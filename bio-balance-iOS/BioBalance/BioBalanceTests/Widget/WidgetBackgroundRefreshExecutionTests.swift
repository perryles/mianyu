import XCTest
@testable import BioBalance

nonisolated final class WidgetBackgroundRefreshExecutionTests: XCTestCase {
    @MainActor func testSuccessPublishesAndCompletesOnlyOnce() async throws {
        var results: [Bool] = []
        var publishCount = 0
        let execution = WidgetBackgroundRefreshExecution { results.append($0) }
        let work = try XCTUnwrap(execution.start(operation: {}, publish: { publishCount += 1 }))
        await work.value
        execution.expire()
        execution.expire()
        XCTAssertEqual(results, [true])
        XCTAssertEqual(publishCount, 1)
        XCTAssertTrue(execution.isFinished)
        XCTAssertNil(execution.start(operation: {}, publish: { publishCount += 1 }))
    }

    @MainActor func testExpirationBeforeStartingDoesNotRunWork() {
        var results: [Bool] = []
        let execution = WidgetBackgroundRefreshExecution { results.append($0) }
        execution.expire()
        execution.expire()
        XCTAssertNil(execution.start(operation: { XCTFail("Expired operation ran") }, publish: { XCTFail("Expired operation published") }))
        XCTAssertEqual(results, [false])
    }

    @MainActor func testExpirationCancelsSuspendedWorkAndSuppressesLateSuccess() async throws {
        var results: [Bool] = []
        var continuation: CheckedContinuation<Void, Never>?
        var observedCancellation = false
        var publishCount = 0
        let started = expectation(description: "Operation suspended")
        let execution = WidgetBackgroundRefreshExecution { results.append($0) }
        let work = try XCTUnwrap(execution.start {
            await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
            observedCancellation = Task.isCancelled
        } publish: {
            publishCount += 1
        })
        await fulfillment(of: [started], timeout: 2)
        execution.expire()
        execution.expire()
        XCTAssertEqual(results, [false])
        continuation?.resume()
        await work.value
        XCTAssertTrue(observedCancellation)
        XCTAssertEqual(publishCount, 0)
        XCTAssertEqual(results, [false])
    }

    @MainActor func testCancellationBeforeWorkStartsCompletesAsFailure() async throws {
        var results: [Bool] = []
        let execution = WidgetBackgroundRefreshExecution { results.append($0) }
        let work = try XCTUnwrap(execution.start(operation: { XCTFail("Cancelled operation ran") }, publish: { XCTFail("Cancelled operation published") }))
        work.cancel()
        await work.value
        execution.expire()
        XCTAssertEqual(results, [false])
        XCTAssertTrue(execution.isFinished)
    }

    @MainActor func testDuplicateStartIsIgnored() async throws {
        var count = 0
        let execution = WidgetBackgroundRefreshExecution { _ in }
        let work = try XCTUnwrap(execution.start(operation: {}, publish: { count += 1 }))
        XCTAssertNil(execution.start(operation: {}, publish: { count += 1 }))
        await work.value
        XCTAssertEqual(count, 1)
    }

    func testRegistrationUsesMainQueueAndExpirationHasAnUnisolatedEntry() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("BioBalance/Core/BioBalanceAppDelegate.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("using: .main"))
        XCTAssertTrue(source.contains("expirationHandler = { @Sendable in"))
        XCTAssertTrue(source.contains("task.expirationHandler = nil"))
    }
}
