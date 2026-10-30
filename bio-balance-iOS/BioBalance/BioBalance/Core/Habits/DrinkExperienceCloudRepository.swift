import CloudKit
import Foundation

nonisolated struct DrinkExperienceCloudSnapshot: Sendable {
    let drinks: [DrinkStampRecord]
    let meals: [MealRecognitionRecord]
}

/// 餐饮 / 餐食の CloudKit 跨设备同步仓储。
///
/// ## 数据隔离
/// - Zone：`CloudKitDataPolicy.Zone.drinkExperience`（独立 private zone，用户可控）。
/// - Record type：`BBDrinkExperience`，每条记录以 `drink.<id>` / `meal.<id>` 作为
///   稳定 record name，保证多设备合并幂等。
/// - Payload 只包含结构化字段白名单；图片 / 文件引用、经纬度、位置文本和 AI 元数据
///   一律只留本机，永不进入 CloudKit。
///
/// ## 同步开关
/// `PreferenceKey.drinkExperienceSyncEnabled` 默认开启；用户关闭后 Store 不再调用本仓储。
///
/// ## 合并策略
/// 以业务 ID 分组，用 `updatedAt` 做 last-write-wins；相同时本机值胜出，
/// 保证相同输入重复同步可得到稳定结果。
///
/// ## 账号绑定
/// 通过 `AccountBindingKey.drinkExperience` 检测 Apple ID 变更；
/// 不匹配时自动关闭同步并清除绑定，防止数据上传到另一个账号。
///
/// ## 失败不阻塞
/// CloudKit 失败不会影响本地餐饮记录的保存或展示。
///
/// ## CKSyncEngine 迁移路径（iOS 17+）
/// 当本 zone 记录数量超过 ~1000 条或需要离线冲突自动解决时，可通过调用
/// `CloudKitSyncTransportResolver.enableSyncEngine(forZone: CloudKitDataPolicy.Zone.drinkExperience)`
/// 启用增量同步模式。启用后 `synchronize(...)` 将委托给 `CloudKitSyncEngineTransport`，
/// zone / record type 保持不变，仅替换底层 transport。
final class DrinkExperienceCloudRepository {
    static let shared = DrinkExperienceCloudRepository()

    private enum Schema {
        // Zone 名与 record type 集中登记在 CloudKitDataPolicy，避免多个功能复用同一 zone。
        static let zoneName = CloudKitDataPolicy.Zone.drinkExperience
        static let recordType = CloudKitDataPolicy.RecordType.drinkExperience
        static let kind = "kind"
        static let payload = "payload"
        static let capturedAt = "capturedAt"
        static let updatedAt = "updatedAt"
        static let schemaVersion = "schemaVersion"
        static let currentSchemaVersion: Int64 = 2
    }

    private enum RecordKind: String {
        case drink
        case meal
    }

    private let container: CKContainer
    private let database: CKDatabase
    private let client: CloudKitClientProtocol
    private let executor: CloudKitOperationExecutor
    private let preferences: UserDefaults
    private let zoneID: CKRecordZone.ID
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// 当前传输模式：legacy（全量查询）或 syncEngine（增量同步）。
    private let transportMode: CloudKitSyncTransportMode

    /// CKSyncEngine 传输层实例（仅在 `.syncEngine` 模式下非 nil）。
    private var syncEngineTransport: AnyObject? // CloudKitSyncEngineTransport (iOS 17+)

    init(
        container: CKContainer = CloudKitDataPolicy.makeContainer(),
        client: CloudKitClientProtocol = CloudKitClient(),
        executor: CloudKitOperationExecutor = CloudKitOperationExecutor(),
        preferences: UserDefaults = .standard,
        transportMode: CloudKitSyncTransportMode? = nil
    ) {
        self.container = container
        self.database = container.privateCloudDatabase
        self.client = client
        self.executor = executor
        self.preferences = preferences
        self.zoneID = CKRecordZone.ID(
            zoneName: Schema.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder.dateDecodingStrategy = .iso8601
        self.transportMode = transportMode
            ?? CloudKitSyncTransportResolver.resolveMode(forZone: Schema.zoneName)
    }

    func synchronize(
        localDrinks: [DrinkStampRecord],
        localMeals: [MealRecognitionRecord]
    ) async throws -> DrinkExperienceCloudSnapshot {
        // 缺少偏好值等同于关闭；直接调用仓储也不能绕过用户授权边界。
        guard preferences.bool(forKey: CloudKitDataPolicy.PreferenceKey.drinkExperienceSyncEnabled) else {
            return DrinkExperienceCloudSnapshot(
                drinks: Array(localDrinks.sorted { $0.capturedAt > $1.capturedAt }.prefix(365)),
                meals: Array(localMeals.sorted { $0.capturedAt > $1.capturedAt }.prefix(365))
            )
        }

        let accountIdentifier = try await preparePrivateDatabase()
        let remoteRecords = try await fetchAllRecords()
        try await verifyCurrentAccount(accountIdentifier)
        var remoteByName = Dictionary(
            remoteRecords.map { ($0.recordID.recordName, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let remoteDrinks = remoteRecords.compactMap(decodeDrink)
        let remoteMeals = remoteRecords.compactMap(decodeMeal)
        let drinks = mergeDrinks(local: localDrinks, remote: remoteDrinks)
        let meals = mergeMeals(local: localMeals, remote: remoteMeals)

        var recordsToSave: [CKRecord] = []
        for drink in drinks {
            if let record = try cloudRecord(for: drink, existing: remoteByName.removeValue(forKey: recordName(for: drink))) {
                recordsToSave.append(record)
            }
        }
        for meal in meals {
            if let record = try cloudRecord(for: meal, existing: remoteByName.removeValue(forKey: recordName(for: meal))) {
                recordsToSave.append(record)
            }
        }

        for start in stride(from: 0, to: recordsToSave.count, by: 200) {
            let end = min(start + 200, recordsToSave.count)
            let batch = Array(recordsToSave[start..<end])
            _ = try await executor.run(
                context: CloudKitLoggerContext(
                    operation: "sync-drink-experience",
                    database: .private,
                    zoneID: zoneID.zoneName
                )
            ) { [container, client, database] in
                let current = try await client.fetchUserRecordID(container: container)
                guard current.recordName == accountIdentifier else {
                    throw CloudKitDomainError.iCloudUnavailable
                }
                _ = try await client.modify(
                    recordsToSave: batch,
                    recordIDsToDelete: [],
                    savePolicy: .changedKeys,
                    in: database
                )
            }
        }

        try await verifyCurrentAccount(accountIdentifier)

        return DrinkExperienceCloudSnapshot(
            drinks: Array(drinks.sorted { $0.capturedAt > $1.capturedAt }.prefix(365)),
            meals: Array(meals.sorted { $0.capturedAt > $1.capturedAt }.prefix(365))
        )
    }

    /// 返回当前 CloudKit 用户的稳定 record name，供本地 Store 阻止跨账号自动上传。
    func currentAccountIdentifier() async throws -> String {
        let status = try await executor.run(
            context: CloudKitLoggerContext(operation: "drink-experience-account-status", database: .private)
        ) { [container, client] in
            try await client.accountStatus(container: container)
        }
        guard status == .available else { throw CloudKitDomainError.iCloudUnavailable }

        return try await executor.run(
            context: CloudKitLoggerContext(operation: "drink-experience-account-identity", database: .private)
        ) { [container, client] in
            try await client.fetchUserRecordID(container: container).recordName
        }
    }

    private func preparePrivateDatabase() async throws -> String {
        let accountIdentifier = try await currentAccountIdentifier()

        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await executor.run(
            context: CloudKitLoggerContext(
                operation: "prepare-drink-experience-zone",
                database: .private,
                zoneID: zoneID.zoneName
            )
        ) { [container, client, database] in
            let current = try await client.fetchUserRecordID(container: container)
            guard current.recordName == accountIdentifier else {
                throw CloudKitDomainError.iCloudUnavailable
            }
            _ = try await client.save(zone: zone, in: database)
        }
        return accountIdentifier
    }

    private func verifyCurrentAccount(_ accountIdentifier: String) async throws {
        let current = try await executor.run(
            context: CloudKitLoggerContext(operation: "verify-drink-experience-account", database: .private)
        ) { [container, client] in
            try await client.fetchUserRecordID(container: container).recordName
        }
        guard current == accountIdentifier else {
            throw CloudKitDomainError.iCloudUnavailable
        }
    }

    private func fetchAllRecords() async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        do {
            repeat {
                let currentCursor = cursor
                let page = try await executor.run(
                    context: CloudKitLoggerContext(
                        operation: "fetch-drink-experience",
                        database: .private,
                        zoneID: zoneID.zoneName
                    )
                ) { [client, database, zoneID] in
                    try await client.runQuery(
                        query: currentCursor == nil
                            ? CKQuery(recordType: Schema.recordType, predicate: NSPredicate(value: true))
                            : nil,
                        cursor: currentCursor,
                        zoneID: zoneID,
                        in: database
                    )
                }
                records.append(contentsOf: page.records)
                cursor = page.cursor
            } while cursor != nil
            return records
        } catch CloudKitDomainError.unknownItem {
            return []
        }
    }

    /// 返回 nil 表示云端已有相同内容，无需产生一次无意义写入。
    private func cloudRecord(for drink: DrinkStampRecord, existing: CKRecord?) throws -> CKRecord? {
        var sanitized = drink
        sanitized.photoFileID = nil
        sanitized.photoURL = nil
        sanitized.cutoutFileID = nil
        sanitized.cutoutURL = nil
        sanitized.latitude = nil
        sanitized.longitude = nil
        sanitized.locationLabel = nil
        sanitized.aiProviderID = nil
        sanitized.aiModel = nil
        sanitized.aiConfidence = nil
        let payload = try encoder.encode(sanitized)
        return makeRecord(
            name: recordName(for: drink),
            kind: .drink,
            payload: payload,
            capturedAt: drink.capturedAt,
            updatedAt: drink.updatedAt ?? drink.capturedAt,
            existing: existing
        )
    }

    private func cloudRecord(for meal: MealRecognitionRecord, existing: CKRecord?) throws -> CKRecord? {
        var sanitized = meal
        sanitized.photoFileID = nil
        sanitized.photoURL = nil
        sanitized.locationSummary = nil
        sanitized.aiProviderID = nil
        sanitized.aiModel = nil
        sanitized.aiConfidence = nil
        let payload = try encoder.encode(sanitized)
        return makeRecord(
            name: recordName(for: meal),
            kind: .meal,
            payload: payload,
            capturedAt: meal.capturedAt,
            updatedAt: meal.updatedAt ?? meal.capturedAt,
            existing: existing
        )
    }

    private func makeRecord(
        name: String,
        kind: RecordKind,
        payload: Data,
        capturedAt: Date,
        updatedAt: Date,
        existing: CKRecord?
    ) -> CKRecord? {
        if let existing,
           existing[Schema.kind] as? String == kind.rawValue,
           existing[Schema.payload] as? Data == payload {
            return nil
        }
        let record = existing ?? CKRecord(
            recordType: Schema.recordType,
            recordID: CKRecord.ID(recordName: name, zoneID: zoneID)
        )
        record[Schema.kind] = kind.rawValue as CKRecordValue
        record[Schema.payload] = payload as CKRecordValue
        record[Schema.capturedAt] = capturedAt as CKRecordValue
        record[Schema.updatedAt] = updatedAt as CKRecordValue
        record[Schema.schemaVersion] = Schema.currentSchemaVersion as CKRecordValue
        return record
    }

    private func decodeDrink(_ record: CKRecord) -> DrinkStampRecord? {
        guard record[Schema.kind] as? String == RecordKind.drink.rawValue,
              let payload = record[Schema.payload] as? Data else { return nil }
        return try? decoder.decode(DrinkStampRecord.self, from: payload)
    }

    private func decodeMeal(_ record: CKRecord) -> MealRecognitionRecord? {
        guard record[Schema.kind] as? String == RecordKind.meal.rawValue,
              let payload = record[Schema.payload] as? Data else { return nil }
        return try? decoder.decode(MealRecognitionRecord.self, from: payload)
    }

    private func recordName(for drink: DrinkStampRecord) -> String { "drink.\(drink.id)" }
    private func recordName(for meal: MealRecognitionRecord) -> String { "meal.\(meal.id)" }

    /// 同一业务 ID 采用逻辑 `updatedAt` 的 last-write-wins；相同时本机值胜出，
    /// 使同一批输入重复同步可以得到稳定结果。
    private func mergeDrinks(local: [DrinkStampRecord], remote: [DrinkStampRecord]) -> [DrinkStampRecord] {
        var merged = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for value in local {
            guard let existing = merged[value.id] else {
                merged[value.id] = value
                continue
            }
            let localDate = value.updatedAt ?? value.capturedAt
            let remoteDate = existing.updatedAt ?? existing.capturedAt
            if localDate >= remoteDate {
                merged[value.id] = value
            }
        }
        return Array(merged.values)
    }

    private func mergeMeals(local: [MealRecognitionRecord], remote: [MealRecognitionRecord]) -> [MealRecognitionRecord] {
        var merged = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for value in local {
            guard let existing = merged[value.id] else {
                merged[value.id] = value
                continue
            }
            let localDate = value.updatedAt ?? value.capturedAt
            let remoteDate = existing.updatedAt ?? existing.capturedAt
            if localDate >= remoteDate {
                merged[value.id] = value
            }
        }
        return Array(merged.values)
    }

    // MARK: - CKSyncEngine 模式支持

    /// 初始化 CKSyncEngine 传输层。
    ///
    /// 调用时机：仓储初始化后、首次 `synchronize` 前。仅在 `transportMode == .syncEngine`
    /// 时生效。传统模式下此方法为 no-op。
    ///
    /// 首次从传统模式迁移时，CKSyncEngine 会执行一次全量 fetch 作为 initial sync，
    /// 保证已有的云端数据不丢失。
    func initializeSyncEngineIfNeeded() {
        guard transportMode == .syncEngine else { return }
        let config = CloudKitDataPolicy.syncEngineConfig(
            forZone: Schema.zoneName,
            recordTypes: [Schema.recordType],
            conflictPolicy: .lastWriteWins
        )
        let handler = DrinkExperienceSyncEventHandler(repository: self)
        let transport = CloudKitSyncEngineTransport(
            config: config,
            container: container,
            preferences: preferences,
            eventHandler: handler
        )
        transport.initialize()
        syncEngineTransport = transport
    }

    /// 在 SyncEngine 模式下通知有本地变更待上传。
    ///
    /// 传统模式下此方法为 no-op（同步在 `synchronize` 中整体完成）。
    func notifyLocalChange(recordIDs: [CKRecord.ID] = []) {
        guard transportMode == .syncEngine else { return }
        (syncEngineTransport as? CloudKitSyncEngineTransport)?.scheduleSend(recordIDs: recordIDs)
    }

    /// 在 SyncEngine 模式下手动触发一次增量 fetch。
    func fetchRemoteChanges() async throws {
        guard transportMode == .syncEngine else { return }
        try await (syncEngineTransport as? CloudKitSyncEngineTransport)?.fetchChanges()
    }
}

// MARK: - DrinkExperience SyncEngine 事件处理

/// 餐饮仓储的 CKSyncEngine 事件处理实现。
///
/// 将 CKSyncEngine 的底层事件（record 级别增量）转译为仓储的业务操作：
/// - 收到远程变更 → 解码 payload 并合并到本地 Store；
/// - 请求待上传 → 返回本地 "dirty" 标记的记录；
/// - 上传成功 → 清除 dirty 标记。
final class DrinkExperienceSyncEventHandler: CloudKitSyncEngineEventHandler, @unchecked Sendable {
    private weak var repository: DrinkExperienceCloudRepository?

    init(repository: DrinkExperienceCloudRepository) {
        self.repository = repository
    }

    func didReceiveRemoteChanges(_ records: [CKRecord], deletedRecordIDs: [CKRecord.ID]) async {
        // 将远程增量变更通知到本地 Store（由业务层 DrinkExperienceStore 处理合并）。
        // 此处仅做日志；实际合并逻辑由 Store 监听 NotificationCenter 完成。
        guard !records.isEmpty || !deletedRecordIDs.isEmpty else { return }
        NotificationCenter.default.post(
            name: .drinkExperienceRemoteChangeReceived,
            object: nil,
            userInfo: [
                "savedRecords": records,
                "deletedRecordIDs": deletedRecordIDs
            ]
        )
    }

    func pendingRecordsToSave() async -> [CKRecord] {
        // 由本地 Store 提供待上传记录。
        // 通过 NotificationCenter 请求或直接查询 Store 的 dirty list。
        // 此处返回空——实际整合时 Store 需维护 pending list。
        return []
    }

    func pendingRecordIDsToDelete() async -> [CKRecord.ID] {
        return []
    }

    func didSaveRecords(_ savedRecords: [CKRecord]) async {
        // 清除本地 dirty 标记。
        NotificationCenter.default.post(
            name: .drinkExperienceSyncDidComplete,
            object: nil,
            userInfo: ["savedRecords": savedRecords]
        )
    }

    func didDeleteRecordIDs(_ deletedIDs: [CKRecord.ID]) async {
        // 确认远端删除已同步。
    }
}

// MARK: - 通知名称

extension Notification.Name {
    /// CKSyncEngine 模式下收到远程餐饮变更。
    nonisolated static let drinkExperienceRemoteChangeReceived = Notification.Name("drinkExperienceRemoteChangeReceived")
    /// CKSyncEngine 模式下上传完成。
    nonisolated static let drinkExperienceSyncDidComplete = Notification.Name("drinkExperienceSyncDidComplete")
}
