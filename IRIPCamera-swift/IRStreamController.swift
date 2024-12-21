//
//  IRStreamController.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import Foundation
import UIKit
import IRPlayerSwift

enum IRStreamControllerStatus: Int {
    case none
    case preparingToPlay
    case readyToPlay
    case playToEnd
    case failed
}

protocol IRStreamControllerDelegate: AnyObject {
    func connectResult(_ videoView: Any, connection: Bool, micSupport: Bool, speakerSupport: Bool)
    func recordingFailed(withErrorCode code: Int, desc: String)
    func finishRecording(showLoadingIcon: Bool)
    func showErrorMessage(_ msg: String)
    func streamControllerStatusChanged(_ status: IRStreamControllerStatus)
    #if DEV
    func checkIsAutoLiveOn() -> Bool
    #endif
    func updatedVideoModes()
}

extension IRStreamControllerDelegate {
    func recordingFailed(withErrorCode code: Int, desc: String) { }
    func finishRecording(showLoadingIcon: Bool) { }
    func updatedVideoModes() { }
}

class IRStreamController: NSObject {

    // MARK: - Properties
    private var httpRequest: StaticHttpRequest?
    private var channel: Int = 0
    private var aryRtspURL: [String] = []
    private var aryStreamInfo: [Any]?
    private var aryIPRatio: [Int] = []
    private var availableStreams: Int = 0
    private var deviceStreamMode: Int = 0
    private var reconnectTimes: Int = 0
    private var stopStreamingFlag: Bool = false
    private var useTCP: Bool = false
    private var selectedFlag: Bool = false
    private var stopForeverFlag: Bool = false
    private var showAuthorityAlertFlag: Bool = false
    private var currentURL: String?
    private var currentIPRatio: Int = 0
    private var deviceInfo: DeviceClass?
    private var token: String?
    private var errorMsg: String?
    private var modes: [IRGLRenderMode]?
    private var parameter: IRMediaParameter?
    private var imageView: UIImageView?
    private var borderLayer: CALayer?
    private var streamingQueue: DispatchQueue?
//    private var rtspStreamer: RTSPReceiver?
    private var streamConnector: IRStreamConnector?

    weak var audioDelegate: AnyObject?
    weak var eventDelegate: IRStreamControllerDelegate?
    weak var videoView: IRPlayerImp?

    // MARK: - Initializers
    override init() {
        super.init()
        initStreamingQueue()
        httpRequest = StaticHttpRequest.shared
    }

    convenience init(rtspURL: String) {
        self.init()
        streamConnector = IRStreamConnector()
        streamConnector?.delegate = self
        streamConnector?.rtspURL = rtspURL
    }

    convenience init(device: DeviceClass) {
        self.init()
        streamConnector = IRCustomStreamConnector()
        if let customStreamConnector = streamConnector as? IRCustomStreamConnector {
            customStreamConnector.deviceInfo = device
        }
        setDeviceClass(device, channel: 0)
    }

    // MARK: - Streaming
    func startStreamConnection() {
        eventDelegate?.streamControllerStatusChanged(.preparingToPlay)
        streamConnector?.startStreamConnection()
    }

    func stopStreaming(stopForever: Bool) -> Int {
        stopStreamingFlag = true
        stopForeverFlag = stopForever
//        rtspStreamer?.stopConnection(stopForever)
        return streamConnector?.stopStreaming(stopForever) ?? 0
    }

    func changeStream(_ stream: Int) {
        guard let deviceInfo = deviceInfo else { return }
        if deviceInfo.streamNO != stream {
            stopStreaming(stopForever: false)
            streamConnector?.changeStream(stream)
        }
    }

    func reconnectToDevice() {
        guard !stopStreamingFlag, reconnectTimes < MAX_RETRY_TIMES else { return }
        reconnectTimes += 1
        streamConnector?.startStreamConnection()
    }

    // MARK: - Helpers
    private func initStreamingQueue() {
        if streamingQueue == nil {
            streamingQueue = DispatchQueue(label: "streaming.queue", qos: .background)
        }
    }

    func setDeviceClass(_ deviceInfo: DeviceClass, channel: Int) {
        self.deviceInfo = deviceInfo
        self.deviceInfo?.streamInfo = nil
        self.channel = channel
    }

    func createFisheyeModes(with parameter: IRMediaParameter?) -> [IRGLRenderMode] {
        let normal = IRGLRenderMode2D()
        let fisheye2Pano = IRGLRenderMode2DFisheye2Pano()
        let fisheye = IRGLRenderMode3DFisheye()
        let fisheye4P = IRGLRenderModeMulti4P()

        normal.shiftController.enabled = false
        fisheye2Pano.contentMode = .scaleAspectFill
        fisheye2Pano.wideDegreeX = 360
        fisheye2Pano.wideDegreeY = 20

        fisheye4P.parameter = parameter
        fisheye.parameter = parameter
        fisheye.aspect = 16.0 / 9.0
        fisheye4P.aspect = fisheye.aspect

        return [fisheye2Pano, fisheye, fisheye4P, normal]
    }

    func getRenderModes() -> [IRGLRenderMode] {
        return videoView?.renderModes ?? []
    }

    func getCurrentRenderMode() -> IRGLRenderMode? {
        return videoView?.renderMode
    }

    func setCurrentRenderMode(_ renderMode: IRGLRenderMode) {
        videoView?.selectRenderMode(renderMode: renderMode)
    }

    // MARK: - ReceiverDelegate
    func connectSuccess() {
        reconnectTimes = 0
        stopStreamingFlag = false
        eventDelegate?.connectResult(self, connection: true, micSupport: false, speakerSupport: false)
    }

    func connectFail(byType type: Int, errorDesc: String) {
        eventDelegate?.showErrorMessage(errorDesc)
    }

    func videoLoss(withErrorCode code: Int, msg: String) {
        reconnectToDevice()
    }
}

extension IRStreamController: IRStreamConnectorDelegate {

    func connectFail(byType type: ConnectorErrorType, errorDesc: String?) {
        var strShow = NSLocalizedString("ReconnectStreamConnectFail", comment: "")
        var errorCode = -99999

        switch type {
        case .authorizationError:
            strShow = NSLocalizedString("loginFail", comment: "")
        case .notSupported:
            strShow = NSLocalizedString("DeiceNitSupported", comment: "")
        default:
            errorCode = -1
            strShow = NSLocalizedString("ConnectFail", comment: "")
        }

        eventDelegate?.showErrorMessage(strShow)
        showHideLoading(false)
    }

    func startStreaming(with response: IRStreamConnectionResponse?) {
        if modes == nil, response?.deviceModelName == "FisheyeCAM" {
            if parameter == nil {
                parameter = IRFisheyeParameter(width: 1440, height: 1024, up: false, rx: 510, ry: 510, cx: 680, cy: 524, latmax: 75)
            }
            modes = createFisheyeModes(with: parameter)
            eventDelegate?.updatedVideoModes()
        } else if modes == nil {
            eventDelegate?.updatedVideoModes()
        }

        aryStreamInfo = response?.streamsInfo
        currentURL = response?.rtspURL

        /*
        rtspStreamer?.stopConnection(false)
        rtspStreamer = nil
         */

        guard let currentURL = currentURL else { return }

        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            /*
            self.rtspStreamer = RTSPReceiver(device: self.deviceInfo,
                                             url: currentURL,
                                             useTCP: self.useTCP)
            self.rtspStreamer?.setEventDelegate(self)
            self.rtspStreamer?.setChannel(self.channel)
            self.rtspStreamer?.videoDecoder?.showView = self.videoView?.videoInput
            self.rtspStreamer?.audioDecoder?.delegate = self.audioDelegate
            self.rtspStreamer?.startConnection()
             */
            self.stopStreamingFlag = false
        }
    }

    private func showHideLoading(_ connected: Bool) {
        DispatchQueue.main.async {
            if connected {
                self.eventDelegate?.connectResult(self, connection: true, micSupport: false, speakerSupport: false)
            } else {
                self.eventDelegate?.connectResult(self, connection: false, micSupport: false, speakerSupport: false)
            }
        }
    }
}
