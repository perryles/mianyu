import Foundation
import SwiftData

/// 保存按日派生的确定性快照。快照只保留在本机，不进入 CloudKit Outbox。
final class DailyDeterministicHealthSnapshotStore {
    static let shared = DailyDeterministicHealthSnapshotStore(
        defaults: .standard
    )
    nonisolated static let storageKey = "health.deterministic.daily-snapshots.v1"
    private static let maximumStoredDays = 31

    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let calendar: Calendar
    private let lock = NSLock()
    private let domain = "daily-health-snapshot"
    private let kind = "snapshot"

    init(
        defaults: UserDefaults,
        calendar: Calendar = .current,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        records = SwiftDataRecordStore(container: container)
        self.calendar = calendar
        migrateLegacyDataIfNeeded()
    }

    @discardableResult
    func save(_ snapshot: DailyDeterministicHealthSnapshot) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let payload = try? encoder.encode(snapshot) else {
            return false
        }
        return records.upsert(
            LocalDataRecordSeed(
                domain: domain,
                recordID: Self.dayKey(for: snapshot.date, calendar: calendar),
                kind: kind,
                occurredAt: snapshot.date,
                updatedAt: snapshot.generatedAt,
                payload: payload
            ),
            keepingNewest: Self.maximumStoredDays
        )
    }

    func latest() -> DailyDeterministicHealthSnapshot? {
        load().max { $0.generatedAt < $1.generatedAt }
    }

    func latestFresh(
        at date: Date = Date(),
        maximumAge: TimeInterval = 6 * 60 * 60
    ) -> DailyDeterministicHealthSnapshot? {
        guard let snapshot = latest(), snapshot.freshness(at: date, maximumAge: maximumAge) == .fresh else {
            return nil
        }
        return snapshot
    }

    func loadComparableWithCurrentEngine(days: Int = 31) -> [DailyDeterministicHealthSnapshot] {
        load(days: days).filter {
            $0.schemaVersion == DailyDeterministicHealthSnapshot.currentSchemaVersion
                && $0.engineVersions == .current
        }
    }

    func exportData(days: Int = 31) -> Data? {
        let exportEncoder = JSONEncoder()
        exportEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        exportEncoder.dateEncodingStrategy = .iso8601
        return try? exportEncoder.encode(load(days: days))
    }

    func load(days: Int = maximumStoredDays) -> [DailyDeterministicHealthSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return Array(decodedSnapshots().sorted { $0.date > $1.date }.prefix(max(0, days)))
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        _ = records.clear(domain: domain, kind: kind)
    }

    private func decodedSnapshots() -> [DailyDeterministicHealthSnapshot] {
        if let rows = records.records(domain: domain, kind: kind) {
            return rows.compactMap { try? decoder.decode(DailyDeterministicHealthSnapshot.self, from: $0.payload) }
        }
        guard let data = defaults.data(forKey: Self.storageKey),
              let snapshots = try? decoder.decode([DailyDeterministicHealthSnapshot].self, from: data) else {
            return []
        }
        return snapshots
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "health.deterministic.daily-snapshots.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        let legacyData = defaults.data(forKey: Self.storageKey)
        let snapshots: [DailyDeterministicHealthSnapshot]
        if let legacyData {
            guard let decoded = try? decoder.decode([DailyDeterministicHealthSnapshot].self, from: legacyData) else { return }
            snapshots = decoded
        } else { snapshots = [] }
        let seeds = snapshots.compactMap { snapshot -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(snapshot) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: Self.dayKey(for: snapshot.date, calendar: calendar),
                kind: kind,
                occurredAt: snapshot.date,
                updatedAt: snapshot.generatedAt,
                payload: data
            )
        }
        guard seeds.count == snapshots.count, records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: Self.storageKey)
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
