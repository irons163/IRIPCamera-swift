//
//  IRStreamConnectionRequestFactory.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import Foundation

class IRStreamConnectionRequestFactory {

    /// Pairs of (RTSP URL key, matching enable-flag key) in display order.
    private static let urlEntries: [(urlKey: String, enableKey: String)] = [
        (RTSP_URL_KEY, RTSP_URL_ENABLE_KEY_1),
        (RTSP_URL_KEY_2, RTSP_URL_ENABLE_KEY_2),
        (RTSP_URL_KEY_3, RTSP_URL_ENABLE_KEY_3),
        (RTSP_URL_KEY_4, RTSP_URL_ENABLE_KEY_4)
    ]

    static func createStreamConnectionRequest(
        userDefaults: UserDefaults = .standard
    ) -> [IRStreamConnectionRequest] {
        guard userDefaults.bool(forKey: ENABLE_RTSP_URL_KEY) else {
            return [IRCustomStreamConnectionRequest(device: DeviceClass())]
        }

        return urlEntries.compactMap { entry in
            let enabled = userDefaults.object(forKey: entry.enableKey) as? Bool ?? true
            guard enabled else { return nil }

            let trimmed = (userDefaults.string(forKey: entry.urlKey) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let request = IRStreamConnectionRequest()
            request.rtspUrl = trimmed
            return request
        }
    }
}
