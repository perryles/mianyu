/// CareTaskModels 定义 CareKit 风格的统一照护任务数据模型。
/// 覆盖服药、康复训练、健康习惯、症状日记四大模块的统一语义。
///
/// 设计依据：
/// - 复用 MedicationStore 已验证的版本化模式（logicalTaskID + revision + effectiveFrom/Until）
/// - CareKit 概念映射：Task → CareTask, Schedule → CareSchedule, Event → CareTaskEvent, Outcome → CareOutcome
/// - 详见 CAREKIT_CARE_PLAN_INTEGRATION.md

import Foundation

// MARK: - 任务分类

nonisolated enum CareTaskCategory: String, Codable, CaseIterable, Sendable, Hashable {
    case medication
    case rehabilitation
    case habit
    case symptom

    var title: String {
        switch self {
        case .medication:
            return String(localized: "服药打卡")
        case .rehabilitation:
            return String(localized: "康复训练")
        case .habit:
            return String(localized: "健康习惯")
        case .symptom:
            return String(localized: "症状日记")
        }
    }

    var shortTitle: String {
        switch self {
        case .medication:
            return String(localized: "服药")
        case .rehabilitation:
            return String(localized: "康复")
        case .habit:
            return String(localized: "习惯")
        case .symptom:
            return String(localized: "日记")
        }
    }

    var symbol: String {
        switch self {
        case .medication:
            return "pills.fill"
        case .rehabilitation:
            return "figure.cooldown"
        case .habit:
            return "leaf.fill"
        case .symptom:
            return "stethoscope"
        }
    }

    /// 对应 CareKit 的_impact 标记，用于 UI 着色
    var accentColorName: String {
        switch self {
        case .medication:
            return "orange"
        case .rehabilitation:
            return "blue"
        case .habit:
            return "green"
        case .symptom:
            return "purple"
        }
    }
}

// MARK: - 计划

nonisolated enum CareScheduleFrequency: String, Codable, Sendable, Hashable, CaseIterable {
    case daily          // 每天
    case weekly         // 指定星期
    case customInterval // 自定义间隔天数

    var title: String {
        switch self {
        case .daily:
            return String(localized: "每天")
        case .weekly:
            return String(localized: "指定星期")
        case .customInterval:
            return String(localized: "自定义间隔")
        }
    }
}

/// CareKit OCKSchedule 的简化映射，支持每日多时段、指定星期和自定义间隔。
nonisolated struct CareSchedule: Codable, Hashable, Sendable {
    struct TimeSlot: Codable, Hashable, Sendable {
        var hour: Int
        var minute: Int
        var durationMinutes: Int

        public init(hour: Int, minute: Int, durationMinutes: Int = 0) {
            self.hour = max(0, min(23, hour))
            self.minute = max(0, min(59, minute))
            self.durationMinutes = max(0, durationMinutes)
        }

        var formattedTime: String {
            String(format: "%02d:%02d", hour, minute)
        }
    }

    var isEnabled: Bool
    var slots: [TimeSlot]
    /// 1...7（周日=1），空集合表示每天都执行
    var weekdays: Set<Int>
    var frequency: CareScheduleFrequency
    /// 当 frequency == .customInterval 时使用
    var customIntervalDays: Int
    var startDate: Date
    var endDate: Date?

    init(
        isEnabled: Bool = true,
        slots: [TimeSlot] = [.init(hour: 8, minute: 0)],
        weekdays: Set<Int> = [],
        frequency: CareScheduleFrequency = .daily,
        customIntervalDays: Int = 1,
        startDate: Date = Date(),
        endDate: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.slots = slots.isEmpty ? [.init(hour: 8, minute: 0)] : slots
        self.weekdays = weekdays
        self.frequency = frequency
        self.customIntervalDays = max(1, customIntervalDays)
        self.startDate = startDate
        self.endDate = endDate
    }

    /// 判断给定日期是否在排程的执行日
    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        guard dayStart >= calendar.startOfDay(for: startDate) else { return false }
        if let endDate {
            guard dayStart <= calendar.startOfDay(for: endDate) else { return false }
        }

        switch frequency {
        case .daily:
            if weekdays.isEmpty { return true }
            let weekday = calendar.component(.weekday, from: date)
            return weekdays.contains(weekday)
        case .weekly:
            let weekday = calendar.component(.weekday, from: date)
            return weekdays.isEmpty || weekdays.contains(weekday)
        case .customInterval:
            let startDay = calendar.startOfDay(for: startDate)
            let dayDiff = calendar.dateComponents([.day], from: startDay, to: dayStart).day ?? 0
            return dayDiff >= 0 && dayDiff % max(1, customIntervalDays) == 0
        }
    }

    /// 生成给定日期当天的所有调度时间点
    func scheduledTimes(on date: Date, calendar: Calendar = .current) -> [Date] {
        guard isScheduled(on: date, calendar: calendar) else { return [] }
        let dayStart = calendar.startOfDay(for: date)
        return slots.compactMap { slot in
            calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: dayStart)
        }
    }

    /// 每日任务总次数
    var dailyEventCount: Int { slots.count }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, slots, weekdays, frequency, customIntervalDays, startDate, endDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        slots = try container.decodeIfPresent([TimeSlot].self, forKey: .slots) ?? [.init(hour: 8, minute: 0)]
        weekdays = try container.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? []
        frequency = try container.decodeIfPresent(CareScheduleFrequency.self, forKey: .frequency) ?? .daily
        customIntervalDays = max(1, try container.decodeIfPresent(Int.self, forKey: .customIntervalDays) ?? 1)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate) ?? Date(timeIntervalSince1970: 0)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
    }
}

// MARK: - CareTask（版本化任务）

/// 一条不可变的照护任务修订。`logicalTaskID` 跨修订稳定，`id` 只标识当前版本。
nonisolated struct CareTask: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var category: CareTaskCategory
    var title: String
    var subtitle: String?
    var icon: String
    var schedule: CareSchedule
    /// 目标值（如晒太阳 20 分钟、呼吸训练 5 分钟）
    var targetValue: Double?
    var unit: String?
    var instructions: String?
    /// 关联模块键（如 "sunlight" 打通光照模块）
    var linkedModule: String?
    /// 版本化字段
    var logicalTaskID: String
    var revision: Int
    var effectiveFrom: Date
    var effectiveUntil: Date?
    /// 外部导入来源标识
    var sourceImportID: String?

    init(
        id: String = UUID().uuidString,
        category: CareTaskCategory,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        schedule: CareSchedule,
        targetValue: Double? = nil,
        unit: String? = nil,
        instructions: String? = nil,
        linkedModule: String? = nil,
        logicalTaskID: String? = nil,
        revision: Int = 1,
        effectiveFrom: Date = Date(),
        effectiveUntil: Date? = nil,
        sourceImportID: String? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.icon = icon ?? category.symbol
        self.schedule = schedule
        self.targetValue = targetValue
        self.unit = unit
        self.instructions = instructions
        self.linkedModule = linkedModule
        self.logicalTaskID = logicalTaskID ?? id
        self.revision = max(1, revision)
        self.effectiveFrom = effectiveFrom
        self.effectiveUntil = effectiveUntil
        self.sourceImportID = sourceImportID
    }

    func isEffective(at date: Date) -> Bool {
        guard effectiveFrom <= date else { return false }
        guard let effectiveUntil else { return true }
        return date < effectiveUntil
    }

    private enum CodingKeys: String, CodingKey {
        case id, category, title, subtitle, icon, schedule
        case targetValue, unit, instructions, linkedModule
        case logicalTaskID, revision, effectiveFrom, effectiveUntil, sourceImportID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(CareTaskCategory.self, forKey: .category)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? category.symbol
        schedule = try container.decode(CareSchedule.self, forKey: .schedule)
        targetValue = try container.decodeIfPresent(Double.self, forKey: .targetValue)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
        linkedModule = try container.decodeIfPresent(String.self, forKey: .linkedModule)
        logicalTaskID = try container.decodeIfPresent(String.self, forKey: .logicalTaskID) ?? id
        revision = max(1, try container.decodeIfPresent(Int.self, forKey: .revision) ?? 1)
        effectiveFrom = try container.decodeIfPresent(Date.self, forKey: .effectiveFrom) ?? Date(timeIntervalSince1970: 0)
        effectiveUntil = try container.decodeIfPresent(Date.self, forKey: .effectiveUntil)
        sourceImportID = try container.decodeIfPresent(String.self, forKey: .sourceImportID)
    }
}

// MARK: - CareTask 事件

nonisolated enum CareTaskEventStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case scheduled
    case completed
    case overdue
    case skipped

    var title: String {
        switch self {
        case .scheduled:
            return String(localized: "待完成")
        case .completed:
            return String(localized: "已完成")
        case .overdue:
            return String(localized: "已逾期")
        case .skipped:
            return String(localized: "已跳过")
        }
    }

    var symbol: String {
        switch self {
        case .scheduled:
            return "clock"
        case .completed:
            return "checkmark.circle.fill"
        case .overdue:
            return "exclamationmark.triangle.fill"
        case .skipped:
            return "forward.fill"
        }
    }
}

/// 类似 CareKit Event：由任务修订和日期派生，结果仍由 `CareOutcome` 保存。
nonisolated struct CareTaskEvent: Identifiable, Hashable, Sendable {
    let id: String
    let taskID: String
    let logicalTaskID: String
    let taskRevision: Int
    let category: CareTaskCategory
    let title: String
    let icon: String
    let slotIndex: Int
    let scheduledAt: Date
    let durationMinutes: Int
    let targetValue: Double?
    let unit: String?
    let instructions: String?
    let linkedModule: String?
    let status: CareTaskEventStatus
    let outcome: CareOutcome?
}

// MARK: - 照护结果

nonisolated struct CareOutcome: Codable, Hashable, Sendable, Identifiable {
    struct Value: Codable, Hashable, Sendable {
        enum Kind: String, Codable, Sendable, Hashable {
            case numeric
            case text
            case rating
            case symptom
            case reaction
        }

        var kind: Kind
        var label: String?
        var numericValue: Double?
        var textValue: String?
        var ratingValue: Int?

        init(kind: Kind, label: String? = nil, numericValue: Double? = nil, textValue: String? = nil, ratingValue: Int? = nil) {
            self.kind = kind
            self.label = label
            self.numericValue = numericValue
            self.textValue = textValue
            self.ratingValue = ratingValue
        }
    }

    let id: String
    var logicalTaskID: String?
    var taskID: String?
    var taskRevision: Int?
    var category: CareTaskCategory
    var completedAt: Date
    /// 对应哪个计划日
    var scheduledDate: Date?
    var values: [Value]
    var note: String?
    /// 跨模块代理引用
    var linkedMedicationEntryID: String?
    var linkedSelfObservationID: String?
    var linkedHabitCheckinKey: String?

    init(
        id: String = UUID().uuidString,
        logicalTaskID: String? = nil,
        taskID: String? = nil,
        taskRevision: Int? = nil,
        category: CareTaskCategory,
        completedAt: Date = Date(),
        scheduledDate: Date? = nil,
        values: [Value] = [],
        note: String? = nil,
        linkedMedicationEntryID: String? = nil,
        linkedSelfObservationID: String? = nil,
        linkedHabitCheckinKey: String? = nil
    ) {
        self.id = id
        self.logicalTaskID = logicalTaskID
        self.taskID = taskID
        self.taskRevision = taskRevision
        self.category = category
        self.completedAt = completedAt
        self.scheduledDate = scheduledDate
        self.values = values
        self.note = note
        self.linkedMedicationEntryID = linkedMedicationEntryID
        self.linkedSelfObservationID = linkedSelfObservationID
        self.linkedHabitCheckinKey = linkedHabitCheckinKey
    }

    private enum CodingKeys: String, CodingKey {
        case id, logicalTaskID, taskID, taskRevision, category
        case completedAt, scheduledDate, values, note
        case linkedMedicationEntryID, linkedSelfObservationID, linkedHabitCheckinKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        logicalTaskID = try container.decodeIfPresent(String.self, forKey: .logicalTaskID)
        taskID = try container.decodeIfPresent(String.self, forKey: .taskID)
        taskRevision = try container.decodeIfPresent(Int.self, forKey: .taskRevision)
        category = try container.decode(CareTaskCategory.self, forKey: .category)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        scheduledDate = try container.decodeIfPresent(Date.self, forKey: .scheduledDate)
        values = try container.decodeIfPresent([Value].self, forKey: .values) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note)
        linkedMedicationEntryID = try container.decodeIfPresent(String.self, forKey: .linkedMedicationEntryID)
        linkedSelfObservationID = try container.decodeIfPresent(String.self, forKey: .linkedSelfObservationID)
        linkedHabitCheckinKey = try container.decodeIfPresent(String.self, forKey: .linkedHabitCheckinKey)
    }
}

// MARK: - 依从性

nonisolated struct CareAdherenceSummary: Hashable, Sendable {
    let category: CareTaskCategory?
    let totalEvents: Int
    let completedEvents: Int
    let skippedEvents: Int
    let overdueEvents: Int
    let adherenceRate: Double       // 0...1

    var formattedAdherence: String {
        completedEvents > 0 && totalEvents > 0
            ? String(format: "%.0f%%", adherenceRate * 100)
            : "--"
    }
}

/// 单周完成率数据
nonisolated struct CareWeeklyAdherence: Identifiable, Hashable, Sendable {
    let id: String
    let weekStart: Date
    let weekLabel: String
    let category: CareTaskCategory?
    let totalEvents: Int
    let completedEvents: Int
    let adherenceRate: Double

    var formattedAdherence: String {
        totalEvents > 0
            ? String(format: "%.0f%%", adherenceRate * 100)
            : "--"
    }
}

// MARK: - Journal Timeline Item (统一日志卡片)

/// 症状日记与服药打卡复用的统一日志时间线项
nonisolated enum JournalTimelineItem: Identifiable, Hashable, Sendable {
    case careTaskEvent(CareTaskEvent)
    case careOutcome(CareOutcome)
    case symptomRecord(SelfObservationRecord)
    case medicationEntry(MedicationEntry)

    var id: String {
        switch self {
        case .careTaskEvent(let event):
            return "event-\(event.id)"
        case .careOutcome(let outcome):
            return "outcome-\(outcome.id)"
        case .symptomRecord(let record):
            return "symptom-\(record.id)"
        case .medicationEntry(let entry):
            return "med-\(entry.id)"
        }
    }

    var timestamp: Date {
        switch self {
        case .careTaskEvent(let event):
            return event.scheduledAt
        case .careOutcome(let outcome):
            return outcome.completedAt
        case .symptomRecord(let record):
            return record.recordedAt
        case .medicationEntry(let entry):
            return entry.takenAt
        }
    }

    var category: CareTaskCategory {
        switch self {
        case .careTaskEvent(let event):
            return event.category
        case .careOutcome(let outcome):
            return outcome.category
        case .symptomRecord:
            return .symptom
        case .medicationEntry:
            return .medication
        }
    }
}
