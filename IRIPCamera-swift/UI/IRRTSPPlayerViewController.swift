//
//  IRRTSPPlayerViewController.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import UIKit
import IRPlayerSwift
import IRPlayerObjc
import IRFFMpeg
import VideoToolbox

class FrameContext {
    let videoDecoder: IRFFVideoDecoderInfo
    let packet: AVPacket

    init(videoDecoder: IRFFVideoDecoderInfo, packet: AVPacket) {
        self.videoDecoder = videoDecoder
        self.packet = packet
    }
}

class MyIRFFVideoInput: IRFFVideoInput {

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

    override func videoDecoder(_ videoDecoder: IRFFVideoDecoderInfo, decodeFrame packet: AVPacket) -> IRFFVideoFrame? {

        iOS8HWDecode(with: FrameContext(videoDecoder: videoDecoder, packet: packet))

        return nil
    }

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

    func iOS8HWDecode(with frameContext: FrameContext) {
        let pCodecCtx: UnsafeMutablePointer<AVCodecContext> = frameContext.videoDecoder.codecContext
        let packet = frameContext.packet
        setupSPSAndPPS(with: pCodecCtx)

        // 3. Create VTDecompressionSession
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
        var startCodeIndex = findFirstNALUType1or5StartCodeIndex(in: packet.data, length: Int(packet.size)) ?? 0

        var naluType: UInt8 = 0
        var startCodeEndedIndex = (startCodeIndex...startCodeIndex+4).first(where: { packet.data[$0] == 0x01 }) ?? 0
        naluType = (packet.data[startCodeEndedIndex + 1] & 0x1F)

        // find the offset, or where the SPS and PPS NALUs end and the IDR frame NALU begins
        var newData: UnsafeMutablePointer<UInt8>!
        var blockLength: Int = 0

        let offset = startCodeIndex
        blockLength = Int(packet.size) - offset
//        newData = UnsafeMutablePointer<UInt8>.allocate(capacity: blockLength)
//        memcpy(newData, &packet.data[offset], blockLength)
        newData = packet.data.advanced(by: offset)

        if naluType == 1 || naluType == 5 {
            // replace the start code header on this NALU with its size.
            // AVCC format requires that you do this.
            // htonl converts the unsigned int from host to network byte order
//            var dataLength32 = UInt32(blockLength - 4).bigEndian
//            memcpy(newData, &dataLength32, MemoryLayout<UInt32>.size)
//            var data = Data()
//            withUnsafeBytes(of: &dataLength32) { bytes in
//                data.append(contentsOf: bytes)
//            }

            // 4. Create a CMBlockBuffer
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

            // 5. Replace separator code with 4-byte length
            // Assuming `packet` is a structure or object that has a `size` property
            let removeHeaderSize = blockLength - (startCodeEndedIndex - startCodeIndex + 1)

            // Convert the size into a 4-byte length code
            let sourceBytes: [UInt8] = [
                UInt8((removeHeaderSize >> 24) & 0xFF),
                UInt8((removeHeaderSize >> 16) & 0xFF),
                UInt8((removeHeaderSize >> 8) & 0xFF),
                UInt8(removeHeaderSize & 0xFF)
            ]

            // Replace the first 4 bytes in the `CMBlockBuffer` with `sourceBytes`
            status = CMBlockBufferReplaceDataBytes(
                with: sourceBytes,      // The source bytes to replace with
                blockBuffer: videoBlock!, // The block buffer to modify
                offsetIntoDestination: 0, // Start at the beginning
                dataLength: 4  // Replace 4 bytes
            )

            // 6. Create a CMSampleBuffer
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

            // 7. Decode the frame
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

    func findFirstNALUType1or5StartCodeIndex(in pointer: UnsafeMutablePointer<UInt8>?, length: Int) -> Int? {
        guard let pointer = pointer else {
            print("Pointer is nil")
            return nil
        }

        let startCode3: [UInt8] = [0x00, 0x00, 0x01]       // 3 字节起始码
        let startCode4: [UInt8] = [0x00, 0x00, 0x00, 0x01] // 4 字节起始码

        var currentIndex = 0

        while currentIndex < length {
            // 检查 4 字节起始码
            if currentIndex + 4 <= length,
               memcmp(pointer.advanced(by: currentIndex), startCode4, 4) == 0 {
                let nalUnitType = pointer[currentIndex + 4] & 0x1F // 获取 nal_unit_type
                if nalUnitType == 1 || nalUnitType == 5 {
                    return currentIndex // 返回找到的起始码索引
                }
                currentIndex += 5 // 跳过起始码和 NALU Header
                continue
            }

            // 检查 3 字节起始码
            if currentIndex + 3 <= length,
               memcmp(pointer.advanced(by: currentIndex), startCode3, 3) == 0 {
                let nalUnitType = pointer[currentIndex + 3] & 0x1F // 获取 nal_unit_type
                if nalUnitType == 1 || nalUnitType == 5 {
                    return currentIndex // 返回找到的起始码索引
                }
                currentIndex += 4 // 跳过起始码和 NALU Header
                continue
            }

            // 如果既不是 4 字节也不是 3 字节起始码，继续往下
            currentIndex += 1
        }

        return nil // 如果没有找到符合条件的 NALU，返回 nil
    }

    func releaseDecoder() {
        if let session = session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }

        if let videoFormatDescr = videoFormatDescr {
            self.videoFormatDescr = nil
        }
    }

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
        let videoInput = Unmanaged<MyIRFFVideoInput>.fromOpaque(decompressionOutputRefCon).takeUnretainedValue()

        if status != noErr || imageBuffer == nil {
            print("Error decompressing frame at time: \(presentationTimeStamp.seconds), error: \(status), infoFlags: \(infoFlags)")
            return
        }

        videoInput.decodeStatus = status
        videoInput.decodeOutput = imageBuffer

        videoInput.videoOutput?.send?(videoFrame: videoInput.videoFrameFromVideoToolBox(frameContext.videoDecoder, packet: frameContext.packet)!)
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

class IRRTSPPlayerViewController: UIViewController, IRRTSPSettingsViewControllerDelegate {

    // MARK: - Properties
    var intDisplayMode: Int = 1
    var intCurrentCh: Int = 0
    var aryVideoView: [UIView] = []
    var aryDevices: [IRStreamConnectionRequest] = []

    @IBOutlet weak var firstViewConstraint: NSLayoutConstraint!
    @IBOutlet weak var secondViewConstraint: NSLayoutConstraint!
    @IBOutlet weak var thirdViewConstraint: NSLayoutConstraint!
    @IBOutlet weak var fourthViewConstraint: NSLayoutConstraint!
    @IBOutlet weak var firstView: UIView!
    @IBOutlet weak var secondView: UIView!
    @IBOutlet weak var thirdView: UIView!
    @IBOutlet weak var fourthView: UIView!
//    @IBOutlet weak var LoadingActivity: UIActivityIndicatorView!
    @IBOutlet weak var infoLabel: UILabel!

    var player: IRPlayerImp!
    var player2: IRPlayerImp!
    var player3: IRPlayerImp!
    var player4: IRPlayerImp!

    var firstVideoView: IRRTSPMediaView!
    var secondVideoView: IRRTSPMediaView!
    var thirdVideoView: IRRTSPMediaView!
    var fourthVideoView: IRRTSPMediaView!

    // MARK: - Lifecycle Methods
    override func viewDidLoad() {
        super.viewDidLoad()

        aryDevices = IRStreamConnectionRequestFactory.createStreamConnectionRequest()

        setupPlayers()
        initVideoView()
        startStreamConnection(byDeviceIndex: 0)
    }

    deinit {
        stopAllStreams(fromGoBack: true)
    }

    // MARK: - Player Setup
    func setupPlayers() {
        player = IRPlayerImp.player()
        configure(player: player)

        player2 = IRPlayerImp.player()
        configure(player: player2)

        player3 = IRPlayerImp.player()
        configure(player: player3)

        player4 = IRPlayerImp.player()
        configure(player: player4)
    }

    func configure(player: IRPlayerImp) {
        player.playableBufferInterval = 0
        player.registerPlayerNotification(target: self,
                                          stateAction: #selector(stateAction(_:)),
                                          progressAction: #selector(progressAction(_:)),
                                          playableAction: #selector(playableAction(_:)),
                                          errorAction: #selector(errorAction(_:)))
        player.viewTapAction = { _, _ in
            print("Player display view did click!")
        }
        player.decoder = IRPlayerDecoder.FFmpegDecoder()
    }

    // MARK: - Video Views
    func initVideoView() {
        addVideoViewToBlock()

        aryVideoView = [firstView, secondView, thirdView, fourthView]

        setBlockShowOrHide(fromViewDidLoad: false)
        resizeViewBlock()
    }

    func addVideoViewToBlock() {
        for i in 0..<4 {
            addVideoViewToBlock(byCh: i)
        }
    }

    func addVideoViewToBlock(byCh ch: Int) {
        let videoView = IRRTSPMediaView()
        videoView.doubleTapEnable = true

        switch ch {
        case 0:
            firstVideoView = videoView
            firstVideoView.player = player
            firstView.addSubview(firstVideoView)
            addConstraints(to: firstVideoView, in: firstView)
        case 1:
            secondVideoView = videoView
            secondVideoView.player = player2
            secondView.addSubview(secondVideoView)
            addConstraints(to: secondVideoView, in: secondView)
        case 2:
            thirdVideoView = videoView
            thirdVideoView.player = player3
            thirdView.addSubview(thirdVideoView)
            addConstraints(to: thirdVideoView, in: thirdView)
        case 3:
            fourthVideoView = videoView
            fourthVideoView.player = player4
            fourthView.addSubview(fourthVideoView)
            addConstraints(to: fourthVideoView, in: fourthView)
        default:
            break
        }
    }

    func addConstraints(to videoView: IRRTSPMediaView, in containerView: UIView) {
        videoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: containerView.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
    }

    func setBlockShowOrHide(fromViewDidLoad: Bool) {
        for (index, view) in aryVideoView.enumerated() {
            view.isHidden = (intDisplayMode == 1 && index != intCurrentCh)
        }
    }

    func resizeViewBlock() {
        if intDisplayMode == 1 {
            switch intCurrentCh {
            case 0: firstViewConstraint = firstViewConstraint.updateMultiplier(1.0)
            case 1: secondViewConstraint = secondViewConstraint.updateMultiplier(1.0)
            case 2: thirdViewConstraint = thirdViewConstraint.updateMultiplier(1.0)
            case 3: fourthViewConstraint = fourthViewConstraint.updateMultiplier(1.0)
            default: break
            }
        } else {
            firstViewConstraint = firstViewConstraint.updateMultiplier(0.5)
            secondViewConstraint = secondViewConstraint.updateMultiplier(0.5)
            thirdViewConstraint = thirdViewConstraint.updateMultiplier(0.5)
            fourthViewConstraint = fourthViewConstraint.updateMultiplier(0.5)
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let vc = segue.destination as? IRRTSPSettingsViewController
        vc?.delegate = self
    }

    // MARK: - Stream Control
    func startStreamConnection(byDeviceIndex index: Int) {
        guard index < aryVideoView.count, index < aryDevices.count else { return }
        let tmpView = aryVideoView[index]
        if let tmpVideo = tmpView.subviews.first as? IRRTSPMediaView {
            tmpVideo.startStreamConnection(with: aryDevices[index])
        }
    }

    func stopAllStreams(fromGoBack: Bool) {
        for index in 0..<4 {
            stopStream(byChannel: index, fromGoBack: fromGoBack)
        }
    }

    func stopStream(byChannel channel: Int, fromGoBack: Bool) {
        guard channel < aryVideoView.count else { return }
        let tmpView = aryVideoView[channel]
        if let tmpVideo = tmpView.subviews.first as? IRRTSPMediaView {
            tmpVideo.stopStreaming(stopForever: true)
            tmpVideo.removeFromSuperview()
        }
    }

    // MARK: - Notification Handlers
    @objc func stateAction(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        let state = IRState.state(fromUserInfo: userInfo)
        switch state.current {
        case .none: infoLabel.text = "None"
        case .buffering: infoLabel.text = "Buffering..."
        case .readyToPlay:
            infoLabel.text = "Prepare"
            player.play()
        case .playing: infoLabel.text = "Playing"
        case .suspend: infoLabel.text = "Suspend"
        case .finished: infoLabel.text = "Finished"
        case .failed: infoLabel.text = "Error"
        }
    }

    @objc func progressAction(_ notification: Notification) {}

    @objc func playableAction(_ notification: Notification) {
//        guard let playable = IRPlayable.playable(fromUserInfo: notification.userInfo) else { return }
//        print("Playable time: \(playable.current)")
    }

    @objc func errorAction(_ notification: Notification) {
//        guard let error = IRError.error(fromUserInfo: notification.userInfo) else { return }
//        print("Player did error: \(error.error ?? "Unknown error")")
    }

    // MARK: - Utility
    func timeString(fromSeconds seconds: CGFloat) -> String {
        return String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    // MARK: - IRRTSPSettingsViewControllerDelegate
    func updatedSettings(_ device: DeviceClass) {
        aryDevices = IRStreamConnectionRequestFactory.createStreamConnectionRequest()
        startStreamConnection(byDeviceIndex: 0)
    }
}

private extension NSLayoutConstraint {

    func updateMultiplier(_ multiplier: CGFloat) -> NSLayoutConstraint {
        // Deactivate the current constraint
        NSLayoutConstraint.deactivate([self])

        // Create a new constraint with the updated multiplier
        let newConstraint = NSLayoutConstraint(
            item: firstItem!,
            attribute: firstAttribute,
            relatedBy: relation,
            toItem: secondItem,
            attribute: secondAttribute,
            multiplier: multiplier,
            constant: constant
        )

        // Copy properties from the old constraint to the new one
        newConstraint.priority = priority
        newConstraint.shouldBeArchived = shouldBeArchived
        newConstraint.identifier = identifier
        newConstraint.isActive = true

        // Activate the new constraint
        NSLayoutConstraint.activate([newConstraint])

        return newConstraint
    }
}
