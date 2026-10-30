import CloudKit
import Foundation
import os

/// 按用户数据域划分的私有 zone 规格（与 `CloudKitDataPolicy.Zone/RecordType` 完全一致）。
nonisolated struct UserDataPrivateZoneSpec: Sendable {
    let zoneName: String
    let recordTypes: [String]
}

/// CloudKit 删除执行器：删除当前 Apple ID 私有库各 zone 的全部记录。
///
/// ## 删除语义（last-write-wins 下的取舍）
/// 私有 zone 是「单写者 + 单所有者」：只有当前 Apple ID 能写，其他设备/用户不会
/// 凭空恢复已删除记录，因此采用**直接删除（hard delete）**而不是 tombstone。
/// 直接删除的好处是云端不残留任何业务 payload（配合日志脱敏，真正做到数据消失）；
/// 代价是「离线删除」没有 pending 队列——如果删除时 iCloud 不可用，该 zone 会被
/// 标记为 `.unavailable`，由用户重试完成（删除是幂等的，重试安全）。
///
/// tombstone 只在「多写者协作」场景才有意义（防止另一台设备用旧快照复活记录），
/// 例如未来的 CKSyncEngine 增量同步或共享协作待办；当前私有域不满足该前提，
/// 使用 tombstone 只会让云端保留一段带时间戳的删除标记，反而违背“数据消失”的目标。
nonisolated struct CloudKitUserDataDeleter: Sendable {
    /// 需要清理的私有 zone 与 record type 白名单。
    static let privateZones: [UserDataPrivateZoneSpec] = [
        UserDataPrivateZoneSpec(
            zoneName: CloudKitDataPolicy.Zone.drinkExperience,
            recordTypes: [CloudKitDataPolicy.RecordType.drinkExperience]
        ),
        UserDataPrivateZoneSpec(
            zoneName: CloudKitDataPolicy.Zone.sleep,
            recordTypes: [CloudKitDataPolicy.RecordType.sleepSession]
        ),
        UserDataPrivateZoneSpec(
            zoneName: CloudKitDataPolicy.Zone.medicationHealth,
            recordTypes: [CloudKitDataPolicy.RecordType.medicationPrescription]
        ),
        UserDataPrivateZoneSpec(
            zoneName: CloudKitDataPolicy.Zone.pregnancy,
            recordTypes: [
                CloudKitDataPolicy.RecordType.pregnancyProfile,
                CloudKitDataPolicy.RecordType.pregnancyWeightEntry,
                CloudKitDataPolicy.RecordType.fetalMovementEntry
            ]
        ),
        UserDataPrivateZoneSpec(
            zoneName: CloudKitDataPolicy.Zone.goalMascot,
            recordTypes: [
                CloudKitDataPolicy.RecordType.goalMascotProfile,
                CloudKitDataPolicy.RecordType.goalMascotXPGrant
            ]
        ),
        UserDataPrivateZoneSpec(
            zoneName: CloudKitDataPolicy.Zone.onboardingPreference,
            recordTypes: [CloudKitDataPolicy.RecordType.onboardingPreference]
        )
    ]

    private static let batchSize = 200

    private let container: CKContainer
    private let database: CKDatabase
    private let client: CloudKitClientProtocol
    private let executor: CloudKitOperationExecutor
    private let friendShareStopper: @Sendable () async throws -> Void

    init(
        container: CKContainer = CloudKitDataPolicy.makeContainer(),
        client: CloudKitClientProtocol = CloudKitClient(),
        executor: CloudKitOperationExecutor = CloudKitOperationExecutor(),
        friendShareStopper: (@Sendable () async throws -> Void)? = nil
    ) {
        self.container = container
        self.database = container.privateCloudDatabase
        self.client = client
        self.executor = executor
        self.friendShareStopper = friendShareStopper ?? {
            try await CloudKitSharingService.shared.stopSharing()
        }
    }

    /// 删除全部私有 zone + 好友共享 zone + 公开资料（尽力而为），返回逐 zone 结果。
    func deleteAll() async -> [CloudZoneDeletionResult] {
        let accountAvailable: Bool
        do {
            _ = try await executor.run(
                context: CloudKitLoggerContext(operation: "privacy-delete.account", database: .private)
            ) { [client, container] in
                try await client.fetchUserRecordID(container: container)
            }
            accountAvailable = true
        } catch {
            accountAvailable = false
            UserDataPrivacyLogger.info("cloud deletion skipped: iCloud unavailable")
        }

        guard accountAvailable else {
            return unavailableResults()
        }

        var results: [CloudZoneDeletionResult] = []
        for spec in Self.privateZones {
            results.append(await deletePrivateZone(spec))
        }
        results.append(await deleteFriendShareZone())
        results.append(await deletePublicProfile())
        return results
    }

    // MARK: - 私有 zone 删除

    private func deletePrivateZone(_ spec: UserDataPrivateZoneSpec) async -> CloudZoneDeletionResult {
        let zoneID = CKRecordZone.ID(zoneName: spec.zoneName, ownerName: CKCurrentUserDefaultName)
        do {
            var recordIDs: [CKRecord.ID] = []
            for recordType in spec.recordTypes {
                var cursor: CKQueryOperation.Cursor?
                repeat {
                    let requestCursor = cursor
                    let page = try await executor.run(
                        context: CloudKitLoggerContext(
                            operation: "privacy-delete.query-\(recordType)",
                            database: .private,
                            zoneID: spec.zoneName
                        )
                    ) { [client, database, zoneID] in
                        try await client.runQuery(
                            query: requestCursor == nil
                                ? CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                                : nil,
                            cursor: requestCursor,
                            zoneID: zoneID,
                            in: database
                        )
                    }
                    recordIDs.append(contentsOf: page.records.map(\.recordID))
                    cursor = page.cursor
                } while cursor != nil
            }

            // CKModifyRecordsOperation delete：按 200 条一批原子删除。
            var deletedCount = 0
            for start in stride(from: 0, to: recordIDs.count, by: Self.batchSize) {
                let end = min(start + Self.batchSize, recordIDs.count)
                let batch = Array(recordIDs[start..<end])
                _ = try await executor.run(
                    context: CloudKitLoggerContext(
                        operation: "privacy-delete.modify",
                        database: .private,
                        zoneID: spec.zoneName
                    )
                ) { [client, database] in
                    try await client.modify(
                        recordsToSave: [],
                        recordIDsToDelete: batch,
                        savePolicy: .changedKeys,
                        in: database
                    )
                }
                deletedCount += batch.count
            }

            UserDataPrivacyLogger.info(
                "cloud zone cleared zone=\(spec.zoneName) records=\(deletedCount)"
            )
            return CloudZoneDeletionResult(
                zoneName: spec.zoneName,
                state: .deleted,
                recordCount: deletedCount
            )
        } catch let error as CloudKitDomainError {
            switch error {
            case .zoneNotFound, .unknownItem:
                // zone 尚不存在或没有对应 record type：视为已删除（空删除）。
                return CloudZoneDeletionResult(zoneName: spec.zoneName, state: .deleted, recordCount: 0)
            default:
                return CloudZoneDeletionResult(
                    zoneName: spec.zoneName,
                    state: .failed,
                    message: error.localizedDescription
                )
            }
        } catch {
            return CloudZoneDeletionResult(
                zoneName: spec.zoneName,
                state: .failed,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - 好友共享 zone（走既有生命周期接口）

    private func deleteFriendShareZone() async -> CloudZoneDeletionResult {
        do {
            // stopSharing 删除整个 FriendHealthShareZone，同时撤销 CKShare、清理健康 root
            // 与共享待办层级，不影响本机数据。
            try await friendShareStopper()
            UserDataPrivacyLogger.info("cloud zone cleared zone=\(CloudKitDataPolicy.Zone.friendHealthShare)")
            return CloudZoneDeletionResult(
                zoneName: CloudKitDataPolicy.Zone.friendHealthShare,
                state: .deleted,
                recordCount: 0
            )
        } catch {
            return CloudZoneDeletionResult(
                zoneName: CloudKitDataPolicy.Zone.friendHealthShare,
                state: .failed,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - 公开资料（尽力而为，不阻塞整体删除）

    private func deletePublicProfile() async -> CloudZoneDeletionResult {
        do {
            let userRecordName = try await executor.run(
                context: CloudKitLoggerContext(operation: "privacy-delete.public-account", database: .public)
            ) { [client, container] in
                try await client.fetchUserRecordID(container: container).recordName
            }
            let publicDB = container.publicCloudDatabase
            var recordIDs: [CKRecord.ID] = []
            var cursor: CKQueryOperation.Cursor?
            repeat {
                let requestCursor = cursor
                let page = try await executor.run(
                    context: CloudKitLoggerContext(
                        operation: "privacy-delete.query-UserProfile",
                        database: .public
                    )
                ) { [client, publicDB] in
                    try await client.runQuery(
                        query: requestCursor == nil
                            ? CKQuery(
                                recordType: CloudKitDataPolicy.RecordType.userProfile,
                                predicate: NSPredicate(
                                    format: "ownerUserRecordName == %@",
                                    userRecordName
                                )
                            )
                            : nil,
                        cursor: requestCursor,
                        zoneID: nil,
                        in: publicDB
                    )
                }
                recordIDs.append(contentsOf: page.records.map(\.recordID))
                cursor = page.cursor
            } while cursor != nil

            for start in stride(from: 0, to: recordIDs.count, by: Self.batchSize) {
                let end = min(start + Self.batchSize, recordIDs.count)
                let batch = Array(recordIDs[start..<end])
                _ = try await executor.run(
                    context: CloudKitLoggerContext(
                        operation: "privacy-delete.public-modify",
                        database: .public
                    )
                ) { [client, publicDB] in
                    try await client.modify(
                        recordsToSave: [],
                        recordIDsToDelete: batch,
                        savePolicy: .changedKeys,
                        in: publicDB
                    )
                }
            }

            UserDataPrivacyLogger.info(
                "public profile cleanup zone=UserProfile records=\(recordIDs.count)"
            )
            return CloudZoneDeletionResult(
                zoneName: "public.UserProfile",
                state: .completed,
                recordCount: recordIDs.count,
                message: recordIDs.isEmpty ? "无公开资料" : "已清理公开资料"
            )
        } catch {
            // 公开库查询可能因 schema 未建索引而失败；公开资料不属健康数据红线，
            // 尽力而为，不阻塞整体删除。
            UserDataPrivacyLogger.info("public profile cleanup skipped (best effort)")
            return CloudZoneDeletionResult(
                zoneName: "public.UserProfile",
                state: .completed,
                recordCount: 0,
                message: "公开资料尽力清理（跳过）"
            )
        }
    }

    private func unavailableResults() -> [CloudZoneDeletionResult] {
        var results = Self.privateZones.map {
            CloudZoneDeletionResult(zoneName: $0.zoneName, state: .unavailable)
        }
        results.append(CloudZoneDeletionResult(
            zoneName: CloudKitDataPolicy.Zone.friendHealthShare,
            state: .unavailable
        ))
        results.append(CloudZoneDeletionResult(
            zoneName: "public.UserProfile",
            state: .unavailable
        ))
        return results
    }
}

/// 「删除我的数据」编排：先删 CloudKit（防止本地残留重新上传复活），再清本地 SwiftData。
@MainActor
final class UserDataDeletionService {
    static let shared = UserDataDeletionService()

    private let recordStore: SwiftDataRecordStore
    private let defaults: UserDefaults
    private let cloudDeleter: CloudKitUserDataDeleter

    init(
        recordStore: SwiftDataRecordStore? = nil,
        defaults: UserDefaults = .standard,
        cloudDeleter: CloudKitUserDataDeleter = CloudKitUserDataDeleter()
    ) {
        self.recordStore = recordStore ?? SwiftDataRecordStore()
        self.defaults = defaults
        self.cloudDeleter = cloudDeleter
    }

    /// 执行完整删除：CloudKit（逐 zone）→ 本地 SwiftData → 刷新 Widget 投影。
    ///
    /// 删除期间临时关闭同步开关，避免删除窗口内后台同步把本地数据重新上传到云端；
    /// 结束后恢复用户原有偏好（不影响删除后新数据的正常同步）。
    func deleteAllData() async -> UserDataDeletionReport {
        let localRecordCount = recordStore.allRecords().count

        // 删除窗口内关闭同步，防止复活（last-write-wins 场景的防护）。
        let previousPrefs = ICloudSyncDomain.allCases.map { ($0, defaults.bool(forKey: $0.preferenceKey)) }
        ICloudSyncDomain.allCases.forEach { defaults.set(false, forKey: $0.preferenceKey) }
        defer {
            for (domain, enabled) in previousPrefs {
                defaults.set(enabled, forKey: domain.preferenceKey)
            }
        }

        let cloudResults = await cloudDeleter.deleteAll()

        let localCleared = recordStore.clearAll()
        if localCleared {
            // 删除后刷新 Widget / 小组件投影，避免展示已删除数据。
            WidgetSyncService.refresh(
                WidgetRefreshDomain.appVisibleDefaults,
                reason: .healthUpdate,
                force: true
            )
        }

        UserDataPrivacyLogger.info(
            "delete completed local=\(localCleared) localRecords=\(localRecordCount) cloudZones=\(cloudResults.count)"
        )
        return UserDataDeletionReport(
            localSwiftDataCleared: localCleared,
            localRecordCount: localRecordCount,
            cloudResults: cloudResults
        )
    }
}
