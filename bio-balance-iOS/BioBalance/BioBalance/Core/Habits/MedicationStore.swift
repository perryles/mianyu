import Foundation
import SwiftData

nonisolated enum MedicationEntryCategory: String, CaseIterable, Codable, Sendable, Hashable {
    case medication
    case supplement

    var title: String {
        switch self {
        case .medication:
            return "用药"
        case .supplement:
            return String(localized: "补剂")
        }
    }

    var shortTitle: String {
        switch self {
        case .medication:
            return "药"
        case .supplement:
            return String(localized: "补")
        }
    }

    var symbol: String {
        switch self {
        case .medication:
            return "pills.fill"
        case .supplement:
            return "leaf.fill"
        }
    }

    var apiType: String {
        switch self {
        case .medication:
            return "medicine"
        case .supplement:
            return "supplement"
        }
    }
}

nonisolated enum MedicationReactionState: String, CaseIterable, Codable, Sendable, Hashable {
    case improved
    case neutral
    case uncomfortable

    var title: String {
        switch self {
        case .improved:
            return String(localized: "更舒服")
        case .neutral:
            return "无明显变化"
        case .uncomfortable:
            return String(localized: "有点不适")
        }
    }

    var shortTitle: String {
        switch self {
        case .improved:
            return String(localized: "舒服")
        case .neutral:
            return String(localized: "平稳")
        case .uncomfortable:
            return String(localized: "不适")
        }
    }

    var symbol: String {
        switch self {
        case .improved:
            return "face.smiling.fill"
        case .neutral:
            return "circle.lefthalf.filled"
        case .uncomfortable:
            return "exclamationmark.circle.fill"
        }
    }
}

nonisolated struct MedicationDraft: Hashable, Sendable, Identifiable {
    let id: String
    var isExistingRecord: Bool
    var category: MedicationEntryCategory
    var name: String?
    var amount: Double?
    var unit: String?
    var purpose: String?
    var note: String?
    var reactionState: MedicationReactionState?
    var reactionNote: String?
    var followUpMinutes: Int?
    var takenAt: Date
    var planID: String?
    var logicalPlanID: String?
    var planRevision: Int?
    var backendRecordedAt: Date?
    var healthAppRecordedAt: Date?
    var healthAppStatusNote: String?

    init(
        id: String = UUID().uuidString,
        isExistingRecord: Bool = false,
        category: MedicationEntryCategory = .medication,
        name: String? = nil,
        amount: Double? = nil,
        unit: String? = nil,
        purpose: String? = nil,
        note: String? = nil,
        reactionState: MedicationReactionState? = nil,
        reactionNote: String? = nil,
        followUpMinutes: Int? = nil,
        takenAt: Date = Date(),
        planID: String? = nil,
        logicalPlanID: String? = nil,
        planRevision: Int? = nil,
        backendRecordedAt: Date? = nil,
        healthAppRecordedAt: Date? = nil,
        healthAppStatusNote: String? = nil
    ) {
        self.id = id
        self.isExistingRecord = isExistingRecord
        self.category = category
        self.name = name
        self.amount = amount
        self.unit = unit
        self.purpose = purpose
        self.note = note
        self.reactionState = reactionState
        self.reactionNote = reactionNote
        self.followUpMinutes = followUpMinutes
        self.takenAt = takenAt
        self.planID = planID
        self.logicalPlanID = logicalPlanID
        self.planRevision = planRevision
        self.backendRecordedAt = backendRecordedAt
        self.healthAppRecordedAt = healthAppRecordedAt
        self.healthAppStatusNote = healthAppStatusNote
    }
}

nonisolated struct MedicationPlanDraft: Hashable, Sendable, Identifiable {
    let id: String
    var isExistingPlan: Bool
    var category: MedicationEntryCategory
    var name: String
    var amount: Double?
    var unit: String
    var purpose: String
    var note: String
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int

    init(
        id: String = UUID().uuidString,
        isExistingPlan: Bool = false,
        category: MedicationEntryCategory = .medication,
        name: String = "",
        amount: Double? = nil,
        unit: String = "mg",
        purpose: String = "",
        note: String = "",
        reminderEnabled: Bool = true,
        reminderHour: Int = 8,
        reminderMinute: Int = 0
    ) {
        self.id = id
        self.isExistingPlan = isExistingPlan
        self.category = category
        self.name = name
        self.amount = amount
        self.unit = unit
        self.purpose = purpose
        self.note = note
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }
}

nonisolated enum MedicationTimeBucket: String, CaseIterable, Sendable, Hashable {
    case morning
    case noon
    case evening
    case bedtime

    var title: String {
        switch self {
        case .morning:
            return String(localized: "早晨")
        case .noon:
            return String(localized: "中午")
        case .evening:
            return String(localized: "傍晚")
        case .bedtime:
            return String(localized: "夜间")
        }
    }

    var symbol: String {
        switch self {
        case .morning:
            return "sunrise.fill"
        case .noon:
            return "sun.max.fill"
        case .evening:
            return "sunset.fill"
        case .bedtime:
            return "moon.stars.fill"
        }
    }

    static func resolve(for date: Date, calendar: Calendar = .current) -> MedicationTimeBucket {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11:
            return .morning
        case 11..<16:
            return .noon
        case 16..<21:
            return .evening
        default:
            return .bedtime
        }
    }
}

nonisolated struct MedicationReminderConfiguration: Codable, Hashable, Sendable {
    var isEnabled: Bool
    var hour: Int
    var minute: Int
}

/// 一条不可变的计划修订。`logicalPlanID` 跨修订稳定，`id` 只标识当前版本。
nonisolated struct MedicationPlan: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var category: MedicationEntryCategory
    var name: String
    var amount: Double?
    var unit: String
    var purpose: String?
    var note: String?
    var reminder: MedicationReminderConfiguration
    var logicalPlanID: String
    var revision: Int
    var effectiveFrom: Date
    var effectiveUntil: Date?

    init(
        id: String,
        category: MedicationEntryCategory,
        name: String,
        amount: Double?,
        unit: String,
        purpose: String?,
        note: String?,
        reminder: MedicationReminderConfiguration,
        logicalPlanID: String? = nil,
        revision: Int = 1,
        effectiveFrom: Date = Date(),
        effectiveUntil: Date? = nil
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.amount = amount
        self.unit = unit
        self.purpose = purpose
        self.note = note
        self.reminder = reminder
        self.logicalPlanID = logicalPlanID ?? id
        self.revision = max(1, revision)
        self.effectiveFrom = effectiveFrom
        self.effectiveUntil = effectiveUntil
    }

    func isEffective(at date: Date) -> Bool {
        guard effectiveFrom <= date else { return false }
        guard let effectiveUntil else { return true }
        return date < effectiveUntil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case category
        case name
        case amount
        case unit
        case purpose
        case note
        case reminder
        case logicalPlanID
        case revision
        case effectiveFrom
        case effectiveUntil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(MedicationEntryCategory.self, forKey: .category)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decodeIfPresent(Double.self, forKey: .amount)
        unit = try container.decode(String.self, forKey: .unit)
        purpose = try container.decodeIfPresent(String.self, forKey: .purpose)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        reminder = try container.decode(MedicationReminderConfiguration.self, forKey: .reminder)
        logicalPlanID = try container.decodeIfPresent(String.self, forKey: .logicalPlanID) ?? id
        revision = max(1, try container.decodeIfPresent(Int.self, forKey: .revision) ?? 1)
        // 旧版本没有生效时间；使用 Unix 纪元可让历史记录继续命中该计划。
        effectiveFrom = try container.decodeIfPresent(Date.self, forKey: .effectiveFrom) ?? Date(timeIntervalSince1970: 0)
        effectiveUntil = try container.decodeIfPresent(Date.self, forKey: .effectiveUntil)
    }
}

nonisolated struct MedicationEntry: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var category: MedicationEntryCategory
    var name: String
    var amount: Double
    var unit: String
    var purpose: String?
    var note: String?
    var reactionState: MedicationReactionState?
    var reactionNote: String?
    var followUpMinutes: Int?
    var takenAt: Date
    var planID: String?
    var logicalPlanID: String?
    var planRevision: Int?
    var backendRecordedAt: Date?
    var healthAppRecordedAt: Date?
    var healthAppStatusNote: String?

    init(
        id: String,
        category: MedicationEntryCategory = .medication,
        name: String,
        amount: Double,
        unit: String,
        purpose: String? = nil,
        note: String? = nil,
        reactionState: MedicationReactionState? = nil,
        reactionNote: String? = nil,
        followUpMinutes: Int? = nil,
        takenAt: Date,
        planID: String? = nil,
        logicalPlanID: String? = nil,
        planRevision: Int? = nil,
        backendRecordedAt: Date? = nil,
        healthAppRecordedAt: Date? = nil,
        healthAppStatusNote: String? = nil
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.amount = amount
        self.unit = unit
        self.purpose = purpose
        self.note = note
        self.reactionState = reactionState
        self.reactionNote = reactionNote
        self.followUpMinutes = followUpMinutes
        self.takenAt = takenAt
        self.planID = planID
        self.logicalPlanID = logicalPlanID
        self.planRevision = planRevision
        self.backendRecordedAt = backendRecordedAt
        self.healthAppRecordedAt = healthAppRecordedAt
        self.healthAppStatusNote = healthAppStatusNote
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case category
        case name
        case amount
        case unit
        case purpose
        case note
        case reactionState
        case reactionNote
        case followUpMinutes
        case takenAt
        case planID
        case logicalPlanID
        case planRevision
        case backendRecordedAt
        case healthAppRecordedAt
        case healthAppStatusNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decodeIfPresent(MedicationEntryCategory.self, forKey: .category) ?? .medication
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Double.self, forKey: .amount)
        unit = try container.decode(String.self, forKey: .unit)
        purpose = try container.decodeIfPresent(String.self, forKey: .purpose)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        reactionState = try container.decodeIfPresent(MedicationReactionState.self, forKey: .reactionState)
        reactionNote = try container.decodeIfPresent(String.self, forKey: .reactionNote)
        followUpMinutes = try container.decodeIfPresent(Int.self, forKey: .followUpMinutes)
        takenAt = try container.decode(Date.self, forKey: .takenAt)
        planID = try container.decodeIfPresent(String.self, forKey: .planID)
        logicalPlanID = try container.decodeIfPresent(String.self, forKey: .logicalPlanID)
        planRevision = try container.decodeIfPresent(Int.self, forKey: .planRevision)
        backendRecordedAt = try container.decodeIfPresent(Date.self, forKey: .backendRecordedAt)
        healthAppRecordedAt = try container.decodeIfPresent(Date.self, forKey: .healthAppRecordedAt)
        healthAppStatusNote = try container.decodeIfPresent(String.self, forKey: .healthAppStatusNote)
    }
}

nonisolated enum MedicationTaskEventStatus: String, Codable, Hashable, Sendable {
    case scheduled
    case completed
    case overdue

    var title: String {
        switch self {
        case .scheduled:
            return String(localized: "待记录")
        case .completed:
            return String(localized: "已记录")
        case .overdue:
            return String(localized: "待补记")
        }
    }

    var symbol: String {
        switch self {
        case .scheduled:
            return "clock"
        case .completed:
            return "checkmark.circle.fill"
        case .overdue:
            return "exclamationmark.circle.fill"
        }
    }
}

/// 类似 CareKit Event：由计划修订和日期派生，结果仍由 `MedicationEntry` 保存。
nonisolated struct MedicationTaskEvent: Identifiable, Hashable, Sendable {
    let id: String
    let planID: String
    let logicalPlanID: String
    let planRevision: Int
    let scheduledAt: Date
    let status: MedicationTaskEventStatus
    let outcome: MedicationEntry?
}

nonisolated struct MedicationNameSummary: Identifiable, Hashable, Sendable {
    var id: String { normalizedKey }
    let normalizedKey: String
    let category: MedicationEntryCategory
    let name: String
    let count: Int
    let lastTakenAt: Date
    let suggestedAmount: Double
    let suggestedUnit: String
    let suggestedPurpose: String?
    let suggestedNote: String?
}

nonisolated struct MedicationUsageSummary: Hashable, Sendable {
    let totalEntries: Int
    let activeDays: Int
    let uniqueMedicationCount: Int
    let currentStreakDays: Int
    let topMedication: MedicationNameSummary?
    let busiestBucket: MedicationTimeBucket?
}

nonisolated struct MedicationReactionSummary: Hashable, Sendable {
    let trackedEntries: Int
    let improvedCount: Int
    let neutralCount: Int
    let uncomfortableCount: Int
    let lastTrackedEntry: MedicationEntry?
}

nonisolated struct MedicationPendingReactionSummary: Hashable, Sendable {
    let pendingEntries: [MedicationEntry]
    let overdueCount: Int
}

nonisolated struct MedicationLocalInsight: Hashable, Sendable {
    let headline: String
    let detail: String
    let tags: [String]
}

final class MedicationStore {
    static let shared = MedicationStore()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let calendar = Calendar.current
    private let key = "medicationStore.v2"
    private let legacyKey = "medicationStore.v1"
    private let domain = "medication-health"
    private let entryKind = "entry"
    private let planKind = "plan"
    private let records: SwiftDataRecordStore

    private struct Payload: Codable {
        var entries: [MedicationEntry]
        var plans: [MedicationPlan]

        init(entries: [MedicationEntry] = [], plans: [MedicationPlan] = []) {
            self.entries = entries
            self.plans = plans
        }

        private enum CodingKeys: String, CodingKey {
            case entries
            case plans
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            entries = try container.decodeIfPresent([MedicationEntry].self, forKey: .entries) ?? []
            plans = try container.decodeIfPresent([MedicationPlan].self, forKey: .plans) ?? []
        }
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

    func save(_ entry: MedicationEntry) {
        var payload = load()
        var resolvedEntry = entry
        // 从计划创建的结果保存精确修订快照，后续编辑计划不会改变历史解释。
        if let planID = resolvedEntry.planID,
           let plan = payload.plans.first(where: { $0.id == planID }) {
            resolvedEntry.logicalPlanID = plan.logicalPlanID
            resolvedEntry.planRevision = plan.revision
        }

        if let index = payload.entries.firstIndex(where: { $0.id == resolvedEntry.id }) {
            payload.entries[index] = resolvedEntry
        } else {
            payload.entries.append(resolvedEntry)
        }
        payload.entries.sort { $0.takenAt > $1.takenAt }
        payload.entries = Array(payload.entries.prefix(240))
        persist(payload)
        scheduleReactionReminder(for: resolvedEntry)
    }

    func removeEntry(id: String) {
        var payload = load()
        payload.entries.removeAll { $0.id == id }
        persist(payload)
        LocalNotificationScheduler.cancel(identifiers: [reactionReminderIdentifier(for: id)])
    }

    func allEntries() -> [MedicationEntry] {
        load().entries.sorted { $0.takenAt > $1.takenAt }
    }

    func todayEntries(on date: Date = Date()) -> [MedicationEntry] {
        allEntries().filter { calendar.isDate($0.takenAt, inSameDayAs: date) }
    }

    func groupedRecentEntries(limitDays: Int = 14) -> [(date: Date, entries: [MedicationEntry])] {
        let cutoff = calendar.date(byAdding: .day, value: -max(0, limitDays - 1), to: calendar.startOfDay(for: Date())) ?? Date.distantPast
        let filtered = allEntries().filter { $0.takenAt >= cutoff }
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.takenAt) }
        return grouped
            .map { (date: $0.key, entries: $0.value.sorted { $0.takenAt > $1.takenAt }) }
            .sorted { $0.date > $1.date }
    }

    func frequentMedicationSummaries(limit: Int = 6) -> [MedicationNameSummary] {
        let grouped = Dictionary(grouping: allEntries()) { normalizedMedicationKey(name: $0.name, category: $0.category) }
        return grouped.compactMap { key, entries in
            guard let latest = entries.max(by: { $0.takenAt < $1.takenAt }) else { return nil }
            return MedicationNameSummary(
                normalizedKey: key,
                category: latest.category,
                name: latest.name,
                count: entries.count,
                lastTakenAt: latest.takenAt,
                suggestedAmount: latest.amount,
                suggestedUnit: latest.unit,
                suggestedPurpose: latest.purpose,
                suggestedNote: latest.note
            )
        }
        .sorted {
            if $0.count == $1.count {
                return $0.lastTakenAt > $1.lastTakenAt
            }
            return $0.count > $1.count
        }
        .prefix(limit)
        .map { $0 }
    }

    func usageSummary(days: Int = 7, referenceDate: Date = Date()) -> MedicationUsageSummary {
        let startOfReferenceDay = calendar.startOfDay(for: referenceDate)
        let cutoff = calendar.date(byAdding: .day, value: -max(0, days - 1), to: startOfReferenceDay) ?? startOfReferenceDay
        let filtered = allEntries().filter { $0.takenAt >= cutoff && $0.takenAt <= referenceDate }

        let activeDays = Set(filtered.map { calendar.startOfDay(for: $0.takenAt) }).count
        let uniqueMedicationCount = Set(filtered.map { normalizedMedicationKey(name: $0.name, category: $0.category) }).count

        let topMedication = Dictionary(grouping: filtered) { normalizedMedicationKey(name: $0.name, category: $0.category) }
            .compactMap { key, entries -> MedicationNameSummary? in
                guard let latest = entries.max(by: { $0.takenAt < $1.takenAt }) else { return nil }
                return MedicationNameSummary(
                    normalizedKey: key,
                    category: latest.category,
                    name: latest.name,
                    count: entries.count,
                    lastTakenAt: latest.takenAt,
                    suggestedAmount: latest.amount,
                    suggestedUnit: latest.unit,
                    suggestedPurpose: latest.purpose,
                    suggestedNote: latest.note
                )
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.lastTakenAt > $1.lastTakenAt
                }
                return $0.count > $1.count
            }
            .first

        let busiestBucket = MedicationTimeBucket.allCases
            .map { bucket in
                (bucket, filtered.filter { MedicationTimeBucket.resolve(for: $0.takenAt, calendar: calendar) == bucket }.count)
            }
            .max(by: { $0.1 < $1.1 })
            .flatMap { $0.1 > 0 ? $0.0 : nil }

        return MedicationUsageSummary(
            totalEntries: filtered.count,
            activeDays: activeDays,
            uniqueMedicationCount: uniqueMedicationCount,
            currentStreakDays: currentStreakDays(referenceDate: referenceDate),
            topMedication: topMedication,
            busiestBucket: busiestBucket
        )
    }

    func reactionSummary(days: Int = 14, referenceDate: Date = Date()) -> MedicationReactionSummary {
        let startOfReferenceDay = calendar.startOfDay(for: referenceDate)
        let cutoff = calendar.date(byAdding: .day, value: -max(0, days - 1), to: startOfReferenceDay) ?? startOfReferenceDay
        let filtered = allEntries()
            .filter { $0.takenAt >= cutoff && $0.takenAt <= referenceDate && $0.reactionState != nil }

        return MedicationReactionSummary(
            trackedEntries: filtered.count,
            improvedCount: filtered.filter { $0.reactionState == .improved }.count,
            neutralCount: filtered.filter { $0.reactionState == .neutral }.count,
            uncomfortableCount: filtered.filter { $0.reactionState == .uncomfortable }.count,
            lastTrackedEntry: filtered.max(by: { $0.takenAt < $1.takenAt })
        )
    }

    func pendingReactionSummary(limit: Int = 4, referenceDate: Date = Date()) -> MedicationPendingReactionSummary {
        let entries = allEntries()
            .filter { entry in
                entry.reactionState == nil &&
                (entry.followUpMinutes ?? 0) > 0 &&
                entry.takenAt <= referenceDate
            }
            .sorted { $0.takenAt > $1.takenAt }

        let overdue = entries.filter { entry in
            guard let followUpMinutes = entry.followUpMinutes else { return false }
            let dueDate = entry.takenAt.addingTimeInterval(TimeInterval(followUpMinutes * 60))
            return dueDate <= referenceDate
        }.count

        return MedicationPendingReactionSummary(
            pendingEntries: Array(entries.prefix(limit)),
            overdueCount: overdue
        )
    }

    func todayEntriesByBucket(on date: Date = Date()) -> [(bucket: MedicationTimeBucket, entries: [MedicationEntry])] {
        let entries = todayEntries(on: date)
        let grouped = Dictionary(grouping: entries) { entry in
            MedicationTimeBucket.resolve(for: entry.takenAt, calendar: calendar)
        }

        return MedicationTimeBucket.allCases.compactMap { bucket in
            guard let values = grouped[bucket], !values.isEmpty else { return nil }
            return (bucket, values.sorted { $0.takenAt < $1.takenAt })
        }
    }

    func allPlans(referenceDate: Date = Date()) -> [MedicationPlan] {
        let activePlans = load().plans
            .filter { $0.isEffective(at: referenceDate) }
            .reduce(into: [String: MedicationPlan]()) { result, plan in
                if let current = result[plan.logicalPlanID], current.revision >= plan.revision {
                    return
                }
                result[plan.logicalPlanID] = plan
            }

        return activePlans.values.sorted {
            if $0.reminder.hour == $1.reminder.hour {
                return $0.reminder.minute < $1.reminder.minute
            }
            return $0.reminder.hour < $1.reminder.hour
        }
    }

    func allPlanVersions(logicalPlanID: String? = nil) -> [MedicationPlan] {
        load().plans
            .filter { logicalPlanID == nil || $0.logicalPlanID == logicalPlanID }
            .sorted {
                if $0.logicalPlanID == $1.logicalPlanID {
                    return $0.revision > $1.revision
                }
                return $0.effectiveFrom > $1.effectiveFrom
            }
    }

    /// 按指定日期即时生成任务事件，不持久化重复的日任务副本。
    func taskEvents(on date: Date = Date(), referenceDate: Date = Date()) -> [MedicationTaskEvent] {
        let payload = load()
        let dayStart = calendar.startOfDay(for: date)

        return payload.plans.compactMap { plan in
            guard let scheduledAt = calendar.date(
                bySettingHour: plan.reminder.hour,
                minute: plan.reminder.minute,
                second: 0,
                of: dayStart
            ), plan.isEffective(at: scheduledAt) else {
                return nil
            }

            let outcome = payload.entries
                .filter { entry in
                    guard calendar.isDate(entry.takenAt, inSameDayAs: dayStart) else { return false }
                    return entry.planID == plan.id ||
                        (entry.logicalPlanID == plan.logicalPlanID && entry.planRevision == plan.revision)
                }
                .min { lhs, rhs in
                    abs(lhs.takenAt.timeIntervalSince(scheduledAt)) < abs(rhs.takenAt.timeIntervalSince(scheduledAt))
                }

            let status: MedicationTaskEventStatus
            if outcome != nil {
                status = .completed
            } else if scheduledAt < referenceDate {
                status = .overdue
            } else {
                status = .scheduled
            }

            return MedicationTaskEvent(
                id: "\(plan.id)|\(Int(dayStart.timeIntervalSince1970))",
                planID: plan.id,
                logicalPlanID: plan.logicalPlanID,
                planRevision: plan.revision,
                scheduledAt: scheduledAt,
                status: status,
                outcome: outcome
            )
        }
        .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func outcomes(for logicalPlanID: String) -> [MedicationEntry] {
        let payload = load()
        let versionIDs = Set(payload.plans
            .filter { $0.logicalPlanID == logicalPlanID }
            .map(\.id))

        return payload.entries
            .filter { entry in
                if entry.logicalPlanID == logicalPlanID { return true }
                guard let planID = entry.planID else { return false }
                return versionIDs.contains(planID)
            }
            .sorted { $0.takenAt > $1.takenAt }
    }

    func reminderEnabledPlanCount() -> Int {
        allPlans().filter(\.reminder.isEnabled).count
    }

    func savePlan(_ plan: MedicationPlan) {
        var payload = load()
        var planToSchedule = plan
        var reminderIDsToCancel: [String] = []

        if let index = payload.plans.firstIndex(where: { $0.id == plan.id }) {
            let previous = payload.plans[index]
            if hasSamePlanDefinition(previous, plan) {
                planToSchedule = previous
            } else {
                let effectiveFrom = Date()
                payload.plans[index].effectiveUntil = effectiveFrom
                reminderIDsToCancel.append(reminderIdentifier(for: previous.id))

                let nextRevision = payload.plans
                    .filter { $0.logicalPlanID == previous.logicalPlanID }
                    .map(\.revision)
                    .max()
                    .map { $0 + 1 } ?? 2

                planToSchedule = MedicationPlan(
                    id: UUID().uuidString,
                    category: plan.category,
                    name: plan.name,
                    amount: plan.amount,
                    unit: plan.unit,
                    purpose: plan.purpose,
                    note: plan.note,
                    reminder: plan.reminder,
                    logicalPlanID: previous.logicalPlanID,
                    revision: nextRevision,
                    effectiveFrom: effectiveFrom
                )
                payload.plans.append(planToSchedule)
            }
        } else {
            planToSchedule.logicalPlanID = plan.logicalPlanID.isEmpty ? plan.id : plan.logicalPlanID
            planToSchedule.revision = max(1, plan.revision)
            planToSchedule.effectiveUntil = nil
            payload.plans.append(planToSchedule)
        }
        payload.plans.sort {
            if $0.reminder.hour == $1.reminder.hour {
                return $0.reminder.minute < $1.reminder.minute
            }
            return $0.reminder.hour < $1.reminder.hour
        }
        persist(payload)
        LocalNotificationScheduler.cancel(identifiers: reminderIDsToCancel)
        scheduleReminder(for: planToSchedule)
    }

    func removePlan(id: String) {
        var payload = load()
        guard let index = payload.plans.firstIndex(where: { $0.id == id }) else { return }
        // 删除仅结束当前版本，历史版本和已产生的结果继续保留。
        payload.plans[index].effectiveUntil = Date()
        persist(payload)
        LocalNotificationScheduler.cancel(identifiers: [reminderIdentifier(for: id)])
    }

    func suggestedDraft(from summary: MedicationNameSummary) -> MedicationDraft {
        MedicationDraft(
            category: summary.category,
            name: summary.name,
            amount: summary.suggestedAmount,
            unit: summary.suggestedUnit,
            purpose: summary.suggestedPurpose,
            note: summary.suggestedNote,
            takenAt: Date()
        )
    }

    func suggestedDraft(from plan: MedicationPlan) -> MedicationDraft {
        MedicationDraft(
            category: plan.category,
            name: plan.name,
            amount: plan.amount,
            unit: plan.unit,
            purpose: plan.purpose,
            note: plan.note,
            takenAt: Date(),
            planID: plan.id,
            logicalPlanID: plan.logicalPlanID,
            planRevision: plan.revision
        )
    }

    func draft(from entry: MedicationEntry) -> MedicationDraft {
        MedicationDraft(
            id: entry.id,
            isExistingRecord: true,
            category: entry.category,
            name: entry.name,
            amount: entry.amount,
            unit: entry.unit,
            purpose: entry.purpose,
            note: entry.note,
            reactionState: entry.reactionState,
            reactionNote: entry.reactionNote,
            followUpMinutes: entry.followUpMinutes,
            takenAt: entry.takenAt,
            planID: entry.planID,
            logicalPlanID: entry.logicalPlanID,
            planRevision: entry.planRevision,
            backendRecordedAt: entry.backendRecordedAt,
            healthAppRecordedAt: entry.healthAppRecordedAt,
            healthAppStatusNote: entry.healthAppStatusNote
        )
    }

    func planDraft(from plan: MedicationPlan) -> MedicationPlanDraft {
        MedicationPlanDraft(
            id: plan.id,
            isExistingPlan: true,
            category: plan.category,
            name: plan.name,
            amount: plan.amount,
            unit: plan.unit,
            purpose: plan.purpose ?? "",
            note: plan.note ?? "",
            reminderEnabled: plan.reminder.isEnabled,
            reminderHour: plan.reminder.hour,
            reminderMinute: plan.reminder.minute
        )
    }

    func localInsight(referenceDate: Date = Date()) -> MedicationLocalInsight {
        let recentEntries = allEntries().filter {
            guard let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: referenceDate)) else { return true }
            return $0.takenAt >= cutoff
        }
        let reaction = reactionSummary(referenceDate: referenceDate)
        let sleepScore = AppGroupManager.shared.getSleepScore()
        let sleepMinutes = AppGroupManager.shared.getSleepDurationMinutes()
        let stress = AppGroupManager.shared.getLatestStress().map { Int($0.rounded()) }
        let periodSummary = PeriodStore.shared.summary(referenceDate: referenceDate)

        var tags: [String] = []
        if let sleepScore, sleepScore > 0 {
            tags.append("睡眠 \(sleepScore) 分")
        }
        if let stress {
            tags.append("压力 \(stress)")
        }
        if let dayIndex = periodSummary.current?.dayIndex {
            tags.append("周期第 \(dayIndex) 天")
        }
        if !recentEntries.isEmpty {
            tags.append("近7天 \(recentEntries.count) 条")
        }

        let bedtimeCount = recentEntries.filter {
            MedicationTimeBucket.resolve(for: $0.takenAt, calendar: calendar) == .bedtime
        }.count

        if reaction.uncomfortableCount > 0 {
            return MedicationLocalInsight(
                headline: "最近已经出现过不适体感，先减少同时变动的变量会更容易回看。",
                detail: "近两周有 \(reaction.uncomfortableCount) 条记录被标成“不适”。如果今天同时又有睡眠偏少、压力偏高或处在经期阶段，更适合先把时间、剂量和触发场景记完整，再观察是否总发生在同一时段。",
                tags: tags
            )
        }

        if bedtimeCount >= 2, let sleepScore, sleepScore > 0, let sleepMinutes, sleepMinutes > 0 {
            let hours = String(format: "%.1f", Double(sleepMinutes) / 60.0)
            let detail: String
            if sleepScore >= 80 {
                detail = "近7天有 \(bedtimeCount) 次夜间记录，而昨夜睡眠约 \(hours) 小时、得分 \(sleepScore) 分，当前更像是节律仍然稳定。后面如果夜间摄入继续增加，再和第二天恢复感一起看会更有参考价值。"
            } else {
                detail = "近7天有 \(bedtimeCount) 次夜间记录，而昨夜睡眠约 \(hours) 小时、得分 \(sleepScore) 分。这里更适合回看服用是否集中在睡前 2 小时内，以及当天是否同时叠加了高压力或晚睡。"
            }
            return MedicationLocalInsight(
                headline: "夜间摄入和睡眠恢复值得放在同一天一起回看。",
                detail: detail,
                tags: tags
            )
        }

        if let stress, stress >= 70 {
            return MedicationLocalInsight(
                headline: "今天压力读数偏高，摄入记录更适合和同一时段的体感一起读。",
                detail: "当前压力约 \(stress) 分。无论是按需用药还是日常补剂，现在都更建议把“为什么服用、服用后有没有变舒服”记清楚，这样后面更容易区分是身体反应，还是高压背景下的短时波动。",
                tags: tags
            )
        }

        if let phase = periodSummary.current?.phase {
            let phaseText = Self.periodPhaseText(phase)
            return MedicationLocalInsight(
                headline: "当前处在\(phaseText)，更适合把体感和周期背景一起看。",
                detail: "经期相关症状、胃口、恢复感和情绪波动都可能让同一种摄入在不同阶段呈现出不同体验。现在先稳定记录时间、剂量和体感，比急着下结论更有帮助。",
                tags: tags
            )
        }

        return MedicationLocalInsight(
            headline: "这个模块已经能先在端上建立“记录 -> 回看 -> 解释”的闭环。",
            detail: "继续把服用时间、用途和服用后体感记完整，后面就能更稳定地和睡眠、压力、周期节律做同天对照。现在不急着推断因果，先把可回看的上下文留住最重要。",
            tags: tags
        )
    }

    private func load() -> Payload {
        guard let rows = records.records(domain: domain) else {
            return loadLegacyPayload() ?? Payload()
        }
        return Payload(
            entries: rows
                .filter { $0.kind == entryKind }
                .compactMap { try? decoder.decode(MedicationEntry.self, from: $0.payload) },
            plans: rows
                .filter { $0.kind == planKind }
                .compactMap { try? decoder.decode(MedicationPlan.self, from: $0.payload) }
        )
    }

    private func persist(_ payload: Payload) {
        let entrySeeds = payload.entries.compactMap { entry -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(entry) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: entry.id,
                kind: entryKind,
                occurredAt: entry.takenAt,
                updatedAt: entry.backendRecordedAt ?? entry.healthAppRecordedAt ?? entry.takenAt,
                payload: data
            )
        }
        let planSeeds = payload.plans.compactMap { plan -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(plan) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: plan.id,
                kind: planKind,
                occurredAt: plan.effectiveFrom,
                updatedAt: plan.effectiveUntil ?? plan.effectiveFrom,
                payload: data
            )
        }
        guard entrySeeds.count == payload.entries.count,
              planSeeds.count == payload.plans.count,
              records.replace(domain: domain, with: entrySeeds + planSeeds) else { return }
        NotificationCenter.default.post(name: .profileVitalityRecordsDidChange, object: self)
    }

    private func loadLegacyPayload() -> Payload? {
        for storageKey in [key, legacyKey] {
            if let data = defaults.data(forKey: storageKey),
               let payload = try? decoder.decode(Payload.self, from: data) {
                return payload
            }
        }
        return nil
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "medicationStore.v2-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: legacyKey)
            return
        }

        let hasLegacyData = defaults.data(forKey: key) != nil || defaults.data(forKey: legacyKey) != nil
        let payload = loadLegacyPayload() ?? Payload()
        guard !hasLegacyData || loadLegacyPayload() != nil else { return }

        let entrySeeds = payload.entries.compactMap { entry -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(entry) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: entry.id,
                kind: entryKind,
                occurredAt: entry.takenAt,
                updatedAt: entry.backendRecordedAt ?? entry.healthAppRecordedAt ?? entry.takenAt,
                payload: data
            )
        }
        let planSeeds = payload.plans.compactMap { plan -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(plan) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: plan.id,
                kind: planKind,
                occurredAt: plan.effectiveFrom,
                updatedAt: plan.effectiveUntil ?? plan.effectiveFrom,
                payload: data
            )
        }
        guard entrySeeds.count == payload.entries.count,
              planSeeds.count == payload.plans.count,
              records.migrate(migrationID, seeds: entrySeeds + planSeeds) else { return }
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: legacyKey)
    }

    private func scheduleReminder(for plan: MedicationPlan) {
        let identifier = reminderIdentifier(for: plan.id)
        LocalNotificationScheduler.cancel(identifiers: [identifier])

        guard plan.reminder.isEnabled else { return }

        let body: String
        if let amount = plan.amount {
            body = String(localized: "别忘了 \(plan.name) \(formattedAmount(amount)) \(plan.unit)，记完就能安心去忙啦。")
        } else {
            body = String(localized: "别忘了 \(plan.name)，记完就能安心去忙啦。")
        }

        LocalNotificationScheduler.scheduleDaily(
            identifier: identifier,
            hour: plan.reminder.hour,
            minute: plan.reminder.minute,
            title: String(localized: "⏰ \(plan.category.title)时间到"),
            body: body
        )
    }

    private func scheduleReactionReminder(for entry: MedicationEntry) {
        let identifier = reactionReminderIdentifier(for: entry.id)
        LocalNotificationScheduler.cancel(identifiers: [identifier])

        guard entry.reactionState == nil,
              let followUpMinutes = entry.followUpMinutes,
              followUpMinutes > 0 else {
            return
        }

        let dueDate = entry.takenAt.addingTimeInterval(TimeInterval(followUpMinutes * 60))
        let seconds = dueDate.timeIntervalSinceNow
        guard seconds > 0 else { return }

        LocalNotificationScheduler.scheduleAfter(
            identifier: identifier,
            seconds: seconds,
            title: String(localized: "📝 身体反馈时间"),
            body: String(localized: "服完 \(entry.name) 感觉如何？回来点一下更舒服、平稳还是不适吧。")
        )
    }

    private func reminderIdentifier(for planID: String) -> String {
        "medication.plan.reminder.\(planID)"
    }

    private func hasSamePlanDefinition(_ lhs: MedicationPlan, _ rhs: MedicationPlan) -> Bool {
        lhs.category == rhs.category &&
        lhs.name == rhs.name &&
        lhs.amount == rhs.amount &&
        lhs.unit == rhs.unit &&
        lhs.purpose == rhs.purpose &&
        lhs.note == rhs.note &&
        lhs.reminder == rhs.reminder
    }

    private func reactionReminderIdentifier(for entryID: String) -> String {
        "medication.entry.reaction.\(entryID)"
    }

    private func normalizedMedicationKey(name: String, category: MedicationEntryCategory) -> String {
        "\(category.rawValue)|\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func currentStreakDays(referenceDate: Date) -> Int {
        let recordedDays = Set(allEntries().map { calendar.startOfDay(for: $0.takenAt) })
        var cursor = calendar.startOfDay(for: referenceDate)
        var streak = 0

        while recordedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    private func formattedAmount(_ amount: Double) -> String {
        if floor(amount) == amount {
            return "\(Int(amount))"
        }
        return String(format: "%.1f", amount)
    }

    private static func periodPhaseText(_ phase: String) -> String {
        switch phase {
        case "MENSTRUATION":
            return String(localized: "经期阶段")
        case "OVULATION":
            return String(localized: "排卵期附近")
        case "FOLLICULAR":
            return "卵泡期"
        case "LUTEAL":
            return "黄体期"
        default:
            return String(localized: "当前周期阶段")
        }
    }
}
