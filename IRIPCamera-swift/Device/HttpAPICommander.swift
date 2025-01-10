//
//  HttpAPICommander.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

enum DeviceConnectorCommandStatus {
    case doDeviceLogin
    case getVideoInfo
    case getTwoWayAudioInfo
}

enum HttpAPICommanderType: Int {
    case httpApiAddress = 0
    case httpApiDdns = 1
    case httpApiCommand = 3
}

enum ConnectorErrorType {
    case authorizationError
    case connectionTimeout
    case notSupported
}

struct MultiPort: Equatable {
    var httpsPort: Int
    var videoPort: Int
    var audioPort: Int
    var normalPort: Int

    static func initial() -> MultiPort {
        return MultiPort(
            httpsPort: HTTPS_APP_COMMAND_PORT,
            videoPort: VIDEO_PORT,
            audioPort: AUDIO_PORT,
            normalPort: NORMAL_PORT
        )
    }

    static func zero() -> MultiPort {
        return MultiPort(
            httpsPort: 0,
            videoPort: 0,
            audioPort: 0,
            normalPort: 0
        )
    }
}

struct GroupPort {
    var dataMultiPort: MultiPort
    var commandMultiPort: MultiPort
}

struct GroupAddress {
    var dataAddress: String
    var commandAddress: String
}

protocol HttpAPICommanderDelegate: AnyObject {
    func failedAfterRetry(_ caller: HttpAPICommander)
    func didLoginResult(
        resultCode: Int,
        message: String,
        caller: HttpAPICommander,
        info: [String: Any]?,
        address: String,
        port: MultiPort
    )
    func didGetRTSPResponse(resultCode: Int, message: String)
    func didGetRtspURLByChannel(
        resultCode: Int,
        message: String?,
        channel: Int,
        url: String,
        ipRatio: Int
    )
    func didGetTwoWayAudioResponse(resultCode: Int, message: String)
    func didGetTwoWayAudioResult(
        resultCode: Int,
        url: String?,
        type: String?,
        sampleRate: Int,
        bps: Int
    )
    func didReportFileDownloadPort(resultCode: Int, message: String, port: Int)
    func didInTheSameLAN(deviceAddress: String, port: MultiPort)
}

class HttpAPICommander {
    // MARK: - Properties
    weak var delegate: HttpAPICommanderDelegate?
    var commandPort: MultiPort = MultiPort.initial()
    var stopConnection: Bool = false

    var address: String = ""
    var userName: String = ""
    var password: String = ""
    var token: String = ""
    var scheme: String = ""

    var videoStreamInfo: [String: Any]?
    var loginInfo: [String: Any]?
    var audioInfo: [String: Any]?

    var retryTime: Int = 0
    var tag: Int = 0
    var currentErrorType: ConnectorErrorType = .authorizationError
    var isAppAndDutUnderTheSameLAN: Bool = false

    // MARK: - Initializer
    init(address: String, port: MultiPort, user: String, password: String, scheme: String) {
        self.commandPort = MultiPort.initial()
        self.address = address
        self.userName = user
        self.password = password
        self.scheme = scheme
    }

    // MARK: - Methods
    func updateUserName(_ userName: String, password: String) {
        self.userName = userName
        self.password = password
    }

    func startLoginToDevice() {
        // Implementation here
    }

    func cancelLoginToDevice() {
        self.stopConnection = true
    }

    func getVideoStreamURL(byChannel channel: Int) {
        // Implementation here
    }

    func getStreamsCodecInfo() -> [String]? {
        guard let videoStreamInfo = videoStreamInfo else { return nil }

        var codecInfo: [String] = []
        // Implementation here
        return codecInfo
    }

    func getTwoWayAudioInfo() {
        // Implementation here
    }

    func closeTwoWayAudio() {
        // Implementation here
    }

    func checkDeviceOnline() {
        // Implementation here
    }
}
