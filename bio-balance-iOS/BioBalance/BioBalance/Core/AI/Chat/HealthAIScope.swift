import Foundation

/// 长期档案上传的显式授权状态，与今日摘要授权分开管理。
enum HealthAICloudAuthorization: Sendable {
    case notGranted
    case granted
}

/// 健康问答的数据边界；不同 Scope 使用独立的上传策略和本地 responder。
enum HealthAIScope: Sendable {
    struct ProfileContext: Sendable {
        let digest: HealthProfileAIDigest
        let cloudAuthorization: HealthAICloudAuthorization
    }

    case today(HealthAIContext)
    case fitness(FitnessAIInsightContext)
    case profile(ProfileContext)

    static func healthProfile(
        digest: HealthProfileAIDigest,
        cloudAuthorization: HealthAICloudAuthorization = .notGranted
    ) -> HealthAIScope {
        .profile(ProfileContext(digest: digest, cloudAuthorization: cloudAuthorization))
    }

    var isProfile: Bool {
        if case .profile = self { return true }
        return false
    }

    var welcomeMessage: String {
        switch self {
        case .today:
            return String(localized: "我已经拿到你今天的健康摘要。你可以直接让我总结恢复状态、解释压力来源，或者给你今晚的具体建议。")
        case .fitness:
            return String(localized: "我已经拿到最小化的训练聚合摘要。你可以让我解释负荷、恢复、训练频率和体能趋势。")
        case .profile:
            return String(localized: "我已经拿到健康档案的聚合摘要。你可以让我解释档案状态、梳理近期变化，或确定本周优先照顾的方向。")
        }
    }

    var loadingMessage: String {
        switch self {
        case .today:
            return String(localized: "正在整理今天的恢复信号、压力变化和活动摘要...")
        case .fitness:
            return String(localized: "正在整理近期训练负荷、恢复和体能趋势...")
        case .profile:
            return String(localized: "正在整理档案状态、长期变化和数据依据...")
        }
    }

    var heroSubtitle: String {
        if case .profile(let context) = self {
            return String(localized: "本地档案解读 · \(context.digest.range.title) · 不上传原始健康记录")
        }
        if case .fitness = self {
            return permitsRemoteRequest ? "基于训练聚合摘要 · 不含原始 HealthKit 记录" : "本地训练解读 · 不上传健康摘要"
        }
        return permitsRemoteRequest ? "基于今日健康摘要回答，离线可用本地模型。" : "本地今日解读 · 不上传健康摘要"
    }

    var composerStatus: String {
        if isProfile {
            return String(localized: "本地档案摘要 · 不上传")
        }
        if case .fitness = self {
            return permitsRemoteRequest ? "基于训练聚合摘要" : "本地训练摘要 · 不上传"
        }
        return permitsRemoteRequest ? "基于今日健康摘要" : "本地今日摘要 · 不上传"
    }

    var inputPlaceholder: String {
        if isProfile { return "例如：本周最值得优先照顾什么？" }
        if case .fitness = self { return "例如：为什么最近训练状态是这样？" }
        return "例如：今晚我最该优先调整什么？"
    }

    var quickQuestions: [String] {
        switch self {
        case .today:
            return [
                "我今天整体恢复得怎么样？",
                "解释我的今日剧本为什么是这个节奏？",
                "为什么今天压力偏高？",
                "今晚最适合做哪三件恢复动作？"
            ]
        case .fitness:
            return [
                "为什么最近训练状态是这个结论？",
                "负荷和恢复之间发生了什么变化？",
                "我的训练频率和前一周相比如何？",
                "目前还缺少哪些数据才能判断得更准？"
            ]
        case .profile:
            return [
                "为什么档案是这个状态？",
                "最近最重要的变化是什么？",
                "本周先照顾什么？"
            ]
        }
    }

    var disclaimer: String {
        switch self {
        case .today(let context):
            return context.disclaimer
        case .fitness:
            return String(localized: "仅用于解释训练与恢复趋势，不构成医疗诊断、治疗或个性化训练处方。请结合自身感受判断。")
        case .profile:
            return String(localized: "仅供健康管理参考，不构成医疗诊断、治疗或急救建议。如有持续不适或异常指标，请咨询医生。")
        }
    }

    var permitsRemoteRequest: Bool {
        switch self {
        case .today:
            // 今日 PromptBuilder 不读取 healthProfileSummary；附带的本地档案不会阻断或进入云端请求。
            return HealthAIConfiguration.isTodayCloudUploadAuthorized
        case .fitness:
            // 健身问答沿用今日摘要的显式授权，但只发送更小的聚合字段集合。
            return HealthAIConfiguration.isTodayCloudUploadAuthorized
        case .profile(let context):
            guard context.cloudAuthorization == .granted else { return false }
            return HealthAIConfiguration.isSecureProfileBackendConfigured
        }
    }
}

/// 仅从清洗后的聚合档案字段构建长期健康 Prompt。
struct HealthAIProfilePromptBuilder {
    func makePrompt(from digest: HealthProfileAIDigest) -> String {
        let safe = SanitizedDigest(digest: digest)
        var lines = [
            "以下是用户主动请求解读的长期健康档案聚合摘要。不得推断未提供的原始记录或医疗结论：",
            "[档案概览]",
            "- 观察范围：\(safe.range)",
            "- 摘要生成时间：\(safe.generatedAt)",
            "- 档案状态：\(safe.status)",
            "- 成长指数：\(safe.growthScore)/100",
            "- 数据可信度：\(safe.dataQualityScore)/100",
            "- 数据依据：\(safe.dataQualitySummary)",
            "- 画像摘要：\(safe.headline)",
            "[长期线索]",
            "- 健康标签：\(listText(safe.topTags, empty: "暂无稳定标签"))",
            "- 容易失衡方向：\(listText(safe.topRisks, empty: "暂无稳定风险方向"))",
            "- 近期变化：\(listText(safe.recentChanges, empty: "暂无足够变化证据"))",
            "- 建议行动：\(listText(safe.nextActions, empty: "先继续积累数据"))",
            "- 缺失或待补数据：\(listText(safe.missingData, empty: "无明显缺口"))",
            "只能使用以上聚合字段回答。未提供原始 HealthKit 序列、症状明细、周期日期、自由备注或用药明细，不得假设这些信息存在。"
        ]
        if !safe.dimensions.isEmpty {
            lines.append("[维度摘要]")
            lines.append(contentsOf: safe.dimensions.map { dimension in
                let score = dimension.score.map { "，\($0)/100" } ?? ""
                return String(localized: "- \(dimension.title)：\(dimension.status)\(score)，趋势 \(dimension.trend)；\(dimension.summary)")
            })
        }
        if !safe.evidence.isEmpty {
            lines.append("[聚合证据]")
            lines.append(contentsOf: safe.evidence.map { "- \($0)" })
        }
        lines.append("回答末尾请补一句提醒：仅供健康管理参考，不构成医疗诊断、治疗或急救建议。如有持续不适或异常指标，请咨询医生。")
        return lines.joined(separator: "\n")
    }

    private func listText(_ values: [String], empty: String) -> String {
        values.isEmpty ? empty : values.joined(separator: "、")
    }

    private struct SanitizedDigest {
        struct Dimension {
            let title: String
            let status: String
            let score: Int?
            let trend: String
            let summary: String
        }

        let range: String
        let generatedAt: String
        let headline: String
        let status: String
        let growthScore: Int
        let topTags: [String]
        let topRisks: [String]
        let nextActions: [String]
        let recentChanges: [String]
        let dataQualityScore: Int
        let dataQualitySummary: String
        let missingData: [String]
        let dimensions: [Dimension]
        let evidence: [String]

        init(digest: HealthProfileAIDigest) {
            range = Self.clean(digest.range.title, limit: 32)
            generatedAt = ISO8601DateFormatter().string(from: digest.generatedAt)
            headline = Self.clean(digest.headline, limit: 160)
            status = Self.clean(digest.status, limit: 40)
            growthScore = max(0, min(100, digest.growthScore))
            topTags = Self.clean(digest.topTags, count: 3, itemLimit: 64)
            topRisks = Self.clean(digest.topRisks, count: 3, itemLimit: 80)
            nextActions = Self.clean(digest.nextActions, count: 3, itemLimit: 80)
            recentChanges = Self.clean(digest.recentChanges, count: 3, itemLimit: 80)
            dataQualityScore = max(0, min(100, digest.dataQualityScore))
            dataQualitySummary = Self.clean(digest.dataQualitySummary, limit: 120)
            missingData = Self.clean(digest.missingData, count: 4, itemLimit: 48)
            dimensions = digest.dimensions.prefix(7).compactMap { item in
                let title = Self.clean(item.title, limit: 40)
                guard !title.isEmpty else { return nil }
                return Dimension(
                    title: title,
                    status: Self.clean(item.status, limit: 48),
                    score: item.score.map { max(0, min(100, $0)) },
                    trend: Self.clean(item.trend, limit: 32),
                    summary: Self.clean(item.summary, limit: 120)
                )
            }
            evidence = Self.clean(digest.evidence, count: 8, itemLimit: 100)
        }

        private static func clean(_ values: [String], count: Int, itemLimit: Int) -> [String] {
            values.prefix(count).compactMap { value in
                let cleaned = clean(value, limit: itemLimit)
                return cleaned.isEmpty ? nil : cleaned
            }
        }

        private static func clean(_ value: String, limit: Int) -> String {
            let flattened = value
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            return String(flattened.prefix(limit))
        }
    }
}

/// 长期档案的本地确定性回答器，不经过通用文本 Provider。
struct HealthAIProfileLocalResponder {
    func answer(question: String, digest: HealthProfileAIDigest) -> HealthAIAnswerPayload {
        let basis = makeBasis(question: question, digest: digest)
        let actions = digest.nextActions.isEmpty
            ? ["继续积累关键模块的数据，再观察档案状态是否稳定。"]
            : Array(digest.nextActions.prefix(3))
        let risks = digest.topRisks.isEmpty
            ? ["当前没有足够证据形成稳定风险判断，仍需结合体感持续观察。"]
            : Array(digest.topRisks.prefix(3)).map { "持续留意：\($0)。" }
        let followUps = [
            "哪些数据最能提高档案可信度？",
            "下一阶段最值得坚持的习惯是什么？"
        ]
        let summary = makeSummary(digest: digest)

        return HealthAIAnswerPayload(
            summary: summary,
            basis: basis,
            actions: actions,
            risks: risks,
            followUps: followUps,
            rawMarkdown: makeMarkdown(
                summary: summary,
                basis: basis,
                actions: actions,
                risks: risks,
                followUps: followUps
            )
        )
    }

    private func makeSummary(digest: HealthProfileAIDigest) -> String {
        if digest.dataQualityScore < 55 || !digest.missingData.isEmpty {
            return String(localized: "档案仍在建立或补充依据，现阶段适合把结论视为观察线索，而不是稳定判断。\(digest.headline)")
        }
        if let risk = digest.topRisks.first {
            return String(localized: "当前档案已有一定连续性，最值得优先关注的是“\(risk)”。\(digest.headline)")
        }
        return String(localized: "当前档案状态为“\(digest.status)”，已有线索整体更适合用于保持节律并继续验证变化。\(digest.headline)")
    }

    private func makeBasis(question: String, digest: HealthProfileAIDigest) -> [String] {
        var basis = [
            "本次解读覆盖\(digest.range.title)，摘要生成于 \(formattedDate(digest.generatedAt))；数据可信度为 \(max(0, min(100, digest.dataQualityScore)))/100。\(digest.dataQualitySummary)"
        ]
        if question.contains("变化"), !digest.recentChanges.isEmpty {
            basis.append("近期变化包括：\(digest.recentChanges.prefix(3).joined(separator: "、"))。")
        } else if !digest.topTags.isEmpty {
            basis.append("当前较稳定的档案标签包括：\(digest.topTags.prefix(3).joined(separator: "、"))。")
        }
        if let dimension = prioritizedDimension(from: digest.dimensions) {
            let score = dimension.score.map { "，\(max(0, min(100, $0)))/100" } ?? ""
            basis.append("维度线索：\(dimension.title)为“\(dimension.status)”\(score)，趋势为“\(dimension.trend)”。")
        }
        var evidenceAndGaps: [String] = []
        if let evidence = digest.evidence.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            evidenceAndGaps.append("关键证据：\(String(evidence.prefix(100)))")
        }
        if !digest.missingData.isEmpty {
            evidenceAndGaps.append("仍需补充或授权：\(digest.missingData.prefix(4).joined(separator: "、"))")
        }
        if !evidenceAndGaps.isEmpty {
            basis.append(evidenceAndGaps.joined(separator: "；") + "。")
        }
        return Array(basis.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.prefix(4))
    }

    private func prioritizedDimension(from dimensions: [HealthProfileAIDimensionDigest]) -> HealthProfileAIDimensionDigest? {
        dimensions.first(where: { $0.trend == HealthProfileTrend.declining.title })
            ?? dimensions.first(where: { $0.score != nil })
            ?? dimensions.first
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func makeMarkdown(
        summary: String,
        basis: [String],
        actions: [String],
        risks: [String],
        followUps: [String]
    ) -> String {
        var lines = ["## 结论", summary, "", "## 依据"]
        lines.append(contentsOf: basis.map { "- \($0)" })
        lines.append(contentsOf: ["", "## 建议"])
        lines.append(contentsOf: actions.map { "- \($0)" })
        lines.append(contentsOf: ["", "## 留意"])
        lines.append(contentsOf: risks.map { "- \($0)" })
        lines.append(contentsOf: ["", "## 下一步可问"])
        lines.append(contentsOf: followUps.map { "- \($0)" })
        lines.append("")
        lines.append("仅供健康管理参考，不构成医疗诊断、治疗或急救建议。如有持续不适或异常指标，请咨询医生。")
        return lines.joined(separator: "\n")
    }
}
