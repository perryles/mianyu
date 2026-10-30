import Foundation
import SwiftData

nonisolated struct MoodOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let backendEmotionCode: String
    let accentHex: String
    let defaultIntensity: Int
}

enum MoodCatalog {
    static let options: [MoodOption] = [
        MoodOption(id: "happy", title: "开心", backendEmotionCode: "happy", accentHex: "F3CF3A", defaultIntensity: 72),
        MoodOption(id: "moved", title: "心动", backendEmotionCode: "happy", accentHex: "F0C235", defaultIntensity: 78),
        MoodOption(id: "excited", title: "兴奋", backendEmotionCode: "happy", accentHex: "E9C935", defaultIntensity: 84),
        MoodOption(id: "calm", title: "平静", backendEmotionCode: "neutral", accentHex: "E7CB54", defaultIntensity: 45),
        MoodOption(id: "anxious", title: "焦虑", backendEmotionCode: "anxious", accentHex: "57C66D", defaultIntensity: 82),
        MoodOption(id: "drained", title: "心累", backendEmotionCode: "tired", accentHex: "58C482", defaultIntensity: 72),
        MoodOption(id: "burnedout", title: "颓废", backendEmotionCode: "tired", accentHex: "63C46F", defaultIntensity: 70),
        MoodOption(id: "confused", title: "难以描述", backendEmotionCode: "neutral", accentHex: "7CB7EA", defaultIntensity: 55),
        MoodOption(id: "sad", title: "难过", backendEmotionCode: "sad", accentHex: "86BCEE", defaultIntensity: 74),
        MoodOption(id: "lonely", title: "孤独", backendEmotionCode: "sad", accentHex: "93C0EC", defaultIntensity: 68),
        MoodOption(id: "wronged", title: "委屈", backendEmotionCode: "sad", accentHex: "7D68E8", defaultIntensity: 72),
        MoodOption(id: "angry", title: "生气", backendEmotionCode: "anxious", accentHex: "785BE6", defaultIntensity: 86)
    ]

    static func option(id: String) -> MoodOption? {
        options.first(where: { $0.id == id })
    }

    static func defaultOption(for backendCode: String) -> MoodOption {
        switch backendCode {
        case "happy":
            return option(id: "happy") ?? options[0]
        case "anxious":
            return option(id: "anxious") ?? options[4]
        case "tired":
            return option(id: "drained") ?? options[5]
        case "sad":
            return option(id: "sad") ?? options[8]
        case "neutral":
            return option(id: "calm") ?? options[3]
        default:
            return option(id: "calm") ?? options[3]
        }
    }
}

nonisolated struct MoodEntry: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let moodID: String
    let title: String
    let backendEmotionCode: String
    let intensity: Int
    /// 用户主动选择的影响因素；旧记录解码时为 nil，保持向后兼容。
    var factors: [String]? = nil
    let note: String?
    let loggedAt: Date
    var backendRecordedAt: Date?
}

final class MoodStore {
    static let shared = MoodStore()

    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let calendar = Calendar.current
    private let key = "moodStore.v1"
    private let domain = "mood"
    private let kind = "entry"

    private struct Payload: Codable {
        var entries: [MoodEntry]
    }

    init(
        defaults: UserDefaults = .standard,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        records = SwiftDataRecordStore(container: container)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        migrateLegacyDataIfNeeded()
    }

    func save(_ entry: MoodEntry) {
        guard let payload = try? encoder.encode(entry) else { return }
        let didSave = records.upsert(
            LocalDataRecordSeed(
                domain: domain,
                recordID: entry.id,
                kind: kind,
                occurredAt: entry.loggedAt,
                updatedAt: entry.backendRecordedAt ?? entry.loggedAt,
                payload: payload
            ),
            keepingNewest: 240
        )
        if didSave {
            NotificationCenter.default.post(name: .profileVitalityRecordsDidChange, object: self)
        }
    }

    func entries(on date: Date = Date()) -> [MoodEntry] {
        allEntries().filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
    }

    func allEntries() -> [MoodEntry] {
        guard let rows = records.records(domain: domain, kind: kind) else {
            return loadLegacy().entries.sorted { $0.loggedAt > $1.loggedAt }
        }
        return rows.compactMap { try? decoder.decode(MoodEntry.self, from: $0.payload) }
    }

    private func loadLegacy() -> Payload {
        guard let data = defaults.data(forKey: key),
              let payload = try? decoder.decode(Payload.self, from: data) else {
            return Payload(entries: [])
        }
        return payload
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "moodStore.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            return
        }
        let legacyData = defaults.data(forKey: key)
        let legacyEntries: [MoodEntry]
        if let legacyData {
            guard let payload = try? decoder.decode(Payload.self, from: legacyData) else { return }
            legacyEntries = payload.entries
        } else {
            legacyEntries = []
        }
        let seeds = legacyEntries.compactMap { entry -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(entry) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: entry.id,
                kind: kind,
                occurredAt: entry.loggedAt,
                updatedAt: entry.backendRecordedAt ?? entry.loggedAt,
                payload: data
            )
        }
        guard seeds.count == legacyEntries.count,
              records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: key)
    }
}
