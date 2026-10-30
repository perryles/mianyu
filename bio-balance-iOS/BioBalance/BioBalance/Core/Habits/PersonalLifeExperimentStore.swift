import Foundation
import SwiftData

final class PersonalLifeExperimentStore {
    static let shared = PersonalLifeExperimentStore()

    private let records: SwiftDataRecordStore
    private let calendar: Calendar
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let domain = "personal-life-experiment"
    private let kind = "record"

    init(calendar: Calendar = .current, container: ModelContainer = MianyuModelContainer.shared) {
        self.calendar = calendar
        records = SwiftDataRecordStore(container: container)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func allRecords() -> [PersonalLifeExperimentRecord] {
        (records.records(domain: domain, kind: kind) ?? [])
            .compactMap { try? decoder.decode(PersonalLifeExperimentRecord.self, from: $0.payload) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func activeExperiment(on referenceDate: Date = Date()) -> PersonalLifeExperimentRecord? {
        guard var active = allRecords().first(where: { $0.status == .active }) else { return nil }
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let completionDay = calendar.date(byAdding: .day, value: active.durationDays, to: active.startDate)
        guard let completionDay, referenceDay >= completionDay else { return active }

        active.status = .completed
        active.endedAt = completionDay
        active.updatedAt = max(active.updatedAt, completionDay)
        return save(active) ? nil : active
    }

    @discardableResult
    func start(kind: PersonalLifeExperimentKind, on date: Date = Date()) -> PersonalLifeExperimentRecord? {
        guard activeExperiment(on: date) == nil else { return nil }
        let record = PersonalLifeExperimentRecord(kind: kind, startDate: calendar.startOfDay(for: date))
        return save(record) ? record : nil
    }

    @discardableResult
    func saveCheckIn(
        on date: Date = Date(),
        followedPlan: Bool,
        feelingScore: Int?
    ) -> PersonalLifeExperimentRecord? {
        guard var record = activeExperiment(on: date) else { return nil }
        let day = calendar.startOfDay(for: date)
        guard let offset = calendar.dateComponents([.day], from: record.startDate, to: day).day,
              (0..<record.durationDays).contains(offset),
              feelingScore.map({ (1...5).contains($0) }) ?? true else { return nil }

        let checkIn = PersonalLifeExperimentCheckIn(
            date: day,
            followedPlan: followedPlan,
            feelingScore: feelingScore,
            updatedAt: Date()
        )
        if let index = record.checkIns.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            record.checkIns[index] = checkIn
        } else {
            record.checkIns.append(checkIn)
        }
        record.checkIns.sort { $0.date < $1.date }
        record.updatedAt = checkIn.updatedAt
        if offset == record.durationDays - 1 {
            record.status = .completed
            record.endedAt = checkIn.updatedAt
        }
        return save(record) ? record : nil
    }

    @discardableResult
    func endActive(on date: Date = Date()) -> PersonalLifeExperimentRecord? {
        guard var record = activeExperiment(on: date) else { return nil }
        record.status = .ended
        record.endedAt = date
        record.updatedAt = date
        return save(record) ? record : nil
    }

    @discardableResult
    private func save(_ record: PersonalLifeExperimentRecord) -> Bool {
        guard let data = try? encoder.encode(record) else { return false }
        let result = records.upsert(
            LocalDataRecordSeed(
                domain: domain,
                recordID: record.id.uuidString,
                kind: kind,
                occurredAt: record.startDate,
                updatedAt: record.updatedAt,
                payload: data
            ),
            keepingNewest: 40
        )
        if result {
            NotificationCenter.default.post(name: .personalLifeExperimentDidChange, object: self)
        }
        return result
    }
}

extension Notification.Name {
    static let personalLifeExperimentDidChange = Notification.Name("personalLifeExperimentDidChange")
}
