//
//  CustomStreamConnectorTests.swift
//  IRIPCamera-swiftTests
//
//  Covers `IRCustomStreamConnector`'s device-connector delegate reactions
//  while no live `DeviceConnector` is attached.
//

import Testing
@testable import IRIPCamera_swift

private final class SpyConnectorDelegate: IRStreamConnectorDelegate {
    private(set) var startedResponses: [IRStreamConnectionResponse?] = []
    private(set) var failures: [ConnectorErrorType] = []

    func connectFail(byType type: ConnectorErrorType, errorDesc: String?) {
        failures.append(type)
    }
    func startStreaming(with response: IRStreamConnectionResponse?) {
        startedResponses.append(response)
    }
}

struct CustomStreamConnectorTests {

    private func makeConnector() -> (IRCustomStreamConnector, SpyConnectorDelegate) {
        let connector = IRCustomStreamConnector()
        connector.deviceInfo = DeviceClass()
        connector.response = IRStreamConnectionResponse()
        let delegate = SpyConnectorDelegate()
        connector.delegate = delegate
        return (connector, delegate)
    }

    @Test func rtspResponseIncrementsRetryWithoutConnector() {
        let (connector, _) = makeConnector()
        connector.didGetRTSPResponse(resultCode: 0, message: "")
        #expect(connector.videoRetry == 1)
    }

    @Test func successfulLoginRecordsModelName() {
        let (connector, _) = makeConnector()
        connector.didFinishLoginAction(resultType: 0, deviceInfo: ["ModelName": "Cam"], errorDesc: "", address: "", port: .zero())
        #expect(connector.response?.deviceModelName == "Cam")
    }

    @Test func loginTimeoutReportsConnectFail() {
        let (connector, delegate) = makeConnector()
        connector.didFinishLoginAction(resultType: -1, deviceInfo: nil, errorDesc: "x", address: "", port: .zero())
        #expect(delegate.failures == [.connectionTimeout])
    }

    @Test func rtspURLResultStartsStreaming() {
        let (connector, delegate) = makeConnector()
        connector.didGetRTSPUrlResult(resultCode: 0, message: "", channel: 0, url: "rtsp://ok", ipRatio: 0)
        #expect(delegate.startedResponses.count == 1)
        #expect(connector.response?.rtspURL == "rtsp://ok")
    }

    @Test func rtspURLFailureIsIgnored() {
        let (connector, delegate) = makeConnector()
        connector.didGetRTSPUrlResult(resultCode: -1, message: "", channel: 0, url: "rtsp://x", ipRatio: 0)
        #expect(delegate.startedResponses.isEmpty)
    }

    @Test func twoWayAudioCallbacksAreSafeWithoutConnector() {
        let (connector, _) = makeConnector()
        connector.didGetTwoWayAudioResponse(resultCode: 0, message: "")
        connector.didGetTwoWayAudioResult(resultCode: 0, url: "", type: "", sampleRate: 0, bps: 0)
        connector.changeStream(1)
        connector.stopStreaming(false)
        // No connector attached: nothing should crash.
    }
}
