import Foundation

nonisolated enum ActivityTrendMetric: String, CaseIterable, Identifiable {
    case steps = "步数"
    case exercise = "锻炼"
    case energy = "能量"
    case stand = "站立"
    case speed = "步速"

    var id: String { rawValue }
    var usesBars: Bool { self != .speed }

    var unit: String {
        switch self {
        case .steps: return String(localized: "步")
        case .exercise: return String(localized: "分钟")
        case .energy: return String(localized: "千卡")
        case .stand: return String(localized: "小时")
        case .speed: return String(localized: "公里/时")
        }
    }
}

nonisolated struct ActivityTrendReading: Identifiable, Equatable {
    let timestamp: Int64
    let value: Double
    var id: Int64 { timestamp }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
}

nonisolated enum ActivityTrendData {
    static func prepare(_ readings: [ActivityTrendReading], metric: ActivityTrendMetric, domain: ClosedRange<Date>) -> [ActivityTrendReading] {
        readings.compactMap { reading in
            let value = metric == .speed ? reading.value * 3.6 : reading.value
            guard value.isFinite, value >= 0, domain.contains(reading.date) else { return nil }
            return ActivityTrendReading(timestamp: reading.timestamp, value: value)
        }.sorted { $0.timestamp < $1.timestamp }
    }

    static func selected(on date: Date, in readings: [ActivityTrendReading], calendar: Calendar = .current) -> ActivityTrendReading? {
        readings.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    static func plotDate(for reading: ActivityTrendReading, metric: ActivityTrendMetric, calendar: Calendar = .current) -> Date {
        guard metric.usesBars, let day = calendar.dateInterval(of: .day, for: reading.date) else { return reading.date }
        return day.start.addingTimeInterval(day.duration / 2)
    }

    static func segments(_ readings: [ActivityTrendReading], calendar: Calendar = .current) -> [[ActivityTrendReading]] {
        var result: [[ActivityTrendReading]] = []
        for reading in readings {
            if let previous = result.last?.last,
               let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: previous.date)),
               calendar.startOfDay(for: reading.date) <= nextDay {
                result[result.count - 1].append(reading)
            } else {
                result.append([reading])
            }
        }
        return result
    }

    static func yDomain(_ readings: [ActivityTrendReading], metric: ActivityTrendMetric) -> ClosedRange<Double> {
        let values = readings.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let padding = max(1, (high - low) * 0.18, high * 0.08)
        return (metric.usesBars ? 0 : max(0, low - padding))...(high + padding)
    }
}
