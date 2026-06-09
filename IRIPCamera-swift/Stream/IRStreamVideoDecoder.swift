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
        let bytes = [UInt8](UnsafeBufferPointer(start: extradata, count: size))

        if codecKind == .h264 {
            if firstByte == 0x01 {
                inputFormat = .avccOrHvcc
                applyH264(NALUParser.parseAVCC(bytes))
            } else if NALUParser.isAnnexBStartCode(bytes) {
                inputFormat = .annexB
                applyH264(NALUParser.parseAnnexBParameterSets(bytes, isHEVC: false))
                nalLengthSize = 4
            } else if let sets = NALUParser.parseAVCC(bytes) {
                inputFormat = .avccOrHvcc
                applyH264(sets)
            } else {
                inputFormat = .annexB
                applyH264(NALUParser.parseAnnexBParameterSets(bytes, isHEVC: false))
                nalLengthSize = 4
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
                applyHEVC(NALUParser.parseHVCC(bytes))
            } else if NALUParser.isAnnexBStartCode(bytes) {
                inputFormat = .annexB
                applyHEVC(NALUParser.parseAnnexBParameterSets(bytes, isHEVC: true))
                nalLengthSize = 4
            } else if let sets = NALUParser.parseHVCC(bytes) {
                inputFormat = .avccOrHvcc
                applyHEVC(sets)
            } else {
                inputFormat = .annexB
                applyHEVC(NALUParser.parseAnnexBParameterSets(bytes, isHEVC: true))
                nalLengthSize = 4
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

    /// Applies parsed H.264 parameter sets to instance state.
    private func applyH264(_ sets: NALUParser.ParameterSets?) {
        guard let sets else { return }
        spsList = sets.sps
        ppsList = sets.pps
        nalLengthSize = sets.nalLengthSize
    }

    /// Applies parsed HEVC parameter sets to instance state.
    private func applyHEVC(_ sets: NALUParser.ParameterSets?) {
        guard let sets else { return }
        vpsList = sets.vps
        spsList = sets.sps
        ppsList = sets.pps
        nalLengthSize = sets.nalLengthSize
    }
}

// MARK: - Packet to AVCC/HVCC conversion
extension IRStreamVideoDecoder {

    // Return Data to avoid externally allocated pointer leaks
    private func buildAVCCSample(from packet: AVPacket) -> (Data?, Int) {
        guard let dataPtr = packet.data, packet.size > 0 else { return (nil, 0) }
        let length = Int(packet.size)
        let bytes = [UInt8](UnsafeBufferPointer(start: dataPtr, count: length))

        if NALUParser.looksLikeAnnexB(bytes) {
            let converted = NALUParser.convertAnnexBToAVCC(bytes, nalLengthSize: nalLengthSize)
            return (converted, converted.count)
        } else {
            // Wrap as Data directly; it will be copied into CMBlockBuffer later
            return (Data(bytes), length)
        }
    }
}

