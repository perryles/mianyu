import Foundation

struct PregnancyProfile: Codable, Equatable, Sendable {
    let id: String
    let dueDate: Date
    let lastMenstrualPeriod: Date
    let endedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        dueDate: Date,
        lastMenstrualPeriod: Date,
        endedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.dueDate = dueDate
        self.lastMenstrualPeriod = lastMenstrualPeriod
        self.endedAt = endedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isActive: Bool { endedAt == nil }
}

struct PregnancyWeightEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let pregnancyID: String
    let measuredAt: Date
    let weightKg: Double
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        pregnancyID: String,
        measuredAt: Date,
        weightKg: Double,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pregnancyID = pregnancyID
        self.measuredAt = measuredAt
        self.weightKg = weightKg
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct FetalMovementEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let pregnancyID: String
    let occurredAt: Date
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        pregnancyID: String,
        occurredAt: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pregnancyID = pregnancyID
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct PregnancySnapshot: Equatable, Sendable {
    var profile: PregnancyProfile?
    var weightEntries: [PregnancyWeightEntry]
    var fetalMovementEntries: [FetalMovementEntry]

    static let empty = PregnancySnapshot(
        profile: nil,
        weightEntries: [],
        fetalMovementEntries: []
    )

    init(
        profile: PregnancyProfile?,
        weightEntries: [PregnancyWeightEntry],
        fetalMovementEntries: [FetalMovementEntry]
    ) {
        self.profile = profile
        self.weightEntries = weightEntries.sorted { $0.measuredAt < $1.measuredAt }
        self.fetalMovementEntries = fetalMovementEntries.sorted { $0.occurredAt > $1.occurredAt }
    }
}

struct PregnancyProgress: Equatable, Sendable {
    let completedWeeks: Int
    let remainingDaysInWeek: Int
    let gestationalDays: Int
    let daysUntilDueDate: Int
    let fractionComplete: Double
    let trimester: Int
}

struct PregnancyStageGuidance: Equatable, Sendable {
    let title: String
    let headline: String
    let detail: String
    let symbol: String

    init(trimester: Int) {
        switch min(3, max(1, trimester)) {
        case 1:
            title = "孕早期"
            headline = "先把产检与休息节奏稳下来"
            detail = "记录日期和体重变化；如果持续不适或有任何担心，及时联系专业医护人员。"
            symbol = "leaf.fill"
        case 2:
            title = "孕中期"
            headline = "留意身体变化，建立自己的记录节奏"
            detail = "可以持续记录体重，并按医生建议开始关注胎动；每个人开始感受到胎动的时间不同。"
            symbol = "figure.walk"
        default:
            title = "孕晚期"
            headline = "保持观察，为分娩阶段做好准备"
            detail = "继续记录体重和熟悉的胎动模式；若胎动明显减少或身体不适，请尽快联系医护人员。"
            symbol = "heart.text.clipboard.fill"
        }
    }
}

enum PregnancyChartRange: String, CaseIterable, Identifiable, Sendable {
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "周"
        case .month: return "月"
        }
    }

    var dayCount: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        }
    }
}

struct FetalMovementMonthGroup: Identifiable, Equatable, Sendable {
    let monthStart: Date
    let entries: [FetalMovementEntry]

    var id: Date { monthStart }
}

enum PregnancyDateCalculator {
    static let standardPregnancyDays = 280

    static func expectedDueDate(
        from lastMenstrualPeriod: Date,
        calendar: Calendar = .current
    ) -> Date {
        let start = calendar.startOfDay(for: lastMenstrualPeriod)
        return calendar.date(byAdding: .day, value: standardPregnancyDays, to: start) ?? start
    }

    static func estimatedLastMenstrualPeriod(
        from dueDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        let due = calendar.startOfDay(for: dueDate)
        return calendar.date(byAdding: .day, value: -standardPregnancyDays, to: due) ?? due
    }

    static func progress(
        for profile: PregnancyProfile,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> PregnancyProgress {
        let start = calendar.startOfDay(for: profile.lastMenstrualPeriod)
        let today = calendar.startOfDay(for: referenceDate)
        let due = calendar.startOfDay(for: profile.dueDate)
        let rawGestationalDays = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        let gestationalDays = max(0, rawGestationalDays)
        let daysUntilDueDate = calendar.dateComponents([.day], from: today, to: due).day ?? 0
        let completedWeeks = gestationalDays / 7
        let remainingDays = gestationalDays % 7
        let fraction = min(1, max(0, Double(rawGestationalDays) / Double(standardPregnancyDays)))

        let trimester: Int
        switch gestationalDays {
        case ..<(14 * 7):
            trimester = 1
        case ..<(28 * 7):
            trimester = 2
        default:
            trimester = 3
        }

        return PregnancyProgress(
            completedWeeks: completedWeeks,
            remainingDaysInWeek: remainingDays,
            gestationalDays: gestationalDays,
            daysUntilDueDate: daysUntilDueDate,
            fractionComplete: fraction,
            trimester: trimester
        )
    }
}

enum PregnancyDayCoding {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

enum PregnancyAnalytics {
    static func dateDomain(
        for range: PregnancyChartRange,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ClosedRange<Date> {
        let startOfToday = calendar.startOfDay(for: referenceDate)

        switch range {
        case .week:
            var weekCalendar = calendar
            weekCalendar.firstWeekday = 2
            weekCalendar.minimumDaysInFirstWeek = 4
            let start = weekCalendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start ?? startOfToday
            let nextWeek = weekCalendar.date(byAdding: .day, value: 7, to: start) ?? referenceDate
            return start...max(start, nextWeek.addingTimeInterval(-1))
        case .month:
            let start = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: startOfToday) ?? startOfToday
            return start...max(start, referenceDate)
        }
    }

    static func weights(
        _ entries: [PregnancyWeightEntry],
        range: PregnancyChartRange,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [PregnancyWeightEntry] {
        let end = referenceDate
        let start = dateDomain(
            for: range,
            referenceDate: referenceDate,
            calendar: calendar
        ).lowerBound
        return entries
            .filter { $0.measuredAt >= start && $0.measuredAt <= end }
            .sorted { $0.measuredAt < $1.measuredAt }
    }

    static func groupFetalMovementsByMonth(
        _ entries: [FetalMovementEntry],
        calendar: Calendar = .current
    ) -> [FetalMovementMonthGroup] {
        let grouped = Dictionary(grouping: entries) { entry in
            let components = calendar.dateComponents([.year, .month], from: entry.occurredAt)
            return calendar.date(from: components) ?? calendar.startOfDay(for: entry.occurredAt)
        }

        return grouped
            .map { month, values in
                FetalMovementMonthGroup(
                    monthStart: month,
                    entries: values.sorted { $0.occurredAt > $1.occurredAt }
                )
            }
            .sorted { $0.monthStart > $1.monthStart }
    }
}
