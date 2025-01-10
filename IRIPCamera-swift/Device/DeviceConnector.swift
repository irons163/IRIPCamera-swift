//
//  DeviceConnector.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import Foundation

protocol DeviceConnectorDelegate: AnyObject {
    func didFailedConnectToDevice()
    func didFinishLoginAction(resultType: Int,
                              deviceInfo: [String: Any]?,
                              errorDesc: String,
                              address: String,
                              port: MultiPort)
    func didGetRTSPResponse(resultCode: Int, message: String)
    func didGetRTSPUrlResult(resultCode: Int,
                             message: String,
                             channel: Int,
                             url: String,
                             ipRatio: Int)
    func didGetTwoWayAudioResponse(resultCode: Int, message: String)
    func didGetTwoWayAudioResult(resultCode: Int,
                                 url: String,
                                 type: String,
                                 sampleRate: Int,
                                 bps: Int)
    func didReportFileDownloadPort(resultCode: Int, message: String, port: Int)
}

extension DeviceConnectorDelegate {
    func didFailedConnectToDevice() { }
    func didFinishLoginAction(resultType: Int, deviceInfo: [String : Any]?, errorDesc: String, address: String, port: MultiPort) { }
    func didReportFileDownloadPort(resultCode: Int, message: String, port: Int) { }
}

enum ConnectorState {
    case checkOnlineConnector
    case loginConnector
}

class DeviceConnector: NSObject {
    // MARK: - Properties
    weak var delegate: DeviceConnectorDelegate?
    var addressConnector: AddressConnector?
    var currentState: ConnectorState = .checkOnlineConnector
    var connectorCounter = 0
    var deviceInfo: Any?
    var originalScheme: String = "http"
    var checkStatus = false
    var getRTSPInfo = false
    var ignoreLoginCache = false
    var tmpMessage: String?

    // MARK: - Initialization
    init(
        address: GroupAddress,
        port: GroupPort,
        user: String,
        password: String,
        delegate: DeviceConnectorDelegate?,
        deviceInfo: Any?,
        state: ConnectorState,
        scheme: String
    ) {
        super.init()
        self.delegate = delegate
        self.currentState = state
        self.originalScheme = scheme == "http" ? scheme : "http"
        self.deviceInfo = deviceInfo

        if address.dataAddress.count > 0 && address.dataAddress != address.commandAddress {
            self.addressConnector = AddressConnector(
                address: address.dataAddress,
                port: port.dataMultiPort,
                user: user,
                password: password,
                scheme: scheme
            )
            self.addressConnector?.tag = HttpAPICommanderType.httpApiAddress.rawValue
            self.addressConnector?.delegate = self
        }
    }

    // MARK: - Methods
    func loginToDevice(getRTSPInfo: Bool, checkPrevious: Bool, ignoreLoginCache: Bool) {
        self.getRTSPInfo = getRTSPInfo
        self.checkStatus = checkPrevious
        self.ignoreLoginCache = ignoreLoginCache

        DispatchQueue.global(qos: .background).async {
            self.startLoginToDevice()
        }
    }

    func getVideoStreamURL(byChannel channel: Int) {
        self.addressConnector?.getVideoStreamURL(byChannel: channel)
    }

    func getTwoWayAudioInfo() {
        self.addressConnector?.getTwoWayAudioInfo()
    }

    func getStreamsCodecInfo() -> [String]? {
        return self.addressConnector?.getStreamsCodecInfo()
    }

    func stopConnectionAction() {
        if let addressConnector = addressConnector {
            addressConnector.cancelLoginToDevice()
        }
    }

    func updateUserName(_ username: String, password: String) {
        self.addressConnector?.updateUserName(username, password: password)
    }

    func startCheckOnlineStatus() {
        self.checkStatus = true
        self.getRTSPInfo = false
        self.ignoreLoginCache = true

        DispatchQueue.global(qos: .background).async {
            self.startCheckStatus()
        }
    }

    private func startLoginToDevice() {
        guard connectorCounter > 0 else {
            self.delegate?.didFinishLoginAction(
                resultType: -1,
                deviceInfo: [:],
                errorDesc: "Connect failed",
                address: "",
                port: MultiPort.zero()
            )
            return
        }
        self.addressConnector?.startLoginToDevice()
    }

    private func startReLoginToDevice() {
        if let addressConnector = addressConnector {
            addressConnector.retryTime = 0
            addressConnector.startLoginToDevice()
        }
    }

    private func startCheckStatus() {
        guard connectorCounter > 0 else {
            self.delegate?.didFinishLoginAction(
                resultType: -1,
                deviceInfo: [:],
                errorDesc: "Connect failed",
                address: "",
                port: MultiPort.zero()
            )
            return
        }
        self.addressConnector?.checkDeviceOnline()
    }
}

extension DeviceConnector: HttpAPICommanderDelegate {

    func failedAfterRetry(_ caller: HttpAPICommander) {
        // no-op
    }
    
    func didLoginResult(resultCode: Int, message: String, caller: HttpAPICommander, info: [String : Any]?, address: String, port: MultiPort) {
        print("ResultCode: \(resultCode)")

        delegate?.didFinishLoginAction(resultType: resultCode, deviceInfo: info, errorDesc: message, address: address, port: port)
    }
    
    func didGetRTSPResponse(resultCode: Int, message: String) {
        // no-op
    }

    func didGetRtspURLByChannel(resultCode: Int, message: String?, channel: Int, url: String, ipRatio: Int) {
        // no-op
    }
    
    func didGetTwoWayAudioResponse(resultCode: Int, message: String) {
        // no-op
    }
    
    func didGetTwoWayAudioResult(resultCode: Int, url: String?, type: String?, sampleRate: Int, bps: Int) {
        // no-op
    }
    
    func didReportFileDownloadPort(resultCode: Int, message: String, port: Int) {
        // no-op
    }
    
    func didInTheSameLAN(deviceAddress: String, port: MultiPort) {
        // no-op
    }
}
