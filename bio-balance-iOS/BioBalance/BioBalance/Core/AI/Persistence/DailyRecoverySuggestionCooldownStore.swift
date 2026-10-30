import Foundation
import SwiftData

/// 记录被跳过建议的冷却时间，避免短期内重复打扰用户。
final class DailyRecoverySuggestionCooldownStore {
    static let shared = DailyRecoverySuggestionCooldownStore()
    static let defaultDuration: TimeInterval = 36 * 60 * 60

    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let key = "daily.recovery.suggestion-cooldowns.v1"
    private let domain = "daily-recovery-cooldown"
    private let kind = "record"

    init(
        defaults: UserDefaults = .standard,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        records = SwiftDataRecordStore(container: container)
        migrateLegacyDataIfNeeded()
    }

    func recordSkip(
        actionID: String,
        title: String,
        now: Date = Date(),
        duration: TimeInterval = DailyRecoverySuggestionCooldownStore.defaultDuration
    ) {
        var records = activeRecords(at: now)
        records.removeAll { $0.actionID == actionID }
        records.append(
            DailyRecoverySuggestionCooldownRecord(
                actionID: actionID,
                category: DailyRecoverySuggestionClassifier.category(for: title),
                expiresAt: now.addingTimeInterval(max(0, duration))
            )
        )
        persist(records)
    }

    func remove(actionID: String, now: Date = Date()) {
        let records = activeRecords(at: now).filter { $0.actionID != actionID }
        persist(records)
    }

    func activeCategories(at date: Date = Date()) -> Set<String> {
        Set(activeRecords(at: date).map(\.category))
    }

    private func activeRecords(at date: Date) -> [DailyRecoverySuggestionCooldownRecord] {
        let stored: [DailyRecoverySuggestionCooldownRecord]
        if let rows = records.records(domain: domain, kind: kind) {
            stored = rows.compactMap { try? JSONDecoder().decode(DailyRecoverySuggestionCooldownRecord.self, from: $0.payload) }
        } else if let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([DailyRecoverySuggestionCooldownRecord].self, from: data) {
            stored = decoded
        } else {
            stored = []
        }
        return stored.filter { $0.expiresAt > date }
    }

    private func persist(_ records: [DailyRecoverySuggestionCooldownRecord]) {
        let bounded = Array(records.sorted { $0.expiresAt > $1.expiresAt }.prefix(48))
        let seeds = bounded.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? JSONEncoder().encode(record) else { return nil }
            return LocalDataRecordSeed(domain: domain, recordID: record.actionID, kind: kind, occurredAt: record.expiresAt, updatedAt: record.expiresAt, payload: data)
        }
        guard seeds.count == bounded.count else { return }
        _ = self.records.replace(domain: domain, kind: kind, with: seeds)
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "daily.recovery.suggestion-cooldowns.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            return
        }
        let legacyData = defaults.data(forKey: key)
        let legacyRecords: [DailyRecoverySuggestionCooldownRecord]
        if let legacyData {
            guard let decoded = try? JSONDecoder().decode([DailyRecoverySuggestionCooldownRecord].self, from: legacyData) else { return }
            legacyRecords = decoded
        } else { legacyRecords = [] }
        let seeds = legacyRecords.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? JSONEncoder().encode(record) else { return nil }
            return LocalDataRecordSeed(domain: domain, recordID: record.actionID, kind: kind, occurredAt: record.expiresAt, updatedAt: record.expiresAt, payload: data)
        }
        guard seeds.count == legacyRecords.count, records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: key)
    }
}
