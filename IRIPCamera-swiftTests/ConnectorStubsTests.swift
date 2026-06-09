//
//  ConnectorStubsTests.swift
//  IRIPCamera-swiftTests
//
//  Exercises the base `HttpAPICommander` stubs, `DeviceConnector` pass-through
//  methods, `DeviceClass.stopConnectionAction`, and `HttpRequest` housekeeping.
//

import Foundation
import Testing
@testable import IRIPCamera_swift

private final class NoopDeviceConnectorDelegate: DeviceConnectorDelegate {
    func didGetRTSPResponse(resultCode: Int, message: String) {}
    func didGetRTSPUrlResult(resultCode: Int, message: String, channel: Int, url: String, ipRatio: Int) {}
    func didGetTwoWayAudioResponse(resultCode: Int, message: String) {}
    func didGetTwoWayAudioResult(resultCode: Int, url: String, type: String, sampleRate: Int, bps: Int) {}
}

private final class NoopHttpRequestTarget: HttpRequestDelegate {
    private(set) var finished = 0
    private(set) var failed = 0
    func didFinishStaticRequestJSON(response: Any, callbackID: DeviceConnectorCommandStatus) { finished += 1 }
    func failToStaticRequest(errorCode code: Int, description: String, callbackID: DeviceConnectorCommandStatus) { failed += 1 }
}

struct ConnectorStubsTests {

    // MARK: - HttpAPICommander base

    @Test func baseCommanderStubsAreCallable() {
        let commander = HttpAPICommander(address: "a", port: .zero(), user: "u", password: "p", scheme: "https")

        commander.startLoginToDevice()
        commander.getVideoStreamURL(byChannel: 0)
        commander.getTwoWayAudioInfo()
        commander.closeTwoWayAudio()
        commander.checkDeviceOnline()
        #expect(commander.getStreamsCodecInfo() == nil)

        commander.updateUserName("newUser", password: "newPass")
        #expect(commander.userName == "newUser")
        #expect(commander.password == "newPass")

        commander.cancelLoginToDevice()
        #expect(commander.stopConnection)
    }

    // MARK: - DeviceConnector pass-throughs

    @Test func deviceConnectorForwardsToAddressConnector() {
        let delegate = NoopDeviceConnectorDelegate()
        // Distinct, non-empty addresses force creation of an AddressConnector.
        let connector = DeviceConnector(
            address: GroupAddress(dataAddress: "10.0.0.1", commandAddress: "10.0.0.2"),
            port: GroupPort(dataMultiPort: .zero(), commandMultiPort: .zero()),
            user: "u",
            password: "p",
            delegate: delegate,
            deviceInfo: nil,
            scheme: "https"
        )

        #expect(connector.getStreamsCodecInfo() == nil)
        connector.updateUserName("u2", password: "p2")
        connector.getVideoStreamURL(byChannel: 0)
        connector.getTwoWayAudioInfo()
        connector.stopConnectionAction()
        // Pass-throughs must not crash with a real address connector attached.
    }

    @Test func deviceConnectorHttpCommanderCallbacksAreNoOps() {
        let connector = DeviceConnector(
            address: GroupAddress(dataAddress: "", commandAddress: ""),
            port: GroupPort(dataMultiPort: .zero(), commandMultiPort: .zero()),
            user: "", password: "", delegate: nil, deviceInfo: nil, scheme: "https"
        )
        let caller = HttpAPICommander(address: "", port: .zero(), user: "", password: "", scheme: "https")

        connector.failedAfterRetry(caller)
        connector.didGetRTSPResponse(resultCode: 0, message: "")
        connector.didGetRtspURLByChannel(resultCode: 0, message: nil, channel: 0, url: "", ipRatio: 0)
        connector.didGetTwoWayAudioResponse(resultCode: 0, message: "")
        connector.didGetTwoWayAudioResult(resultCode: 0, url: nil, type: nil, sampleRate: 0, bps: 0)
        connector.didReportFileDownloadPort(resultCode: 0, message: "", port: 0)
        connector.didInTheSameLAN(deviceAddress: "", port: .zero())
        // All are intentional no-ops; this just guards against regressions/crashes.
    }

    // MARK: - DeviceClass

    @Test func stopConnectionActionReleasesConnector() {
        let device = DeviceClass()
        device.connector = DeviceConnector(
            address: GroupAddress(dataAddress: "10.0.0.1", commandAddress: "10.0.0.2"),
            port: GroupPort(dataMultiPort: .zero(), commandMultiPort: .zero()),
            user: "u", password: "p", delegate: nil, deviceInfo: nil, scheme: "https"
        )

        device.stopConnectionAction()

        #expect(device.connector == nil)
    }

    // MARK: - HttpRequest housekeeping

    @Test func doJsonRequestIgnoresInvalidURL() {
        // Use an isolated instance so the shared singleton is not touched.
        let request = HttpRequest()
        let target = NoopHttpRequestTarget()
        request.doJsonRequest(
            token: nil,
            url: "not a valid url",
            method: .get,
            callbackID: .getVideoInfo,
            target: target
        )
        // Invalid URL is rejected before any request is made.
        #expect(target.finished == 0)
        #expect(target.failed == 0)
    }

    @Test func housekeepingCallsAreSafe() {
        let request = HttpRequest()
        request.cleanCamCheck()
        request.destroySharedInstance()
    }
}
