//
//  IRStreamConnectionRequestFactory.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import Foundation

class IRStreamConnectionRequestFactory {

    static func createStreamConnectionRequest() -> [IRStreamConnectionRequest] {
        var devices: [IRStreamConnectionRequest] = []
        let userDefaults = UserDefaults.standard

        if userDefaults.bool(forKey: ENABLE_RTSP_URL_KEY) {
            let request = IRStreamConnectionRequest()
            request.rtspUrl = userDefaults.string(forKey: RTSP_URL_KEY) ?? ""
            devices.append(request)
        } else {
            let device = DeviceClass()
            let request = IRCustomStreamConnectionRequest(device: device)
            devices.append(request)
        }

        return devices
    }
}
