import Foundation
import HealthKit

/// TrendsViewModel 压力矩阵 / 趋势卡片计算的纯计算子模块。
/// 从原 TrendsViewModel.swift 拆出：保持对外接口不变（static 方法由 private 提升为 internal）。
/// PEN-3 P2-3：纯计算迁移到 nonisolated 命名空间，避免在主线程执行批量矩阵计算。

// MARK: - 小时取整辅助
extension Calendar {
    nonisolated func startOfHour(for date: Date) -> Date {
        dateInterval(of: .hour, for: date)?.start ?? date
    }
}

// MARK: - 压力矩阵计算（nonisolated 纯计算）

nonisolated enum PressureMatrixMath {

    private struct PressureDayHourKey: Hashable {
        let day: Date
        let hour: Int
    }

    static func estimateStressSeriesByTimestamp(
        hrv: [TimeSeriesPointDouble],
        heartRate: [TimeSeriesPointDouble],
        restingHeartRate: [TimeSeriesPointDouble]
    ) -> [TimeSeriesPointDouble] {
        let calendar = Calendar.current
        let hrvByHour = averagedValuesByKey(hrv) { calendar.startOfHour(for: $0.date).timeIntervalSince1970 }
        let hourByTimestamp = averagedValuesByKey(heartRate) { calendar.startOfHour(for: $0.date).timeIntervalSince1970 }
        let restingByDay = averagedValuesByKey(restingHeartRate) { calendar.startOfDay(for: $0.date) }
        let hrvBaseline = HealthBaselineStrategy.usableValue(for: Array(hrvByHour.values), metric: .hrvSDNN)
        let timestamps = Set(hrvByHour.keys).union(hourByTimestamp.keys)

        return timestamps.compactMap { timestamp in
            let hour = Date(timeIntervalSince1970: timestamp)
            let day = calendar.startOfDay(for: hour)
            let hr = hourByTimestamp[timestamp] ?? 0
            let resting = restingByDay[day]
            let priorTimestamp = calendar.date(byAdding: .hour, value: -1, to: hour)?.timeIntervalSince1970
            let stress = StressDailyEngine.instantaneousStress(
                hrv: hrvByHour[timestamp] ?? 0,
                heartRate: hr,
                restingHeartRate: resting,
                recentAvgHrv: hrvBaseline,
                priorHeartRate: priorTimestamp.flatMap { hourByTimestamp[$0] }
            )
            guard stress > 0 else { return nil }
            return TimeSeriesPointDouble(timestamp: Int64(hour.timeIntervalSince1970), value: Double(stress))
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    static func buildPressureSlotMatrix(
        range: TrendsRange,
        historyEvents: [TimeSeriesPointDouble],
        estimatedHourly: [TimeSeriesPointDouble]
    ) -> (rows: [PressureTimeSlotRow], samples: [PressureSamplePoint]) {
        let calendar = Calendar.current
        let now = Date()
        let currentDayStart = calendar.startOfDay(for: now)
        let currentHourStart = calendar.startOfHour(for: now)
        let slotDuration = range.isIntraday ? 1 : 3
        let displayedDays = (0..<range.windowDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: range.startDate)
        }
        let slotStarts = Array(stride(from: 0, to: 24, by: slotDuration))

        let historyByDayHour = Dictionary(grouping: historyEvents) { event in
            PressureDayHourKey(
                day: calendar.startOfDay(for: event.date),
                hour: calendar.component(.hour, from: event.date)
            )
        }
        let estimatedByDayHour = Dictionary(grouping: estimatedHourly) { event in
            PressureDayHourKey(
                day: calendar.startOfDay(for: event.date),
                hour: calendar.component(.hour, from: event.date)
            )
        }

        let allBaselines = historyEvents + estimatedHourly
        let dayBaselines = averagedValuesByKey(allBaselines) { calendar.startOfDay(for: $0.date) }

        var rows: [PressureTimeSlotRow] = []
        var samples: [PressureSamplePoint] = []

        for day in displayedDays {
            let dayStart = calendar.startOfDay(for: day)
            var cells: [PressureTimeSlotCell] = []

            for slotStart in slotStarts {
                let slotDate = calendar.date(byAdding: .hour, value: slotStart, to: dayStart) ?? dayStart
                let isFutureSlot = dayStart == currentDayStart && slotDate > currentHourStart

                if isFutureSlot {
                    cells.append(
                        PressureTimeSlotCell(
                            date: dayStart,
                            slotStartHour: slotStart,
                            slotDurationHours: slotDuration,
                            value: nil,
                            source: .empty
                        )
                    )
                    continue
                }

                let hours = Array(slotStart..<(min(slotStart + slotDuration, 24)))
                let historyValues = hours.flatMap { hour in
                    historyByDayHour[PressureDayHourKey(day: dayStart, hour: hour)]?.map { $0.value } ?? []
                }
                let estimatedValues = hours.flatMap { hour in
                    estimatedByDayHour[PressureDayHourKey(day: dayStart, hour: hour)]?.map { $0.value } ?? []
                }

                let cell: PressureTimeSlotCell
                if !historyValues.isEmpty {
                    let value = historyValues.reduce(0, +) / Double(historyValues.count)
                    cell = PressureTimeSlotCell(
                        date: dayStart,
                        slotStartHour: slotStart,
                        slotDurationHours: slotDuration,
                        value: value,
                        source: .measured
                    )
                } else if !estimatedValues.isEmpty {
                    let value = estimatedValues.reduce(0, +) / Double(estimatedValues.count)
                    cell = PressureTimeSlotCell(
                        date: dayStart,
                        slotStartHour: slotStart,
                        slotDurationHours: slotDuration,
                        value: value,
                        source: .estimated
                    )
                } else if let baseline = dayBaselines[dayStart] {
                    cell = PressureTimeSlotCell(
                        date: dayStart,
                        slotStartHour: slotStart,
                        slotDurationHours: slotDuration,
                        value: baseline,
                        source: .inferred
                    )
                } else {
                    cell = PressureTimeSlotCell(
                        date: dayStart,
                        slotStartHour: slotStart,
                        slotDurationHours: slotDuration,
                        value: nil,
                        source: .empty
                    )
                }

                cells.append(cell)

                if let value = cell.value {
                    samples.append(
                        PressureSamplePoint(
                            timestamp: Int64(slotDate.timeIntervalSince1970),
                            value: value,
                            source: cell.source
                        )
                    )
                }
            }

            rows.append(PressureTimeSlotRow(date: dayStart, cells: cells))
        }

        return (rows, samples)
    }

    static func averagedValuesByKey<Key: Hashable>(
        _ points: [TimeSeriesPointDouble],
        key: (TimeSeriesPointDouble) -> Key
    ) -> [Key: Double] {
        Dictionary(grouping: points, by: key).mapValues { groupedPoints in
            let values = groupedPoints.map(\.value)
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Double(values.count)
        }
    }
}

// MARK: - TrendsViewModel 展示派生

extension TrendsViewModel {

    static func buildFeaturedCategoryCards(from details: [TrendCategoryID: TrendCategoryDetailModel]) -> [FeaturedTrendCategoryModel] {
        let featuredCategories: [TrendCategoryID] = [
            .sleepRecovery,
            .heartCardio,
            .dailyActivity
        ]

        return featuredCategories.compactMap { category in
            guard let detail = details[category] else { return nil }
            guard let primaryMetric = primaryMetric(for: category, detail: detail) else { return nil }

            let supportingMetrics = detail.metrics
                .filter { $0.title != primaryMetric.title }
                .prefix(2)

            return FeaturedTrendCategoryModel(
                category: category,
                primaryMetric: primaryMetric,
                supportingMetrics: Array(supportingMetrics),
                sleepNightSummaries: detail.sleepNightSummaries,
                sleepRecoveryMetrics: detail.sleepRecoveryMetrics
            )
        }
    }

    static func primaryMetric(for category: TrendCategoryID, detail: TrendCategoryDetailModel) -> TrendCategoryMetricModel? {
        let preferredTitles: [String]
        switch category {
        case .sleepRecovery:
            preferredTitles = ["睡眠总时长", "睡眠评分", "睡眠 HRV"]
        case .heartCardio:
            preferredTitles = ["心率", "心率变异性（HRV）", "静息心率"]
        case .dailyActivity:
            preferredTitles = ["步行速度", "步数", "步行距离"]
        default:
            preferredTitles = []
        }

        for title in preferredTitles {
            if let matched = detail.metrics.first(where: { $0.title == title }) {
                return matched
            }
        }

        return detail.metrics.first
    }
}
