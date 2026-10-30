import Foundation

/// Pulse AI 健身解读允许使用的最小化聚合摘要。
/// 不包含 HealthKit 原始样本、精确时间序列、位置或用户自由备注。
struct FitnessAIInsightContext: Equatable, Sendable {
    let dateText: String
    let recentTrainingDays: Int
    let previousTrainingDays: Int
    let recentMinutes: Int
    let previousMinutes: Int
    let currentLoadScore: Int?
    let currentRecoveryScore: Int?
    let performanceScore: Int?
    let performanceChange: Int?
    let hrvSampleDays: Int
    let activitySampleDays: Int
    let latestWorkoutSummary: String?

    var totalSignalDays: Int {
        max(activitySampleDays, hrvSampleDays)
    }

    static let placeholder = FitnessAIInsightContext(
        dateText: "--",
        recentTrainingDays: 0,
        previousTrainingDays: 0,
        recentMinutes: 0,
        previousMinutes: 0,
        currentLoadScore: nil,
        currentRecoveryScore: nil,
        performanceScore: nil,
        performanceChange: nil,
        hrvSampleDays: 0,
        activitySampleDays: 0,
        latestWorkoutSummary: nil
    )
}

enum FitnessAIInsightConfidence: String, Equatable, Sendable {
    case insufficient
    case building
    case ready

    var title: String {
        switch self {
        case .insufficient:
            return String(localized: "样本不足")
        case .building:
            return String(localized: "趋势建立中")
        case .ready:
            return String(localized: "数据较完整")
        }
    }

    var progress: Double {
        switch self {
        case .insufficient: return 0.24
        case .building: return 0.58
        case .ready: return 0.92
        }
    }
}

struct FitnessAIInsightModel: Equatable, Sendable {
    let eyebrow: String
    let title: String
    let summary: String
    let evidence: [String]
    let confidence: FitnessAIInsightConfidence
    let accentHex: String
    let symbol: String
}

/// 先由本地确定性规则给出可解释结论；生成式 AI 只负责在用户主动请求后展开说明。
struct FitnessAIInsightEngine {
    func makeInsight(from context: FitnessAIInsightContext) -> FitnessAIInsightModel {
        let confidence = confidence(for: context)
        guard confidence != .insufficient else {
            return FitnessAIInsightModel(
                eyebrow: "PULSE AI · 本地解读",
                title: "先建立你的训练基线",
                summary: "目前还没有足够的训练与恢复样本，Pulse AI 不会用缺失数据推断你的状态。",
                evidence: compactEvidence(from: context),
                confidence: confidence,
                accentHex: "5578F6",
                symbol: "sparkles"
            )
        }

        let load = context.currentLoadScore
        let recovery = context.currentRecoveryScore
        let performanceChange = context.performanceChange ?? 0

        if let load, let recovery, load >= 70, recovery < 45 {
            return FitnessAIInsightModel(
                eyebrow: "PULSE AI · 负荷观察",
                title: "训练负荷暂时跑在恢复前面",
                summary: "近期训练刺激已经明显累积，而恢复信号相对偏弱；这是一段需要继续观察吸收情况的窗口。",
                evidence: compactEvidence(from: context),
                confidence: confidence,
                accentHex: "EF6A8A",
                symbol: "waveform.path.ecg"
            )
        }

        if context.recentTrainingDays == 0 && context.previousTrainingDays > 0 {
            return FitnessAIInsightModel(
                eyebrow: "PULSE AI · 节奏变化",
                title: "训练节奏出现了一段空档",
                summary: "与前一周相比，最近七天没有形成明确训练记录，当前趋势更像节奏中断而不是表现下降。",
                evidence: compactEvidence(from: context),
                confidence: confidence,
                accentHex: "7B74F5",
                symbol: "chart.line.downtrend.xyaxis"
            )
        }

        if context.recentTrainingDays > context.previousTrainingDays || performanceChange >= 6 {
            return FitnessAIInsightModel(
                eyebrow: "PULSE AI · 趋势变化",
                title: "训练节奏正在向上抬升",
                summary: "最近七天的训练频率或综合表现高于前一阶段，当前变化来自持续积累，而不是单次峰值。",
                evidence: compactEvidence(from: context),
                confidence: confidence,
                accentHex: "3B8EF7",
                symbol: "chart.line.uptrend.xyaxis"
            )
        }

        if let load, let recovery, recovery >= 60, load >= 35 {
            return FitnessAIInsightModel(
                eyebrow: "PULSE AI · 状态解读",
                title: "训练与恢复目前比较同步",
                summary: "近期负荷已经形成，同时恢复信号没有明显掉队，整体呈现相对稳定的吸收状态。",
                evidence: compactEvidence(from: context),
                confidence: confidence,
                accentHex: "2DA8A1",
                symbol: "point.3.connected.trianglepath.dotted"
            )
        }

        return FitnessAIInsightModel(
            eyebrow: "PULSE AI · 状态解读",
            title: "训练趋势仍在建立中",
            summary: "当前没有明显的负荷失衡或快速变化，继续积累记录后，趋势判断会更稳定。",
            evidence: compactEvidence(from: context),
            confidence: confidence,
            accentHex: "5578F6",
            symbol: "sparkles"
        )
    }

    private func confidence(for context: FitnessAIInsightContext) -> FitnessAIInsightConfidence {
        guard context.totalSignalDays > 0 || context.recentTrainingDays > 0 else {
            return .insufficient
        }
        if context.activitySampleDays >= 5 && context.hrvSampleDays >= 2 {
            return .ready
        }
        return .building
    }

    private func compactEvidence(from context: FitnessAIInsightContext) -> [String] {
        var result: [String] = []
        if context.recentTrainingDays > 0 || context.previousTrainingDays > 0 {
            result.append("近 7 天训练 \(context.recentTrainingDays) 天、\(context.recentMinutes) 分钟；前 7 天 \(context.previousTrainingDays) 天、\(context.previousMinutes) 分钟")
        }
        if let load = context.currentLoadScore, let recovery = context.currentRecoveryScore {
            result.append("当前聚合负荷 \(load) 分，恢复 \(recovery) 分")
        }
        if let score = context.performanceScore {
            let delta = context.performanceChange.map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "趋势建立中"
            result.append("近 7 天体能表现 \(score) 分，阶段变化 \(delta)")
        }
        if let latestWorkout = context.latestWorkoutSummary, !latestWorkout.isEmpty {
            result.append("最近训练：\(String(latestWorkout.prefix(80)))")
        }
        if result.isEmpty {
            result.append("当前缺少连续的训练、活动和 HRV 聚合样本")
        }
        return Array(result.prefix(3))
    }
}

struct FitnessAIInsightLocalResponder {
    func answer(question _: String, context: FitnessAIInsightContext) -> HealthAIAnswerPayload {
        let insight = FitnessAIInsightEngine().makeInsight(from: context)
        let actions = insight.confidence == .insufficient
            ? ["继续记录训练时长与强度，帮助趋势逐步建立。", "有条件时同步活动与 HRV 聚合数据。"]
            : ["继续观察后续记录是否延续当前趋势。", "将数据结论与疲劳、疼痛和主观体感一起判断。"]
        let risks = ["聚合趋势不能替代身体感受，也不构成医疗诊断或个性化训练处方。"]
        let followUps = [
            "目前还缺少哪些数据？",
            "负荷和恢复分别是怎么计算的？",
            "最近七天和前七天最大的变化是什么？"
        ]
        let basisMarkdown = insight.evidence.map { "- \($0)" }.joined(separator: "\n")
        let actionMarkdown = actions.map { "- \($0)" }.joined(separator: "\n")
        let riskMarkdown = risks.map { "- \($0)" }.joined(separator: "\n")
        let followUpMarkdown = followUps.map { "- \($0)" }.joined(separator: "\n")
        return HealthAIAnswerPayload(
            summary: insight.title,
            basis: insight.evidence,
            actions: actions,
            risks: risks,
            followUps: followUps,
            rawMarkdown: """
            ## 结论
            \(insight.title)。\(insight.summary)
            ## 依据
            \(basisMarkdown)
            ## 建议
            \(actionMarkdown)
            ## 留意
            \(riskMarkdown)
            ## 下一步可问
            \(followUpMarkdown)
            """,
            source: .deterministic
        )
    }
}
