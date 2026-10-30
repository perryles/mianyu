import Foundation

/// 将最小健康上下文和有限聊天历史转换为 Provider 无关的消息序列。
struct HealthAIContextPromptBuilder {
    static let maximumQuestionCharacters = 2_000
    static let maximumHistoryMessageCharacters = 1_500
    static let maximumHistoryMessages = 4

    /// 清理并限制用户问题；空白输入不会进入 Provider 或本地 responder。
    func normalizedQuestion(_ question: String) -> String? {
        boundedText(question, limit: Self.maximumQuestionCharacters)
    }

    /// 只携带最近四条有效对话，并限制每条文本长度和请求体大小。
    func makeMessages(
        question: String,
        scope: HealthAIScope,
        history: [HealthAIChatMessage]
    ) -> [AITextMessage] {
        var messages = [
            AITextMessage(role: .system, content: systemInstruction(for: scope)),
            AITextMessage(role: .system, content: contextPrompt(for: scope))
        ]
        let normalizedQuestion = normalizedQuestion(question)
        var inspectedMostRecentConversationMessage = false
        let recentHistory = history.reversed().compactMap { message -> AITextMessage? in
            guard !message.isLoading,
                  message.role != .system,
                  let content = boundedText(
                    message.text,
                    limit: Self.maximumHistoryMessageCharacters
                  ) else { return nil }
            if !inspectedMostRecentConversationMessage {
                inspectedMostRecentConversationMessage = true
                // 当前 UI 会先把问题写入消息列表；这里去掉该副本，避免同一问题发送两次。
                // 比较时必须使用问题上限；历史文本上限更短，长问题若先截成历史长度会无法匹配。
                if message.role == .user,
                   self.normalizedQuestion(message.text) == normalizedQuestion {
                    return nil
                }
            }
            return AITextMessage(role: message.role == .user ? .user : .assistant, content: content)
        }.prefix(Self.maximumHistoryMessages).reversed()
        messages.append(contentsOf: recentHistory)
        if let question = normalizedQuestion {
            messages.append(AITextMessage(role: .user, content: question))
        }
        return messages
    }

    private func systemInstruction(for scope: HealthAIScope) -> String {
        let timeBoundary: String
        switch scope {
        case .profile:
            timeBoundary = "这是长期档案解读，不要把档案趋势改写成当天事实，也不要使用今天或今晚等即时语义。"
        case .fitness:
            timeBoundary = "这是训练聚合数据解读。只能解释训练负荷、恢复、频率和趋势，不得生成动作、组数、次数或训练处方。"
        case .today:
            timeBoundary = "这是当日摘要解读，涉及长期趋势时必须明确区分当天数据与近期基线。"
        }
        return """
        你是 眠屿 的 Pulse AI。你的职责是基于用户授权的健康摘要，提供一般性健康解读、趋势说明和保守的生活方式建议。
        不要做医疗诊断，不要给药物或治疗方案，不要替代医生。遇到明显高风险症状、胸痛、呼吸困难、昏厥、自伤风险时，优先建议立即寻求线下医疗帮助。
        回答请使用简体中文，风格温和、明确，不要编造缺失数据。
        HRV、睡眠评分、压力评分和个人基线只能引用上下文中明确提供的确定性结果；不得自行计算、补全、估算或改写这些数字。上下文标记为基线校准中时，不得输出恢复分，也不得声称 HRV 高于或低于个人基线。
        \(timeBoundary)
        你的输出必须严格包含以下 5 个 Markdown 二级标题，且顺序固定：
        ## 结论
        ## 依据
        ## 建议
        ## 留意
        ## 下一步可问
        “结论”直接回答；“依据”和“建议”各使用 2 到 4 条无序列表；“留意”使用 0 到 3 条无序列表；“下一步可问”使用 2 到 3 条短追问。
        如果数据不足，请在“结论”和“依据”里明确指出缺少的样本。没有明显风险时，在“留意”写明仍需结合体感观察。
        """
    }

    private func contextPrompt(for scope: HealthAIScope) -> String {
        switch scope {
        case .today(let context):
            return todayPrompt(context)
        case .fitness(let context):
            return fitnessPrompt(context)
        case .profile(let profile):
            return HealthAIProfilePromptBuilder().makePrompt(from: profile.digest)
        }
    }

    private func fitnessPrompt(_ context: FitnessAIInsightContext) -> String {
        let latestWorkout = boundedContextText(context.latestWorkoutSummary, limit: 120) ?? "当前无足够样本"
        return [
            "以下是用户主动请求解读的最小化训练聚合摘要：",
            "[观察范围]",
            "- 截止日期：\(boundedContextText(context.dateText, limit: 40) ?? "未知")",
            "- 近 7 天训练天数：\(context.recentTrainingDays)",
            "- 前 7 天训练天数：\(context.previousTrainingDays)",
            "- 近 7 天训练分钟：\(context.recentMinutes)",
            "- 前 7 天训练分钟：\(context.previousMinutes)",
            "[聚合状态]",
            "- 当前训练负荷：\(context.currentLoadScore.map { "\($0)/100" } ?? "当前无足够样本")",
            "- 当前恢复状态：\(context.currentRecoveryScore.map { "\($0)/100" } ?? "当前无足够样本")",
            "- 近 7 天体能表现：\(context.performanceScore.map { "\($0)/100" } ?? "当前无足够样本")",
            "- 相对前 7 天变化：\(context.performanceChange.map(String.init) ?? "当前无足够样本")",
            "- HRV 有效样本天数：\(context.hrvSampleDays)",
            "- 活动有效样本天数：\(context.activitySampleDays)",
            "- 最近训练摘要：\(latestWorkout)",
            "只能解释以上聚合字段。不得推断原始 HealthKit 样本、精确时间、位置、症状或未提供的训练内容。不得生成训练动作、组数、次数或多日训练计划。",
            "回答末尾请补一句提醒：仅用于解释训练与恢复趋势，不构成医疗诊断、治疗或个性化训练处方。"
        ].joined(separator: "\n")
    }

    private func todayPrompt(_ context: HealthAIContext) -> String {
        var lines = ["以下是用户今天的健康摘要，仅供一般健康建议：", "[睡眠]"]
        lines.append("- 总睡眠：\(value(context.sleep.typedDuration.map { "\($0.value) 分钟" }))")
        lines.append("- 睡眠评分：\(value(context.sleep.score.map(String.init)))")
        lines.append("- 入睡/醒来：\(value(timeRange(context.sleep.startLocalTime, context.sleep.endLocalTime)))")
        lines.append("- 醒来次数：\(value(context.sleep.awakeCount.map(String.init)))")
        lines.append("[恢复生命体征]")
        lines.append("- 夜间 HRV：\(value(context.recoveryVitals.typedNightlyHrv.map { "\(Int($0.value.rounded())) ms" }))")
        lines.append("- 夜间平均心率：\(value(context.recoveryVitals.typedNightlyAverageHeartRate.map { "\($0.roundedValue) bpm" }))")
        lines.append("- 夜间呼吸频率：\(value(context.recoveryVitals.nightlyRespiratoryRate.map { String(format: String(localized: "%.1f 次/分"), $0) }))")
        lines.append("[今日心率与压力]")
        lines.append("- 当前心率：\(value(context.todayVitals.typedCurrentHeartRate.map { "\($0.roundedValue) bpm" }))")
        lines.append("- 静息心率：\(value(context.todayVitals.typedRestingHeartRate.map { "\($0.roundedValue) bpm" }))")
        lines.append("- 近期平均静息心率：\(value(context.todayVitals.typedRecentAverageRestingHeartRate.map { "\($0.roundedValue) bpm" }))")
        lines.append("- 今日平均 HRV：\(value(context.todayVitals.typedTodayAverageHrv.map { "\(Int($0.value.rounded())) ms" }))")
        lines.append("- 近期平均 HRV：\(value(context.todayVitals.typedRecentAverageHrv.map { "\(Int($0.value.rounded())) ms" }))")
        lines.append("- 当前压力：\(value(context.stress.currentScore.map { "\($0)/100" }))")
        lines.append("- 今日综合压力：\(value(context.stress.dailyScore.map { "\($0)/100" }))")
        lines.append("- 压力分层：\(boundedContextText(context.stress.title, limit: 80) ?? "当前无足够样本")")
        lines.append("- 压力摘要：\(boundedContextText(context.stress.summary, limit: 240) ?? "当前无足够样本")")
        if context.recoveryScriptPlan?.confidence == 0 {
            lines.append("- 恢复计算状态：个人基线校准中；禁止输出恢复分或 HRV 相对基线结论")
        } else if let plan = context.recoveryScriptPlan {
            lines.append("- 确定性恢复分：\(plan.readinessScore)/100")
            lines.append("- 恢复计算置信度：\(String(format: "%.2f", plan.confidence))")
        }
        lines.append("[活动与恢复行为]")
        lines.append("- 今日步数：\(value(context.activity.stepsToday.map(String.init)))")
        lines.append("- 今日步速：\(value(context.activity.walkingSpeedMpsToday.map { String(format: "%.2f m/s", $0) }))")
        lines.append("- 当前久坐时长：\(value(context.recoveryBehavior.sedentaryElapsedMinutesCurrent.map { "\($0) 分钟" }))")
        lines.append("- 今日累计久坐：\(value(context.recoveryBehavior.sedentaryTotalMinutesToday.map { "\($0) 分钟" }))")
        lines.append("- 今日打断次数：\(value(context.recoveryBehavior.activeBreakCountToday.map(String.init)))")
        lines.append("回答末尾请补一句提醒：\(boundedContextText(context.disclaimer, limit: 240) ?? "仅供健康管理参考。")")
        return lines.joined(separator: "\n")
    }

    private func value(_ value: String?) -> String { value ?? "当前无足够样本" }

    private func timeRange(_ start: String?, _ end: String?) -> String? {
        guard let start = boundedText(start, limit: 16),
              let end = boundedText(end, limit: 16) else { return nil }
        return "\(start) - \(end)"
    }

    private func boundedText(_ value: String?, limit: Int) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(max(0, limit)))
    }

    /// 上下文字段不是用户消息，先压成单行，避免换行伪装成新的 Prompt 指令或字段。
    private func boundedContextText(_ value: String?, limit: Int) -> String? {
        let flattened = value?
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return boundedText(flattened, limit: limit)
    }
}
