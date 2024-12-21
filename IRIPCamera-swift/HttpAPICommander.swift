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
    var httpPort: Int
    var httpsPort: Int
    var videoPort: Int
    var audioPort: Int
    var normalPort: Int
    var downloadPort: Int

    static func initial() -> MultiPort {
        return MultiPort(
            httpPort: HTTP_APP_COMMAND_PORT,
            httpsPort: HTTPS_APP_COMMAND_PORT,
            videoPort: VIDEO_PORT,
            audioPort: AUDIO_PORT,
            normalPort: NORMAL_PORT,
            downloadPort: DOWNLOAD_PORT
        )
    }

    static func zero() -> MultiPort {
        return MultiPort(
            httpPort: 0,
            httpsPort: 0,
            videoPort: 0,
            audioPort: 0,
            normalPort: 0,
            downloadPort: 0
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
    var getRTSPInfo: Bool = false
    var getAudioInfo: Bool = false
    var ignoreLoginCache: Bool = false
    var stopCommandTunnel: Bool = false

    var address: String = ""
    var userName: String = ""
    var password: String = ""
    var uid: String = ""
    var token: String = ""
    var privilege: String = ""
    var scheme: String = ""

    var videoStreamInfo: [String: Any]?
    var loginInfo: [String: Any]?
    var audioInfo: [String: Any]?

    var retryTime: Int = 0
    var tag: Int = 0
    var currentErrorType: ConnectorErrorType = .authorizationError
    var isAppAndDutUnderTheSameLAN: Bool = false

    var asiHttpSender: StaticHttpRequest?
    var deviceType: DeviceType = .ipcam

    // MARK: - Initializer
    init(address: String, port: MultiPort, user: String, password: String, scheme: String) {
        self.commandPort = MultiPort.initial()
        self.address = address
        self.userName = user
        self.password = password
        self.scheme = scheme
        self.stopCommandTunnel = false
    }

    // MARK: - Methods
    func updateUserName(_ userName: String, password: String) {
        self.userName = userName
        self.password = password
    }

    func startLoginToDevice(getStreamInfo: Bool, ignoreLoginCache: Bool) {
        self.getRTSPInfo = getStreamInfo
        self.ignoreLoginCache = ignoreLoginCache
    }

    func cancelLoginToDevice() {
        self.stopConnection = true
        print("Cancel type=\(tag)")
    }

    func getVideoStreamURL(byChannel channel: Int) {
        // Implementation here
    }

    func getStreamsCodecInfo() -> [String]? {
        guard let videoStreamInfo = videoStreamInfo else { return nil }

        var codecInfo: [String] = []
        if let streamSettings = videoStreamInfo["StreamSettings"] as? [[String: Any]] {
            for stream in streamSettings {
                if let enable = stream["Enable"] as? Bool, enable,
                   let codec = stream["Codec"] as? String,
                   let resolution = stream["Resolution"] as? String {
                    codecInfo.append("\(codec)(\(resolution))")
                }
            }
        }
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
