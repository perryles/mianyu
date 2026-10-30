import SwiftUI

// MARK: - 健康压力估算器

/// 健康压力估算器
/// 基于 HRV、心率和静息心率估算实时压力值，供报告模块和当日压力曲线使用。
enum HealthStressEstimator {
    /// 根据单次 HRV 采样估算瞬时压力
    static func estimate(
        hrv: Double,
        heartRate: Double,
        restingHeartRate: Double?,
        hrvBaseline: Double? = nil,
        priorHeartRate: Double? = nil
    ) -> Int {
        StressDailyEngine.instantaneousStress(
            hrv: hrv,
            heartRate: heartRate,
            restingHeartRate: restingHeartRate,
            recentAvgHrv: hrvBaseline,
            priorHeartRate: priorHeartRate
        )
    }

    /// 获取今日压力时间序列（优先使用已合并的历史数据，否则实时估算）
    static func todayStressPoints(realtime: RealtimeHealth? = nil, history: HealthHistory? = nil) async -> [TimeSeriesPoint] {
        let calendar = Calendar.current
        let historyToday = mergedRealtimeIntoTodayHistory(realtime: realtime, history: history, calendar: calendar)
        if !historyToday.isEmpty {
            return historyToday
        }

        let start = calendar.startOfDay(for: Date())
        async let hrvSamples = try? HealthKitManager.shared.fetchTodayHRVSamples()
        async let heartRateSamples = try? HealthKitManager.shared.fetchHeartRateSeries(start: start, end: Date(), maxPoints: 180)
        async let resting = try? HealthKitManager.shared.fetchRestingHeartRate()

        let hrv = await hrvSamples ?? []
        let hr = await heartRateSamples ?? []
        let restingValue = await resting

        let intervalEnd = max(Date(), start.addingTimeInterval(1))
        let estimated = StressDailyEngine.sevenMinuteStressPoints(
            hrv: hrv,
            heartRate: hr,
            restingHeartRate: restingValue,
            in: DateInterval(start: start, end: intervalEnd)
        )

        if !estimated.isEmpty {
            return estimated
        }

        if let realtime, realtime.stress_value > 0 {
            return [TimeSeriesPoint(timestamp: realtime.timestamp, value: realtime.stress_value)]
        }

        return []
    }

    /// 按天估算历史压力序列（用于多日报告）
    static func estimateDailyStress(
        hrv: [TimeSeriesPointDouble],
        heartRate: [TimeSeriesPointDouble],
        restingHeartRate: [TimeSeriesPointDouble],
        restingHeartRateBaseline: Double? = nil
    ) -> [TimeSeriesPointDouble] {
        let calendar = Calendar.current
        let hrvByDay = dailyAverages(hrv, calendar: calendar)
        let hrByDay = dailyAverages(heartRate, calendar: calendar)
        let restingByDay = dailyAverages(restingHeartRate, calendar: calendar)
        let hrvBaseline = HealthBaselineStrategy.usableValue(
            for: Array(hrvByDay.values),
            metric: .hrvSDNN
        )
        let resolvedRestingHeartRateBaseline = StressDailyEngine.resolvedRestingHeartRateBaseline(
            measured: nil,
            historical: restingHeartRateBaseline,
            heartRate: hrByDay.map { day, value in
                TimeSeriesPoint(
                    timestamp: Int64(day.timeIntervalSince1970),
                    value: Int(value.rounded())
                )
            }
        )
        let days = Set(hrvByDay.keys).union(hrByDay.keys)

        return days.compactMap { day in
            let stress = estimate(
                hrv: hrvByDay[day] ?? 0,
                heartRate: hrByDay[day] ?? 0,
                restingHeartRate: restingByDay[day] ?? resolvedRestingHeartRateBaseline,
                hrvBaseline: hrvBaseline
            )
            guard stress > 0 else { return nil }
            return TimeSeriesPointDouble(timestamp: Int64(day.timeIntervalSince1970), value: Double(stress))
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    private static func dailyAverages(
        _ points: [TimeSeriesPointDouble],
        calendar: Calendar
    ) -> [Date: Double] {
        Dictionary(grouping: points) { calendar.startOfDay(for: $0.date) }
            .mapValues { samples in
                samples.map(\.value).reduce(0, +) / Double(samples.count)
            }
    }

    /// 将实时压力数据合并进当天历史序列，按 5 分钟窗口去重
    private static func mergedRealtimeIntoTodayHistory(realtime: RealtimeHealth?, history: HealthHistory?, calendar: Calendar) -> [TimeSeriesPoint] {
        var points = (history?.stressPoints ?? [])
            .filter { $0.value > 0 && calendar.isDateInToday($0.date) }

        if let realtime, realtime.stress_value > 0 {
            points.append(TimeSeriesPoint(timestamp: realtime.timestamp, value: realtime.stress_value))
        }

        guard !points.isEmpty else { return [] }

        var deduped: [Int64: TimeSeriesPoint] = [:]
        for point in points {
            deduped[point.timestamp / 300] = point
        }
        return deduped.values.sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - 报告解读引擎

/// 报告解读引擎
/// 负责将原始健康指标转化为可阅读的评分拆解、建议摘要、趋势上下文和周期洞察。
enum ReportInterpretationEngine {
    /// 根据五项指标生成综合评分拆解
    static func makeBreakdown(
        sleepHours: Double?,
        stress: Double?,
        hrv: Double?,
        steps: Double?,
        activeEnergy: Double?
    ) -> ReportScoreBreakdown? {
        let items = [
            sleepContribution(hours: sleepHours),
            stressContribution(stress: stress),
            hrvContribution(hrv: hrv),
            activityContribution(steps: steps, activeEnergy: activeEnergy)
        ]

        let availableItems = items.filter { $0.score != nil }
        guard !availableItems.isEmpty else { return nil }

        let sorted = availableItems.sorted {
            ($0.score ?? 0) < ($1.score ?? 0)
        }
        let leadingNegative = sorted.first
        let leadingPositive = sorted.last

        let headline: String = {
            if let leadingNegative, let score = leadingNegative.score, score <= 58 {
                return String(localized: "\(leadingNegative.kind.title)是今天的主要拖累。")
            }
            if let leadingPositive, let score = leadingPositive.score, score >= 82 {
                return String(localized: "\(leadingPositive.kind.title)是今天最明显的加分项。")
            }
            return String(localized: "今天整体有轻微波动，恢复基础还算可读。")
        }()

        return ReportScoreBreakdown(
            items: items,
            leadingPositiveKind: leadingPositive?.kind,
            leadingNegativeKind: leadingNegative?.kind,
            headline: headline
        )
    }

    /// 根据评分拆解和恢复脚本生成行动建议摘要
    static func makeAdviceSummary(
        breakdown: ReportScoreBreakdown?,
        recoveryScriptPlan: RecoveryScriptPlan?
    ) -> ReportAdviceSummary? {
        if let recoveryScriptPlan {
            let items = [recoveryScriptPlan.morningScript, recoveryScriptPlan.afternoonScript, recoveryScriptPlan.eveningScript]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return ReportAdviceSummary(
                title: recoveryScriptPlan.readinessBand.title,
                summary: recoveryScriptPlan.headline,
                actionItems: Array(items.prefix(3)),
                priorityText: priorityText(for: recoveryScriptPlan.readinessBand),
                tintHex: tintHex(for: recoveryScriptPlan.readinessBand)
            )
        }

        guard let leadingNegative = breakdown?.leadingNegative else { return nil }
        switch leadingNegative.kind {
        case .sleep:
            return ReportAdviceSummary(
                title: "先把睡眠补回来",
                summary: "今天更需要优先把睡眠和节律拉回稳定区间。",
                actionItems: ["今晚尽量提前收尾，保证固定入睡时间。", "白天避免额外透支，给晚间恢复留空间。"],
                priorityText: "优先恢复",
                tintHex: "5B8CFF"
            )
        case .stress:
            return ReportAdviceSummary(
                title: "先降压力负荷",
                summary: "当前更像是压力在拖累恢复状态，适合先降负荷再推进。",
                actionItems: ["把今天后半程安排收轻一点。", "优先做一次短时呼吸或散步放松。"],
                priorityText: "高优先级",
                tintHex: "FF8A5B"
            )
        case .hrv:
            return ReportAdviceSummary(
                title: "先把恢复弹性拉回来",
                summary: "HRV 偏低说明今天更适合守住恢复节奏，不适合硬顶强度。",
                actionItems: ["今天训练以轻量或恢复型安排为主。", "晚间减少刺激，把恢复窗口留足。"],
                priorityText: "优先恢复",
                tintHex: "8E6CFF"
            )
        case .activity:
            return ReportAdviceSummary(
                title: "补一点轻活动",
                summary: "活动量还没把状态带起来，适合补充一段轻活动唤醒节律。",
                actionItems: ["安排一段轻松步行或拉伸。", "不要久坐太久，把身体重新带动起来。"],
                priorityText: "轻推进",
                tintHex: "34C759"
            )
        }
    }

    /// 根据当前索引和摘要序列生成近 7 天趋势上下文
    static func makeTrendContext(
        currentIndex: Int,
        summaries: [ReportDaySummary]
    ) -> ReportTrendContext? {
        guard summaries.indices.contains(currentIndex) else { return nil }
        let window = Array(summaries[0...currentIndex].suffix(7)).filter { $0.score != nil }
        guard let current = summaries[currentIndex].score else { return nil }
        guard !window.isEmpty else { return nil }

        let average = Double(window.map(\.scoreValue).reduce(0, +)) / Double(window.count)
        let delta = Double(current) - average
        let comparisonText: String
        if delta >= 4 {
            comparisonText = "高于近7天均值 \(Int(delta.rounded())) 分"
        } else if delta <= -4 {
            comparisonText = "低于近7天均值 \(Int(abs(delta).rounded())) 分"
        } else {
            comparisonText = "与近7天均值基本持平"
        }

        let state: ReportTrendState = {
            guard window.count >= 6 else { return .stable }
            let previousValues = Array(window.dropLast(3)).suffix(3).map(\.scoreValue)
            let recentValues = Array(window.suffix(3)).map(\.scoreValue)
            guard !previousValues.isEmpty, !recentValues.isEmpty else { return .stable }
            let previousAverage = Double(previousValues.reduce(0, +)) / Double(previousValues.count)
            let recentAverage = Double(recentValues.reduce(0, +)) / Double(recentValues.count)
            let trendDelta = recentAverage - previousAverage
            if trendDelta >= 4 { return .recovering }
            if trendDelta <= -4 { return .strained }
            return .stable
        }()

        let summary = "\(comparisonText)，最近三天\(state.title)。"
        return ReportTrendContext(
            title: state.title,
            comparisonText: comparisonText,
            summary: summary,
            state: state
        )
    }

    /// 根据周期内的摘要序列生成周期洞察（周报/月报共用）
    static func periodInsight(from summaries: [ReportDaySummary], scope: String, healthProfile: HealthProfileSummary? = nil) -> ReportPeriodInsight? {
        if let healthProfile, healthProfile.dataQuality.score >= 55, let tag = healthProfile.tags.first {
            var details = [tag.detail]
            if let milestone = healthProfile.milestones.first {
                details.append("里程碑：\(milestone.title)。")
            }
            if let risk = healthProfile.riskTendencies.first {
                details.append("需要留意：\(risk.title)。")
            }
            if let action = healthProfile.actionRecommendations.first {
                details.append("下一步：\(action.title)。")
            }
            details.append("档案数据可信度 \(healthProfile.dataQuality.score)/100。")
            return ReportPeriodInsight(
                headline: "\(scope)长期画像：\(tag.title)",
                detail: details.joined(separator: " ")
            )
        }

        let valid = summaries.filter(\.hasData)
        guard !valid.isEmpty else { return nil }

        let negativeKinds = valid.compactMap { $0.scoreBreakdown?.leadingNegativeKind }
        let positiveKinds = valid.compactMap { $0.scoreBreakdown?.leadingPositiveKind }
        let primaryNegative = mostFrequentKind(in: negativeKinds)
        let primaryPositive = mostFrequentKind(in: positiveKinds)

        let scores = valid.compactMap(\.score)
        let scoreDelta: Int? = {
            guard let first = scores.first, let last = scores.last else { return nil }
            return last - first
        }()

        if let primaryNegative {
            let detail: String
            if let scoreDelta, scoreDelta <= -4 {
                detail = "\(scope)主要拖累来自\(primaryNegative.title)，而且后段评分在继续走弱。"
            } else {
                detail = "\(scope)最常见的拖累项是\(primaryNegative.title)，建议优先围绕这项做恢复调整。"
            }
            return ReportPeriodInsight(headline: "\(scope)主要拖累是\(primaryNegative.title)", detail: detail)
        }

        if let primaryPositive {
            return ReportPeriodInsight(
                headline: "\(scope)主要加分项是\(primaryPositive.title)",
                detail: "\(scope)整体没有明显短板，当前更多是\(primaryPositive.title)在托住状态。"
            )
        }

        return ReportPeriodInsight(
            headline: "\(scope)整体较平稳",
            detail: "这段时间没有出现特别集中的拖累项，适合继续维持当前节律。"
        )
    }

    // MARK: - 分项贡献计算

    /// 睡眠分项贡献
    private static func sleepContribution(hours: Double?) -> ReportScoreContribution {
        guard let hours, hours > 0 else {
            return ReportScoreContribution(kind: .sleep, score: nil, valueText: "--", detail: "暂无足够睡眠样本。", tone: .missing)
        }
        let score = max(0, min(100, Int((100 - abs(hours - 7.5) * 16).rounded())))
        let detail: String
        let tone: ReportContributionTone
        switch score {
        case 85...:
            detail = "睡眠时长接近理想区间，是今天的重要加分项。"
            tone = .positive
        case 65..<85:
            detail = "睡眠基础尚可，但还没有形成很稳的恢复优势。"
            tone = .neutral
        default:
            detail = "睡眠时长离理想区间偏远，是当前主要拖累之一。"
            tone = .caution
        }
        return ReportScoreContribution(kind: .sleep, score: score, valueText: String(format: "%.1f h", hours), detail: detail, tone: tone)
    }

    /// 压力分项贡献
    private static func stressContribution(stress: Double?) -> ReportScoreContribution {
        guard let stress, stress > 0 else {
            return ReportScoreContribution(kind: .stress, score: nil, valueText: "--", detail: "暂无足够压力样本。", tone: .missing)
        }
        let score = max(0, min(100, Int((100 - stress).rounded())))
        let detail: String
        let tone: ReportContributionTone
        switch stress {
        case ..<35:
            detail = "压力处在较低区间，对今天整体状态更友好。"
            tone = .positive
        case ..<65:
            detail = "压力处在可控范围，还没有明显拖累恢复。"
            tone = .neutral
        default:
            detail = "压力明显偏高，正在拉低今天的恢复质量。"
            tone = .caution
        }
        return ReportScoreContribution(kind: .stress, score: score, valueText: "\(Int(stress.rounded()))", detail: detail, tone: tone)
    }

    /// HRV 分项贡献
    private static func hrvContribution(hrv: Double?) -> ReportScoreContribution {
        guard let hrv, hrv > 0 else {
            return ReportScoreContribution(kind: .hrv, score: nil, valueText: "--", detail: "暂无足够 HRV 样本。", tone: .missing)
        }
        let score = max(0, min(100, Int((hrv * 1.4).rounded())))
        let detail: String
        let tone: ReportContributionTone
        switch score {
        case 80...:
            detail = "HRV 处在较有弹性的区间，对恢复有明显帮助。"
            tone = .positive
        case 60..<80:
            detail = "HRV 还算稳定，但弹性优势不算特别突出。"
            tone = .neutral
        default:
            detail = "HRV 偏低，说明今天的恢复弹性还没完全拉起来。"
            tone = .caution
        }
        return ReportScoreContribution(kind: .hrv, score: score, valueText: "\(Int(hrv.rounded())) ms", detail: detail, tone: tone)
    }

    /// 活动分项贡献
    private static func activityContribution(steps: Double?, activeEnergy: Double?) -> ReportScoreContribution {
        guard let steps, steps > 0 else {
            let energyText = activeEnergy.map { "\(Int($0.rounded())) kcal" } ?? "--"
            return ReportScoreContribution(kind: .activity, score: nil, valueText: energyText, detail: "暂无足够活动样本。", tone: .missing)
        }
        let score = max(0, min(100, Int((steps / 80.0).rounded())))
        let activityText = String(format: "%.1fk", steps / 1000.0)
        let detail: String
        let tone: ReportContributionTone
        switch score {
        case 80...:
            detail = "今天的活动量比较充足，整体节律被顺利带起来了。"
            tone = .positive
        case 60..<80:
            detail = "活动量处在基础区间，能支撑状态但还不算特别亮眼。"
            tone = .neutral
        default:
            detail = "活动量偏少，身体节律还没有被充分带动起来。"
            tone = .caution
        }
        return ReportScoreContribution(kind: .activity, score: score, valueText: activityText, detail: detail, tone: tone)
    }

    // MARK: - 辅助方法

    /// 恢复准备度→优先级文本
    private static func priorityText(for band: RecoveryReadinessBand) -> String {
        switch band {
        case .protect: return "高优先级"
        case .recover: return "优先恢复"
        case .balanced: return "正常安排"
        case .pushLight: return "轻推进"
        }
    }

    /// 恢复准备度→主题色 Hex
    private static func tintHex(for band: RecoveryReadinessBand) -> String {
        switch band {
        case .protect: return "F46B5A"
        case .recover: return "FF8A5B"
        case .balanced: return "34C759"
        case .pushLight: return "5B8CFF"
        }
    }

    /// 找出数组中出现频率最高的指标类型
    private static func mostFrequentKind(in kinds: [ReportMetricKind]) -> ReportMetricKind? {
        guard !kinds.isEmpty else { return nil }
        let counts = Dictionary(grouping: kinds, by: { $0 }).mapValues(\.count)
        return counts.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.rawValue > rhs.key.rawValue
            }
            return lhs.value < rhs.value
        }?.key
    }
}

// MARK: - 报告内容组合器

/// 报告内容组合器
/// 将评分、趋势、建议等原始数据组装成可直接展示给用户的 Takeaway 条目。
enum ReportContentComposer {
    /// 生成日报关键结论（最多 5 条）
    static func dailyTakeaways(summary: ReportDaySummary?, nearbyPoints: [ReportDaySummary]) -> [ReportsTakeaway] {
        guard let summary else {
            return [
                ReportsTakeaway(
                    title: "数据状态",
                    value: "等待同步",
                    detail: "同步睡眠、心率、HRV、压力或活动样本后，这里会生成当天解读。",
                    systemImage: "icloud.and.arrow.down",
                    tint: Color(hex: "8AA0B8")
                )
            ]
        }

        var items: [ReportsTakeaway] = [
            ReportsTakeaway(
                title: "综合状态",
                value: summary.score.map { "\($0)分" } ?? "暂无评分",
                detail: summary.scoreBreakdown?.headline ?? "当天样本还不够完整，先保留基础摘要。",
                    systemImage: "gauge",
                tint: ReportsScorePalette.tint(for: summary.score)
            ),
            ReportsTakeaway(
                title: "数据完整度",
                value: "\(availableMetricCount(in: summary))/5",
                detail: dataCoverageText(for: summary),
                    systemImage: "checklist",
                tint: Color(hex: "5B8CFF")
            )
        ]

        if let leadingPositive = summary.scoreBreakdown?.leadingPositive {
            items.append(
                ReportsTakeaway(
                    title: "主要加分",
                    value: leadingPositive.kind.title,
                    detail: leadingPositive.detail,
                    systemImage: leadingPositive.kind.systemImage,
                    tint: leadingPositive.kind.tint
                )
            )
        }

        if let leadingNegative = summary.scoreBreakdown?.leadingNegative, leadingNegative.tone == .caution {
            items.append(
                ReportsTakeaway(
                    title: "优先关注",
                    value: leadingNegative.kind.title,
                    detail: leadingNegative.detail,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: leadingNegative.kind.tint
                )
            )
        }

        if let trend = trendTakeaway(from: nearbyPoints, scope: "近7天") {
            items.append(trend)
        }

        if let action = summary.adviceSummary?.actionItems.first {
            items.append(
                ReportsTakeaway(
                    title: "下一步行动",
                    value: summary.adviceSummary?.priorityText ?? "建议",
                    detail: action,
                    systemImage: "figure.walk",
                    tint: summary.adviceSummary?.tint ?? Theme.Colors.mintGreen
                )
            )
        }

        return Array(items.prefix(5))
    }

    /// 生成周报/月报关键结论（最多 6 条）
    static func periodTakeaways(points: [ReportDaySummary], scope: String) -> [ReportsTakeaway] {
        let valid = points.filter { $0.score != nil || $0.hasData }
        guard !valid.isEmpty else {
            return [
                ReportsTakeaway(
                    title: "数据状态",
                    value: "暂无报告",
                    detail: "\(scope)还没有足够样本，继续同步后会自动整理趋势、波动和建议。",
                    systemImage: "calendar",
                    tint: Color(hex: "8AA0B8")
                )
            ]
        }

        let scores = valid.compactMap(\.score)
        let average = scores.isEmpty ? nil : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
        let best = valid.filter { $0.score != nil }.max { $0.scoreValue < $1.scoreValue }
        let weakest = valid.filter { $0.score != nil }.min { $0.scoreValue < $1.scoreValue }
        let primaryNegative = mostFrequentKind(valid.compactMap { $0.scoreBreakdown?.leadingNegativeKind })
        let primaryPositive = mostFrequentKind(valid.compactMap { $0.scoreBreakdown?.leadingPositiveKind })

        var items: [ReportsTakeaway] = [
            ReportsTakeaway(
                title: "有效报告",
                value: "\(valid.count)天",
                detail: "本段时间已纳入 \(valid.count) 天健康样本，覆盖越完整，结论越稳定。",
                systemImage: "doc.text.magnifyingglass",
                tint: Color(hex: "5B8CFF")
            ),
            ReportsTakeaway(
                title: "平均状态",
                value: average.map { "\($0)分" } ?? "暂无评分",
                detail: average.map { periodAverageText(score: $0, scope: scope) } ?? "已有部分健康样本，但评分条件还不完整。",
                systemImage: "chart.line.uptrend.xyaxis",
                tint: ReportsScorePalette.tint(for: average)
            )
        ]

        if let best {
            items.append(
                ReportsTakeaway(
                    title: "表现最好",
                    value: best.date.reportsShortDateString(),
                    detail: "综合评分 \(best.scoreValue) 分，适合回看当天睡眠、活动和压力安排。",
                    systemImage: "star.fill",
                    tint: Theme.Colors.mintGreen
                )
            )
        }

        if let weakest, best?.id != weakest.id {
            items.append(
                ReportsTakeaway(
                    title: "波动低点",
                    value: weakest.date.reportsShortDateString(),
                    detail: "综合评分 \(weakest.scoreValue) 分，优先复盘当天的恢复和压力负荷。",
                    systemImage: "arrow.down.circle.fill",
                    tint: Color(hex: "F46B5A")
                )
            )
        }

        if let primaryNegative {
            items.append(
                ReportsTakeaway(
                    title: "主要拖累",
                    value: primaryNegative.title,
                    detail: "\(scope)最常见的短板来自\(primaryNegative.title)，建议优先围绕这项做调整。",
                    systemImage: primaryNegative.systemImage,
                    tint: primaryNegative.tint
                )
            )
        } else if let primaryPositive {
            items.append(
                ReportsTakeaway(
                    title: "主要支撑",
                    value: primaryPositive.title,
                    detail: "\(scope)\(primaryPositive.title)相对稳定，是当前状态的主要支撑。",
                    systemImage: primaryPositive.systemImage,
                    tint: primaryPositive.tint
                )
            )
        }

        if let trend = trendTakeaway(from: valid, scope: scope) {
            items.append(trend)
        }

        if let action = weakest?.adviceSummary?.actionItems.first {
            items.append(
                ReportsTakeaway(
                    title: "恢复优先项",
                    value: weakest?.adviceSummary?.priorityText ?? "建议",
                    detail: action,
                    systemImage: "checkmark.seal.fill",
                    tint: weakest?.adviceSummary?.tint ?? Theme.Colors.mintGreen
                )
            )
        }

        return Array(items.prefix(6))
    }

    // MARK: - 辅助方法

    /// 统计已有有效指标的个数
    private static func availableMetricCount(in summary: ReportDaySummary) -> Int {
        [summary.score.map { _ in true },
         summary.sleepHours.map { _ in true },
         summary.stress.map { _ in true },
         summary.hrv.map { _ in true },
         summary.steps.map { _ in true }]
            .compactMap { $0 }
            .filter { $0 }
            .count
    }

    /// 生成数据覆盖率描述文本
    private static func dataCoverageText(for summary: ReportDaySummary) -> String {
        let missing = [
            summary.sleepHours == nil ? "睡眠" : nil,
            summary.stress == nil ? "压力" : nil,
            summary.hrv == nil ? "HRV" : nil,
            summary.steps == nil ? "活动" : nil
        ].compactMap { $0 }

        if missing.isEmpty {
            return String(localized: "睡眠、压力、HRV 和活动样本都已覆盖，今天的报告可信度较高。")
        }
        return "仍缺少\(missing.joined(separator: "、"))样本，结论会先以已有数据为主。"
    }

    /// 根据周期平均分生成解读文本
    private static func periodAverageText(score: Int, scope: String) -> String {
        switch score {
        case 85...:
            return String(localized: "\(scope)整体恢复基础较好，可以继续保持当前节律。")
        case 70..<85:
            return String(localized: "\(scope)整体稳定，但仍有可优化的小波动。")
        case 50..<70:
            return String(localized: "\(scope)出现一定波动，建议优先守住睡眠和压力恢复。")
        default:
            return String(localized: "\(scope)恢复压力偏高，需要先降低负荷再推进训练或工作强度。")
        }
    }

    /// 根据评分序列生成趋势变化 Takeaway
    private static func trendTakeaway(from points: [ReportDaySummary], scope: String) -> ReportsTakeaway? {
        let scored = points.filter { $0.score != nil }.sorted { $0.date < $1.date }
        guard let first = scored.first, let last = scored.last, first.id != last.id else { return nil }
        let delta = last.scoreValue - first.scoreValue
        let value: String
        let detail: String
        let tint: Color
        if delta >= 4 {
            value = "+\(delta)分"
            detail = "\(scope)评分正在回升，说明近期恢复安排开始变得更友好。"
            tint = Theme.Colors.mintGreen
        } else if delta <= -4 {
            value = "\(delta)分"
            detail = "\(scope)评分走弱，建议先减少透支，把恢复窗口留出来。"
            tint = Color(hex: "F46B5A")
        } else {
            value = "基本持平"
            detail = "\(scope)评分变化不大，当前更适合做细节优化。"
            tint = Color(hex: "5B8CFF")
        }
        return ReportsTakeaway(
            title: "趋势变化",
            value: value,
            detail: detail,
            systemImage: delta < -3 ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis",
            tint: tint
        )
    }

    /// 找出数组中出现频率最高的指标类型
    private static func mostFrequentKind(_ kinds: [ReportMetricKind]) -> ReportMetricKind? {
        guard !kinds.isEmpty else { return nil }
        let counts = Dictionary(grouping: kinds, by: { $0 }).mapValues(\.count)
        return counts.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.rawValue > rhs.key.rawValue
            }
            return lhs.value < rhs.value
        }?.key
    }
}
