//
//  StreamControllerFactoryTests.swift
//  IRIPCamera-swiftTests
//
//  Verifies `IRStreamControllerFactory` wires up the right controller flavour
//  for each request type.
//

import Testing
@testable import IRIPCamera_swift

@MainActor
struct StreamControllerFactoryTests {

    @Test func buildsRTSPControllerForPlainRequest() {
        let request = IRStreamConnectionRequest()
        request.rtspUrl = "rtsp://example"

        let controller = IRStreamControllerFactory.createStreamController(by: request)

        // A plain RTSP request must not be treated as a custom-device request.
        #expect(controller.deviceInfo == nil)
    }

    @Test func buildsDeviceControllerForCustomRequest() {
        let device = DeviceClass()
        device.deviceName = "cam"
        let request = IRCustomStreamConnectionRequest(device: device)

        let controller = IRStreamControllerFactory.createStreamController(by: request)

        #expect(controller.deviceInfo === device)
    }
}
