import Foundation

nonisolated struct StressFocusCapacityTrendSnapshot: Sendable {
    let points: [TimeSeriesPoint]
    let averageValue: Int?
    let peakPoint: TimeSeriesPoint?
    let lowPoint: TimeSeriesPoint?
    let highRangeSampleCount: Int
    let midRangeSampleCount: Int
    let lowRangeSampleCount: Int

    init(
        assessment: StressFocusCapacityAssessment,
        stressPoints: [TimeSeriesPoint],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        var resolvedPoints = stressPoints
            .filter { $0.date >= dayStart && $0.date < dayEnd }
            .sorted { $0.timestamp < $1.timestamp }
            .map {
                TimeSeriesPoint(
                    timestamp: $0.timestamp,
                    value: StressFocusCapacityEngine.estimatedScore(stressScore: $0.value)
                )
            }

        if let score = assessment.score {
            let nowTimestamp = Int64(now.timeIntervalSince1970)
            if resolvedPoints.isEmpty || abs((resolvedPoints.last?.timestamp ?? 0) - nowTimestamp) > 600 {
                resolvedPoints.append(TimeSeriesPoint(timestamp: nowTimestamp, value: score))
            }
        }

        points = resolvedPoints
        if resolvedPoints.isEmpty {
            averageValue = assessment.score
            peakPoint = nil
            lowPoint = nil
        } else {
            averageValue = Int(
                (Double(resolvedPoints.reduce(0) { $0 + $1.value }) / Double(resolvedPoints.count)).rounded()
            )
            peakPoint = resolvedPoints.max { $0.value < $1.value }
            lowPoint = resolvedPoints.min { $0.value < $1.value }
        }
        highRangeSampleCount = resolvedPoints.reduce(0) { $0 + ($1.value >= 80 ? 1 : 0) }
        midRangeSampleCount = resolvedPoints.reduce(0) { $0 + ((55..<80).contains($1.value) ? 1 : 0) }
        lowRangeSampleCount = resolvedPoints.reduce(0) { $0 + ($1.value < 55 ? 1 : 0) }
    }
}

nonisolated enum StressFocusCapacityPresentation {
    static let subtitle = "结合压力、恢复、睡眠、节律、活动与补水，查看当前更适合推进哪种强度的任务。"
    static let dimensionsTitle = "六维构成"

    static func statusText(for assessment: StressFocusCapacityAssessment) -> String {
        statusText(for: assessment.band)
    }

    static func statusText(forScore score: Int?) -> String {
        guard let score else { return statusText(for: .unavailable) }
        return statusText(for: StressFocusCapacityEngine.band(for: score))
    }

    static func summary(for assessment: StressFocusCapacityAssessment) -> String {
        summary(for: assessment.band)
    }

    static func summary(forScore score: Int?) -> String {
        guard let score else { return summary(for: .unavailable) }
        return summary(for: StressFocusCapacityEngine.band(for: score))
    }

    private static func statusText(for band: StressFocusCapacityBand) -> String {
        switch band {
        case .strong: return "适合深度专注"
        case .available: return "适合推进重点"
        case .limited: return "适合短段处理"
        case .depleted: return "先降负荷"
        case .unavailable: return "等待数据"
        }
    }

    private static func summary(for band: StressFocusCapacityBand) -> String {
        switch band {
        case .strong:
            return String(localized: "当前压力余量与恢复状态较好，可以安排一段相对完整的重点任务，中间保留短恢复。")
        case .available:
            return String(localized: "当前具备可用的专注条件，更适合 20 到 35 分钟的小块推进，减少频繁切换。")
        case .limited:
            return String(localized: "压力或恢复状态正在压缩专注窗口，先处理短任务，把复杂工作拆小或后移。")
        case .depleted:
            return String(localized: "当前任务条件偏紧，先离屏、补水或走动几分钟，再用一个短任务重新判断状态。")
        case .unavailable:
            return String(localized: "继续保持佩戴并同步压力与恢复数据后，这里会显示更完整的今日判断。")
        }
    }

    static let methodBullets = [
        "核心维度是非线性压力余量与身体电量，高压力或恢复不足都会明显压缩专注窗口。",
        "睡眠时长与评分用于估计认知储备，醒后时长用于修正当前昼夜节律窗口。",
        "连续久坐会降低活动刷新分；补水按醒后时长校正，避免早晨用全天目标误判。",
        "缺失维度不会按 0 分处理，而是退出加权并降低置信度；分数偏低也不代表能力变差。"
    ]

    static let disclaimer = "专注能力由压力、恢复、睡眠、节律、活动与补水数据估算，用于安排任务节奏参考，不是认知能力或注意力障碍评估，也不构成医疗诊断或治疗建议。"

    static let shareMethod = "由六维任务状态模型估算"

    static func metricItems(for assessment: StressFocusCapacityAssessment) -> [StressFocusCapacityMetricItem] {
        [
            StressFocusCapacityMetricItem(
                title: "压力余量",
                valueText: scoreText(assessment.stressHeadroom),
                note: assessment.stressHeadroom == nil ? "等待综合压力" : "高压力区间采用非线性扣减"
            ),
            StressFocusCapacityMetricItem(
                title: "身体电量",
                valueText: scoreText(assessment.bodyBatteryScore),
                note: assessment.bodyBatteryScore == nil ? "等待恢复与日内消耗" : "反映恢复底盘与持续消耗"
            ),
            StressFocusCapacityMetricItem(
                title: "睡眠储备",
                valueText: scoreText(assessment.sleepReadiness),
                note: assessment.sleepReadiness == nil ? "等待睡眠时长与评分" : "按睡眠目标和睡眠评分合成"
            ),
            StressFocusCapacityMetricItem(
                title: "昼夜节律",
                valueText: scoreText(assessment.circadianReadiness),
                note: assessment.circadianReadiness == nil ? "等待有效醒来时间" : "按醒后时长识别当前清醒窗口"
            ),
            StressFocusCapacityMetricItem(
                title: "活动刷新",
                valueText: scoreText(assessment.movementReadiness),
                note: assessment.movementReadiness == nil ? "等待久坐状态" : "连续静坐越久，任务条件越保守"
            ),
            StressFocusCapacityMetricItem(
                title: "补水进度",
                valueText: scoreText(assessment.hydrationReadiness),
                note: assessment.hydrationReadiness == nil ? "记录饮水后参与估算" : "按醒后时长比较应有进度"
            )
        ]
    }

    static func dataQualityTitle(for assessment: StressFocusCapacityAssessment) -> String {
        switch assessment.availableDimensionCount {
        case 5...: return "多维数据较完整"
        case 3..<5: return "多维数据可参考"
        case 1..<3: return "有限维度估算"
        default: return "等待同步"
        }
    }

    static func dataQualityDetail(for assessment: StressFocusCapacityAssessment) -> String {
        guard assessment.availableDimensionCount > 0 else {
            return String(localized: "保持佩戴并同步健康数据后，这里会更新六维任务状态。")
        }
        let confidenceText = assessment.confidence.map { "，综合置信度 \(Int(($0 * 100).rounded()))%" } ?? ""
        return String(localized: "当前接入 \(assessment.availableDimensionCount)/6 个维度\(confidenceText)，缺失项未按 0 分处理。")
    }

    static let scaleItems = [
        StressFocusCapacityScaleItem(range: "80-100", meaning: "适合深度专注和复杂任务。"),
        StressFocusCapacityScaleItem(range: "55-79", meaning: "适合推进重点，但要留间隔。"),
        StressFocusCapacityScaleItem(range: "30-54", meaning: "适合短段处理和低阻力任务。"),
        StressFocusCapacityScaleItem(range: "0-29", meaning: "先降负荷，复杂任务延后。")
    ]

    static let observationItems = [
        StressFocusCapacityContentItem(
            symbol: "waveform.path.ecg",
            title: "看压力是否继续抬升",
            detail: "综合压力继续上行时，专注窗口通常会变短。"
        ),
        StressFocusCapacityContentItem(
            symbol: "speaker.wave.2.fill",
            title: "看环境刺激",
            detail: "噪声、通知和频繁切换会放大低分状态的影响。"
        ),
        StressFocusCapacityContentItem(
            symbol: "timer",
            title: "看一段任务后的回落",
            detail: "如果一段任务后分数继续下滑，就适合先暂停恢复。"
        )
    ]

    static func rangeAdvice(forScore score: Int?) -> String {
        guard let score else {
            return String(localized: "继续同步综合压力与身体电量所需的健康样本，专注任务条件会自动更新。")
        }
        switch StressFocusCapacityEngine.band(for: score) {
        case .strong:
            return String(localized: "这段时间压力余量与恢复状态较好，适合安排深度工作、学习或复杂决策，并在完整专注块之间保留短恢复。")
        case .available:
            return String(localized: "当前具备推进重点任务的条件，更适合 30 到 45 分钟一段，减少通知和频繁切换。")
        case .limited:
            return String(localized: "压力或恢复状态正在压缩专注窗口。先处理短任务和低阻力事项，把复杂工作拆小或后移。")
        case .depleted:
            return String(localized: "当前不适合长时间硬顶复杂任务。先离屏、喝水或走动几分钟，再用一个短任务重新判断状态。")
        case .unavailable:
            return String(localized: "继续同步综合压力与身体电量所需的健康样本，专注任务条件会自动更新。")
        }
    }

    static func scenarioItems(forScore score: Int?) -> [StressFocusCapacityContentItem] {
        guard let score else {
            return [
                StressFocusCapacityContentItem(symbol: "applewatch", title: "等待同步", detail: "先等压力与恢复样本回来，再判断今天的专注窗口。"),
                StressFocusCapacityContentItem(symbol: "timer", title: "先小块开始", detail: "不确定状态时，先用一段短任务试探当前专注手感。")
            ]
        }
        switch StressFocusCapacityEngine.band(for: score) {
        case .strong:
            return [
                StressFocusCapacityContentItem(symbol: "scope", title: "适合深工", detail: "适合写作、方案、代码、学习这类需要连续思考的任务。"),
                StressFocusCapacityContentItem(symbol: "timer", title: "适合长块", detail: "可以安排 45 到 60 分钟专注块，中间留 5 到 10 分钟恢复。")
            ]
        case .available:
            return [
                StressFocusCapacityContentItem(symbol: "rectangle.stack.fill", title: "适合推进", detail: "适合邮件、整理、复盘、常规沟通这类中等难度任务。"),
                StressFocusCapacityContentItem(symbol: "timer", title: "适合短块", detail: "用 20 到 35 分钟一段的节奏，减少频繁切换。")
            ]
        case .limited, .depleted:
            return [
                StressFocusCapacityContentItem(symbol: "tray.full.fill", title: "适合清杂", detail: "优先处理低阻力事项，不建议现在挑战复杂决策。"),
                StressFocusCapacityContentItem(symbol: "pause.circle.fill", title: "适合缓冲", detail: "先做呼吸、喝水或起身，再决定是否继续推进。")
            ]
        case .unavailable:
            return []
        }
    }

    static func actionPlan(hasData: Bool) -> [String] {
        [
            hasData ? "把最重要的一件事切成一段可完成的小块。" : "先等同步完成，再判断今天的专注窗口。",
            "尽量把分心源头放到视线外，减少来回切换。",
            "分数偏低时，把复杂任务拆成 20 到 35 分钟的小段。"
        ]
    }

    private static func scoreText(_ score: Int?) -> String {
        score.map { "\($0)/100" } ?? "--"
    }
}
