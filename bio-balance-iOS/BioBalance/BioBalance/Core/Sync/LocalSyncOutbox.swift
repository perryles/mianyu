import Foundation
import SwiftData

nonisolated enum LocalSyncOutboxRecordType: String, Codable, Sendable {
    // 仅为保证已持久化的 v1 项仍可解码并被清理而保留。
    // 新的每日健康快照仅保存在本地，禁止进入同步队列。
    case healthSnapshot = "BBHealthSnapshot"
    case userEvent = "BBUserEvent"
    // 保留此项以解码既有 v1 数据；新的删除操作应保留目标记录类型并设置 `tombstone`。
    case tombstone = "BBTombstone"
}

nonisolated private enum LocalSyncOutboxLimits {
    static let maximumItems = 128
    static let maximumPayloadBytes = 256 * 1024
    static let maximumRecordIDBytes = 255
    static let maximumRevisionBytes = 64
    static let maximumAttemptCount = 10_000
    static let maximumLeaseDuration: TimeInterval = 5 * 60
}

nonisolated struct LocalSyncOutboxItem: Codable, Equatable, Sendable {
    let id: String
    let revision: String
    let recordType: LocalSyncOutboxRecordType
    let recordID: String
    let schemaVersion: Int
    let payload: Data
    let createdAt: Date
    let updatedAt: Date
    let attemptCount: Int
    let nextAttemptAt: Date
    let tombstone: Bool

    init(
        id: String,
        revision: String,
        recordType: LocalSyncOutboxRecordType,
        recordID: String,
        schemaVersion: Int,
        payload: Data,
        createdAt: Date,
        updatedAt: Date,
        attemptCount: Int,
        nextAttemptAt: Date,
        tombstone: Bool
    ) {
        self.id = id
        self.revision = revision
        self.recordType = recordType
        self.recordID = recordID
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
        self.tombstone = tombstone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let recordType = try container.decode(LocalSyncOutboxRecordType.self, forKey: .recordType)
        let recordID = try container.decode(String.self, forKey: .recordID)
        let id = try container.decode(String.self, forKey: .id)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let payload = try container.decode(Data.self, forKey: .payload)
        let attemptCount = try container.decode(Int.self, forKey: .attemptCount)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        let nextAttemptAt = try container.decode(Date.self, forKey: .nextAttemptAt)

        let revision = try container.decodeIfPresent(String.self, forKey: .revision) ?? "legacy"
        guard !recordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              recordID.utf8.count <= LocalSyncOutboxLimits.maximumRecordIDBytes,
              id == Self.makeID(recordType: recordType, recordID: recordID),
              !revision.isEmpty,
              revision.utf8.count <= LocalSyncOutboxLimits.maximumRevisionBytes,
              schemaVersion > 0,
              payload.count <= LocalSyncOutboxLimits.maximumPayloadBytes,
              (0...LocalSyncOutboxLimits.maximumAttemptCount).contains(attemptCount),
              createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              nextAttemptAt.timeIntervalSinceReferenceDate.isFinite else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid local sync outbox item.")
            )
        }

        self.init(
            id: id,
            revision: revision,
            recordType: recordType,
            recordID: recordID,
            schemaVersion: schemaVersion,
            payload: payload,
            createdAt: createdAt,
            updatedAt: updatedAt,
            attemptCount: attemptCount,
            nextAttemptAt: nextAttemptAt,
            tombstone: try container.decodeIfPresent(Bool.self, forKey: .tombstone) ?? false
        )
    }

    func retrying(
        now: Date,
        retryAfter: TimeInterval? = nil,
        maxDelay: TimeInterval = 24 * 60 * 60
    ) -> LocalSyncOutboxItem {
        let boundedMaxDelay = max(0, maxDelay)
        let explicitDelay = retryAfter.flatMap { $0.isFinite ? min(boundedMaxDelay, max(0, $0)) : nil }
        let delay = explicitDelay ?? min(boundedMaxDelay, pow(2, Double(min(attemptCount, 8))) * 30)
        return LocalSyncOutboxItem(
            id: id,
            revision: revision,
            recordType: recordType,
            recordID: recordID,
            schemaVersion: schemaVersion,
            payload: payload,
            createdAt: createdAt,
            updatedAt: now,
            attemptCount: min(LocalSyncOutboxLimits.maximumAttemptCount, attemptCount + 1),
            nextAttemptAt: now.addingTimeInterval(delay),
            tombstone: tombstone
        )
    }

    func leased(until date: Date) -> LocalSyncOutboxItem {
        LocalSyncOutboxItem(
            id: id,
            revision: revision,
            recordType: recordType,
            recordID: recordID,
            schemaVersion: schemaVersion,
            payload: payload,
            createdAt: createdAt,
            updatedAt: updatedAt,
            attemptCount: attemptCount,
            nextAttemptAt: date,
            tombstone: tombstone
        )
    }

    static func makeID(recordType: LocalSyncOutboxRecordType, recordID: String) -> String {
        "\(recordType.rawValue):\(recordID)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case revision
        case recordType
        case recordID
        case schemaVersion
        case payload
        case createdAt
        case updatedAt
        case attemptCount
        case nextAttemptAt
        case tombstone
    }
}

nonisolated enum LocalSyncOutboxRejection: String, Equatable, Sendable {
    case retiredRecordType
    case invalidRecordID
    case invalidSchemaVersion
    case payloadTooLarge
    case queueFull
    case storageCorrupted
    case persistenceFailed
}

nonisolated enum LocalSyncOutboxEnqueueResult: Equatable, Sendable {
    case enqueued(LocalSyncOutboxItem)
    case unchanged(LocalSyncOutboxItem)
    case rejected(LocalSyncOutboxRejection)

    var accepted: Bool {
        switch self {
        case .enqueued, .unchanged: return true
        case .rejected: return false
        }
    }
}

nonisolated enum LocalSyncOutboxStorageState: Equatable, Sendable {
    case healthy(itemCount: Int)
    case corrupted
}

/// 本机持久化的待发送队列，为未来的可选 CloudKit sender 提供租约和 revision ACK。
///
/// 队列保存在本机 SwiftData 容器，不会放入 App Group；Watch 与 Widget 既不生产
/// 也不消费它。入队不代表已经上传，只有 sender 使用同一 `id + revision` 成功 ACK
/// 后才能删除。payload 只允许低频用户事件或派生摘要，禁止 HealthKit 原始流、
/// 音频、图片和模型对话全文。
final class LocalSyncOutbox {
    static let shared = LocalSyncOutbox()
    nonisolated static let storageKey = "sync.local-outbox.v1"
    static let maximumItems = LocalSyncOutboxLimits.maximumItems
    static let maximumPayloadBytes = LocalSyncOutboxLimits.maximumPayloadBytes

    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private let domain = "local-sync-outbox"
    private let kind = "item"

    init(
        defaults: UserDefaults = .standard,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        records = SwiftDataRecordStore(container: container)
        migrateLegacyDataIfNeeded()
        purgeRetiredItems()
    }

    @discardableResult
    func enqueue(
        recordType: LocalSyncOutboxRecordType,
        recordID: String,
        schemaVersion: Int,
        payload: Data,
        tombstone: Bool = false,
        now: Date = Date()
    ) -> LocalSyncOutboxEnqueueResult {
        guard !Self.isRetired(recordType) else {
            return .rejected(.retiredRecordType)
        }
        guard !recordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              recordID.utf8.count <= LocalSyncOutboxLimits.maximumRecordIDBytes else {
            return .rejected(.invalidRecordID)
        }
        guard schemaVersion > 0 else { return .rejected(.invalidSchemaVersion) }
        guard payload.count <= Self.maximumPayloadBytes else { return .rejected(.payloadTooLarge) }

        lock.lock()
        defer { lock.unlock() }
        guard var items = loadUnlocked() else { return .rejected(.storageCorrupted) }

        let id = LocalSyncOutboxItem.makeID(recordType: recordType, recordID: recordID)
        let existing = items.first { $0.id == id }
        if let existing,
           existing.schemaVersion == schemaVersion,
           existing.payload == payload,
           existing.tombstone == tombstone {
            return .unchanged(existing)
        }
        guard existing != nil || items.count < Self.maximumItems else {
            return .rejected(.queueFull)
        }

        let item = LocalSyncOutboxItem(
            id: id,
            revision: UUID().uuidString,
            recordType: recordType,
            recordID: recordID,
            schemaVersion: schemaVersion,
            payload: payload,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            attemptCount: 0,
            nextAttemptAt: now,
            tombstone: tombstone
        )
        items.removeAll { $0.id == id }
        items.append(item)
        items.sort { $0.updatedAt > $1.updatedAt }
        guard saveUnlocked(items) else { return .rejected(.persistenceFailed) }
        return .enqueued(item)
    }

    func pending(at date: Date = Date(), limit: Int = 32) -> [LocalSyncOutboxItem] {
        lock.lock()
        defer { lock.unlock() }
        return (loadUnlocked() ?? [])
            .filter { $0.nextAttemptAt <= date }
            .sorted { $0.updatedAt < $1.updatedAt }
            .prefix(max(0, limit))
            .map { $0 }
    }

    /// 为单个发送方原子预留到期项目；若发送方在确认前停止，租约到期后项目会重新变为可发送。
    func claimPending(
        at date: Date = Date(),
        limit: Int = 32,
        leaseDuration: TimeInterval = 60
    ) -> [LocalSyncOutboxItem] {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              leaseDuration.isFinite,
              limit > 0 else { return [] }

        lock.lock()
        defer { lock.unlock() }
        guard var items = loadUnlocked() else { return [] }

        let boundedLease = min(
            LocalSyncOutboxLimits.maximumLeaseDuration,
            max(1, leaseDuration)
        )
        let leaseUntil = date.addingTimeInterval(boundedLease)
        let dueIDs = Set(
            items
                .filter { $0.nextAttemptAt <= date }
                .sorted { $0.updatedAt < $1.updatedAt }
                .prefix(limit)
                .map(\.id)
        )
        guard !dueIDs.isEmpty else { return [] }

        var claimed: [LocalSyncOutboxItem] = []
        for index in items.indices where dueIDs.contains(items[index].id) {
            let leased = items[index].leased(until: leaseUntil)
            items[index] = leased
            claimed.append(leased)
        }
        guard saveUnlocked(items) else { return [] }
        return claimed.sorted { $0.updatedAt < $1.updatedAt }
    }

    @discardableResult
    func markSucceeded(id: String, revision: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var items = loadUnlocked(),
              let index = items.firstIndex(where: { $0.id == id && $0.revision == revision }) else {
            return false
        }
        items.remove(at: index)
        return saveUnlocked(items)
    }

    @discardableResult
    func markFailed(
        id: String,
        revision: String,
        at date: Date = Date(),
        retryAfter: TimeInterval? = nil
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var items = loadUnlocked(),
              let index = items.firstIndex(where: { $0.id == id && $0.revision == revision }) else {
            return false
        }
        items[index] = items[index].retrying(now: date, retryAfter: retryAfter)
        return saveUnlocked(items)
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()?.count ?? 0
    }

    func storageState() -> LocalSyncOutboxStorageState {
        lock.lock()
        defer { lock.unlock() }
        guard let items = loadUnlocked() else { return .corrupted }
        return .healthy(itemCount: items.count)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        _ = records.clear(domain: domain, kind: kind)
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func loadUnlocked(includeRetired: Bool = false) -> [LocalSyncOutboxItem]? {
        guard let rows = records.records(domain: domain, kind: kind) else { return nil }
        let items = rows.compactMap { try? decoder.decode(LocalSyncOutboxItem.self, from: $0.payload) }
        guard items.count == rows.count,
              Set(items.map(\.id)).count == items.count else {
            return nil
        }
        if includeRetired {
            return items
        }
        return items.filter { !Self.isRetired($0.recordType) }
    }

    private func saveUnlocked(_ items: [LocalSyncOutboxItem]) -> Bool {
        let seeds = items.compactMap(makeSeed)
        guard seeds.count == items.count else { return false }
        return records.replace(domain: domain, kind: kind, with: seeds)
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "sync.local-outbox.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        let legacyData = defaults.data(forKey: Self.storageKey)
        let legacyItems: [LocalSyncOutboxItem]
        if let legacyData {
            guard let decoded = try? decoder.decode([LocalSyncOutboxItem].self, from: legacyData),
                  Set(decoded.map(\.id)).count == decoded.count else { return }
            legacyItems = decoded
        } else {
            legacyItems = []
        }
        let seeds = legacyItems.compactMap(makeSeed)
        guard seeds.count == legacyItems.count,
              records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// 删除已撤销云端发送意图的记录类型所对应的本地项目。
    /// 常规读取同样会排除它们，因此即使清理失败，后续发送方也无法领取已停用的健康载荷。
    private func purgeRetiredItems() {
        lock.lock()
        defer { lock.unlock() }
        guard let items = loadUnlocked(includeRetired: true) else { return }
        let activeItems = items.filter { !Self.isRetired($0.recordType) }
        guard activeItems.count != items.count else { return }
        _ = saveUnlocked(activeItems)
    }

    private static func isRetired(_ recordType: LocalSyncOutboxRecordType) -> Bool {
        switch recordType {
        case .healthSnapshot:
            true
        case .userEvent, .tombstone:
            false
        }
    }

    private func makeSeed(_ item: LocalSyncOutboxItem) -> LocalDataRecordSeed? {
        guard let data = try? encoder.encode(item) else { return nil }
        return LocalDataRecordSeed(
            domain: domain,
            recordID: item.id,
            kind: kind,
            occurredAt: item.nextAttemptAt,
            updatedAt: item.updatedAt,
            payload: data
        )
    }
}
