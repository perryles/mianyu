import Foundation

final class ActionRecordStore {
    static let shared = ActionRecordStore()

    private let storage: FitnessCalendarStore
    private let caffeineEventStore: CaffeineDoseEventStore

    init(defaults: UserDefaults = .standard) {
        self.storage = FitnessCalendarStore(defaults: defaults)
        self.caffeineEventStore = CaffeineDoseEventStore(defaults: defaults)
    }

    func allRecords() -> [LocalActionDayRecord] {
        storage.allRecords()
    }

    func record(for date: Date) -> LocalActionDayRecord {
        storage.record(for: date)
    }

    func updateRecord(
        for date: Date,
        mutate: (inout LocalActionDayRecord) -> Void
    ) {
        storage.updateRecord(for: date, mutate: mutate)
    }

    func setShared(_ isShared: Bool, for date: Date) {
        storage.setShared(isShared, for: date)
    }

    func recentSharedRecords(limit: Int = 3) -> [LocalActionDayRecord] {
        storage.recentSharedRecords(limit: limit)
    }

    func dayKey(for date: Date) -> String {
        storage.dayKey(for: date)
    }

    func normalizedDate(for date: Date) -> Date {
        storage.normalizedDate(for: date)
    }

    func behaviorSnapshot(for date: Date) -> LocalActionDayRecord {
        record(for: date)
    }

    func recordCaffeineDose(
        amountMg: Int,
        at consumedAt: Date = Date(),
        source: CaffeineDoseSource,
        note: String? = nil
    ) {
        guard amountMg > 0 else { return }
        caffeineEventStore.append(amountMg: amountMg, consumedAt: consumedAt, source: source, note: note)
    }

    func caffeineDoseEvents(on date: Date) -> [CaffeineDoseEvent] {
        caffeineEventStore.events(on: date)
    }

    func caffeineDoseEvents(in interval: DateInterval) -> [CaffeineDoseEvent] {
        caffeineEventStore.events(in: interval)
    }
}
