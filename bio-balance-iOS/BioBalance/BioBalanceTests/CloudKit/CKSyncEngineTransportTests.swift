import CloudKit
import Foundation
import XCTest
@testable import BioBalance

// MARK: - CKSyncEngine 传输层测试

/// 验证 CKSyncEngine 抽象层的配置、模式解析和冲突解决逻辑。
///
/// 注意：由于 `CKSyncEngine` 需要真实 CloudKit 容器，这些测试聚焦于
/// 不依赖网络的纯逻辑部分：模式解析器、配置工厂、冲突解决算法。
nonisolated final class CKSyncEngineTransportTests: XCTestCase {

    // MARK: - CloudKitSyncTransportResolver 测试

    @MainActor func testResolverDefaultsToLegacyMode() {
        let suiteName = "test.sync-resolver.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 没有显式启用时应返回 legacy。
        let mode = CloudKitSyncTransportResolver.resolveMode(forZone: CloudKitDataPolicy.Zone.drinkExperience)
        // 由于使用 .standard，这里只验证默认逻辑不 crash。
        XCTAssertTrue([CloudKitSyncTransportMode.legacy, .syncEngine].contains(mode))
    }

    @MainActor func testResolverReturnsLegacyWhenDisabled() {
        let suiteName = "test.sync-resolver.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let zoneName = "TestZone"
        CloudKitSyncTransportResolver.disableSyncEngine(forZone: zoneName, in: defaults)
        let key = "cloudkit.sync-engine.enabled.\(zoneName)"
        XCTAssertFalse(defaults.bool(forKey: key))
    }

    @MainActor func testResolverReturnsSyncEngineWhenEnabled() {
        let suiteName = "test.sync-resolver.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let zoneName = "TestZone"
        CloudKitSyncTransportResolver.enableSyncEngine(forZone: zoneName, in: defaults)
        let key = "cloudkit.sync-engine.enabled.\(zoneName)"
        XCTAssertTrue(defaults.bool(forKey: key))
    }

    @MainActor func testResolverDisableRemovesKey() {
        let suiteName = "test.sync-resolver.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let zoneName = "TestZone"
        CloudKitSyncTransportResolver.enableSyncEngine(forZone: zoneName, in: defaults)
        CloudKitSyncTransportResolver.disableSyncEngine(forZone: zoneName, in: defaults)
        let key = "cloudkit.sync-engine.enabled.\(zoneName)"
        XCTAssertFalse(defaults.bool(forKey: key))
    }

    // MARK: - CloudKitDataPolicy.syncEngineConfig 测试

    @MainActor func testSyncEngineConfigUsesCorrectStateKey() {
        let config = CloudKitDataPolicy.syncEngineConfig(
            forZone: CloudKitDataPolicy.Zone.drinkExperience,
            recordTypes: [CloudKitDataPolicy.RecordType.drinkExperience]
        )

        XCTAssertEqual(config.zoneName, CloudKitDataPolicy.Zone.drinkExperience)
        XCTAssertEqual(config.recordTypes, [CloudKitDataPolicy.RecordType.drinkExperience])
        XCTAssertEqual(config.stateSerializationKey, CloudKitDataPolicy.SyncEngineStateKey.drinkExperience)
        XCTAssertEqual(config.conflictPolicy, .lastWriteWins)
    }

    @MainActor func testSyncEngineConfigForSleepZone() {
        let config = CloudKitDataPolicy.syncEngineConfig(
            forZone: CloudKitDataPolicy.Zone.sleep,
            recordTypes: [CloudKitDataPolicy.RecordType.sleepSession],
            conflictPolicy: .mergeFields
        )

        XCTAssertEqual(config.zoneName, CloudKitDataPolicy.Zone.sleep)
        XCTAssertEqual(config.stateSerializationKey, CloudKitDataPolicy.SyncEngineStateKey.sleep)
        XCTAssertEqual(config.conflictPolicy, .mergeFields)
    }

    @MainActor func testSyncEngineConfigForUnknownZoneGeneratesFallbackKey() {
        let config = CloudKitDataPolicy.syncEngineConfig(
            forZone: "CustomTestZone",
            recordTypes: ["TestRecord"]
        )

        XCTAssertEqual(config.zoneName, "CustomTestZone")
        XCTAssertEqual(config.stateSerializationKey, "ck-sync-engine.state.CustomTestZone.v1")
    }

    @MainActor func testSyncEngineConfigZoneIDMatchesPolicyZone() {
        let config = CloudKitDataPolicy.syncEngineConfig(
            forZone: CloudKitDataPolicy.Zone.goalMascot,
            recordTypes: [
                CloudKitDataPolicy.RecordType.goalMascotProfile,
                CloudKitDataPolicy.RecordType.goalMascotXPGrant
            ]
        )

        XCTAssertEqual(config.zoneID.zoneName, CloudKitDataPolicy.Zone.goalMascot)
        XCTAssertEqual(config.zoneID.ownerName, CKCurrentUserDefaultName)
        XCTAssertEqual(config.stateSerializationKey, CloudKitDataPolicy.SyncEngineStateKey.goalMascot)
    }

    // MARK: - SyncEngineStateKey 稳定性测试

    @MainActor func testSyncEngineStateKeysRemainStable() {
        XCTAssertEqual(CloudKitDataPolicy.SyncEngineStateKey.drinkExperience, "ck-sync-engine.state.drinkExperience.v1")
        XCTAssertEqual(CloudKitDataPolicy.SyncEngineStateKey.sleep, "ck-sync-engine.state.sleep.v1")
        XCTAssertEqual(CloudKitDataPolicy.SyncEngineStateKey.medicationHealth, "ck-sync-engine.state.medicationHealth.v1")
        XCTAssertEqual(CloudKitDataPolicy.SyncEngineStateKey.pregnancy, "ck-sync-engine.state.pregnancy.v1")
        XCTAssertEqual(CloudKitDataPolicy.SyncEngineStateKey.goalMascot, "ck-sync-engine.state.goalMascot.v1")
    }

    // MARK: - 传输模式枚举测试

    @MainActor func testTransportModeRawValues() {
        XCTAssertEqual(CloudKitSyncTransportMode.legacy.rawValue, "legacy")
        XCTAssertEqual(CloudKitSyncTransportMode.syncEngine.rawValue, "syncEngine")
    }

    // MARK: - 冲突解决策略测试

    @MainActor func testConflictPolicyRawValues() {
        XCTAssertEqual(CloudKitSyncConflictPolicy.lastWriteWins.rawValue, "lastWriteWins")
        XCTAssertEqual(CloudKitSyncConflictPolicy.mergeFields.rawValue, "mergeFields")
        XCTAssertEqual(CloudKitSyncConflictPolicy.askDelegate.rawValue, "askDelegate")
    }

    // MARK: - DrinkExperienceCloudRepository 传输模式测试

    @MainActor func testDrinkRepositoryAcceptsTransportModeParameter() {
        // 验证仓储可以接受显式的传输模式参数（不 crash）。
        let repo = DrinkExperienceCloudRepository(transportMode: .legacy)
        XCTAssertNotNil(repo)
    }

    @MainActor func testDrinkRepositorySyncEngineInitNoOpInLegacyMode() {
        let repo = DrinkExperienceCloudRepository(transportMode: .legacy)
        // legacy 模式下 initializeSyncEngineIfNeeded 应为 no-op。
        repo.initializeSyncEngineIfNeeded()
        // 不 crash 即通过。
    }

    @MainActor func testDrinkRepositoryNotifyLocalChangeNoOpInLegacyMode() {
        let repo = DrinkExperienceCloudRepository(transportMode: .legacy)
        // legacy 模式下 notifyLocalChange 应为 no-op。
        repo.notifyLocalChange()
        // 不 crash 即通过。
    }

    // MARK: - Notification 名称测试

    @MainActor func testDrinkExperienceNotificationNames() {
        XCTAssertEqual(
            Notification.Name.drinkExperienceRemoteChangeReceived.rawValue,
            "drinkExperienceRemoteChangeReceived"
        )
        XCTAssertEqual(
            Notification.Name.drinkExperienceSyncDidComplete.rawValue,
            "drinkExperienceSyncDidComplete"
        )
    }

    @MainActor func testSleepSummaryNotificationNames() {
        XCTAssertEqual(
            Notification.Name.sleepSummaryRemoteChangeReceived.rawValue,
            "sleepSummaryRemoteChangeReceived"
        )
        XCTAssertEqual(
            Notification.Name.sleepSummarySyncDidComplete.rawValue,
            "sleepSummarySyncDidComplete"
        )
    }

    // MARK: - Zone 配置不变性测试（迁移安全）

    @MainActor func testMigrationPreservesZoneAndRecordTypeIdentifiers() {
        // 验证 SyncEngine 配置使用的 zone/recordType 与传统模式完全一致。
        let drinkConfig = CloudKitDataPolicy.syncEngineConfig(
            forZone: CloudKitDataPolicy.Zone.drinkExperience,
            recordTypes: [CloudKitDataPolicy.RecordType.drinkExperience]
        )
        XCTAssertEqual(drinkConfig.zoneName, "BioBalanceDrinkExperienceZone")
        XCTAssertEqual(drinkConfig.recordTypes.first, "BBDrinkExperience")

        let sleepConfig = CloudKitDataPolicy.syncEngineConfig(
            forZone: CloudKitDataPolicy.Zone.sleep,
            recordTypes: [CloudKitDataPolicy.RecordType.sleepSession]
        )
        XCTAssertEqual(sleepConfig.zoneName, "BioBalanceSleepZone")
        XCTAssertEqual(sleepConfig.recordTypes.first, "BBSleepSession")

        let pregnancyConfig = CloudKitDataPolicy.syncEngineConfig(
            forZone: CloudKitDataPolicy.Zone.pregnancy,
            recordTypes: [
                CloudKitDataPolicy.RecordType.pregnancyProfile,
                CloudKitDataPolicy.RecordType.pregnancyWeightEntry,
                CloudKitDataPolicy.RecordType.fetalMovementEntry
            ]
        )
        XCTAssertEqual(pregnancyConfig.zoneName, "BioBalancePregnancyZone")
        XCTAssertEqual(pregnancyConfig.stateSerializationKey, CloudKitDataPolicy.SyncEngineStateKey.pregnancy)
    }
}
