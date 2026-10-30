import Foundation
import SwiftData

final class CaffeineDoseEventStore {
    static let shared = CaffeineDoseEventStore()

    private let key = "caffeineDoseEventStore.v1"
    private let domain = "caffeine-dose"
    private let kind = "event"
    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let calendar = Calendar.current

    private struct Payload: Codable {
        var events: [CaffeineDoseEvent]
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

    func allEvents() -> [CaffeineDoseEvent] {
        guard let rows = records.records(domain: domain, kind: kind) else {
            return loadLegacyPayload().events.sorted { $0.consumedAt > $1.consumedAt }
        }
        return rows.compactMap { try? decoder.decode(CaffeineDoseEvent.self, from: $0.payload) }
    }

    func events(on date: Date) -> [CaffeineDoseEvent] {
        let normalized = calendar.startOfDay(for: date)
        return allEvents()
            .filter { calendar.isDate($0.consumedAt, inSameDayAs: normalized) }
            .sorted { $0.consumedAt < $1.consumedAt }
    }

    func events(in interval: DateInterval) -> [CaffeineDoseEvent] {
        allEvents()
            .filter { interval.contains($0.consumedAt) }
            .sorted { $0.consumedAt < $1.consumedAt }
    }

    func append(
        amountMg: Int,
        consumedAt: Date = Date(),
        source: CaffeineDoseSource,
        note: String? = nil
    ) {
        guard amountMg > 0 else { return }
        let event = CaffeineDoseEvent(
            amountMg: amountMg,
            consumedAt: consumedAt,
            source: source,
            note: note
        )
        guard let payload = try? encoder.encode(event) else { return }
        let didSave = records.upsert(
            LocalDataRecordSeed(
                domain: domain,
                recordID: event.id.uuidString.lowercased(),
                kind: kind,
                occurredAt: event.consumedAt,
                updatedAt: Date(),
                payload: payload
            ),
            keepingNewest: 512
        )
        if didSave {
            NotificationCenter.default.post(name: .profileVitalityRecordsDidChange, object: self)
        }
    }

    private func loadLegacyPayload() -> Payload {
        guard let data = defaults.data(forKey: key),
              let payload = try? decoder.decode(Payload.self, from: data) else {
            return Payload(events: [])
        }
        return payload
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "caffeineDoseEventStore.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            return
        }
        let legacyData = defaults.data(forKey: key)
        let legacyEvents: [CaffeineDoseEvent]
        if let legacyData {
            guard let payload = try? decoder.decode(Payload.self, from: legacyData) else { return }
            legacyEvents = payload.events
        } else {
            legacyEvents = []
        }
        let seeds = legacyEvents.compactMap { event -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(event) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: event.id.uuidString.lowercased(),
                kind: kind,
                occurredAt: event.consumedAt,
                updatedAt: event.consumedAt,
                payload: data
            )
        }
        guard seeds.count == legacyEvents.count,
              records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: key)
    }
}
