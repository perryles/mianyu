import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// FitnessCalendarViewModel 日历/节奏/连续天数构建子模块。
/// 从 FitnessCalendarViewModel+Presentation.swift 再拆分：日历构建、可见范围、节奏/训练连续、目标参考值。
/// 对外接口不变；跨文件访问的 private 成员提升为 internal。

@MainActor
extension FitnessCalendarViewModel {

    func makeCheckinOpeningModel(days: [HabitFitnessCalendarDay]) -> FitnessCheckinOpeningModel {
        let monthRange = visibleRange(for: .month, anchor: selectedDate)
        let monthDays = buildOpeningMonthDays(startDate: monthRange.startDate)
        let currentStreak = rhythmStreak(endingAt: todayDate)
        let longestStreak = longestRhythmStreak()
        let allRhythmDates = store.allRecords()
            .filter { $0.fitnessCheckinMode?.countsForRhythm == true }
            .map { calendar.startOfDay(for: $0.date) }
            .sorted()
        let startDate = allRhythmDates.first ?? todayDate
        let todayRecord = store.record(for: todayDate)

        return FitnessCheckinOpeningModel(
            currentStreak: currentStreak,
            longestStreak: max(longestStreak, currentStreak),
            startDate: startDate,
            monthTitle: calendarRangeTitle(for: .month, startDate: monthRange.startDate, endDate: monthRange.endDate),
            todayStatusTitle: todayRecord.fitnessCheckinMode?.title ?? "待打卡",
            todayMode: todayRecord.fitnessCheckinMode,
            days: monthDays
        )
    }

    func buildOpeningMonthDays(startDate: Date) -> [HabitFitnessCalendarDay] {
        let firstWeekday = calendar.component(.weekday, from: startDate)
        let leadingCount = max(0, firstWeekday - calendar.firstWeekday)
        let adjustedLeadingCount = leadingCount < 0 ? leadingCount + 7 : leadingCount
        let monthDays = calendar.range(of: .day, in: .month, for: startDate)?.count ?? 30
        let totalVisibleDays = adjustedLeadingCount + monthDays
        let trailingCount = totalVisibleDays % 7 == 0 ? 0 : 7 - (totalVisibleDays % 7)
        let energyMap = pointsMap(activeEnergyTrend)
        let exerciseMap = pointsMap(exerciseMinutesTrend)
        let standMap = pointsMap(standHoursTrend)
        let hrvMap = pointsMap(hrvTrend)

        return (0..<(totalVisibleDays + trailingCount)).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index - adjustedLeadingCount, to: startDate) else { return nil }
            return buildCalendarDay(
                for: date,
                energyMap: energyMap,
                exerciseMap: exerciseMap,
                standMap: standMap,
                hrvMap: hrvMap,
                isInDisplayedMonth: calendar.isDate(date, equalTo: startDate, toGranularity: .month)
            )
        }
    }

    func makeCalendarModel() -> HabitFitnessCalendarModel {
        let range = visibleRange(for: calendarScope, anchor: selectedDate)
        let energyMap = pointsMap(activeEnergyTrend)
        let exerciseMap = pointsMap(exerciseMinutesTrend)
        let standMap = pointsMap(standHoursTrend)
        let hrvMap = pointsMap(hrvTrend)

        let days: [HabitFitnessCalendarDay]
        switch calendarScope {
        case .week:
            days = (0..<7).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: range.startDate) else { return nil }
                return buildCalendarDay(for: day, energyMap: energyMap, exerciseMap: exerciseMap, standMap: standMap, hrvMap: hrvMap, isInDisplayedMonth: true)
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
                built.append(
                    buildCalendarDay(
                        for: day,
                        energyMap: energyMap,
                        exerciseMap: exerciseMap,
                        standMap: standMap,
                        hrvMap: hrvMap,
                        isInDisplayedMonth: calendar.isDate(day, equalTo: range.startDate, toGranularity: .month)
                    )
                )
            }
            days = built
        }

        let rhythmStreak = rhythmStreak(endingAt: selectedDate)
        let trainingStreak = trainingStreak(endingAt: selectedDate, exerciseMap: exerciseMap, days: days)
        let visible = days.filter { calendarScope == .week || $0.isInDisplayedMonth }
        let totalMinutes = visible.reduce(0) { $0 + $1.displayWorkoutMinutes }

        return HabitFitnessCalendarModel(
            scope: calendarScope,
            rangeTitle: calendarRangeTitle(for: calendarScope, startDate: range.startDate, endDate: range.endDate),
            streakText: rhythmStreak > 0 ? "节奏连续 \(rhythmStreak) 天 · 训练连续 \(trainingStreak) 天" : "从今天开始建立你的训练节奏",
            summaryPills: [
                "节奏 \(rhythmStreak) 天",
                "训练 \(trainingStreak) 天",
                "本段 \(totalMinutes) 分钟"
            ],
            days: days
        )
    }

    func visibleRange(for scope: HabitCalendarScope, anchor: Date) -> (startDate: Date, endDate: Date) {
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

    func calendarFetchRange(anchoredAt date: Date) -> (startDate: Date, endDate: Date, days: Int) {
        let range = visibleRange(for: calendarScope, anchor: date)
        let recentStart = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: date)) ?? range.startDate
        let fetchStart = min(range.startDate, recentStart)
        let span = (calendar.dateComponents([.day], from: fetchStart, to: range.endDate).day ?? 0) + 1
        return (fetchStart, range.endDate, max(span, 35))
    }

    func pointsMap(_ points: [TimeSeriesPointDouble]) -> [Date: Double] {
        Dictionary(uniqueKeysWithValues: points.map { (calendar.startOfDay(for: $0.date), $0.value) })
    }

    func visibleDays(from days: [HabitFitnessCalendarDay]) -> [HabitFitnessCalendarDay] {
        days.filter { calendarScope == .week || $0.isInDisplayedMonth }
    }

    func recentDays(from days: [HabitFitnessCalendarDay], count: Int) -> [HabitFitnessCalendarDay] {
        recentDays(endingAt: selectedDate, from: days, count: count)
    }

    func recentDays(endingAt endDate: Date, from days: [HabitFitnessCalendarDay], count: Int) -> [HabitFitnessCalendarDay] {
        let visible = visibleDays(from: days).sorted { $0.date < $1.date }
        let end = calendar.startOfDay(for: endDate)
        let visibleThroughEnd = visible.filter { $0.date <= end }
        if visibleThroughEnd.count >= count {
            return Array(visibleThroughEnd.suffix(count))
        }

        let generated = (0..<count).compactMap { offset -> HabitFitnessCalendarDay? in
            guard let date = calendar.date(byAdding: .day, value: -(count - 1 - offset), to: end) else { return nil }
            let normalized = calendar.startOfDay(for: date)
            if let day = visible.first(where: { calendar.isDate($0.date, inSameDayAs: normalized) }) {
                return day
            }
            let record = store.record(for: normalized)
            return buildDetachedDay(for: record)
        }
        return generated
    }

    func buildCalendarDay(
        for date: Date,
        energyMap: [Date: Double],
        exerciseMap: [Date: Double],
        standMap: [Date: Double],
        hrvMap: [Date: Double],
        isInDisplayedMonth: Bool
    ) -> HabitFitnessCalendarDay {
        let day = calendar.startOfDay(for: date)
        let record = store.record(for: day)
        let activeEnergy = Int((energyMap[day] ?? 0).rounded())
        let exerciseMinutes = Int((exerciseMap[day] ?? 0).rounded())
        let standHours = Int((standMap[day] ?? 0).rounded())
        let inferredOnly = record.fitnessCheckinMode == nil && exerciseMinutes > 0

        let statusText: String
        if let mode = record.fitnessCheckinMode {
            statusText = mode.title
        } else if inferredOnly {
            statusText = "待确认"
        } else {
            statusText = "未打卡"
        }

        let highlightHex = record.fitnessCheckinMode?.tintHex
            ?? (inferredOnly ? "F4B46B" : activeEnergy >= 250 ? "73C8E8" : "D8E2F5")

        return HabitFitnessCalendarDay(
            date: day,
            dayLabel: weekdayShortString(day),
            numberLabel: dayNumberString(day),
            activeEnergyText: activeEnergy > 0 ? "\(activeEnergy)" : "—",
            workoutLabel: workoutSummaries[day]?.dominantWorkoutTitle,
            statusText: statusText,
            highlightHex: highlightHex,
            isInDisplayedMonth: isInDisplayedMonth,
            isFuture: day > calendar.startOfDay(for: Date()),
            isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
            exerciseMinutes: exerciseMinutes,
            activeEnergy: activeEnergy,
            standHours: standHours,
            hrvValue: hrvMap[day],
            checkinMode: record.fitnessCheckinMode,
            manualWorkoutMinutes: record.manualWorkoutMinutes,
            manualWorkoutEffort: record.manualWorkoutEffort,
            fitnessNote: record.fitnessNote,
            isShared: record.isShared,
            checkedInAt: record.checkedInAt,
            isInferredWorkoutOnly: inferredOnly
        )
    }

    func rhythmStreak(endingAt date: Date) -> Int {
        var streak = 0
        var cursor = calendar.startOfDay(for: date)
        while true {
            let record = store.record(for: cursor)
            guard record.fitnessCheckinMode?.countsForRhythm == true else { break }
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    func longestRhythmStreak() -> Int {
        let rhythmDates = Set(
            store.allRecords()
                .filter { $0.fitnessCheckinMode?.countsForRhythm == true }
                .map { calendar.startOfDay(for: $0.date) }
        )
        guard !rhythmDates.isEmpty else { return 0 }

        var longest = 0
        var cursor = rhythmDates.min() ?? todayDate
        let last = max(rhythmDates.max() ?? cursor, todayDate)
        var running = 0

        while cursor <= last {
            if rhythmDates.contains(cursor) {
                running += 1
                longest = max(longest, running)
            } else {
                running = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: next)
        }
        return longest
    }

    func trainingStreak(endingAt date: Date, exerciseMap: [Date: Double], days: [HabitFitnessCalendarDay]) -> Int {
        var streak = 0
        var cursor = calendar.startOfDay(for: date)
        while true {
            let record = store.record(for: cursor)
            let inferred = (exerciseMap[cursor] ?? 0) > 0 || (days.first(where: { calendar.isDate($0.date, inSameDayAs: cursor) })?.activeEnergy ?? 0) >= 120
            let qualifies = record.fitnessCheckinMode?.countsForTraining == true || inferred
            if !qualifies { break }
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    func weeklyTrainingDays(referenceDate: Date, days: [HabitFitnessCalendarDay]) -> Int {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start ?? calendar.startOfDay(for: referenceDate)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return allTrainingDays().filter { $0 >= weekStart && $0 <= weekEnd }.count
    }

    var targetMinutes: Int {
        calendarScope == .week ? 150 : 600
    }

    var targetTrainingDays: Int {
        calendarScope == .week ? 4 : 16
    }

    func allTrainingDays() -> [Date] {
        store.allRecords()
            .filter { $0.fitnessCheckinMode == .workout }
            .map { calendar.startOfDay(for: $0.date) }
    }

    // MARK: 迷你运动月历

    /// 迷你月历独立于主日历 scope 的月份锚点，初始跟随选中日。
    var miniMonthDisplayedMonth: Date {
        miniMonthAnchor ?? calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
    }

    func shiftMiniMonthCalendar(by step: Int) {
        guard let newDate = calendar.date(byAdding: .month, value: step, to: miniMonthDisplayedMonth) else { return }
        playSelectionFeedback()
        miniMonthAnchor = calendar.dateInterval(of: .month, for: newDate)?.start ?? newDate
        // 翻到趋势窗口（约 60 天）覆盖不到的更早月份时，按新锚点补拉数据。
        let windowStart = calendar.date(byAdding: .day, value: -60, to: todayDate) ?? todayDate
        let monthStart = miniMonthAnchor ?? newDate
        if monthStart < calendar.startOfDay(for: windowStart) {
            load(for: newDate)
        }
    }

}
