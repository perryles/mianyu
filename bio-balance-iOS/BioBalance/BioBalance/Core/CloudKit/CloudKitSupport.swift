import CloudKit
import Foundation
import os

// MARK: - CloudKit 基础类型
//
// 本文件提供所有业务仓储共享的 CloudKit 基础组件：
// 1. 数据库可见范围（CloudKitDatabaseScope）
// 2. 结构化日志上下文（CloudKitLoggerContext）
// 3. 领域错误与 CKError 映射（CloudKitDomainError）
// 4. 有限重试策略与执行器（CloudKitRetryPolicy / CloudKitOperationExecutor）
// 5. SDK 异步协议与默认实现（CloudKitClientProtocol / CloudKitClient）
//
// ## 传输层架构（双轨并存）
//
// ```
// Repository (业务逻辑)
//    ├── Legacy Transport (本文件: CloudKitOperationExecutor + CloudKitClient)
//    │   适用于 ≤ 数百条记录、全量查询 + last-write-wins 的场景
//    │
//    └── SyncEngine Transport (CloudKitSyncEngineTransport.swift)
//        适用于 > 1000 条记录、需增量同步/离线冲突/断点续传的场景
//        通过 CloudKitSyncTransportResolver 按 zone 独立切换
// ```
//
// 业务仓储不应直接 import CloudKit SDK，而应通过这里的协议抽象访问，
// 以便在单元测试中注入 Stub，并确保所有错误映射、重试和日志统一处理。

/// 仅用于明确一次 CloudKit 操作的数据可见范围和日志上下文。
///
/// - `private`：只有当前 Apple ID 可见，适合可选的个人数据恢复；
/// - `shared`：只有 CKShare 的参与者可见，必须由用户显式邀请/接受；
/// - `public`：容器内所有用户可查询，只能保存公开资料，禁止健康数据。
nonisolated enum CloudKitDatabaseScope: String, Sendable {
    case `private`
    case shared
    case `public`
}

/// 一次 CloudKit 操作に対する構造化ログコンテキスト。
///
/// 各仓储が `executor.run(context:)` に渡すことで、成功・失敗・リトライの全ログに
/// 操作名・DB スコープ・zone・record ID が自動付与され、本番障害時に原因特定が迅速になる。
nonisolated struct CloudKitLoggerContext: Sendable {
    let operation: String
    let database: CloudKitDatabaseScope?
    let zoneID: String?
    let recordID: String?
    let shareID: String?

    init(
        operation: String,
        database: CloudKitDatabaseScope? = nil,
        zoneID: String? = nil,
        recordID: String? = nil,
        shareID: String? = nil
    ) {
        self.operation = operation
        self.database = database
        self.zoneID = zoneID
        self.recordID = recordID
        self.shareID = shareID
    }

    var summary: String {
        var parts = ["op=\(operation)"]
        if let database {
            parts.append("db=\(database.rawValue)")
        }
        if let zoneID {
            parts.append("zone=\(zoneID)")
        }
        if let recordID {
            parts.append("record=\(recordID)")
        }
        if let shareID {
            parts.append("share=\(shareID)")
        }
        return parts.joined(separator: " ")
    }
}

nonisolated enum CloudKitDomainError: Error, LocalizedError, Equatable, Sendable {
    case iCloudUnavailable
    case missingPayload
    case invalidRecord
    case profileNotFound
    case participantNotFound
    case unsupportedRemoval
    case conflict
    case serverRecordChanged
    case serverRejectedRequest
    case badContainer
    case notAuthenticated
    case permissionFailure
    case networkUnavailable
    case requestRateLimited(retryAfter: TimeInterval?)
    case serviceUnavailable
    case quotaExceeded
    case zoneNotFound
    case badDatabase
    case unknownItem
    case partialFailure(message: String)
    case unknown(message: String)

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return String(localized: "当前 iCloud 不可用，好友共享暂时无法使用。")
        case .missingPayload:
            return String(localized: "共享摘要还没有准备好，稍后再试一次。")
        case .invalidRecord:
            return String(localized: "共享记录内容不完整，暂时无法读取。")
        case .profileNotFound:
            return String(localized: "没有找到对应的公开资料。")
        case .participantNotFound:
            return String(localized: "没有找到对应的共享参与者。")
        case .unsupportedRemoval:
            return String(localized: "当前系统不支持直接移除该共享参与者。")
        case .conflict:
            return String(localized: "这份健康摘要已经在共享中了，请先停止当前共享再重新创建。")
        case .serverRecordChanged:
            return String(localized: "这条 iCloud 记录已在另一台设备更新，请刷新后再试。")
        case .serverRejectedRequest:
            return String(localized: "CloudKit 拒绝了这次共享请求。应用会优先恢复已有共享；若仅 TestFlight 或商店版本失败，请确认 CloudKit Production schema 已部署。")
        case .badContainer:
            return String(localized: "当前 CloudKit 容器配置不正确，请检查签名与容器标识。")
        case .notAuthenticated:
            return String(localized: "当前 iCloud 账号未登录或暂时不可用。")
        case .permissionFailure:
            return String(localized: "CloudKit 暂时拒绝了这次访问，请稍后重试。")
        case .networkUnavailable:
            return String(localized: "网络不可用，稍后连接网络后再试。")
        case .requestRateLimited(let retryAfter):
            if let retryAfter {
                return String(localized: "CloudKit 请求过于频繁，请 \(Int(ceil(retryAfter))) 秒后重试。")
            }
            return String(localized: "CloudKit 请求过于频繁，请稍后重试。")
        case .serviceUnavailable:
            return String(localized: "CloudKit 当前不可用，请稍后再试。")
        case .quotaExceeded:
            return String(localized: "iCloud 存储配额不足，暂时无法继续共享。")
        case .zoneNotFound:
            return String(localized: "共享区已不存在，需要重新建立共享。")
        case .badDatabase:
            return String(localized: "CloudKit 请求被发送到了错误的数据库。")
        case .unknownItem:
            return String(localized: "CloudKit 中没有找到对应记录。")
        case .partialFailure(let message):
            return message
        case .unknown(let message):
            return message
        }
    }

    static func from(_ error: Error) -> CloudKitDomainError {
        if let domainError = error as? CloudKitDomainError {
            return domainError
        }

        guard let ckError = error as? CKError else {
            return .unknown(message: error.localizedDescription)
        }

        switch ckError.code {
        case .serverRejectedRequest:
            return .serverRejectedRequest
        case .alreadyShared:
            return .conflict
        case .serverRecordChanged:
            return .serverRecordChanged
        case .badContainer:
            return .badContainer
        case .notAuthenticated:
            return .notAuthenticated
        case .permissionFailure:
            return .permissionFailure
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .requestRateLimited:
            return .requestRateLimited(retryAfter: ckError.userInfo[CKErrorRetryAfterKey] as? TimeInterval)
        case .serviceUnavailable:
            return .serviceUnavailable
        case .quotaExceeded:
            return .quotaExceeded
        case .zoneNotFound:
            return .zoneNotFound
        case .badDatabase:
            return .badDatabase
        case .unknownItem:
            return .unknownItem
        case .partialFailure, .batchRequestFailed:
            let firstFailure = ckError.partialErrorsByItemID?.values.first
            let message = firstFailure.map { CloudKitDomainError.from($0).localizedDescription }
                ?? ckError.localizedDescription
            return .partialFailure(message: message)
        default:
            return .unknown(message: ckError.localizedDescription)
        }
    }
}

nonisolated enum CloudKitResultSource: String, Sendable {
    case fresh
    case partial
    case staleFallback
}

nonisolated struct CloudKitOperationResult<Value: Sendable>: Sendable {
    let value: Value
    let source: CloudKitResultSource
    let error: CloudKitDomainError?

    init(value: Value, source: CloudKitResultSource = .fresh, error: CloudKitDomainError? = nil) {
        self.value = value
        self.source = source
        self.error = error
    }
}

/// 只重试网络、限流和服务暂时不可用等瞬时错误。
///
/// 设计约束：
/// - `maxAttempts` 包含第一次执行；权限 / 配额 / 数据格式 / 冲突错误绝不盲目重试。
/// - 限流错误优先遵从服务端 `retryAfterSeconds`，但不超过 `maxDelay`。
/// - 非限流错误使用指数退避（`baseDelay * 2^(attempt-1)`），同样受 `maxDelay` 封顶。
/// - 默认 `.balanced` 为 3 次尝试 / 0.35-2.5s，适合前台用户操作。
nonisolated struct CloudKitRetryPolicy: Sendable {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval

    static let balanced = CloudKitRetryPolicy(maxAttempts: 3, baseDelay: 0.35, maxDelay: 2.5)

    func shouldRetry(_ error: CloudKitDomainError, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }

        switch error {
        case .networkUnavailable, .requestRateLimited, .serviceUnavailable:
            return true
        default:
            return false
        }
    }

    func delay(for error: CloudKitDomainError, attempt: Int) -> TimeInterval {
        if case .requestRateLimited(let retryAfter) = error, let retryAfter {
            return min(max(retryAfter, baseDelay), maxDelay)
        }

        let exponent = max(0, attempt - 1)
        let exponential = baseDelay * pow(2, Double(exponent))
        return min(exponential, maxDelay)
    }
}

/// CloudKit 操作的统一错误映射、有限重试和结构化日志入口。
///
/// 该类型不提供业务幂等性，也不负责离线持久化；调用方仍须使用稳定 record ID、
/// 合适的 save policy 或 Outbox。Task 被取消时必须立即向上传播，不能继续后台重试。
/// 执行器没有可变共享状态，可安全地由任意 actor 的 Repository 复用。
/// 显式 `nonisolated` 避免工程默认 MainActor 隔离把同步初始化误判为跨 actor 调用。
nonisolated final class CloudKitOperationExecutor: Sendable {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "CloudKit")

    let retryPolicy: CloudKitRetryPolicy

    init(retryPolicy: CloudKitRetryPolicy = .balanced) {
        self.retryPolicy = retryPolicy
    }

    func map(_ error: Error) -> CloudKitDomainError {
        CloudKitDomainError.from(error)
    }

    func run<T>(
        context: CloudKitLoggerContext,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 1

        while true {
            do {
                let value = try await operation()
                Self.logger.info("[CloudKit] success \(context.summary, privacy: .public) attempt=\(attempt, privacy: .public)")
                return value
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let mapped = map(error)
                let description = mapped.localizedDescription
                Self.logger.error("[CloudKit] failure \(context.summary, privacy: .public) attempt=\(attempt, privacy: .public) error=\(description, privacy: .public)")

                guard retryPolicy.shouldRetry(mapped, attempt: attempt) else {
                    throw mapped
                }

                let delay = retryPolicy.delay(for: mapped, attempt: attempt)
                let delayNanos = UInt64(max(0, delay) * 1_000_000_000)
                Self.logger.info("[CloudKit] retrying \(context.summary, privacy: .public) attempt=\(attempt, privacy: .public) delay=\(delay, privacy: .public)")
                try await Task.sleep(nanoseconds: delayNanos)
                attempt += 1
            }
        }
    }
}

/// 对 CloudKit SDK 的最小异步封装，便于仓储统一处理错误并在测试中模拟账号、网络和冲突。
///
/// ## 使用规则
/// 1. 所有业务仓储**必须**通过此协议或同层抽象访问 CloudKit SDK。
/// 2. CloudKit 失败**不得**阻断本地数据的保存或展示。
/// 3. `fetch(recordID:)` 在 `.unknownItem` 时返回 `nil`（非 throw），简化调用方空检查。
/// 4. `modify(recordsToSave:...)` 批量操作**不保证顺序**，调用方须自行控制幂等性。
/// 5. 测试中注入 `Stub` 实现即可模拟任意账号状态、网络故障和冲突场景。
protocol CloudKitClientProtocol: Sendable {
    func accountStatus(container: CKContainer) async throws -> CKAccountStatus
    func fetchUserRecordID(container: CKContainer) async throws -> CKRecord.ID
    func accept(metadata: CKShare.Metadata, container: CKContainer) async throws
    func save(zone: CKRecordZone, in database: CKDatabase) async throws -> CKRecordZone
    func delete(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws
    func fetch(recordID: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord?
    func save(record: CKRecord, in database: CKDatabase) async throws -> CKRecord
    func modify(
        recordsToSave: [CKRecord],
        recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        in database: CKDatabase
    ) async throws -> [CKRecord]
    func runQuery(
        query: CKQuery?,
        cursor: CKQueryOperation.Cursor?,
        zoneID: CKRecordZone.ID?,
        in database: CKDatabase
    ) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?)
    func fetchAllZoneIDs(in database: CKDatabase) async throws -> [CKRecordZone.ID]
}

/// iOS 18.6+ 默认实现，直接使用 CKDatabase / CKContainer 原生 async API（iOS 15+），
/// 不再需要 `withCheckedThrowingContinuation` 回调包装。
///
/// 优势：
/// - 消除回调包装的 double-resume 风险；
/// - 代码行数减少 60%+，可读性大幅提升；
/// - 编译器能正确推断 Sendable 约束。
///
/// 注意：`accept(metadata:)` 仍使用 `CKAcceptSharesOperation`，因该路径需要处理
/// 多条 metadata 批量接受的边界情况，直接操作更可控。
struct CloudKitClient: CloudKitClientProtocol {
    nonisolated init() {}

    func accountStatus(container: CKContainer) async throws -> CKAccountStatus {
        // iOS 15+ 自动桥接 async 版本。
        try await container.accountStatus()
    }

    func fetchUserRecordID(container: CKContainer) async throws -> CKRecord.ID {
        // `fetchUserRecordID(completionHandler:)` 的 Swift async 名称为 userRecordID()。
        try await container.userRecordID()
    }

    func accept(metadata: CKShare.Metadata, container: CKContainer) async throws {
        // 保留 Operation：批量接受多 metadata 时操作级回调更可控。
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    func save(zone: CKRecordZone, in database: CKDatabase) async throws -> CKRecordZone {
        // iOS 15+ 原生 async：modifyRecordZones(saving:deleting:)
        let results = try await database.modifyRecordZones(saving: [zone], deleting: [])
        switch results.saveResults[zone.zoneID] {
        case .success(let saved):
            return saved
        case .failure(let error):
            throw error
        case nil:
            // 原子操作成功但结果缺失——理论上不会发生，回退返回入参。
            return zone
        }
    }

    func delete(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws {
        let results = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
        if case .failure(let error) = results.deleteResults[zoneID] {
            throw error
        }
    }

    func fetch(recordID: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord? {
        // iOS 15+ `record(for:)` 在 unknownItem 时 throw；协议约定返回 nil。
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func save(record: CKRecord, in database: CKDatabase) async throws -> CKRecord {
        // 单条保存走 modifyRecords 以保持与批量操作相同的 savePolicy 语义。
        let results = try await database.modifyRecords(saving: [record], deleting: [])
        switch results.saveResults[record.recordID] {
        case .success(let saved):
            return saved
        case .failure(let error):
            throw error
        case nil:
            throw CloudKitDomainError.invalidRecord
        }
    }

    func modify(
        recordsToSave: [CKRecord],
        recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        in database: CKDatabase
    ) async throws -> [CKRecord] {
        // iOS 15+ 原生 async；atomically=true 保证批内一致性。
        let results = try await database.modifyRecords(
            saving: recordsToSave,
            deleting: recordIDsToDelete,
            savePolicy: savePolicy,
            atomically: true
        )

        // 原子操作成功 → 所有 saveResults 应为 .success；逐条提取实际已保存的 record。
        var saved: [CKRecord] = []
        saved.reserveCapacity(recordsToSave.count)
        for record in recordsToSave {
            switch results.saveResults[record.recordID] {
            case .success(let savedRecord):
                saved.append(savedRecord)
            case .failure(let error):
                throw error
            case nil:
                // 原子成功但缺失——不应发生；回退使用输入 record。
                saved.append(record)
            }
        }
        return saved
    }

    func runQuery(
        query: CKQuery?,
        cursor: CKQueryOperation.Cursor?,
        zoneID: CKRecordZone.ID?,
        in database: CKDatabase
    ) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        // iOS 15+ 原生 async：records(matching:) / records(continuingMatchFrom:)
        let result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)

        if let cursor {
            result = try await database.records(continuingMatchFrom: cursor)
        } else if let query {
            result = try await database.records(matching: query, inZoneWith: zoneID)
        } else {
            throw CloudKitDomainError.invalidRecord
        }

        // 逐条检查——首条失败即 throw，与旧 Operation 行为一致。
        var records: [CKRecord] = []
        records.reserveCapacity(result.matchResults.count)
        for (_, recordResult) in result.matchResults {
            switch recordResult {
            case .success(let record):
                records.append(record)
            case .failure(let error):
                throw error
            }
        }
        return (records, result.queryCursor)
    }

    func fetchAllZoneIDs(in database: CKDatabase) async throws -> [CKRecordZone.ID] {
        // `fetchAllRecordZones(completionHandler:)` 的 Swift async 名称为 allRecordZones()。
        let zones = try await database.allRecordZones()
        return zones.map(\.zoneID)
    }
}
