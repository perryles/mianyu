import Foundation

enum MentalRecoveryBand: String, Sendable {
    case steady
    case watch
    case elevated

    var title: String {
        switch self {
        case .steady:
            return "恢复稳定"
        case .watch:
            return String(localized: "负荷累积")
        case .elevated:
            return "优先恢复"
        }
    }

    var accentHex: String {
        switch self {
        case .steady:
            return "37B36B"
        case .watch:
            return "F0A43A"
        case .elevated:
            return "E76D5B"
        }
    }
}

struct MentalRecoveryAction: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let accentHex: String
}

struct MentalRecoveryTrendPoint: Identifiable, Hashable, Sendable {
    let date: Date
    let moodLoad: Double
    let sleepRecovery: Double?
    let selfObservationLoad: Double?

    var id: TimeInterval { date.timeIntervalSince1970 }
}

struct MentalRecoverySnapshot: Sendable {
    let referenceDate: Date
    let band: MentalRecoveryBand
    let overallScore: Int
    let headline: String
    let summary: String
    let moodLoad: Int
    let bodyStressLoad: Int
    let sleepRecoveryScore: Int?
    let assessmentLoad: Int?
    let selfObservationLoad: Int?
    let dominantMoodTitle: String?
    let repeatedHeavyDays: Int
    let averageIntensity: Int?
    let linkTitle: String
    let linkBody: String
    let actions: [MentalRecoveryAction]
    let cautionText: String?
    let trend: [MentalRecoveryTrendPoint]
    let dataNote: String
}

struct MentalRecoveryAnalyzer {
    var calendar: Calendar = .current

    func analyze(
        referenceDate: Date,
        moodEntries: [MoodEntry],
        sleepSummaries: [SleepTrendNightSummary],
        nightlyHrv: [HealthKitManager.NightlyHRV],
        restingHeartRateSeries: [TimeSeriesPointDouble],
        selfObservationSummaries: [SelfObservationDailySummary],
        currentStress: Int?,
        latestGAD7: MentalAssessmentResult?,
        latestPHQ9: MentalAssessmentResult?
    ) -> MentalRecoverySnapshot {
        let normalizedReferenceDate = calendar.startOfDay(for: referenceDate)
        let windowStart = calendar.date(byAdding: .day, value: -6, to: normalizedReferenceDate) ?? normalizedReferenceDate
        let nextDay = calendar.date(byAdding: .day, value: 1, to: normalizedReferenceDate) ?? normalizedReferenceDate

        let recentMoodEntries = moodEntries
            .filter { $0.loggedAt >= windowStart && $0.loggedAt < nextDay }
            .sorted { $0.loggedAt < $1.loggedAt }
        let recentSleep = sleepSummaries
            .filter { calendar.startOfDay(for: $0.day) >= windowStart && calendar.startOfDay(for: $0.day) <= normalizedReferenceDate }
            .sorted { $0.day < $1.day }
        let recentNightlyHrv = nightlyHrv
            .filter { calendar.startOfDay(for: $0.date) >= windowStart && calendar.startOfDay(for: $0.date) <= normalizedReferenceDate }
            .sorted { $0.date < $1.date }
        let recentResting = restingHeartRateSeries
            .filter { calendar.startOfDay(for: $0.date) >= windowStart && calendar.startOfDay(for: $0.date) <= normalizedReferenceDate }
            .sorted { $0.date < $1.date }
        let recentSelfObservationSummaries = selfObservationSummaries
            .filter { calendar.startOfDay(for: $0.date) >= windowStart && calendar.startOfDay(for: $0.date) <= normalizedReferenceDate }
            .sorted { $0.date < $1.date }

        let groupedMoodEntries = Dictionary(grouping: recentMoodEntries) {
            calendar.startOfDay(for: $0.loggedAt)
        }
        let trend = buildTrend(
            windowStart: windowStart,
            referenceDate: normalizedReferenceDate,
            moodEntriesByDay: groupedMoodEntries,
            sleepSummaries: recentSleep,
            selfObservationSummaries: recentSelfObservationSummaries
        )

        let moodLoad = resolvedMoodLoad(from: recentMoodEntries)
        let averageIntensity = averageIntensity(for: recentMoodEntries)
        let dominantMoodTitle = dominantMoodTitle(for: recentMoodEntries)
        let repeatedHeavyDays = trend.filter { $0.moodLoad >= 62 }.count
        let sleepRecoveryScore = resolvedSleepRecovery(from: recentSleep)
        let sleepLoad = sleepRecoveryScore.map { max(0, 100 - $0) } ?? 48
        let bodySignalLoad = resolvedBodySignalLoad(
            currentStress: currentStress,
            nightlyHrv: recentNightlyHrv,
            restingHeartRateSeries: recentResting
        )
        let assessmentLoad = resolvedAssessmentLoad(
            referenceDate: normalizedReferenceDate,
            gad7: latestGAD7,
            phq9: latestPHQ9
        )
        let selfObservationLoad = resolvedSelfObservationLoad(from: recentSelfObservationSummaries)
        let overallScore = blendedScore(
            moodLoad: moodLoad,
            bodyLoad: bodySignalLoad,
            sleepLoad: sleepLoad,
            selfObservationLoad: selfObservationLoad,
            assessmentLoad: assessmentLoad
        )
        let band: MentalRecoveryBand
        switch overallScore {
        case ..<38:
            band = .steady
        case ..<64:
            band = .watch
        default:
            band = .elevated
        }

        let headline = headline(for: band, sleepRecoveryScore: sleepRecoveryScore, repeatedHeavyDays: repeatedHeavyDays)
        let summary = summary(
            band: band,
            dominantMoodTitle: dominantMoodTitle,
            moodLoad: moodLoad,
            bodyLoad: bodySignalLoad,
            sleepRecoveryScore: sleepRecoveryScore,
            selfObservationLoad: selfObservationLoad,
            repeatedHeavyDays: repeatedHeavyDays
        )
        let linkNarrative = linkageNarrative(
            dominantMoodTitle: dominantMoodTitle,
            moodLoad: moodLoad,
            bodyLoad: bodySignalLoad,
            sleepRecoveryScore: sleepRecoveryScore,
            selfObservationLoad: selfObservationLoad,
            repeatedHeavyDays: repeatedHeavyDays
        )
        let actions = recoveryActions(
            band: band,
            moodLoad: moodLoad,
            bodyLoad: bodySignalLoad,
            sleepRecoveryScore: sleepRecoveryScore,
            selfObservationLoad: selfObservationLoad,
            repeatedHeavyDays: repeatedHeavyDays
        )
        let cautionText = cautionText(referenceDate: normalizedReferenceDate, gad7: latestGAD7, phq9: latestPHQ9)
        let dataNote = dataNote(
            moodEntries: recentMoodEntries,
            sleepSummaries: recentSleep,
            currentStress: currentStress,
            selfObservationLoad: selfObservationLoad,
            assessmentLoad: assessmentLoad
        )

        return MentalRecoverySnapshot(
            referenceDate: normalizedReferenceDate,
            band: band,
            overallScore: overallScore,
            headline: headline,
            summary: summary,
            moodLoad: moodLoad,
            bodyStressLoad: bodySignalLoad,
            sleepRecoveryScore: sleepRecoveryScore,
            assessmentLoad: assessmentLoad,
            selfObservationLoad: selfObservationLoad,
            dominantMoodTitle: dominantMoodTitle,
            repeatedHeavyDays: repeatedHeavyDays,
            averageIntensity: averageIntensity,
            linkTitle: linkNarrative.title,
            linkBody: linkNarrative.body,
            actions: actions,
            cautionText: cautionText,
            trend: trend,
            dataNote: dataNote
        )
    }

    private func buildTrend(
        windowStart: Date,
        referenceDate: Date,
        moodEntriesByDay: [Date: [MoodEntry]],
        sleepSummaries: [SleepTrendNightSummary],
        selfObservationSummaries: [SelfObservationDailySummary]
    ) -> [MentalRecoveryTrendPoint] {
        let sleepByDay = Dictionary(grouping: sleepSummaries, by: { calendar.startOfDay(for: $0.day) })
            .compactMapValues { summaries in
                summaries.max { $0.asleepMinutes < $1.asleepMinutes }
            }
        let selfObservationByDay = Dictionary(uniqueKeysWithValues: selfObservationSummaries.map { (calendar.startOfDay(for: $0.date), $0) })

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: windowStart),
                  date <= referenceDate else {
                return nil
            }
            let entries = moodEntriesByDay[calendar.startOfDay(for: date)] ?? []
            let moodLoad = entries.isEmpty ? 0 : dailyMoodLoad(entries)
            let sleepRecovery = sleepByDay[calendar.startOfDay(for: date)].map { Double($0.sleepScoreEstimate) }
            let selfObservationLoad = selfObservationByDay[calendar.startOfDay(for: date)].flatMap(Self.selfObservationLoad)
            return MentalRecoveryTrendPoint(date: date, moodLoad: moodLoad, sleepRecovery: sleepRecovery, selfObservationLoad: selfObservationLoad)
        }
    }

    private func resolvedMoodLoad(from entries: [MoodEntry]) -> Int {
        guard !entries.isEmpty else { return 30 }
        return Int(dailyMoodLoad(entries).rounded())
    }

    private func dailyMoodLoad(_ entries: [MoodEntry]) -> Double {
        guard !entries.isEmpty else { return 0 }
        let weighted = entries.map { entry -> Double in
            let base = emotionLoadBaseline(code: entry.backendEmotionCode)
            return base * 0.68 + Double(entry.intensity) * 0.32
        }
        return weighted.reduce(0, +) / Double(weighted.count)
    }

    private func emotionLoadBaseline(code: String) -> Double {
        switch code {
        case "happy":
            return 18
        case "neutral":
            return 38
        case "tired":
            return 62
        case "anxious":
            return 84
        case "sad":
            return 76
        default:
            return 46
        }
    }

    private func averageIntensity(for entries: [MoodEntry]) -> Int? {
        guard !entries.isEmpty else { return nil }
        let value = entries.reduce(0) { $0 + $1.intensity }
        return Int((Double(value) / Double(entries.count)).rounded())
    }

    private func dominantMoodTitle(for entries: [MoodEntry]) -> String? {
        let grouped = Dictionary(grouping: entries, by: \.moodID)
        let topMoodID = grouped.max { lhs, rhs in
            if lhs.value.count == rhs.value.count {
                return lhs.key < rhs.key
            }
            return lhs.value.count < rhs.value.count
        }?.key
        return topMoodID.flatMap { MoodCatalog.option(id: $0)?.title }
    }

    private func resolvedSleepRecovery(from summaries: [SleepTrendNightSummary]) -> Int? {
        let recent = Array(summaries.suffix(3))
        guard !recent.isEmpty else { return nil }
        let total = recent.reduce(0.0) { partial, night in
            let durationHours = Double(night.asleepMinutes) / 60.0
            let durationScore = min(100.0, max(0.0, durationHours / 8.0 * 100.0))
            let efficiencyScore = min(100.0, max(0.0, (night.efficiency ?? 0.8) * 100.0))
            let structureScore = min(100.0, max(0.0, ((night.deepRatio ?? 0.16) / 0.2) * 100.0))
            return partial + durationScore * 0.45 + efficiencyScore * 0.35 + structureScore * 0.20
        }
        return Int((total / Double(recent.count)).rounded())
    }

    private func resolvedBodySignalLoad(
        currentStress: Int?,
        nightlyHrv: [HealthKitManager.NightlyHRV],
        restingHeartRateSeries: [TimeSeriesPointDouble]
    ) -> Int {
        var components: [Double] = []

        if let currentStress, currentStress > 0 {
            components.append(Double(currentStress))
        }

        if let latestHrv = nightlyHrv.last?.avgMs {
            let baselineValues = Array(nightlyHrv.dropLast().suffix(4)).map(\.avgMs)
            if let baseline = average(of: baselineValues), baseline > 0 {
                let dropRatio = max(0, min(1, (baseline - latestHrv) / baseline))
                components.append(30 + dropRatio * 70)
            }
        }

        if let latestResting = restingHeartRateSeries.last?.value {
            let baselineValues = Array(restingHeartRateSeries.dropLast().suffix(4)).map(\.value)
            if let baseline = average(of: baselineValues), baseline > 0 {
                let rise = max(0, latestResting - baseline)
                let normalizedRise = min(1, rise / 10.0)
                components.append(28 + normalizedRise * 72)
            }
        }

        guard !components.isEmpty else { return 42 }
        return Int((components.reduce(0, +) / Double(components.count)).rounded())
    }

    private func resolvedAssessmentLoad(
        referenceDate: Date,
        gad7: MentalAssessmentResult?,
        phq9: MentalAssessmentResult?
    ) -> Int? {
        var values: [Double] = []

        if let gad7, isRecentAssessment(gad7, referenceDate: referenceDate) {
            values.append((Double(gad7.score) / 21.0) * 100.0)
        }
        if let phq9, isRecentAssessment(phq9, referenceDate: referenceDate) {
            values.append((Double(phq9.score) / 27.0) * 100.0)
        }

        guard !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count)).rounded())
    }

    private func resolvedSelfObservationLoad(from summaries: [SelfObservationDailySummary]) -> Int? {
        let loads = summaries.compactMap(Self.selfObservationLoad)
        guard !loads.isEmpty else { return nil }
        return Int((loads.reduce(0, +) / Double(loads.count)).rounded())
    }

    nonisolated private static func selfObservationLoad(from summary: SelfObservationDailySummary) -> Double? {
        guard summary.recordCount > 0 else { return nil }
        return min(100, max(0, 100 - summary.burdenScore))
    }

    private func blendedScore(
        moodLoad: Int,
        bodyLoad: Int,
        sleepLoad: Int,
        selfObservationLoad: Int?,
        assessmentLoad: Int?
    ) -> Int {
        var weightedTotal = Double(moodLoad) * 0.30 + Double(bodyLoad) * 0.24 + Double(sleepLoad) * 0.20
        var weight = 0.74
        if let selfObservationLoad {
            weightedTotal += Double(selfObservationLoad) * 0.12
            weight += 0.12
        }
        if let assessmentLoad {
            weightedTotal += Double(assessmentLoad) * 0.14
            weight += 0.14
        }
        return Int((weightedTotal / weight).rounded())
    }

    private func headline(for band: MentalRecoveryBand, sleepRecoveryScore: Int?, repeatedHeavyDays: Int) -> String {
        switch band {
        case .steady:
            if let sleepRecoveryScore, sleepRecoveryScore >= 74 {
                return "这几天的心理恢复节奏还算稳"
            }
            return String(localized: "最近的负荷没有明显堆高")
        case .watch:
            if repeatedHeavyDays >= 3 {
                return "情绪负荷已经连续几天偏重"
            }
            return String(localized: "恢复窗口在变窄，适合早点干预")
        case .elevated:
            return String(localized: "先把恢复放回优先级，再继续硬撑会更累")
        }
    }

    private func summary(
        band: MentalRecoveryBand,
        dominantMoodTitle: String?,
        moodLoad: Int,
        bodyLoad: Int,
        sleepRecoveryScore: Int?,
        selfObservationLoad: Int?,
        repeatedHeavyDays: Int
    ) -> String {
        let moodText = dominantMoodTitle.map { "最近最常出现的是\($0)" } ?? "最近的情绪记录还不够密"
        let sleepText: String
        if let sleepRecoveryScore {
            sleepText = sleepRecoveryScore >= 72 ? "睡眠恢复还在托住你" : "昨晚到最近几晚的睡眠恢复偏弱"
        } else {
            sleepText = "睡眠恢复数据还不够完整"
        }
        let selfObservationText = selfObservationLoad.map { "主观体感负荷约 \($0) 分，" } ?? ""

        switch band {
        case .steady:
            return String(localized: "\(moodText)，\(selfObservationText)\(sleepText)。现在更适合维持节律，而不是突然加码。")
        case .watch:
            return "\(moodText)，\(selfObservationText)身体压力约 \(bodyLoad) 分，且 \(repeatedHeavyDays >= 3 ? "高负荷天数已经连续出现" : "情绪与身体压力开始叠加")。"
        case .elevated:
            return String(localized: "\(moodText)，情绪负荷 \(moodLoad) 分，\(selfObservationText)\(sleepText)。这更像是恢复资源不够，而不是你不够努力。")
        }
    }

    private func linkageNarrative(
        dominantMoodTitle: String?,
        moodLoad: Int,
        bodyLoad: Int,
        sleepRecoveryScore: Int?,
        selfObservationLoad: Int?,
        repeatedHeavyDays: Int
    ) -> (title: String, body: String) {
        if let selfObservationLoad, selfObservationLoad >= 58 {
            return (
                "主观体感已经在提醒你降负荷",
                "健康档案中的主观体感显示最近负荷偏高。今天更适合把任务切小、减少额外刺激，并给睡眠恢复留出余量。"
            )
        }
        if let sleepRecoveryScore, sleepRecoveryScore < 68, moodLoad >= 60 {
            return (
                "情绪和睡眠在互相放大",
                "最近 7 天里，情绪负荷偏高的日子同时伴随较弱的夜间恢复。先把今晚睡前 90 分钟放松下来，通常比继续追求效率更有用。"
            )
        }
        if bodyLoad >= 70 {
            return (
                "身体压力已经顶到前台",
                "当前或最近的身体压力信号偏高，说明神经系统还没完全退回恢复区。今天更适合短而轻的恢复动作，而不是继续叠刺激。"
            )
        }
        if repeatedHeavyDays >= 3 {
            return (
                "这是连续累积，不是单点波动",
                "高负荷感受已经连续出现几天，更值得回看作息、社交消耗和咖啡因，而不是只盯着某一次心情变化。"
            )
        }
        return (
            "最近仍以节律观察为主",
            "目前看到的是轻到中度波动。继续稳定记录心情、睡眠和近两周问卷，会更容易分辨它是不是短期起伏。"
        )
    }

    private func recoveryActions(
        band: MentalRecoveryBand,
        moodLoad: Int,
        bodyLoad: Int,
        sleepRecoveryScore: Int?,
        selfObservationLoad: Int?,
        repeatedHeavyDays: Int
    ) -> [MentalRecoveryAction] {
        var actions: [MentalRecoveryAction] = []

        if let selfObservationLoad, selfObservationLoad >= 58 {
            actions.append(
                MentalRecoveryAction(
                    id: "self-observation",
                    title: "今天先降低主观负担",
                    detail: "健康档案中的主观体感负荷偏高，先把任务拆小、减少额外刺激，给身体和情绪都留一点缓冲。",
                    icon: "checklist.checked",
                    accentHex: "34C759"
                )
            )
        }

        if let sleepRecoveryScore, sleepRecoveryScore < 72 {
            actions.append(
                MentalRecoveryAction(
                    id: "sleep",
                    title: "今晚先修复睡前 90 分钟",
                    detail: "把强刺激、补工作和大量信息输入往前挪，优先留出一个更安静的落坡段。",
                    icon: "moon.stars.fill",
                    accentHex: "6C7BFF"
                )
            )
        }

        if bodyLoad >= 62 {
            actions.append(
                MentalRecoveryAction(
                    id: "stress",
                    title: "做一次 3 分钟降压动作",
                    detail: "呼吸、散步或离开当前环境都可以，重点不是完成任务，而是让神经系统先松一点。",
                    icon: "wind",
                    accentHex: "F08B57"
                )
            )
        }

        if moodLoad >= 60 || repeatedHeavyDays >= 3 {
            actions.append(
                MentalRecoveryAction(
                    id: "emotion",
                    title: "把情绪命名清楚，而不是混着扛",
                    detail: "今天只挑一个最贴近的感受补记下来，后面回看时会更容易找到真正消耗你的节点。",
                    icon: "heart.text.square.fill",
                    accentHex: "38B388"
                )
            )
        }

        if actions.count < 3 {
            actions.append(
                MentalRecoveryAction(
                    id: "anchor",
                    title: band == .steady ? "继续守住一个恢复锚点" : "给今天留一个最低恢复标准",
                    detail: band == .steady ? "补水、晒太阳或早点停下都算，把稳定感延续下去。" : "哪怕只完成补水、呼吸或提早 20 分钟收尾，也是在把恢复拉回来。",
                    icon: "sparkles",
                    accentHex: band == .steady ? "37B36B" : "E76D5B"
                )
            )
        }

        if actions.count < 3 {
            actions.append(
                MentalRecoveryAction(
                    id: "observe",
                    title: "7 天后再看一次趋势",
                    detail: "连续趋势比单天感受更重要。现在先把记录补齐，再看它是在回落还是继续抬高。",
                    icon: "chart.line.uptrend.xyaxis",
                    accentHex: "5C89E6"
                )
            )
        }

        return Array(actions.prefix(3))
    }

    private func cautionText(
        referenceDate: Date,
        gad7: MentalAssessmentResult?,
        phq9: MentalAssessmentResult?
    ) -> String? {
        if let phq9,
           isRecentAssessment(phq9, referenceDate: referenceDate),
           phq9.answers.indices.contains(8),
           phq9.answers[8] > 0 {
            return String(localized: "如果第 9 题也让你感到困扰，请优先联系信任的人、专业支持或健康 App 里的心理健康资源。")
        }

        let gad7Elevated = gad7.map { isRecentAssessment($0, referenceDate: referenceDate) && $0.score >= 10 } ?? false
        let phq9Elevated = phq9.map { isRecentAssessment($0, referenceDate: referenceDate) && $0.score >= 10 } ?? false
        if gad7Elevated || phq9Elevated {
            return String(localized: "近两周量表分数也在偏高区间。除了自我恢复，适合尽早增加现实支持和专业支持。")
        }
        return nil
    }

    private func dataNote(
        moodEntries: [MoodEntry],
        sleepSummaries: [SleepTrendNightSummary],
        currentStress: Int?,
        selfObservationLoad: Int?,
        assessmentLoad: Int?
    ) -> String {
        var parts: [String] = []
        parts.append("最近 7 天心情 \(moodEntries.isEmpty ? "样本较少" : "已记录 \(moodEntries.count) 条")")
        parts.append("睡眠 \(sleepSummaries.isEmpty ? "暂缺夜间摘要" : "已接入夜间恢复")")
        parts.append(currentStress == nil ? "实时压力暂缺" : "已接入身体压力")
        parts.append(selfObservationLoad == nil ? "健康档案主观体感未纳入" : "已纳入主观体感")
        if assessmentLoad == nil {
            parts.append("量表未纳入")
        }
        return parts.joined(separator: " · ")
    }

    private func isRecentAssessment(_ result: MentalAssessmentResult, referenceDate: Date) -> Bool {
        let day = calendar.startOfDay(for: result.recordedAt)
        let threshold = calendar.date(byAdding: .day, value: -21, to: referenceDate) ?? referenceDate
        return day >= threshold && day <= referenceDate
    }

    private func average(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
