import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// FitnessCalendarViewModel 选中日详情子模块。
/// 从 FitnessCalendarViewModel+Presentation.swift 再拆分：详情模型、脱离日历的单日构建、详情文案。

@MainActor
extension FitnessCalendarViewModel {

    func refreshSelectedDetailIfNeeded(for date: Date) {
        guard let selectedDetail,
              calendar.isDate(selectedDetail.date, inSameDayAs: date) else {
            return
        }

        let normalized = calendar.startOfDay(for: date)
        let day = calendarModel.days.first { calendar.isDate($0.date, inSameDayAs: normalized) }
            ?? buildDetachedDay(for: store.record(for: normalized))
        self.selectedDetail = makeDetailModel(for: day)
    }

    func makeSelectedDayContext(days: [HabitFitnessCalendarDay]) -> FitnessSelectedDayContextModel {
        let day = days.first(where: { $0.isSelected }) ?? selectedCalendarDay
        let title = day.map { ChineseDateText.writtenMonthDay($0.date) } ?? ChineseDateText.writtenMonthDay(selectedDate)
        let recovery = day.map(recoveryScore(for:)) ?? 0
        let load = day.map(trainingLoadScore(for:)) ?? 0
        let statusText = day?.checkinMode?.title ?? (day?.isInferredWorkoutOnly == true ? "识别到活动" : "等待打卡")
        let accentHex = day?.highlightHex ?? "58CC6A"

        let summaryText: String
        if let day {
            if day.displayWorkoutMinutes > 0 {
                summaryText = "\(statusText) · \(day.displayWorkoutMinutes) 分钟 · 恢复 \(recovery) 分"
            } else if day.checkinMode == .recovery {
                summaryText = "今天偏恢复节奏，适合把训练压力放轻一点。"
            } else if day.checkinMode == .rest {
                summaryText = "今天是休息日，恢复本身也是节律的一部分。"
            } else {
                summaryText = "这一天还没有明确训练记录，可以补充训练、恢复或休息状态。"
            }
        } else {
            summaryText = "先选中一天，健身节律会把训练、恢复和负荷放在一起看。"
        }
        let trainingMinutes = day?.displayWorkoutMinutes ?? 0
        let activeEnergy = day?.activeEnergy ?? 0

        return FitnessSelectedDayContextModel(
            date: day?.date ?? selectedDate,
            title: title,
            statusText: statusText,
            summaryText: summaryText,
            trainingText: trainingMinutes > 0 ? "\(trainingMinutes) 分" : "--",
            energyText: activeEnergy > 0 ? "\(activeEnergy) kcal" : "--",
            recoveryText: recovery > 0 ? "\(recovery) 分" : "--",
            loadText: load > 0 ? "\(load) 分" : "--",
            accentHex: accentHex,
            isShared: day?.isShared ?? false,
            day: day
        )
    }

    func makeDetailModel(for day: HabitFitnessCalendarDay) -> ActionDayDetailModel {
        let hrvText = day.hrvValue.map { "\((Int($0.rounded()))) ms" } ?? "暂无"
        let workoutSummary = workoutSummaries[calendar.startOfDay(for: day.date)]
        let workoutTitle = workoutSummary?.dominantWorkoutTitle
            ?? (day.checkinMode?.title ?? "综合活动")
        let trendPoints = exerciseMinutesTrend
            .filter { calendar.isDate($0.date, equalTo: day.date, toGranularity: .weekOfYear) }
            .filter { $0.value > 0 }
            .map { HabitTrendPoint(date: $0.date, value: $0.value) }

        let summary: String
        if day.checkinMode == .workout || day.displayWorkoutMinutes > 0 {
            summary = "\(workoutTitle) · \(day.displayWorkoutMinutes) 分钟 · \(day.activeEnergy) kcal"
        } else if day.checkinMode == .recovery {
            summary = "今天以轻恢复为主，保住了节奏连续。"
        } else if day.checkinMode == .rest {
            summary = "今天是计划休整日，作为节律缓冲很合适。"
        } else if day.activeEnergy > 0 {
            summary = "系统识别到活动，但你还没有手动确认今天的训练模式。"
        } else {
            summary = "当天暂无明显训练记录。"
        }

        var statusTags: [ActionDayDetailStatusTag] = [
            ActionDayDetailStatusTag(
                title: day.checkinMode?.title ?? (day.isInferredWorkoutOnly ? "识别到活动" : "未打卡"),
                tintHex: day.checkinMode?.tintHex ?? (day.isInferredWorkoutOnly ? "F4B46B" : "94A3C3")
            )
        ]
        if day.displayWorkoutMinutes > 0 {
            statusTags.append(ActionDayDetailStatusTag(title: "\(day.displayWorkoutMinutes) 分钟", tintHex: "58CC6A"))
        }
        if day.activeEnergy > 0 {
            statusTags.append(ActionDayDetailStatusTag(title: "\(day.activeEnergy) kcal", tintHex: "F4B46B"))
        }
        if let effort = day.manualWorkoutEffort {
            statusTags.append(ActionDayDetailStatusTag(title: effort.title, tintHex: effort.tintHex))
        }

        let insightText = detailInsightText(for: day, trendPoints: trendPoints)
        let distance = workoutSummary?.totalDistanceKilometers ?? 0
        let pace = distance > 0
            ? Double(workoutSummary?.totalMinutes ?? day.displayWorkoutMinutes) / distance
            : nil

        // 距离、心情等编辑字段直接取本地记录，保证详情页回显最新保存值。
        let localRecord = store.record(for: day.date)

        return ActionDayDetailModel(
            date: day.date,
            title: ChineseDateText.writtenMonthDay(day.date),
            workoutTitle: workoutTitle,
            movementSummary: summary,
            statItems: [
                ActionDayDetailStatItem(title: "打卡", valueText: day.checkinMode?.shortTitle ?? "未打卡", tintHex: day.checkinMode?.tintHex ?? "94A3C3"),
                ActionDayDetailStatItem(title: "训练", valueText: day.displayWorkoutMinutes > 0 ? "\(day.displayWorkoutMinutes) 分钟" : "暂无", tintHex: "58CC6A"),
                ActionDayDetailStatItem(title: "消耗", valueText: day.activeEnergy > 0 ? "\(day.activeEnergy) kcal" : "暂无", tintHex: "F4B46B"),
                ActionDayDetailStatItem(title: "HRV", valueText: hrvText, tintHex: "DE5B84")
            ],
            statusTags: statusTags,
            trendPoints: trendPoints,
            insightText: insightText,
            isShared: day.isShared,
            checkinMode: day.checkinMode,
            manualWorkoutMinutes: day.manualWorkoutMinutes,
            manualWorkoutDistanceKm: localRecord.manualWorkoutDistanceKm,
            manualWorkoutEffort: day.manualWorkoutEffort,
            dailyMood: localRecord.dailyMood,
            fitnessNote: day.fitnessNote,
            checkedInAt: day.checkedInAt,
            trainingLoadScore: trainingLoadScore(for: day),
            recoveryScore: recoveryScore(for: day),
            workoutCount: workoutSummary?.workoutCount,
            distanceKilometers: distance > 0 ? distance : nil,
            averagePaceText: pace.map(Self.paceText),
            swimmingReport: workoutSummary?.swimmingReport,
            workoutReportKind: workoutSummary.map { _ in WorkoutReportKind.recognized(from: workoutTitle) }
        )
    }

    func buildDetachedDay(for record: LocalActionDayRecord) -> HabitFitnessCalendarDay {
        let key = calendar.startOfDay(for: record.date)
        let activeEnergy = Int((pointsMap(activeEnergyTrend)[key] ?? 0).rounded())
        let exercise = Int((pointsMap(exerciseMinutesTrend)[key] ?? 0).rounded())
        let stand = Int((pointsMap(standHoursTrend)[key] ?? 0).rounded())
        let hrv = pointsMap(hrvTrend)[key]
        return HabitFitnessCalendarDay(
            date: key,
            dayLabel: weekdayShortString(key),
            numberLabel: dayNumberString(key),
            activeEnergyText: activeEnergy > 0 ? "\(activeEnergy)" : "—",
            workoutLabel: workoutSummaries[key]?.dominantWorkoutTitle,
            statusText: "记录",
            highlightHex: record.fitnessCheckinMode?.tintHex ?? "D8E2F5",
            isInDisplayedMonth: true,
            isFuture: false,
            isSelected: calendar.isDate(key, inSameDayAs: selectedDate),
            exerciseMinutes: exercise,
            activeEnergy: activeEnergy,
            standHours: stand,
            hrvValue: hrv,
            checkinMode: record.fitnessCheckinMode,
            manualWorkoutMinutes: record.manualWorkoutMinutes,
            manualWorkoutEffort: record.manualWorkoutEffort,
            fitnessNote: record.fitnessNote,
            isShared: record.isShared,
            checkedInAt: record.checkedInAt,
            isInferredWorkoutOnly: record.fitnessCheckinMode == nil && (exercise > 0 || activeEnergy >= 120)
        )
    }

    func detailInsightText(for day: HabitFitnessCalendarDay, trendPoints: [HabitTrendPoint]) -> String {
        guard !trendPoints.isEmpty else {
            return String(localized: "这段时间还没有足够的训练样本，等后续再同步几天，你会更容易看出这一天在整周训练里的位置。")
        }

        let currentValue = Double(day.displayWorkoutMinutes)
        let maxValue = trendPoints.map(\.value).max() ?? 0
        let average = trendPoints.reduce(0) { $0 + $1.value } / Double(max(trendPoints.count, 1))

        if currentValue > 0, abs(currentValue - maxValue) < 0.5 {
            return String(localized: "这是本周训练量最高的一天，适合作为这周节奏和恢复安排的参照点。")
        }
        if currentValue > average {
            return String(localized: "今天高于本周平均训练量，说明这一天承担了更明显的训练刺激。")
        }
        if currentValue > 0 {
            return String(localized: "今天更像补节奏的一练，虽然不是峰值日，但对维持连续训练很有帮助。")
        }
        return String(localized: "这一天没有明确训练分钟，更像是恢复或过渡日，可以结合前后几天一起回看。")
    }

}
