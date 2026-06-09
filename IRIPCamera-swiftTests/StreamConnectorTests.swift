//
//  StreamConnectorTests.swift
//  IRIPCamera-swiftTests
//
//  Covers the base `IRStreamConnector` delegate contract.
//

import Testing
@testable import IRIPCamera_swift

private final class SpyConnectorDelegate: IRStreamConnectorDelegate {
    private(set) var startedResponses: [IRStreamConnectionResponse?] = []
    private(set) var failures: [(type: ConnectorErrorType, desc: String?)] = []

    func connectFail(byType type: ConnectorErrorType, errorDesc: String?) {
        failures.append((type, errorDesc))
    }

    func startStreaming(with response: IRStreamConnectionResponse?) {
        startedResponses.append(response)
    }
}

struct StreamConnectorTests {

    @Test func startStreamConnectionForwardsRTSPURLToDelegate() {
        let connector = IRStreamConnector()
        let delegate = SpyConnectorDelegate()
        connector.delegate = delegate
        connector.rtspURL = "rtsp://camera/live"
        connector.videoRetry = 7

        connector.startStreamConnection()

        #expect(delegate.startedResponses.count == 1)
        #expect(connector.response?.rtspURL == "rtsp://camera/live")
        #expect(delegate.startedResponses.first??.rtspURL == "rtsp://camera/live")
        // videoRetry must be reset on every fresh connection attempt.
        #expect(connector.videoRetry == 0)
    }

    @Test func startStreamConnectionWithoutDelegateStillBuildsResponse() {
        let connector = IRStreamConnector()
        connector.rtspURL = "rtsp://camera/2"

        connector.startStreamConnection()

        #expect(connector.response?.rtspURL == "rtsp://camera/2")
    }

    @Test func baseStopAndChangeStreamAreNoOps() {
        let connector = IRStreamConnector()
        let delegate = SpyConnectorDelegate()
        connector.delegate = delegate

        connector.stopStreaming(true)
        connector.changeStream(2)

        #expect(delegate.startedResponses.isEmpty)
        #expect(delegate.failures.isEmpty)
    }
}
