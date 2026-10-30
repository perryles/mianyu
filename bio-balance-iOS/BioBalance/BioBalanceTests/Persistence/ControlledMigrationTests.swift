import Foundation
import SwiftData
import XCTest
@testable import BioBalance

nonisolated final class ControlledMigrationTests: XCTestCase {
    @MainActor private func makeFixture() throws -> (container: ModelContainer, defaults: UserDefaults, suiteName: String) {
        let suiteName = "ControlledMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (
            try MianyuModelContainer.make(isStoredInMemoryOnly: true),
            defaults,
            suiteName
        )
    }

    // MARK: - SwiftDataRecordStore.migrate：幂等 + 迁移后校验 + 失败回滚

    @MainActor func testMigrateIsIdempotentAndValidatesSeedsAfterSave() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = SwiftDataRecordStore(container: fixture.container)
        let seed = LocalDataRecordSeed(
            domain: "test-domain",
            recordID: "1",
            kind: "entry",
            occurredAt: Date(timeIntervalSince1970: 1_725_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_725_000_000),
            payload: Data("x".utf8)
        )

        XCTAssertTrue(store.migrate("test-migration", seeds: [seed]))

        // 迁移后校验：seed 已可查询。
        let rows = store.records(domain: "test-domain", kind: "entry")
        XCTAssertEqual(rows?.map(\.stableKey), [seed.stableKey])

        // 幂等：重复迁移返回 true，不重复写入。
        XCTAssertTrue(store.migrate("test-migration", seeds: [seed]))
        XCTAssertEqual(store.records(domain: "test-domain", kind: "entry")?.count, 1)
        XCTAssertTrue(store.isMigrationComplete("test-migration"))
    }

    @MainActor func testMigrateRollsBackWhenSaveFailsAndKeepsNoPartialRows() throws {
        // 只读测试存储确定性拒绝保存；不能依赖某个 SDK 的 externalStorage 大小阈值。
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadOnlyMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("test.store")
        // 先创建有效的磁盘存储；只读配置不能首次创建存储，也不能使用 /dev/null。
        do {
            let writable = ModelConfiguration(schema: MianyuModelContainer.schema, url: storeURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: MianyuModelContainer.schema, configurations: [writable])
            try ModelContext(container).save()
        }
        let configuration = ModelConfiguration(
            "ReadOnlyMigrationTest", schema: MianyuModelContainer.schema,
            url: storeURL, allowsSave: false, cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: MianyuModelContainer.schema, configurations: [configuration])
        let store = SwiftDataRecordStore(container: container)
        let date = Date(timeIntervalSince1970: 1_725_000_000)

        let seed = LocalDataRecordSeed(
            domain: "read-only-domain",
            recordID: "entry",
            kind: "entry",
            occurredAt: date,
            updatedAt: date,
            payload: Data("migration-test".utf8)
        )
        XCTAssertFalse(store.migrate("read-only-migration", seeds: [seed]))
        XCTAssertFalse(store.isMigrationComplete("read-only-migration"))
        XCTAssertEqual(store.records(domain: "read-only-domain", kind: "entry")?.count ?? 0, 0)
    }

    // MARK: - ControlledMigrationCoordinator：受控迁移

    @MainActor func testCoordinatorMigratesAppGroupKeysAndLegacyStorePayload() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let appGroupSuite = "ControlledMigrationTests.appGroup.\(UUID().uuidString)"
        let appGroup = try XCTUnwrap(UserDefaults(suiteName: appGroupSuite))
        appGroup.removePersistentDomain(forName: appGroupSuite)
        defer { appGroup.removePersistentDomain(forName: appGroupSuite) }

        // App Group 业务 key（非 Store 迁移 key，迁移后保留在标准 defaults）。
        let appGroupKey = "periodStore.v1"
        let appGroupPayload = Data("legacy-period-bytes".utf8)
        appGroup.set(appGroupPayload, forKey: appGroupKey)

        // 标准 defaults 中的旧整包 payload，应由 MoodStore 迁入 SwiftData 后删除。
        let entry = MoodEntry(
            id: "mood-1",
            moodID: "calm",
            title: "平静",
            backendEmotionCode: "neutral",
            intensity: 45,
            note: nil,
            loggedAt: Date(timeIntervalSince1970: 1_725_000_000),
            backendRecordedAt: nil
        )
        struct LegacyPayload: Encodable { let entries: [MoodEntry] }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        fixture.defaults.set(
            try encoder.encode(LegacyPayload(entries: [entry])),
            forKey: "moodStore.v1"
        )

        let configuration = ControlledMigrationCoordinator.Configuration(
            standardDefaults: fixture.defaults,
            appGroupDefaults: appGroup,
            container: fixture.container
        )
        let report = ControlledMigrationCoordinator.runAtLaunch(configuration: configuration)

        XCTAssertTrue(report.failures.isEmpty, report.sanitizedSummary())

        // App Group key 已搬到标准 defaults 并删除旧 key；未解码的业务数据被保留。
        XCTAssertEqual(fixture.defaults.data(forKey: appGroupKey), appGroupPayload)
        XCTAssertNil(appGroup.object(forKey: appGroupKey))

        // mood 旧 payload 已迁入 SwiftData，旧整包 key 已删除。
        XCTAssertEqual(
            MoodStore(defaults: fixture.defaults, container: fixture.container).allEntries(),
            [entry]
        )
        XCTAssertNil(fixture.defaults.data(forKey: "moodStore.v1"))
    }

    @MainActor func testCoordinatorIsIncrementalAndIdempotentAcrossRuns() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let entry = MoodEntry(
            id: "mood-2",
            moodID: "happy",
            title: "开心",
            backendEmotionCode: "happy",
            intensity: 72,
            note: nil,
            loggedAt: Date(timeIntervalSince1970: 1_725_000_000),
            backendRecordedAt: nil
        )
        struct LegacyPayload: Encodable { let entries: [MoodEntry] }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        fixture.defaults.set(
            try encoder.encode(LegacyPayload(entries: [entry])),
            forKey: "moodStore.v1"
        )

        let configuration = ControlledMigrationCoordinator.Configuration(
            standardDefaults: fixture.defaults,
            appGroupDefaults: nil,
            container: fixture.container
        )

        let firstReport = ControlledMigrationCoordinator.runAtLaunch(configuration: configuration)
        XCTAssertTrue(firstReport.failures.isEmpty, firstReport.sanitizedSummary())
        XCTAssertTrue(
            SwiftDataRecordStore(container: fixture.container).isMigrationComplete("moodStore.v1-to-swiftdata.v1")
        )

        let recordsStore = SwiftDataRecordStore(container: fixture.container)
        let moodCountAfterFirstRun = recordsStore.records(domain: "mood", kind: "entry")?.count

        let secondReport = ControlledMigrationCoordinator.runAtLaunch(configuration: configuration)
        XCTAssertTrue(secondReport.failures.isEmpty, secondReport.sanitizedSummary())
        XCTAssertEqual(recordsStore.records(domain: "mood", kind: "entry")?.count, moodCountAfterFirstRun)
        XCTAssertNil(fixture.defaults.data(forKey: "moodStore.v1"))
    }

    @MainActor func testCoordinatorRunsCleanlyWithoutLegacyData() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let configuration = ControlledMigrationCoordinator.Configuration(
            standardDefaults: fixture.defaults,
            appGroupDefaults: nil,
            container: fixture.container
        )
        let report = ControlledMigrationCoordinator.runAtLaunch(configuration: configuration)

        // 全新安装：所有任务都应完成（无旧数据时各 Store 只写空 marker），不抛错。
        XCTAssertTrue(report.failures.isEmpty, report.sanitizedSummary())
        XCTAssertEqual(report.results.count, 17)
    }
}
