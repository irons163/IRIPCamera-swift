//
//  AddressConnector.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import Foundation
import SystemConfiguration.CaptiveNetwork
import Alamofire

class LocalIPInfo {
    var currentInterfaceIP: String?
    var wifiIP: String?
    var cellularIP: String?

    init(currentInterfaceIP: String? = nil, wifiIP: String? = nil, cellularIP: String? = nil) {
        self.currentInterfaceIP = currentInterfaceIP
        self.wifiIP = wifiIP
        self.cellularIP = cellularIP
    }
}

class AddressConnector: HttpAPICommander, StaticHttpRequestDelegate {

    // MARK: - Start Login Process
    override func startLoginToDevice(getStreamInfo: Bool, ignoreLoginCache: Bool) {
        super.startLoginToDevice(getStreamInfo: getStreamInfo, ignoreLoginCache: ignoreLoginCache)
        DispatchQueue.global().async {
            self.loginToDevice()
        }
    }

    override func getVideoStreamURL(byChannel channel: Int) {
        guard let videoStreamInfo = self.videoStreamInfo,
              let streamSettings = videoStreamInfo["StreamSettings"] as? [[String: Any]] else {
            return
        }

        var selectedChannel = channel
        if selectedChannel >= streamSettings.count {
            selectedChannel = streamSettings.count - 1
        } else if selectedChannel < 0 {
            selectedChannel = 0
        }

        var streamChannel = 0
        for stream in streamSettings {
            guard let isEnabled = stream["Enable"] as? Bool, isEnabled else { continue }

            if streamChannel == selectedChannel,
               let rtspURLString = stream["URL"] as? String,
               let components = URLComponents(string: rtspURLString) {
                var updatedComponents = components
                updatedComponents.host = self.address
                updatedComponents.port = self.commandPort.videoPort

                if let updatedURL = updatedComponents.url {
                    delegate?.didGetRtspURLByChannel(
                        resultCode: 0,
                        message: nil,
                        channel: selectedChannel,
                        url: updatedURL.absoluteString,
                        ipRatio: stream["FPS"] as? Int ?? 0
                    )
                    break
                }
            } else {
                streamChannel += 1
            }
        }
    }

    override func getTwoWayAudioInfo() {
        // Custom implementation for getting two-way audio info
    }

    // MARK: - Private Methods
    private func loginToDevice() {
        guard !stopConnection else {
            cancelLoginToDevice()
            return
        }

        // Custom login logic
    }

    private func getRTSPInfo(withToken token: String) {
        guard !stopConnection else {
            cancelLoginToDevice()
            return
        }

        let port = scheme == "http" ? commandPort.httpPort : commandPort.httpsPort
        let commandURL = String(format: GET_STREAM_SETTINGS, scheme, address, port)

        StaticHttpRequest.shared.doJsonRequest(
            token: token,
            externalLink: getLocalIPInfo().currentInterfaceIP,
            url: commandURL,
            method: .get,
            postData: nil,
            callbackID: .getVideoInfo,
            target: self
        )
    }

    private func getTwoWayAudioInfo(withToken token: String) {
        guard !stopConnection else {
            cancelLoginToDevice()
            return
        }

        let port = scheme == "http" ? commandPort.httpPort : commandPort.httpsPort
        let commandURL = String(format: GET_AUDIOOUT_INFO, scheme, address, port)

        StaticHttpRequest.shared.doJsonRequest(
            token: token,
            externalLink: getLocalIPInfo().currentInterfaceIP,
            url: commandURL,
            method: .get,
            postData: nil,
            callbackID: .getTwoWayAudioInfo,
            target: self
        )
    }

    private func getRedirectURL(from url: URL) -> URL? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        let semaphore = DispatchSemaphore(value: 0)
        var redirectURL: URL?

        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            redirectURL = response?.url
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        return redirectURL
    }

    private func getLocalIPInfo() -> LocalIPInfo {
        var wifiAddress: String?
        var cellularAddress: String?

        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        defer { freeifaddrs(ifaddr) }

        guard getifaddrs(&ifaddr) == 0 else { return LocalIPInfo() }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                let name = String(cString: interface.ifa_name)
                let addr = withUnsafePointer(to: &interface.ifa_addr.pointee) {
                    $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { addr in
                        String(cString: inet_ntoa(addr.pointee.sin_addr))
                    }
                }

                if name == "en0" {
                    wifiAddress = addr
                } else if name == "pdp_ip0" {
                    cellularAddress = addr
                }
            }
        }

        let localIPInfo = LocalIPInfo()
        localIPInfo.wifiIP = wifiAddress
        localIPInfo.cellularIP = cellularAddress
        localIPInfo.currentInterfaceIP = wifiAddress ?? cellularAddress

        return localIPInfo
    }

    // MARK: - StaticHttpRequestDelegate
    func failToStaticRequest(errorCode: Int, description: String, callbackID: DeviceConnectorCommandStatus) {
        print("AddressConnector failToStaticRequestWithErrorCode callback \(callbackID)")
        guard !stopConnection else {
            print("stopConnection Return")
            return
        }

        retryTime += 1
        switch callbackID {
        case .doDeviceLogin:
            if retryTime <= 3 {
                DispatchQueue.global().async {
                    self.loginToDevice()
                }
            } else if !stopConnection {
                delegate?.didLoginResult(
                    resultCode: -1,
                    message: "connect failed",
                    caller: self,
                    info: nil,
                    address: address,
                    port: commandPort
                )
            }
        case .getVideoInfo:
            if retryTime <= 3 {
                getRTSPInfo(withToken: token)
            } else {
                delegate?.didGetRTSPResponse(resultCode: -2, message: "Get Rtsp Stream Info failed")
            }
        case .getTwoWayAudioInfo:
            if retryTime <= 3 {
                getTwoWayAudioInfo(withToken: token)
            } else {
                delegate?.didGetTwoWayAudioResult(resultCode: -1, url: nil, type: nil, sampleRate: 0, bps: 0)
            }
        default:
            break
        }
    }

    func didFinishStaticRequestJSON(response: Any, callbackID: DeviceConnectorCommandStatus) {
        print("AddressConnector didFinishStaticRequestJSON callback \(callbackID)")
        guard !stopConnection else {
            print("stopConnection Return")
            return
        }
        // Handle successful request here
    }

    override func checkDeviceOnline() {
        startLoginToDevice(getStreamInfo: false, ignoreLoginCache: true)
    }
}
