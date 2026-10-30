import Foundation

struct BodyIndexPersonalizedContent: Equatable, Sendable {
    let headline: String
    let detail: String
    let facts: [BodyIndexPersonalizedFact]
    let actions: [String]
}

struct BodyIndexPersonalizedFact: Equatable, Sendable {
    let title: String
    let value: String
    let symbol: String
}

struct BodyIndexPersonalizationMotion: Equatable, Sendable {
    let ambientScale: Double
    let ambientOpacity: Double
    let primaryNodeScale: Double
    let weatherOffset: Double

    static let `static` = BodyIndexPersonalizationMotion(
        ambientScale: 1,
        ambientOpacity: 0.055,
        primaryNodeScale: 1,
        weatherOffset: 0
    )

    static func resolve(reduceMotion: Bool, isActive: Bool) -> BodyIndexPersonalizationMotion {
        guard !reduceMotion else { return .static }
        return BodyIndexPersonalizationMotion(
            ambientScale: isActive ? 1.14 : 0.94,
            ambientOpacity: isActive ? 0.105 : 0.035,
            primaryNodeScale: isActive ? 1.08 : 0.96,
            weatherOffset: isActive ? -2.5 : 2
        )
    }
}

struct BodyIndexPersonalizationContext: Equatable, Sendable {
    var hrvBaseline: Double?
    var restingHeartRateBaseline: Double?
    var stressScore: Int?
    var sleepMinutes: Int?
    var sleepScore: Int?
    var recentVO2Max: Double?
    var vo2SourceText: String?
    var walkingSpeedMps: Double?

    static let empty = BodyIndexPersonalizationContext()
}

enum BodyIndexPersonalization {
    static func content(
        for destination: DashboardOtherMetricDestination,
        points: [TimeSeriesPointDouble],
        currentValue: Double?,
        heartRhythmResult: HeartRhythmStabilityResult,
        context: BodyIndexPersonalizationContext = .empty
    ) -> BodyIndexPersonalizedContent {
        let values = points.map(\.value)
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let latest = currentValue ?? values.last

        switch destination {
        case .hrv:
            let comparison = comparisonText(latest: latest, average: average, higherIsBetter: true)
            return .init(
                headline: comparison.headline,
                detail: "这是基于你所选周期内 HRV 样本的个人比较，不与他人横向排名。\(comparison.detail)",
                facts: [
                    fact("当前 HRV", metric(latest, unit: "ms"), "waveform.path.ecg"),
                    fact("个人基线", metric(context.hrvBaseline ?? average, unit: "ms"), "scope"),
                    fact("昨夜睡眠", context.sleepMinutes.map { "\($0) 分钟" } ?? "暂无", "bed.double.fill"),
                    fact("今日压力", context.stressScore.map { "\($0) 分" } ?? "暂无", "brain.head.profile")
                ],
                actions: ["今晚优先守住稳定睡眠窗口", "恢复偏紧时减少额外高强度负荷"]
            )
        case .restingHeartRate:
            let comparison = comparisonText(latest: latest, average: average, higherIsBetter: false)
            return .init(
                headline: comparison.headline,
                detail: "静息心率会结合你自己的周期均值判断。\(comparison.detail)",
                facts: [
                    fact("当前静息心率", metric(latest, unit: "bpm"), "heart.fill"),
                    fact("个人基线", metric(context.restingHeartRateBaseline ?? average, unit: "bpm"), "scope"),
                    fact("HRV 基线", metric(context.hrvBaseline, unit: "ms"), "waveform.path.ecg"),
                    fact("睡眠评分", context.sleepScore.map { "\($0) 分" } ?? "暂无", "moon.stars.fill")
                ],
                actions: ["在相近时间与状态下继续记录", "持续高于个人常态时优先补水和恢复"]
            )
        case .vo2Max:
            let delta = trendDelta(points)
            return .init(
                headline: delta.map { $0 >= 0 ? "你的心肺趋势正在维持或提升" : "你的心肺趋势近期有所回落" } ?? "正在建立你的心肺趋势",
                detail: "最大摄氧量是慢变量，会优先参考你自己的连续估算，而不是单日变化。",
                facts: [
                    fact("当前估算", metric(latest, unit: "ml/kg/min", digits: 1), "lungs.fill"),
                    fact("近期均值", metric(context.recentVO2Max ?? average, unit: "ml/kg/min", digits: 1), "chart.line.uptrend.xyaxis"),
                    fact("数据来源", context.vo2SourceText ?? "等待样本", "applewatch"),
                    fact("趋势样本", "\(points.count) 个", "point.3.connected.trianglepath.dotted")
                ],
                actions: ["每周安排规律的中等强度有氧", "用数周方向评估训练是否适合你"]
            )
        case .wristTemperature:
            let deviation = latest.flatMap { value in average.map { value - $0 } }
            return .init(
                headline: deviation.map { abs($0) <= 0.3 ? "最近夜间温度接近你的周期基线" : "最近夜间温度偏离你的周期基线" } ?? "正在建立你的夜间温度基线",
                detail: "手腕温度按你的夜间均值比较；环境、经期、饮酒和身体状态都可能造成偏移。",
                facts: [
                    fact("最近夜间值", metric(latest, unit: "℃", digits: 1), "thermometer.medium"),
                    fact("周期基线", metric(average, unit: "℃", digits: 1), "scope"),
                    fact("相对偏移", deviation.map { String(format: "%+.1f ℃", $0) } ?? "暂无", "arrow.left.and.right"),
                    fact("有效夜晚", "\(points.count) 晚", "moon.stars.fill")
                ],
                actions: ["保持卧室与佩戴条件稳定", "连续偏移并伴随不适时用体温计复测"]
            )
        case .sunlight:
            let minutes = max(0, latest ?? 0)
            let gap = max(0, 20 - Int(minutes.rounded()))
            return .init(
                headline: gap == 0 ? "今天已达到你的日照参考目标" : "今天还可补约 \(gap) 分钟自然光",
                detail: "结合你的当日日照记录与当前位置环境，优先选择舒适、紫外线不过强的时段。",
                facts: [],
                actions: ["利用通勤或散步顺手补光", "紫外线偏强时缩短时长并选择遮阴路线"]
            )
        case .walkingAsymmetry:
            let value = latest
            return .init(
                headline: value.map { $0 <= 10 ? "你的最近步态处在较稳定区间" : "你的最近步态不对称需要多留意" } ?? "正在建立你的步态基线",
                detail: "判断会优先参考你自己的连续步态记录，并结合疲劳、鞋履与活动负荷理解。",
                facts: [
                    fact("最近不对称", metric(latest, unit: "%", digits: 1), "figure.walk"),
                    fact("周期均值", metric(average, unit: "%", digits: 1), "equal.circle.fill"),
                    fact("今日步速", metric(context.walkingSpeedMps, unit: "m/s", digits: 2), "speedometer"),
                    fact("偏高样本", "\(values.filter { $0 > 10 }.count) 个", "exclamationmark.triangle.fill")
                ],
                actions: ["今天优先选择平稳路面", "连续偏高或伴随疼痛时降低冲击活动"]
            )
        case .heartRhythm:
            let clues = heartRhythmResult.suspectedAtrialFibrillationCount + heartRhythmResult.suspectedEctopicCount
            return .init(
                headline: heartRhythmResult.hasData ? (clues == 0 ? "你的观察窗口内未见明显异常线索" : "你的观察窗口内出现 \(clues) 次异常线索") : "正在建立你的心律参考",
                detail: "结果只聚合你的房颤负担、心律通知和 ECG 结论，不用于替代医疗诊断。",
                facts: [
                    fact("稳定评分", heartRhythmResult.score.map { "\($0) 分" } ?? "暂无", "gauge.with.dots.needle.50percent"),
                    fact("分类记录", "\(heartRhythmResult.classifiedTotal) 次", "waveform.path.ecg.rectangle"),
                    fact("异常线索", "\(clues) 次", "exclamationmark.heart.fill"),
                    fact("心率事件", "\(heartRhythmResult.heartRateEventCount) 次", "heart.text.square.fill")
                ],
                actions: ["保持 Apple Watch 规律佩戴", "持续心悸、胸闷或异常提示时及时就医"]
            )
        }
    }

    private static func fact(_ title: String, _ value: String, _ symbol: String) -> BodyIndexPersonalizedFact {
        .init(title: title, value: value, symbol: symbol)
    }

    private static func metric(_ value: Double?, unit: String, digits: Int = 0) -> String {
        guard let value, value.isFinite else { return "暂无" }
        return "\(String(format: "%.*f", digits, value)) \(unit)"
    }

    private static func trendDelta(_ points: [TimeSeriesPointDouble]) -> Double? {
        guard let first = points.first?.value, let last = points.last?.value, points.count > 1 else { return nil }
        return last - first
    }

    private static func comparisonText(latest: Double?, average: Double?, higherIsBetter: Bool) -> (headline: String, detail: String) {
        guard let latest, let average, average > 0 else {
            return ("正在建立你的个人基线", "继续积累相同条件下的记录后，会给出更贴近你的比较。")
        }
        let difference = (latest - average) / average
        if abs(difference) < 0.05 {
            return ("最近数值接近你的周期常态", "当前与个人均值差异较小。")
        }
        let favorable = higherIsBetter ? difference > 0 : difference < 0
        return favorable
            ? ("最近数值优于你的周期常态", "当前相对个人均值向更有利的方向变化。")
            : ("最近数值偏离你的周期常态", "先结合睡眠、负荷和身体感受观察是否持续。")
    }
}
