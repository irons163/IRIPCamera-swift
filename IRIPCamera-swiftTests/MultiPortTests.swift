//
//  MultiPortTests.swift
//  IRIPCamera-swiftTests
//
//  Covers the `MultiPort` value type and the grouping structs it lives in.
//

import Testing
@testable import IRIPCamera_swift

struct MultiPortTests {

    @Test func zeroIsAllZeros() {
        let port = MultiPort.zero()
        #expect(port.httpsPort == 0)
        #expect(port.videoPort == 0)
        #expect(port.audioPort == 0)
        #expect(port.normalPort == 0)
    }

    @Test func initialUsesConfiguredConstants() {
        let port = MultiPort.initial()
        #expect(port.httpsPort == HTTPS_APP_COMMAND_PORT)
        #expect(port.videoPort == VIDEO_PORT)
        #expect(port.audioPort == AUDIO_PORT)
        #expect(port.normalPort == NORMAL_PORT)
    }

    @Test func equatableComparesEveryField() {
        let base = MultiPort(httpsPort: 1, videoPort: 2, audioPort: 3, normalPort: 4)
        #expect(base == MultiPort(httpsPort: 1, videoPort: 2, audioPort: 3, normalPort: 4))
        #expect(base != MultiPort(httpsPort: 9, videoPort: 2, audioPort: 3, normalPort: 4))
        #expect(base != MultiPort(httpsPort: 1, videoPort: 2, audioPort: 3, normalPort: 9))
    }

    @Test func groupingStructsPreservePorts() {
        let data = MultiPort(httpsPort: 1, videoPort: 2, audioPort: 3, normalPort: 4)
        let command = MultiPort.zero()
        let group = GroupPort(dataMultiPort: data, commandMultiPort: command)
        #expect(group.dataMultiPort == data)
        #expect(group.commandMultiPort == command)

        let address = GroupAddress(dataAddress: "10.0.0.1", commandAddress: "10.0.0.2")
        #expect(address.dataAddress == "10.0.0.1")
        #expect(address.commandAddress == "10.0.0.2")
    }
}
