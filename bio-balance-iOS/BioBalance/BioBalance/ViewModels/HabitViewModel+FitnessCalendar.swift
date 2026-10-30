import SwiftUI

/// HabitViewModel 健身日历与趋势域 子模块。
/// 从原 HabitViewModel.swift 拆出，对外接口不变。

@MainActor
extension HabitViewModel {

    func makeFitnessCalendarModel(
        scope: HabitCalendarScope,
        energyTrend: [TimeSeriesPointDouble]?,
        exerciseTrend: [TimeSeriesPointDouble]?,
        standTrend: [TimeSeriesPointDouble]?,
        hrvTrend: [TimeSeriesPointDouble]?
    ) -> HabitFitnessCalendarModel {
        let calendar = Calendar.current
        let range = visibleRange(for: scope, anchor: selectedDateContext)
        let energyMap = pointsMap(energyTrend ?? activeEnergyTrend)
        let exerciseMap = pointsMap(exerciseTrend ?? exerciseMinutesTrend)
        let standMap = pointsMap(standTrend ?? standHoursTrend)
        let hrvMap = pointsMap(hrvTrend ?? self.hrvTrend)

        let days: [HabitFitnessCalendarDay]
        switch scope {
        case .week:
            days = (0..<7).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: range.startDate) else { return nil }
                return buildCalendarDay(
                    for: day,
                    energyMap: energyMap,
                    exerciseMap: exerciseMap,
                    standMap: standMap,
                    hrvMap: hrvMap,
                    isInDisplayedMonth: true
                )
            }
        case .month:
            let firstWeekday = calendar.component(.weekday, from: range.startDate)
            let leadingCount = max(0, firstWeekday - calendar.firstWeekday)
            let adjustedLeadingCount = leadingCount < 0 ? leadingCount + 7 : leadingCount
            let monthDays = calendar.range(of: .day, in: .month, for: range.startDate)?.count ?? 30
            let totalVisibleDays = adjustedLeadingCount + monthDays
            let trailingCount = totalVisibleDays % 7 == 0 ? 0 : 7 - (totalVisibleDays % 7)
            var built: [HabitFitnessCalendarDay] = []
            for index in 0..<(totalVisibleDays + trailingCount) {
                guard let day = calendar.date(byAdding: .day, value: index - adjustedLeadingCount, to: range.startDate) else { continue }
                let isDisplayedMonth = calendar.isDate(day, equalTo: range.startDate, toGranularity: .month)
                built.append(
                    buildCalendarDay(
                        for: day,
                        energyMap: energyMap,
                        exerciseMap: exerciseMap,
                        standMap: standMap,
                        hrvMap: hrvMap,
                        isInDisplayedMonth: isDisplayedMonth
                    )
                )
            }
            days = built
        }

        let activeDays = days.filter { $0.exerciseMinutes > 0 || $0.activeEnergy > 0 }
        let streak = consecutiveActiveDays(endingAt: selectedDateContext, exerciseMap: exerciseMap, energyMap: energyMap)
        let totalMinutes = activeDays.reduce(0) { $0 + $1.exerciseMinutes }
        let totalEnergy = activeDays.reduce(0) { $0 + $1.activeEnergy }

        return HabitFitnessCalendarModel(
            scope: scope,
            rangeTitle: calendarRangeTitle(for: scope, startDate: range.startDate, endDate: range.endDate),
            streakText: streak > 0 ? "连续运动 \(streak) 天" : "这段时间还没有连续训练",
            summaryPills: [
                "连续 \(streak) 天",
                "锻炼 \(totalMinutes) 分钟",
                "消耗 \(totalEnergy) kcal"
            ],
            days: days
        )
    }

    func makeFitnessStatsCards(scope: HabitCalendarScope, days: [HabitFitnessCalendarDay]) -> [HabitFitnessStatsCardModel] {
        let activeDays = days.filter { $0.isInDisplayedMonth || scope == .week }
        let totalMinutes = activeDays.reduce(0) { $0 + $1.exerciseMinutes }
        let goalMinutes = scope == .week ? 150 : 600
        let activeTrainingDays = activeDays.filter { $0.exerciseMinutes > 0 || $0.activeEnergy >= 120 }.count
        let targetActiveDays = scope == .week ? 4 : 16
        let longestDay = activeDays.max(by: { $0.exerciseMinutes < $1.exerciseMinutes })
        let highestIntensityDay = activeDays.max {
            intensityScore(for: $0) < intensityScore(for: $1)
        }

        let longestText: String
        if let longestDay, longestDay.exerciseMinutes > 0 {
            longestText = "\(longestDay.exerciseMinutes) 分钟"
        } else {
            longestText = "暂无"
        }

        let longestDetail: String
        if let longestDay, longestDay.exerciseMinutes > 0 {
            longestDetail = ChineseDateText.writtenMonthDay(longestDay.date)
        } else {
            longestDetail = "等待训练记录"
        }

        let highestText: String
        let highestDetail: String
        if let highestIntensityDay, intensityScore(for: highestIntensityDay) > 0 {
            highestText = intensityTier(for: highestIntensityDay)
            highestDetail = "\(highestIntensityDay.activeEnergy) kcal / \(max(highestIntensityDay.exerciseMinutes, 1)) 分钟"
        } else {
            highestText = "暂无"
            highestDetail = "等待同步"
        }

        return [
            HabitFitnessStatsCardModel(
                id: "exercise-total",
                title: "锻炼时间",
                valueText: "\(totalMinutes) 分钟",
                detailText: scope == .week ? "目标 150 分钟" : "目标 600 分钟",
                progress: goalMinutes > 0 ? min(1, Double(totalMinutes) / Double(goalMinutes)) : nil,
                tintHex: "F06A7B",
                symbol: "figure.run"
            ),
            HabitFitnessStatsCardModel(
                id: "exercise-longest",
                title: "最长运动时间",
                valueText: longestText,
                detailText: longestDetail,
                progress: nil,
                tintHex: "7D90FF",
                symbol: "timer"
            ),
            HabitFitnessStatsCardModel(
                id: "exercise-intensity",
                title: "最高强度",
                valueText: highestText,
                detailText: highestDetail,
                progress: nil,
                tintHex: "F4B46B",
                symbol: "flame.fill"
            ),
            HabitFitnessStatsCardModel(
                id: "exercise-frequency",
                title: "活跃天数",
                valueText: "\(activeTrainingDays) 天",
                detailText: scope == .week ? "目标 \(targetActiveDays) 天" : "保持每周 4 天节律",
                progress: targetActiveDays > 0 ? min(1, Double(activeTrainingDays) / Double(targetActiveDays)) : nil,
                tintHex: "73C8E8",
                symbol: "calendar.badge.clock"
            )
        ]
    }

    func convertTrend(_ points: [TimeSeriesPointDouble]) -> [HabitTrendPoint] {
        points
            .filter { $0.value > 0 }
            .map { HabitTrendPoint(date: $0.date, value: $0.value) }
    }

    func averageTrendValue(_ points: [HabitTrendPoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    struct HabitTrendSummary {
        let badgeText: String
        let detailText: String
    }

    func trendSummary(
        for kind: HabitBodyMetricKind,
        points: [HabitTrendPoint],
        neutralText: String
    ) -> HabitTrendSummary {
        let values = points.map(\.value)
        guard values.count >= 2 else {
            return HabitTrendSummary(
                badgeText: values.isEmpty ? "暂无数据" : "样本较少",
                detailText: values.isEmpty ? "等待健康 App 同步趋势数据" : "样本还不够，继续记录后再看变化。"
            )
        }

        let comparison: (current: Double, previous: Double)
        if values.count >= 6 {
            let splitIndex = values.count / 2
            let firstHalf = Array(values.prefix(splitIndex))
            let secondHalf = Array(values.suffix(values.count - splitIndex))
            comparison = (
                current: secondHalf.reduce(0, +) / Double(secondHalf.count),
                previous: firstHalf.reduce(0, +) / Double(firstHalf.count)
            )
        } else {
            comparison = (current: values.last ?? 0, previous: values.first ?? 0)
        }

        let delta = comparison.current - comparison.previous
        let absoluteThreshold = trendAbsoluteThreshold(for: kind)
        let relativeThreshold = max(abs(comparison.previous) * trendRelativeThreshold(for: kind), absoluteThreshold)
        let currentText = trendValueText(for: kind, value: comparison.current)
        let previousText = trendValueText(for: kind, value: comparison.previous)

        if abs(delta) < relativeThreshold {
            return HabitTrendSummary(
                badgeText: "持平",
                detailText: neutralText.isEmpty ? "当前约 \(currentText)，和前一阶段基本持平。" : neutralText
            )
        }

        let direction = delta > 0 ? trendUpLabel(for: kind) : trendDownLabel(for: kind)
        let amount = delta > 0 ? delta : -delta
        let amountText = trendDeltaText(for: kind, value: amount, previousValue: comparison.previous)
        return HabitTrendSummary(
            badgeText: delta > 0 ? "上升" : "回落",
            detailText: "\(direction)\(amountText)，从 \(previousText) 变到 \(currentText)。"
        )
    }

    func trendAbsoluteThreshold(for kind: HabitBodyMetricKind) -> Double {
        switch kind {
        case .basal, .active:
            return 20
        case .stand, .sunlight:
            return 1
        case .hrv:
            return 3
        case .restingHeartRate:
            return 2
        case .wristTemperature:
            return 0.15
        case .walkingAsymmetry:
            return 0.3
        }
    }

    func trendRelativeThreshold(for kind: HabitBodyMetricKind) -> Double {
        switch kind {
        case .wristTemperature:
            return 0.04
        case .walkingAsymmetry:
            return 0.08
        default:
            return 0.06
        }
    }

    func trendUpLabel(for kind: HabitBodyMetricKind) -> String {
        switch kind {
        case .hrv:
            return "恢复指标走高 "
        case .restingHeartRate:
            return String(localized: "静息基线升高 ")
        case .walkingAsymmetry:
            return String(localized: "步态不对称增加 ")
        case .wristTemperature:
            return String(localized: "夜间体温升高 ")
        default:
            return String(localized: "较前一阶段增加 ")
        }
    }

    func trendDownLabel(for kind: HabitBodyMetricKind) -> String {
        switch kind {
        case .hrv:
            return "恢复指标回落 "
        case .restingHeartRate:
            return String(localized: "静息基线回落 ")
        case .walkingAsymmetry:
            return String(localized: "步态更平衡 ")
        case .wristTemperature:
            return String(localized: "夜间体温回落 ")
        default:
            return String(localized: "较前一阶段下降 ")
        }
    }

    func trendValueText(for kind: HabitBodyMetricKind, value: Double) -> String {
        switch kind {
        case .basal, .active:
            return "\(Int(value.rounded())) kcal"
        case .stand:
            return String(localized: "\(Int(value.rounded())) 小时")
        case .hrv:
            return "\(Int(value.rounded())) ms"
        case .restingHeartRate:
            return "\(Int(value.rounded())) bpm"
        case .sunlight:
            return String(localized: "\(Int(value.rounded())) 分钟")
        case .wristTemperature:
            return String(format: "%.1f℃", value)
        case .walkingAsymmetry:
            return String(format: "%.1f%%", value)
        }
    }

    func trendDeltaText(for kind: HabitBodyMetricKind, value: Double, previousValue: Double) -> String {
        let relative = previousValue > 0 ? abs(value) / previousValue : 0
        switch kind {
        case .basal, .active:
            return "\(Int(value.rounded())) kcal"
        case .stand:
            return String(localized: "\(Int(value.rounded())) 小时")
        case .hrv:
            return "\(Int(value.rounded())) ms"
        case .restingHeartRate:
            return "\(Int(value.rounded())) bpm"
        case .sunlight:
            return String(localized: "\(Int(value.rounded())) 分钟")
        case .wristTemperature:
            return String(format: "%.1f℃", value)
        case .walkingAsymmetry:
            if relative >= 0.1 {
                return "\(Int((relative * 100).rounded()))%"
            }
            return String(format: "%.1f%%", value)
        }
    }

    func trimTrend(_ points: [TimeSeriesPointDouble], endingAt endDate: Date, days: Int) -> [TimeSeriesPointDouble] {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: endDate)
        guard let startDay = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: endDay) else {
            return []
        }
        return points
            .filter {
                let day = calendar.startOfDay(for: $0.date)
                return day >= startDay && day <= endDay
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func calendarFetchRange(anchoredAt date: Date) -> (startDate: Date, endDate: Date, days: Int) {
        let range = visibleRange(for: calendarScope, anchor: date)
        let span = (Calendar.current.dateComponents([.day], from: range.startDate, to: range.endDate).day ?? 0) + 1
        let days = max(7, span)
        return (range.startDate, range.endDate, days)
    }

    func visibleRange(for scope: HabitCalendarScope, anchor: Date) -> (startDate: Date, endDate: Date) {
        let calendar = Calendar.current
        switch scope {
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: anchor)
            let start = interval?.start ?? calendar.startOfDay(for: anchor)
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return (calendar.startOfDay(for: start), calendar.startOfDay(for: end))
        case .month:
            let interval = calendar.dateInterval(of: .month, for: anchor)
            let start = interval?.start ?? calendar.startOfDay(for: anchor)
            let end = calendar.date(byAdding: .day, value: -1, to: interval?.end ?? start) ?? start
            return (calendar.startOfDay(for: start), calendar.startOfDay(for: end))
        }
    }

    func pointsMap(_ points: [TimeSeriesPointDouble]) -> [Date: Double] {
        Dictionary(uniqueKeysWithValues: points.map { (Calendar.current.startOfDay(for: $0.date), $0.value) })
    }

    func buildCalendarDay(
        for date: Date,
        energyMap: [Date: Double],
        exerciseMap: [Date: Double],
        standMap: [Date: Double],
        hrvMap: [Date: Double],
        isInDisplayedMonth: Bool
    ) -> HabitFitnessCalendarDay {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let activeEnergy = Int((energyMap[day] ?? 0).rounded())
        let exerciseMinutes = Int((exerciseMap[day] ?? 0).rounded())
        let standHours = Int((standMap[day] ?? 0).rounded())
        let hrvValue = hrvMap[day]
        let workoutLabel = calendarWorkoutSummaries[day]?.dominantWorkoutTitle
        let record = actionRecordStore.record(for: day)
        let inferredOnly = record.fitnessCheckinMode == nil && (exerciseMinutes > 0 || activeEnergy >= 120)
        let statusText: String
        if let mode = record.fitnessCheckinMode {
            statusText = mode.title
        } else if inferredOnly {
            statusText = "待确认"
        } else if exerciseMinutes > 0 {
            statusText = "有训练"
        } else if activeEnergy > 0 {
            statusText = "有活动"
        } else {
            statusText = "休整"
        }

        let highlightHex: String
        switch (record.fitnessCheckinMode, exerciseMinutes, activeEnergy) {
        case let (.some(mode), _, _):
            highlightHex = mode.tintHex
        case let (_, minutes, _) where minutes >= 45:
            highlightHex = "F06A7B"
        case let (_, minutes, _) where minutes >= 20:
            highlightHex = "F4B46B"
        case (_, _, let energy) where energy >= 250:
            highlightHex = "73C8E8"
        default:
            highlightHex = "D8E2F5"
        }

        return HabitFitnessCalendarDay(
            date: day,
            dayLabel: weekdayShortString(day),
            numberLabel: dayNumberString(day),
            activeEnergyText: activeEnergy > 0 ? "\(activeEnergy)" : "—",
            workoutLabel: workoutLabel,
            statusText: statusText,
            highlightHex: highlightHex,
            isInDisplayedMonth: isInDisplayedMonth,
            isFuture: day > calendar.startOfDay(for: Date()),
            isSelected: calendar.isDate(day, inSameDayAs: selectedDateContext),
            exerciseMinutes: exerciseMinutes,
            activeEnergy: activeEnergy,
            standHours: standHours,
            hrvValue: hrvValue,
            checkinMode: record.fitnessCheckinMode,
            manualWorkoutMinutes: record.manualWorkoutMinutes,
            manualWorkoutEffort: record.manualWorkoutEffort,
            fitnessNote: record.fitnessNote,
            isShared: record.isShared,
            checkedInAt: record.checkedInAt,
            isInferredWorkoutOnly: inferredOnly
        )
    }

    func consecutiveActiveDays(endingAt date: Date, exerciseMap: [Date: Double], energyMap: [Date: Double]) -> Int {
        let calendar = Calendar.current
        var streak = 0
        var cursor = calendar.startOfDay(for: date)

        while true {
            let hasActivity = (exerciseMap[cursor] ?? 0) > 0 || (energyMap[cursor] ?? 0) >= 120
            if !hasActivity { break }
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    func calendarRangeTitle(for scope: HabitCalendarScope, startDate: Date, endDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        switch scope {
        case .week:
            formatter.setLocalizedDateFormatFromTemplate("Md")
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        case .month:
            formatter.dateFormat = "yyyy年M月"
            return formatter.string(from: startDate)
        }
    }

    func intensityScore(for day: HabitFitnessCalendarDay) -> Double {
        let minutes = day.displayWorkoutMinutes
        guard minutes > 0 else { return 0 }
        return Double(day.activeEnergy) / Double(max(minutes, 1))
    }

    func intensityTier(for day: HabitFitnessCalendarDay) -> String {
        let score = intensityScore(for: day)
        switch score {
        case ..<1:
            return String(localized: "轻")
        case ..<4:
            return String(localized: "中")
        default:
            return String(localized: "高")
        }
    }
}
