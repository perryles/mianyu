import CloudKit
import Foundation
import os

// MARK: - CKSyncEngine 增量同步传输层
//
// 本文件提供基于 CKSyncEngine（iOS 17+）的增量同步传输层，作为现有
// CloudKitOperationExecutor + 手动全量查询架构的**可选升级路径**。
//
// ## 何时启用 CKSyncEngine 模式
// - 某个 zone 的记录数量超过 ~1000 条，全量拉取的开销开始影响用户体验；
// - 业务需要离线冲突自动解决（而非简单 last-write-wins）；
// - 需要实时增量推送（remote notification → 增量 fetch → UI 更新）。
//
// ## 迁移约束
// - zone 名称和 record type 保持不变（均已在 CloudKitDataPolicy 注册）；
// - 仅替换底层 transport 逻辑，上层业务接口（Repository protocol）保持一致；
// - 现有数据不丢失——首次启用 SyncEngine 模式时执行一次全量同步到本地缓存。
//
// ## 架构关系
// ```
// Repository (业务逻辑)
//    ├── LegacyTransport (CloudKitOperationExecutor + CloudKitClient)
//    └── SyncEngineTransport (CKSyncEngine + 本地持久化)
// ```
//
// ## 多 Zone 并行注意事项
// 当前设计为 **per-zone 独立实例**：每个启用 SyncEngine 的 zone 各自拥有一个
// `CloudKitSyncEngineTransport` 实例。这意味着：
// - 各仓储完全解耦，可独立启用/禁用，无需跨域协调；
// - 同一 private database 下若有 N 个 zone 同时启用，会创建 N 个 CKSyncEngine 实例，
//   它们各自维护独立的 change token 并都会收到 database-level 的变更通知。
//   每个实例只处理自己 zone 的记录，其余自动忽略。
//
// 当未来同时启用 SyncEngine 的 zone 超过 3 个时，建议重构为 **单一共享 CKSyncEngine
// + zone 路由** 模式（类似 Apple 官方 Sample），以减少重复 fetch 开销。
// 当前阶段（≤2 个 zone 可能需要 SyncEngine）per-zone 方案更简单且无数据风险。

// MARK: - 同步传输模式

/// 同步传输模式——决定仓储使用传统全量查询还是 CKSyncEngine 增量同步。
///
/// 各仓储在初始化时通过 `CloudKitSyncTransportResolver` 获取当前模式，
/// 运行期间不会动态切换（需要重启 / 重新初始化仓储才能生效）。
nonisolated enum CloudKitSyncTransportMode: String, Sendable {
    /// 传统模式：全量 CKQuery 拉取 + last-write-wins 合并。
    /// 适合 ≤ 数百条记录的域，当前所有仓储的默认模式。
    case legacy

    /// CKSyncEngine 增量模式：基于服务端 change token 的增量同步，
    /// 支持离线累积、冲突回调和断点续传。
    case syncEngine
}

// MARK: - 同步引擎配置

/// CKSyncEngine 域配置。每个需要启用 SyncEngine 的 zone 需提供一份配置。
///
/// - `zoneName`：必须与 `CloudKitDataPolicy.Zone` 中注册的值完全一致。
/// - `recordTypes`：该 zone 下所有参与同步的 record type。
/// - `conflictPolicy`：发生 `.serverRecordChanged` 时的自动解决策略。
/// - `stateSerializationKey`：CKSyncEngine.State.Serialization 的本地持久化 key。
nonisolated struct CloudKitSyncEngineZoneConfig: Sendable {
    let zoneName: String
    let recordTypes: [String]
    let conflictPolicy: CloudKitSyncConflictPolicy
    let stateSerializationKey: String

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }
}

/// 冲突解决策略——在 CKSyncEngine 的 `handleEvent(.sentRecordZoneChanges)` 回调中
/// 遇到 `.serverRecordChanged` 时使用。
///
/// - `lastWriteWins`：与传统模式一致，比较 `updatedAt` 字段选择较新的版本；
/// - `mergeFields`：逐字段合并——对数值字段取较大值 / 对集合字段取并集；
/// - `askDelegate`：将冲突上报给 `CloudKitSyncConflictDelegate` 由业务逻辑决定。
nonisolated enum CloudKitSyncConflictPolicy: String, Sendable {
    case lastWriteWins
    case mergeFields
    case askDelegate
}

// MARK: - 冲突代理协议

/// 业务层实现此协议以处理 CKSyncEngine 报告的记录级冲突。
///
/// 仅在 `conflictPolicy == .askDelegate` 时调用。
/// 返回的 `CKRecord` 将作为冲突解决结果写回服务端。
nonisolated protocol CloudKitSyncConflictDelegate: Sendable {
    /// 解决单条记录冲突。
    ///
    /// - Parameters:
    ///   - clientRecord: 本端（待上传）的版本。
    ///   - serverRecord: 服务端当前最新版本。
    /// - Returns: 合并后应覆盖到服务端的最终记录；返回 `nil` 表示放弃本端变更。
    func resolveConflict(
        clientRecord: CKRecord,
        serverRecord: CKRecord
    ) async -> CKRecord?
}

// MARK: - 同步事件回调协议

/// CKSyncEngine 事件回调——仓储实现此协议以响应增量变更。
///
/// 与 CKSyncEngine.Delegate 的区别：本协议已将 CKSyncEngine 的底层事件
/// 转译为业务级别的 "收到远程变更" / "本地待上传记录" / "冲突" 三类事件，
/// 仓储无需直接与 CKSyncEngine.Event 交互。
nonisolated protocol CloudKitSyncEngineEventHandler: Sendable {
    /// 收到远程增量变更后调用。仓储在此将 CKRecord 转换为本地模型并持久化。
    func didReceiveRemoteChanges(_ records: [CKRecord], deletedRecordIDs: [CKRecord.ID]) async

    /// SyncEngine 需要本地待上传的记录时调用。
    /// 仓储返回所有在上次同步后本地新增 / 修改的记录。
    func pendingRecordsToSave() async -> [CKRecord]

    /// SyncEngine 需要本地待删除的 record ID 时调用。
    func pendingRecordIDsToDelete() async -> [CKRecord.ID]

    /// 上传成功后调用。仓储在此清除本地 "待同步" 标记。
    func didSaveRecords(_ savedRecords: [CKRecord]) async

    /// 删除成功后调用。
    func didDeleteRecordIDs(_ deletedIDs: [CKRecord.ID]) async
}

// MARK: - CKSyncEngine 传输层封装

/// 基于 CKSyncEngine 的增量同步传输层。
///
/// ## 生命周期
/// 1. 调用 `initialize()` → 从 UserDefaults 恢复 `CKSyncEngine.State.Serialization`
///    并创建 CKSyncEngine 实例。
/// 2. CKSyncEngine 自动在后台执行增量 fetch / send 循环。
/// 3. 收到远程变更 → 通过 `eventHandler` 回调给仓储。
/// 4. 本地有新增 → 仓储调用 `scheduleSend()` 触发上传。
/// 5. 应用退出时 CKSyncEngine 自动持久化 state serialization。
///
/// ## 首次迁移
/// 若 `stateSerializationKey` 对应的本地存储为空，说明是从传统模式首次迁移，
/// CKSyncEngine 将执行一次全量 fetch（相当于 initial sync），不会丢失现有云端数据。
///
/// ## 线程安全
/// `CKSyncEngine` 本身是 thread-safe 的；本类的引擎引用与冲突暂存记录由
/// `NSLock` 保护，可安全跨 actor 使用。`UserDefaults` 的同步访问由 Foundation 保证。
nonisolated final class CloudKitSyncEngineTransport: NSObject, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "SyncEngine")

    private let config: CloudKitSyncEngineZoneConfig
    private let container: CKContainer
    private let database: CKDatabase
    private let preferences: UserDefaults
    private let conflictDelegate: (any CloudKitSyncConflictDelegate)?
    private let eventHandler: any CloudKitSyncEngineEventHandler

    /// 底层 CKSyncEngine 实例；`initialize()` 后可用。
    /// 使用 NSLock 保护以满足 Sendable 要求。
    private let engineLock = NSLock()
    private var _engine: CKSyncEngine?

    /// 冲突解决产物必须保留服务端 change tag。若只重新登记 record ID，
    /// Repository Outbox 可能再次提供旧 client record，造成重复冲突。
    private let resolvedRecordsLock = NSLock()
    private var resolvedRecords: [CKRecord.ID: CKRecord] = [:]

    private var engine: CKSyncEngine? {
        engineLock.withLock { _engine }
    }

    init(
        config: CloudKitSyncEngineZoneConfig,
        container: CKContainer = CloudKitDataPolicy.makeContainer(),
        preferences: UserDefaults = .standard,
        conflictDelegate: (any CloudKitSyncConflictDelegate)? = nil,
        eventHandler: any CloudKitSyncEngineEventHandler
    ) {
        self.config = config
        self.container = container
        self.database = container.privateCloudDatabase
        self.preferences = preferences
        self.conflictDelegate = conflictDelegate
        self.eventHandler = eventHandler
        super.init()
    }

    // MARK: - 公开接口

    /// 初始化并启动 CKSyncEngine。
    ///
    /// 从 UserDefaults 恢复上次持久化的 state serialization；如果不存在（首次迁移），
    /// CKSyncEngine 将自动执行一次全量 fetch 作为 initial sync。
    func initialize() {
        guard engine == nil else {
            Self.logger.debug("[SyncEngine] initialize ignored because engine already exists zone=\(self.config.zoneName, privacy: .public)")
            return
        }
        let serialization = loadStateSerialization()
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: serialization,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        engineLock.withLock { _engine = engine }
        Self.logger.info("[SyncEngine] initialized zone=\(self.config.zoneName, privacy: .public) hasState=\(serialization != nil, privacy: .public)")
    }

    /// 通知 CKSyncEngine 有本地变更待上传。
    ///
    /// 仓储在本地新增 / 修改记录后调用此方法，SyncEngine 将在下次 send 周期
    /// 通过 `nextRecordZoneChangeBatch` 回调获取实际的 pending records。
    ///
    /// - Parameter recordIDs: 具体的待上传记录 ID。若为空，则先确保 zone 存在
    ///   （适用于首次同步 zone 尚未创建的场景），实际记录仍由 `nextRecordZoneChangeBatch` 提供。
    func scheduleSend(recordIDs: [CKRecord.ID] = []) {
        guard let engine else {
            Self.logger.warning("[SyncEngine] scheduleSend called before initialize")
            return
        }
        if recordIDs.isEmpty {
            // 确保 zone 存在，并把仓储 Outbox 中的记录登记为 pending change。
            // RecordZoneChangeBatch 只会为 state 中已经登记的 change 请求实体；
            // 仅返回 pendingRecordsToSave() 并不能触发上传。
            engine.state.add(pendingDatabaseChanges: [
                .saveZone(CKRecordZone(zoneID: config.zoneID))
            ])
            Task { [weak self, weak engine] in
                guard let self, let engine else { return }
                let records = await self.eventHandler.pendingRecordsToSave()
                let deletions = await self.eventHandler.pendingRecordIDsToDelete()
                let saveChanges = records
                    .filter { self.accepts($0) }
                    .map { CKSyncEngine.PendingRecordZoneChange.saveRecord($0.recordID) }
                let deleteChanges = deletions
                    .filter { $0.zoneID == self.config.zoneID }
                    .map { CKSyncEngine.PendingRecordZoneChange.deleteRecord($0) }
                let changes = saveChanges + deleteChanges
                if !changes.isEmpty {
                    engine.state.add(pendingRecordZoneChanges: changes)
                }
            }
        } else {
            let validRecordIDs = recordIDs.filter { $0.zoneID == config.zoneID }
            guard !validRecordIDs.isEmpty else {
                Self.logger.warning("[SyncEngine] ignored save IDs outside configured zone=\(self.config.zoneName, privacy: .public)")
                return
            }
            engine.state.add(pendingRecordZoneChanges: validRecordIDs.map {
                .saveRecord($0)
            })
        }
    }

    /// 通知 CKSyncEngine 有本地删除待同步。
    func scheduleDelete(recordIDs: [CKRecord.ID]) {
        guard let engine else { return }
        let validRecordIDs = recordIDs.filter { $0.zoneID == config.zoneID }
        guard !validRecordIDs.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: validRecordIDs.map {
            .deleteRecord($0)
        })
    }

    /// 处理远程推送通知。
    ///
    /// **注意**：CKSyncEngine（iOS 17+）在 `automaticallySync = true`（默认）时
    /// 会自动监听并处理 CloudKit silent push，无需手动调用此方法。
    /// 仅在需要精确日志追踪或 `automaticallySync = false` 时使用。
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        Self.logger.info("[SyncEngine] remote notification received zone=\(self.config.zoneName, privacy: .public)")
    }

    /// 手动触发一次 fetch 周期（适用于收到远程推送通知后）。
    func fetchChanges() async throws {
        guard let engine else {
            throw CloudKitDomainError.iCloudUnavailable
        }
        try await engine.fetchChanges()
    }

    /// 手动触发一次 send 周期（适用于应用即将退出时的最后尝试）。
    func sendChanges() async throws {
        guard let engine else {
            throw CloudKitDomainError.iCloudUnavailable
        }
        try await engine.sendChanges()
    }

    // MARK: - State 持久化

    private func loadStateSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = preferences.data(forKey: config.stateSerializationKey) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        } catch {
            // 损坏或不兼容的 change token 不能阻止同步启动。删除后让
            // CKSyncEngine 执行一次安全的 initial sync。
            preferences.removeObject(forKey: config.stateSerializationKey)
            Self.logger.error("[SyncEngine] discarded invalid state zone=\(self.config.zoneName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func saveStateSerialization(_ serialization: CKSyncEngine.State.Serialization) {
        do {
            preferences.set(try JSONEncoder().encode(serialization), forKey: config.stateSerializationKey)
        } catch {
            Self.logger.error("[SyncEngine] failed to persist state zone=\(self.config.zoneName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func accepts(_ record: CKRecord) -> Bool {
        record.recordID.zoneID == config.zoneID && config.recordTypes.contains(record.recordType)
    }
}

// MARK: - CKSyncEngine 代理

extension CloudKitSyncEngineTransport: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let stateUpdate):
            saveStateSerialization(stateUpdate.stateSerialization)

        case .accountChange(let accountChange):
            handleAccountChange(accountChange)

        case .fetchedDatabaseChanges(let fetchedChanges):
            handleFetchedDatabaseChanges(fetchedChanges)

        case .fetchedRecordZoneChanges(let fetchedChanges):
            await handleFetchedRecordZoneChanges(fetchedChanges)

        case .sentRecordZoneChanges(let sentChanges):
            await handleSentRecordZoneChanges(sentChanges, syncEngine: syncEngine)

        case .sentDatabaseChanges:
            break

        case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .willSendChanges, .didSendChanges, .didFetchChanges:
            break

        @unknown default:
            Self.logger.warning("[SyncEngine] unhandled event type")
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        // 按 scope 过滤本 zone 的 pending changes（遵循 Apple 官方模式）。
        let scope = context.options.scope
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges.filter {
            scope.contains($0) && $0.targetRecordID?.zoneID == config.zoneID
        }

        let pendingSaves = (await eventHandler.pendingRecordsToSave()).filter { accepts($0) }
        let pendingDeletes = (await eventHandler.pendingRecordIDsToDelete()).filter { $0.zoneID == config.zoneID }

        guard !pendingSaves.isEmpty || !pendingDeletes.isEmpty || !pendingChanges.isEmpty else {
            return nil
        }

        // 使用 pendingChanges + recordProvider 初始化器——Apple 推荐模式。
        var recordsByID = Dictionary(pendingSaves.map { ($0.recordID, $0) }, uniquingKeysWith: { first, _ in first })
        for change in pendingChanges {
            if let recordID = change.targetRecordID,
               let resolved = resolvedRecord(for: recordID) {
                recordsByID[recordID] = resolved
            }
        }
        let recordLookup = recordsByID
        let deleteSet = Set(pendingDeletes)

        let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pendingChanges) { recordID in
            if deleteSet.contains(recordID) {
                return nil
            }
            return recordLookup[recordID]
        }
        return batch
    }

    // MARK: - 事件处理

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signOut, .switchAccounts:
            // Apple ID 变更——清除本地 sync state 和 account binding，
            // 等同于传统模式的 AccountBindingKey 检测 + 禁用同步偏好。
            preferences.removeObject(forKey: config.stateSerializationKey)

            // 根据 zone 清除对应的 AccountBindingKey 和同步偏好。
            switch config.zoneName {
            case CloudKitDataPolicy.Zone.drinkExperience:
                preferences.removeObject(forKey: CloudKitDataPolicy.AccountBindingKey.drinkExperience)
                preferences.set(false, forKey: CloudKitDataPolicy.PreferenceKey.drinkExperienceSyncEnabled)
            case CloudKitDataPolicy.Zone.sleep:
                preferences.removeObject(forKey: CloudKitDataPolicy.AccountBindingKey.sleepSummary)
                preferences.set(false, forKey: CloudKitDataPolicy.PreferenceKey.sleepSummarySyncEnabled)
            case CloudKitDataPolicy.Zone.medicationHealth:
                preferences.removeObject(forKey: CloudKitDataPolicy.AccountBindingKey.medicationHealth)
                preferences.set(false, forKey: CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled)
            case CloudKitDataPolicy.Zone.goalMascot:
                preferences.removeObject(forKey: CloudKitDataPolicy.AccountBindingKey.goalMascot)
            default:
                break
            }

            Self.logger.info("[SyncEngine] account changed, state + binding cleared zone=\(self.config.zoneName, privacy: .public)")
        case .signIn:
            Self.logger.info("[SyncEngine] account signed in zone=\(self.config.zoneName, privacy: .public)")
        @unknown default:
            break
        }
    }

    private func handleFetchedDatabaseChanges(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges) {
        // database-level changes（zone 创建/删除）通常不需要业务处理。
        for deletion in changes.deletions {
            if deletion.zoneID == config.zoneID {
                Self.logger.warning("[SyncEngine] zone deleted remotely zone=\(self.config.zoneName, privacy: .public)")
            }
        }
    }

    private func handleFetchedRecordZoneChanges(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        // per-zone transport 共享同一个 private database，必须主动隔离事件，
        // 否则一个仓储可能误消费另一个业务域的记录或删除事件。
        let modifications = changes.modifications.map(\.record).filter { accepts($0) }
        let deletions = changes.deletions.map(\.recordID).filter { $0.zoneID == config.zoneID }

        guard !modifications.isEmpty || !deletions.isEmpty else { return }

        Self.logger.info("[SyncEngine] fetched zone=\(self.config.zoneName, privacy: .public) saved=\(modifications.count, privacy: .public) deleted=\(deletions.count, privacy: .public)")

        await eventHandler.didReceiveRemoteChanges(modifications, deletedRecordIDs: deletions)
    }

    private func handleSentRecordZoneChanges(_ changes: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine) async {
        // 处理成功保存。
        let savedRecords = changes.savedRecords
        if !savedRecords.isEmpty {
            removeResolvedRecords(withIDs: savedRecords.map(\.recordID))
            await eventHandler.didSaveRecords(savedRecords)
        }

        // 处理成功删除。
        let deletedIDs = changes.deletedRecordIDs
        if !deletedIDs.isEmpty {
            await eventHandler.didDeleteRecordIDs(deletedIDs)
        }

        // 处理失败的保存——按错误码分类处理。
        var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] = []
        var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] = []

        for failedSave in changes.failedRecordSaves {
            let failedRecord = failedSave.record

            let ckError = failedSave.error

            switch ckError.code {
            case .serverRecordChanged:
                // 冲突：按配置的策略解决。
                handleConflict(clientRecord: failedRecord, serverRecord: ckError.serverRecord)

            case .zoneNotFound:
                // Zone 不存在——创建 zone 后重试保存。
                let zone = CKRecordZone(zoneID: failedRecord.recordID.zoneID)
                pendingDatabaseChanges.append(.saveZone(zone))
                pendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))

            case .unknownItem:
                // 本地缓存的 server record 已不存在——清除缓存后重试上传。
                pendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))

            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled:
                // CKSyncEngine 会自动重试这些瞬时错误，仅做日志。
                Self.logger.debug("[SyncEngine] retryable error record=\(failedRecord.recordID.recordName, privacy: .public) code=\(ckError.code.rawValue, privacy: .public)")

            default:
                Self.logger.error("[SyncEngine] unhandled error saving record=\(failedRecord.recordID.recordName, privacy: .public) code=\(ckError.code.rawValue, privacy: .public) desc=\(ckError.localizedDescription, privacy: .public)")
            }
        }

        if !pendingDatabaseChanges.isEmpty {
            syncEngine.state.add(pendingDatabaseChanges: pendingDatabaseChanges)
        }
        if !pendingRecordZoneChanges.isEmpty {
            syncEngine.state.add(pendingRecordZoneChanges: pendingRecordZoneChanges)
        }
    }

    // MARK: - 冲突解决

    private func handleConflict(clientRecord: CKRecord, serverRecord: CKRecord?) {
        guard let serverRecord else {
            Self.logger.warning("[SyncEngine] conflict without server record, dropping client change")
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let resolvedRecord: CKRecord?

            switch self.config.conflictPolicy {
            case .lastWriteWins:
                resolvedRecord = Self.resolveByLastWriteWins(client: clientRecord, server: serverRecord)

            case .mergeFields:
                resolvedRecord = Self.resolveByFieldMerge(client: clientRecord, server: serverRecord)

            case .askDelegate:
                resolvedRecord = await self.conflictDelegate?.resolveConflict(
                    clientRecord: clientRecord,
                    serverRecord: serverRecord
                )
            }

            if let resolvedRecord {
                self.storeResolvedRecord(resolvedRecord)
                self.scheduleSend(recordIDs: [resolvedRecord.recordID])
            }
        }
    }

    private func storeResolvedRecord(_ record: CKRecord) {
        resolvedRecordsLock.withLock {
            resolvedRecords[record.recordID] = record
        }
    }

    private func resolvedRecord(for recordID: CKRecord.ID) -> CKRecord? {
        resolvedRecordsLock.withLock { resolvedRecords[recordID] }
    }

    private func removeResolvedRecords(withIDs recordIDs: [CKRecord.ID]) {
        resolvedRecordsLock.withLock {
            recordIDs.forEach { resolvedRecords.removeValue(forKey: $0) }
        }
    }

    /// last-write-wins：比较 `updatedAt` 字段，较新者覆盖。
    private static func resolveByLastWriteWins(client: CKRecord, server: CKRecord) -> CKRecord? {
        let clientDate = client[CloudKitDataPolicy.MetadataField.updatedAt] as? Date ?? .distantPast
        let serverDate = server[CloudKitDataPolicy.MetadataField.updatedAt] as? Date ?? .distantPast

        if clientDate >= serverDate {
            // 本端较新：将本端字段写入 server record（保留 server 的 change tag）。
            for key in client.allKeys() {
                server[key] = client[key]
            }
            return server
        } else {
            // 服务端较新：放弃本端变更，接受 server 版本。
            return nil
        }
    }

    /// field-merge：对数值字段取较大值，对字符串/日期字段按 updatedAt 选择。
    private static func resolveByFieldMerge(client: CKRecord, server: CKRecord) -> CKRecord? {
        let clientDate = client[CloudKitDataPolicy.MetadataField.updatedAt] as? Date ?? .distantPast
        let serverDate = server[CloudKitDataPolicy.MetadataField.updatedAt] as? Date ?? .distantPast

        // 基于 server record 做合并（保留其 change tag）。
        for key in client.allKeys() {
            let clientValue = client[key]
            let serverValue = server[key]

            // 数值字段：取较大值。
            if let clientNum = clientValue as? NSNumber, let serverNum = serverValue as? NSNumber {
                server[key] = max(clientNum.doubleValue, serverNum.doubleValue) as CKRecordValue
            }
            // 日期字段：取较新值。
            else if let clientDateVal = clientValue as? Date, let serverDateVal = serverValue as? Date {
                server[key] = max(clientDateVal, serverDateVal) as CKRecordValue
            }
            // 其他字段：按整体 updatedAt 选择。
            else if clientDate >= serverDate {
                server[key] = clientValue
            }
        }

        // updatedAt 统一设为最新时间。
        server[CloudKitDataPolicy.MetadataField.updatedAt] = max(clientDate, serverDate) as CKRecordValue
        return server
    }
}

private extension CKSyncEngine.PendingRecordZoneChange {
    var targetRecordID: CKRecord.ID? {
        switch self {
        case .saveRecord(let recordID), .deleteRecord(let recordID):
            return recordID
        @unknown default:
            return nil
        }
    }
}

// MARK: - 传输模式解析器

/// 统一判断某个 zone 应使用传统模式还是 CKSyncEngine 模式。
///
/// 判断逻辑（优先级从高到低）：
/// 1. 如果 UserDefaults 中该 zone 的迁移标记为 true，返回 `.syncEngine`；
/// 2. 否则返回 `.legacy`。
///
/// ## 如何启用 SyncEngine
/// 在设置页或启动时调用：
/// ```swift
/// CloudKitSyncTransportResolver.enableSyncEngine(forZone: CloudKitDataPolicy.Zone.drinkExperience)
/// ```
/// 然后在下次仓储初始化时自动生效。
///
/// ## 未接通 zone 的防护（PEN-3 P1-3）
/// 仅当 zone 的 `CloudKitSyncEngineEventHandler` 已实现 `pendingRecordsToSave()` /
/// `pendingRecordIDsToDelete()`（本地 Store 维护 pending list）并接通 ACK 时，
/// 才允许进入 `.syncEngine` 模式；否则即使误开迁移标记也回退到 `.legacy` 全量同步，
/// 避免 "SyncEngine 模式却永不上传" 的静默数据不同步陷阱。
nonisolated enum CloudKitSyncTransportResolver {
    /// UserDefaults key 前缀。
    private static let keyPrefix = "cloudkit.sync-engine.enabled."
    /// 当前已接通 CKSyncEngine 增量上传的 zone 白名单（需实现 pending 记录提供 + ACK 后再加入）。
    private static let syncEngineReadyZones: Set<String> = []
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "CloudKitSyncTransport")

    /// 解析指定 zone 当前应使用的传输模式。
    static func resolveMode(forZone zoneName: String) -> CloudKitSyncTransportMode {
        let key = keyPrefix + zoneName
        guard UserDefaults.standard.bool(forKey: key) else { return .legacy }
        guard syncEngineReadyZones.contains(zoneName) else {
            logger.warning("SyncEngine flag set for unready zone, falling back to legacy zone=\(zoneName, privacy: .public)")
            return .legacy
        }
        return .syncEngine
    }

    /// 为指定 zone 启用 CKSyncEngine 模式（下次仓储初始化生效）。
    /// 注意：仅写入迁移标记；真正生效由 `resolveMode` 的白名单防护决定——
    /// 未接通 pending 记录提供/ACK 的 zone 即使标记已置位也回退到 `.legacy`。
    static func enableSyncEngine(forZone zoneName: String, in defaults: UserDefaults = .standard) {
        let key = keyPrefix + zoneName
        defaults.set(true, forKey: key)
    }

    /// 为指定 zone 回退到传统模式（下次仓储初始化生效）。
    static func disableSyncEngine(forZone zoneName: String, in defaults: UserDefaults = .standard) {
        let key = keyPrefix + zoneName
        defaults.removeObject(forKey: key)
    }
}
