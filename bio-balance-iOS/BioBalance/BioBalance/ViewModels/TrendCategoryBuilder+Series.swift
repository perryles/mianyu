import Foundation
import HealthKit

/// TrendCategoryBuilder Series 子模块。
/// 从 TrendCategoryBuilder.swift 按职责拆分，对外接口不变。

extension TrendCategoryBuilder {

    static func percentSummary(from values: [TimeSeriesPointDouble]) -> String {
        guard let latest = values.last?.value, latest.isFinite else { return "暂无" }
        return "\(Int(latest.rounded()))%"
    }

    static func convertDailyHabitAnalyticsValues(
        _ values: [DailySleepStressAnalytics],
        metric: KeyPath<DailySleepStressAnalytics, Double?>
    ) -> [TimeSeriesPointDouble] {
        values.compactMap { item in
            guard let value = item[keyPath: metric],
                  let date = dayFormatter.date(from: item.date) else { return nil }
            return TimeSeriesPointDouble(timestamp: Int64(date.timeIntervalSince1970), value: value)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    static func convertDailyHabitCompletionRates(_ values: [DailySleepStressAnalytics]) -> [TimeSeriesPointDouble] {
        values.compactMap { item in
            guard let date = dayFormatter.date(from: item.date) else { return nil }
            let value: Double?
            if let rate = item.water_completion_rate {
                value = rate <= 1.0 ? rate * 100.0 : rate
            } else if let intake = item.water_intake_ml, let target = item.water_target_ml, target > 0 {
                value = min(100.0, (intake / Double(target)) * 100.0)
            } else {
                value = nil
            }
            guard let value, value.isFinite else { return nil }
            return TimeSeriesPointDouble(timestamp: Int64(date.timeIntervalSince1970), value: value)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    static func mergeDailyHabitValues(
        remoteValues: [DailySleepStressAnalytics],
        metric: KeyPath<DailySleepStressAnalytics, Double?>,
        localValue: (LocalActionDayRecord) -> Double,
        range: TrendsRange
    ) -> [TimeSeriesPointDouble] {
        let now = Date()
        let remotePoints = convertDailyHabitAnalyticsValues(remoteValues, metric: metric)
            .filter { $0.date >= range.startDate && $0.date <= now }
        var merged = Dictionary(uniqueKeysWithValues: remotePoints.map { ($0.timestamp, $0) })

        for record in ActionRecordStore.shared.allRecords() {
            let date = Calendar.current.startOfDay(for: record.date)
            guard date >= range.startDate && date <= now else { continue }
            let timestamp = Int64(date.timeIntervalSince1970)
            let value = localValue(record)
            guard value > 0 else { continue }
            if merged[timestamp] == nil || (merged[timestamp]?.value ?? 0) <= 0 {
                merged[timestamp] = TimeSeriesPointDouble(timestamp: timestamp, value: value)
            }
        }

        return merged.values.sorted { $0.timestamp < $1.timestamp }
    }

    static func mergeDailyHabitCompletionRates(
        remoteValues: [DailySleepStressAnalytics],
        localRecords: [LocalActionDayRecord],
        defaultTargetMl: Int,
        range: TrendsRange
    ) -> [TimeSeriesPointDouble] {
        let now = Date()
        let remotePoints = convertDailyHabitCompletionRates(remoteValues)
            .filter { $0.date >= range.startDate && $0.date <= now }
        var merged = Dictionary(uniqueKeysWithValues: remotePoints.map { ($0.timestamp, $0) })

        for record in localRecords {
            let date = Calendar.current.startOfDay(for: record.date)
            guard date >= range.startDate && date <= now else { continue }
            let timestamp = Int64(date.timeIntervalSince1970)
            guard record.waterMl > 0 else { continue }
            let target = max(defaultTargetMl, 1)
            let value = min(100.0, (Double(record.waterMl) / Double(target)) * 100.0)
            if merged[timestamp] == nil || (merged[timestamp]?.value ?? 0) <= 0 {
                merged[timestamp] = TimeSeriesPointDouble(timestamp: timestamp, value: value)
            }
        }

        return merged.values.sorted { $0.timestamp < $1.timestamp }
    }

    static func mealRecognitionSeries(
        records: [MealRecognitionRecord],
        range: TrendsRange,
        value: (MealRecognitionRecord) -> Double,
        aggregation: EventAggregation
    ) -> [TimeSeriesPointDouble] {
        eventSeries(
            events: records,
            range: range,
            date: \.capturedAt,
            value: value,
            aggregation: aggregation
        )
    }

    static func symptomRecordSeries(
        records: [SelfObservationRecord],
        range: TrendsRange,
        value: (SelfObservationRecord) -> Double,
        aggregation: EventAggregation
    ) -> [TimeSeriesPointDouble] {
        eventSeries(
            events: records,
            range: range,
            date: \.recordedAt,
            value: value,
            aggregation: aggregation
        )
    }

    static func medicationEntrySeries(
        entries: [MedicationEntry],
        range: TrendsRange
    ) -> [TimeSeriesPointDouble] {
        eventSeries(
            events: entries,
            range: range,
            date: \.takenAt,
            value: { _ in 1 },
            aggregation: .sum
        )
    }

    static func eventSeries<Event>(
        events: [Event],
        range: TrendsRange,
        date: KeyPath<Event, Date>,
        value: (Event) -> Double,
        aggregation: EventAggregation
    ) -> [TimeSeriesPointDouble] {
        let now = Date()
        let filtered = events
            .filter { event in
                let eventDate = event[keyPath: date]
                return eventDate >= range.startDate && eventDate <= now
            }
            .sorted { $0[keyPath: date] < $1[keyPath: date] }

        if range == .day {
            return filtered.map { event in
                TimeSeriesPointDouble(
                    timestamp: Int64(event[keyPath: date].timeIntervalSince1970),
                    value: value(event)
                )
            }
        }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0[keyPath: date]) }
        return grouped.map { day, dayEvents in
            let values = dayEvents.map(value)
            let aggregatedValue: Double
            switch aggregation {
            case .sum:
                aggregatedValue = values.reduce(0, +)
            case .average:
                aggregatedValue = values.reduce(0, +) / Double(max(values.count, 1))
            }
            return TimeSeriesPointDouble(
                timestamp: Int64(day.timeIntervalSince1970),
                value: aggregatedValue
            )
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    static func convertMetersToKilometers(_ values: [TimeSeriesPointDouble]) -> [TimeSeriesPointDouble] {
        values.map { point in
            TimeSeriesPointDouble(timestamp: point.timestamp, value: point.value / 1000.0)
        }
    }

    static func convertPercentToPercentage(_ values: [TimeSeriesPointDouble]) -> [TimeSeriesPointDouble] {
        values.map { point in
            TimeSeriesPointDouble(timestamp: point.timestamp, value: point.value * 100.0)
        }
    }

    static func summedPositiveValues(in points: [TimeSeriesPointDouble]) -> Double {
        points.reduce(0) { partialResult, point in
            partialResult + max(0, point.value)
        }
    }

    static func sumOrNil(for points: [TimeSeriesPointDouble]) -> Double? {
        guard !points.isEmpty else { return nil }
        return summedPositiveValues(in: points)
    }

    static func completeWindowSum(
        for points: [TimeSeriesPointDouble],
        expectedPointCount: Int
    ) -> Double? {
        guard expectedPointCount > 0, points.count == expectedPointCount else { return nil }
        return summedPositiveValues(in: points)
    }

}
