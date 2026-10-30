import Foundation
import SwiftData

/// Mianyu 的本机结构化数据容器。
///
/// 这里显式关闭 App Group 与 CloudKit：跨进程仍使用精简 App Group 投影，跨设备仍由
/// 现有 CloudKit Repository / WCSession 负责，避免形成第二套隐式同步通道。
enum MianyuModelContainer {
    static let schema = Schema([
        LocalDataRecord.self
    ])

    static let shared: ModelContainer = {
        do {
            return try make()
        } catch {
            fatalError("Unable to create Mianyu SwiftData container: \(error)")
        }
    }()

    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "BioBalanceLocalV1",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

/// 一条可索引的本地业务记录。业务对象仍保持 Codable 值类型，SwiftData 行只负责
/// 稳定 ID、域/类型、时间索引和 payload 持久化，避免把 UI 模型耦合到持久层。
@Model
final class LocalDataRecord {
    @Attribute(.unique) var stableKey: String
    var domain: String
    var recordID: String
    var kind: String
    var occurredAt: Date
    var updatedAt: Date
    @Attribute(.externalStorage) var payload: Data

    init(
        stableKey: String,
        domain: String,
        recordID: String,
        kind: String,
        occurredAt: Date,
        updatedAt: Date,
        payload: Data
    ) {
        self.stableKey = stableKey
        self.domain = domain
        self.recordID = recordID
        self.kind = kind
        self.occurredAt = occurredAt
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

nonisolated struct LocalDataRecordSeed: Sendable {
    let domain: String
    let recordID: String
    let kind: String
    let occurredAt: Date
    let updatedAt: Date
    let payload: Data

    var stableKey: String { "\(domain)::\(kind)::\(recordID)" }
}

nonisolated struct LocalDataRecordSnapshot: Sendable {
    let stableKey: String
    let domain: String
    let recordID: String
    let kind: String
    let occurredAt: Date
    let updatedAt: Date
    let payload: Data
}

/// Store 共用的同步 SwiftData 适配器。工程默认 MainActor 隔离，因此每个业务 Store
/// 持有自己的 ModelContext，并在原有同步 API 内完成读写。
final class SwiftDataRecordStore {
    private static let migrationDomain = "__migration"
    private let context: ModelContext

    init(container: ModelContainer = MianyuModelContainer.shared) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func records(domain: String, kind: String? = nil) -> [LocalDataRecordSnapshot]? {
        do {
            let requestedDomain = domain
            let descriptor = FetchDescriptor<LocalDataRecord>(
                predicate: #Predicate { $0.domain == requestedDomain }
            )
            return try context.fetch(descriptor)
                .filter { kind == nil || $0.kind == kind }
                .sorted {
                    if $0.occurredAt == $1.occurredAt {
                        return $0.stableKey < $1.stableKey
                    }
                    return $0.occurredAt > $1.occurredAt
                }
                .map { row in
                    LocalDataRecordSnapshot(
                        stableKey: row.stableKey,
                        domain: row.domain,
                        recordID: row.recordID,
                        kind: row.kind,
                        occurredAt: row.occurredAt,
                        updatedAt: row.updatedAt,
                        payload: row.payload
                    )
                }
        } catch {
            return nil
        }
    }

    /// 返回全部本地记录（跨域），供审计/导出/删除服务使用。
    func allRecords() -> [LocalDataRecordSnapshot] {
        do {
            return try context.fetch(FetchDescriptor<LocalDataRecord>())
                .map { row in
                    LocalDataRecordSnapshot(
                        stableKey: row.stableKey,
                        domain: row.domain,
                        recordID: row.recordID,
                        kind: row.kind,
                        occurredAt: row.occurredAt,
                        updatedAt: row.updatedAt,
                        payload: row.payload
                    )
                }
        } catch {
            return []
        }
    }

    func upsert(_ seed: LocalDataRecordSeed, keepingNewest limit: Int? = nil) -> Bool {
        do {
            if let existing = try record(stableKey: seed.stableKey) {
                existing.domain = seed.domain
                existing.recordID = seed.recordID
                existing.kind = seed.kind
                existing.occurredAt = seed.occurredAt
                existing.updatedAt = seed.updatedAt
                existing.payload = seed.payload
            } else {
                context.insert(Self.model(from: seed))
            }

            if let limit {
                let requestedDomain = seed.domain
                let rows = try context.fetch(
                    FetchDescriptor<LocalDataRecord>(
                        predicate: #Predicate { $0.domain == requestedDomain }
                    )
                )
                .filter { $0.kind == seed.kind }
                .sorted { $0.occurredAt > $1.occurredAt }
                for row in rows.dropFirst(max(0, limit)) {
                    context.delete(row)
                }
            }
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    func replace(domain: String, kind: String, with seeds: [LocalDataRecordSeed]) -> Bool {
        do {
            let requestedDomain = domain
            let rows = try context.fetch(
                FetchDescriptor<LocalDataRecord>(
                    predicate: #Predicate { $0.domain == requestedDomain }
                )
            )
            for row in rows where row.kind == kind {
                context.delete(row)
            }
            seeds.forEach { context.insert(Self.model(from: $0)) }
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    /// 原子替换一个业务域的全部记录，用于同时包含多种 kind 的聚合。
    func replace(domain: String, with seeds: [LocalDataRecordSeed]) -> Bool {
        guard seeds.allSatisfy({ $0.domain == domain }) else { return false }
        do {
            let requestedDomain = domain
            let rows = try context.fetch(
                FetchDescriptor<LocalDataRecord>(
                    predicate: #Predicate { $0.domain == requestedDomain }
                )
            )
            for row in rows {
                context.delete(row)
            }
            seeds.forEach { context.insert(Self.model(from: $0)) }
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    func remove(stableKey: String) -> Bool {
        do {
            guard let row = try record(stableKey: stableKey) else { return true }
            context.delete(row)
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    func clear(domain: String, kind: String? = nil) -> Bool {
        do {
            let requestedDomain = domain
            let rows = try context.fetch(
                FetchDescriptor<LocalDataRecord>(
                    predicate: #Predicate { $0.domain == requestedDomain }
                )
            )
            for row in rows where kind == nil || row.kind == kind {
                context.delete(row)
            }
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    /// 删除全部本地记录（含内部基础设施域）。「删除我的数据」的本地阶段使用。
    func clearAll() -> Bool {
        do {
            let rows = try context.fetch(FetchDescriptor<LocalDataRecord>())
            for row in rows {
                context.delete(row)
            }
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    func isMigrationComplete(_ migrationID: String) -> Bool {
        (try? record(stableKey: Self.migrationKey(migrationID))) != nil
    }

    /// 将旧记录与迁移标记放进同一个 SwiftData transaction。调用方只有在返回 true 后
    /// 才能删除旧 UserDefaults 数据，从而保证崩溃或保存失败时仍可重试。
    ///
    /// 迁移后校验：保存成功后回读数据库，确认每个 seed 都已可查询；只要有一个缺失就
    /// 回滚整次迁移并返回 false，旧数据仍留在 UserDefaults，下次启动重试。
    func migrate(_ migrationID: String, seeds: [LocalDataRecordSeed]) -> Bool {
        if isMigrationComplete(migrationID) { return true }
        do {
            let existingKeys = Set(try context.fetch(FetchDescriptor<LocalDataRecord>()).map(\.stableKey))
            for seed in seeds where !existingKeys.contains(seed.stableKey) {
                context.insert(Self.model(from: seed))
            }
            let marker = LocalDataRecordSeed(
                domain: Self.migrationDomain,
                recordID: migrationID,
                kind: "completed",
                occurredAt: Date(),
                updatedAt: Date(),
                payload: Data()
            )
            context.insert(Self.model(from: marker))
            try context.save()

            let savedKeys = Set(try context.fetch(FetchDescriptor<LocalDataRecord>()).map(\.stableKey))
            guard seeds.allSatisfy({ savedKeys.contains($0.stableKey) }) else {
                context.rollback()
                return false
            }
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    private func record(stableKey: String) throws -> LocalDataRecord? {
        let requestedKey = stableKey
        var descriptor = FetchDescriptor<LocalDataRecord>(
            predicate: #Predicate { $0.stableKey == requestedKey }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func migrationKey(_ migrationID: String) -> String {
        "\(migrationDomain)::completed::\(migrationID)"
    }

    private static func model(from seed: LocalDataRecordSeed) -> LocalDataRecord {
        LocalDataRecord(
            stableKey: seed.stableKey,
            domain: seed.domain,
            recordID: seed.recordID,
            kind: seed.kind,
            occurredAt: seed.occurredAt,
            updatedAt: seed.updatedAt,
            payload: seed.payload
        )
    }

}
