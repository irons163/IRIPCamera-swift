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

class AddressConnector: HttpAPICommander, HttpRequestDelegate {

    // MARK: - Start Login Process
    override func startLoginToDevice() {
        super.startLoginToDevice()
        DispatchQueue.global().async {
            self.loginToDevice()
        }
    }

    override func getVideoStreamURL(byChannel channel: Int) {
        delegate?.didGetRtspURLByChannel(
            resultCode: 0,
            message: nil,
            channel: 0,
            url: "",
            ipRatio:0
        )
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

        HttpRequest.shared.doJsonRequest(
            token: token,
            url: "",
            method: .get,
            callbackID: .getVideoInfo,
            target: self
        )
    }

    private func getTwoWayAudioInfo(withToken token: String) {
        guard !stopConnection else {
            cancelLoginToDevice()
            return
        }

        HttpRequest.shared.doJsonRequest(
            token: token,
            url: "",
            method: .get,
            callbackID: .getTwoWayAudioInfo,
            target: self
        )
    }

    private func getLocalIPInfo() -> LocalIPInfo {
        let localIPInfo = LocalIPInfo()
        localIPInfo.wifiIP = ""
        localIPInfo.cellularIP = ""
        localIPInfo.currentInterfaceIP = ""

        return localIPInfo
    }

    // MARK: - HttpRequestDelegate
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
        startLoginToDevice()
    }
}
