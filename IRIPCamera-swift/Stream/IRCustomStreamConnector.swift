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
    
    private var httpRequest: HttpRequest?
    private var streamInfoArray: [String] = []
    var deviceConnector: DeviceConnector?
    var deviceInfo: DeviceClass?
    var stopForever: Bool = false

    override func startStreamConnection() {
        if deviceConnector == nil {
            deviceConnector = DeviceConnector(
                address: GroupAddress(dataAddress: deviceInfo?.deviceAddress ?? "", commandAddress: ""),
                port: GroupPort(dataMultiPort: deviceInfo?.httpPort ?? MultiPort.initial(), commandMultiPort: MultiPort.initial()),
                user: deviceInfo?.userName ?? "",
                password: deviceInfo?.password ?? "",
                delegate: self,
                deviceInfo: deviceInfo,
                state: .loginConnector,
                scheme: "https"
            )
            response = IRStreamConnectionResponse()
        }
        videoRetry = 0
        deviceConnector?.loginToDevice(getRTSPInfo: true, checkPrevious: false, ignoreLoginCache: true)
    }

    override func stopStreaming(_ stopForever: Bool) {
        guard let connector = deviceConnector, stopForever else {
            return
        }
        connector.stopConnectionAction()
        connector.delegate = nil
        deviceConnector = nil
    }

    override func changeStream(_ stream: Int) {
        deviceConnector?.getVideoStreamURL(byChannel: stream)
    }
}

extension IRCustomStreamConnector: DeviceConnectorDelegate {

    func didFinishLoginAction(resultType: Int,
                              deviceInfo: [String: Any]?,
                              errorDesc: String,
                              address: String,
                              port: MultiPort) {
        if resultType == 0 {
            response?.deviceModelName = deviceInfo?["ModelName"] as? String
        }

        switch resultType {
        case -1:
            delegate?.connectFail(byType: .connectionTimeout, errorDesc: nil)
        // more resultCode
        default:
            break
        }

        print("didfinishLoginActionByResultType:\(resultType), \(errorDesc ?? "")")
    }

    func didGetRTSPResponse(resultCode: Int, message msg: String) {
        videoRetry += 1
        if !stopForever {
            deviceConnector?.getVideoStreamURL(byChannel: 0)
        }
    }

    func didGetRTSPUrlResult(resultCode: Int,
                             message msg: String,
                             channel ch: Int,
                             url: String,
                             ipRatio: Int) {
        if resultCode == 0 {
            deviceInfo?.streamInfo = streamInfoArray[ch]
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
