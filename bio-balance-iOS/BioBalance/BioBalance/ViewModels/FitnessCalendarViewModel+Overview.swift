import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// FitnessCalendarViewModel 概览与统计卡片子模块。
/// 从 FitnessCalendarViewModel+Presentation.swift 再拆分：统计卡片、训练概览。

@MainActor
extension FitnessCalendarViewModel {

    func makeStatsCards(days: [HabitFitnessCalendarDay]) -> [HabitFitnessStatsCardModel] {
        let visible = days.filter { calendarScope == .week || $0.isInDisplayedMonth }
        let totalMinutes = visible.reduce(0) { $0 + $1.displayWorkoutMinutes }
        let totalTrainingDays = visible.filter { $0.checkinMode == .workout || $0.isInferredWorkoutOnly }.count
        let highestIntensityDay = visible.max { intensityScore(for: $0) < intensityScore(for: $1) }
        let longestDay = visible.max { $0.displayWorkoutMinutes < $1.displayWorkoutMinutes }
        let weekGoal = 4

        return [
            HabitFitnessStatsCardModel(
                id: "minutes",
                title: "训练分钟",
                valueText: "\(totalMinutes) 分钟",
                detailText: calendarScope == .week ? "本周节奏目标 150 分钟" : "本月持续累积",
                progress: calendarScope == .week ? min(1, Double(totalMinutes) / 150) : nil,
                tintHex: "58CC6A",
                symbol: "figure.run"
            ),
            HabitFitnessStatsCardModel(
                id: "days",
                title: "训练天数",
                valueText: "\(totalTrainingDays) 天",
                detailText: calendarScope == .week ? "本周目标 \(weekGoal) 天" : "保持每周 4 天的节奏",
                progress: calendarScope == .week ? min(1, Double(totalTrainingDays) / Double(weekGoal)) : nil,
                tintHex: "2AA7A1",
                symbol: "calendar.badge.clock"
            ),
            HabitFitnessStatsCardModel(
                id: "longest",
                title: "最长一练",
                valueText: longestDay.map { "\($0.displayWorkoutMinutes) 分钟" } ?? "暂无",
                detailText: longestDay.map { ChineseDateText.writtenMonthDay($0.date) } ?? "等第一条记录出现",
                progress: nil,
                tintHex: "73C8E8",
                symbol: "timer"
            ),
            HabitFitnessStatsCardModel(
                id: "intensity",
                title: "最高强度",
                valueText: highestIntensityDay.map(intensityTier(for:)) ?? "暂无",
                detailText: highestIntensityDay.map { "\($0.activeEnergy) kcal / \(max(1, $0.displayWorkoutMinutes)) 分钟" } ?? "等样本同步",
                progress: nil,
                tintHex: "F4B46B",
                symbol: "flame.fill"
            )
        ]
    }

    func makeOverviewModel(days: [HabitFitnessCalendarDay]) -> FitnessOverviewModel {
        let visible = visibleDays(from: days)
        let trainingDays = visible.filter { $0.checkinMode == .workout || $0.isInferredWorkoutOnly }
        let totalMinutes = visible.reduce(0) { $0 + $1.displayWorkoutMinutes }
        let totalEnergy = visible.reduce(0) { $0 + $1.activeEnergy }
        let averageMinutes = trainingDays.isEmpty ? nil : Int((Double(totalMinutes) / Double(trainingDays.count)).rounded())
        let bestDay = visible.max {
            if $0.displayWorkoutMinutes == $1.displayWorkoutMinutes {
                return $0.activeEnergy < $1.activeEnergy
            }
            return $0.displayWorkoutMinutes < $1.displayWorkoutMinutes
        }
        let manualWorkoutCount = visible.filter { $0.checkinMode == .workout }.count
        let title = calendarScope == .week ? "本周训练摘要" : "本月训练摘要"

        let subtitle: String
        if trainingDays.isEmpty && totalEnergy == 0 {
            subtitle = calendarScope == .week
                ? "这周还没有形成明显训练记录，先打一张卡，后面这里就会开始累计结果。"
                : "这个月还没有形成明显训练记录，等你开始训练后，这里会自动整理整月节奏。"
        } else if totalMinutes > 0 {
            subtitle = "\(calendarScope == .week ? "本周" : "本月")完成 \(trainingDays.count) 天训练，累计 \(totalMinutes) 分钟，\(trainingDays.count >= targetTrainingDays ? "节奏保持稳定" : "已经开始进入状态")"
        } else {
            subtitle = "\(calendarScope == .week ? "本周" : "本月")已有 \(totalEnergy) kcal 活动消耗，说明身体在动，但结构化训练还可以更明确。"
        }

        let bestDayText: String
        if let bestDay, bestDay.displayWorkoutMinutes > 0 || bestDay.activeEnergy > 0 {
            let minutesText = bestDay.displayWorkoutMinutes > 0 ? "\(bestDay.displayWorkoutMinutes) 分钟" : "待补训练"
            let energyText = bestDay.activeEnergy > 0 ? "\(bestDay.activeEnergy) kcal" : "低消耗"
            bestDayText = "最佳一天：\(ChineseDateText.writtenMonthDay(bestDay.date)) · \(minutesText) · \(energyText)"
        } else {
            bestDayText = "最佳一天：等第一条像样的训练记录出现"
        }

        let coachTip: String
        if totalMinutes >= targetMinutes && trainingDays.count >= targetTrainingDays {
            coachTip = "这段时间的总量和频率都在线，可以继续按现在的节奏推进，重点是别让高质量训练断档。"
        } else if totalMinutes > 0 && manualWorkoutCount < trainingDays.count {
            coachTip = "系统已经识别到部分训练，但手动打卡还不够完整，补上模式和备注后，回看价值会明显更高。"
        } else {
            let missingMinutes = max(0, targetMinutes - totalMinutes)
            let missingDays = max(0, targetTrainingDays - trainingDays.count)
            if missingMinutes == 0 && missingDays > 0 {
                coachTip = "总分钟已经不差，接下来更值得把训练分布铺开一些，再补 \(missingDays) 天会更稳。"
            } else if missingDays == 0 && missingMinutes > 0 {
                coachTip = "训练天数已经够了，后面再补 \(missingMinutes) 分钟左右，这一段的训练质量会更完整。"
            } else {
                coachTip = "这一段离目标还差 \(missingDays) 天、约 \(missingMinutes) 分钟，哪怕先补一练，也比继续留空更容易把节奏接住。"
            }
        }

        return FitnessOverviewModel(
            title: title,
            subtitle: subtitle,
            bestDayText: bestDayText,
            coachTip: coachTip,
            statItems: [
                FitnessOverviewStatItem(id: "days", title: "训练天数", valueText: "\(trainingDays.count) 天", tintHex: "58CC6A", symbol: "calendar"),
                FitnessOverviewStatItem(id: "minutes", title: "训练分钟", valueText: "\(totalMinutes) 分钟", tintHex: "73C8E8", symbol: "timer"),
                FitnessOverviewStatItem(id: "energy", title: "总消耗", valueText: "\(totalEnergy) kcal", tintHex: "F4B46B", symbol: "flame.fill"),
                FitnessOverviewStatItem(id: "average", title: "日均训练", valueText: averageMinutes.map { "\($0) 分钟" } ?? "--", tintHex: "2AA7A1", symbol: "chart.bar.fill")
            ]
        )
    }

}
