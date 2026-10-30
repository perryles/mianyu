import Foundation

enum SportTrendKind: String, Sendable, CaseIterable {
    case running
    case cycling
    case swimming

    var title: String {
        switch self {
        case .running: "跑步"
        case .cycling: "骑行"
        case .swimming: "游泳"
        }
    }

    var systemImage: String {
        switch self {
        case .running: "figure.run"
        case .cycling: "bicycle"
        case .swimming: "figure.pool.swim"
        }
    }

    var durationTitle: String { "\(title)总时长" }
    var distanceTitle: String { "\(title)距离" }
    var countTitle: String { "\(title)次数" }
    var energyTitle: String { "\(title)能量" }

    var efficiencyTitle: String {
        switch self {
        case .running: "平均配速"
        case .cycling, .swimming: "平均速度"
        }
    }

    var efficiencyUnit: String {
        switch self {
        case .running: "分/公里"
        case .cycling, .swimming: "km/h"
        }
    }

    var efficiencyReadingHint: String {
        switch self {
        case .running: "配速数值越低代表跑得越快"
        case .cycling, .swimming: "速度数值越高代表节奏越快"
        }
    }

    func accentHex(for metric: SportTrendVolumeMetric) -> String {
        switch (self, metric) {
        case (.running, .duration): "FF7A59"
        case (.running, .count): "F36F45"
        case (.running, .distance): "32ADE6"
        case (.cycling, .duration): "32ADE6"
        case (.cycling, .count): "27C2FF"
        case (.cycling, .distance): "5DADE2"
        case (.swimming, .duration): "27C2FF"
        case (.swimming, .count): "32ADE6"
        case (.swimming, .distance): "5DADE2"
        }
    }

    var efficiencyAccentHex: String {
        switch self {
        case .running: "8EC5FF"
        case .cycling, .swimming: "7CD992"
        }
    }

    var energyAccentHex: String { "FFB340" }
}

enum SportTrendVolumeMetric: String, CaseIterable, Identifiable, Sendable {
    case distance
    case duration
    case count

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: "距离"
        case .duration: "时长"
        case .count: "次数"
        }
    }

    var unit: String {
        switch self {
        case .distance: "km"
        case .duration: "分钟"
        case .count: "次"
        }
    }
}

struct SportTrendDayPoint: Identifiable, Sendable, Equatable {
    var id: Date { date }
    let date: Date
    let duration: Double?
    let distance: Double?
    let count: Double?
    let energy: Double?
    let efficiency: Double?

    func value(for metric: SportTrendVolumeMetric) -> Double? {
        switch metric {
        case .distance: distance
        case .duration: duration
        case .count: count
        }
    }

    var hasAnyValue: Bool {
        duration != nil || distance != nil || count != nil || energy != nil || efficiency != nil
    }
}

struct MindfulnessTrendDayPoint: Identifiable, Sendable, Equatable {
    var id: Date { date }
    let date: Date
    let mindfulMinutes: Double?
    let stateScore: Double?

    var hasAnyValue: Bool { mindfulMinutes != nil || stateScore != nil }
}

struct SegmentedTrendValuePoint: Identifiable, Sendable, Equatable {
    var id: String { "\(segment)-\(date.timeIntervalSinceReferenceDate)" }
    let date: Date
    let value: Double
    let segment: Int
}

enum SpecializedTrendChartAnalyzer {
    static func sportDays(
        metrics: [TrendCategoryMetricModel],
        kind: SportTrendKind,
        calendar: Calendar = .current
    ) -> [SportTrendDayPoint] {
        let duration = aggregatedValues(
            points: metricPoints(named: kind.durationTitle, in: metrics),
            aggregation: .sum,
            calendar: calendar
        )
        let distance = aggregatedValues(
            points: metricPoints(named: kind.distanceTitle, in: metrics),
            aggregation: .sum,
            calendar: calendar
        )
        let count = aggregatedValues(
            points: metricPoints(named: kind.countTitle, in: metrics),
            aggregation: .sum,
            calendar: calendar
        )
        let energy = aggregatedValues(
            points: metricPoints(named: kind.energyTitle, in: metrics),
            aggregation: .sum,
            calendar: calendar
        )
        let efficiency = aggregatedValues(
            points: metricPoints(named: kind.efficiencyTitle, in: metrics),
            aggregation: .average,
            calendar: calendar
        )

        let dates = Set(duration.keys)
            .union(distance.keys)
            .union(count.keys)
            .union(energy.keys)
            .union(efficiency.keys)

        return dates.sorted().map { date in
            SportTrendDayPoint(
                date: date,
                duration: duration[date],
                distance: distance[date],
                count: count[date],
                energy: energy[date],
                efficiency: efficiency[date]
            )
        }
        .filter(\.hasAnyValue)
    }

    static func mindfulnessDays(
        metrics: [TrendCategoryMetricModel],
        calendar: Calendar = .current
    ) -> [MindfulnessTrendDayPoint] {
        let mindful = aggregatedValues(
            points: metricPoints(named: "正念时长", in: metrics),
            aggregation: .sum,
            calendar: calendar
        )
        let state = aggregatedValues(
            points: metricPoints(named: "心理状态", in: metrics),
            aggregation: .average,
            calendar: calendar
        )
        let dates = Set(mindful.keys).union(state.keys)

        return dates.sorted().map { date in
            MindfulnessTrendDayPoint(
                date: date,
                mindfulMinutes: mindful[date],
                stateScore: state[date]
            )
        }
        .filter(\.hasAnyValue)
    }

    static func total(
        _ points: [SportTrendDayPoint],
        metric: SportTrendVolumeMetric
    ) -> Double? {
        let values = points.compactMap { $0.value(for: metric) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    static func average(_ values: [Double?]) -> Double? {
        let validValues = values.compactMap { $0 }.filter(\.isFinite)
        guard !validValues.isEmpty else { return nil }
        return validValues.reduce(0, +) / Double(validValues.count)
    }

    /// 将折线按缺失值或缺失自然日切段，避免图表跨空档连接成伪趋势。
    static func segmentedValues(
        _ values: [(date: Date, value: Double?)],
        calendar: Calendar = .current
    ) -> [SegmentedTrendValuePoint] {
        var segment = 0
        var previousDate: Date?
        var result: [SegmentedTrendValuePoint] = []

        for entry in values.sorted(by: { $0.date < $1.date }) {
            if let previousDate {
                let previousDay = calendar.startOfDay(for: previousDate)
                let currentDay = calendar.startOfDay(for: entry.date)
                if (calendar.dateComponents([.day], from: previousDay, to: currentDay).day ?? 0) > 1 {
                    segment += 1
                }
            }

            guard let value = entry.value, value.isFinite else {
                segment += 1
                previousDate = entry.date
                continue
            }

            result.append(SegmentedTrendValuePoint(date: entry.date, value: value, segment: segment))
            previousDate = entry.date
        }

        return result
    }

    private enum Aggregation {
        case sum
        case average
    }

    private static func metricPoints(
        named title: String,
        in metrics: [TrendCategoryMetricModel]
    ) -> [TimeSeriesPointDouble] {
        metrics.first(where: { $0.title == title })?.points ?? []
    }

    private static func aggregatedValues(
        points: [TimeSeriesPointDouble],
        aggregation: Aggregation,
        calendar: Calendar
    ) -> [Date: Double] {
        let validPoints = points.filter { $0.value.isFinite }
        let grouped = Dictionary(grouping: validPoints) { calendar.startOfDay(for: $0.date) }

        return grouped.reduce(into: [Date: Double]()) { result, entry in
            let values = entry.value.map(\.value)
            guard !values.isEmpty else { return }
            switch aggregation {
            case .sum:
                result[entry.key] = values.reduce(0, +)
            case .average:
                result[entry.key] = values.reduce(0, +) / Double(values.count)
            }
        }
    }
}
