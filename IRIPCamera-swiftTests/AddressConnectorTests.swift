//
//  AddressConnectorTests.swift
//  IRIPCamera-swiftTests
//
//  Exercises the retry / failure escalation in `AddressConnector` using an
//  injected mock HTTP client (no real networking).
//

import Testing
@testable import IRIPCamera_swift

/// Records issued requests instead of hitting the network.
private final class MockHttpRequest: HttpRequesting {
    private(set) var requests: [(url: String, callbackID: DeviceConnectorCommandStatus)] = []

    func doJsonRequest(
        token: String?,
        url: String,
        method: HttpRequestMethod,
        callbackID: DeviceConnectorCommandStatus,
        target: HttpRequestDelegate
    ) {
        requests.append((url, callbackID))
    }

    func count(of callbackID: DeviceConnectorCommandStatus) -> Int {
        requests.filter { $0.callbackID == callbackID }.count
    }
}

private final class SpyCommanderDelegate: HttpAPICommanderDelegate {
    private(set) var loginResults: [Int] = []
    private(set) var rtspResponses: [Int] = []
    private(set) var twoWayResults: [Int] = []
    private(set) var rtspURLChannels: [Int] = []

    func failedAfterRetry(_ caller: HttpAPICommander) {}
    func didLoginResult(resultCode: Int, message: String, caller: HttpAPICommander, info: [String : Any]?, address: String, port: MultiPort) {
        loginResults.append(resultCode)
    }
    func didGetRTSPResponse(resultCode: Int, message: String) {
        rtspResponses.append(resultCode)
    }
    func didGetRtspURLByChannel(resultCode: Int, message: String?, channel: Int, url: String, ipRatio: Int) {
        rtspURLChannels.append(channel)
    }
    func didGetTwoWayAudioResponse(resultCode: Int, message: String) {}
    func didGetTwoWayAudioResult(resultCode: Int, url: String?, type: String?, sampleRate: Int, bps: Int) {
        twoWayResults.append(resultCode)
    }
    func didReportFileDownloadPort(resultCode: Int, message: String, port: Int) {}
    func didInTheSameLAN(deviceAddress: String, port: MultiPort) {}
}

struct AddressConnectorTests {

    private func makeConnector() -> (AddressConnector, MockHttpRequest, SpyCommanderDelegate) {
        let connector = AddressConnector(address: "10.0.0.1", port: .zero(), user: "u", password: "p", scheme: "https")
        let mock = MockHttpRequest()
        let delegate = SpyCommanderDelegate()
        connector.httpRequest = mock
        connector.delegate = delegate
        return (connector, mock, delegate)
    }

    @Test func videoInfoRetriesThreeTimesThenFails() {
        let (connector, mock, delegate) = makeConnector()

        // Four consecutive failures: 3 retries, then escalate to the delegate.
        for _ in 0..<4 {
            connector.failToStaticRequest(errorCode: 500, description: "boom", callbackID: .getVideoInfo)
        }

        #expect(mock.count(of: .getVideoInfo) == 3)
        #expect(delegate.rtspResponses == [-2])
    }

    @Test func twoWayAudioRetriesThreeTimesThenFails() {
        let (connector, mock, delegate) = makeConnector()

        for _ in 0..<4 {
            connector.failToStaticRequest(errorCode: 500, description: "boom", callbackID: .getTwoWayAudioInfo)
        }

        #expect(mock.count(of: .getTwoWayAudioInfo) == 3)
        #expect(delegate.twoWayResults == [-1])
    }

    @Test func loginRetriesThreeTimesThenFails() {
        let (connector, mock, delegate) = makeConnector()

        for _ in 0..<4 {
            connector.failToStaticRequest(errorCode: 401, description: "auth", callbackID: .doDeviceLogin)
        }

        // Login retries do not go through the JSON request helper.
        #expect(mock.requests.isEmpty)
        #expect(delegate.loginResults == [-1])
    }

    @Test func getVideoStreamURLReportsThroughDelegate() {
        let (connector, _, delegate) = makeConnector()

        connector.getVideoStreamURL(byChannel: 2)

        // The base address connector reports channel 0 with an empty URL.
        #expect(delegate.rtspURLChannels == [0])
    }

    @Test func failureIsIgnoredAfterCancellation() {
        let (connector, mock, delegate) = makeConnector()
        connector.cancelLoginToDevice() // sets stopConnection = true

        connector.failToStaticRequest(errorCode: 500, description: "boom", callbackID: .getVideoInfo)

        #expect(mock.requests.isEmpty)
        #expect(delegate.rtspResponses.isEmpty)
        #expect(connector.retryTime == 0)
    }
}
