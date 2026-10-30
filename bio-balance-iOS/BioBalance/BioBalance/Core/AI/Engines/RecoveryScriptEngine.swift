import Foundation

/// 根据确定性健康指标生成恢复分层、理由和行动建议。
struct RecoveryScriptEngine {
    func makePlan(context: HealthAIContext, now: Date = Date()) -> RecoveryScriptPlan {
        let isCalibrating = isColdStart(context)
        let score = isCalibrating ? 50 : readinessScore(context: context)
        let band = isCalibrating ? .balanced : readinessBand(for: score)
        let confidence = isCalibrating ? 0 : confidenceScore(context: context)
        let focus = isCalibrating ? "建立个人基线" : recoveryFocus(for: band, context: context)
        let reasons = isCalibrating
            ? ["当前有效健康样本不足，正在建立个人基线。暂不根据 HRV、睡眠或压力生成确定性恢复分。"]
            : keyReasons(for: band, score: score, context: context)
        let actions = immediateActions(for: band, context: context)
        let risks = isCalibrating ? ["基线校准中"] : riskFlags(for: band, context: context)
        let headline = isCalibrating
            ? "正在建立你的个人基线，先记录几晚稳定数据。"
            : headline(for: band, context: context)
        let morning = morningScript(for: band, context: context)
        let afternoon = afternoonScript(for: band, context: context)
        let evening = eveningScript(for: band, context: context)
        let avoid = avoidList(for: band, context: context)
        let watchPrompt = isCalibrating ? "先连续记录几晚，再开始比较个人变化。" : watchPrompt(for: band, context: context)
        let widgetSummary = [headline, actions.first, evening]
            .compactMap { item in
                guard let item else { return nil }
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " ")

        return RecoveryScriptPlan(
            readinessBand: band,
            readinessScore: score,
            headline: headline,
            recoveryFocus: focus,
            keyReasons: reasons,
            immediateActions: actions,
            riskFlags: risks,
            morningScript: morning,
            afternoonScript: afternoon,
            eveningScript: evening,
            avoidList: avoid,
            watchPrompt: watchPrompt,
            widgetSummary: widgetSummary,
            confidence: confidence,
            generatedAt: now
        )
    }

    private func readinessScore(context: HealthAIContext) -> Int {
        var score = 54
        let goalMinutes = max(context.sleepGoalMinutes ?? 480, 1)

        if let sleepMinutes = context.sleep.typedDuration?.value {
            let ratio = Double(sleepMinutes) / Double(goalMinutes)
            switch ratio {
            case ..<0.7:
                score -= 22
            case ..<0.85:
                score -= 14
            case 1.0...:
                score += 8
            default:
                break
            }
        }

        if let sleepScore = context.sleep.score {
            switch sleepScore {
            case ..<65:
                score -= 12
            case ..<78:
                score -= 6
            case 86...:
                score += 6
            default:
                break
            }
        }

        if let stress = context.stress.score {
            switch stress {
            case 75...:
                score -= 22
            case 60...74:
                score -= 14
            case 45...59:
                score -= 8
            case ..<26:
                score += 6
            default:
                break
            }
        }

        if let hrv = context.todayVitals.typedTodayAverageHrv,
           let baseline = context.todayVitals.typedRecentAverageHrv {
            let ratio = hrv.value / baseline.value
            switch ratio {
            case ..<0.8:
                score -= 14
            case ..<0.92:
                score -= 8
            case 1.05...:
                score += 5
            default:
                break
            }
        }

        if let resting = context.todayVitals.typedRestingHeartRate,
           let baseline = context.todayVitals.typedRecentAverageRestingHeartRate {
            let delta = resting.value - baseline.value
            if delta >= 6 {
                score -= 10
            } else if delta >= 3 {
                score -= 6
            } else if delta <= -3 {
                score += 4
            }
        }

        if let remaining = context.caffeineEstimatedRemainingMg {
            switch remaining {
            case 120...:
                score -= 12
            case 70...119:
                score -= 7
            default:
                break
            }
        }

        if let sunlight = context.daylightMinutesToday, sunlight < 10 {
            score -= 4
        }

        if let water = context.waterMlToday, water < 1000 {
            score -= 4
        }

        if let sedentary = context.recoveryBehavior.sedentaryElapsedMinutesCurrent, sedentary >= 75 {
            score -= 6
        }

        return max(0, min(100, score))
    }

    private func readinessBand(for score: Int) -> RecoveryReadinessBand {
        switch score {
        case ..<28:
            return .protect
        case ..<50:
            return .recover
        case 72...:
            return .pushLight
        default:
            return .balanced
        }
    }

    private func confidenceScore(context: HealthAIContext) -> Double {
        let candidates: [Bool] = [
            context.sleep.typedDuration != nil,
            context.sleep.score != nil,
            context.stress.score != nil,
            context.todayVitals.typedTodayAverageHrv != nil && context.todayVitals.typedRecentAverageHrv != nil,
            context.todayVitals.typedRestingHeartRate != nil,
            context.caffeineEstimatedRemainingMg != nil,
            context.daylightMinutesToday != nil,
            context.waterMlToday != nil
        ]
        let presentCount = candidates.filter { $0 }.count
        return Double(presentCount) / Double(max(candidates.count, 1))
    }

    private func headline(for band: RecoveryReadinessBand, context: HealthAIContext) -> String {
        let lowSleep = isShortSleep(context)
        let highStress = (context.stress.score ?? 0) >= 70
        let highCaffeine = (context.caffeineEstimatedRemainingMg ?? 0) >= 80

        switch band {
        case .protect:
            if lowSleep && highStress {
                return String(localized: "昨晚恢复不足又叠加高压，今天更适合先保恢复底盘。")
            }
            if highCaffeine {
                return String(localized: "今天恢复窗口容易被刺激占掉，节奏要明显收一收。")
            }
            return String(localized: "今天更适合把恢复和降刺激放在第一位。")
        case .recover:
            if lowSleep {
                return String(localized: "昨晚恢复一般，今天先把节律稳住，再慢慢把状态拉回来。")
            }
            return String(localized: "今天先把身体节律稳住，再考虑推进任务。")
        case .balanced:
            return String(localized: "今天可以平稳推进，但别把后半天继续拉满。")
        case .pushLight:
            return String(localized: "今天恢复在线，适合轻推进而不是硬冲强度。")
        }
    }

    private func recoveryFocus(for band: RecoveryReadinessBand, context: HealthAIContext) -> String {
        if let caffeine = context.caffeineEstimatedRemainingMg, caffeine >= 80 {
            return "减少晚间刺激"
        }
        if let sedentary = context.recoveryBehavior.sedentaryElapsedMinutesCurrent, sedentary >= 75 {
            return String(localized: "打断久坐堆积")
        }
        if let stress = context.stress.score, stress >= 70 {
            return "先降压力负荷"
        }
        if isShortSleep(context) {
            return "补回睡眠恢复窗口"
        }
        switch band {
        case .protect:
            return "守住恢复底盘"
        case .recover:
            return String(localized: "稳住全天节律")
        case .balanced:
            return String(localized: "平稳推进不过载")
        case .pushLight:
            return String(localized: "轻推进不硬冲")
        }
    }

    private func keyReasons(for band: RecoveryReadinessBand, score: Int, context: HealthAIContext) -> [String] {
        var reasons: [String] = []

        if let sleepMinutes = context.sleep.typedDuration?.value,
           let goalMinutes = context.sleepGoalMinutes,
           goalMinutes > 0,
           sleepMinutes < Int(Double(goalMinutes) * 0.85) {
            reasons.append("昨晚睡眠时长低于目标，恢复底盘偏薄。")
        }

        if let sleepScore = context.sleep.score, sleepScore < 70 {
            reasons.append("睡眠评分偏低，说明恢复质量还没有完全拉起来。")
        }

        if let stress = context.stress.score, stress >= 60 {
            reasons.append("今天压力负荷偏高，继续加码更容易透支恢复。")
        }

        if let hrv = context.todayVitals.typedTodayAverageHrv,
           let baseline = context.todayVitals.typedRecentAverageHrv {
            let ratio = hrv.value / baseline.value
            if ratio < 0.92 {
                reasons.append("HRV 低于近期基线，身体弹性更像在提醒你先收节奏。")
            } else if ratio >= 1.05 && band == .pushLight {
                reasons.append("HRV 相比近期基线更稳，说明今天具备轻推进空间。")
            }
        }

        if let resting = context.todayVitals.typedRestingHeartRate,
           let baseline = context.todayVitals.typedRecentAverageRestingHeartRate {
            let delta = resting.value - baseline.value
            if delta >= 3 {
                reasons.append("静息心率高于近期基线，今天更像处在偏紧状态。")
            }
        }

        if let caffeine = context.caffeineEstimatedRemainingMg, caffeine >= 70 {
            reasons.append("体内残留咖啡因仍然偏高，晚间恢复窗口更容易被拖后。")
        }

        if let daylight = context.daylightMinutesToday, daylight < 10 {
            reasons.append("今天自然光暴露偏少，节律稳定性可能会受一点影响。")
        }

        if let water = context.waterMlToday, water < 1000 {
            reasons.append("今天补水还不够，容易放大疲劳和紧绷感。")
        }

        if let sedentary = context.recoveryBehavior.sedentaryElapsedMinutesCurrent, sedentary >= 60 {
            reasons.append("连续久坐时间偏长，身体容易一直停留在紧绷状态。")
        }

        if reasons.isEmpty {
            reasons.append(score >= 70 ? "主要恢复信号整体平稳，今天有一定轻推进空间。" : "当前样本没有出现特别单一的拖累项，更适合稳住节律。")
        }

        return Array(reasons.prefix(3))
    }

    private func immediateActions(for band: RecoveryReadinessBand, context: HealthAIContext) -> [String] {
        var actions: [String] = []

        if let water = context.waterMlToday, water < 1000 {
            actions.append("先补一杯水，把身体从低补水状态拉回来。")
        }

        if let sedentary = context.recoveryBehavior.sedentaryElapsedMinutesCurrent, sedentary >= 60 {
            actions.append("现在就起身活动 3 到 5 分钟，先把久坐链条打断。")
        }

        if let daylight = context.daylightMinutesToday, daylight < 10 {
            actions.append("午后补一点自然光和轻步行，帮助把节律重新稳住。")
        }

        if let caffeine = context.caffeineEstimatedRemainingMg, caffeine >= 80 {
            actions.append("今天后半段先停刺激性饮品，把晚上恢复窗口保住。")
        }

        switch band {
        case .protect:
            actions.append("把今天非必要的高强度训练或高压任务主动降一级。")
        case .recover:
            actions.append("优先安排稳定输出和轻恢复，不急着把节奏拉满。")
        case .balanced:
            actions.append("把最重要的一件事做完即可，后半天别继续叠高负荷。")
        case .pushLight:
            actions.append("可以正常推进，但把强度控制在七成以内，给晚上留恢复余地。")
        }

        return Array(actions.prefix(3))
    }

    private func riskFlags(for band: RecoveryReadinessBand, context: HealthAIContext) -> [String] {
        var flags: [String] = []

        if let stress = context.stress.score, stress >= 75 {
            flags.append("高压负荷")
        }
        if let caffeine = context.caffeineEstimatedRemainingMg, caffeine >= 80 {
            flags.append("晚间刺激残留")
        }
        if let sedentary = context.recoveryBehavior.sedentaryElapsedMinutesCurrent, sedentary >= 75 {
            flags.append("连续久坐过长")
        }
        if isShortSleep(context) {
            flags.append("睡眠恢复不足")
        }
        if band == .protect {
            flags.append("不适合临时加练")
        }

        return Array(flags.prefix(3))
    }

    private func morningScript(for band: RecoveryReadinessBand, context: HealthAIContext) -> String {
        if band == .protect {
            return String(localized: "早上先用补水、短走动和低刺激启动身体，别一上来就堆高任务强度。")
        }
        if band == .recover {
            return String(localized: "上午先做稳定节律的事，优先把心率和体感拉回舒服区间。")
        }
        if context.stress.score ?? 0 >= 55 {
            return String(localized: "上午先推进最重要的一件事，中间记得插一次短走动或呼吸打断。")
        }
        return String(localized: "上午可以正常推进，但先留一点弹性，别把最耗神的任务全挤在第一段。")
    }

    private func afternoonScript(for band: RecoveryReadinessBand, context: HealthAIContext) -> String {
        if let daylight = context.daylightMinutesToday, daylight < 10 {
            return String(localized: "午后优先补一点自然光和轻步行，这比继续久坐更能稳住节律。")
        }
        if let sedentary = context.recoveryBehavior.sedentaryElapsedMinutesCurrent, sedentary >= 60 {
            return String(localized: "午后别连续久坐太久，最好每 60 分钟左右起身一次，把紧绷感打断。")
        }
        if band == .pushLight {
            return String(localized: "午后可以保持稳定推进，但训练和工作都只建议到中等负荷。")
        }
        return String(localized: "午后以平稳输出为主，如果体感开始发紧，就先把节奏收一点。")
    }

    private func eveningScript(for band: RecoveryReadinessBand, context: HealthAIContext) -> String {
        if let caffeine = context.caffeineEstimatedRemainingMg, caffeine >= 80 {
            return String(localized: "晚上尽量不再补刺激性饮品，并把入睡时间往前收，给恢复留窗口。")
        }
        switch band {
        case .protect:
            return String(localized: "晚上优先早点收尾、少刺激、少额外训练，尽量把睡前节奏放缓。")
        case .recover:
            return String(localized: "晚上适合轻恢复、拉伸或安静活动，重点是把入睡质量守住。")
        case .balanced:
            return String(localized: "晚上保持温和节奏就好，别临时加高强度训练或太晚工作。")
        case .pushLight:
            return String(localized: "晚上可以做轻到中等活动，但仍建议把结束时间留在睡前 2 小时之外。")
        }
    }

    private func avoidList(for band: RecoveryReadinessBand, context: HealthAIContext) -> [String] {
        var items: [String] = []
        if let caffeine = context.caffeineEstimatedRemainingMg, caffeine >= 60 {
            items.append("继续补高咖啡因饮品")
        }
        if let stress = context.stress.score, stress >= 60 {
            items.append("把晚间任务继续拉满")
        }
        if let sedentary = context.recoveryBehavior.sedentaryElapsedMinutesCurrent, sedentary >= 75 {
            items.append("连续久坐不打断")
        }
        if band == .protect {
            items.append("临时加练高强度运动")
        }
        return items.isEmpty ? ["过晚继续提神和过度刺激"] : items
    }

    private func watchPrompt(for band: RecoveryReadinessBand, context: HealthAIContext) -> String {
        if let caffeine = context.caffeineEstimatedRemainingMg, caffeine >= 80 {
            return String(localized: "今晚先减刺激，早点收节奏。")
        }
        switch band {
        case .protect:
            return String(localized: "今天先把恢复放前面。")
        case .recover:
            return String(localized: "今天先稳节律，再慢慢推进。")
        case .balanced:
            return String(localized: "状态平稳，后半天别再加码。")
        case .pushLight:
            return String(localized: "恢复在线，适合轻推进。")
        }
    }

    private func isShortSleep(_ context: HealthAIContext) -> Bool {
        guard let sleepMinutes = context.sleep.typedDuration?.value,
              let goalMinutes = context.sleepGoalMinutes,
              goalMinutes > 0 else {
            return false
        }
        return Double(sleepMinutes) / Double(goalMinutes) < 0.85
    }

    private func isColdStart(_ context: HealthAIContext) -> Bool {
        let hasRelativeHrv = context.todayVitals.typedTodayAverageHrv != nil
            && context.todayVitals.typedRecentAverageHrv != nil
        let hasRelativeRestingHeartRate = context.todayVitals.typedRestingHeartRate != nil
            && context.todayVitals.typedRecentAverageRestingHeartRate != nil
        return context.sleep.typedDuration == nil
            && context.sleep.score == nil
            && context.stress.score == nil
            && !hasRelativeHrv
            && !hasRelativeRestingHeartRate
    }
}

