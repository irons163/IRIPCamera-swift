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

enum PrefType {
    case unknown
    case address
    case ddns
}

class DeviceConnector: NSObject {
    // MARK: - Properties
    weak var delegate: DeviceConnectorDelegate?
    var commandConnector: HttpAPICommander?
    var addressConnector: AddressConnector?
    var ddnsConnector: AddressConnector?
    var deviceConnector: HttpAPICommander?
    var currentState: ConnectorState = .checkOnlineConnector
    var currentConnectorType: PrefType = .unknown
    var connectorCounter = 0
    var connectionFailCounter = 0
    var deviceInfo: Any?
    var originalScheme: String = "http"
    var hasReported = false
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
        type: DeviceType,
        scheme: String,
        connectorType: PrefType
    ) {
        super.init()
        self.delegate = delegate
        self.currentState = state
        self.currentConnectorType = connectorType
        self.originalScheme = scheme == "http" ? scheme : "http"
        self.deviceInfo = deviceInfo

        if address.commandAddress.count > 0 {
            self.commandConnector = AddressConnector(
                address: address.commandAddress,
                port: port.commandMultiPort,
                user: user,
                password: password,
                scheme: scheme
            )
            self.commandConnector?.tag = HttpAPICommanderType.httpApiAddress.rawValue
            self.commandConnector?.delegate = self
            self.connectorCounter += 1
        }

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
            self.connectorCounter += 1
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
        self.deviceConnector?.getVideoStreamURL(byChannel: channel)
    }

    func getTwoWayAudioInfo() {
        self.deviceConnector?.getTwoWayAudioInfo()
    }

    func getStreamsCodecInfo() -> [String]? {
        return self.deviceConnector?.getStreamsCodecInfo()
    }

    func stopConnectionAction() {
        if let deviceConnector = deviceConnector {
            deviceConnector.cancelLoginToDevice()
        } else {
            if let commandConnector = commandConnector {
                commandConnector.cancelLoginToDevice()
            }
            if let addressConnector = addressConnector {
                addressConnector.cancelLoginToDevice()
            }
            if let ddnsConnector = ddnsConnector {
                ddnsConnector.cancelLoginToDevice()
            }
        }
    }

    func updateUserName(_ username: String, password: String) {
        self.deviceConnector?.updateUserName(username, password: password)
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

        self.commandConnector?.startLoginToDevice(getStreamInfo: getRTSPInfo, ignoreLoginCache: ignoreLoginCache)
        self.addressConnector?.startLoginToDevice(getStreamInfo: getRTSPInfo, ignoreLoginCache: ignoreLoginCache)
        self.ddnsConnector?.startLoginToDevice(getStreamInfo: getRTSPInfo, ignoreLoginCache: ignoreLoginCache)
    }

    private func startReLoginToDevice() {
        switch currentConnectorType {
        case .unknown:
            break
        case .address:
            if let ddnsConnector = ddnsConnector {
                ddnsConnector.retryTime = 0
                ddnsConnector.startLoginToDevice(getStreamInfo: getRTSPInfo, ignoreLoginCache: ignoreLoginCache)
            }
        case .ddns:
            if let addressConnector = addressConnector {
                addressConnector.retryTime = 0
                addressConnector.startLoginToDevice(getStreamInfo: getRTSPInfo, ignoreLoginCache: ignoreLoginCache)
            }
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

        self.commandConnector?.checkDeviceOnline()
        self.addressConnector?.checkDeviceOnline()
        self.ddnsConnector?.checkDeviceOnline()
    }

    func stopOthersConnector(byConnectedId connectedId: Int) {
        if connectedId != self.commandConnector?.tag {
            self.commandConnector?.cancelLoginToDevice()
        }
        if connectedId != self.addressConnector?.tag {
            self.addressConnector?.cancelLoginToDevice()
        }
        if connectedId != self.ddnsConnector?.tag {
            self.ddnsConnector?.cancelLoginToDevice()
        }
    }
}

extension DeviceConnector: HttpAPICommanderDelegate {

    func failedAfterRetry(_ caller: HttpAPICommander) {
        // no-op
    }
    
    func didLoginResult(resultCode: Int, message: String, caller: HttpAPICommander, info: [String : Any]?, address: String, port: MultiPort) {
        print("ResultCode: \(resultCode)")
        connectionFailCounter += 1

        guard !hasReported else {
            print("HasReported")
            return
        }

        if let info = info, resultCode == 0 {
            print("_resultCode=\(resultCode)")
            stopOthersConnector(byConnectedId: caller.tag)
        }

        if resultCode == 0 || resultCode == -99 {
            hasReported = true
            connectionFailCounter = 0
            delegate?.didFinishLoginAction(resultType: resultCode, deviceInfo: info, errorDesc: message, address: address, port: port)
        } else if connectionFailCounter >= connectorCounter {
            hasReported = true
            connectionFailCounter = 0
            delegate?.didFinishLoginAction(resultType: -1, deviceInfo: info, errorDesc: "Connect Failed!", address: address, port: port)
        } else {
            startReLoginToDevice()
        }
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
