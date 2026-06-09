//
//  DeviceConnectorTests.swift
//  IRIPCamera-swiftTests
//
//  Covers `DeviceConnector` login guard and delegate forwarding.
//

import Foundation
import Testing
@testable import IRIPCamera_swift

private final class SpyDeviceConnectorDelegate: DeviceConnectorDelegate {
    struct LoginAction {
        let resultType: Int
        let errorDesc: String
        let address: String
        let deviceInfo: [String: Any]?
    }

    private let lock = NSLock()
    private var _loginActions: [LoginAction] = []
    var loginActions: [LoginAction] {
        lock.lock(); defer { lock.unlock() }
        return _loginActions
    }

    func didFinishLoginAction(resultType: Int, deviceInfo: [String : Any]?, errorDesc: String, address: String, port: MultiPort) {
        lock.lock(); defer { lock.unlock() }
        _loginActions.append(LoginAction(resultType: resultType, errorDesc: errorDesc, address: address, deviceInfo: deviceInfo))
    }

    // Required members without protocol defaults.
    func didGetRTSPResponse(resultCode: Int, message: String) {}
    func didGetRTSPUrlResult(resultCode: Int, message: String, channel: Int, url: String, ipRatio: Int) {}
    func didGetTwoWayAudioResponse(resultCode: Int, message: String) {}
    func didGetTwoWayAudioResult(resultCode: Int, url: String, type: String, sampleRate: Int, bps: Int) {}
}

struct DeviceConnectorTests {

    private func makeConnector(delegate: DeviceConnectorDelegate) -> DeviceConnector {
        DeviceConnector(
            address: GroupAddress(dataAddress: "", commandAddress: ""),
            port: GroupPort(dataMultiPort: .zero(), commandMultiPort: .zero()),
            user: "",
            password: "",
            delegate: delegate,
            deviceInfo: nil,
            scheme: "https"
        )
    }

    @Test func loginFailsWhenNoConnectorAvailable() async throws {
        let delegate = SpyDeviceConnectorDelegate()
        let connector = makeConnector(delegate: delegate)

        connector.loginToDevice(getRTSPInfo: true, checkPrevious: false, ignoreLoginCache: true)
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(delegate.loginActions.map(\.resultType) == [-1])
        #expect(delegate.loginActions.first?.errorDesc == "Connect failed")
    }

    @Test func checkOnlineStatusFailsWhenNoConnectorAvailable() async throws {
        let delegate = SpyDeviceConnectorDelegate()
        let connector = makeConnector(delegate: delegate)

        connector.startCheckOnlineStatus()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(delegate.loginActions.map(\.resultType) == [-1])
    }

    @Test func loginResultIsForwardedToDelegate() {
        let delegate = SpyDeviceConnectorDelegate()
        let connector = makeConnector(delegate: delegate)
        let caller = HttpAPICommander(address: "", port: .zero(), user: "", password: "", scheme: "https")

        connector.didLoginResult(
            resultCode: 0,
            message: "ok",
            caller: caller,
            info: ["ModelName": "Cam"],
            address: "1.2.3.4",
            port: .zero()
        )

        #expect(delegate.loginActions.count == 1)
        let action = delegate.loginActions.first
        #expect(action?.resultType == 0)
        #expect(action?.errorDesc == "ok")
        #expect(action?.address == "1.2.3.4")
        #expect(action?.deviceInfo?["ModelName"] as? String == "Cam")
    }
}
