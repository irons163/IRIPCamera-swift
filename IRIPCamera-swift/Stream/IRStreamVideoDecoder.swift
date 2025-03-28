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

class IRStreamVideoDecoder: IRFFVideoInput {

    // MARK: - Properties
    let startCode3 = Data([0x00, 0x00, 0x01])
    let startCode4 = Data([0x00, 0x00, 0x00, 0x01])

    private var session: VTDecompressionSession?
    private var videoFormatDescr: CMFormatDescription?
    private var status: OSStatus = noErr
    private var decodeStatus: OSStatus = noErr
    private var decodeOutput: CVImageBuffer?
    private var spsData: Data?
    private var ppsData: Data?

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
        videoInput.decodeOutput = imageBuffer

        videoInput.videoOutput?.send?(videoFrame: videoInput.videoFrameFromVideoToolBox(frameContext.videoDecoder, packet: frameContext.packet)!)
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
    }
}

extension IRStreamVideoDecoder {

    private func videoToolboxDecode(with frameContext: FrameContext) {
        let pCodecCtx: UnsafeMutablePointer<AVCodecContext> = frameContext.videoDecoder.codecContext
        let packet = frameContext.packet
        setupSPSAndPPS(with: pCodecCtx)

        // Create VTDecompressionSession
        if session == nil {
            var callback = VTDecompressionOutputCallbackRecord(
                decompressionOutputCallback: didDecompress,
                decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
            )

            let destinationImageBufferAttributes: [String: Any] = [
                kCVPixelBufferOpenGLESCompatibilityKey as String: false,
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]

            status = VTDecompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                formatDescription: videoFormatDescr!,
                decoderSpecification: nil,
                imageBufferAttributes: destinationImageBufferAttributes as CFDictionary,
                outputCallback: &callback,
                decompressionSessionOut: &session
            )
        }

        // Decode NAL unit
        let startCodeIndex = findFirstNALUType1or5StartCodeIndex(in: packet.data, length: Int(packet.size)) ?? 0

        var naluType: UInt8 = 0
        let startCodeEndedIndex = (startCodeIndex...startCodeIndex+4).first(where: { packet.data[$0] == 0x01 }) ?? 0
        naluType = (packet.data[startCodeEndedIndex + 1] & 0x1F)

        // Find the offset, or where the SPS and PPS NALUs end and the IDR frame NALU begins
        var newData: UnsafeMutablePointer<UInt8>!
        var blockLength: Int = 0

        let offset = startCodeIndex
        blockLength = Int(packet.size) - offset
        newData = packet.data.advanced(by: offset)

        if naluType == 1 || naluType == 5 {
            // Create a CMBlockBuffer
            var videoBlock: CMBlockBuffer?
            status = CMBlockBufferCreateWithMemoryBlock(
                allocator: nil,
                memoryBlock: newData,
                blockLength: blockLength,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: blockLength,
                flags: 0,
                blockBufferOut: &videoBlock
            )

            // Replace the start code header(4-byte length) on NALU with its size.
            // AVCC format requires that you do this.
            let sizeWithoutStartCodeHeader = blockLength - (startCodeEndedIndex - startCodeIndex + 1)

            // Convert the size into a 4-byte length code
            let sourceBytes: [UInt8] = [
                UInt8((sizeWithoutStartCodeHeader >> 24) & 0xFF),
                UInt8((sizeWithoutStartCodeHeader >> 16) & 0xFF),
                UInt8((sizeWithoutStartCodeHeader >> 8) & 0xFF),
                UInt8(sizeWithoutStartCodeHeader & 0xFF)
            ]

            // Replace the first 4 bytes(start code header) in the `CMBlockBuffer` with `sourceBytes`
            // TODO: If start code header is 3 bytes, here might be wrong?
            status = CMBlockBufferReplaceDataBytes(
                with: sourceBytes,      // The source bytes to replace with
                blockBuffer: videoBlock!, // The block buffer to modify
                offsetIntoDestination: 0, // Start at the beginning
                dataLength: 4  // Replace 4 bytes
            )

            // Create a CMSampleBuffer
            var sbRef: CMSampleBuffer?
            status = CMSampleBufferCreate(
                allocator: kCFAllocatorDefault,
                dataBuffer: videoBlock,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: videoFormatDescr!,
                sampleCount: 1,
                sampleTimingEntryCount: 0,
                sampleTimingArray: nil,
                sampleSizeEntryCount: 1,
                sampleSizeArray: &blockLength,
                sampleBufferOut: &sbRef
            )

            // Decode the frame
            var flagOut = VTDecodeInfoFlags()
            status = VTDecompressionSessionDecodeFrame(
                session!,
                sampleBuffer: sbRef!,
                flags: [._EnableAsynchronousDecompression],
                frameRefcon: Unmanaged.passRetained(frameContext).toOpaque(),
                infoFlagsOut: &flagOut
            )
            print(status)
        }
    }

    private func videoFrameFromVideoToolBox(_ videoDecoder: IRFFVideoDecoderInfo, packet: AVPacket) -> IRFFVideoFrame? {
        guard let imageBuffer = decodeOutput else {
            return nil
        }

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

extension IRStreamVideoDecoder {

    private func setupSPSAndPPS(with pCodecCtx: UnsafeMutablePointer<AVCodecContext>) {
        guard let data = pCodecCtx.pointee.extradata,
              spsData == nil || ppsData == nil else { return }

        let size = Int(pCodecCtx.pointee.extradata_size)
        var tmp3 = ""

        for i in 0..<size {
            let str = String(format: " %.2X", data[Int(i)])
            tmp3 += str
        }

        var startCodeSPSIndex = 0
        var startCodePPSIndex = 0

        for i in 3..<size {
            if data[Int(i)] == 0x01, data[Int(i)-1] == 0x00, data[Int(i)-2] == 0x00, data[Int(i)-3] == 0x00 {
                if startCodeSPSIndex == 0 {
                    startCodeSPSIndex = i
                } else {
                    startCodePPSIndex = i
                    break
                }
            }
        }

        let spsLength = startCodePPSIndex - startCodeSPSIndex - 4
        let ppsLength = size - (startCodePPSIndex + 1)

        let naluTypeSPS = Int(data[startCodeSPSIndex + 1] & 0x1F)
        if naluTypeSPS == 7 {
            spsData = Data(bytes: &data[startCodeSPSIndex + 1], count: spsLength)
        }

        let naluTypePPS = Int(data[startCodePPSIndex + 1] & 0x1F)
        if naluTypePPS == 8 {
            ppsData = Data(bytes: &data[startCodePPSIndex + 1], count: ppsLength)
        }

        guard let sps = spsData, let pps = ppsData else {
            print("Failed to get data for SPS or PPS")
            return
        }

        sps.withUnsafeBytes { spsPointer in
            pps.withUnsafeBytes { ppsPointer in

                guard let spsBaseAddress = spsPointer.bindMemory(to: UInt8.self).baseAddress,
                      let ppsBaseAddress = ppsPointer.bindMemory(to: UInt8.self).baseAddress else {
                    print("Failed to get base address for SPS or PPS")
                    return
                }

                let parameterSetPointers: [UnsafePointer<UInt8>] = [
                    spsBaseAddress,
                    ppsBaseAddress
                ]
                let parameterSetSizes: [Int] = [sps.count, pps.count]

                status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: parameterSetPointers,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &videoFormatDescr
                )
            }
        }
    }
}

extension IRStreamVideoDecoder {

    private func findFirstNALUType1or5StartCodeIndex(in pointer: UnsafeMutablePointer<UInt8>?, length: Int) -> Int? {
        guard let pointer = pointer else {
            print("Pointer is nil")
            return nil
        }

        let startCode3: [UInt8] = [0x00, 0x00, 0x01]
        let startCode4: [UInt8] = [0x00, 0x00, 0x00, 0x01]

        var currentIndex = 0

        while currentIndex < length {
            // check startCode4
            if currentIndex + 4 <= length,
               memcmp(pointer.advanced(by: currentIndex), startCode4, 4) == 0 {
                let nalUnitType = pointer[currentIndex + 4] & 0x1F // get nal_unit_type
                if nalUnitType == 1 || nalUnitType == 5 {
                    return currentIndex
                }
                currentIndex += 5 // skip the start code & NALU Header
                continue
            }

            // check startCode3
            if currentIndex + 3 <= length,
               memcmp(pointer.advanced(by: currentIndex), startCode3, 3) == 0 {
                let nalUnitType = pointer[currentIndex + 3] & 0x1F // get nal_unit_type
                if nalUnitType == 1 || nalUnitType == 5 {
                    return currentIndex
                }
                currentIndex += 4 // skip the start code & NALU Header
                continue
            }

            // not found, keep going
            currentIndex += 1
        }

        return nil
    }
}
