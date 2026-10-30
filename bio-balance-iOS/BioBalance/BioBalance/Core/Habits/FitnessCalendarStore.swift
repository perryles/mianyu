import Foundation
import SwiftData

final class FitnessCalendarStore {
    static let shared = FitnessCalendarStore()

    private let key = "actionRecordStore.v2"
    private let legacyKey = "actionRecordStore.v1"
    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let calendar = Calendar.current
    private let domain = "action-day"
    private let kind = "record"

    private struct Payload: Codable {
        var records: [LocalActionDayRecord]
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

    func allRecords() -> [LocalActionDayRecord] {
        guard let rows = records.records(domain: domain, kind: kind) else {
            return loadLegacyPayload().records.sorted { $0.date > $1.date }
        }
        return rows.compactMap { try? decoder.decode(LocalActionDayRecord.self, from: $0.payload) }
    }

    func record(for date: Date) -> LocalActionDayRecord {
        let normalized = normalizedDate(for: date)
        if let existing = allRecords().first(where: { calendar.isDate($0.date, inSameDayAs: normalized) }) {
            return existing
        }
        return emptyRecord(for: normalized)
    }

    func updateRecord(for date: Date, mutate: (inout LocalActionDayRecord) -> Void) {
        let normalized = normalizedDate(for: date)
        var record = allRecords().first { calendar.isDate($0.date, inSameDayAs: normalized) }
            ?? emptyRecord(for: normalized)

        mutate(&record)
        record.completedActions = Array(Set(record.completedActions)).sorted { $0.rawValue < $1.rawValue }
        record.updatedAt = Date()

        guard let payload = try? encoder.encode(record) else { return }
        let didSave = records.upsert(
            LocalDataRecordSeed(
                domain: domain,
                recordID: record.id,
                kind: kind,
                occurredAt: record.date,
                updatedAt: record.updatedAt,
                payload: payload
            ),
            keepingNewest: 180
        )
        if didSave {
            NotificationCenter.default.post(name: .profileVitalityRecordsDidChange, object: self)
        }
    }

    func setShared(_ isShared: Bool, for date: Date) {
        updateRecord(for: date) { record in
            record.isShared = isShared
        }
    }

    func recentSharedRecords(limit: Int = 3) -> [LocalActionDayRecord] {
        allRecords()
            .filter(\.isShared)
            .prefix(limit)
            .map { $0 }
    }

    func setFitnessCheckin(mode: FitnessCheckinMode, for date: Date) {
        updateRecord(for: date) { record in
            record.fitnessCheckinMode = mode
            record.checkedInAt = Date()
            if mode != .workout {
                record.manualWorkoutMinutes = 0
                record.manualWorkoutEffort = nil
                record.fitnessNote = ""
            }
        }
    }

    func clearFitnessCheckin(for date: Date) {
        updateRecord(for: date) { record in
            record.fitnessCheckinMode = nil
            record.manualWorkoutMinutes = 0
            record.manualWorkoutEffort = nil
            record.fitnessNote = ""
            record.checkedInAt = nil
        }
    }

    func saveFitnessDetail(
        for date: Date,
        mode: FitnessCheckinMode?,
        minutes: Int,
        effort: WorkoutEffortLevel?,
        note: String,
        isShared: Bool
    ) {
        updateRecord(for: date) { record in
            record.fitnessCheckinMode = mode
            record.manualWorkoutMinutes = max(0, minutes)
            record.manualWorkoutEffort = mode == .workout ? effort : nil
            record.fitnessNote = mode == .workout ? note : ""
            record.isShared = isShared
            record.checkedInAt = mode == nil ? nil : (record.checkedInAt ?? Date())
            if mode != .workout {
                record.manualWorkoutMinutes = 0
            }
        }
    }

    /// 保存详情页的完整草稿：在原有字段之外还包含运动距离与当日心情。
    func saveFitnessDetail(for date: Date, draft: FitnessDayDetailDraft) {
        updateRecord(for: date) { record in
            record.fitnessCheckinMode = draft.mode
            record.manualWorkoutMinutes = draft.mode == .workout ? max(0, draft.minutes) : 0
            record.manualWorkoutDistanceKm = draft.mode == .workout ? max(0, draft.distanceKm) : 0
            record.manualWorkoutEffort = draft.mode == .workout ? draft.effort : nil
            record.fitnessNote = draft.mode == .workout ? draft.note : ""
            record.dailyMood = draft.mood
            record.isShared = draft.isShared
            record.checkedInAt = draft.mode == nil ? nil : (record.checkedInAt ?? Date())
        }
    }

    func dayKey(for date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    func normalizedDate(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func emptyRecord(for normalized: Date) -> LocalActionDayRecord {
        LocalActionDayRecord(
            id: dayKey(for: normalized),
            date: normalized,
            completedActions: [],
            waterMl: 0,
            caffeineMg: 0,
            sunlightMinutes: 0,
            mindfulnessMinutes: 0,
            standHours: 0,
            isShared: false,
            fitnessCheckinMode: nil,
            manualWorkoutMinutes: 0,
            manualWorkoutEffort: nil,
            fitnessNote: "",
            checkedInAt: nil,
            updatedAt: normalized
        )
    }

    private func loadLegacyPayload() -> Payload {
        if let data = defaults.data(forKey: key),
           let payload = try? decoder.decode(Payload.self, from: data) {
            return payload
        }

        if let data = defaults.data(forKey: legacyKey),
           let payload = try? decoder.decode(Payload.self, from: data) {
            return payload
        }

        return Payload(records: [])
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "actionRecordStore.v2-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: legacyKey)
            return
        }

        let hasLegacyData = defaults.data(forKey: key) != nil || defaults.data(forKey: legacyKey) != nil
        let legacyRecords = loadLegacyPayload().records
        if hasLegacyData, legacyRecords.isEmpty {
            let currentData = defaults.data(forKey: key) ?? defaults.data(forKey: legacyKey)
            guard currentData.flatMap({ try? decoder.decode(Payload.self, from: $0) }) != nil else { return }
        }
        let seeds = legacyRecords.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(record) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: record.id,
                kind: kind,
                occurredAt: record.date,
                updatedAt: record.updatedAt,
                payload: data
            )
        }
        guard seeds.count == legacyRecords.count,
              records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: legacyKey)
    }
}
