//
//  IRIPCamera_swiftTests.swift
//  IRIPCamera-swiftTests
//
//  Created by irons on 2024/12/21.
//

import Testing
@testable import IRIPCamera_swift

/// Smoke tests covering the lightweight value types and shared constants.
struct IRIPCamera_swiftTests {

    @Test func maxRetryTimesIsThree() {
        #expect(MAX_RETRY_TIMES == 3)
    }

    @Test func streamConnectionRequestDefaultsToEmptyURL() {
        #expect(IRStreamConnectionRequest().rtspUrl.isEmpty)
    }

    @Test func customStreamConnectionRequestRetainsDevice() {
        let device = DeviceClass()
        device.deviceName = "cam-1"
        let request = IRCustomStreamConnectionRequest(device: device)
        #expect(request.device === device)
        #expect(request.rtspUrl.isEmpty)
    }

    @Test func streamConnectionResponseStartsEmpty() {
        let response = IRStreamConnectionResponse()
        #expect(response.rtspURL == nil)
        #expect(response.deviceModelName == nil)
        #expect(response.streamsInfo == nil)
    }
}
