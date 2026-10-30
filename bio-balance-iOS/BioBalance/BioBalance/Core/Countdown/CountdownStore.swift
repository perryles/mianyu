import Foundation
import SwiftData

struct LocalCountdownItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var title: String
    var targetDate: Date
    var note: String?
    var isPinned: Bool
    var isShared: Bool
    let createdAt: Date
    var updatedAt: Date
}

final class CountdownStore {
    static let shared = CountdownStore()

    private let key = "countdownStore.v1"
    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let domain = "countdown"
    private let kind = "item"

    private struct Payload: Codable {
        var items: [LocalCountdownItem]
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

    func items() -> [LocalCountdownItem] {
        loadPayload().items.sorted(by: sortComparator)
    }

    func upsert(
        id: String? = nil,
        title: String,
        targetDate: Date,
        note: String?,
        isPinned: Bool,
        isShared: Bool
    ) {
        var payload = loadPayload()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let now = Date()

        if let id, let index = payload.items.firstIndex(where: { $0.id == id }) {
            payload.items[index].title = trimmedTitle
            payload.items[index].targetDate = targetDate
            payload.items[index].note = sanitized(note)
            payload.items[index].isPinned = isPinned
            payload.items[index].isShared = isShared
            payload.items[index].updatedAt = now
        } else {
            payload.items.append(
                LocalCountdownItem(
                    id: id ?? UUID().uuidString,
                    title: trimmedTitle,
                    targetDate: targetDate,
                    note: sanitized(note),
                    isPinned: isPinned,
                    isShared: isShared,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        savePayload(payload)
    }

    func delete(id: String) {
        var payload = loadPayload()
        payload.items.removeAll { $0.id == id }
        savePayload(payload)
    }

    func setShared(_ isShared: Bool, id: String) {
        mutate(id: id) { item in
            item.isShared = isShared
        }
    }

    func setPinned(_ isPinned: Bool, id: String) {
        mutate(id: id) { item in
            item.isPinned = isPinned
        }
    }

    func recentSharedItems(limit: Int = 3) -> [LocalCountdownItem] {
        items()
            .filter(\.isShared)
            .prefix(limit)
            .map { $0 }
    }

    private func mutate(id: String, _ update: (inout LocalCountdownItem) -> Void) {
        var payload = loadPayload()
        guard let index = payload.items.firstIndex(where: { $0.id == id }) else { return }
        update(&payload.items[index])
        payload.items[index].updatedAt = Date()
        savePayload(payload)
    }

    private func loadPayload() -> Payload {
        if let rows = records.records(domain: domain, kind: kind) {
            return Payload(items: rows.compactMap { try? decoder.decode(LocalCountdownItem.self, from: $0.payload) })
        }
        return loadLegacyPayload()
    }

    private func loadLegacyPayload() -> Payload {
        guard let data = defaults.data(forKey: key),
              let payload = try? decoder.decode(Payload.self, from: data) else {
            return Payload(items: [])
        }
        return payload
    }

    private func savePayload(_ payload: Payload) {
        let sorted = payload.items.sorted(by: sortComparator)
        let seeds = sorted.compactMap { item -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(item) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: item.id,
                kind: kind,
                occurredAt: item.targetDate,
                updatedAt: item.updatedAt,
                payload: data
            )
        }
        guard seeds.count == sorted.count else { return }
        _ = records.replace(domain: domain, kind: kind, with: seeds)
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "countdownStore.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            return
        }
        let legacyData = defaults.data(forKey: key)
        let items: [LocalCountdownItem]
        if let legacyData {
            guard let payload = try? decoder.decode(Payload.self, from: legacyData) else { return }
            items = payload.items
        } else {
            items = []
        }
        let seeds = items.compactMap { item -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(item) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: item.id,
                kind: kind,
                occurredAt: item.targetDate,
                updatedAt: item.updatedAt,
                payload: data
            )
        }
        guard seeds.count == items.count, records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: key)
    }

    private func sortComparator(lhs: LocalCountdownItem, rhs: LocalCountdownItem) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }
        if lhs.targetDate != rhs.targetDate {
            return lhs.targetDate < rhs.targetDate
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func sanitized(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
