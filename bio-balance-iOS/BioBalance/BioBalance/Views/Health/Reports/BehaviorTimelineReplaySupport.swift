/// BehaviorTimelineReplaySupport 作为行为时间线回放的支撑类型。
/// 负责定义事件类型枚举（咖啡因/水分/光照/情绪/睡眠/压力）及回放事件分类。

import Foundation

enum BehaviorTimelineEventKind: String, Codable, Sendable {
    case caffeine
    case hydration
    case daylight
    case mood
    case sleep
    case stress

    var title: String {
        switch self {
        case .caffeine: return "咖啡因"
        case .hydration: return "补水"
        case .daylight: return "日照"
        case .mood: return "情绪"
        case .sleep: return "睡眠"
        case .stress: return "压力"
        }
    }

    var symbolName: String {
        switch self {
        case .caffeine: return "cup.and.saucer.fill"
        case .hydration: return "drop.fill"
        case .daylight: return "sun.max.fill"
        case .mood: return "face.smiling.inverse"
        case .sleep: return "bed.double.fill"
        case .stress: return "brain.head.profile"
        }
    }
}

enum BehaviorTimelineTone: String, Codable, Sendable {
    case calm
    case neutral
    case caution
    case alert
}

struct BehaviorTimelineEvent: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let timestamp: Date
    let kind: BehaviorTimelineEventKind
    let title: String
    let detail: String
    let tone: BehaviorTimelineTone
    let source: String
}

struct BehaviorTimelineExplanation: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let timestamp: Date
    let title: String
    let detail: String
    let tone: BehaviorTimelineTone
}

struct BehaviorTimelineReplay: Codable, Equatable, Hashable, Sendable {
    let headline: String
    let summary: String
    let events: [BehaviorTimelineEvent]
    let explanations: [BehaviorTimelineExplanation]
    let coverageFlags: [String]

    struct DisplayNode: Identifiable, Hashable {
        enum Kind: Hashable {
            case event(BehaviorTimelineEventKind)
            case explanation
        }

        let id: String
        let timestamp: Date
        let title: String
        let detail: String
        let tone: BehaviorTimelineTone
        let symbolName: String
        let kind: Kind
    }

    var displayNodes: [DisplayNode] {
        let eventNodes = events.map {
            DisplayNode(
                id: $0.id,
                timestamp: $0.timestamp,
                title: $0.title,
                detail: $0.detail,
                tone: $0.tone,
                symbolName: $0.kind.symbolName,
                kind: .event($0.kind)
            )
        }
        let explanationNodes = explanations.map {
            DisplayNode(
                id: $0.id,
                timestamp: $0.timestamp,
                title: $0.title,
                detail: $0.detail,
                tone: $0.tone,
                symbolName: "sparkles",
                kind: .explanation
            )
        }
        return (eventNodes + explanationNodes)
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    switch (lhs.kind, rhs.kind) {
                    case (.explanation, .event):
                        return false
                    case (.event, .explanation):
                        return true
                    default:
                        return lhs.title < rhs.title
                    }
                }
                return lhs.timestamp < rhs.timestamp
            }
    }
}

struct BehaviorTimelineReplayBuilder {
    struct Input: Sendable {
        let date: Date
        let caffeineEvents: [CaffeineDoseEvent]
        let caffeineTotalMg: Int?
        let waterMl: Int?
        let waterTargetMl: Int?
        let daylightMinutes: Int?
        let moodEntries: [MoodEntry]
        let sleepSummary: SleepTrendNightSummary?
        let stressPoints: [TimeSeriesPoint]
        let sleepGoalMinutes: Int
    }

    private let actionRecordStore: ActionRecordStore
    private let moodStore: MoodStore
    private let healthKitManager: HealthKitManager
    private let calendar: Calendar

    init(
        actionRecordStore: ActionRecordStore = .shared,
        moodStore: MoodStore = .shared,
        healthKitManager: HealthKitManager = .shared,
        calendar: Calendar = .current
    ) {
        self.actionRecordStore = actionRecordStore
        self.moodStore = moodStore
        self.healthKitManager = healthKitManager
        self.calendar = calendar
    }

    func build(for date: Date) async -> BehaviorTimelineReplay {
        let normalizedDate = calendar.startOfDay(for: date)
        let actionSnapshot = actionRecordStore.behaviorSnapshot(for: normalizedDate)
        let caffeineEvents = actionRecordStore.caffeineDoseEvents(on: normalizedDate)
        let caffeineTotal = (try? await healthKitManager.fetchDietaryCaffeine(on: normalizedDate)) ?? (actionSnapshot.caffeineMg > 0 ? actionSnapshot.caffeineMg : 0)
        let waterMl = (try? await healthKitManager.fetchDietaryWaterIntake(on: normalizedDate)) ?? (actionSnapshot.waterMl > 0 ? actionSnapshot.waterMl : 0)
        let daylightMinutes = (try? await healthKitManager.fetchTimeInDaylightMinutes(on: normalizedDate)) ?? (actionSnapshot.sunlightMinutes > 0 ? actionSnapshot.sunlightMinutes : 0)
        let moodEntries = moodStore.entries(on: normalizedDate)
        let sleepSummary = (try? await healthKitManager.fetchSleepNightSummaries(days: 2, endDate: normalizedDate))?
            .last(where: { calendar.isDate($0.day, inSameDayAs: normalizedDate) })
        let stressPoints = await resolvedStressPoints(for: normalizedDate)

        return build(
            from: Input(
                date: normalizedDate,
                caffeineEvents: caffeineEvents,
                caffeineTotalMg: caffeineTotal > 0 ? caffeineTotal : nil,
                waterMl: waterMl > 0 ? waterMl : nil,
                waterTargetMl: AppGroupManager.shared.getWaterTargetMl() ?? 2000,
                daylightMinutes: daylightMinutes > 0 ? daylightMinutes : nil,
                moodEntries: moodEntries,
                sleepSummary: sleepSummary,
                stressPoints: stressPoints,
                sleepGoalMinutes: SleepGoalResolver.goalMinutes()
            )
        )
    }

    func build(from input: Input) -> BehaviorTimelineReplay {
        var coverageFlags: [String] = []
        var events: [BehaviorTimelineEvent] = []
        var explanations: [BehaviorTimelineExplanation] = []

        let dayStart = calendar.startOfDay(for: input.date)

        if let sleepSummary = input.sleepSummary {
            let sleepTone: BehaviorTimelineTone = sleepSummary.sleepScoreEstimate < 70 ? .caution : .calm
            let sleepDetail = "前一夜睡了 \(sleepSummary.asleepMinutes.bbFormattedDurationCompact)，睡眠评分约 \(sleepSummary.sleepScoreEstimate) 分，夜醒 \(sleepSummary.awakeMinutes) 分钟。"
            events.append(
                BehaviorTimelineEvent(
                    id: "sleep-\(Int(sleepSummary.startTime.timeIntervalSince1970))",
                    timestamp: sleepSummary.startTime,
                    kind: .sleep,
                    title: "前一夜睡眠基础盘",
                    detail: sleepDetail,
                    tone: sleepTone,
                    source: "healthkit"
                )
            )
            if sleepSummary.asleepMinutes < Int(Double(input.sleepGoalMinutes) * 0.85) || sleepSummary.sleepScoreEstimate < 72 {
                explanations.append(
                    BehaviorTimelineExplanation(
                        id: "sleep-debt-\(Int(dayStart.timeIntervalSince1970))",
                        timestamp: calendar.date(byAdding: .hour, value: 9, to: dayStart) ?? dayStart,
                        title: "恢复基础不足",
                        detail: "昨晚睡眠基础偏弱，今天上午更容易出现紧绷和恢复慢的感觉。",
                        tone: .caution
                    )
                )
            }
        } else {
            coverageFlags.append("今天缺少前一夜睡眠摘要")
        }

        if !input.caffeineEvents.isEmpty {
            let sorted = input.caffeineEvents.sorted { $0.consumedAt < $1.consumedAt }
            for event in sorted.prefix(3) {
                events.append(
                    BehaviorTimelineEvent(
                        id: "caffeine-\(event.id.uuidString)",
                        timestamp: event.consumedAt,
                        kind: .caffeine,
                        title: "摄入咖啡因 \(event.amountMg)mg",
                        detail: event.note?.isEmpty == false ? event.note! : "记录到一次含咖啡因饮品摄入。",
                        tone: event.amountMg >= 120 ? .caution : .neutral,
                        source: event.source.rawValue
                    )
                )
            }
        } else if let caffeineTotal = input.caffeineTotalMg, caffeineTotal > 0 {
            coverageFlags.append("今天缺少咖啡因时间点")
            events.append(
                BehaviorTimelineEvent(
                    id: "caffeine-summary-\(Int(dayStart.timeIntervalSince1970))",
                    timestamp: calendar.date(byAdding: .hour, value: 15, to: dayStart) ?? dayStart,
                    kind: .caffeine,
                    title: "今天累计咖啡因 \(caffeineTotal)mg",
                    detail: "当前只有总量，没有精确摄入时间，所以这里只能做摘要判断。",
                    tone: caffeineTotal >= 220 ? .caution : .neutral,
                    source: "daily-summary"
                )
            )
        } else {
            coverageFlags.append("今天缺少咖啡因记录")
        }

        if let waterMl = input.waterMl, waterMl > 0 {
            let target = max(input.waterTargetMl ?? 2000, 1)
            let reachedTarget = waterMl >= target
            events.append(
                BehaviorTimelineEvent(
                    id: "hydration-\(Int(dayStart.timeIntervalSince1970))",
                    timestamp: calendar.date(byAdding: .hour, value: 13, to: dayStart) ?? dayStart,
                    kind: .hydration,
                    title: reachedTarget ? "补水接近目标" : "今天已补水 \(waterMl)ml",
                    detail: reachedTarget ? "补水已经接近或达到目标，白天身体节律更容易稳住。" : "补水已经开始，但还没完全把恢复底盘拉起来。",
                    tone: reachedTarget ? .calm : .neutral,
                    source: "daily-summary"
                )
            )
        } else {
            coverageFlags.append("今天缺少补水记录")
        }

        if let daylightMinutes = input.daylightMinutes, daylightMinutes > 0 {
            let tone: BehaviorTimelineTone = daylightMinutes < 10 ? .caution : .calm
            events.append(
                BehaviorTimelineEvent(
                    id: "daylight-\(Int(dayStart.timeIntervalSince1970))",
                    timestamp: calendar.date(byAdding: .hour, value: 14, to: dayStart) ?? dayStart,
                    kind: .daylight,
                    title: daylightMinutes < 10 ? "白天自然光偏少" : "今天有日照暴露",
                    detail: "今天累计日照约 \(daylightMinutes) 分钟。",
                    tone: tone,
                    source: "daily-summary"
                )
            )
        } else {
            coverageFlags.append("今天缺少日照记录")
        }

        let representativeMoodEntries = representativeMoodEntries(from: input.moodEntries)
        if representativeMoodEntries.isEmpty {
            coverageFlags.append("今天缺少情绪记录")
        } else {
            for entry in representativeMoodEntries {
                let moodTone: BehaviorTimelineTone = negativeMoodCodes.contains(entry.backendEmotionCode) ? .caution : .neutral
                let noteDetail = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = noteDetail?.isEmpty == false ? noteDetail! : "主观记录为 \(entry.title)，强度 \(entry.intensity)。"
                events.append(
                    BehaviorTimelineEvent(
                        id: "mood-\(entry.id)",
                        timestamp: entry.loggedAt,
                        kind: .mood,
                        title: "记录情绪：\(entry.title)",
                        detail: detail,
                        tone: moodTone,
                        source: "mood-store"
                    )
                )
            }
        }

        let stressHighlights = stressHighlights(from: input.stressPoints)
        if stressHighlights.isEmpty {
            coverageFlags.append("今天缺少压力样本")
        } else {
            for highlight in stressHighlights {
                events.append(highlight)
            }
        }

        explanations.append(contentsOf: explanationNodes(
            input: input,
            dayStart: dayStart,
            events: events
        ))

        let trimmedEvents = Array(events.sorted { $0.timestamp < $1.timestamp }.prefix(8))
        let trimmedExplanations = Array(explanations.sorted { $0.timestamp < $1.timestamp }.prefix(3))
        let headline = makeHeadline(from: trimmedExplanations, events: trimmedEvents)
        let summary = makeSummary(from: trimmedExplanations, coverageFlags: coverageFlags)

        return BehaviorTimelineReplay(
            headline: headline,
            summary: summary,
            events: trimmedEvents,
            explanations: trimmedExplanations,
            coverageFlags: coverageFlags
        )
    }

    private func resolvedStressPoints(for date: Date) async -> [TimeSeriesPoint] {
        if calendar.isDateInToday(date) {
            return await HealthStressEstimator.todayStressPoints()
        }

        let hrvPoints = (try? await healthKitManager.fetchHRVSamples(on: date)) ?? []
        let heartRatePoints = (try? await healthKitManager.fetchHeartRateSeries(on: date, maxPoints: 180)) ?? []
        let restingHeartRate = try? await healthKitManager.fetchRestingHeartRate(on: date)

        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        return StressDailyEngine.sevenMinuteStressPoints(
            hrv: hrvPoints,
            heartRate: heartRatePoints,
            restingHeartRate: restingHeartRate,
            in: DateInterval(start: dayStart, end: dayEnd)
        )
    }

    private func representativeMoodEntries(from entries: [MoodEntry]) -> [MoodEntry] {
        let sorted = entries.sorted {
            if $0.intensity == $1.intensity {
                return $0.loggedAt < $1.loggedAt
            }
            return $0.intensity > $1.intensity
        }
        return Array(sorted.prefix(3)).sorted { $0.loggedAt < $1.loggedAt }
    }

    private func stressHighlights(from points: [TimeSeriesPoint]) -> [BehaviorTimelineEvent] {
        guard !points.isEmpty else { return [] }
        let sorted = points.sorted { $0.date < $1.date }
        var highlights: [BehaviorTimelineEvent] = []

        if let firstRise = firstStressRise(in: sorted) {
            highlights.append(
                BehaviorTimelineEvent(
                    id: "stress-rise-\(firstRise.timestamp)",
                    timestamp: firstRise.date,
                    kind: .stress,
                    title: "压力开始抬升",
                    detail: "这一段压力值开始明显上扬，适合回看当时的行为和情绪背景。",
                    tone: .caution,
                    source: "estimated"
                )
            )
        }

        if let peak = sorted.max(by: { $0.value < $1.value }), peak.value > 0 {
            highlights.append(
                BehaviorTimelineEvent(
                    id: "stress-peak-\(peak.timestamp)",
                    timestamp: peak.date,
                    kind: .stress,
                    title: "压力峰值时段",
                    detail: "这一天压力峰值约 \(peak.value)/100。",
                    tone: peak.value >= 70 ? .alert : .caution,
                    source: "estimated"
                )
            )
        }

        if let recovery = recoveryPoint(in: sorted) {
            highlights.append(
                BehaviorTimelineEvent(
                    id: "stress-recovery-\(recovery.timestamp)",
                    timestamp: recovery.date,
                    kind: .stress,
                    title: "压力开始回落",
                    detail: "后半段压力出现回落，说明身体开始从高负荷里往下退。",
                    tone: .calm,
                    source: "estimated"
                )
            )
        }

        return highlights
    }

    private func firstStressRise(in points: [TimeSeriesPoint]) -> TimeSeriesPoint? {
        guard points.count >= 2 else { return points.first(where: { $0.value >= 55 }) }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            if current.value >= 55 && current.value - previous.value >= 8 {
                return current
            }
        }
        return points.first(where: { $0.value >= 60 })
    }

    private func recoveryPoint(in points: [TimeSeriesPoint]) -> TimeSeriesPoint? {
        guard let peak = points.max(by: { $0.value < $1.value }) else { return nil }
        return points.last(where: { $0.timestamp > peak.timestamp && ($0.value + 10) < peak.value })
    }

    private func explanationNodes(
        input: Input,
        dayStart: Date,
        events: [BehaviorTimelineEvent]
    ) -> [BehaviorTimelineExplanation] {
        var nodes: [BehaviorTimelineExplanation] = []
        let stressRiseEvent = events.first(where: { $0.kind == .stress && $0.title.contains("抬升") })
        let stressPeakEvent = events.first(where: { $0.kind == .stress && $0.title.contains("峰值") })
        let sleepWeak = {
            guard let sleepSummary = input.sleepSummary else { return false }
            return sleepSummary.asleepMinutes < Int(Double(input.sleepGoalMinutes) * 0.85) || sleepSummary.sleepScoreEstimate < 72
        }()

        if let peak = stressPeakEvent,
           let lateCaffeine = input.caffeineEvents
            .filter({ calendar.component(.hour, from: $0.consumedAt) >= 15 })
            .sorted(by: { $0.consumedAt < $1.consumedAt })
            .last,
           peak.timestamp.timeIntervalSince(lateCaffeine.consumedAt) >= 0,
           peak.timestamp.timeIntervalSince(lateCaffeine.consumedAt) <= 6 * 60 * 60 {
            nodes.append(
                BehaviorTimelineExplanation(
                    id: "explain-late-caffeine-\(lateCaffeine.id.uuidString)",
                    timestamp: peak.timestamp.addingTimeInterval(60),
                    title: "晚咖啡可能把压力拖进了晚上",
                    detail: "下午后的咖啡因摄入和晚间高压力出现在同一段，今晚入睡窗口更容易被刺激拖后。",
                    tone: .caution
                )
            )
        }

        if sleepWeak, let rise = stressRiseEvent, calendar.component(.hour, from: rise.timestamp) < 12 {
            nodes.append(
                BehaviorTimelineExplanation(
                    id: "explain-sleep-debt-\(Int(dayStart.timeIntervalSince1970))",
                    timestamp: rise.timestamp.addingTimeInterval(60),
                    title: "今天上午更容易紧绷",
                    detail: "前一夜恢复基础不足，上午出现压力抬升时，身体更容易直接进入紧绷状态。",
                    tone: .caution
                )
            )
        }

        if (input.daylightMinutes ?? 0) < 10,
           let moodEvent = events.first(where: { $0.kind == .mood && $0.tone == .caution }) ?? stressPeakEvent {
            nodes.append(
                BehaviorTimelineExplanation(
                    id: "explain-daylight-\(Int(dayStart.timeIntervalSince1970))",
                    timestamp: moodEvent.timestamp.addingTimeInterval(60),
                    title: "白天自然输入偏少",
                    detail: "今天日照暴露偏少，身体节律更难被自然拉起来，主观低落或高压会更容易放大。",
                    tone: .neutral
                )
            )
        }

        if let moodEvent = events.first(where: { $0.kind == .mood }),
           let rise = stressRiseEvent,
           rise.timestamp.timeIntervalSince(moodEvent.timestamp) >= 0,
           rise.timestamp.timeIntervalSince(moodEvent.timestamp) <= 4 * 60 * 60 {
            nodes.append(
                BehaviorTimelineExplanation(
                    id: "explain-mood-stress-\(moodEvent.id)",
                    timestamp: rise.timestamp.addingTimeInterval(120),
                    title: "主观感受与压力变化出现在同一段",
                    detail: "情绪记录后不久压力开始抬升，说明这段时间主观体感和身体负荷可能正在一起波动。",
                    tone: .neutral
                )
            )
        }

        return nodes
    }

    private func makeHeadline(from explanations: [BehaviorTimelineExplanation], events: [BehaviorTimelineEvent]) -> String {
        if let first = explanations.first {
            return first.title
        }
        if events.contains(where: { $0.kind == .stress && $0.tone == .alert }) {
            return String(localized: "这一天更像是在白天后半段逐渐把压力推高。")
        }
        return String(localized: "这一天的状态变化已经能看出几个关键行为节点。")
    }

    private func makeSummary(from explanations: [BehaviorTimelineExplanation], coverageFlags: [String]) -> String {
        if let first = explanations.first {
            return first.detail
        }
        if coverageFlags.count >= 3 {
            return String(localized: "当前样本还不够完整，这条时间线先用于保守回看，不做强结论。")
        }
        return String(localized: "先把当天的关键行为和状态节点摆在一起，通常就更容易看懂节律是怎么被推出来的。")
    }

    private let negativeMoodCodes: Set<String> = ["anxious", "sad", "tired"]
}
