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
    case buffering
    case preparingToPlay
    case readyToPlay
    case playing
    case playToEnd
    case failed
}

protocol IRStreamControllerDelegate: AnyObject {
    func connectResult(_ videoView: Any, connection: Bool, micSupport: Bool, speakerSupport: Bool)
    func showErrorMessage(_ msg: String)
    func streamControllerStatusChanged(_ status: IRStreamControllerStatus)
    func updatedVideoModes(_ modes: [IRGLRenderMode]?)
}

extension IRStreamControllerDelegate {
    func updatedVideoModes(_ modes: [IRGLRenderMode]?) { }
}

class IRStreamController: NSObject {

    var deviceInfo: DeviceClass?
    private var httpRequest: HttpRequest?
    private var channel: Int = 0
    private var aryStreamInfo: [Any]?
    private var availableStreams: Int = 0
    private var deviceStreamMode: Int = 0
    private var reconnectTimes: Int = 0
    private var stopStreamingFlag: Bool = false
    private var stopForeverFlag: Bool = false
    private var currentURL: String?
    private var token: String?

    private var parameter: IRMediaParameter?
    private var streamConnector: IRStreamConnector?

    weak var eventDelegate: IRStreamControllerDelegate?
    weak var videoView: IRPlayerImp? {
        didSet {
            videoView?.registerPlayerNotification(target: self,
                                              stateAction: #selector(stateAction(_:)))
        }
    }

    // MARK: - Initializers
    override init() {
        super.init()
        httpRequest = HttpRequest.shared
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
        self.deviceInfo = device
    }

    // MARK: - Streaming
    func startStreamConnection() {
        eventDelegate?.streamControllerStatusChanged(.preparingToPlay)
        streamConnector?.startStreamConnection()
    }

    func stopStreaming(stopForever: Bool) {
        stopStreamingFlag = true
        stopForeverFlag = stopForever
        videoView?.pause()
        streamConnector?.stopStreaming(stopForever)
        connected(false)
    }

    func changeStream(_ stream: Int) {
        stopStreaming(stopForever: false)
        streamConnector?.changeStream(stream)
    }

    func reconnectToDevice() {
        guard !stopStreamingFlag, reconnectTimes < MAX_RETRY_TIMES else { return }
        reconnectTimes += 1
        streamConnector?.startStreamConnection()
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
        connected(true)
    }

    func connectFail(byType type: Int, errorDesc: String) {
        eventDelegate?.showErrorMessage(errorDesc)
    }

    func videoLoss(withErrorCode code: Int, msg: String) {
        reconnectToDevice()
    }

    // MARK: - Notification Handlers
    @objc func stateAction(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        let state = IRState.state(fromUserInfo: userInfo)
        switch state.current {
        case .buffering:
            eventDelegate?.streamControllerStatusChanged(.buffering)
            break
        case .readyToPlay:
            connectSuccess()
        case .playing:
            eventDelegate?.streamControllerStatusChanged(.playing)
        case .failed:
            reconnectToDevice()
            break
        default:
            break
        }
    }
}

extension IRStreamController: IRStreamConnectorDelegate {

    func connectFail(byType type: ConnectorErrorType, errorDesc: String?) {
        var strShow = NSLocalizedString("ReconnectStreamConnectFail", comment: "")

        switch type {
        case .authorizationError:
            strShow = NSLocalizedString("loginFail", comment: "")
        case .notSupported:
            strShow = NSLocalizedString("DeiceNitSupported", comment: "")
        default:
            strShow = NSLocalizedString("ConnectFail", comment: "")
        }

        eventDelegate?.showErrorMessage(strShow)
        connected(false)
    }

    func startStreaming(with response: IRStreamConnectionResponse?) {
        if response?.deviceModelName == "FisheyeCAM" {
            if parameter == nil {
                parameter = IRFisheyeParameter(width: 1440, height: 1024, up: false, rx: 510, ry: 510, cx: 680, cy: 524, latmax: 75)
            }
            eventDelegate?.updatedVideoModes(createFisheyeModes(with: parameter))
        } else {
            eventDelegate?.updatedVideoModes([IRGLRenderMode2D()])
        }

        aryStreamInfo = response?.streamsInfo
        currentURL = response?.rtspURL

        self.videoView?.pause()

        guard let currentURL = currentURL else {
            connected(false)
            return
        }

        let input = MyIRFFVideoInput(outputType: .decoder)
        self.videoView?.replaceVideoWithURL(contentURL: NSURL(string: currentURL), videoType: .normal, videoInput: input)
    }

    private func connected(_ connected: Bool) {
        DispatchQueue.main.async {
            self.eventDelegate?.connectResult(self, connection: connected, micSupport: false, speakerSupport: false)
        }
    }
}
