import CloudKit
import Foundation
import SwiftData
import XCTest
@testable import BioBalance

/// 用户数据导出/删除服务单元测试。
///
/// 全部使用内存 SwiftData 容器 + Stub CloudKit 客户端，离线运行，
/// 不依赖真实 iCloud / HealthKit / 网络。覆盖：
/// - 白名单投影（只导出白名单 ∩ 实际字段，自由文本/健康明细被过滤）；
/// - JSON / CSV 导出内容与内部域排除；
/// - 本地 SwiftData 全量清除；
/// - CloudKit 逐 zone 记录删除（CKModifyRecordsOperation delete 语义）；
/// - 删除编排：先云端后本地、iCloud 不可用时报告 unavailable。
nonisolated final class UserDataExportDeletionTests: XCTestCase {

    private struct Fixture {
        let container: ModelContainer
        let defaults: UserDefaults
        let suiteName: String
    }

    @MainActor private func makeFixture() throws -> Fixture {
        let suiteName = "UserDataPrivacyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return Fixture(
            container: try MianyuModelContainer.make(isStoredInMemoryOnly: true),
            defaults: defaults,
            suiteName: suiteName
        )
    }

    /// 直接向 SwiftData 写入一条指定 payload 的记录（用于白名单/脱敏断言，不依赖业务 Store）。
    @MainActor private func makeSeed(
        domain: String,
        recordID: String,
        kind: String = "entry",
        occurredAt: Date = Date(timeIntervalSince1970: 1_725_000_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_725_000_001),
        payload: [String: Any]
    ) throws -> LocalDataRecordSeed {
        LocalDataRecordSeed(
            domain: domain,
            recordID: recordID,
            kind: kind,
            occurredAt: occurredAt,
            updatedAt: updatedAt,
            payload: try JSONSerialization.data(withJSONObject: payload)
        )
    }

    // MARK: - 白名单投影

    @MainActor func testAuditUsesInjectedLocalStoreAndSyncPreferences() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = SwiftDataRecordStore(container: fixture.container)
        let date = Date(timeIntervalSince1970: 1_725_000_000)
        XCTAssertTrue(store.upsert(try makeSeed(
            domain: "mood", recordID: "audit-1", occurredAt: date, payload: ["note": "private"]
        )))
        fixture.defaults.set(true, forKey: ICloudSyncDomain.sleepSummary.preferenceKey)
        let report = UserDataAuditService(recordStore: store, defaults: fixture.defaults).audit()
        let summary = try XCTUnwrap(report.domainSummaries.first { $0.domain == "mood" })
        XCTAssertEqual(summary.recordCount, 1)
        XCTAssertEqual(summary.earliestAt, date)
        XCTAssertEqual(summary.latestAt, date)
        XCTAssertEqual(report.cloudSyncEnabled.first { $0.domain == ICloudSyncDomain.sleepSummary.rawValue }?.isEnabled, true)
        XCTAssertEqual(store.allRecords().count, 1, "审计不得修改本地记录")
    }

    @MainActor func testProjectionKeepsOnlyWhitelistedKeysAndDropsNotes() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let date = Date(timeIntervalSince1970: 1_725_000_000)
        let mood = MoodEntry(
            id: "mood-1",
            moodID: "calm",
            title: "平静",
            backendEmotionCode: "neutral",
            intensity: 45,
            note: "包含隐私的自由文本",
            loggedAt: date,
            backendRecordedAt: nil
        )
        MoodStore(defaults: fixture.defaults, container: fixture.container).save(mood)

        let store = SwiftDataRecordStore(container: fixture.container)
        let rows = try XCTUnwrap(store.records(domain: "mood"))
        let projected = UserDataExportService.project(
            payload: try XCTUnwrap(rows.first?.payload),
            whitelist: UserDataPrivacyRegistry.exportWhitelist(for: "mood")
        )

        XCTAssertEqual(projected?["moodID"]?.stringValue, "calm")
        XCTAssertEqual(projected?["intensity"]?.numberValue, 45)
        // note 不在白名单，绝不导出
        XCTAssertNil(projected?["note"])
        // title 是目录标题（非自由文本），允许导出
        XCTAssertEqual(projected?["title"]?.stringValue, "平静")
    }

    @MainActor func testProjectionRejectsRawHealthAndLocationFieldsForDrink() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let date = Date(timeIntervalSince1970: 1_725_000_000)
        let drink = DrinkStampRecord(
            id: "drink-1",
            storeName: "本地咖啡店",
            cityName: "上海",
            drinkName: "美式",
            capturedAt: date,
            photoFileID: 123,
            photoURL: "file:///private/photo.png",
            cutoutFileID: 456,
            cutoutURL: "file:///private/cutout.png",
            latitude: 31.23,
            longitude: 121.47,
            locationLabel: "精确位置文本",
            status: .confirmed,
            isGeneratedFromRecognition: false
        )
        DrinkExperienceStore(defaults: fixture.defaults, container: fixture.container).saveStamp(drink)

        let store = SwiftDataRecordStore(container: fixture.container)
        let rows = try XCTUnwrap(store.records(domain: "drink-experience"))
        let projected = UserDataExportService.project(
            payload: try XCTUnwrap(rows.first?.payload),
            whitelist: UserDataPrivacyRegistry.exportWhitelist(for: "drink-experience")
        )

        XCTAssertEqual(projected?["drinkName"]?.stringValue, "美式")
        // 图片/文件引用、精确坐标、位置文本、AI 元数据一律不导出
        XCTAssertNil(projected?["photoURL"])
        XCTAssertNil(projected?["cutoutURL"])
        XCTAssertNil(projected?["latitude"])
        XCTAssertNil(projected?["longitude"])
        XCTAssertNil(projected?["locationLabel"])
    }

    // MARK: - 导出

    @MainActor func testJSONExportContainsOnlyWhitelistedFieldsAndExcludesInternalDomains() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let date = Date(timeIntervalSince1970: 1_725_000_000)
        MoodStore(defaults: fixture.defaults, container: fixture.container).save(
            MoodEntry(
                id: "mood-1",
                moodID: "calm",
                title: "平静",
                backendEmotionCode: "neutral",
                intensity: 45,
                note: "不应导出",
                loggedAt: date,
                backendRecordedAt: nil
            )
        )
        // 内部域（同步队列）
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        _ = outbox.enqueue(
            recordType: .userEvent,
            recordID: "event-1",
            schemaVersion: 1,
            payload: Data("payload".utf8),
            now: date
        )

        let service = UserDataExportService(recordStore: SwiftDataRecordStore(container: fixture.container))
        let url = try service.generateExport(format: .json, now: date)
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let domains = try XCTUnwrap(root["domains"] as? [String: Any])

        XCTAssertNotNil(domains["mood"])
        // 内部域绝不进入导出文件
        XCTAssertNil(domains["local-sync-outbox"])

        let moodDomain = try XCTUnwrap(domains["mood"] as? [String: Any])
        let records = try XCTUnwrap(moodDomain["records"] as? [[String: Any]])
        let record = try XCTUnwrap(records.first)
        let fields = try XCTUnwrap(record["fields"] as? [String: Any])
        XCTAssertEqual(fields["moodID"] as? String, "calm")
        XCTAssertNil(fields["note"])
    }

    @MainActor func testCSVExportProducesReadableRowsWithoutSensitiveFields() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let date = Date(timeIntervalSince1970: 1_725_000_000)
        MoodStore(defaults: fixture.defaults, container: fixture.container).save(
            MoodEntry(
                id: "mood-1",
                moodID: "calm",
                title: "平静",
                backendEmotionCode: "neutral",
                intensity: 45,
                note: "不应导出",
                loggedAt: date,
                backendRecordedAt: nil
            )
        )

        let service = UserDataExportService(recordStore: SwiftDataRecordStore(container: fixture.container))
        let url = try service.generateExport(format: .csv, now: date)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")

        XCTAssertTrue(lines[0].contains("domain"))
        XCTAssertTrue(lines[0].contains("moodID"))
        XCTAssertTrue(lines.dropFirst().contains { $0.contains("mood") && $0.contains("calm") })
        XCTAssertFalse(text.contains("不应导出"))
        XCTAssertFalse(text.contains("note"))
    }

    // MARK: - 本地删除

    @MainActor func testClearAllRemovesEveryLocalRecord() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let date = Date(timeIntervalSince1970: 1_725_000_000)
        MoodStore(defaults: fixture.defaults, container: fixture.container).save(
            MoodEntry(
                id: "mood-1",
                moodID: "calm",
                title: "平静",
                backendEmotionCode: "neutral",
                intensity: 45,
                note: nil,
                loggedAt: date,
                backendRecordedAt: nil
            )
        )
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        _ = outbox.enqueue(
            recordType: .userEvent,
            recordID: "event-1",
            schemaVersion: 1,
            payload: Data("payload".utf8),
            now: date
        )

        let store = SwiftDataRecordStore(container: fixture.container)
        // 包含业务记录 + 可能的迁移标记（__migration），至少应有 2 条。
        XCTAssertGreaterThanOrEqual(store.allRecords().count, 2)

        XCTAssertTrue(store.clearAll())
        XCTAssertEqual(store.allRecords().count, 0)
        // 重开一个 store 实例确认持久层真的清空
        let reopened = SwiftDataRecordStore(container: fixture.container)
        XCTAssertEqual(reopened.allRecords().count, 0)
    }

    // MARK: - CloudKit 删除

    @MainActor func testCloudKitDeleterQueriesAndDeletesAllPrivateZoneRecords() async throws {
        let zoneID = CKRecordZone.ID(zoneName: CloudKitDataPolicy.Zone.drinkExperience, ownerName: CKCurrentUserDefaultName)
        let record1 = CKRecord(recordType: CloudKitDataPolicy.RecordType.drinkExperience, recordID: CKRecord.ID(recordName: "drink.1", zoneID: zoneID))
        let record2 = CKRecord(recordType: CloudKitDataPolicy.RecordType.drinkExperience, recordID: CKRecord.ID(recordName: "drink.2", zoneID: zoneID))

        let stub = PrivacyCloudKitClientStub(zoneRecords: [zoneID: [record1, record2]])
        let deleter = CloudKitUserDataDeleter(
            container: CKContainer(identifier: CloudKitDataPolicy.containerIdentifier),
            client: stub,
            executor: CloudKitOperationExecutor(retryPolicy: CloudKitRetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0)),
            friendShareStopper: { }
        )

        let results = await deleter.deleteAll()

        // 每个私有 zone 都返回 deleted（含空 zone），好友共享 zone 也被清除
        XCTAssertGreaterThanOrEqual(
            results.filter { $0.state == .deleted }.count,
            CloudKitUserDataDeleter.privateZones.count
        )
        XCTAssertTrue(CloudKitUserDataDeleter.privateZones.allSatisfy { spec in
            results.contains { $0.zoneName == spec.zoneName && $0.state == .deleted }
        })
        // drinkExperience zone 删除 2 条
        let drinkResult = try XCTUnwrap(results.first { $0.zoneName == CloudKitDataPolicy.Zone.drinkExperience })
        XCTAssertEqual(drinkResult.recordCount, 2)
        // 两条记录都被 CKModifyRecordsOperation delete 删除
        XCTAssertEqual(stub.deletedRecordNames, ["drink.1", "drink.2"])
        // 好友共享与公开资料为 completed/deleted
        XCTAssertTrue(results.contains { $0.zoneName == CloudKitDataPolicy.Zone.friendHealthShare })
    }

    @MainActor func testCloudKitDeleterReportsUnavailableWithoutAccount() async throws {
        let stub = PrivacyCloudKitClientStub(accountAvailable: false)
        let deleter = CloudKitUserDataDeleter(
            container: CKContainer(identifier: CloudKitDataPolicy.containerIdentifier),
            client: stub,
            executor: CloudKitOperationExecutor(retryPolicy: CloudKitRetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0)),
            friendShareStopper: { }
        )

        let results = await deleter.deleteAll()
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.state == .unavailable })
        XCTAssertTrue(stub.deletedRecordNames.isEmpty)
    }

    // MARK: - 删除编排（本地 + 云端）

    @MainActor func testDeletionServiceClearsLocalAfterCloudAndRestoresSyncPrefs() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let date = Date(timeIntervalSince1970: 1_725_000_000)
        MoodStore(defaults: fixture.defaults, container: fixture.container).save(
            MoodEntry(
                id: "mood-1",
                moodID: "calm",
                title: "平静",
                backendEmotionCode: "neutral",
                intensity: 45,
                note: nil,
                loggedAt: date,
                backendRecordedAt: nil
            )
        )

        CloudKitDataPolicy.registerDefaultPreferences(in: fixture.defaults)
        let stub = PrivacyCloudKitClientStub(accountAvailable: true)
        let service = UserDataDeletionService(
            recordStore: SwiftDataRecordStore(container: fixture.container),
            defaults: fixture.defaults,
            cloudDeleter: CloudKitUserDataDeleter(
                container: CKContainer(identifier: CloudKitDataPolicy.containerIdentifier),
                client: stub,
                executor: CloudKitOperationExecutor(retryPolicy: CloudKitRetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0)),
                friendShareStopper: { }
            )
        )

        let report = await service.deleteAllData()
        XCTAssertTrue(report.localSwiftDataCleared)
        XCTAssertGreaterThanOrEqual(report.localRecordCount, 1)
        XCTAssertEqual(SwiftDataRecordStore(container: fixture.container).allRecords().count, 0)
        XCTAssertEqual(report.cloudFailureCount, 0)

        // 同步开关在删除后恢复（默认开启）
        XCTAssertTrue(fixture.defaults.bool(forKey: CloudKitDataPolicy.PreferenceKey.drinkExperienceSyncEnabled))
    }

    // MARK: - 白名单 fail-closed 加固

    @MainActor func testUnknownDomainFailsClosedWithoutExportedFields() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let store = SwiftDataRecordStore(container: fixture.container)
        XCTAssertTrue(store.upsert(try makeSeed(
            domain: "future-unknown-domain",
            recordID: "unknown-1",
            payload: ["secretField": "不应导出的未知域字段", "count": 3]
        )))

        // 未知域白名单为空 → 投影为 nil（没有任何字段可导出）
        XCTAssertTrue(UserDataPrivacyRegistry.exportWhitelist(for: "future-unknown-domain").isEmpty)
        let row = try XCTUnwrap(store.records(domain: "future-unknown-domain")?.first)
        let projected = UserDataExportService.project(
            payload: row.payload,
            whitelist: UserDataPrivacyRegistry.exportWhitelist(for: "future-unknown-domain")
        )
        XCTAssertNil(projected)

        // JSON 导出：未知域记录只有元数据，绝不带 fields
        let url = try UserDataExportService(recordStore: store).generateExport(format: .json)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let domains = try XCTUnwrap(root["domains"] as? [String: Any])
        let unknown = try XCTUnwrap(domains["future-unknown-domain"] as? [String: Any])
        let records = try XCTUnwrap(unknown["records"] as? [[String: Any]])
        let record = try XCTUnwrap(records.first)
        XCTAssertNil(record["fields"], "未知域记录只允许导出元数据，不得带任何字段")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("不应导出的未知域字段"))
    }

    @MainActor func testSensitiveAggregateDomainsExportOnlyWhitelistedMetadata() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let date = Date(timeIntervalSince1970: 1_725_000_000)
        let iso = ISO8601DateFormatter().string(from: date)
        let store = SwiftDataRecordStore(container: fixture.container)
        // period：经期明细（流量/疼痛/备注/起止日期）一律不导出，仅保留聚合更新时间戳
        XCTAssertTrue(store.upsert(try makeSeed(
            domain: "period",
            recordID: "period-1",
            payload: [
                "updatedAt": iso,
                "startDate": "2026-08-01",
                "endDate": "2026-08-05",
                "flowLevel": "heavy",
                "painLevel": 7,
                "note": "period 隐私备注"
            ]
        )))
        // daily-health-snapshot：派生健康快照只导出 schemaVersion/date/generatedAt，metrics 明细不导出
        XCTAssertTrue(store.upsert(try makeSeed(
            domain: "daily-health-snapshot",
            recordID: "snapshot-1",
            payload: [
                "schemaVersion": 1,
                "date": "2026-08-01",
                "generatedAt": iso,
                "metrics": ["heartRateSamples": [60, 61], "sleepStages": "deep 3h"]
            ]
        )))

        let url = try UserDataExportService(recordStore: store).generateExport(format: .json)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let domains = try XCTUnwrap(root["domains"] as? [String: Any])

        let periodDomain = try XCTUnwrap(domains["period"] as? [String: Any])
        let periodRecords = try XCTUnwrap(periodDomain["records"] as? [[String: Any]])
        let periodFields = try XCTUnwrap(periodRecords.first?["fields"] as? [String: Any])
        XCTAssertEqual(periodFields.keys.sorted(), ["updatedAt"], "经期域只导出聚合更新时间戳")

        let snapshotDomain = try XCTUnwrap(domains["daily-health-snapshot"] as? [String: Any])
        let snapshotRecords = try XCTUnwrap(snapshotDomain["records"] as? [[String: Any]])
        let snapshotFields = try XCTUnwrap(snapshotRecords.first?["fields"] as? [String: Any])
        XCTAssertEqual(
            snapshotFields.keys.sorted(),
            ["date", "generatedAt", "schemaVersion"],
            "健康快照只导出版本与时间戳"
        )

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("period 隐私备注"))
        XCTAssertFalse(text.contains("flowLevel"))
        XCTAssertFalse(text.contains("heartRateSamples"))
        XCTAssertFalse(text.contains("sleepStages"))
    }

    // MARK: - 导出文件整体脱敏（fail-closed 兜底）

    @MainActor func testExportedFilesNeverContainSensitiveSubstrings() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let date = Date(timeIntervalSince1970: 1_725_000_000)
        MoodStore(defaults: fixture.defaults, container: fixture.container).save(
            MoodEntry(
                id: "mood-secret",
                moodID: "calm",
                title: "平静",
                backendEmotionCode: "neutral",
                intensity: 45,
                note: "SENSITIVE_NOTE_MARKER_42",
                loggedAt: date,
                backendRecordedAt: nil
            )
        )
        DrinkExperienceStore(defaults: fixture.defaults, container: fixture.container).saveStamp(
            DrinkStampRecord(
                id: "drink-secret",
                storeName: "本地咖啡店",
                cityName: "上海",
                drinkName: "美式",
                capturedAt: date,
                photoFileID: 1,
                photoURL: "file:///private/SENSITIVE_PHOTO_42.png",
                cutoutFileID: 2,
                cutoutURL: "file:///private/SENSITIVE_CUTOUT_42.png",
                latitude: 31.2300001,
                longitude: 121.4700001,
                locationLabel: "SENSITIVE_LOCATION_MARKER_42",
                status: .confirmed,
                isGeneratedFromRecognition: false
            )
        )

        let service = UserDataExportService(recordStore: SwiftDataRecordStore(container: fixture.container))
        for format in [UserDataExportFormat.json, UserDataExportFormat.csv] {
            let url = try service.generateExport(format: format)
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(text.contains("SENSITIVE_NOTE_MARKER_42"), "\(format.rawValue) 不应包含自由文本备注")
            XCTAssertFalse(text.contains("SENSITIVE_PHOTO_42"), "\(format.rawValue) 不应包含图片引用")
            XCTAssertFalse(text.contains("SENSITIVE_CUTOUT_42"), "\(format.rawValue) 不应包含裁剪图引用")
            XCTAssertFalse(text.contains("SENSITIVE_LOCATION_MARKER_42"), "\(format.rawValue) 不应包含精确位置文本")
            XCTAssertFalse(text.contains("31.2300001"), "\(format.rawValue) 不应包含纬度")
            XCTAssertFalse(text.contains("121.4700001"), "\(format.rawValue) 不应包含经度")
        }
    }

    // MARK: - 日志脱敏

    @MainActor func testPrivacyLogsNeverContainPayloadValues() async throws {
        #if DEBUG
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let recorder = PrivacyLogRecorder()
        UserDataPrivacyLogger.testCapture = { recorder.record($0) }
        defer { UserDataPrivacyLogger.testCapture = nil }

        let date = Date(timeIntervalSince1970: 1_725_000_000)
        MoodStore(defaults: fixture.defaults, container: fixture.container).save(
            MoodEntry(
                id: "mood-1",
                moodID: "calm",
                title: "平静",
                backendEmotionCode: "neutral",
                intensity: 45,
                note: "LOG_SENSITIVE_NOTE_77",
                loggedAt: date,
                backendRecordedAt: nil
            )
        )
        DrinkExperienceStore(defaults: fixture.defaults, container: fixture.container).saveStamp(
            DrinkStampRecord(
                id: "drink-1",
                storeName: "本地咖啡店",
                cityName: "上海",
                drinkName: "美式",
                capturedAt: date,
                photoFileID: 1,
                photoURL: "file:///private/LOG_SENSITIVE_PHOTO_77.png",
                cutoutFileID: 2,
                cutoutURL: "file:///private/LOG_SENSITIVE_CUTOUT_77.png",
                latitude: 31.2300001,
                longitude: 121.4700001,
                locationLabel: "LOG_SENSITIVE_LOCATION_77",
                status: .confirmed,
                isGeneratedFromRecognition: false
            )
        )

        // 触发导出与删除，收集所有隐私日志
        _ = try UserDataExportService(recordStore: SwiftDataRecordStore(container: fixture.container))
            .generateExport(format: .json)

        CloudKitDataPolicy.registerDefaultPreferences(in: fixture.defaults)
        let stub = PrivacyCloudKitClientStub(accountAvailable: true)
        let service = UserDataDeletionService(
            recordStore: SwiftDataRecordStore(container: fixture.container),
            defaults: fixture.defaults,
            cloudDeleter: CloudKitUserDataDeleter(
                container: CKContainer(identifier: CloudKitDataPolicy.containerIdentifier),
                client: stub,
                executor: CloudKitOperationExecutor(retryPolicy: CloudKitRetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0)),
                friendShareStopper: { }
            )
        )
        _ = await service.deleteAllData()

        let lines = recorder.snapshot()
        XCTAssertFalse(lines.isEmpty, "导出/删除应产生可被断言的隐私日志")
        let forbidden = [
            "LOG_SENSITIVE_NOTE_77",
            "LOG_SENSITIVE_PHOTO_77",
            "LOG_SENSITIVE_CUTOUT_77",
            "LOG_SENSITIVE_LOCATION_77",
            "31.2300001",
            "121.4700001"
        ]
        for line in lines {
            for token in forbidden {
                XCTAssertFalse(line.contains(token), "日志泄露 payload：「\(line)」包含 \(token)")
            }
        }
        #else
        throw XCTSkip("日志捕获钩子仅用于 Debug，Release 不包含捕获路径。")
        #endif
    }

    // MARK: - 幂等

    @MainActor func testDeletionIsIdempotentAcrossRepeatedRuns() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let date = Date(timeIntervalSince1970: 1_725_000_000)
        MoodStore(defaults: fixture.defaults, container: fixture.container).save(
            MoodEntry(
                id: "mood-1",
                moodID: "calm",
                title: "平静",
                backendEmotionCode: "neutral",
                intensity: 45,
                note: nil,
                loggedAt: date,
                backendRecordedAt: nil
            )
        )

        CloudKitDataPolicy.registerDefaultPreferences(in: fixture.defaults)
        let stub = PrivacyCloudKitClientStub(accountAvailable: true)
        let service = UserDataDeletionService(
            recordStore: SwiftDataRecordStore(container: fixture.container),
            defaults: fixture.defaults,
            cloudDeleter: CloudKitUserDataDeleter(
                container: CKContainer(identifier: CloudKitDataPolicy.containerIdentifier),
                client: stub,
                executor: CloudKitOperationExecutor(retryPolicy: CloudKitRetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0)),
                friendShareStopper: { }
            )
        )

        let first = await service.deleteAllData()
        XCTAssertTrue(first.localSwiftDataCleared)
        XCTAssertGreaterThanOrEqual(first.localRecordCount, 1)
        XCTAssertEqual(first.cloudFailureCount, 0)
        XCTAssertTrue(first.isFullyCleared)

        // 第二次删除：本地与云端均已空，仍成功返回（幂等，无失败、无副作用）
        let second = await service.deleteAllData()
        XCTAssertTrue(second.localSwiftDataCleared)
        XCTAssertEqual(second.localRecordCount, 0)
        XCTAssertEqual(second.cloudFailureCount, 0)
        XCTAssertTrue(second.isFullyCleared)
        XCTAssertEqual(SwiftDataRecordStore(container: fixture.container).allRecords().count, 0)
    }

    @MainActor func testClearAllIsIdempotentOnEmptyStore() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let store = SwiftDataRecordStore(container: fixture.container)
        XCTAssertTrue(store.clearAll())
        XCTAssertTrue(store.clearAll())
        XCTAssertEqual(store.allRecords().count, 0)
    }

    // MARK: - iCloud 不可用分支（端到端）

    @MainActor func testDeletionServiceClearsLocalAndReportsCloudUnavailableWhenICloudDown() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let date = Date(timeIntervalSince1970: 1_725_000_000)
        MoodStore(defaults: fixture.defaults, container: fixture.container).save(
            MoodEntry(
                id: "mood-1",
                moodID: "calm",
                title: "平静",
                backendEmotionCode: "neutral",
                intensity: 45,
                note: nil,
                loggedAt: date,
                backendRecordedAt: nil
            )
        )

        CloudKitDataPolicy.registerDefaultPreferences(in: fixture.defaults)
        let stub = PrivacyCloudKitClientStub(accountAvailable: false)
        let service = UserDataDeletionService(
            recordStore: SwiftDataRecordStore(container: fixture.container),
            defaults: fixture.defaults,
            cloudDeleter: CloudKitUserDataDeleter(
                container: CKContainer(identifier: CloudKitDataPolicy.containerIdentifier),
                client: stub,
                executor: CloudKitOperationExecutor(retryPolicy: CloudKitRetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0)),
                friendShareStopper: { }
            )
        )

        let report = await service.deleteAllData()
        // 本地数据仍然清除，云端标记 unavailable（数据保留等待重试）
        XCTAssertTrue(report.localSwiftDataCleared)
        XCTAssertEqual(SwiftDataRecordStore(container: fixture.container).allRecords().count, 0)
        XCTAssertTrue(report.cloudUnavailable)
        XCTAssertEqual(report.cloudFailureCount, 0)
        XCTAssertFalse(report.isFullyCleared, "iCloud 不可用时整体删除未完成，需要重试")
        XCTAssertTrue(report.cloudResults.allSatisfy { $0.state == .unavailable })
        // 同步开关在删除后恢复（默认开启）
        XCTAssertTrue(fixture.defaults.bool(forKey: CloudKitDataPolicy.PreferenceKey.drinkExperienceSyncEnabled))
    }

    @MainActor func testDeletionRetryAfterICloudRestoredCompletesCloudCleanup() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let date = Date(timeIntervalSince1970: 1_725_000_000)
        MoodStore(defaults: fixture.defaults, container: fixture.container).save(
            MoodEntry(
                id: "mood-1",
                moodID: "calm",
                title: "平静",
                backendEmotionCode: "neutral",
                intensity: 45,
                note: nil,
                loggedAt: date,
                backendRecordedAt: nil
            )
        )
        CloudKitDataPolicy.registerDefaultPreferences(in: fixture.defaults)

        // 第一轮：iCloud 不可用 → 本地清除、云端 unavailable
        let downStub = PrivacyCloudKitClientStub(accountAvailable: false)
        let downService = UserDataDeletionService(
            recordStore: SwiftDataRecordStore(container: fixture.container),
            defaults: fixture.defaults,
            cloudDeleter: CloudKitUserDataDeleter(
                container: CKContainer(identifier: CloudKitDataPolicy.containerIdentifier),
                client: downStub,
                executor: CloudKitOperationExecutor(retryPolicy: CloudKitRetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0)),
                friendShareStopper: { }
            )
        )
        let first = await downService.deleteAllData()
        XCTAssertTrue(first.localSwiftDataCleared)
        XCTAssertTrue(first.cloudUnavailable)
        XCTAssertTrue(downStub.deletedRecordNames.isEmpty)

        // 第二轮：iCloud 恢复 → 幂等重试补删云端记录
        let zoneID = CKRecordZone.ID(zoneName: CloudKitDataPolicy.Zone.drinkExperience, ownerName: CKCurrentUserDefaultName)
        let cloudRecord = CKRecord(
            recordType: CloudKitDataPolicy.RecordType.drinkExperience,
            recordID: CKRecord.ID(recordName: "drink.retry", zoneID: zoneID)
        )
        let restoredStub = PrivacyCloudKitClientStub(
            zoneRecords: [zoneID: [cloudRecord]],
            accountAvailable: true
        )
        let retryService = UserDataDeletionService(
            recordStore: SwiftDataRecordStore(container: fixture.container),
            defaults: fixture.defaults,
            cloudDeleter: CloudKitUserDataDeleter(
                container: CKContainer(identifier: CloudKitDataPolicy.containerIdentifier),
                client: restoredStub,
                executor: CloudKitOperationExecutor(retryPolicy: CloudKitRetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0)),
                friendShareStopper: { }
            )
        )
        let second = await retryService.deleteAllData()
        XCTAssertTrue(second.localSwiftDataCleared)
        XCTAssertEqual(second.cloudFailureCount, 0)
        XCTAssertFalse(second.cloudUnavailable)
        XCTAssertTrue(second.isFullyCleared)
        // 云端记录确实被 CKModifyRecordsOperation delete 删除
        XCTAssertEqual(restoredStub.deletedRecordNames, ["drink.retry"])
    }

}

// MARK: - 测试用 Stub

/// 内存版 CloudKit 客户端：按 zone 保存记录，query 返回、modify delete 移除。
private final class PrivacyCloudKitClientStub: CloudKitClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var zoneRecords: [CKRecordZone.ID: [CKRecord]]
    private let accountAvailable: Bool
    private var deletedNames: [String] = []

    init(
        zoneRecords: [CKRecordZone.ID: [CKRecord]] = [:],
        accountAvailable: Bool = true
    ) {
        self.zoneRecords = zoneRecords
        self.accountAvailable = accountAvailable
    }

    var deletedRecordNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return deletedNames.sorted()
    }

    func accountStatus(container: CKContainer) async throws -> CKAccountStatus {
        accountAvailable ? .available : .noAccount
    }

    func fetchUserRecordID(container: CKContainer) async throws -> CKRecord.ID {
        guard accountAvailable else { throw CloudKitDomainError.iCloudUnavailable }
        return CKRecord.ID(recordName: "current-user")
    }

    func accept(metadata: CKShare.Metadata, container: CKContainer) async throws {}

    func save(zone: CKRecordZone, in database: CKDatabase) async throws -> CKRecordZone { zone }

    func delete(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws {
        lock.withLock {
            zoneRecords[zoneID] = []
        }
    }

    func fetch(recordID: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord? {
        lock.withLock {
            zoneRecords[recordID.zoneID]?.first { $0.recordID == recordID }
        }
    }

    func save(record: CKRecord, in database: CKDatabase) async throws -> CKRecord { record }

    func modify(
        recordsToSave: [CKRecord],
        recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        in database: CKDatabase
    ) async throws -> [CKRecord] {
        lock.withLock {
            for id in recordIDsToDelete {
                deletedNames.append(id.recordName)
                zoneRecords[id.zoneID]?.removeAll { $0.recordID == id }
            }
            return recordsToSave
        }
    }

    func runQuery(
        query: CKQuery?,
        cursor: CKQueryOperation.Cursor?,
        zoneID: CKRecordZone.ID?,
        in database: CKDatabase
    ) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        lock.withLock {
            guard let zoneID else { return ([], nil) }
            let records = (zoneRecords[zoneID] ?? []).filter { record in
                guard let query else { return true }
                return record.recordType == query.recordType
            }
            return (records, nil)
        }
    }

    func fetchAllZoneIDs(in database: CKDatabase) async throws -> [CKRecordZone.ID] {
        lock.withLock { Array(zoneRecords.keys) }
    }
}

private extension UserDataExportValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}


/// 隐私日志捕获器（测试用）：线程安全地把日志文本收集到数组。
nonisolated private final class PrivacyLogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func record(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}
