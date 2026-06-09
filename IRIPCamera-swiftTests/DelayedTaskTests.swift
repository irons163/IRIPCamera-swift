//
//  DelayedTaskTests.swift
//  IRIPCamera-swiftTests
//
//  Covers the scheduling / cancellation behaviour of `DelayedTask`.
//

import Foundation
import Testing
@testable import IRIPCamera_swift

@MainActor
struct DelayedTaskTests {

    @Test func runsScheduledWorkAfterDelay() async {
        let task = DelayedTask()

        let didRun: Bool = await withCheckedContinuation { continuation in
            task.schedule(after: 0.02) {
                continuation.resume(returning: true)
            }
        }

        #expect(didRun)
    }

    @Test func cancelPreventsExecution() async throws {
        let task = DelayedTask()
        var ran = false

        task.schedule(after: 0.05) { ran = true }
        task.cancel()

        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(ran == false)
    }

    @Test func reschedulingCancelsPreviousWork() async throws {
        let task = DelayedTask()
        var firstRan = false
        var secondRan = false

        task.schedule(after: 0.05) { firstRan = true }
        task.schedule(after: 0.05) { secondRan = true }

        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(firstRan == false)
        #expect(secondRan == true)
    }
}
