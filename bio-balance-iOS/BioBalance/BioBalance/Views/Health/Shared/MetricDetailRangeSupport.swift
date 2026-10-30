/// MetricDetailRangeSupport 作为健康指标详情页的共享支撑类型。
/// 负责定义时间范围枚举（天/周/月）并提供范围聚合天数计算。

import Foundation

/// 今日页“身体信号”统一使用的滚动时间范围。
/// 日为所选自然日；周/月/年分别为截至锚点日的最近 7/30/365 天。
enum BodySignalRollingRange: String, CaseIterable, Sendable {
    case day
    case week
    case month
    case year

    var dayCount: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }

    func interval(anchorDate: Date, calendar: Calendar = .current) -> DateInterval {
        let anchorStart = calendar.startOfDay(for: anchorDate)
        let end = calendar.date(byAdding: .day, value: 1, to: anchorStart)
            ?? anchorStart.addingTimeInterval(86_400)
        guard self != .day else { return DateInterval(start: anchorStart, end: end) }
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: anchorStart)
            ?? end.addingTimeInterval(-Double(dayCount) * 86_400)
        return DateInterval(start: start, end: end)
    }

    func queryEnd(anchorDate: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        min(interval(anchorDate: anchorDate, calendar: calendar).end, now)
    }

    func shiftedAnchor(_ anchorDate: Date, by offset: Int, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component
        switch self {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        return calendar.date(byAdding: component, value: offset, to: anchorDate) ?? anchorDate
    }
}

enum MetricDetailRange: String, CaseIterable, Identifiable {
    case day = "天"
    case week = "周"
    case month = "月"

    var id: String { rawValue }

    var aggregateDays: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 31
        }
    }

    func shift(_ date: Date, by step: Int, calendar: Calendar = .current) -> Date {
        switch self {
        case .day:
            return calendar.date(byAdding: .day, value: step, to: date) ?? date
        case .week:
            return calendar.date(byAdding: .day, value: step * 7, to: date) ?? date
        case .month:
            return calendar.date(byAdding: .month, value: step, to: date) ?? date
        }
    }

    func canShiftForward(from date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let candidate = shift(date, by: 1, calendar: calendar)
        let candidateStart = visibleDateInterval(anchorDate: candidate, calendar: calendar).start
        return candidateStart <= calendar.startOfDay(for: now)
    }

    func shiftClampedToToday(
        _ date: Date,
        by step: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        guard step > 0 else { return shift(date, by: step, calendar: calendar) }
        guard canShiftForward(from: date, now: now, calendar: calendar) else { return date }
        return min(shift(date, by: step, calendar: calendar), calendar.startOfDay(for: now))
    }

    func title(for date: Date, calendar: Calendar = .current) -> String {
        switch self {
        case .day:
            return ChineseDateText.fullDate(date)
        case .week:
            let interval = visibleDateInterval(anchorDate: date, calendar: calendar)
            let start = interval.start
            let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? start
            return "\(ChineseDateText.compactMonthDay(start)) - \(ChineseDateText.compactMonthDay(end))"
        case .month:
            return ChineseDateText.compactMonth(date)
        }
    }

    func visibleDateInterval(anchorDate: Date, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .day:
            let start = calendar.startOfDay(for: anchorDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .week:
            let anchorStart = calendar.startOfDay(for: anchorDate)
            let end = calendar.date(byAdding: .day, value: 1, to: anchorStart) ?? anchorStart
            let start = calendar.date(byAdding: .day, value: -7, to: end) ?? anchorStart
            return DateInterval(start: start, end: end)
        case .month:
            return calendar.dateInterval(of: .month, for: anchorDate)
                ?? DateInterval(start: calendar.startOfDay(for: anchorDate), duration: 24 * 60 * 60)
        }
    }

    func queryEndDate(anchorDate: Date, calendar: Calendar = .current) -> Date {
        let interval = visibleDateInterval(anchorDate: anchorDate, calendar: calendar)
        return calendar.date(byAdding: .second, value: -1, to: interval.end) ?? anchorDate
    }

    func contains(_ date: Date, anchorDate: Date, calendar: Calendar = .current) -> Bool {
        visibleDateInterval(anchorDate: anchorDate, calendar: calendar).contains(date)
    }

    func points(in rawPoints: [TimeSeriesPointDouble], anchorDate: Date, calendar: Calendar = .current) -> [TimeSeriesPointDouble] {
        let sorted = rawPoints.sorted { $0.timestamp < $1.timestamp }
        let interval = visibleDateInterval(anchorDate: anchorDate, calendar: calendar)
        return sorted.filter { interval.contains($0.date) }
    }
}
