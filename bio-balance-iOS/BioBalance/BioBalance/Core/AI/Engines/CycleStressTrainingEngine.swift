import Foundation

/// 结合周期、压力、睡眠和训练负荷给出训练节律。
struct CycleStressTrainingEngine {
    /// 周期训练决策需要的聚合输入；缺失项不会被默认成实测值。
    struct Input: Sendable {
        let phase: CyclePhaseKind
        let cycleDay: Int?
        let cycleLength: Int?
        let flowLevel: Int?
        let painLevel: Int?
        let moodLevel: Int?
        let stressScore: Int?
        let sleepMinutes: Int?
        let sleepScore: Int?
        let sleepGoalMinutes: Int?
        let hrv: Double?
        let recentAvgHrv: Double?
        let workoutMinutes: Int?
        let workoutEffort: WorkoutEffortLevel?
        let vo2Max: Double?
    }

    func makePlan(input: Input) -> CycleTrainingRhythmPlan? {
        guard input.phase != .unknown else { return nil }

        let todayMode = resolveTodayMode(input: input)
        let intensityBand = resolveIntensityBand(mode: todayMode)
        let warnings = warningFlags(input: input, mode: todayMode)
        let reason = todayReason(input: input, mode: todayMode)
        let recoveryFocus = recoveryFocus(input: input, mode: todayMode)
        let confidence = confidence(input: input)

        return CycleTrainingRhythmPlan(
            phase: input.phase,
            phaseLabel: input.phase.title,
            todayTrainingMode: todayMode,
            allowedIntensityBand: intensityBand,
            todayReason: reason,
            recoveryFocus: recoveryFocus,
            warningFlags: warnings,
            nextThreeDayRhythm: nextThreeDayRhythm(input: input, todayMode: todayMode),
            confidence: confidence
        )
    }

    private func resolveTodayMode(input: Input) -> CycleTrainingMode {
        let stress = input.stressScore ?? 0
        let pain = input.painLevel ?? 0
        let flow = input.flowLevel ?? 0
        let sleepScore = input.sleepScore ?? 0
        let hrvRatio: Double? = {
            guard let hrv = input.hrv, let recent = input.recentAvgHrv, recent > 0 else { return nil }
            return hrv / recent
        }()

        if input.phase == .menstruation {
            if pain >= 3 || flow >= 3 || stress >= 60 || sleepScore > 0 && sleepScore < 72 {
                return .rest
            }
            return .recovery
        }

        if input.phase == .luteal {
            if stress >= 60 || sleepScore > 0 && sleepScore < 72 || (hrvRatio ?? 1) < 0.9 {
                return .recovery
            }
            return .lightTrain
        }

        if input.phase == .ovulation {
            if stress >= 60 || pain >= 2 {
                return .lightTrain
            }
            return .normalTrain
        }

        if stress >= 65 || sleepScore > 0 && sleepScore < 70 {
            return .lightTrain
        }
        if let ratio = hrvRatio, ratio < 0.9 {
            return .lightTrain
        }
        return .normalTrain
    }

    private func resolveIntensityBand(mode: CycleTrainingMode) -> String {
        switch mode {
        case .rest:
            return String(localized: "仅休整，不追求训练量")
        case .recovery:
            return "低刺激、轻恢复"
        case .lightTrain:
            return String(localized: "轻到中等负荷")
        case .normalTrain:
            return String(localized: "正常训练，但不要超量")
        }
    }

    private func todayReason(input: Input, mode: CycleTrainingMode) -> String {
        switch (input.phase, mode) {
        case (.menstruation, .rest):
            return String(localized: "当前更像是经期不适和恢复压力一起抬高，今天先把身体舒适度放前面。")
        case (.menstruation, .recovery):
            return String(localized: "经期阶段更适合轻恢复与保节律，不值得为了完成训练量去硬顶。")
        case (.follicular, .normalTrain):
            return String(localized: "卵泡期通常更适合正常训练，当前恢复线索也支持稳定推进。")
        case (.luteal, .recovery), (.luteal, .lightTrain):
            return String(localized: "黄体期末段更容易被压力和睡眠波动放大，今天建议先把刺激降下来。")
        case (.ovulation, .normalTrain):
            return String(localized: "当前周期段更适合正常推进，但仍建议留一点恢复余量。")
        default:
            return String(localized: "今天更适合按身体反馈调低一点强度，先把节律守住。")
        }
    }

    private func recoveryFocus(input: Input, mode: CycleTrainingMode) -> String {
        if mode == .rest || mode == .recovery {
            return String(localized: "优先睡眠、补水、轻走动和降低刺激，让身体先回到舒服区间。")
        }
        if input.phase == .luteal {
            return String(localized: "后半天优先稳节律，训练结束时间尽量往前放。")
        }
        return String(localized: "训练后把补水、拉伸和睡前收节奏做好，会比继续堆量更值。")
    }

    private func warningFlags(input: Input, mode: CycleTrainingMode) -> [String] {
        var flags: [String] = []
        if let pain = input.painLevel, pain >= 3 {
            flags.append("当前症状偏明显")
        }
        if let stress = input.stressScore, stress >= 60 {
            flags.append("当前压力偏高")
        }
        if let sleep = input.sleepScore, sleep > 0 && sleep < 72 {
            flags.append("昨夜恢复不足")
        }
        if let ratio = hrvRatio(input: input), ratio < 0.9 {
            flags.append("HRV 低于近期恢复基线")
        }
        if mode == .normalTrain && flags.isEmpty {
            flags.append("训练后仍建议保留恢复余量")
        }
        return flags
    }

    private func nextThreeDayRhythm(input: Input, todayMode: CycleTrainingMode) -> [CycleTrainingDayRhythm] {
        let labels = ["今天", "明天", "后天"]
        return labels.enumerated().map { index, label in
            let mode: CycleTrainingMode
            if index == 0 {
                mode = todayMode
            } else if input.phase == .menstruation {
                mode = todayMode == .rest ? .recovery : todayMode
            } else if input.phase == .luteal {
                mode = todayMode == .recovery ? .lightTrain : todayMode
            } else {
                mode = todayMode
            }
            return CycleTrainingDayRhythm(
                id: "\(label)-\(mode.rawValue)",
                dayLabel: label,
                mode: mode,
                summary: mode.title
            )
        }
    }

    private func confidence(input: Input) -> Double {
        let candidates: [Bool] = [
            input.flowLevel != nil || input.painLevel != nil || input.moodLevel != nil,
            input.stressScore != nil,
            input.sleepMinutes != nil || input.sleepScore != nil,
            input.hrv != nil,
            input.recentAvgHrv != nil,
            input.workoutMinutes != nil
        ]
        let presentCount = candidates.filter { $0 }.count
        return Double(presentCount) / Double(max(candidates.count, 1))
    }

    private func hrvRatio(input: Input) -> Double? {
        guard let hrv = input.hrv, let recent = input.recentAvgHrv, recent > 0 else { return nil }
        return hrv / recent
    }
}
