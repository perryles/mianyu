import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// FitnessCalendarViewModel 成就/徽章/训练记录/共享亮点子模块。
/// 从 FitnessCalendarViewModel+Presentation.swift 再拆分：挑战历史、成就卡、徽章、训练日志、共享亮点。

@MainActor
extension FitnessCalendarViewModel {

    func makeHistoryPreview(_ record: RecoveryChallengeRecord) -> RecoveryChallengeHistoryPreviewItem {
        let definition = record.definition
        let subtitle: String
        switch record.status {
        case .completed:
            subtitle = "连续 \(record.targetDays) 天全部守住"
        case .failed:
            subtitle = "在第 \(max(1, record.currentStreak + 1)) 天失手"
        case .abandoned:
            subtitle = "进行到第 \(max(1, record.currentDayIndex)) 天时结束"
        case .active:
            subtitle = "挑战仍在进行中"
        }

        let finishedAt = record.completedAt ?? record.failedAt ?? record.abandonedAt ?? record.latestRelevantDate
        return RecoveryChallengeHistoryPreviewItem(
            recordID: record.id,
            title: definition.title,
            subtitle: subtitle,
            statusText: record.status.title,
            tintHex: definition.tintHex,
            dateText: ChineseDateText.writtenMonthDay(finishedAt),
            status: record.status,
            kind: record.kind
        )
    }

    func makeAchievementCard(days: [HabitFitnessCalendarDay]) -> FitnessAchievementCardModel {
        let rhythm = rhythmStreak(endingAt: selectedDate)
        let training = trainingStreak(endingAt: selectedDate, exerciseMap: pointsMap(exerciseMinutesTrend), days: days)
        let weeklyDays = weeklyTrainingDays(referenceDate: selectedDate, days: days)
        let today = store.record(for: todayDate)

        let mascotTitle: String
        let mascotSubtitle: String
        let ctaText: String
        switch today.fitnessCheckinMode {
        case .workout:
            mascotTitle = "今天这张卡打得很稳"
            mascotSubtitle = today.hasTrainingNote ? "你已经把今天的训练留痕了，后面回看会很有成就感。" : "要不要顺手补一句备注？后续回看会更有故事感。"
            ctaText = "训练已完成"
        case .recovery:
            mascotTitle = "恢复也算坚持"
            mascotSubtitle = "你没有把节奏断掉，反而是在给下一次训练蓄力。"
            ctaText = "今天是恢复日"
        case .rest:
            mascotTitle = "休息得体，也很专业"
            mascotSubtitle = "节奏不是每天硬冲，知道什么时候收也是训练的一部分。"
            ctaText = "今天是休息日"
        case nil:
            mascotTitle = "今天准备开练了吗？"
            mascotSubtitle = "先点一次打卡，把今天的训练节奏立住。"
            ctaText = "今天还没打卡"
        }

        return FitnessAchievementCardModel(
            rhythmStreak: rhythm,
            trainingStreak: training,
            weeklyTrainingDays: weeklyDays,
            weeklyGoal: 4,
            todayMode: today.fitnessCheckinMode,
            mascotTitle: mascotTitle,
            mascotSubtitle: mascotSubtitle,
            ctaText: ctaText
        )
    }

    func makeBadges() -> [FitnessBadgeModel] {
        let all = store.allRecords()
        let workoutDays = all.filter { $0.fitnessCheckinMode == .workout }
        let notedWorkoutCount = workoutDays.filter(\.hasTrainingNote).count
        let currentRhythm = rhythmStreak(endingAt: selectedDate)
        let weekGoalHit = weeklyTrainingDays(referenceDate: selectedDate, days: calendarModel.days) >= 4
        let highIntensityUnlocked = workoutDays.contains { $0.manualWorkoutEffort == .hard } || calendarModel.days.contains { intensityScore(for: $0) >= 4 && $0.displayWorkoutMinutes >= 20 }

        return [
            FitnessBadgeModel(id: "first", title: "第一次开练", subtitle: "完成一次训练打卡", symbol: "star.fill", tintHex: "F4B46B", isUnlocked: !workoutDays.isEmpty),
            FitnessBadgeModel(id: "three", title: "三日连击", subtitle: "训练连续 3 天", symbol: "bolt.fill", tintHex: "58CC6A", isUnlocked: trainingStreak(endingAt: selectedDate, exerciseMap: pointsMap(exerciseMinutesTrend), days: calendarModel.days) >= 3),
            FitnessBadgeModel(id: "seven", title: "七日节奏", subtitle: "节奏连续 7 天", symbol: "flame.fill", tintHex: "FF8A5B", isUnlocked: currentRhythm >= 7),
            FitnessBadgeModel(id: "week-goal", title: "周目标达成", subtitle: "单周 4 个训练日", symbol: "calendar.circle.fill", tintHex: "73C8E8", isUnlocked: weekGoalHit),
            FitnessBadgeModel(id: "intensity", title: "强度突破", subtitle: "完成一次高强度训练", symbol: "hare.fill", tintHex: "F06A7B", isUnlocked: highIntensityUnlocked),
            FitnessBadgeModel(id: "notes", title: "记录习惯养成", subtitle: "写下 5 条训练备注", symbol: "text.badge.checkmark", tintHex: "2AA7A1", isUnlocked: notedWorkoutCount >= 5)
        ]
    }

    func makeTrainingLogs(days: [HabitFitnessCalendarDay]) -> [FitnessTrainingLogItem] {
        let recentDates = (0..<30).compactMap { calendar.date(byAdding: .day, value: -$0, to: selectedDate) }
            .map { calendar.startOfDay(for: $0) }
        return recentDates.compactMap { dayDate in
            let record = store.record(for: dayDate)
            let relatedDay = days.first(where: { calendar.isDate($0.date, inSameDayAs: dayDate) }) ?? buildDetachedDay(for: record)
            let hasConfirmedTraining =
                record.fitnessCheckinMode == .workout ||
                record.manualWorkoutMinutes > 0 ||
                relatedDay.exerciseMinutes > 0

            guard hasConfirmedTraining else { return nil }

            let title = relatedDay.workoutLabel ?? record.fitnessCheckinMode?.title ?? "系统记录到训练"
            let subtitle = ChineseDateText.writtenMonthDay(dayDate)
            let duration = max(record.manualWorkoutMinutes, relatedDay.exerciseMinutes)
            let statsParts: [String] = [
                duration > 0 ? "\(duration) 分钟" : nil,
                relatedDay.activeEnergy > 0 ? "\(relatedDay.activeEnergy) kcal" : nil,
                record.manualWorkoutEffort?.title
            ].compactMap { $0 }

            return FitnessTrainingLogItem(
                date: dayDate,
                mode: record.fitnessCheckinMode,
                title: title,
                subtitle: subtitle,
                statsLine: statsParts.isEmpty ? "这一天有训练样本，可手动补充模式和备注" : statsParts.joined(separator: " · "),
                note: record.fitnessNote,
                isShared: record.isShared,
                day: relatedDay
            )
        }
    }

    func makeSharedHighlights(days: [HabitFitnessCalendarDay]) -> [FitnessSharedHighlightItem] {
        let visible = visibleDays(from: days)
        let longestDay = visible.max {
            if $0.displayWorkoutMinutes == $1.displayWorkoutMinutes {
                return $0.activeEnergy < $1.activeEnergy
            }
            return $0.displayWorkoutMinutes < $1.displayWorkoutMinutes
        }

        let recentDates = (0..<21).compactMap { calendar.date(byAdding: .day, value: -$0, to: selectedDate) }
            .map { calendar.startOfDay(for: $0) }

        let candidates: [HabitFitnessCalendarDay] = recentDates.compactMap { dayDate in
            let record = store.record(for: dayDate)
            let relatedDay = days.first(where: { calendar.isDate($0.date, inSameDayAs: dayDate) }) ?? buildDetachedDay(for: record)
            let hasTrainingSignal =
                relatedDay.displayWorkoutMinutes > 0 ||
                relatedDay.activeEnergy > 0 ||
                record.fitnessCheckinMode != nil ||
                record.hasTrainingNote
            return hasTrainingSignal ? relatedDay : nil
        }

        let prioritizedShared = candidates.filter(\.isShared)
        var result: [HabitFitnessCalendarDay] = Array(prioritizedShared.prefix(3))
        if result.count < 3 {
            for day in candidates where !result.contains(where: { calendar.isDate($0.date, inSameDayAs: day.date) }) {
                result.append(day)
                if result.count == 3 { break }
            }
        }

        return result.map { day in
            let title = day.checkinMode?.title ?? (day.isInferredWorkoutOnly ? "系统记录到训练" : "最近活动亮点")
            let subtitle = [
                day.displayWorkoutMinutes > 0 ? "\(day.displayWorkoutMinutes) 分钟" : nil,
                day.activeEnergy > 0 ? "\(day.activeEnergy) kcal" : nil,
                day.manualWorkoutEffort?.title
            ]
            .compactMap { $0 }
            .joined(separator: " · ")

            let badgeText: String
            let tintHex: String
            if day.isShared {
                badgeText = "已共享"
                tintHex = "2AA7A1"
            } else if day.manualWorkoutEffort == .hard {
                badgeText = "高强度"
                tintHex = "F06A7B"
            } else if let longestDay, calendar.isDate(longestDay.date, inSameDayAs: day.date), longestDay.displayWorkoutMinutes > 0 {
                badgeText = "最长一练"
                tintHex = "73C8E8"
            } else if day.isInferredWorkoutOnly {
                badgeText = "待补卡"
                tintHex = "F4B46B"
            } else {
                badgeText = "最近记录"
                tintHex = day.checkinMode?.tintHex ?? "58CC6A"
            }

            return FitnessSharedHighlightItem(
                date: day.date,
                title: title,
                subtitle: subtitle.isEmpty ? "这一天有活动或训练信号，建议点开补全记录。" : subtitle,
                badgeText: badgeText,
                tintHex: tintHex,
                day: day
            )
        }
    }

}
