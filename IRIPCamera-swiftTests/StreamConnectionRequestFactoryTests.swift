//
//  StreamConnectionRequestFactoryTests.swift
//  IRIPCamera-swiftTests
//
//  Verifies how `IRStreamConnectionRequestFactory` turns persisted settings
//  into stream connection requests.
//

import Foundation
import Testing
@testable import IRIPCamera_swift

struct StreamConnectionRequestFactoryTests {

    /// Builds an isolated `UserDefaults` so tests never touch the real domain.
    private func makeDefaults() -> UserDefaults {
        let suite = "RequestFactoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func returnsCustomRequestWhenRTSPDisabled() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: ENABLE_RTSP_URL_KEY)

        let requests = IRStreamConnectionRequestFactory.createStreamConnectionRequest(userDefaults: defaults)

        #expect(requests.count == 1)
        #expect(requests.first is IRCustomStreamConnectionRequest)
    }

    @Test func defaultsToCustomRequestWhenNothingConfigured() {
        let defaults = makeDefaults()

        let requests = IRStreamConnectionRequestFactory.createStreamConnectionRequest(userDefaults: defaults)

        #expect(requests.count == 1)
        #expect(requests.first is IRCustomStreamConnectionRequest)
    }

    @Test func collectsEnabledNonEmptyURLs() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: ENABLE_RTSP_URL_KEY)
        defaults.set("rtsp://a", forKey: RTSP_URL_KEY)
        defaults.set("rtsp://b", forKey: RTSP_URL_KEY_2)
        defaults.set("rtsp://c", forKey: RTSP_URL_KEY_3)
        defaults.set("rtsp://d", forKey: RTSP_URL_KEY_4)

        let requests = IRStreamConnectionRequestFactory.createStreamConnectionRequest(userDefaults: defaults)

        #expect(requests.count == 4)
        #expect(requests.map(\.rtspUrl) == ["rtsp://a", "rtsp://b", "rtsp://c", "rtsp://d"])
        #expect(requests.allSatisfy { !($0 is IRCustomStreamConnectionRequest) })
    }

    @Test func skipsDisabledSlots() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: ENABLE_RTSP_URL_KEY)
        defaults.set("rtsp://a", forKey: RTSP_URL_KEY)
        defaults.set("rtsp://b", forKey: RTSP_URL_KEY_2)
        defaults.set(false, forKey: RTSP_URL_ENABLE_KEY_2)

        let requests = IRStreamConnectionRequestFactory.createStreamConnectionRequest(userDefaults: defaults)

        #expect(requests.map(\.rtspUrl) == ["rtsp://a"])
    }

    @Test func skipsEmptyAndWhitespaceURLs() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: ENABLE_RTSP_URL_KEY)
        defaults.set("", forKey: RTSP_URL_KEY)
        defaults.set("   \n ", forKey: RTSP_URL_KEY_2)
        defaults.set("  rtsp://trim  ", forKey: RTSP_URL_KEY_3)

        let requests = IRStreamConnectionRequestFactory.createStreamConnectionRequest(userDefaults: defaults)

        #expect(requests.map(\.rtspUrl) == ["rtsp://trim"])
    }

    @Test func slotsAreEnabledByDefaultWhenFlagAbsent() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: ENABLE_RTSP_URL_KEY)
        defaults.set("rtsp://a", forKey: RTSP_URL_KEY)
        // No enable flag set for slot 1 -> should default to enabled.

        let requests = IRStreamConnectionRequestFactory.createStreamConnectionRequest(userDefaults: defaults)

        #expect(requests.map(\.rtspUrl) == ["rtsp://a"])
    }
}
