//
//  IRCustomStreamConnector.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import Foundation
import UIKit
import CoreMotion

class IRCustomStreamConnector: IRStreamConnector, UIAlertViewDelegate {
    
    private var httpRequest: StaticHttpRequest?
    private var streamInfoArray: [String] = []
    var deviceConnector: DeviceConnector?
    var deviceInfo: DeviceClass?
    var stopForever: Bool = false

    override func startStreamConnection() {
        if deviceConnector == nil {
            deviceConnector = DeviceConnector(
                address: GroupAddress(dataAddress: deviceInfo?.deviceAddress ?? "", commandAddress: deviceInfo?.httpCMDAddress ?? ""),
                port: GroupPort(dataMultiPort: deviceInfo?.httpPort ?? MultiPort.initial(), commandMultiPort: deviceInfo?.httpCMDPort ?? MultiPort.initial()),
                user: deviceInfo?.userName ?? "",
                password: deviceInfo?.password ?? "",
                delegate: self,
                deviceInfo: deviceInfo,
                state: .loginConnector,
                type: .ipcam,
                scheme: "http",
                connectorType: deviceInfo?.prefType ?? .unknown
            )
            response = IRStreamConnectionResponse()
        }
        videoRetry = 0
        deviceConnector?.loginToDevice(getRTSPInfo: true, checkPrevious: false, ignoreLoginCache: true)
    }

    override func stopStreaming(_ stopForever: Bool) -> Int {
        if let connector = deviceConnector {
            if stopForever {
                connector.stopConnectionAction()
                connector.delegate = nil
                deviceConnector = nil
            }
        }
        return 0
    }

    override func changeStream(_ stream: Int) {
        deviceConnector?.getVideoStreamURL(byChannel: deviceInfo?.streamNO ?? 0)
    }

    override func getErrorCode() -> Int {
        return -1
    }

    func didfinishLoginAction(
        byResultType resultCode: Int,
        deviceInfo: [String: Any]?,
        errorDesc: String?,
        address: String?,
        port: MultiPort
    ) {
        if resultCode == 0 {
            response?.deviceModelName = deviceInfo?["ModelName"] as? String
        }

        switch resultCode {
        case -1:
            delegate?.connectFail(byType: .connectionTimeout, errorDesc: nil)
        case -2:
            delegate?.connectFail(byType: .notSupported, errorDesc: errorDesc)
        case -99:
            delegate?.connectFail(byType: .authorizationError, errorDesc: nil)
        default:
            break
        }

        print("didfinishLoginActionByResultType:\(resultCode), \(errorDesc ?? "")")
    }

    func didGetRTSPResponse(resultCode: Int, message msg: String) {
        videoRetry += 1
        if resultCode == -97, videoRetry > 3 {
            if !stopForever {
                deviceConnector?.getStreamsCodecInfo()
                if deviceInfo?.streamNO == -1 {
                    deviceInfo?.streamNO = streamInfoArray.count - 1
                }
                deviceConnector?.getVideoStreamURL(byChannel: deviceInfo?.streamNO ?? 0)
            }
        } else if resultCode == -2, videoRetry > 3 {
            delegate?.connectFail(byType: .connectionTimeout, errorDesc: msg)
        } else if !stopForever {
            deviceConnector?.getStreamsCodecInfo()
            if deviceInfo?.streamNO == -1 {
                deviceInfo?.streamNO = streamInfoArray.count - 1
            }
            deviceConnector?.getVideoStreamURL(byChannel: deviceInfo?.streamNO ?? 0)
        }
    }

    func didGetRTSPUrlResult(resultCode: Int,
                             message msg: String,
                             channel ch: Int,
                             url: String,
                             ipRatio: Int) {
        if resultCode == 0 {
            var channel = ch
            while channel >= streamInfoArray.count {
                print("@@ ch = \(channel), array = \(streamInfoArray.count)")
                channel -= 1
            }

            response?.streamsInfo = streamInfoArray
            deviceInfo?.streamInfo = streamInfoArray[channel]
            deviceInfo?.streamNO = channel
            response?.rtspURL = url
            delegate?.startStreaming(with: response)
        }
    }

    func didGetTwoWayAudioResponse(resultCode: Int, message msg: String) {
        deviceConnector?.getTwoWayAudioInfo()
    }

    func didGetTwoWayAudioResult(resultCode: Int,
                                 url: String,
                                 type: String,
                                 sampleRate: Int,
                                 bps: Int) {
        // Handle Two Way Audio Result
    }
}

extension IRCustomStreamConnector: DeviceConnectorDelegate {

}
