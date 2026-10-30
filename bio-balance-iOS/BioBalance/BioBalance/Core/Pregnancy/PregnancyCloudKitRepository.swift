import CloudKit
import Foundation

protocol PregnancyRepositoryProtocol: Sendable {
    func fetchSnapshot() async throws -> PregnancySnapshot
    func saveProfile(_ profile: PregnancyProfile) async throws -> PregnancyProfile
    func saveWeightEntry(_ entry: PregnancyWeightEntry) async throws -> PregnancyWeightEntry
    func deleteWeightEntry(id: String) async throws
    func saveFetalMovementEntry(_ entry: FetalMovementEntry) async throws -> FetalMovementEntry
    func deleteFetalMovementEntry(id: String) async throws
    func deleteAllPregnancyData() async throws
}

enum PregnancyCloudSchema {
    // Zone 与 record type 集中登记在 CloudKitDataPolicy；删除孕期数据即删除整个 zone，
    // 不会波及其他 iCloud 功能。
    static let zoneName = CloudKitDataPolicy.Zone.pregnancy
    static let profileRecordType = CloudKitDataPolicy.RecordType.pregnancyProfile
    static let weightRecordType = CloudKitDataPolicy.RecordType.pregnancyWeightEntry
    static let fetalMovementRecordType = CloudKitDataPolicy.RecordType.fetalMovementEntry
    static let profileRecordName = "current-pregnancy"
    static let legacyPregnancyID = "legacy-current-pregnancy"
    /// 旧 profile 缺少业务 ID 时使用的确定性新 ID，保证多设备同时升级也得到同一值。
    static let migratedPregnancyID = "pregnancy.current"
    static let schemaVersion: Int64 = 3
}

/// 孕期データの CloudKit 跨设备同步仓储。
///
/// ## 数据隔离
/// - Zone：`CloudKitDataPolicy.Zone.pregnancy`（独立 private zone）。
/// - 三种 record type：Profile（单条固定 record name）、WeightEntry、FetalMovementEntry。
/// - 只包含预产期、末次月经、体重、胎动时间等结构化字段；无图片、无第三方元数据。
///
/// ## 同步策略
/// 全局启动与 iCloud 管理页通过 `PreferenceKey.pregnancySyncEnabled` 控制调度，
/// 且默认按需加载。本 Repository 是纯 CloudKit 边界，假定调用方已完成偏好判定。
///
/// ## 删除边界
/// `deleteAllPregnancyData()` 直接删除整个 zone，实现一键清除全部云端孕期记录。
///
/// ## 日期字段兼容
/// Profile 的 `dueDate` / `lastMenstrualPeriod` 同时存储 Date 值与 `yyyy-MM-dd` 格式的
/// day-key 字段，防止跨时区 CloudKit 反序列化导致日期偏移。读取时优先使用 day-key。
///
/// ## CKSyncEngine 迁移路径（iOS 17+）
/// 孕期记录数量通常较少（≤数十条），传统全量查询模式已足够。未来如需增量同步可通过
/// `CloudKitSyncTransportResolver.enableSyncEngine(forZone: CloudKitDataPolicy.Zone.pregnancy)`
/// 启用，zone / record type 保持不变。
final class PregnancyCloudKitRepository: PregnancyRepositoryProtocol, @unchecked Sendable {
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
            zoneName: PregnancyCloudSchema.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
    }

    func fetchSnapshot() async throws -> PregnancySnapshot {
        let accountIdentifier = try await preparePrivateDatabase()
        let profile = try await fetchProfile(accountIdentifier: accountIdentifier)
        let weightRecords = try await fetchAllRecords(ofType: PregnancyCloudSchema.weightRecordType)
        let weights = try weightRecords
            .map { record in
                guard let entry = Self.decodeWeightEntry(record, currentPregnancyID: profile?.id) else {
                    throw CloudKitDomainError.invalidRecord
                }
                return entry
            }
            .filter { $0.pregnancyID == profile?.id }
        let movementRecords = try await fetchAllRecords(ofType: PregnancyCloudSchema.fetalMovementRecordType)
        let movements = try movementRecords
            .map { record in
                guard let entry = Self.decodeFetalMovementEntry(record, currentPregnancyID: profile?.id) else {
                    throw CloudKitDomainError.invalidRecord
                }
                return entry
            }
            .filter { $0.pregnancyID == profile?.id }
        if let currentPregnancyID = profile?.id {
            // 旧记录缺少 pregnancyID，或使用早期占位 ID。读取时已归一到当前孕期，
            // 这里再尝试回写新 schema；迁移失败不影响本次读取。
            try? await migrateLegacyRecords(
                weightRecords + movementRecords,
                to: currentPregnancyID,
                accountIdentifier: accountIdentifier
            )
        }
        try await verifyCurrentAccount(accountIdentifier)

        return PregnancySnapshot(
            profile: profile,
            weightEntries: weights,
            fetalMovementEntries: movements
        )
    }

    func saveProfile(_ profile: PregnancyProfile) async throws -> PregnancyProfile {
        let accountIdentifier = try await preparePrivateDatabase()
        let recordID = CKRecord.ID(
            recordName: PregnancyCloudSchema.profileRecordName,
            zoneID: zoneID
        )
        let existing = try await fetchRecord(with: recordID)
        let record = existing ?? CKRecord(
            recordType: PregnancyCloudSchema.profileRecordType,
            recordID: recordID
        )
        record["pregnancyID"] = profile.id as CKRecordValue
        record["dueDate"] = profile.dueDate as CKRecordValue
        record["lastMenstrualPeriod"] = profile.lastMenstrualPeriod as CKRecordValue
        record["dueDateKey"] = PregnancyDayCoding.key(for: profile.dueDate) as CKRecordValue
        record["lastMenstrualPeriodKey"] = PregnancyDayCoding.key(for: profile.lastMenstrualPeriod) as CKRecordValue
        record["datingTimeZone"] = TimeZone.current.identifier as CKRecordValue
        if let endedAt = profile.endedAt {
            record["endedAt"] = endedAt as CKRecordValue
        } else {
            record["endedAt"] = nil
        }
        let existingPregnancyID = existing.flatMap { $0["pregnancyID"] as? String }
        let createdAt = existingPregnancyID == profile.id
            ? existing.flatMap { $0["createdAt"] as? Date } ?? profile.createdAt
            : profile.createdAt
        record["createdAt"] = createdAt as CKRecordValue
        record["updatedAt"] = profile.updatedAt as CKRecordValue
        record["schemaVersion"] = PregnancyCloudSchema.schemaVersion as CKRecordValue

        let saved = try await save(
            record,
            operation: "save-pregnancy-profile",
            accountIdentifier: accountIdentifier
        )
        guard let decoded = Self.decodeProfile(saved) else {
            throw CloudKitDomainError.invalidRecord
        }
        return decoded
    }

    func saveWeightEntry(_ entry: PregnancyWeightEntry) async throws -> PregnancyWeightEntry {
        let accountIdentifier = try await preparePrivateDatabase()
        let recordID = CKRecord.ID(recordName: entry.id, zoneID: zoneID)
        let existing = try await fetchRecord(with: recordID)
        let record = existing ?? CKRecord(
            recordType: PregnancyCloudSchema.weightRecordType,
            recordID: recordID
        )
        record["pregnancyID"] = entry.pregnancyID as CKRecordValue
        record["measuredAt"] = entry.measuredAt as CKRecordValue
        record["weightKg"] = entry.weightKg as CKRecordValue
        record["createdAt"] = (existing.flatMap { $0["createdAt"] as? Date } ?? entry.createdAt) as CKRecordValue
        record["updatedAt"] = entry.updatedAt as CKRecordValue
        record["schemaVersion"] = PregnancyCloudSchema.schemaVersion as CKRecordValue

        let saved = try await save(
            record,
            operation: "save-pregnancy-weight",
            accountIdentifier: accountIdentifier
        )
        guard let decoded = Self.decodeWeightEntry(saved) else {
            throw CloudKitDomainError.invalidRecord
        }
        return decoded
    }

    func deleteWeightEntry(id: String) async throws {
        try await deleteRecord(
            CKRecord.ID(recordName: id, zoneID: zoneID),
            operation: "delete-pregnancy-weight"
        )
    }

    func saveFetalMovementEntry(_ entry: FetalMovementEntry) async throws -> FetalMovementEntry {
        let accountIdentifier = try await preparePrivateDatabase()
        let recordID = CKRecord.ID(recordName: entry.id, zoneID: zoneID)
        let existing = try await fetchRecord(with: recordID)
        let record = existing ?? CKRecord(
            recordType: PregnancyCloudSchema.fetalMovementRecordType,
            recordID: recordID
        )
        record["pregnancyID"] = entry.pregnancyID as CKRecordValue
        record["occurredAt"] = entry.occurredAt as CKRecordValue
        record["createdAt"] = (existing.flatMap { $0["createdAt"] as? Date } ?? entry.createdAt) as CKRecordValue
        record["updatedAt"] = entry.updatedAt as CKRecordValue
        record["schemaVersion"] = PregnancyCloudSchema.schemaVersion as CKRecordValue

        let saved = try await save(
            record,
            operation: "save-fetal-movement",
            accountIdentifier: accountIdentifier
        )
        guard let decoded = Self.decodeFetalMovementEntry(saved) else {
            throw CloudKitDomainError.invalidRecord
        }
        return decoded
    }

    func deleteFetalMovementEntry(id: String) async throws {
        try await deleteRecord(
            CKRecord.ID(recordName: id, zoneID: zoneID),
            operation: "delete-fetal-movement"
        )
    }

    func deleteAllPregnancyData() async throws {
        let accountIdentifier = try await preparePrivateDatabase()
        try await executor.run(
            context: CloudKitLoggerContext(
                operation: "delete-pregnancy-zone",
                database: .private,
                zoneID: zoneID.zoneName
            )
        ) { [container, client, database, zoneID] in
            let current = try await client.fetchUserRecordID(container: container)
            guard current.recordName == accountIdentifier else {
                throw CloudKitDomainError.iCloudUnavailable
            }
            try await client.delete(zoneID: zoneID, in: database)
        }
    }

    private func preparePrivateDatabase() async throws -> String {
        let status = try await executor.run(
            context: CloudKitLoggerContext(operation: "pregnancy-account-status", database: .private)
        ) { [container, client] in
            try await client.accountStatus(container: container)
        }

        guard status == .available else {
            throw CloudKitDomainError.iCloudUnavailable
        }

        let accountIdentifier = try await executor.run(
            context: CloudKitLoggerContext(operation: "pregnancy-account-identity", database: .private)
        ) { [container, client] in
            try await client.fetchUserRecordID(container: container).recordName
        }

        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await executor.run(
            context: CloudKitLoggerContext(
                operation: "prepare-pregnancy-zone",
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
            context: CloudKitLoggerContext(operation: "verify-pregnancy-account", database: .private)
        ) { [container, client] in
            try await client.fetchUserRecordID(container: container).recordName
        }
        guard current == accountIdentifier else {
            throw CloudKitDomainError.iCloudUnavailable
        }
    }

    private func fetchProfile(accountIdentifier: String) async throws -> PregnancyProfile? {
        let recordID = CKRecord.ID(
            recordName: PregnancyCloudSchema.profileRecordName,
            zoneID: zoneID
        )
        guard let record = try await fetchRecord(with: recordID) else { return nil }
        guard let profile = Self.decodeProfile(record) else {
            throw CloudKitDomainError.invalidRecord
        }
        try? await migrateLegacyRecords(
            [record],
            to: profile.id,
            accountIdentifier: accountIdentifier
        )
        return profile
    }

    private func fetchRecord(with recordID: CKRecord.ID) async throws -> CKRecord? {
        try await executor.run(
            context: CloudKitLoggerContext(
                operation: "fetch-pregnancy-record",
                database: .private,
                zoneID: zoneID.zoneName,
                recordID: recordID.recordName
            )
        ) { [client, database] in
            try await client.fetch(recordID: recordID, in: database)
        }
    }

    private func fetchAllRecords(ofType recordType: String) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            do {
                let currentCursor = cursor
                let page = try await executor.run(
                    context: CloudKitLoggerContext(
                        operation: "query-\(recordType)",
                        database: .private,
                        zoneID: zoneID.zoneName
                    )
                ) { [client, database, zoneID] in
                    try await client.runQuery(
                        query: currentCursor == nil
                            ? CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                            : nil,
                        cursor: currentCursor,
                        zoneID: zoneID,
                        in: database
                    )
                }
                records.append(contentsOf: page.records)
                cursor = page.cursor
            } catch CloudKitDomainError.unknownItem {
                return []
            }
        } while cursor != nil

        return records
    }

    private func save(
        _ record: CKRecord,
        operation: String,
        accountIdentifier: String
    ) async throws -> CKRecord {
        try await executor.run(
            context: CloudKitLoggerContext(
                operation: operation,
                database: .private,
                zoneID: zoneID.zoneName,
                recordID: record.recordID.recordName
            )
        ) { [container, client, database] in
            let current = try await client.fetchUserRecordID(container: container)
            guard current.recordName == accountIdentifier else {
                throw CloudKitDomainError.iCloudUnavailable
            }
            return try await client.save(record: record, in: database)
        }
    }

    private func migrateLegacyRecords(
        _ records: [CKRecord],
        to currentPregnancyID: String,
        accountIdentifier: String
    ) async throws {
        let recordsToMigrate = records.filter { record in
            let rawID = record["pregnancyID"] as? String
            let storedID = rawID?.trimmingCharacters(in: .whitespacesAndNewlines)
            return storedID == nil || storedID?.isEmpty == true || storedID == PregnancyCloudSchema.legacyPregnancyID
        }
        guard !recordsToMigrate.isEmpty else { return }

        for record in recordsToMigrate {
            record["pregnancyID"] = currentPregnancyID as CKRecordValue
            record["schemaVersion"] = PregnancyCloudSchema.schemaVersion as CKRecordValue
        }

        _ = try await executor.run(
            context: CloudKitLoggerContext(
                operation: "migrate-pregnancy-records",
                database: .private,
                zoneID: zoneID.zoneName
            )
        ) { [container, client, database] in
            let current = try await client.fetchUserRecordID(container: container)
            guard current.recordName == accountIdentifier else {
                throw CloudKitDomainError.iCloudUnavailable
            }
            return try await client.modify(
                recordsToSave: recordsToMigrate,
                recordIDsToDelete: [],
                savePolicy: .changedKeys,
                in: database
            )
        }
    }

    private func deleteRecord(_ recordID: CKRecord.ID, operation: String) async throws {
        let accountIdentifier = try await preparePrivateDatabase()
        guard try await fetchRecord(with: recordID) != nil else { return }
        _ = try await executor.run(
            context: CloudKitLoggerContext(
                operation: operation,
                database: .private,
                zoneID: zoneID.zoneName,
                recordID: recordID.recordName
            )
        ) { [container, client, database] in
            let current = try await client.fetchUserRecordID(container: container)
            guard current.recordName == accountIdentifier else {
                throw CloudKitDomainError.iCloudUnavailable
            }
            return try await client.modify(
                recordsToSave: [],
                recordIDsToDelete: [recordID],
                savePolicy: .ifServerRecordUnchanged,
                in: database
            )
        }
    }

    static func decodeProfile(_ record: CKRecord) -> PregnancyProfile? {
        let dueDate = (record["dueDateKey"] as? String).flatMap { PregnancyDayCoding.date(from: $0) }
            ?? record["dueDate"] as? Date
        let lastMenstrualPeriod = (record["lastMenstrualPeriodKey"] as? String).flatMap { PregnancyDayCoding.date(from: $0) }
            ?? record["lastMenstrualPeriod"] as? Date
        guard let dueDate, let lastMenstrualPeriod else {
            return nil
        }
        let storedPregnancyID = record["pregnancyID"] as? String
        let rawPregnancyID = storedPregnancyID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pregnancyID: String
        if let rawPregnancyID,
           !rawPregnancyID.isEmpty,
           rawPregnancyID != PregnancyCloudSchema.legacyPregnancyID {
            pregnancyID = rawPregnancyID
        } else {
            pregnancyID = PregnancyCloudSchema.migratedPregnancyID
        }
        let endedAt = record["endedAt"] as? Date
        let createdAt = record["createdAt"] as? Date ?? record.creationDate ?? Date()
        let updatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? createdAt
        return PregnancyProfile(
            id: pregnancyID,
            dueDate: dueDate,
            lastMenstrualPeriod: lastMenstrualPeriod,
            endedAt: endedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func decodeWeightEntry(
        _ record: CKRecord,
        currentPregnancyID: String? = nil
    ) -> PregnancyWeightEntry? {
        let pregnancyID = resolvedPregnancyID(in: record, currentPregnancyID: currentPregnancyID)
        guard let measuredAt = record["measuredAt"] as? Date,
              let weightKg = (record["weightKg"] as? NSNumber)?.doubleValue,
              weightKg > 0 else {
            return nil
        }
        let createdAt = record["createdAt"] as? Date ?? record.creationDate ?? Date()
        let updatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? createdAt
        return PregnancyWeightEntry(
            id: record.recordID.recordName,
            pregnancyID: pregnancyID,
            measuredAt: measuredAt,
            weightKg: weightKg,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func decodeFetalMovementEntry(
        _ record: CKRecord,
        currentPregnancyID: String? = nil
    ) -> FetalMovementEntry? {
        let pregnancyID = resolvedPregnancyID(in: record, currentPregnancyID: currentPregnancyID)
        guard let occurredAt = record["occurredAt"] as? Date else { return nil }
        let createdAt = record["createdAt"] as? Date ?? record.creationDate ?? Date()
        let updatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? createdAt
        return FetalMovementEntry(
            id: record.recordID.recordName,
            pregnancyID: pregnancyID,
            occurredAt: occurredAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func resolvedPregnancyID(
        in record: CKRecord,
        currentPregnancyID: String?
    ) -> String {
        let rawID = record["pregnancyID"] as? String
        let storedID = rawID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let storedID,
           !storedID.isEmpty,
           storedID != PregnancyCloudSchema.legacyPregnancyID {
            return storedID
        }
        return currentPregnancyID ?? PregnancyCloudSchema.migratedPregnancyID
    }
}

enum PregnancyCloudErrorText {
    static func message(for error: Error) -> String {
        guard let cloudError = error as? CloudKitDomainError else {
            return String(localized: "暂时无法连接 iCloud，请稍后重试。")
        }

        switch cloudError {
        case .iCloudUnavailable:
            return String(localized: "iCloud 账号已变化或暂时不可用，请重试。")
        case .notAuthenticated:
            return String(localized: "请先在系统设置中登录 iCloud，然后重试。")
        case .networkUnavailable:
            return String(localized: "当前网络不可用，连接网络后可继续同步。")
        case .quotaExceeded:
            return String(localized: "iCloud 存储空间不足，释放空间后再试。")
        case .badContainer:
            return String(localized: "iCloud 容器配置异常，请更新应用或联系支持。")
        case .requestRateLimited(let retryAfter):
            if let retryAfter {
                return String(localized: "iCloud 请求较频繁，请在 \(Int(ceil(retryAfter))) 秒后重试。")
            }
            return String(localized: "iCloud 请求较频繁，请稍后重试。")
        case .serviceUnavailable, .serverRejectedRequest:
            return String(localized: "iCloud 服务暂时不可用，请稍后重试。")
        case .invalidRecord, .partialFailure:
            return String(localized: "iCloud 中的孕期记录暂时无法读取，请重试。")
        default:
            return String(localized: "孕期记录未能同步到 iCloud，请稍后重试。")
        }
    }
}
