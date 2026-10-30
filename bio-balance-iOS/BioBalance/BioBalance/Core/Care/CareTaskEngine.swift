/// CareTaskEngine 是统一照护任务引擎的核心。
///
/// 职责：
/// - 管理 CareTask 的版本化 CRUD（rehabilitation / habit / symptom 类别）
/// - 按日派生 CareTaskEvent
/// - 记录 CareOutcome
/// - 对 medication 类别采用只读代理（桥接 MedicationStore）
/// - 计算 adherence 完成率
///
/// 设计依据详见 CAREKIT_CARE_PLAN_INTEGRATION.md

import Foundation
import SwiftData

final class CareTaskEngine {
    static let shared = CareTaskEngine()

    static let domain = "care-task"
    private let taskKind = "task"
    private let outcomeKind = "outcome"
    private let maxOutcomes = 500
    private let maxTaskVersions = 200

    private let records: SwiftDataRecordStore
    private let calendar = Calendar.current
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(container: ModelContainer = MianyuModelContainer.shared) {
        self.records = SwiftDataRecordStore(container: container)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - 任务增删改查

    func saveTask(_ task: CareTask) {
        var payload = loadPayload()
        var taskToSchedule = task
        var reminderIDsToCancel: [String] = []

        if let index = payload.tasks.firstIndex(where: { $0.id == task.id }) {
            let previous = payload.tasks[index]
            if hasSameTaskDefinition(previous, task) {
                taskToSchedule = previous
            } else {
                let effectiveFrom = Date()
                payload.tasks[index].effectiveUntil = effectiveFrom
                reminderIDsToCancel.append(reminderIdentifier(for: previous.id))

                let nextRevision = payload.tasks
                    .filter { $0.logicalTaskID == previous.logicalTaskID }
                    .map(\.revision)
                    .max()
                    .map { $0 + 1 } ?? 2

                taskToSchedule = CareTask(
                    id: UUID().uuidString,
                    category: task.category,
                    title: task.title,
                    subtitle: task.subtitle,
                    icon: task.icon,
                    schedule: task.schedule,
                    targetValue: task.targetValue,
                    unit: task.unit,
                    instructions: task.instructions,
                    linkedModule: task.linkedModule,
                    logicalTaskID: previous.logicalTaskID,
                    revision: nextRevision,
                    effectiveFrom: effectiveFrom,
                    sourceImportID: task.sourceImportID ?? previous.sourceImportID
                )
                payload.tasks.append(taskToSchedule)
            }
        } else {
            taskToSchedule.logicalTaskID = task.logicalTaskID.isEmpty ? task.id : task.logicalTaskID
            taskToSchedule.revision = max(1, task.revision)
            taskToSchedule.effectiveUntil = nil
            payload.tasks.append(taskToSchedule)
        }

        // 保留上限：按 logicalTaskID 分组，每组保留最新 N 个修订
        payload.tasks = pruneTaskVersions(payload.tasks)

        persist(payload)
        LocalNotificationScheduler.cancel(identifiers: reminderIDsToCancel)
        scheduleReminder(for: taskToSchedule)
        NotificationCenter.default.post(name: .careTasksDidChange, object: self)
    }

    func removeTask(id: String) {
        var payload = loadPayload()
        guard let index = payload.tasks.firstIndex(where: { $0.id == id }) else { return }
        payload.tasks[index].effectiveUntil = Date()
        persist(payload)
        LocalNotificationScheduler.cancel(identifiers: [reminderIdentifier(for: id)])
        NotificationCenter.default.post(name: .careTasksDidChange, object: self)
    }

    func allTasks(referenceDate: Date = Date()) -> [CareTask] {
        let engineTasks = loadPayload()
            .tasks
            .filter { $0.isEffective(at: referenceDate) }
            .reduce(into: [String: CareTask]()) { result, task in
                if let current = result[task.logicalTaskID], current.revision >= task.revision {
                    return
                }
                result[task.logicalTaskID] = task
            }
            .values
            .sorted { firstTask, secondTask in
                let firstTime = firstTask.schedule.slots.first?.formattedTime ?? ""
                let secondTime = secondTask.schedule.slots.first?.formattedTime ?? ""
                return firstTime < secondTime
            }

        // 合并服药任务（从 MedicationStore 代理）
        let medicationTasks = CareMedicationBridge.shared.bridgeTasks(referenceDate: referenceDate)
        return engineTasks + medicationTasks
    }

    func tasks(category: CareTaskCategory, referenceDate: Date = Date()) -> [CareTask] {
        allTasks(referenceDate: referenceDate).filter { $0.category == category }
    }

    func allTaskVersions(logicalTaskID: String? = nil) -> [CareTask] {
        loadPayload()
            .tasks
            .filter { logicalTaskID == nil || $0.logicalTaskID == logicalTaskID }
            .sorted {
                if $0.logicalTaskID == $1.logicalTaskID {
                    return $0.revision > $1.revision
                }
                return $0.effectiveFrom > $1.effectiveFrom
            }
    }

    // MARK: - 事件

    /// 按指定日期即时派生任务事件（不持久化），合并引擎自管任务和代理模块。
    func events(on date: Date = Date(), referenceDate: Date = Date()) -> [CareTaskEvent] {
        let dayStart = calendar.startOfDay(for: date)
        let engineOutcomes = loadPayload().outcomes

        var events: [CareTaskEvent] = []

        // 引擎自管任务
        let activeTasks = loadPayload()
            .tasks
            .filter { $0.isEffective(at: dayStart) && $0.category != .medication }

        for task in activeTasks {
            guard task.schedule.isScheduled(on: date, calendar: calendar) else { continue }
            let times = task.schedule.scheduledTimes(on: date, calendar: calendar)
            for (slotIndex, scheduledAt) in times.enumerated() {
                let slot = task.schedule.slots[min(slotIndex, task.schedule.slots.count - 1)]

                // 晒太阳类任务：自动读取光照模块
                if task.linkedModule == "sunlight" {
                    let sunlightMinutes = AppGroupManager.shared.getSunlightMinutesToday() ?? 0
                    let target = task.targetValue ?? 20
                    if Double(sunlightMinutes) >= target {
                        let outcome = CareOutcome(
                            logicalTaskID: task.logicalTaskID,
                            taskID: task.id,
                            taskRevision: task.revision,
                            category: .habit,
                            completedAt: Date(),
                            scheduledDate: dayStart,
                            values: [.init(kind: .numeric, label: "日照", numericValue: Double(sunlightMinutes))],
                            note: nil,
                            linkedHabitCheckinKey: "sunlight"
                        )
                        events.append(task.event(id: task.id, logicalID: task.logicalTaskID, revision: task.revision, category: task.category, title: task.title, icon: task.icon, slotIndex: slotIndex, scheduledAt: scheduledAt, durationMinutes: slot.durationMinutes, targetValue: task.targetValue, unit: task.unit, instructions: task.instructions, linkedModule: task.linkedModule, status: .completed, outcome: outcome))
                        continue
                    }
                }

                let matchedOutcome = engineOutcomes.first { outcome in
                    guard outcome.taskID == task.id || (outcome.logicalTaskID == task.logicalTaskID && outcome.taskRevision == task.revision) else { return false }
                    guard let scheduledDate = outcome.scheduledDate else { return false }
                    return calendar.isDate(scheduledDate, inSameDayAs: dayStart)
                }

                let status: CareTaskEventStatus
                if matchedOutcome != nil {
                    status = .completed
                } else if scheduledAt < referenceDate {
                    status = .overdue
                } else {
                    status = .scheduled
                }

                events.append(task.event(
                    id: task.id,
                    logicalID: task.logicalTaskID,
                    revision: task.revision,
                    category: task.category,
                    title: task.title,
                    icon: task.icon,
                    slotIndex: slotIndex,
                    scheduledAt: scheduledAt,
                    durationMinutes: slot.durationMinutes,
                    targetValue: task.targetValue,
                    unit: task.unit,
                    instructions: task.instructions,
                    linkedModule: task.linkedModule,
                    status: status,
                    outcome: matchedOutcome
                ))
            }
        }

        // 合并服药事件（代理 MedicationStore）
        events.append(contentsOf: CareMedicationBridge.shared.bridgeEvents(on: date, referenceDate: referenceDate))

        // 合并康复挑战事件（代理 RecoveryChallengeStore）
        events.append(contentsOf: CareChallengeBridge.shared.bridgeEvents(on: date))

        return events.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func events(category: CareTaskCategory, on date: Date = Date(), referenceDate: Date = Date()) -> [CareTaskEvent] {
        events(on: date, referenceDate: referenceDate).filter { $0.category == category }
    }

    /// 今日概览：按类别分组
    func todaySummary(referenceDate: Date = Date()) -> [CareTodaySection] {
        let allEvents = events(on: referenceDate, referenceDate: referenceDate)
        return CareTaskCategory.allCases.compactMap { category in
            let categoryEvents = allEvents.filter { $0.category == category }
            guard !categoryEvents.isEmpty else { return nil }
            return CareTodaySection(category: category, events: categoryEvents)
        }
    }

    // MARK: - 结果

    func recordOutcome(_ outcome: CareOutcome) {
        var payload = loadPayload()
        if let index = payload.outcomes.firstIndex(where: { $0.id == outcome.id }) {
            payload.outcomes[index] = outcome
        } else {
            payload.outcomes.append(outcome)
        }
        payload.outcomes.sort { $0.completedAt > $1.completedAt }
        payload.outcomes = Array(payload.outcomes.prefix(maxOutcomes))
        persist(payload)
        NotificationCenter.default.post(name: .careTasksDidChange, object: self)
    }

    func removeOutcome(id: String) {
        var payload = loadPayload()
        payload.outcomes.removeAll { $0.id == id }
        persist(payload)
        NotificationCenter.default.post(name: .careTasksDidChange, object: self)
    }

    func outcomes(for logicalTaskID: String) -> [CareOutcome] {
        loadPayload().outcomes
            .filter { $0.logicalTaskID == logicalTaskID }
            .sorted { $0.completedAt > $1.completedAt }
    }

    func outcomes(on date: Date) -> [CareOutcome] {
        let dayStart = calendar.startOfDay(for: date)
        return loadPayload().outcomes.filter { outcome in
            guard let scheduledDate = outcome.scheduledDate else {
                return calendar.isDate(outcome.completedAt, inSameDayAs: dayStart)
            }
            return calendar.isDate(scheduledDate, inSameDayAs: dayStart)
        }
    }

    // MARK: - 依从性

    func adherenceSummary(days: Int = 7, category: CareTaskCategory? = nil, referenceDate: Date = Date()) -> CareAdherenceSummary {
        var total = 0
        var completed = 0
        var skipped = 0
        var overdue = 0

        for dayOffset in 0..<max(1, days) {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: referenceDate) else { continue }
            let dayEvents = events(on: date, referenceDate: referenceDate)
            let filtered = category.map { target in dayEvents.filter { $0.category == target } } ?? dayEvents
            total += filtered.count
            completed += filtered.filter { $0.status == .completed }.count
            skipped += filtered.filter { $0.status == .skipped }.count
            overdue += filtered.filter { $0.status == .overdue }.count
        }

        let rate = total > 0 ? Double(completed) / Double(total) : 0
        return CareAdherenceSummary(category: category, totalEvents: total, completedEvents: completed, skippedEvents: skipped, overdueEvents: overdue, adherenceRate: rate)
    }

    func weeklyAdherence(weeks: Int = 4, category: CareTaskCategory? = nil, referenceDate: Date = Date()) -> [CareWeeklyAdherence] {
        var results: [CareWeeklyAdherence] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"

        for weekOffset in 0..<max(1, weeks) {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: calendar.startOfWeek(for: referenceDate)) else { continue }
            var total = 0
            var completed = 0

            for dayOffset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                if date > referenceDate { continue }
                let dayEvents = events(on: date, referenceDate: referenceDate)
                let filtered = category.map { target in dayEvents.filter { $0.category == target } } ?? dayEvents
                total += filtered.count
                completed += filtered.filter { $0.status == .completed }.count
            }

            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let label = "\(formatter.string(from: weekStart))-\(formatter.string(from: weekEnd))"
            let rate = total > 0 ? Double(completed) / Double(total) : 0
            results.append(CareWeeklyAdherence(
                id: "\(weekStart.timeIntervalSince1970)-\(category?.rawValue ?? "all")",
                weekStart: weekStart,
                weekLabel: label,
                category: category,
                totalEvents: total,
                completedEvents: completed,
                adherenceRate: rate
            ))
        }

        return results.reversed()
    }

    // MARK: - 私有实现

    private struct Payload: Codable {
        var tasks: [CareTask]
        var outcomes: [CareOutcome]

        init(tasks: [CareTask] = [], outcomes: [CareOutcome] = []) {
            self.tasks = tasks
            self.outcomes = outcomes
        }

        private enum CodingKeys: String, CodingKey { case tasks, outcomes }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tasks = try container.decodeIfPresent([CareTask].self, forKey: .tasks) ?? []
            outcomes = try container.decodeIfPresent([CareOutcome].self, forKey: .outcomes) ?? []
        }
    }

    private func loadPayload() -> Payload {
        guard let rows = records.records(domain: Self.domain) else { return Payload() }
        let tasks = rows
            .filter { $0.kind == taskKind }
            .compactMap { try? decoder.decode(CareTask.self, from: $0.payload) }
        let outcomes = rows
            .filter { $0.kind == outcomeKind }
            .compactMap { try? decoder.decode(CareOutcome.self, from: $0.payload) }
        return Payload(tasks: tasks, outcomes: outcomes)
    }

    private func persist(_ payload: Payload) {
        let taskSeeds = payload.tasks.compactMap { task -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(task) else { return nil }
            return LocalDataRecordSeed(
                domain: Self.domain,
                recordID: task.id,
                kind: taskKind,
                occurredAt: task.effectiveFrom,
                updatedAt: task.effectiveUntil ?? task.effectiveFrom,
                payload: data
            )
        }
        let outcomeSeeds = payload.outcomes.compactMap { outcome -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(outcome) else { return nil }
            return LocalDataRecordSeed(
                domain: Self.domain,
                recordID: outcome.id,
                kind: outcomeKind,
                occurredAt: outcome.completedAt,
                updatedAt: outcome.completedAt,
                payload: data
            )
        }
        guard taskSeeds.count == payload.tasks.count,
              outcomeSeeds.count == payload.outcomes.count,
              records.replace(domain: Self.domain, with: taskSeeds + outcomeSeeds) else { return }
    }

    private func pruneTaskVersions(_ tasks: [CareTask]) -> [CareTask] {
        let grouped = Dictionary(grouping: tasks, by: { $0.logicalTaskID })
        return grouped.values.flatMap { group -> [CareTask] in
            let sorted = group.sorted { $0.revision > $1.revision }
            // 保留所有 effectiveUntil == nil（当前版本）+ 最近 maxTaskVersions 个历史版本
            let active = sorted.filter { $0.effectiveUntil == nil }
            let historical = sorted.filter { $0.effectiveUntil != nil }
            return active + Array(historical.prefix(maxTaskVersions))
        }
    }

    private func hasSameTaskDefinition(_ lhs: CareTask, _ rhs: CareTask) -> Bool {
        lhs.category == rhs.category &&
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
        lhs.icon == rhs.icon &&
        lhs.schedule == rhs.schedule &&
        lhs.targetValue == rhs.targetValue &&
        lhs.unit == rhs.unit &&
        lhs.instructions == rhs.instructions &&
        lhs.linkedModule == rhs.linkedModule
    }

    // MARK: - 通知调度

    private func scheduleReminder(for task: CareTask) {
        let identifier = reminderIdentifier(for: task.id)
        LocalNotificationScheduler.cancel(identifiers: [identifier])

        guard task.schedule.isEnabled else { return }

        for slot in task.schedule.slots {
            let slotID = "\(identifier).\(slot.hour).\(slot.minute)"
            LocalNotificationScheduler.cancel(identifiers: [slotID])

            let body: String
            if let target = task.targetValue, let unit = task.unit {
                body = String(localized: "\(task.title) 目标 \(formattedValue(target)) \(unit)，完成后记得打卡。")
            } else {
                body = String(localized: "别忘了完成\(task.title)，打卡记录更安心。")
            }

            LocalNotificationScheduler.scheduleDaily(
                identifier: slotID,
                hour: slot.hour,
                minute: slot.minute,
                title: "🔔 \(task.category.title)提醒",
                body: body
            )
        }
    }

    private func reminderIdentifier(for taskID: String) -> String {
        "caretask.reminder.\(taskID)"
    }

    private func formattedValue(_ value: Double) -> String {
        if floor(value) == value { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }
}

// MARK: - 今日区块

nonisolated struct CareTodaySection: Identifiable, Hashable, Sendable {
    var id: String { category.rawValue }
    let category: CareTaskCategory
    let events: [CareTaskEvent]

    var completedCount: Int { events.filter { $0.status == .completed }.count }
    var totalCount: Int { events.count }
    var hasOverdue: Bool { events.contains { $0.status == .overdue } }
}

// MARK: - CareTask 便捷能力

private extension CareTask {
    func event(
        id: String,
        logicalID: String,
        revision: Int,
        category: CareTaskCategory,
        title: String,
        icon: String,
        slotIndex: Int,
        scheduledAt: Date,
        durationMinutes: Int,
        targetValue: Double?,
        unit: String?,
        instructions: String?,
        linkedModule: String?,
        status: CareTaskEventStatus,
        outcome: CareOutcome?
    ) -> CareTaskEvent {
        CareTaskEvent(
            id: "\(id)|\(slotIndex)|\(Int(Calendar.current.startOfDay(for: scheduledAt).timeIntervalSince1970))",
            taskID: id,
            logicalTaskID: logicalID,
            taskRevision: revision,
            category: category,
            title: title,
            icon: icon,
            slotIndex: slotIndex,
            scheduledAt: scheduledAt,
            durationMinutes: durationMinutes,
            targetValue: targetValue,
            unit: unit,
            instructions: instructions,
            linkedModule: linkedModule,
            status: status,
            outcome: outcome
        )
    }
}

// MARK: - 日历扩展

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}

// MARK: - 通知名称

extension Notification.Name {
    static let careTasksDidChange = Notification.Name("careTasksDidChange")
}
