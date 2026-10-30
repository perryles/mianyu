import Foundation

nonisolated struct AppGroupSnapshotCacheStatus: Equatable, Sendable {
    let isAvailable: Bool
    let schemaVersion: Int?
    let generatedAt: Date?
    let lastWriteAt: Date?
    let byteCount: Int
    let staleAfter: TimeInterval

    func isStale(at now: Date) -> Bool {
        guard let generatedAt else { return true }
        return now.timeIntervalSince(generatedAt) > staleAfter
    }
}

nonisolated enum AppGroupSnapshotStore {
    static let widgetSnapshotV2Key = AppGroupSchema.Keys.widgetSnapshotV2
    static let legacyWidgetSnapshotV2Key = "widget_snapshot_v2"
    static let lastSnapshotWriteKey = "lastSnapshotWrite"

    nonisolated static func userDefaults() -> UserDefaults? {
        AppGroupManager.userDefaults()
    }

    static func status(
        now: Date = Date(),
        staleAfter: TimeInterval = AppGroupSchema.Freshness.generalStaleAfter
    ) -> AppGroupSnapshotCacheStatus {
        guard let defaults = userDefaults() else {
            return AppGroupSnapshotCacheStatus(
                isAvailable: false,
                schemaVersion: nil,
                generatedAt: nil,
                lastWriteAt: nil,
                byteCount: 0,
                staleAfter: staleAfter
            )
        }
        return status(defaults: defaults, now: now, staleAfter: staleAfter)
    }

    static func status(
        defaults: UserDefaults,
        now: Date = Date(),
        staleAfter: TimeInterval = AppGroupSchema.Freshness.generalStaleAfter
    ) -> AppGroupSnapshotCacheStatus {
        let snapshot = loadSnapshot(defaults: defaults, key: widgetSnapshotV2Key)
        let v2Data = defaults.data(forKey: widgetSnapshotV2Key)
        let legacyData = defaults.data(forKey: legacyWidgetSnapshotV2Key)
        let lastWriteValue = defaults.object(forKey: lastSnapshotWriteKey)
        let lastWriteAt: Date?
        if let timestamp = lastWriteValue as? TimeInterval {
            lastWriteAt = Date(timeIntervalSince1970: timestamp)
        } else if let date = lastWriteValue as? Date {
            lastWriteAt = date
        } else {
            lastWriteAt = nil
        }

        return AppGroupSnapshotCacheStatus(
            isAvailable: snapshot != nil || v2Data != nil || legacyData != nil,
            schemaVersion: snapshot?.schemaVersion,
            generatedAt: snapshot?.generatedAt,
            lastWriteAt: lastWriteAt,
            byteCount: (v2Data?.count ?? 0) + (legacyData?.count ?? 0),
            staleAfter: staleAfter
        )
    }

    static func load() -> AppGroupHealthSnapshot? {
        guard let defaults = userDefaults() else { return nil }
        return load(defaults: defaults)
    }

    static func save(_ snapshot: AppGroupHealthSnapshot) {
        guard let defaults = userDefaults() else { return }
        save(snapshot, defaults: defaults)
    }

    static func debugState() -> String {
        guard let defaults = userDefaults() else { return "no_app_group" }
        return debugState(defaults: defaults)
    }

    static func load(defaults: UserDefaults) -> AppGroupHealthSnapshot? {
        if let snapshot = loadSnapshot(defaults: defaults, key: widgetSnapshotV2Key) {
            return snapshot
        }

        guard let legacyData = defaults.data(forKey: legacyWidgetSnapshotV2Key),
              let legacySnapshot = try? JSONDecoder().decode(AppGroupHealthSnapshot.self, from: legacyData) else {
            return nil
        }

        defaults.set(legacyData, forKey: widgetSnapshotV2Key)
        defaults.removeObject(forKey: legacyWidgetSnapshotV2Key)
        return legacySnapshot
    }

    static func save(_ snapshot: AppGroupHealthSnapshot, defaults: UserDefaults) {
        let snapshotToSave: AppGroupHealthSnapshot
        if let current = loadSnapshot(defaults: defaults, key: widgetSnapshotV2Key) {
            guard current.generatedAt <= snapshot.generatedAt else { return }
            snapshotToSave = snapshot.preservingPreviouslySyncedDomains(from: current)
        } else {
            snapshotToSave = snapshot
        }

        guard let data = try? JSONEncoder().encode(snapshotToSave) else {
            return
        }

        defaults.set(data, forKey: widgetSnapshotV2Key)
        defaults.set(snapshotToSave.generatedAt.timeIntervalSince1970, forKey: lastSnapshotWriteKey)
        defaults.removeObject(forKey: legacyWidgetSnapshotV2Key)
    }

    static func clear(defaults: UserDefaults) {
        defaults.removeObject(forKey: widgetSnapshotV2Key)
        defaults.removeObject(forKey: legacyWidgetSnapshotV2Key)
        defaults.removeObject(forKey: lastSnapshotWriteKey)
    }

    static func clear() {
        guard let defaults = userDefaults() else { return }
        clear(defaults: defaults)
    }

    static func debugState(defaults: UserDefaults) -> String {
        let hasV2 = defaults.data(forKey: widgetSnapshotV2Key) != nil
        let hasLegacy = defaults.data(forKey: legacyWidgetSnapshotV2Key) != nil
        let lastWrite = defaults.object(forKey: lastSnapshotWriteKey) as? TimeInterval
        let lastWriteText = lastWrite.map { String(Int($0)) } ?? "nil"
        let snapshot = loadSnapshot(defaults: defaults, key: widgetSnapshotV2Key)
        let schemaText = snapshot.map { String($0.schemaVersion) } ?? "nil"
        let generatedAtText = snapshot.map { String(Int($0.generatedAt.timeIntervalSince1970)) } ?? "nil"
        return "v2=\(hasV2),legacy=\(hasLegacy),schema=\(schemaText),generatedAt=\(generatedAtText),write=\(lastWriteText)"
    }

    private static func loadSnapshot(defaults: UserDefaults, key: String) -> AppGroupHealthSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppGroupHealthSnapshot.self, from: data)
    }
}

enum SharedStorageReader {
    static func userDefaults() -> UserDefaults? {
        AppGroupSnapshotStore.userDefaults()
    }

    static func object(forKey key: String) -> Any? {
        userDefaults()?.object(forKey: key)
    }

    static func data(forKey key: String) -> Data? {
        object(forKey: key) as? Data
    }

    static func int(forKey key: String) -> Int? {
        if let int = object(forKey: key) as? Int { return int }
        if let double = object(forKey: key) as? Double { return Int(double.rounded()) }
        if let string = object(forKey: key) as? String { return Int(string) }
        return nil
    }

    static func double(forKey key: String) -> Double? {
        if let double = object(forKey: key) as? Double { return double }
        if let int = object(forKey: key) as? Int { return Double(int) }
        if let string = object(forKey: key) as? String { return Double(string) }
        return nil
    }

    static func string(forKey key: String) -> String? {
        if let string = object(forKey: key) as? String {
            return string
        }
        return userDefaults()?.string(forKey: key)
    }

    static func bool(forKey key: String) -> Bool? {
        if let bool = object(forKey: key) as? Bool { return bool }
        if let int = object(forKey: key) as? Int { return int != 0 }
        if let double = object(forKey: key) as? Double { return double != 0 }
        if let string = object(forKey: key) as? String {
            let normalized = string.lowercased()
            if normalized == "true" { return true }
            if normalized == "false" { return false }
            if let int = Int(normalized) { return int != 0 }
        }
        return nil
    }

    static func date(forKey key: String) -> Date? {
        if let date = object(forKey: key) as? Date {
            return date
        }
        guard let timestamp = double(forKey: key) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }
}
