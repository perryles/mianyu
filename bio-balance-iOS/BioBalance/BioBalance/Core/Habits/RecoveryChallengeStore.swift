import Foundation
import SwiftData

final class RecoveryChallengeStore {
    static let shared = RecoveryChallengeStore()

    private let key = "recoveryChallengeStore.v1"
    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let calendar: Calendar
    private let evaluator: RecoveryChallengeEvaluator
    private let dataProvider: RecoveryChallengeDataProviding
    private let reminderScheduler: UnifiedReminderScheduling
    private let domain = "recovery-challenge"
    private let kind = "record"

    private struct Payload: Codable {
        var records: [RecoveryChallengeRecord]
    }

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        evaluator: RecoveryChallengeEvaluator? = nil,
        dataProvider: RecoveryChallengeDataProviding? = nil,
        reminderScheduler: UnifiedReminderScheduling = UnifiedReminderWindowCoordinator.shared,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        records = SwiftDataRecordStore(container: container)
        self.calendar = calendar
        self.evaluator = evaluator ?? RecoveryChallengeEvaluator(calendar: calendar)
        self.dataProvider = dataProvider ?? RecoveryChallengeLiveDataProvider(calendar: calendar)
        self.reminderScheduler = reminderScheduler
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        migrateLegacyDataIfNeeded()
    }

    func activeChallenge() -> RecoveryChallengeRecord? {
        allRecords().first(where: { $0.status == .active })
    }

    func allRecords() -> [RecoveryChallengeRecord] {
        loadPayload().records.sorted { $0.createdAt > $1.createdAt }
    }

    func history(limit: Int = 3) -> [RecoveryChallengeRecord] {
        allRecords()
            .filter { $0.status != .active }
            .sorted { $0.latestRelevantDate > $1.latestRelevantDate }
            .prefix(limit)
            .map { $0 }
    }

    func refreshReminderSchedule() {
        let records = allRecords()
        let active = records.first(where: { $0.status == .active })
        let staleIdentifiers = records
            .filter { $0.id != active?.id || active?.reminderEnabled != true }
            .map { reminderIdentifier(for: $0.id) }
        reminderScheduler.cancel(identifiers: staleIdentifiers)

        guard let active, active.reminderEnabled else { return }
        scheduleReminder(for: active)
    }

    @discardableResult
    func start(kind: RecoveryChallengeKind, on date: Date = Date()) -> RecoveryChallengeRecord? {
        guard activeChallenge() == nil else { return nil }
        let normalizedStart = calendar.startOfDay(for: date)
        var payload = loadPayload()
        let targetText = targetText(for: kind)
        let progresses = (0..<7).compactMap { offset -> RecoveryChallengeDayProgress? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: normalizedStart) else { return nil }
            return RecoveryChallengeDayProgress.placeholder(for: day, targetText: targetText)
        }
        let record = RecoveryChallengeRecord(kind: kind, startDate: normalizedStart, dayProgresses: progresses)
        payload.records.insert(record, at: 0)
        payload.records = Array(payload.records.prefix(24))
        savePayload(payload)
        scheduleReminder(for: record)
        return record
    }

    @discardableResult
    func restart(kind: RecoveryChallengeKind, on date: Date = Date()) -> RecoveryChallengeRecord? {
        guard activeChallenge() == nil else { return nil }
        return start(kind: kind, on: date)
    }

    func abandonActiveChallenge() {
        guard var record = activeChallenge() else { return }
        record.status = .abandoned
        record.abandonedAt = Date()
        record.reminderEnabled = false
        replace(record)
        cancelReminder(for: record.id)
    }

    @discardableResult
    func toggleReminderEnabled(_ enabled: Bool, for recordID: UUID) -> RecoveryChallengeRecord? {
        guard var record = allRecords().first(where: { $0.id == recordID }) else { return nil }
        record.reminderEnabled = enabled && record.status == .active
        replace(record)
        if record.reminderEnabled {
            scheduleReminder(for: record)
        } else {
            cancelReminder(for: recordID)
        }
        return record
    }

    @discardableResult
    func evaluateAndRefresh(on date: Date = Date()) async -> RecoveryChallengeRecord? {
        guard let active = activeChallenge() else { return nil }
        let context = RecoveryChallengeEvaluationContext(
            now: date,
            calendar: calendar,
            dataProvider: dataProvider
        )
        let updated = await evaluator.evaluateAndRefresh(record: active, on: date, context: context)
        replace(updated)
        if updated.status == .active, updated.reminderEnabled {
            scheduleReminder(for: updated)
        } else {
            cancelReminder(for: updated.id)
        }
        return updated
    }

    private func replace(_ record: RecoveryChallengeRecord) {
        var payload = loadPayload()
        if let index = payload.records.firstIndex(where: { $0.id == record.id }) {
            payload.records[index] = record
        } else {
            payload.records.insert(record, at: 0)
        }
        payload.records = payload.records
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(24)
            .map { $0 }
        savePayload(payload)
    }

    private func reminderIdentifier(for recordID: UUID) -> String {
        "recovery.challenge.\(recordID.uuidString)"
    }

    private func scheduleReminder(for record: RecoveryChallengeRecord) {
        guard record.reminderEnabled, record.status == .active else { return }
        let definition = record.definition
        reminderScheduler.scheduleDaily(
            identifier: reminderIdentifier(for: record.id),
            hour: definition.reminderHour,
            minute: definition.reminderMinute,
            title: definition.title,
            body: reminderBody(for: record.kind),
            source: .recoveryChallenge,
            priority: 300
        )
    }

    private func cancelReminder(for recordID: UUID) {
        reminderScheduler.cancel(identifiers: [reminderIdentifier(for: recordID)])
    }

    private func reminderBody(for kind: RecoveryChallengeKind) -> String {
        switch kind {
        case .sleepEarly:
            return String(localized: "今天尽量提前收尾，把入睡时间守在 00:30 前。")
        case .lowCaffeine:
            return String(localized: "后半天尽量别再补高咖啡因，把今天守在 200 mg 内。")
        case .sunlight:
            return String(localized: "今天补一点自然光暴露，把日照时长拉到 20 分钟。")
        }
    }

    private func targetText(for kind: RecoveryChallengeKind) -> String {
        switch kind {
        case .sleepEarly:
            return String(localized: "不晚于 00:30")
        case .lowCaffeine:
            return "<= 200 mg"
        case .sunlight:
            return ">= 20 分钟"
        }
    }

    private func loadPayload() -> Payload {
        if let rows = records.records(domain: domain, kind: kind) {
            return Payload(records: rows.compactMap { try? decoder.decode(RecoveryChallengeRecord.self, from: $0.payload) })
        }
        return loadLegacyPayload()
    }

    private func loadLegacyPayload() -> Payload {
        guard let data = defaults.data(forKey: key),
              let payload = try? decoder.decode(Payload.self, from: data) else {
            return Payload(records: [])
        }
        return payload
    }

    private func savePayload(_ payload: Payload) {
        let seeds = payload.records.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(record) else { return nil }
            return makeSeed(record: record, payload: data)
        }
        guard seeds.count == payload.records.count,
              records.replace(domain: domain, kind: kind, with: seeds) else { return }
        NotificationCenter.default.post(name: .profileVitalityRecordsDidChange, object: self)
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "recoveryChallengeStore.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            return
        }
        let legacyData = defaults.data(forKey: key)
        let legacyRecords: [RecoveryChallengeRecord]
        if let legacyData {
            guard let payload = try? decoder.decode(Payload.self, from: legacyData) else { return }
            legacyRecords = payload.records
        } else {
            legacyRecords = []
        }
        let seeds = legacyRecords.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(record) else { return nil }
            return makeSeed(record: record, payload: data)
        }
        guard seeds.count == legacyRecords.count, records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: key)
    }

    private func makeSeed(record: RecoveryChallengeRecord, payload: Data) -> LocalDataRecordSeed {
        LocalDataRecordSeed(
            domain: domain,
            recordID: record.id.uuidString,
            kind: kind,
            occurredAt: record.startDate,
            updatedAt: record.latestRelevantDate,
            payload: payload
        )
    }
}
