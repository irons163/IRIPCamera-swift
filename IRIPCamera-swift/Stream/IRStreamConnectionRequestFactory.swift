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
            let urls = [
                userDefaults.string(forKey: RTSP_URL_KEY) ?? "",
                userDefaults.string(forKey: RTSP_URL_KEY_2) ?? "",
                userDefaults.string(forKey: RTSP_URL_KEY_3) ?? "",
                userDefaults.string(forKey: RTSP_URL_KEY_4) ?? ""
            ]
            let enables = [
                userDefaults.object(forKey: RTSP_URL_ENABLE_KEY_1) as? Bool ?? true,
                userDefaults.object(forKey: RTSP_URL_ENABLE_KEY_2) as? Bool ?? true,
                userDefaults.object(forKey: RTSP_URL_ENABLE_KEY_3) as? Bool ?? true,
                userDefaults.object(forKey: RTSP_URL_ENABLE_KEY_4) as? Bool ?? true
            ]
            for (index, url) in urls.enumerated() {
                guard index < enables.count, enables[index] else { continue }
                let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let request = IRStreamConnectionRequest()
                request.rtspUrl = trimmed
                devices.append(request)
            }
        } else {
            let device = DeviceClass()
            let request = IRCustomStreamConnectionRequest(device: device)
            devices.append(request)
        }

        return devices
    }
}
