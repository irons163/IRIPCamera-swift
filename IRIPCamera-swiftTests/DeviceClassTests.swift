//
//  DeviceClassTests.swift
//  IRIPCamera-swiftTests
//
//  Covers `DeviceClass` defaults and its `NSCopying` implementation.
//

import Testing
@testable import IRIPCamera_swift

private final class SpyDeviceDelegate: DeviceClassDelegate {
    private(set) var finishedCount = 0
    func didDeviceStatusFinish(_ device: DeviceClass) { finishedCount += 1 }
}

struct DeviceClassTests {

    @Test func freshDeviceHasEmptyDefaults() {
        let device = DeviceClass()
        #expect(device.deviceName.isEmpty)
        #expect(device.deviceAddress.isEmpty)
        #expect(device.userName.isEmpty)
        #expect(device.password.isEmpty)
        #expect(device.streamInfo == "")
        #expect(device.httpPort == MultiPort.initial())
        #expect(device.connector == nil)
    }

    @Test func copyDuplicatesValueFields() {
        let original = DeviceClass()
        original.deviceName = "Front Door"
        original.deviceAddress = "192.168.1.50"
        original.userName = "admin"
        original.password = "secret"
        original.streamInfo = "main"
        original.httpPort = MultiPort(httpsPort: 1, videoPort: 2, audioPort: 3, normalPort: 4)

        let copy = original.copy() as! DeviceClass

        #expect(copy !== original)
        #expect(copy.deviceName == "Front Door")
        #expect(copy.deviceAddress == "192.168.1.50")
        #expect(copy.userName == "admin")
        #expect(copy.password == "secret")
        #expect(copy.streamInfo == "main")
        #expect(copy.httpPort == original.httpPort)
    }

    @Test func copyDoesNotCarryDelegate() {
        let original = DeviceClass()
        original.delegate = SpyDeviceDelegate()

        let copy = original.copy() as! DeviceClass

        #expect(copy.delegate == nil)
    }

    @Test func getWideDegreeValueIsZero() {
        #expect(DeviceClass().getWideDegreeValue() == 0)
    }

    @Test func httpRequestCallbacksNotifyDelegate() {
        let device = DeviceClass()
        let delegate = SpyDeviceDelegate()
        device.delegate = delegate

        device.didFinishStaticRequestJSON(response: [:], callbackID: .doDeviceLogin)
        device.failToStaticRequest(errorCode: 1, description: "x", callbackID: .getVideoInfo)

        #expect(delegate.finishedCount == 2)
    }
}
