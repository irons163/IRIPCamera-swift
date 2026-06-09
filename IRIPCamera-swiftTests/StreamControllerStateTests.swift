//
//  StreamControllerStateTests.swift
//  IRIPCamera-swiftTests
//
//  Covers `IRStreamController`'s playback state machine and connector-delegate
//  reactions. The IRPlayer-typed `updatedVideoModes` callback is intentionally
//  left to its protocol default so the test target needs no IRPlayer import.
//

import Foundation
import Testing
@testable import IRIPCamera_swift

private final class SpyControllerDelegate: IRStreamControllerDelegate {
    private let lock = NSLock()
    private var _statuses: [IRStreamControllerStatus] = []
    private var _errors: [String] = []
    private var _connectResults: [Bool] = []

    var statuses: [IRStreamControllerStatus] { lock.lock(); defer { lock.unlock() }; return _statuses }
    var errors: [String] { lock.lock(); defer { lock.unlock() }; return _errors }
    var connectResults: [Bool] { lock.lock(); defer { lock.unlock() }; return _connectResults }

    func connectResult(_ videoView: Any, connection: Bool, micSupport: Bool, speakerSupport: Bool) {
        lock.lock(); _connectResults.append(connection); lock.unlock()
    }
    func showErrorMessage(_ msg: String) {
        lock.lock(); _errors.append(msg); lock.unlock()
    }
    func streamControllerStatusChanged(_ status: IRStreamControllerStatus) {
        lock.lock(); _statuses.append(status); lock.unlock()
    }
    // updatedVideoModes(_:) intentionally uses the protocol default.
}

@MainActor
struct StreamControllerStateTests {

    private func waitUntil(timeout: TimeInterval = 1.0, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makeRTSPController() -> (IRStreamController, SpyControllerDelegate) {
        let controller = IRStreamController(rtspURL: "rtsp://example/live")
        let delegate = SpyControllerDelegate()
        controller.eventDelegate = delegate
        return (controller, delegate)
    }

    private func makeDeviceController() -> (IRStreamController, SpyControllerDelegate) {
        let controller = IRStreamController(device: DeviceClass())
        let delegate = SpyControllerDelegate()
        controller.eventDelegate = delegate
        return (controller, delegate)
    }

    // MARK: - State machine

    @Test func bufferingStateReportsBufferingStatus() {
        let (controller, delegate) = makeRTSPController()
        controller.handle(playbackState: .buffering)
        #expect(delegate.statuses == [.buffering])
    }

    @Test func playingStateReportsPlayingStatus() {
        let (controller, delegate) = makeRTSPController()
        controller.handle(playbackState: .playing)
        #expect(delegate.statuses == [.playing])
    }

    @Test func otherStateIsIgnored() {
        let (controller, delegate) = makeRTSPController()
        controller.handle(playbackState: .other)
        #expect(delegate.statuses.isEmpty)
        #expect(delegate.errors.isEmpty)
        #expect(delegate.connectResults.isEmpty)
    }

    @Test func readyToPlayReportsSuccessfulConnection() async {
        let (controller, delegate) = makeRTSPController()
        controller.handle(playbackState: .readyToPlay)
        await waitUntil { !delegate.connectResults.isEmpty }
        #expect(delegate.connectResults == [true])
    }

    @Test func stateActionWithEmptyUserInfoIsNoOp() {
        let (controller, delegate) = makeRTSPController()
        controller.stateAction(Notification(name: .init("test"), object: nil, userInfo: [:]))
        #expect(delegate.statuses.isEmpty)
        #expect(delegate.connectResults.isEmpty)
    }

    // MARK: - Connector delegate reactions

    @Test func startStreamConnectionAnnouncesPreparing() {
        let (controller, delegate) = makeRTSPController()
        controller.startStreamConnection()
        #expect(delegate.statuses == [.preparingToPlay])
    }

    @Test func connectFailShowsErrorAndReportsDisconnect() async {
        let (controller, delegate) = makeRTSPController()
        controller.connectFail(byType: ConnectorErrorType.authorizationError, errorDesc: nil)
        #expect(delegate.errors.count == 1)
        await waitUntil { !delegate.connectResults.isEmpty }
        #expect(delegate.connectResults == [false])
    }

    // MARK: - Reconnect (failed state)

    @Test func failedStateTriggersReconnect() async {
        let (controller, delegate) = makeDeviceController()
        controller.handle(playbackState: .failed)
        // Reconnect drives a login attempt that fails (no reachable device),
        // surfacing an error message back through the delegate.
        await waitUntil { !delegate.errors.isEmpty }
        #expect(!delegate.errors.isEmpty)
    }

    @Test func failedStateDoesNotReconnectAfterStop() async {
        let (controller, delegate) = makeDeviceController()
        controller.stopStreaming(stopForever: true)
        controller.handle(playbackState: .failed)
        // Give any erroneous reconnect a chance to surface, then assert none did.
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(delegate.errors.isEmpty)
    }

    @Test func videoLossTriggersReconnect() async {
        let (controller, delegate) = makeDeviceController()
        controller.videoLoss(withErrorCode: 1, msg: "lost")
        await waitUntil { !delegate.errors.isEmpty }
        #expect(!delegate.errors.isEmpty)
    }

    // MARK: - Connector error mapping

    @Test func connectFailMapsEveryErrorType() {
        let (controller, delegate) = makeRTSPController()
        controller.connectFail(byType: ConnectorErrorType.authorizationError, errorDesc: nil)
        controller.connectFail(byType: ConnectorErrorType.notSupported, errorDesc: nil)
        controller.connectFail(byType: ConnectorErrorType.connectionTimeout, errorDesc: nil)
        // Each type produces exactly one (non-empty) user-facing message.
        #expect(delegate.errors.count == 3)
        #expect(delegate.errors.allSatisfy { !$0.isEmpty })
    }

    @Test func legacyConnectFailForwardsRawDescription() {
        let (controller, delegate) = makeRTSPController()
        controller.connectFail(byType: 5, errorDesc: "boom")
        #expect(delegate.errors == ["boom"])
    }

    // MARK: - startStreaming branches

    @Test func startStreamingWithoutURLReportsDisconnect() async {
        let (controller, delegate) = makeRTSPController()
        controller.startStreaming(with: IRStreamConnectionResponse())
        await waitUntil { !delegate.connectResults.isEmpty }
        #expect(delegate.connectResults == [false])
    }

    @Test func startStreamingFisheyeWithoutURLReportsDisconnect() async {
        let (controller, delegate) = makeRTSPController()
        let response = IRStreamConnectionResponse()
        response.deviceModelName = "FisheyeCAM"
        controller.startStreaming(with: response)
        await waitUntil { !delegate.connectResults.isEmpty }
        #expect(delegate.connectResults == [false])
    }

    // MARK: - Render modes / change stream

    @Test func renderModeAccessorsAreSafeWithoutVideoView() {
        let (controller, _) = makeRTSPController()
        #expect(controller.getRenderModes().isEmpty)
        #expect(controller.getCurrentRenderMode() == nil)

        // createFisheyeModes builds the full fisheye mode set.
        let modes = controller.createFisheyeModes(with: nil)
        #expect(modes.count == 4)

        // Setting a mode without a video view must not crash.
        if let first = modes.first {
            controller.setCurrentRenderMode(first)
        }
    }

    @Test func changeStreamReportsDisconnect() async {
        let (controller, delegate) = makeRTSPController()
        controller.changeStream(1)
        await waitUntil { !delegate.connectResults.isEmpty }
        #expect(delegate.connectResults == [false])
    }
}
