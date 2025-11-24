//
//  IRStreamVideoDecoder.swift
//  IRIPCamera-swift
//
//  Created by irons on 2025/3/19.
//

import VideoToolbox
import IRPlayerSwift
import IRPlayerObjc
import IRFFMpeg

class FrameContext {
    let videoDecoder: IRFFVideoDecoderInfo
    let packet: AVPacket

    init(videoDecoder: IRFFVideoDecoderInfo, packet: AVPacket) {
        self.videoDecoder = videoDecoder
        self.packet = packet
    }
}

final class IRStreamVideoDecoder: IRFFVideoInput {

    // MARK: - Properties
    private let startCode3: [UInt8] = [0x00, 0x00, 0x01]
    private let startCode4: [UInt8] = [0x00, 0x00, 0x00, 0x01]

    private var session: VTDecompressionSession?
    private var videoFormatDescr: CMFormatDescription?
    private var status: OSStatus = noErr
    private var decodeStatus: OSStatus = noErr

    // Parameter sets
    private var spsList: [Data] = []
    private var ppsList: [Data] = []
    private var vpsList: [Data] = [] // HEVC

    // Input format tracking
    private enum NALInputFormat {
        case annexB
        case avccOrHvcc
    }
    private var inputFormat: NALInputFormat?
    private var nalLengthSize: Int = 4 // default to 4 if unknown

    // Codec tracking
    private enum CodecKind {
        case h264
        case hevc
    }
    private var codecKind: CodecKind = .h264

    private let didDecompress: VTDecompressionOutputCallback = { (
            decompressionOutputRefCon: UnsafeMutableRawPointer?,
            sourceFrameRefCon: UnsafeMutableRawPointer?,
            status: OSStatus,
            infoFlags: VTDecodeInfoFlags,
            imageBuffer: CVImageBuffer?,
            presentationTimeStamp: CMTime,
            presentationDuration: CMTime
        ) in

        guard let sourceFrameRefCon = sourceFrameRefCon else { return }
        let frameContext = Unmanaged<FrameContext>.fromOpaque(sourceFrameRefCon).takeRetainedValue()

        guard let decompressionOutputRefCon = decompressionOutputRefCon else { return }
        let videoInput = Unmanaged<IRStreamVideoDecoder>.fromOpaque(decompressionOutputRefCon).takeUnretainedValue()

        if status != noErr || imageBuffer == nil {
            print("Error decompressing frame at time: \(presentationTimeStamp.seconds), error: \(status), infoFlags: \(infoFlags)")
            return
        }

        videoInput.decodeStatus = status

        if let frame = videoInput.videoFrameFromImageBuffer(frameContext.videoDecoder, packet: frameContext.packet, imageBuffer: imageBuffer!) {
            videoInput.videoOutput?.send?(videoFrame: frame)
        }
    }

    override func videoDecoder(_ videoDecoder: IRFFVideoDecoderInfo, decodeFrame packet: AVPacket) -> IRFFVideoFrame? {
        videoToolboxDecode(with: FrameContext(videoDecoder: videoDecoder, packet: packet))
        return nil
    }

    func releaseDecoder() {
        if let session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
        videoFormatDescr = nil
        spsList.removeAll()
        ppsList.removeAll()
        vpsList.removeAll()
        inputFormat = nil
        nalLengthSize = 4
    }
}

// MARK: - Decode flow
extension IRStreamVideoDecoder {

    private func videoToolboxDecode(with frameContext: FrameContext) {
        let pCodecCtx: UnsafeMutablePointer<AVCodecContext> = frameContext.videoDecoder.codecContext
        let packet = frameContext.packet

        // 1) Ensure we have a CMFormatDescription and a VT session
        if videoFormatDescr == nil || session == nil {
            setupFormatDescriptionIfNeeded(from: pCodecCtx)
            setupVTSessionIfNeeded()
            if session == nil || videoFormatDescr == nil {
                return
            }
        }

        // 2) Prepare sample buffer in length-prefixed format (VT expects AVCC/HVCC)
        let (avccData, sampleSize) = buildAVCCSample(from: packet)
        guard let avccData, sampleSize > 0 else { return }

        // 3) Create CMBlockBuffer owned by CoreMedia, then copy Data into it (avoid external pointer management and leaks)
        var blockBuffer: CMBlockBuffer?
        status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil, // Let CoreMedia allocate memory
            blockLength: sampleSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: sampleSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        if status != noErr || blockBuffer == nil {
            print("CMBlockBufferCreateWithMemoryBlock error: \(status)")
            return
        }

        // Copy AVCC/HVCC bytes into CMBlockBuffer
        avccData.withUnsafeBytes { rawBuf in
            if let base = rawBuf.bindMemory(to: UInt8.self).baseAddress {
                let rc = CMBlockBufferReplaceDataBytes(
                    with: base,
                    blockBuffer: blockBuffer!,
                    offsetIntoDestination: 0,
                    dataLength: sampleSize
                )
                if rc != noErr {
                    print("CMBlockBufferReplaceDataBytes error: \(rc)")
                }
            }
        }

        // 4) Create CMSampleBuffer with timing info
        var sbRef: CMSampleBuffer?
        var sampleSizeArray = [sampleSize]

        // Build timing
        let tb = frameContext.videoDecoder.timebase
        let ptsSeconds: Double
        if packet.pts != IR_AV_NOPTS_VALUE {
            ptsSeconds = Double(packet.pts) * tb
        } else if packet.dts != IR_AV_NOPTS_VALUE {
            ptsSeconds = Double(packet.dts) * tb
        } else {
            ptsSeconds = 0
        }
        let durSeconds: Double = packet.duration > 0 ? Double(packet.duration) * tb : (frameContext.videoDecoder.fps > 0 ? 1.0 / frameContext.videoDecoder.fps : 0)

        var timing = CMSampleTimingInfo(
            duration: durSeconds > 0 ? CMTimeMakeWithSeconds(durSeconds, preferredTimescale: 600) : CMTime.invalid,
            presentationTimeStamp: CMTimeMakeWithSeconds(ptsSeconds, preferredTimescale: 600),
            decodeTimeStamp: CMTime.invalid
        )

        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: videoFormatDescr!,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizeArray,
            sampleBufferOut: &sbRef
        )
        if status != noErr || sbRef == nil {
            print("CMSampleBufferCreate error: \(status)")
            return
        }

        // 5) Decode
        var flagOut = VTDecodeInfoFlags()
        status = VTDecompressionSessionDecodeFrame(
            session!,
            sampleBuffer: sbRef!,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: Unmanaged.passRetained(frameContext).toOpaque(),
            infoFlagsOut: &flagOut
        )
        if status != noErr {
            print("VTDecompressionSessionDecodeFrame error: \(status)")
        }
    }

    private func setupVTSessionIfNeeded() {
        guard session == nil, let videoFormatDescr else { return }
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: didDecompress,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        let destinationImageBufferAttributes: [String: Any] = [
            kCVPixelBufferOpenGLESCompatibilityKey as String: false,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]

        status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: videoFormatDescr,
            decoderSpecification: nil,
            imageBufferAttributes: destinationImageBufferAttributes as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        if status != noErr {
            print("VTDecompressionSessionCreate error: \(status)")
            session = nil
        }
    }

    private func videoFrameFromImageBuffer(_ videoDecoder: IRFFVideoDecoderInfo, packet: AVPacket, imageBuffer: CVImageBuffer) -> IRFFVideoFrame? {
        let videoFrame = IRFFCVYUVVideoFrame(pixelBuffer: imageBuffer)
        if packet.pts != IR_AV_NOPTS_VALUE {
            videoFrame.position = TimeInterval(packet.pts) * videoDecoder.timebase
        } else {
            videoFrame.position = TimeInterval(packet.dts)
        }

        let frameDuration = packet.duration
        if frameDuration != 0 {
            videoFrame.duration = TimeInterval(frameDuration) * videoDecoder.timebase
        } else {
            videoFrame.duration = 1.0 / videoDecoder.fps
        }
        return videoFrame
    }
}

// MARK: - Format description / extradata parsing
extension IRStreamVideoDecoder {

    private func setupFormatDescriptionIfNeeded(from pCodecCtx: UnsafeMutablePointer<AVCodecContext>) {
        guard videoFormatDescr == nil else { return }

        // Detect codec kind
        if pCodecCtx.pointee.codec_id == AV_CODEC_ID_HEVC {
            codecKind = .hevc
        } else {
            codecKind = .h264
        }

        // Reset parameter sets
        spsList.removeAll()
        ppsList.removeAll()
        vpsList.removeAll()

        guard let extradata = pCodecCtx.pointee.extradata, pCodecCtx.pointee.extradata_size > 0 else {
            // No extradata, assume Annex B stream; nalLengthSize default to 4
            inputFormat = .annexB
            nalLengthSize = 4
            return
        }

        let size = Int(pCodecCtx.pointee.extradata_size)
        let firstByte = extradata[0]

        if codecKind == .h264 {
            if firstByte == 0x01 {
                inputFormat = .avccOrHvcc
                _ = parseAVCC(extradata: extradata, size: size)
            } else if isAnnexBStartCode(extradata, size: size) {
                inputFormat = .annexB
                parseAnnexBParameterSets(extradata: extradata, size: size, isHEVC: false)
                nalLengthSize = 4
            } else {
                if !parseAVCC(extradata: extradata, size: size) {
                    inputFormat = .annexB
                    parseAnnexBParameterSets(extradata: extradata, size: size, isHEVC: false)
                    nalLengthSize = 4
                } else {
                    inputFormat = .avccOrHvcc
                }
            }

            guard let firstSPS = spsList.first, let firstPPS = ppsList.first else {
                print("No SPS/PPS parsed from extradata.")
                return
            }

            if !(nalLengthSize == 1 || nalLengthSize == 2 || nalLengthSize == 4) {
                nalLengthSize = 4
            }

            let headerLen = Int32(nalLengthSize)

            firstSPS.withUnsafeBytes { spsRawBuf in
                firstPPS.withUnsafeBytes { ppsRawBuf in
                    guard
                        let spsBase = spsRawBuf.bindMemory(to: UInt8.self).baseAddress,
                        let ppsBase = ppsRawBuf.bindMemory(to: UInt8.self).baseAddress
                    else { return }

                    let parameterPointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                    let parameterSizes: [Int] = [firstSPS.count, firstPPS.count]

                    parameterPointers.withUnsafeBufferPointer { ptrs in
                        parameterSizes.withUnsafeBufferPointer { sizes in
                            guard let pPtr = ptrs.baseAddress, let sPtr = sizes.baseAddress else { return }
                            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                                allocator: kCFAllocatorDefault,
                                parameterSetCount: 2,
                                parameterSetPointers: pPtr,
                                parameterSetSizes: sPtr,
                                nalUnitHeaderLength: headerLen,
                                formatDescriptionOut: &videoFormatDescr
                            )
                        }
                    }
                }
            }

        } else {
            if firstByte == 0x01 {
                inputFormat = .avccOrHvcc
                _ = parseHVCC(extradata: extradata, size: size)
            } else if isAnnexBStartCode(extradata, size: size) {
                inputFormat = .annexB
                parseAnnexBParameterSets(extradata: extradata, size: size, isHEVC: true)
                nalLengthSize = 4
            } else {
                if !parseHVCC(extradata: extradata, size: size) {
                    inputFormat = .annexB
                    parseAnnexBParameterSets(extradata: extradata, size: size, isHEVC: true)
                    nalLengthSize = 4
                } else {
                    inputFormat = .avccOrHvcc
                }
            }

            guard let firstVPS = vpsList.first, let firstSPS = spsList.first, let firstPPS = ppsList.first else {
                print("No VPS/SPS/PPS parsed from extradata.")
                return
            }

            if !(nalLengthSize == 1 || nalLengthSize == 2 || nalLengthSize == 4) {
                nalLengthSize = 4
            }

            let headerLen = Int32(nalLengthSize)

            firstVPS.withUnsafeBytes { vpsRawBuf in
                firstSPS.withUnsafeBytes { spsRawBuf in
                    firstPPS.withUnsafeBytes { ppsRawBuf in
                        guard
                            let vpsBase = vpsRawBuf.bindMemory(to: UInt8.self).baseAddress,
                            let spsBase = spsRawBuf.bindMemory(to: UInt8.self).baseAddress,
                            let ppsBase = ppsRawBuf.bindMemory(to: UInt8.self).baseAddress
                        else { return }

                        let parameterPointers: [UnsafePointer<UInt8>] = [vpsBase, spsBase, ppsBase]
                        let parameterSizes: [Int] = [firstVPS.count, firstSPS.count, firstPPS.count]

                        parameterPointers.withUnsafeBufferPointer { ptrs in
                            parameterSizes.withUnsafeBufferPointer { sizes in
                                guard let pPtr = ptrs.baseAddress, let sPtr = sizes.baseAddress else { return }
                                status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                                    allocator: kCFAllocatorDefault,
                                    parameterSetCount: 3,
                                    parameterSetPointers: pPtr,
                                    parameterSetSizes: sPtr,
                                    nalUnitHeaderLength: headerLen,
                                    extensions: nil,
                                    formatDescriptionOut: &videoFormatDescr
                                )
                            }
                        }
                    }
                }
            }
        }

        if status != noErr {
            print("CMVideoFormatDescriptionCreate error: \(status)")
            videoFormatDescr = nil
        }
    }

    @discardableResult
    private func parseAVCC(extradata: UnsafeMutablePointer<UInt8>, size: Int) -> Bool {
        guard size >= 7, extradata[0] == 1 else { return false }
        let lengthSizeMinusOne = Int(extradata[4] & 0x03)
        nalLengthSize = lengthSizeMinusOne + 1
        var offset = 5

        let numOfSPS = Int(extradata[offset] & 0x1F)
        offset += 1

        spsList.removeAll()
        ppsList.removeAll()

        for _ in 0..<numOfSPS {
            if offset + 2 > size { return false }
            let spsLength = Int(extradata[offset]) << 8 | Int(extradata[offset + 1])
            offset += 2
            if offset + spsLength > size { return false }
            let sps = Data(bytes: extradata.advanced(by: offset), count: spsLength)
            spsList.append(sps)
            offset += spsLength
        }

        if offset + 1 > size { return false }
        let numOfPPS = Int(extradata[offset])
        offset += 1

        for _ in 0..<numOfPPS {
            if offset + 2 > size { return false }
            let ppsLength = Int(extradata[offset]) << 8 | Int(extradata[offset + 1])
            offset += 2
            if offset + ppsLength > size { return false }
            let pps = Data(bytes: extradata.advanced(by: offset), count: ppsLength)
            ppsList.append(pps)
            offset += ppsLength
        }

        return !spsList.isEmpty && !ppsList.isEmpty
    }

    @discardableResult
    private func parseHVCC(extradata: UnsafeMutablePointer<UInt8>, size: Int) -> Bool {
        guard size >= 23, extradata[0] == 1 else { return false }

        let lengthSizeMinusOne = Int(extradata[21] & 0x03)
        nalLengthSize = lengthSizeMinusOne + 1

        var offset = 22
        if offset >= size { return false }

        let numOfArrays = Int(extradata[offset])
        offset += 1

        spsList.removeAll()
        ppsList.removeAll()
        vpsList.removeAll()

        for _ in 0..<numOfArrays {
            if offset + 3 > size { return false }
            let arrayCompletenessAndType = extradata[offset]
            offset += 1
            let nalUnitType = Int(arrayCompletenessAndType & 0x3F)
            let numNalus = Int(extradata[offset]) << 8 | Int(extradata[offset + 1])
            offset += 2

            for _ in 0..<numNalus {
                if offset + 2 > size { return false }
                let nalUnitLength = Int(extradata[offset]) << 8 | Int(extradata[offset + 1])
                offset += 2
                if offset + nalUnitLength > size { return false }
                let data = Data(bytes: extradata.advanced(by: offset), count: nalUnitLength)
                switch nalUnitType {
                case 32: vpsList.append(data)
                case 33: spsList.append(data)
                case 34: ppsList.append(data)
                default: break
                }
                offset += nalUnitLength
            }
        }

        return !vpsList.isEmpty && !spsList.isEmpty && !ppsList.isEmpty
    }

    private func parseAnnexBParameterSets(extradata: UnsafeMutablePointer<UInt8>, size: Int, isHEVC: Bool) {
        spsList.removeAll()
        ppsList.removeAll()
        vpsList.removeAll()

        var index = 0
        while let (range, naluType) = nextAnnexBNAL(in: extradata, size: size, start: index, isHEVC: isHEVC) {
            if isHEVC {
                switch naluType {
                case 32:
                    let vps = Data(bytes: extradata.advanced(by: range.lowerBound), count: range.count)
                    vpsList.append(vps)
                case 33:
                    let sps = Data(bytes: extradata.advanced(by: range.lowerBound), count: range.count)
                    spsList.append(sps)
                case 34:
                    let pps = Data(bytes: extradata.advanced(by: range.lowerBound), count: range.count)
                    ppsList.append(pps)
                default:
                    break
                }
            } else {
                if naluType == 7 {
                    let sps = Data(bytes: extradata.advanced(by: range.lowerBound), count: range.count)
                    spsList.append(sps)
                } else if naluType == 8 {
                    let pps = Data(bytes: extradata.advanced(by: range.lowerBound), count: range.count)
                    ppsList.append(pps)
                }
            }
            index = range.upperBound
        }
    }

    private func isAnnexBStartCode(_ ptr: UnsafeMutablePointer<UInt8>, size: Int) -> Bool {
        if size >= 4 && memcmp(ptr, startCode4, 4) == 0 { return true }
        if size >= 3 && memcmp(ptr, startCode3, 3) == 0 { return true }
        return false
    }
}

// MARK: - Packet to AVCC/HVCC conversion
extension IRStreamVideoDecoder {

    // Return Data to avoid externally allocated pointer leaks
    private func buildAVCCSample(from packet: AVPacket) -> (Data?, Int) {
        guard let dataPtr = packet.data, packet.size > 0 else { return (nil, 0) }
        let length = Int(packet.size)

        let looksLikeAnnexB = looksLikeAnnexBBuffer(dataPtr, length: length)
        if looksLikeAnnexB {
            let converted = convertAnnexBToAVCC(dataPtr, length: length, nalLengthSize: nalLengthSize)
            return (converted, converted.count)
        } else {
            // Wrap as Data directly; it will be copied into CMBlockBuffer later
            let data = Data(bytes: dataPtr, count: length)
            return (data, length)
        }
    }

    private func looksLikeAnnexBBuffer(_ ptr: UnsafeMutablePointer<UInt8>, length: Int) -> Bool {
        if length >= 4 && memcmp(ptr, startCode4, 4) == 0 { return true }
        if length >= 3 && memcmp(ptr, startCode3, 3) == 0 { return true }
        var i = 0
        while i + 4 <= length {
            if memcmp(ptr.advanced(by: i), startCode4, 4) == 0 { return true }
            if i + 3 <= length && memcmp(ptr.advanced(by: i), startCode3, 3) == 0 { return true }
            i += 1
        }
        return false
    }

    // Convert to Data (length-prefixed)
    private func convertAnnexBToAVCC(_ ptr: UnsafeMutablePointer<UInt8>, length: Int, nalLengthSize: Int) -> Data {
        var nalRanges: [(start: Int, end: Int)] = []
        var i = 0
        func matchStartCode(_ p: UnsafeMutablePointer<UInt8>, _ len: Int) -> Int? {
            if len >= 4 && memcmp(p, startCode4, 4) == 0 { return 4 }
            if len >= 3 && memcmp(p, startCode3, 3) == 0 { return 3 }
            return nil
        }

        while i < length {
            guard let scLen = matchStartCode(ptr.advanced(by: i), length - i) else {
                i += 1
                continue
            }
            let naluStart = i + scLen
            var j = naluStart
            var nextStart: Int?
            while j < length {
                if let _ = matchStartCode(ptr.advanced(by: j), length - j) {
                    nextStart = j
                    break
                }
                j += 1
            }
            let naluEnd = nextStart ?? length
            if naluEnd > naluStart {
                nalRanges.append((start: naluStart, end: naluEnd))
            }
            i = naluEnd
        }

        if nalRanges.isEmpty { return Data() }

        var out = Data()
        out.reserveCapacity(nalRanges.reduce(0) { $0 + nalLengthSize + ($1.end - $1.start) })

        for r in nalRanges {
            let nalSize = r.end - r.start
            // Write length (big-endian)
            for b in stride(from: (nalLengthSize - 1), through: 0, by: -1) {
                let v = UInt8((nalSize >> (b * 8)) & 0xFF)
                out.append(v)
            }
            // Write NALU payload
            out.append(UnsafeBufferPointer(start: ptr.advanced(by: r.start), count: nalSize))
        }
        return out
    }

    private func nextAnnexBNAL(in ptr: UnsafeMutablePointer<UInt8>, size: Int, start: Int, isHEVC: Bool) -> ((Range<Int>, Int))? {
        var i = start
        func matchStartCode(_ p: UnsafeMutablePointer<UInt8>, _ len: Int) -> Int? {
            if len >= 4 && memcmp(p, startCode4, 4) == 0 { return 4 }
            if len >= 3 && memcmp(p, startCode3, 3) == 0 { return 3 }
            return nil
        }

        var scLen1: Int?
        while i < size {
            if let sc = matchStartCode(ptr.advanced(by: i), size - i) {
                scLen1 = sc
                break
            }
            i += 1
        }
        guard let sc1 = scLen1 else { return nil }
        let naluStart = i + sc1

        var j = naluStart
        var nextStartIdx: Int?
        while j < size {
            if let _ = matchStartCode(ptr.advanced(by: j), size - j) {
                nextStartIdx = j
                break
            }
            j += 1
        }
        let naluEnd = nextStartIdx ?? size
        guard naluEnd > naluStart else { return nil }

        let firstByte = ptr[naluStart]
        let naluType: Int
        if isHEVC {
            naluType = Int((firstByte >> 1) & 0x3F)
        } else {
            naluType = Int(firstByte & 0x1F)
        }
        return (naluStart..<naluEnd, naluType)
    }
}

