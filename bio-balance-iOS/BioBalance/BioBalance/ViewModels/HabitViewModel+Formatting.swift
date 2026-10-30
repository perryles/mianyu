import SwiftUI

/// HabitViewModel 格式化与建议域 子模块。
/// 从原 HabitViewModel.swift 拆出，对外接口不变。

@MainActor
extension HabitViewModel {

    func fitnessRecoveryInsight(for day: HabitFitnessCalendarDay?) -> FitnessRecoveryInsightModel {
        guard let day else {
            return FitnessRecoveryInsightModel(
                title: "恢复线索待建立",
                statusText: "等待同步",
                detailText: "同步到 HRV、训练和活动样本后，这里会开始给出当天训练节律与恢复线索。",
                accentHex: "7D90FF"
            )
        }

        if let hrv = day.hrvValue, hrv > 0 {
            let status = hrvStatusText(hrv)
            if day.exerciseMinutes >= 45 && hrv < 35 {
                return FitnessRecoveryInsightModel(
                    title: "建议优先恢复管理",
                    statusText: status,
                    detailText: "当日训练负荷较为明确，但恢复信号仍偏紧。后续更建议优先关注睡眠、轻量活动与节律稳定性。",
                    accentHex: "F06A7B"
                )
            }

            if day.exerciseMinutes >= 20 {
                return FitnessRecoveryInsightModel(
                    title: "训练节律可继续维持",
                    statusText: status,
                    detailText: "当日同时具备训练与恢复样本，当前更适合继续观察训练量与恢复反馈的连续性，而不宜仅依据单次表现判断。",
                    accentHex: hrv < 35 ? "F4B46B" : "73C8E8"
                )
            }

            return FitnessRecoveryInsightModel(
                title: "适合进行节律观察",
                statusText: status,
                detailText: "当前恢复信号已具备参考价值，但训练刺激相对有限，更适合作为基础节律与恢复基线的观察样本。",
                accentHex: "7D90FF"
            )
        }

        if day.exerciseMinutes > 0 {
            return FitnessRecoveryInsightModel(
                title: "训练已记录，恢复数据待同步",
                statusText: day.exerciseMinutes >= 45 ? "负荷较高" : "训练完成",
                detailText: "当日已有明确训练记录，但尚缺少可读的 HRV 样本。当前可先结合训练分钟与活动消耗评估负荷，恢复判断待同步后再补充。",
                accentHex: day.exerciseMinutes >= 45 ? "F06A7B" : "F4B46B"
            )
        }

        if day.activeEnergy > 0 {
            return FitnessRecoveryInsightModel(
                title: "属于基础活跃日",
                statusText: "轻活动",
                detailText: "当日存在活动消耗，但尚无明确训练与恢复样本，更适合作为日常活跃水平与恢复缓冲的参考。",
                accentHex: "73C8E8"
            )
        }

        return FitnessRecoveryInsightModel(
            title: "属于恢复缓冲日",
            statusText: "恢复观察",
            detailText: "当日未见明显训练负荷，恢复样本亦较有限，更适合作为训练节律中的休整与缓冲节点参考。",
            accentHex: "7D90FF"
        )
    }

    func weekdayShortString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "E"
        return formatter.string(from: date).replacingOccurrences(of: "周", with: "")
    }

    func dayNumberString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    func heartRateStatusText(average: Int) -> String {
        switch average {
        case ..<1:
            return "暂无"
        case ..<55:
            return String(localized: "偏低")
        case 55...95:
            return String(localized: "稳定")
        default:
            return String(localized: "偏高")
        }
    }

    func hrvStatusText(_ value: Double) -> String {
        switch value {
        case ..<1:
            return String(localized: "等待同步")
        case ..<35:
            return String(localized: "偏低")
        case 35..<70:
            return "正常"
        default:
            return String(localized: "不错")
        }
    }

    func wristTemperatureStatusText(_ value: Double) -> String {
        switch value {
        case ..<1:
            return String(localized: "等待同步")
        case 34...37.8:
            return "正常"
        default:
            return String(localized: "留意波动")
        }
    }

    func walkingAsymmetryStatusText(_ value: Double) -> String {
        switch value {
        case ..<1:
            return String(localized: "等待同步")
        case ...10:
            return "正常"
        case ...15:
            return String(localized: "轻微偏高")
        default:
            return String(localized: "建议留意")
        }
    }

    func shortTimeString(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    func monthDayString(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    func historicalSuggestion(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return String(localized: "\(formatter.string(from: date)) 的习惯记录")
    }

    func applyLocalActionRecord(_ record: LocalActionDayRecord) {
        waterAmount = record.waterMl
        caffeineAmount = record.caffeineMg
        if waterTarget <= 0 {
            waterTarget = 2000
        }
        waterCompletionRate = waterTarget > 0 ? min(1.0, Double(waterAmount) / Double(max(1, waterTarget))) : 0.0
        selectedActionRecord = record
    }

    func syncSelectedDayActionRecord() {
        actionRecordStore.updateRecord(for: selectedDateContext) { record in
            record.waterMl = waterAmount
            record.caffeineMg = caffeineAmount
            record.sunlightMinutes = sunlightMinutes
            record.mindfulnessMinutes = mindfulnessMinutes
            record.standHours = standHours

            var completed = Set(record.completedActions)
            if waterAmount > 0 {
                completed.insert(.water)
            } else {
                completed.remove(.water)
            }
            if sunlightMinutes >= 20 {
                completed.insert(.sunlight)
            } else {
                completed.remove(.sunlight)
            }
            if mindfulnessMinutes > 0 {
                completed.insert(.mindfulness)
            } else {
                completed.remove(.mindfulness)
            }
            let standGoal = AppGroupManager.shared.getStandHoursGoal() ?? 12
            if standHours >= standGoal {
                completed.insert(.stand)
            } else {
                completed.remove(.stand)
            }
            record.completedActions = Array(completed)
        }
        selectedActionRecord = actionRecordStore.record(for: selectedDateContext)
    }

    func persistHabitSummaryToAppGroup() {
        let record = actionRecordStore.record(for: selectedDateContext)
        AppGroupManager.shared.saveHabitSummary(
            waterIntakeMl: Double(record.waterMl),
            waterTargetMl: waterTarget,
            waterCompletionRate: waterCompletionRate,
            caffeineRemainedMg: Double(record.caffeineMg)
        )
    }

    func localSuggestion(for date: Date) -> String {
        let record = actionRecordStore.record(for: date)
        if record.completedActions.count >= 3 {
            return String(localized: "今天已经完成了大半动作，后面更适合收尾和保持节奏。")
        }
        if record.waterMl == 0 {
            return String(localized: "先补一杯水，通常是最轻松也最容易完成的第一步。")
        }
        if record.sunlightMinutes < 20 {
            return String(localized: "补一点自然光，会比硬扛更容易把状态带起来。")
        }
        if record.mindfulnessMinutes == 0 {
            return String(localized: "留 3 到 5 分钟给呼吸正念，今天的恢复感会更完整。")
        }
        return historicalSuggestion(for: date)
    }
}
