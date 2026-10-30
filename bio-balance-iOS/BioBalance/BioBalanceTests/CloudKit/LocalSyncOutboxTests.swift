import Foundation
import SwiftData
import XCTest
@testable import BioBalance

/// LocalSyncOutbox（PEN-15 出站队列）单元测试。
///
/// 全部使用内存 SwiftData 容器 + 独立 UserDefaults suite，离线运行，
/// 不依赖 CloudKit / HealthKit / 真实网络。覆盖：
/// 入队/幂等/替换、pending 取数、租约领取与过期、ACK 删除、失败重试与退避、
/// 队列上限、解码校验、旧版 UserDefaults 迁移与损坏存储降级。
nonisolated final class LocalSyncOutboxTests: XCTestCase {

    private struct Fixture {
        let container: ModelContainer
        let defaults: UserDefaults
        let suiteName: String
    }

    @MainActor private func makeFixture() throws -> Fixture {
        let suiteName = "LocalSyncOutboxTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return Fixture(
            container: try MianyuModelContainer.make(isStoredInMemoryOnly: true),
            defaults: defaults,
            suiteName: suiteName
        )
    }

    @MainActor private func makeItem(
        recordType: LocalSyncOutboxRecordType = .userEvent,
        recordID: String = "record-1",
        schemaVersion: Int = 1,
        payload: Data = Data("payload".utf8),
        attemptCount: Int = 0,
        createdAt: Date = Date(timeIntervalSince1970: 1_730_000_000),
        nextAttemptAt: Date = Date(timeIntervalSince1970: 1_730_000_000)
    ) -> LocalSyncOutboxItem {
        LocalSyncOutboxItem(
            id: LocalSyncOutboxItem.makeID(recordType: recordType, recordID: recordID),
            revision: UUID().uuidString,
            recordType: recordType,
            recordID: recordID,
            schemaVersion: schemaVersion,
            payload: payload,
            createdAt: createdAt,
            updatedAt: createdAt,
            attemptCount: attemptCount,
            nextAttemptAt: nextAttemptAt,
            tombstone: false
        )
    }

    // MARK: - 入队

    @MainActor func testEnqueueRejectsRetiredHealthSnapshotRecordType() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)

        let result = outbox.enqueue(
            recordType: .healthSnapshot,
            recordID: "2026-08-08",
            schemaVersion: 2,
            payload: Data("local-health-snapshot".utf8)
        )

        XCTAssertEqual(result, .rejected(.retiredRecordType))
        XCTAssertEqual(outbox.count(), 0)
    }

    @MainActor func testDailyHealthSnapshotSaveDoesNotEnqueueCloudPayload() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let store = DailyDeterministicHealthSnapshotStore(
            defaults: fixture.defaults,
            container: fixture.container
        )
        let now = Date(timeIntervalSince1970: 1_754_640_000)
        let snapshot = DailyDeterministicHealthSnapshot(
            schemaVersion: DailyDeterministicHealthSnapshot.currentSchemaVersion,
            date: now,
            generatedAt: now,
            engineVersions: .current,
            metrics: []
        )

        _ = store.save(snapshot)

        XCTAssertEqual(store.latest(), snapshot)
        XCTAssertEqual(outbox.count(), 0)
    }

    @MainActor func testEnqueueCreatesItemWithStableIDAndZeroAttempts() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)

        let result = outbox.enqueue(
            recordType: .userEvent,
            recordID: "sleep-1",
            schemaVersion: 2,
            payload: Data("summary".utf8),
            now: now
        )

        guard case let .enqueued(item) = result else {
            return XCTFail("Expected enqueued, got \(result)")
        }
        XCTAssertEqual(item.id, "BBUserEvent:sleep-1")
        XCTAssertEqual(item.recordType, .userEvent)
        XCTAssertEqual(item.recordID, "sleep-1")
        XCTAssertEqual(item.schemaVersion, 2)
        XCTAssertEqual(item.payload, Data("summary".utf8))
        XCTAssertEqual(item.attemptCount, 0)
        XCTAssertEqual(item.nextAttemptAt, now)
        XCTAssertEqual(item.createdAt, now)
        XCTAssertFalse(item.tombstone)
        XCTAssertFalse(item.revision.isEmpty)
        XCTAssertEqual(outbox.count(), 1)
        XCTAssertEqual(outbox.storageState(), .healthy(itemCount: 1))
    }

    @MainActor func testEnqueueIdenticalItemReturnsUnchanged() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let payload = Data("payload".utf8)

        let first = outbox.enqueue(
            recordType: .userEvent,
            recordID: "event-1",
            schemaVersion: 1,
            payload: payload,
            now: now
        )
        guard case let .enqueued(original) = first else {
            return XCTFail("Expected enqueued")
        }

        let second = outbox.enqueue(
            recordType: .userEvent,
            recordID: "event-1",
            schemaVersion: 1,
            payload: payload,
            now: now.addingTimeInterval(10)
        )

        guard case let .unchanged(same) = second else {
            return XCTFail("Expected unchanged, got \(second)")
        }
        XCTAssertEqual(same, original)
        XCTAssertEqual(outbox.count(), 1)
    }

    @MainActor func testEnqueueSameIDWithNewPayloadReplacesAndKeepsCreatedAt() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)

        let first = outbox.enqueue(
            recordType: .userEvent,
            recordID: "record-1",
            schemaVersion: 1,
            payload: Data("v1".utf8),
            now: now
        )
        guard case let .enqueued(original) = first else {
            return XCTFail("Expected enqueued")
        }

        let second = outbox.enqueue(
            recordType: .userEvent,
            recordID: "record-1",
            schemaVersion: 1,
            payload: Data("v2".utf8),
            now: now.addingTimeInterval(60)
        )
        guard case let .enqueued(replaced) = second else {
            return XCTFail("Expected enqueued replacement, got \(second)")
        }

        XCTAssertEqual(replaced.id, original.id)
        XCTAssertNotEqual(replaced.revision, original.revision)
        XCTAssertEqual(replaced.createdAt, original.createdAt)
        XCTAssertEqual(replaced.updatedAt, now.addingTimeInterval(60))
        XCTAssertEqual(replaced.attemptCount, 0)
        XCTAssertEqual(replaced.payload, Data("v2".utf8))
        XCTAssertEqual(outbox.count(), 1)
    }

    @MainActor func testEnqueueSameIDWithDifferentSchemaVersionReplaces() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)

        _ = outbox.enqueue(
            recordType: .userEvent,
            recordID: "record-1",
            schemaVersion: 1,
            payload: Data("v1".utf8),
            now: now
        )
        let result = outbox.enqueue(
            recordType: .userEvent,
            recordID: "record-1",
            schemaVersion: 2,
            payload: Data("v1".utf8),
            now: now.addingTimeInterval(60)
        )

        guard case let .enqueued(replaced) = result else {
            return XCTFail("Expected enqueued replacement, got \(result)")
        }
        XCTAssertEqual(replaced.schemaVersion, 2)
        XCTAssertEqual(outbox.count(), 1)
    }

    @MainActor func testEnqueueTombstoneToggleReplaces() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)

        _ = outbox.enqueue(
            recordType: .userEvent,
            recordID: "record-1",
            schemaVersion: 1,
            payload: Data("v1".utf8),
            tombstone: false,
            now: now
        )
        let result = outbox.enqueue(
            recordType: .userEvent,
            recordID: "record-1",
            schemaVersion: 1,
            payload: Data("v1".utf8),
            tombstone: true,
            now: now.addingTimeInterval(60)
        )

        guard case let .enqueued(replaced) = result else {
            return XCTFail("Expected enqueued tombstone replacement, got \(result)")
        }
        XCTAssertTrue(replaced.tombstone)
        XCTAssertEqual(outbox.count(), 1)
    }

    @MainActor func testEnqueueRejectsInvalidRecordID() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)

        let empty = outbox.enqueue(
            recordType: .userEvent,
            recordID: "",
            schemaVersion: 1,
            payload: Data("x".utf8),
            now: now
        )
        XCTAssertEqual(empty, .rejected(.invalidRecordID))

        let whitespace = outbox.enqueue(
            recordType: .userEvent,
            recordID: "   ",
            schemaVersion: 1,
            payload: Data("x".utf8),
            now: now
        )
        XCTAssertEqual(whitespace, .rejected(.invalidRecordID))

        let tooLong = String(repeating: "a", count: 256)
        let oversizedID = outbox.enqueue(
            recordType: .userEvent,
            recordID: tooLong,
            schemaVersion: 1,
            payload: Data("x".utf8),
            now: now
        )
        XCTAssertEqual(oversizedID, .rejected(.invalidRecordID))
        XCTAssertEqual(outbox.count(), 0)
    }

    @MainActor func testEnqueueRejectsInvalidSchemaVersion() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)

        XCTAssertEqual(
            outbox.enqueue(
                recordType: .userEvent,
                recordID: "r1",
                schemaVersion: 0,
                payload: Data("x".utf8),
                now: now
            ),
            .rejected(.invalidSchemaVersion)
        )
        XCTAssertEqual(
            outbox.enqueue(
                recordType: .userEvent,
                recordID: "r1",
                schemaVersion: -3,
                payload: Data("x".utf8),
                now: now
            ),
            .rejected(.invalidSchemaVersion)
        )
    }

    @MainActor func testEnqueueRejectsOversizedPayload() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let oversized = Data(repeating: 0xAB, count: LocalSyncOutbox.maximumPayloadBytes + 1)

        XCTAssertEqual(
            outbox.enqueue(
                recordType: .userEvent,
                recordID: "r1",
                schemaVersion: 1,
                payload: oversized,
                now: now
            ),
            .rejected(.payloadTooLarge)
        )
        XCTAssertEqual(outbox.count(), 0)
    }

    @MainActor func testEnqueueRejectsWhenQueueFull() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)

        for index in 0..<LocalSyncOutbox.maximumItems {
            let result = outbox.enqueue(
                recordType: .userEvent,
                recordID: "record-\(index)",
                schemaVersion: 1,
                payload: Data("p\(index)".utf8),
                now: now.addingTimeInterval(TimeInterval(index))
            )
            guard case .enqueued = result else {
                return XCTFail("Expected enqueue to succeed at index \(index), got \(result)")
            }
        }

        XCTAssertEqual(outbox.count(), LocalSyncOutbox.maximumItems)
        let overflow = outbox.enqueue(
            recordType: .userEvent,
            recordID: "overflow",
            schemaVersion: 1,
            payload: Data("x".utf8),
            now: now.addingTimeInterval(10_000)
        )
        XCTAssertEqual(overflow, .rejected(.queueFull))
    }

    // MARK: - pending 取数

    @MainActor func testPendingReturnsOnlyDueItemsSortedByUpdatedAt() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let t0 = Date(timeIntervalSince1970: 1_730_000_000)

        outbox.enqueue(recordType: .userEvent, recordID: "a", schemaVersion: 1, payload: Data("a".utf8), now: t0)
        outbox.enqueue(recordType: .userEvent, recordID: "b", schemaVersion: 1, payload: Data("b".utf8), now: t0.addingTimeInterval(1))
        outbox.enqueue(recordType: .userEvent, recordID: "c", schemaVersion: 1, payload: Data("c".utf8), now: t0.addingTimeInterval(2))

        // 全部到期：按 updatedAt 升序返回 a, b, c。
        let all = outbox.pending(at: t0.addingTimeInterval(2))
        XCTAssertEqual(all.map(\.recordID), ["a", "b", "c"])

        // limit 生效。
        let limited = outbox.pending(at: t0.addingTimeInterval(2), limit: 2)
        XCTAssertEqual(limited.map(\.recordID), ["a", "b"])

        // t0 之前无任何到期条目；t0 时仅 a 到期。
        XCTAssertTrue(outbox.pending(at: t0.addingTimeInterval(-1)).isEmpty)
        XCTAssertEqual(outbox.pending(at: t0).map(\.recordID), ["a"])
    }

    @MainActor func testPendingLimitZeroReturnsEmpty() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        outbox.enqueue(recordType: .userEvent, recordID: "a", schemaVersion: 1, payload: Data("a".utf8), now: now)

        XCTAssertTrue(outbox.pending(at: now, limit: 0).isEmpty)
    }

    // MARK: - 租约（claimPending）

    @MainActor func testClaimPendingReservesDueItemsUntilLease() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let result = outbox.enqueue(
            recordType: .userEvent,
            recordID: "lease-1",
            schemaVersion: 1,
            payload: Data("x".utf8),
            now: now
        )
        guard case let .enqueued(item) = result else { return XCTFail("enqueue failed") }

        let claimed = outbox.claimPending(at: now, limit: 32, leaseDuration: 60)
        XCTAssertEqual(claimed.map(\.id), [item.id])
        XCTAssertEqual(claimed[0].nextAttemptAt, now.addingTimeInterval(60))
        // 租约期间不再可见、不可重复领取。
        XCTAssertTrue(outbox.pending(at: now).isEmpty)
        XCTAssertTrue(outbox.claimPending(at: now).isEmpty)

        // 租约过期后重新可领取。
        let afterLease = outbox.claimPending(at: now.addingTimeInterval(61))
        XCTAssertEqual(afterLease.map(\.id), [item.id])
    }

    @MainActor func testClaimPendingSkipsFutureItems() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)

        outbox.enqueue(recordType: .userEvent, recordID: "due", schemaVersion: 1, payload: Data("d".utf8), now: now)
        // 第二个条目 nextAttemptAt 在未来（通过失败重试制造）。
        let failed = outbox.enqueue(recordType: .userEvent, recordID: "future", schemaVersion: 1, payload: Data("f".utf8), now: now)
        guard case let .enqueued(futureItem) = failed else { return XCTFail("enqueue failed") }
        _ = outbox.markFailed(id: futureItem.id, revision: futureItem.revision, at: now, retryAfter: 3600)

        let claimed = outbox.claimPending(at: now)
        XCTAssertEqual(claimed.map(\.recordID), ["due"])
    }

    @MainActor func testClaimPendingRespectsLimitAndLeaseCap() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)

        for index in 0..<5 {
            outbox.enqueue(
                recordType: .userEvent,
                recordID: "r\(index)",
                schemaVersion: 1,
                payload: Data("p".utf8),
                now: now.addingTimeInterval(TimeInterval(index))
            )
        }

        let claimed = outbox.claimPending(at: now.addingTimeInterval(10), limit: 2, leaseDuration: 60)
        XCTAssertEqual(claimed.map(\.recordID), ["r0", "r1"])

        // leaseDuration 上限 5 分钟。
        let single = outbox.claimPending(at: now.addingTimeInterval(10), limit: 1, leaseDuration: 10_000)
        XCTAssertEqual(single.map(\.recordID), ["r2"])
        XCTAssertEqual(single[0].nextAttemptAt, now.addingTimeInterval(10 + 300))
    }

    @MainActor func testClaimPendingInvalidParametersReturnEmpty() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        outbox.enqueue(recordType: .userEvent, recordID: "a", schemaVersion: 1, payload: Data("a".utf8), now: now)

        XCTAssertTrue(outbox.claimPending(at: now, limit: 0).isEmpty)
        XCTAssertTrue(outbox.claimPending(at: .distantPast).isEmpty)
        XCTAssertTrue(outbox.claimPending(at: now, limit: 1, leaseDuration: .nan).isEmpty)
    }

    // MARK: - ACK（markSucceeded / markFailed）

    @MainActor func testMarkSucceededRemovesItemOnlyForMatchingRevision() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let result = outbox.enqueue(
            recordType: .userEvent,
            recordID: "ack-1",
            schemaVersion: 1,
            payload: Data("x".utf8),
            now: now
        )
        guard case let .enqueued(item) = result else { return XCTFail("enqueue failed") }

        XCTAssertFalse(outbox.markSucceeded(id: item.id, revision: "stale-revision"))
        XCTAssertEqual(outbox.count(), 1)

        XCTAssertTrue(outbox.markSucceeded(id: item.id, revision: item.revision))
        XCTAssertEqual(outbox.count(), 0)
        XCTAssertEqual(outbox.storageState(), .healthy(itemCount: 0))
    }

    @MainActor func testMarkFailedIncrementsAttemptsAndAppliesExponentialBackoff() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let date = Date(timeIntervalSince1970: 1_730_000_000)
        let result = outbox.enqueue(
            recordType: .userEvent,
            recordID: "retry-1",
            schemaVersion: 1,
            payload: Data("x".utf8),
            now: date
        )
        guard case let .enqueued(item) = result else { return XCTFail("enqueue failed") }

        // 第 1 次失败：attempt 0 → 1，nextAttemptAt = date + 30s（2^0 * 30）。
        XCTAssertTrue(outbox.markFailed(id: item.id, revision: item.revision, at: date))
        var pending = outbox.pending(at: date.addingTimeInterval(30))
        XCTAssertEqual(pending.map(\.recordID), ["retry-1"])
        XCTAssertEqual(pending[0].attemptCount, 1)
        XCTAssertEqual(pending[0].nextAttemptAt, date.addingTimeInterval(30))

        // 第 2 次失败：attempt 1 → 2，nextAttemptAt = date + 30 + 60s（2^1 * 30）。
        let claimed = outbox.claimPending(at: date.addingTimeInterval(30))
        XCTAssertEqual(claimed.count, 1)
        XCTAssertTrue(outbox.markFailed(id: claimed[0].id, revision: claimed[0].revision, at: date.addingTimeInterval(30)))
        pending = outbox.pending(at: date.addingTimeInterval(30 + 60))
        XCTAssertEqual(pending[0].attemptCount, 2)
        XCTAssertEqual(pending[0].nextAttemptAt, date.addingTimeInterval(30 + 60))
    }

    @MainActor func testMarkFailedHonorsExplicitRetryAfter() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let date = Date(timeIntervalSince1970: 1_730_000_000)
        let result = outbox.enqueue(
            recordType: .userEvent,
            recordID: "retry-2",
            schemaVersion: 1,
            payload: Data("x".utf8),
            now: date
        )
        guard case let .enqueued(item) = result else { return XCTFail("enqueue failed") }

        XCTAssertTrue(outbox.markFailed(id: item.id, revision: item.revision, at: date, retryAfter: 5))
        let pending = outbox.pending(at: date.addingTimeInterval(5))
        XCTAssertEqual(pending[0].attemptCount, 1)
        XCTAssertEqual(pending[0].nextAttemptAt, date.addingTimeInterval(5))
    }

    @MainActor func testMarkFailedReturnsFalseForUnknownItem() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let date = Date(timeIntervalSince1970: 1_730_000_000)

        XCTAssertFalse(outbox.markFailed(id: "missing", revision: "r", at: date))
        XCTAssertFalse(outbox.markSucceeded(id: "missing", revision: "r"))
    }

    // MARK: - retrying 退避边界

    @MainActor func testRetryingCapsAttemptCountAndExponent() {
        let now = Date(timeIntervalSince1970: 1_730_000_000)

        // attemptCount 8 → 指数上限 2^8 * 30 = 7680s。
        var item = makeItem(attemptCount: 8)
        var retried = item.retrying(now: now)
        XCTAssertEqual(retried.attemptCount, 9)
        XCTAssertEqual(retried.nextAttemptAt, now.addingTimeInterval(7680))

        // attemptCount 9 → 指数仍封顶 8，不再增长。
        item = makeItem(attemptCount: 9)
        retried = item.retrying(now: now)
        XCTAssertEqual(retried.attemptCount, 10)
        XCTAssertEqual(retried.nextAttemptAt, now.addingTimeInterval(7680))

        // attemptCount 达到上限后不再增加。
        item = makeItem(attemptCount: 10_000)
        retried = item.retrying(now: now)
        XCTAssertEqual(retried.attemptCount, 10_000)
    }

    @MainActor func testRetryingAppliesMaxDelayBound() {
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let item = makeItem(attemptCount: 8)

        // maxDelay 更小时以 maxDelay 为准。
        let retried = item.retrying(now: now, maxDelay: 60)
        XCTAssertEqual(retried.nextAttemptAt, now.addingTimeInterval(60))

        // 显式 retryAfter 超过 maxDelay 时被截断。
        let capped = item.retrying(now: now, retryAfter: 100_000, maxDelay: 60)
        XCTAssertEqual(capped.nextAttemptAt, now.addingTimeInterval(60))
    }

    // MARK: - clear / 持久化

    @MainActor func testClearRemovesAllItems() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)

        outbox.enqueue(recordType: .userEvent, recordID: "a", schemaVersion: 1, payload: Data("a".utf8), now: now)
        outbox.enqueue(recordType: .userEvent, recordID: "b", schemaVersion: 1, payload: Data("b".utf8), now: now)

        XCTAssertEqual(outbox.count(), 2)
        outbox.clear()
        XCTAssertEqual(outbox.count(), 0)
        XCTAssertEqual(outbox.storageState(), .healthy(itemCount: 0))
    }

    @MainActor func testItemsSurviveReopenAcrossInstances() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let first = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let result = first.enqueue(
            recordType: .userEvent,
            recordID: "persist-1",
            schemaVersion: 1,
            payload: Data("x".utf8),
            now: now
        )
        guard case let .enqueued(item) = result else { return XCTFail("enqueue failed") }

        let reopened = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        XCTAssertEqual(reopened.count(), 1)
        XCTAssertEqual(reopened.pending(at: now), [item])
    }

    // MARK: - 损坏存储降级

    @MainActor func testCorruptedStorageDegradesToCorruptedState() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        outbox.enqueue(recordType: .userEvent, recordID: "a", schemaVersion: 1, payload: Data("a".utf8), now: now)

        // 直接向存储写入无法解码的 payload，模拟磁盘损坏。
        let store = SwiftDataRecordStore(container: fixture.container)
        let corruptedSeed = LocalDataRecordSeed(
            domain: "local-sync-outbox",
            recordID: "corrupt",
            kind: "item",
            occurredAt: now,
            updatedAt: now,
            payload: Data("not-a-json-payload".utf8)
        )
        XCTAssertTrue(store.replace(domain: "local-sync-outbox", kind: "item", with: [corruptedSeed]))

        XCTAssertEqual(outbox.storageState(), .corrupted)
        XCTAssertEqual(outbox.count(), 0)
        // 损坏时不接受新入队，避免静默丢数据。
        let result = outbox.enqueue(
            recordType: .userEvent,
            recordID: "new",
            schemaVersion: 1,
            payload: Data("x".utf8),
            now: now
        )
        XCTAssertEqual(result, .rejected(.storageCorrupted))
    }

    // MARK: - 旧版 UserDefaults 迁移

    @MainActor func testInjectedRetiredHealthSnapshotNeverAppearsInReadsOrClaims() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let retired = makeItem(
            recordType: .healthSnapshot,
            recordID: "late-health-snapshot",
            payload: Data("health".utf8),
            createdAt: now
        )
        let retained = makeItem(
            recordType: .userEvent,
            recordID: "sendable-event",
            payload: Data("event".utf8),
            createdAt: now.addingTimeInterval(1)
        )
        let encoder = JSONEncoder()
        let store = SwiftDataRecordStore(container: fixture.container)
        let seeds = try [retired, retained].map { item in
            LocalDataRecordSeed(
                domain: "local-sync-outbox",
                recordID: item.id,
                kind: "item",
                occurredAt: item.nextAttemptAt,
                updatedAt: item.updatedAt,
                payload: try encoder.encode(item)
            )
        }

        // Inject after initialization so startup cleanup cannot remove the retired item.
        XCTAssertTrue(store.replace(domain: "local-sync-outbox", kind: "item", with: seeds))
        XCTAssertEqual(store.records(domain: "local-sync-outbox", kind: "item")?.count, 2)

        let claimDate = now.addingTimeInterval(2)
        XCTAssertEqual(outbox.count(), 1)
        XCTAssertEqual(outbox.pending(at: claimDate).map(\.recordType), [.userEvent])

        let claimed = outbox.claimPending(at: claimDate, leaseDuration: 60)
        XCTAssertEqual(claimed.map(\.recordType), [.userEvent])
        XCTAssertEqual(claimed.map(\.recordID), ["sendable-event"])
        XCTAssertEqual(outbox.count(), 1)
        XCTAssertTrue(outbox.pending(at: claimDate).isEmpty)
        XCTAssertTrue(outbox.claimPending(at: claimDate).isEmpty)

        let afterLease = claimDate.addingTimeInterval(61)
        XCTAssertEqual(outbox.pending(at: afterLease).map(\.recordType), [.userEvent])
        XCTAssertEqual(outbox.claimPending(at: afterLease).map(\.recordType), [.userEvent])
    }

    @MainActor func testReopenPurgesPersistedHealthSnapshotsWithoutDeletingOtherDomains() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        _ = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let retired = makeItem(
            recordType: .healthSnapshot,
            recordID: "retired-health",
            payload: Data("health".utf8),
            createdAt: now
        )
        let retained = makeItem(
            recordType: .userEvent,
            recordID: "retained-event",
            payload: Data("event".utf8),
            createdAt: now.addingTimeInterval(1)
        )
        let encoder = JSONEncoder()
        let store = SwiftDataRecordStore(container: fixture.container)
        let seeds = try [retired, retained].map { item in
            LocalDataRecordSeed(
                domain: "local-sync-outbox",
                recordID: item.id,
                kind: "item",
                occurredAt: item.nextAttemptAt,
                updatedAt: item.updatedAt,
                payload: try encoder.encode(item)
            )
        }
        XCTAssertTrue(store.replace(domain: "local-sync-outbox", kind: "item", with: seeds))

        let reopened = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)

        XCTAssertEqual(reopened.count(), 1)
        XCTAssertEqual(reopened.pending(at: now.addingTimeInterval(2)).map(\.recordID), ["retained-event"])
        XCTAssertEqual(
            store.records(domain: "local-sync-outbox", kind: "item")?.map(\.recordID),
            [retained.id]
        )
    }

    @MainActor func testMigratesLegacyUserDefaultsItems() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let legacyItems = [
            makeItem(recordType: .healthSnapshot, recordID: "legacy-1", payload: Data("l1".utf8), createdAt: now),
            makeItem(recordType: .userEvent, recordID: "legacy-2", payload: Data("l2".utf8), createdAt: now.addingTimeInterval(1))
        ]
        let legacyData = try JSONEncoder().encode(legacyItems)
        fixture.defaults.set(legacyData, forKey: LocalSyncOutbox.storageKey)

        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        XCTAssertEqual(outbox.count(), 1)
        // 迁移成功后清理旧 key。
        XCTAssertNil(fixture.defaults.object(forKey: LocalSyncOutbox.storageKey))

        let pending = outbox.pending(at: now.addingTimeInterval(2))
        XCTAssertEqual(pending.map(\.recordID), ["legacy-2"])
        XCTAssertEqual(pending[0].revision, legacyItems[1].revision)
    }

    @MainActor func testMigrationIsIdempotent() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let legacyItems = [makeItem(recordID: "legacy-1", payload: Data("l1".utf8), createdAt: now)]
        fixture.defaults.set(try JSONEncoder().encode(legacyItems), forKey: LocalSyncOutbox.storageKey)

        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        XCTAssertEqual(outbox.count(), 1)

        // 再次初始化（迁移标记已存在）不应重复写入。
        let reopened = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        XCTAssertEqual(reopened.count(), 1)
    }

    // MARK: - LocalSyncOutboxItem 解码校验

    @MainActor func testItemCodableRoundTrip() throws {
        let item = makeItem(
            recordType: .userEvent,
            recordID: "roundtrip-1",
            schemaVersion: 3,
            payload: Data("payload-bytes".utf8)
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(LocalSyncOutboxItem.self, from: data)
        XCTAssertEqual(decoded, item)
    }

    @MainActor func testItemDecodingRejectsInvalidValues() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // id 与 recordType/recordID 不匹配。
        var item = makeItem()
        item = LocalSyncOutboxItem(
            id: "wrong-id",
            revision: item.revision,
            recordType: item.recordType,
            recordID: item.recordID,
            schemaVersion: item.schemaVersion,
            payload: item.payload,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            attemptCount: item.attemptCount,
            nextAttemptAt: item.nextAttemptAt,
            tombstone: item.tombstone
        )
        XCTAssertThrowsError(try decoder.decode(LocalSyncOutboxItem.self, from: encoder.encode(item)))

        // 空 revision。
        item = makeItem()
        let emptyRevision = LocalSyncOutboxItem(
            id: item.id,
            revision: "",
            recordType: item.recordType,
            recordID: item.recordID,
            schemaVersion: item.schemaVersion,
            payload: item.payload,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            attemptCount: item.attemptCount,
            nextAttemptAt: item.nextAttemptAt,
            tombstone: item.tombstone
        )
        XCTAssertThrowsError(try decoder.decode(LocalSyncOutboxItem.self, from: encoder.encode(emptyRevision)))

        // schemaVersion 0。
        item = makeItem(schemaVersion: 0)
        XCTAssertThrowsError(try decoder.decode(LocalSyncOutboxItem.self, from: encoder.encode(item)))

        // payload 超限。
        item = makeItem(payload: Data(repeating: 0x01, count: LocalSyncOutbox.maximumPayloadBytes + 1))
        XCTAssertThrowsError(try decoder.decode(LocalSyncOutboxItem.self, from: encoder.encode(item)))

        // attemptCount 越界。
        item = makeItem(attemptCount: -1)
        XCTAssertThrowsError(try decoder.decode(LocalSyncOutboxItem.self, from: encoder.encode(item)))
        item = makeItem(attemptCount: 10_001)
        XCTAssertThrowsError(try decoder.decode(LocalSyncOutboxItem.self, from: encoder.encode(item)))

        // recordID 超长。
        item = makeItem(recordID: String(repeating: "a", count: 256))
        XCTAssertThrowsError(try decoder.decode(LocalSyncOutboxItem.self, from: encoder.encode(item)))
    }
}
