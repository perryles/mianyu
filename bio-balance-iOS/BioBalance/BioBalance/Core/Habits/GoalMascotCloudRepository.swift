import CloudKit
import Foundation

struct GoalMascotCloudSnapshot {
    var name: String
    var nameUpdatedAt: Date?
    var createdAt: Date
    var baselineXP: Int
    var rewardCount: Int
    var lastXPDate: Date?
    var grants: [GoalXPGrant]

    static func empty(createdAt: Date = Date()) -> GoalMascotCloudSnapshot {
        GoalMascotCloudSnapshot(
            name: GoalPetState.empty.name,
            nameUpdatedAt: nil,
            createdAt: createdAt,
            baselineXP: 0,
            rewardCount: 0,
            lastXPDate: nil,
            grants: []
        )
    }
}

struct GoalMascotCloudFetchResult {
    let accountIdentifier: String
    let snapshot: GoalMascotCloudSnapshot?
}

nonisolated enum GoalMascotCloudSchema {
    // Mascot 使用独立 private zone；XP grant 是追加型事实，不能按 profile 整体覆盖。
    static let zoneName = CloudKitDataPolicy.Zone.goalMascot
    static let profileRecordType = CloudKitDataPolicy.RecordType.goalMascotProfile
    static let grantRecordType = CloudKitDataPolicy.RecordType.goalMascotXPGrant
    static let profileRecordName = "current-mascot"
    static let schemaVersion: Int64 = 2
}

/// 目标吉祥物（Mascot）の CloudKit 跨设备同步仓储。
///
/// ## 数据隔离
/// - Zone：`CloudKitDataPolicy.Zone.goalMascot`（独立 private zone）。
/// - Profile record（`BBMascotProfile`）：聚合名称、账本前基线 XP 等概要；用稳定单条
///   record name `current-mascot` 做 last-write-wins 覆盖式保存。
/// - XP Grant record（`BBMascotXPGrant`）：追加型事实，以 `goalID + dayBucket` 作为
///   唯一 key，保证同一目标同一天只产生一条 grant，多设备合并幂等。
///
/// ## 合并策略
/// - Profile 字段：`name` 使用 `nameUpdatedAt` 进行 last-write-wins；数值字段取 max。
/// - Grant 列表：相同 key 保留 `amount` 更大者；相等时取 `awardedAt` 更早者。
///
/// ## 隐私边界
/// 只保存结构化数值与时间戳；不含任何健康指标、位置或用户自由文本。
/// CloudKit 失败不会阻断本地目标追踪。
///
/// ## CKSyncEngine 迁移路径（iOS 17+）
/// XP Grant 为追加型事实，记录数量可能随使用时间增长。当 grant 数量超过 ~1000 条时，
/// 可通过 `CloudKitSyncTransportResolver.enableSyncEngine(forZone: CloudKitDataPolicy.Zone.goalMascot)`
/// 启用增量同步模式。zone / record type 保持不变，仅替换底层 transport。
nonisolated final class GoalMascotCloudRepository {
    private let container: CKContainer
    private let database: CKDatabase
    private let client: CloudKitClientProtocol
    private let executor: CloudKitOperationExecutor
    private let zoneID: CKRecordZone.ID

    init(
        container: CKContainer = CloudKitDataPolicy.makeContainer(),
        client: CloudKitClientProtocol = CloudKitClient(),
        executor: CloudKitOperationExecutor = CloudKitOperationExecutor()
    ) {
        self.container = container
        self.database = container.privateCloudDatabase
        self.client = client
        self.executor = executor
        self.zoneID = CKRecordZone.ID(
            zoneName: GoalMascotCloudSchema.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
    }

    func fetch() async throws -> GoalMascotCloudFetchResult {
        let accountIdentifier = try await preparePrivateDatabase()
        let remote = try await fetchRemoteSnapshot()
        try await verifyCurrentAccount(accountIdentifier)
        return GoalMascotCloudFetchResult(accountIdentifier: accountIdentifier, snapshot: remote.snapshot)
    }

    func synchronize(local: GoalMascotCloudSnapshot) async throws -> GoalMascotCloudFetchResult {
        let accountIdentifier = try await preparePrivateDatabase()
        let remote = try await fetchRemoteSnapshot()
        let merged = Self.merge(local: local, remote: remote.snapshot)

        try await save(
            snapshot: merged,
            profileRecord: remote.profileRecord,
            grantRecords: remote.grantRecords,
            accountIdentifier: accountIdentifier
        )
        try await verifyCurrentAccount(accountIdentifier)
        return GoalMascotCloudFetchResult(accountIdentifier: accountIdentifier, snapshot: merged)
    }

    static func grantKey(for grant: GoalXPGrant) -> String {
        let dayBucket = Int(floor(grant.date.timeIntervalSince1970 / 86_400))
        return "\(grant.goalID.uuidString.lowercased())__\(dayBucket)"
    }

    static func merge(
        local: GoalMascotCloudSnapshot,
        remote: GoalMascotCloudSnapshot?
    ) -> GoalMascotCloudSnapshot {
        guard let remote else { return normalized(local) }

        let localNameDate = local.nameUpdatedAt ?? .distantPast
        let remoteNameDate = remote.nameUpdatedAt ?? .distantPast
        let resolvedName: String
        let resolvedNameDate: Date?
        if localNameDate > remoteNameDate
            || (localNameDate == remoteNameDate
                && local.name != GoalPetState.empty.name
                && remote.name == GoalPetState.empty.name) {
            resolvedName = local.name
            resolvedNameDate = local.nameUpdatedAt
        } else {
            resolvedName = remote.name
            resolvedNameDate = remote.nameUpdatedAt
        }

        let grants = mergeGrants(local.grants + remote.grants)
        return normalized(
            GoalMascotCloudSnapshot(
                name: resolvedName,
                nameUpdatedAt: resolvedNameDate,
                createdAt: min(local.createdAt, remote.createdAt),
                baselineXP: max(local.baselineXP, remote.baselineXP),
                rewardCount: max(local.rewardCount, remote.rewardCount),
                lastXPDate: [local.lastXPDate, remote.lastXPDate].compactMap { $0 }.max(),
                grants: grants
            )
        )
    }

    private struct RemoteSnapshot {
        let snapshot: GoalMascotCloudSnapshot?
        let profileRecord: CKRecord?
        let grantRecords: [String: CKRecord]
    }

    private func preparePrivateDatabase() async throws -> String {
        let status = try await executor.run(
            context: CloudKitLoggerContext(operation: "mascot-account-status", database: .private)
        ) { [container, client] in
            try await client.accountStatus(container: container)
        }
        guard status == .available else {
            throw CloudKitDomainError.iCloudUnavailable
        }

        let accountIdentifier = try await executor.run(
            context: CloudKitLoggerContext(operation: "mascot-account-identity", database: .private)
        ) { [container, client] in
            try await client.fetchUserRecordID(container: container).recordName
        }

        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await executor.run(
            context: CloudKitLoggerContext(
                operation: "prepare-mascot-zone",
                database: .private,
                zoneID: zoneID.zoneName
            )
        ) { [container, client, database] in
            let current = try await client.fetchUserRecordID(container: container)
            guard current.recordName == accountIdentifier else {
                throw CloudKitDomainError.iCloudUnavailable
            }
            return try await client.save(zone: zone, in: database)
        }
        return accountIdentifier
    }

    private func verifyCurrentAccount(_ accountIdentifier: String) async throws {
        let current = try await executor.run(
            context: CloudKitLoggerContext(operation: "verify-mascot-account", database: .private)
        ) { [container, client] in
            try await client.fetchUserRecordID(container: container).recordName
        }
        guard current == accountIdentifier else {
            throw CloudKitDomainError.iCloudUnavailable
        }
    }

    private func fetchRemoteSnapshot() async throws -> RemoteSnapshot {
        let profileID = CKRecord.ID(
            recordName: GoalMascotCloudSchema.profileRecordName,
            zoneID: zoneID
        )
        let profileRecord = try await executor.run(
            context: CloudKitLoggerContext(
                operation: "fetch-mascot-profile",
                database: .private,
                zoneID: zoneID.zoneName,
                recordID: profileID.recordName
            )
        ) { [client, database] in
            try await client.fetch(recordID: profileID, in: database)
        }

        let grantRecords = try await fetchAllGrantRecords()
        let decodedGrants = grantRecords.values.compactMap(Self.decodeGrant)
        let profile = profileRecord.flatMap { Self.decodeProfile($0, grants: decodedGrants) }
        let snapshot = profile ?? (decodedGrants.isEmpty ? nil : GoalMascotCloudSnapshot(
            name: GoalPetState.empty.name,
            nameUpdatedAt: nil,
            createdAt: decodedGrants.map(\.awardedAt).min() ?? Date(),
            baselineXP: 0,
            rewardCount: 0,
            lastXPDate: decodedGrants.map(\.date).max(),
            grants: decodedGrants
        ))

        return RemoteSnapshot(
            snapshot: snapshot.map(Self.normalized),
            profileRecord: profileRecord,
            grantRecords: grantRecords
        )
    }

    private func fetchAllGrantRecords() async throws -> [String: CKRecord] {
        var records: [String: CKRecord] = [:]
        var cursor: CKQueryOperation.Cursor?

        repeat {
            do {
                let currentCursor = cursor
                let page = try await executor.run(
                    context: CloudKitLoggerContext(
                        operation: "query-mascot-grants",
                        database: .private,
                        zoneID: zoneID.zoneName
                    )
                ) { [client, database, zoneID] in
                    try await client.runQuery(
                        query: currentCursor == nil
                            ? CKQuery(recordType: GoalMascotCloudSchema.grantRecordType, predicate: NSPredicate(value: true))
                            : nil,
                        cursor: currentCursor,
                        zoneID: zoneID,
                        in: database
                    )
                }
                for record in page.records {
                    records[record.recordID.recordName] = record
                }
                cursor = page.cursor
            } catch CloudKitDomainError.unknownItem {
                return [:]
            }
        } while cursor != nil

        return records
    }

    private func save(
        snapshot: GoalMascotCloudSnapshot,
        profileRecord: CKRecord?,
        grantRecords: [String: CKRecord],
        accountIdentifier: String
    ) async throws {
        let profileID = CKRecord.ID(
            recordName: GoalMascotCloudSchema.profileRecordName,
            zoneID: zoneID
        )
        let profile = profileRecord ?? CKRecord(
            recordType: GoalMascotCloudSchema.profileRecordType,
            recordID: profileID
        )
        profile["name"] = snapshot.name as CKRecordValue
        profile["nameUpdatedAt"] = snapshot.nameUpdatedAt as CKRecordValue?
        profile["createdAt"] = snapshot.createdAt as CKRecordValue
        profile["baselineXP"] = Int64(snapshot.baselineXP) as CKRecordValue
        // 兼容尚未升级的设备；新代码只使用 baselineXP，旧字段不再进入业务模型。
        profile["legacyXP"] = Int64(snapshot.baselineXP) as CKRecordValue
        profile["rewardCount"] = Int64(snapshot.rewardCount) as CKRecordValue
        profile["lastXPDate"] = snapshot.lastXPDate as CKRecordValue?
        profile["updatedAt"] = Date() as CKRecordValue
        profile["schemaVersion"] = GoalMascotCloudSchema.schemaVersion as CKRecordValue

        var recordsToSave = [profile]
        for grant in snapshot.grants {
            let recordName = Self.grantKey(for: grant)
            let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
            let record = grantRecords[recordName] ?? CKRecord(
                recordType: GoalMascotCloudSchema.grantRecordType,
                recordID: recordID
            )
            record["grantID"] = grant.id.uuidString as CKRecordValue
            record["goalID"] = grant.goalID.uuidString as CKRecordValue
            record["date"] = grant.date as CKRecordValue
            record["amount"] = Int64(grant.amount) as CKRecordValue
            record["awardedAt"] = grant.awardedAt as CKRecordValue
            record["schemaVersion"] = GoalMascotCloudSchema.schemaVersion as CKRecordValue
            recordsToSave.append(record)
        }

        for batch in recordsToSave.chunked(into: 200) {
            _ = try await executor.run(
                context: CloudKitLoggerContext(
                    operation: "save-mascot-snapshot",
                    database: .private,
                    zoneID: zoneID.zoneName
                )
            ) { [container, client, database] in
                let current = try await client.fetchUserRecordID(container: container)
                guard current.recordName == accountIdentifier else {
                    throw CloudKitDomainError.iCloudUnavailable
                }
                return try await client.modify(
                    recordsToSave: batch,
                    recordIDsToDelete: [],
                    savePolicy: .changedKeys,
                    in: database
                )
            }
        }
    }

    private static func decodeProfile(
        _ record: CKRecord,
        grants: [GoalXPGrant]
    ) -> GoalMascotCloudSnapshot? {
        guard let name = record["name"] as? String else { return nil }
        return GoalMascotCloudSnapshot(
            name: name,
            nameUpdatedAt: record["nameUpdatedAt"] as? Date,
            createdAt: (record["createdAt"] as? Date) ?? Date(),
            baselineXP: max(0, Int(
                (record["baselineXP"] as? Int64)
                    ?? (record["legacyXP"] as? Int64)
                    ?? 0
            )),
            rewardCount: max(0, Int((record["rewardCount"] as? Int64) ?? 0)),
            lastXPDate: record["lastXPDate"] as? Date,
            grants: grants
        )
    }

    private static func decodeGrant(_ record: CKRecord) -> GoalXPGrant? {
        guard let goalIDText = record["goalID"] as? String,
              let goalID = UUID(uuidString: goalIDText),
              let date = record["date"] as? Date,
              let awardedAt = record["awardedAt"] as? Date else {
            return nil
        }
        let id = (record["grantID"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        return GoalXPGrant(
            id: id,
            goalID: goalID,
            date: date,
            amount: max(0, Int((record["amount"] as? Int64) ?? 0)),
            awardedAt: awardedAt
        )
    }

    private static func normalized(_ snapshot: GoalMascotCloudSnapshot) -> GoalMascotCloudSnapshot {
        var value = snapshot
        value.name = String(snapshot.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
        if value.name.isEmpty {
            value.name = GoalPetState.empty.name
        }
        value.baselineXP = max(0, snapshot.baselineXP)
        value.rewardCount = max(0, snapshot.rewardCount)
        value.grants = mergeGrants(snapshot.grants)
        return value
    }

    private static func mergeGrants(_ grants: [GoalXPGrant]) -> [GoalXPGrant] {
        var merged: [String: GoalXPGrant] = [:]
        for grant in grants {
            let key = grantKey(for: grant)
            guard let existing = merged[key] else {
                merged[key] = grant
                continue
            }
            if grant.amount > existing.amount
                || (grant.amount == existing.amount && grant.awardedAt < existing.awardedAt) {
                merged[key] = grant
            }
        }
        return merged.values.sorted {
            if $0.date == $1.date {
                return $0.goalID.uuidString < $1.goalID.uuidString
            }
            return $0.date < $1.date
        }
    }
}

private extension Array {
    nonisolated func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { index in
            Array(self[index..<Swift.min(index + size, count)])
        }
    }
}
