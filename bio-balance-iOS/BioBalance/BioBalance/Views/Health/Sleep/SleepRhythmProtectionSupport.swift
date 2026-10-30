/// SleepRhythmProtectionSupport 作为睡眠节律保护的支撑类型。
/// 负责定义计划状态枚举（进行中/已完成/已放弃）及相关计划记录数据结构。

import Foundation
import SwiftData

enum SleepRhythmProtectionStatus: String, Codable, Sendable {
    case active
    case finished
    case abandoned
}

struct SleepRhythmProtectionPlanRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var mode: SleepRhythmTrainingMode
    var status: SleepRhythmProtectionStatus
    var startDate: Date
    var createdAt: Date
    var updatedAt: Date
    var targetOffsetMinutes: Int
    var completedDayKeys: Set<String>
    var completedStepIDsByDay: [String: Set<String>]
    var reminderEnabled: Bool

    init(
        id: UUID = UUID(),
        mode: SleepRhythmTrainingMode,
        status: SleepRhythmProtectionStatus = .active,
        startDate: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        targetOffsetMinutes: Int = 0,
        completedDayKeys: Set<String> = [],
        completedStepIDsByDay: [String: Set<String>] = [:],
        reminderEnabled: Bool = false
    ) {
        self.id = id
        self.mode = mode
        self.status = status
        self.startDate = startDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.targetOffsetMinutes = targetOffsetMinutes
        self.completedDayKeys = completedDayKeys
        self.completedStepIDsByDay = completedStepIDsByDay
        self.reminderEnabled = reminderEnabled
    }
}

struct SleepRhythmProtectionSummary: Equatable, Sendable {
    let mode: SleepRhythmTrainingMode
    let status: SleepRhythmProtectionStatus
    let dayIndex: Int
    let totalDays: Int
    let progress: Double
    let targetBedtime: Date?
    let headline: String
    let tonightFocus: String
    let rescueText: String
    let completedStepIDs: Set<String>
    let completedDayKeys: Set<String>
    let targetOffsetMinutes: Int
    let reminderEnabled: Bool
    let isActivePlan: Bool
}

final class SleepRhythmProtectionStore {
    static let shared = SleepRhythmProtectionStore()

    private let key = "sleepRhythmProtectionStore.v1"
    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let calendar: Calendar
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let domain = "sleep-rhythm-protection"
    private let kind = "plan"

    private struct Payload: Codable {
        var records: [SleepRhythmProtectionPlanRecord]
    }

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        records = SwiftDataRecordStore(container: container)
        self.calendar = calendar
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        migrateLegacyDataIfNeeded()
    }

    func activePlan() -> SleepRhythmProtectionPlanRecord? {
        loadPayload().records.first(where: { $0.status == .active })
    }

    func latestPlan(for mode: SleepRhythmTrainingMode) -> SleepRhythmProtectionPlanRecord? {
        loadPayload().records
            .sorted { $0.updatedAt > $1.updatedAt }
            .first(where: { $0.mode == mode })
    }

    @discardableResult
    func start(mode: SleepRhythmTrainingMode, on date: Date = Date()) -> SleepRhythmProtectionPlanRecord {
        var payload = loadPayload()
        let normalized = calendar.startOfDay(for: date)
        for index in payload.records.indices where payload.records[index].status == .active {
            payload.records[index].status = .finished
            payload.records[index].updatedAt = Date()
            cancelReminder(for: payload.records[index].id)
        }
        let record = SleepRhythmProtectionPlanRecord(mode: mode, startDate: normalized)
        payload.records.insert(record, at: 0)
        savePayload(trimmed(payload))
        return record
    }

    @discardableResult
    func ensureActivePlan(mode: SleepRhythmTrainingMode, on date: Date = Date()) -> SleepRhythmProtectionPlanRecord {
        if var active = activePlan() {
            if active.mode != mode {
                active.mode = mode
                active.updatedAt = Date()
                replace(active)
            }
            return active
        }
        return start(mode: mode, on: date)
    }

    @discardableResult
    func toggleStep(_ stepID: String, on date: Date = Date()) -> SleepRhythmProtectionPlanRecord? {
        guard var record = activePlan() else { return nil }
        let dayKey = dayKey(for: date)
        var ids = record.completedStepIDsByDay[dayKey] ?? []
        if ids.contains(stepID) {
            ids.remove(stepID)
        } else {
            ids.insert(stepID)
        }
        record.completedStepIDsByDay[dayKey] = ids
        record.updatedAt = Date()
        replace(record)
        return record
    }

    @discardableResult
    func toggleTodayCompleted(on date: Date = Date()) -> SleepRhythmProtectionPlanRecord? {
        guard var record = activePlan() else { return nil }
        let key = dayKey(for: date)
        if record.completedDayKeys.contains(key) {
            record.completedDayKeys.remove(key)
        } else {
            record.completedDayKeys.insert(key)
        }
        record.updatedAt = Date()
        replace(record)
        return record
    }

    @discardableResult
    func adjustTargetOffset(
        by delta: Int?,
        baseTargetBedtime: Date? = nil,
        on date: Date = Date()
    ) -> SleepRhythmProtectionPlanRecord? {
        guard var record = activePlan() else { return nil }
        if let delta {
            record.targetOffsetMinutes = min(90, max(-90, record.targetOffsetMinutes + delta))
        } else {
            record.targetOffsetMinutes = 0
        }
        record.updatedAt = date
        replace(record)
        // 目标发生变化时同步覆盖同标识的每日通知，避免界面时间与提醒时间不一致。
        if record.reminderEnabled {
            let adjustedTarget = baseTargetBedtime.flatMap {
                calendar.date(byAdding: .minute, value: record.targetOffsetMinutes, to: $0)
            }
            scheduleReminder(for: record, targetBedtime: adjustedTarget)
        }
        return record
    }

    @discardableResult
    func toggleReminderEnabled(_ enabled: Bool, targetBedtime: Date?) -> SleepRhythmProtectionPlanRecord? {
        guard var record = activePlan() else { return nil }
        record.reminderEnabled = enabled
        record.updatedAt = Date()
        replace(record)
        if enabled {
            scheduleReminder(for: record, targetBedtime: targetBedtime)
        } else {
            cancelReminder(for: record.id)
        }
        return record
    }

    func abandonActivePlan() {
        guard var record = activePlan() else { return }
        record.status = .abandoned
        record.reminderEnabled = false
        record.updatedAt = Date()
        replace(record)
        cancelReminder(for: record.id)
    }

    private func replace(_ record: SleepRhythmProtectionPlanRecord) {
        var payload = loadPayload()
        if let index = payload.records.firstIndex(where: { $0.id == record.id }) {
            payload.records[index] = record
        } else {
            payload.records.insert(record, at: 0)
        }
        savePayload(trimmed(payload))
    }

    private func trimmed(_ payload: Payload) -> Payload {
        Payload(records: payload.records.sorted { $0.updatedAt > $1.updatedAt }.prefix(24).map { $0 })
    }

    private func loadPayload() -> Payload {
        if let rows = records.records(domain: domain, kind: kind) {
            return Payload(records: rows.compactMap { try? decoder.decode(SleepRhythmProtectionPlanRecord.self, from: $0.payload) })
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
            return LocalDataRecordSeed(domain: domain, recordID: record.id.uuidString, kind: kind, occurredAt: record.startDate, updatedAt: record.updatedAt, payload: data)
        }
        guard seeds.count == payload.records.count else { return }
        _ = records.replace(domain: domain, kind: kind, with: seeds)
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "sleepRhythmProtectionStore.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            return
        }
        let legacyData = defaults.data(forKey: key)
        let legacyRecords: [SleepRhythmProtectionPlanRecord]
        if let legacyData {
            guard let payload = try? decoder.decode(Payload.self, from: legacyData) else { return }
            legacyRecords = payload.records
        } else { legacyRecords = [] }
        let seeds = legacyRecords.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(record) else { return nil }
            return LocalDataRecordSeed(domain: domain, recordID: record.id.uuidString, kind: kind, occurredAt: record.startDate, updatedAt: record.updatedAt, payload: data)
        }
        guard seeds.count == legacyRecords.count, records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: key)
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: date))
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func reminderIdentifier(for recordID: UUID) -> String {
        "sleep.rhythmProtection.\(recordID.uuidString)"
    }

    private func scheduleReminder(for record: SleepRhythmProtectionPlanRecord, targetBedtime: Date?) {
        guard record.status == .active, record.reminderEnabled else { return }
        let calendar = Calendar.current
        let reminderDate = targetBedtime.flatMap { calendar.date(byAdding: .minute, value: -45, to: $0) } ?? defaultReminderDate()
        let components = calendar.dateComponents([.hour, .minute], from: reminderDate)
        LocalNotificationScheduler.scheduleDaily(
            identifier: reminderIdentifier(for: record.id),
            hour: components.hour ?? 22,
            minute: components.minute ?? 15,
            title: record.mode == .travelReset ? String(localized: "🧳 异地睡眠护航中") : String(localized: "🌙 今晚节律护航中"),
            body: record.mode == .travelReset ? String(localized: "跟着本地时间收个尾，明早起床和晒太阳的锚点就稳了。") : String(localized: "屏幕调暗、节奏放慢，给今晚留一段舒服的助眠缓冲带。")
        )
    }

    private func cancelReminder(for recordID: UUID) {
        LocalNotificationScheduler.cancel(identifiers: [reminderIdentifier(for: recordID)])
    }

    private func defaultReminderDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        return calendar.date(bySettingHour: 22, minute: 15, second: 0, of: now) ?? now
    }
}

struct SleepRhythmProtectionEngine {
    struct Input {
        let mode: SleepRhythmTrainingMode
        let plan: SleepRhythmRebuildPlan
        let record: SleepRhythmProtectionPlanRecord?
        let now: Date
        let calendar: Calendar
    }

    func build(input: Input) -> SleepRhythmProtectionSummary {
        let totalDays = max(1, input.plan.estimatedDays)
        let activeRecord = input.record
        let start = activeRecord?.startDate ?? input.calendar.startOfDay(for: input.now)
        let dayIndex = currentDay(start: start, now: input.now, totalDays: totalDays, calendar: input.calendar)
        let todayKey = dayKey(for: input.now, calendar: input.calendar)
        let completedDays = activeRecord?.completedDayKeys ?? []
        let completedSteps = activeRecord?.completedStepIDsByDay[todayKey] ?? []
        let target = adjustedTarget(input.plan.targetBedtime, offset: activeRecord?.targetOffsetMinutes ?? 0, calendar: input.calendar)
        let progress = max(Double(dayIndex) / Double(totalDays) * 0.45, Double(min(completedDays.count, totalDays)) / Double(totalDays))

        return SleepRhythmProtectionSummary(
            mode: input.mode,
            status: activeRecord?.status ?? .active,
            dayIndex: dayIndex,
            totalDays: totalDays,
            progress: min(1.0, max(0.0, progress)),
            targetBedtime: target,
            headline: headline(mode: input.mode, plan: input.plan, record: activeRecord),
            tonightFocus: tonightFocus(mode: input.mode, plan: input.plan, completedSteps: completedSteps),
            rescueText: input.plan.rescueDetail,
            completedStepIDs: completedSteps,
            completedDayKeys: completedDays,
            targetOffsetMinutes: activeRecord?.targetOffsetMinutes ?? 0,
            reminderEnabled: activeRecord?.reminderEnabled ?? false,
            isActivePlan: activeRecord?.status == .active
        )
    }

    private func currentDay(start: Date, now: Date, totalDays: Int, calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: now)
        let diff = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
        return min(max(diff + 1, 1), totalDays)
    }

    private func adjustedTarget(_ date: Date?, offset: Int, calendar: Calendar) -> Date? {
        guard let date else { return nil }
        return calendar.date(byAdding: .minute, value: offset, to: date)
    }

    private func headline(
        mode: SleepRhythmTrainingMode,
        plan: SleepRhythmRebuildPlan,
        record: SleepRhythmProtectionPlanRecord?
    ) -> String {
        if record == nil {
            return mode == .travelReset ? "可启动 3 天出差重建" : "可启动今晚节律保护"
        }
        if mode == .travelReset {
            return String(localized: "出差节律保护进行中")
        }
        if mode == .lateNightRecovery {
            return "晚睡纠偏进行中"
        }
        return plan.headline
    }

    private func tonightFocus(
        mode: SleepRhythmTrainingMode,
        plan: SleepRhythmRebuildPlan,
        completedSteps: Set<String>
    ) -> String {
        if let next = plan.routineSteps.first(where: { !completedSteps.contains($0.id) }) {
            return String(localized: "今晚先做「\(next.title)」")
        }
        if mode == .travelReset {
            return String(localized: "今晚流程已完成，明早继续守住本地起床和日照。")
        }
        return String(localized: "今晚锚点已完成，后面只需要保持低刺激。")
    }

    private func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: date))
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
