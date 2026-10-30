import Foundation
import HealthKit

struct HealthProfileSubjectiveRecord: Hashable, Sendable {
    let recordedAt: Date
    let selfRating: Int?
    let energy: Int?
    let stressLoad: Int?
    let sleepQuality: Int?
    let wellbeingScore: Double?

    init(
        recordedAt: Date,
        selfRating: Int? = nil,
        energy: Int? = nil,
        stressLoad: Int? = nil,
        sleepQuality: Int? = nil,
        wellbeingScore: Double? = nil
    ) {
        self.recordedAt = recordedAt
        self.selfRating = selfRating.map { max(1, min(5, $0)) }
        self.energy = energy.map { max(1, min(5, $0)) }
        self.stressLoad = stressLoad.map { max(1, min(5, $0)) }
        self.sleepQuality = sleepQuality.map { max(1, min(5, $0)) }
        self.wellbeingScore = wellbeingScore.map { max(0, min(100, $0)) }
    }
}

struct HealthProfileData: Sendable {
    var sleepDurations: [TimeSeriesPointDouble] = []
    var sleepScores: [TimeSeriesPointDouble] = []
    var hrv: [TimeSeriesPointDouble] = []
    var restingHeartRate: [TimeSeriesPointDouble] = []
    var heartRate: [TimeSeriesPointDouble] = []
    var steps: [TimeSeriesPointDouble] = []
    var exerciseMinutes: [TimeSeriesPointDouble] = []
    var standHours: [TimeSeriesPointDouble] = []
    var vo2Max: [TimeSeriesPointDouble] = []
    var caffeine: [TimeSeriesPointDouble] = []
    var sedentarySummaries: [SedentaryDaySummary] = []
    var dailyWellnessRecords: [DailyWellnessDayRecord] = []
    var actionRecords: [LocalActionDayRecord] = []
    var challengeRecords: [RecoveryChallengeRecord] = []
    var moodRecordDates: [Date] = []
    var subjectiveRecords: [HealthProfileSubjectiveRecord] = []
    var symptomRecordDates: [Date] = []
    var moodRecordDays: Int = 0
    var selfAssessmentRecordDays: Int = 0
    var symptomRecordDays: Int = 0
    var periodEnabled: Bool = false
    var authorization: [HealthProfileModule: HealthProfileDataCompletenessState] = [:]
}

protocol HealthProfileDataSource: Sendable {
    func loadProfileData(days: Int, endDate: Date, calendar: Calendar) async -> HealthProfileData
}

struct DefaultHealthProfileDataSource: HealthProfileDataSource {
    func loadProfileData(days: Int, endDate: Date, calendar: Calendar) async -> HealthProfileData {
        let endDay = calendar.startOfDay(for: endDate)
        let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) ?? endDay
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDate

        async let sleepNightTask = try? HealthKitManager.shared.fetchSleepNightSummaries(days: days, endDate: endDate)
        async let sleepScoreTask = try? HealthKitManager.shared.fetchDailySleepScoreSeries(days: days, endDate: endDate)
        async let hrvTask = try? HealthKitManager.shared.fetchDailyHRVAverages(days: days, endDate: endDate)
        async let restingTask = try? HealthKitManager.shared.fetchDailyRestingHeartRateAverages(days: days, endDate: endDate)
        async let heartRateTask = try? HealthKitManager.shared.fetchDailyHeartRateAverages(days: days, endDate: endDate)
        async let stepsTask = try? HealthKitManager.shared.fetchDailyStepSums(days: days, endDate: endDate)
        async let exerciseTask = try? HealthKitManager.shared.fetchDailyExerciseTimeSums(days: days, endDate: endDate)
        async let standTask = try? HealthKitManager.shared.fetchDailyStandHours(days: days, endDate: endDate)
        async let vo2Task = try? HealthKitManager.shared.fetchDailyResolvedVo2MaxAverages(days: days, endDate: endDate)
        async let caffeineTask = try? HealthKitManager.shared.fetchDailyDietaryCaffeineSums(days: days, endDate: endDate)
        async let sedentaryTask = try? HealthKitManager.shared.fetchSedentaryDaySummaries(days: days, endDate: endDate, now: endDate)

        let dailyRecords = DailyWellnessStore.shared.allRecords().filter { isInWindow($0.date, start: startDay, end: endExclusive, calendar: calendar) }
        let actionRecords = ActionRecordStore.shared.allRecords().filter { isInWindow($0.date, start: startDay, end: endExclusive, calendar: calendar) }
        let challenges = RecoveryChallengeStore.shared.allRecords().filter {
            let referenceDate = $0.completedAt ?? $0.failedAt ?? $0.abandonedAt ?? $0.startDate
            return isInWindow(referenceDate, start: startDay, end: endExclusive, calendar: calendar)
        }
        let moodRecordDates = MoodStore.shared.allEntries()
            .filter { isInWindow($0.loggedAt, start: startDay, end: endExclusive, calendar: calendar) }
            .map(\.loggedAt)
        let moodDays = Set(moodRecordDates.map { calendar.startOfDay(for: $0) }).count
        let observationRecords = SelfObservationStore.shared.allRecords().filter {
            isInWindow($0.recordedAt, start: startDay, end: endExclusive, calendar: calendar)
        }
        let subjectiveRecords = observationRecords
            .filter(\.isHealthProfileAssessment)
            .compactMap { record -> HealthProfileSubjectiveRecord? in
                let selfRating = record.answer(for: .selfRating)
                let energy = record.answer(for: .energy)
                let stressLoad = record.answer(for: .stressLoad)
                let sleepQuality = record.answer(for: .sleepQuality)
                guard selfRating != nil || energy != nil || stressLoad != nil || sleepQuality != nil else {
                    return nil
                }
                return HealthProfileSubjectiveRecord(
                    recordedAt: record.recordedAt,
                    selfRating: selfRating,
                    energy: energy,
                    stressLoad: stressLoad,
                    sleepQuality: sleepQuality,
                    wellbeingScore: record.burdenScore
                )
            }
        let symptomRecordDates = observationRecords
            .filter(\.isSymptomObservation)
            .map(\.recordedAt)
        let selfAssessmentDays = Set(
            subjectiveRecords.map { calendar.startOfDay(for: $0.recordedAt) }
        ).count
        let symptomDays = Set(symptomRecordDates.map { calendar.startOfDay(for: $0) }).count
        let periodSummary = PeriodStore.shared.summary(days: max(days, 30), referenceDate: endDate)
        let hasPeriodData = !(periodSummary.dayLogs ?? []).isEmpty || !(periodSummary.cycles ?? []).isEmpty
        let sleepNights = await sleepNightTask ?? []

        return HealthProfileData(
            sleepDurations: sleepNights.map { TimeSeriesPointDouble(timestamp: Int64($0.day.timeIntervalSince1970), value: Double($0.asleepMinutes)) },
            sleepScores: await sleepScoreTask ?? [],
            hrv: await hrvTask ?? [],
            restingHeartRate: await restingTask ?? [],
            heartRate: await heartRateTask ?? [],
            steps: await stepsTask ?? [],
            exerciseMinutes: await exerciseTask ?? [],
            standHours: await standTask ?? [],
            vo2Max: await vo2Task ?? [],
            caffeine: await caffeineTask ?? [],
            sedentarySummaries: await sedentaryTask ?? [],
            dailyWellnessRecords: dailyRecords,
            actionRecords: actionRecords,
            challengeRecords: challenges,
            moodRecordDates: moodRecordDates,
            subjectiveRecords: subjectiveRecords,
            symptomRecordDates: symptomRecordDates,
            moodRecordDays: moodDays,
            selfAssessmentRecordDays: selfAssessmentDays,
            symptomRecordDays: symptomDays,
            periodEnabled: hasPeriodData,
            authorization: [:]
        )
    }

    private func isInWindow(_ date: Date, start: Date, end: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= start && day < end
    }
}

struct HealthProfileEngine: Sendable {
    private let dataSource: HealthProfileDataSource
    private let calendar: Calendar

    init(dataSource: HealthProfileDataSource = DefaultHealthProfileDataSource(), calendar: Calendar = .current) {
        self.dataSource = dataSource
        self.calendar = calendar
    }

    func generate(range: HealthProfileRange = .thirtyDays, endDate: Date = Date()) async -> HealthProfileSummary {
        let days = max(14, range.dayCount)
        let data = await dataSource.loadProfileData(days: days, endDate: endDate, calendar: calendar)
        return makeSummary(data: data, range: range, generatedAt: endDate)
    }

    func makeSummary(data: HealthProfileData, range: HealthProfileRange = .thirtyDays, generatedAt: Date = Date()) -> HealthProfileSummary {
        let profileData = windowedData(data, days: range.dayCount, endingAt: generatedAt)
        let sampleCount = primarySampleCount(profileData)
        let dimensions = makeDimensions(profileData, generatedAt: generatedAt)
        let weightedScore = growthScore(dimensions)
        let status = sampleCount < 7 ? HealthProfileStatus.building : status(for: weightedScore)
        let changes = sampleCount < 7 ? [] : makeChanges(data, generatedAt: generatedAt)
        let tags = sampleCount < 7 ? [] : makeTags(profileData)
        let milestones = sampleCount < 7 ? [] : makeMilestones(data, generatedAt: generatedAt)
        let risks = makeRiskTendencies(data: profileData, status: status)
        let completeness = makeCompleteness(profileData)
        let actions = makeActionRecommendations(
            data: profileData,
            status: status,
            risks: risks,
            completeness: completeness,
            dimensions: dimensions
        )
        let headline = makeHeadline(status: status, dimensions: dimensions, changes: changes, sampleCount: sampleCount)

        return HealthProfileSummary(
            generatedAt: generatedAt,
            range: range,
            headline: headline,
            status: status,
            growthScore: weightedScore,
            dimensions: dimensions,
            changes: Array(changes.prefix(5)),
            tags: tags,
            milestones: milestones,
            riskTendencies: risks,
            actionRecommendations: actions,
            dataCompleteness: completeness
        )
    }
}

private extension HealthProfileEngine {
    func makeDimensions(_ data: HealthProfileData, generatedAt: Date) -> [HealthProfileDimension] {
        let subjectiveDays = subjectiveObservationDayCount(data)
        return [
            dimension(kind: .sleepRhythm, score: sleepScore(data), sampleCount: recordedDayCount([data.sleepDurations, data.sleepScores]), detail: sleepDetail(data)),
            dimension(kind: .recoveryVitals, score: recoveryScore(data), sampleCount: recordedDayCount([data.hrv, data.restingHeartRate]), detail: recoveryDetail(data)),
            dimension(kind: .stressStability, score: stressScore(data), sampleCount: estimatedStress(data).count, detail: stressDetail(data)),
            dimension(kind: .activityBase, score: activityScore(data), sampleCount: recordedDayCount([data.steps, data.exerciseMinutes, data.standHours]), detail: activityDetail(data)),
            dimension(kind: .habitConsistency, score: habitScore(data, generatedAt: generatedAt), sampleCount: recordedHabitDays(data), detail: habitDetail(data)),
            HealthProfileDimension(
                kind: .menstrualWellbeing,
                title: HealthProfileDimensionKind.menstrualWellbeing.title,
                statusText: data.periodEnabled ? "已启用" : "未启用",
                score: nil,
                trend: data.periodEnabled ? .observing : .missing,
                detail: data.periodEnabled ? "周期记录会作为恢复解释的背景，不参与主要成长分。" : "如果不适用，可以忽略这一项。"
            ),
            HealthProfileDimension(
                kind: .symptomObservation,
                title: "主观体感",
                statusText: subjectiveDays > 0 ? "已记录 \(subjectiveDays) 天" : "按需记录",
                score: nil,
                trend: subjectiveTrend(data),
                detail: subjectiveDetail(data)
            )
        ]
    }

    func dimension(kind: HealthProfileDimensionKind, score: Int?, sampleCount: Int, detail: String) -> HealthProfileDimension {
        let trend: HealthProfileTrend
        let statusText: String
        if sampleCount == 0 {
            trend = .missing
            statusText = "等待同步"
        } else if sampleCount < 7 {
            trend = .observing
            statusText = "样本较少"
        } else if score == nil {
            trend = .observing
            statusText = "建立基线"
        } else if let score, score >= 78 {
            trend = .improving
            statusText = "表现稳定"
        } else if let score, score >= 60 {
            trend = .stable
            statusText = "继续观察"
        } else {
            trend = .declining
            statusText = "需要照顾"
        }
        return HealthProfileDimension(kind: kind, title: kind.title, statusText: statusText, score: score, trend: trend, detail: detail)
    }

    func growthScore(_ dimensions: [HealthProfileDimension]) -> Int {
        let weights: [HealthProfileDimensionKind: Double] = [
            .sleepRhythm: 0.25,
            .recoveryVitals: 0.25,
            .stressStability: 0.20,
            .activityBase: 0.15,
            .habitConsistency: 0.15
        ]
        var weighted = 0.0
        var usedWeight = 0.0
        for dimension in dimensions {
            guard let weight = weights[dimension.kind], let score = dimension.score else { continue }
            weighted += Double(score) * weight
            usedWeight += weight
        }
        guard usedWeight > 0 else { return 0 }
        return Int((weighted / usedWeight).rounded())
    }

    func status(for score: Int) -> HealthProfileStatus {
        if score >= 80 { return .growing }
        if score >= 65 { return .stable }
        if score >= 45 { return .needsRepair }
        return .volatile
    }

    func makeHeadline(status: HealthProfileStatus, dimensions: [HealthProfileDimension], changes: [HealthProfileChange], sampleCount: Int) -> String {
        if sampleCount < 7 {
            return String(localized: "你的健康档案正在建立，继续同步睡眠、心率、活动和日常记录后，会开始总结长期节律。")
        }
        if let positive = changes.first(where: { $0.kind == .positive }) {
            return positive.detail
        }
        let strongest = dimensions
            .filter { $0.score != nil }
            .max { ($0.score ?? 0) < ($1.score ?? 0) }
        let weakest = dimensions
            .filter { $0.score != nil }
            .min { ($0.score ?? 0) < ($1.score ?? 0) }
        if status == .growing || status == .stable {
            return "最近整体\(status.title)，\(strongest?.title ?? "基础节律")是主要支撑。"
        }
        return "最近\(weakest?.title ?? "恢复节律")更值得优先照顾，可以先从睡眠、轻活动和短恢复开始。"
    }

    func makeChanges(_ data: HealthProfileData, generatedAt: Date) -> [HealthProfileChange] {
        var changes: [HealthProfileChange] = []
        appendDeltaChange(
            to: &changes,
            title: "睡眠时长变化",
            current: averageLast(data.sleepDurations, days: 7, endingAt: generatedAt),
            previous: averagePrevious(data.sleepDurations, currentDays: 7, previousDays: 7, endingAt: generatedAt),
            threshold: 25,
            positiveWhenIncreasing: true,
            impact: .sleep,
            module: .sleep,
            positiveTemplate: "最近 7 天平均睡眠比前一阶段多 %.0f 分钟。",
            negativeTemplate: "最近 7 天平均睡眠比前一阶段少 %.0f 分钟。"
        )
        appendDeltaChange(
            to: &changes,
            title: "日常活动变化",
            current: averageLast(data.steps, days: 7, endingAt: generatedAt),
            previous: averagePrevious(data.steps, currentDays: 7, previousDays: 7, endingAt: generatedAt),
            threshold: 700,
            positiveWhenIncreasing: true,
            impact: .activity,
            module: .activity,
            positiveTemplate: "最近 7 天日均步数增加约 %.0f 步。",
            negativeTemplate: "最近 7 天日均步数减少约 %.0f 步。"
        )
        appendDeltaChange(
            to: &changes,
            title: "久坐堆积变化",
            current: averageLast(data.sedentarySummaries.map { point($0.date, Double($0.totalSedentaryMinutes)) }, days: 7, endingAt: generatedAt),
            previous: averagePrevious(data.sedentarySummaries.map { point($0.date, Double($0.totalSedentaryMinutes)) }, currentDays: 7, previousDays: 7, endingAt: generatedAt),
            threshold: 30,
            positiveWhenIncreasing: false,
            impact: .habit,
            module: .sedentary,
            positiveTemplate: "最近 7 天日均久坐比前一阶段少 %.0f 分钟。",
            negativeTemplate: "最近 7 天日均久坐比前一阶段多 %.0f 分钟。"
        )
        appendDeltaChange(
            to: &changes,
            title: "恢复信号变化",
            current: averageLast(data.hrv, days: 7, endingAt: generatedAt),
            previous: averagePrevious(data.hrv, currentDays: 7, previousDays: 7, endingAt: generatedAt),
            threshold: 4,
            positiveWhenIncreasing: true,
            impact: .recovery,
            module: .stress,
            positiveTemplate: "最近 7 天 HRV 均值比前一阶段高 %.0f ms。",
            negativeTemplate: "最近 7 天 HRV 均值比前一阶段低 %.0f ms。"
        )
        appendDeltaChange(
            to: &changes,
            title: "主观体感变化",
            current: averageLast(subjectiveWellbeingPoints(data), days: 7, endingAt: generatedAt),
            previous: averagePrevious(subjectiveWellbeingPoints(data), currentDays: 7, previousDays: 7, endingAt: generatedAt),
            threshold: 8,
            positiveWhenIncreasing: true,
            impact: .stress,
            module: .symptoms,
            positiveTemplate: "最近 7 天主观体感均值比前一阶段提高 %.0f 分。",
            negativeTemplate: "最近 7 天主观体感均值比前一阶段降低 %.0f 分。"
        )

        if changes.isEmpty {
            changes.append(
                HealthProfileChange(
                    title: "最近整体比较稳定",
                    detail: "暂时没有特别明显的波动，继续积累数据后会给出更细的长期画像。",
                    kind: .stable,
                    impact: .data,
                    relatedModule: .healthKit
                )
            )
        }
        return changes.sorted { lhs, rhs in
            priority(lhs.kind) < priority(rhs.kind)
        }
    }

    func appendDeltaChange(
        to changes: inout [HealthProfileChange],
        title: String,
        current: Double?,
        previous: Double?,
        threshold: Double,
        positiveWhenIncreasing: Bool,
        impact: HealthProfileImpact,
        module: HealthProfileModule,
        positiveTemplate: String,
        negativeTemplate: String
    ) {
        guard let current, let previous else { return }
        let delta = current - previous
        guard abs(delta) >= threshold else { return }
        let isPositive = positiveWhenIncreasing ? delta > 0 : delta < 0
        let template = isPositive ? positiveTemplate : negativeTemplate
        changes.append(
            HealthProfileChange(
                title: title,
                detail: String(format: template, abs(delta)),
                kind: isPositive ? .positive : .risk,
                impact: impact,
                relatedModule: module
            )
        )
    }

    func makeTags(_ data: HealthProfileData) -> [HealthProfileTag] {
        var tags: [HealthProfileTag] = []
        let sleepSamples = positive(data.sleepDurations)
        let sedentaryDays = data.sedentarySummaries.filter { $0.sourceStatus == .ready }
        let stressValues = estimatedStress(data)

        if sleepSamples.count >= 7, standardDeviation(sleepSamples.map(\.value)) < 55 {
            tags.append(tag("睡眠节律稳定型", "睡眠时长波动较小，近期恢复更容易被稳定作息托住。", .medium, ["当前范围睡眠样本 \(sleepSamples.count) 天"], firstDetectedAt: sleepSamples[6].date))
        } else if sleepSamples.count >= 7 {
            tags.append(tag("睡眠节律正在观察", "目前睡眠节律还有波动，先继续观察入睡和起床时间。", .low, ["当前范围睡眠样本 \(sleepSamples.count) 天"], firstDetectedAt: sleepSamples[6].date))
        }
        let afternoonSedentary = sedentaryDays
            .filter { preferredDaypart($0) == "下午" && $0.totalSedentaryMinutes >= 180 }
            .sorted { $0.date < $1.date }
        if afternoonSedentary.count >= 3 {
            tags.append(tag("午后容易掉电", "下午久坐更集中，可以把短步行或起身点提前安排。", .medium, ["下午久坐集中重复出现"], firstDetectedAt: afternoonSedentary[2].date))
        }
        let longSedentary = sedentaryDays
            .filter { $0.longestSessionMinutes >= 75 }
            .sorted { $0.date < $1.date }
        if longSedentary.count >= 3 {
            tags.append(tag("久坐堆积型疲劳", "长坐时段比较容易堆积，恢复动作越早插入越稳。", .medium, ["多天出现较长久坐段"], firstDetectedAt: longSedentary[2].date))
        }
        let highStress = stressValues.filter { $0.value >= 68 }.sorted { $0.date < $1.date }
        if highStress.count >= 3 {
            tags.append(tag("压力恢复慢", "高压力日后更适合安排短放松，而不是继续叠加任务。", .medium, ["压力估算多次偏高"], firstDetectedAt: highStress[2].date))
        }
        let caffeineDays = data.caffeine.filter { $0.value >= 80 }.sorted { $0.date < $1.date }
        if caffeineDays.count >= 2, (sleepScore(data) ?? 100) < 78 {
            tags.append(tag("晚间咖啡因敏感", "目前只有每日总量，先把咖啡因和晚间恢复放在一起观察。", .low, ["多天有咖啡因记录", "睡眠节律仍在观察"], firstDetectedAt: caffeineDays[1].date))
        }
        if let stepsDelta = deltaPercent(data.steps), stepsDelta > 0.12, let hrvDelta = deltaPercent(data.hrv), hrvDelta > -0.05 {
            tags.append(tag("活动带动恢复", "轻活动增加时，恢复信号没有同步走弱，可以继续保留这类节奏。", .low, ["步数近期上升", "HRV 未明显下降"]))
        }
        if data.periodEnabled {
            tags.append(tag("周期恢复背景", "周期记录已纳入档案背景，后续可帮助解释阶段性恢复波动。", .low, ["周期健康记录已启用"]))
        }
        let moodDays = moodRecordDayCount(data)
        if moodDays >= 3 {
            let detectedAt = uniqueDays(data.moodRecordDates).dropFirst(2).first
            tags.append(tag("情绪压力联动观察", "情绪记录已有样本，后续可以和压力、睡眠一起观察。", .low, ["情绪记录 \(moodDays) 天"], firstDetectedAt: detectedAt))
        }
        let subjectiveDays = selfAssessmentDayCount(data)
        if subjectiveDays >= 3 {
            let detectedAt = uniqueDays(data.subjectiveRecords.map(\.recordedAt)).dropFirst(2).first
            tags.append(tag("主观体感已有证据", "精力、压力和睡眠感受已进入档案，用于解释客观信号的阶段性变化。", .low, ["主观体感记录 \(subjectiveDays) 天"], firstDetectedAt: detectedAt))
        }
        return Array(tags.prefix(6))
    }

    func makeMilestones(_ data: HealthProfileData, generatedAt: Date) -> [HealthProfileMilestone] {
        var items: [HealthProfileMilestone] = []
        let sleepGoal = Double(SleepGoalResolver.goalMinutes()) * 0.85
        let recentSleep = pointsInLastWindow(data.sleepDurations, days: 7, endingAt: generatedAt)
        if let achievedAt = streakAchievementDate(recentSleep, target: 5, qualifies: { $0.value >= sleepGoal }) {
            items.append(milestone("连续 5 天睡眠接近目标", "最近已有连续多天睡眠达到目标的 85% 以上。", achievedAt, .sleep))
        }
        let sedentaryPoints = data.sedentarySummaries.map { point($0.date, Double($0.longestSessionMinutes)) }
        if let current = averageLast(sedentaryPoints, days: 7, endingAt: generatedAt),
           let previous = averagePrevious(sedentaryPoints, currentDays: 7, previousDays: 7, endingAt: generatedAt),
           previous - current >= 15 {
            let achievedAt = pointsInLastWindow(sedentaryPoints, days: 7, endingAt: generatedAt).last?.date ?? generatedAt
            items.append(milestone("久坐最长单次变短", "本周最长久坐单次比前一阶段减少约 \(Int((previous - current).rounded())) 分钟。", achievedAt, .sedentary))
        }
        let recentActions = actionRecordsInLastWindow(data.actionRecords, days: 7, endingAt: generatedAt)
        let recentDailyRecords = dailyRecordsInLastWindow(data.dailyWellnessRecords, days: 7, endingAt: generatedAt)
        let sunlightDates = uniqueDays(
            recentActions.filter { $0.sunlightMinutes >= 5 }.map(\.date) +
            recentDailyRecords.filter { $0.isCompleted(.sunlight) }.map(\.date)
        )
        if sunlightDates.count >= 4 {
            items.append(milestone("本周多次完成日照目标", "最近至少 4 天有日照或节律相关记录。", sunlightDates[3], .habits))
        }
        let recoveryDates = uniqueDays(
            recentDailyRecords
                .filter { $0.microRecoveryCount > 0 || $0.isCompleted(.breathing) }
                .map(\.date)
        )
        if recoveryDates.count >= 3 {
            items.append(milestone("压力后有恢复动作", "最近多天完成呼吸或微恢复动作，这是可控的恢复资产。", recoveryDates[2], .habits))
        }
        if let vo2Delta = deltaPercent(data.vo2Max), vo2Delta > 0.02 {
            let achievedAt = positive(data.vo2Max).last?.date ?? generatedAt
            items.append(milestone("体能趋势有改善迹象", "VO2Max 或活动能力近期进入轻微改善趋势。", achievedAt, .activity))
        }
        return Array(items.prefix(4))
    }

    func makeRiskTendencies(data: HealthProfileData, status: HealthProfileStatus) -> [HealthProfileRiskTendency] {
        var risks: [HealthProfileRiskTendency] = []
        let sleepSampleCount = recordedDayCount([data.sleepDurations, data.sleepScores])
        let stressSampleCount = estimatedStress(data).count
        let activitySampleCount = recordedDayCount([data.steps, data.exerciseMinutes, data.standHours])

        if sleepSampleCount >= 3, (sleepScore(data) ?? 100) < 62 {
            risks.append(risk("睡眠不足", "最近睡眠债偏多。", "先把起床和入睡时间拉稳。", .sleep))
        }
        if data.sedentarySummaries.filter({ $0.longestSessionMinutes >= 75 }).count >= 2 {
            risks.append(risk("久坐堆积", "长坐更容易集中在下午或连续工作时段。", "固定一个起身点，比临时补救更稳。", .sedentary))
        }
        if stressSampleCount >= 3, (stressScore(data) ?? 100) < 60 {
            risks.append(risk("压力恢复慢", "高压力日之后恢复动作偏少或 HRV 波动较大。", "安排 3 分钟短放松，先降低负荷。", .stress))
        }
        if data.caffeine.filter({ $0.value > 0 }).count >= 2, data.caffeine.suffix(7).contains(where: { $0.value >= 120 }) {
            risks.append(risk("咖啡因偏多", "刺激性饮品可能影响晚间恢复。", "下午后先减少一杯，观察睡眠变化。", .habits))
        }
        if activitySampleCount >= 3, (activityScore(data) ?? 100) < 58 {
            risks.append(risk("活动不足", "最近轻活动偏少。", "先从 10 分钟步行恢复。", .activity))
        }
        if risks.isEmpty, status == .building {
            risks.append(risk("样本还少", "目前不能生成稳定倾向。", "继续同步睡眠、心率、活动和日常记录。", .healthKit))
        }
        return Array(risks.prefix(4))
    }

    func makeActionRecommendations(
        data: HealthProfileData,
        status: HealthProfileStatus,
        risks: [HealthProfileRiskTendency],
        completeness: [HealthProfileDataCompleteness],
        dimensions: [HealthProfileDimension]
    ) -> [HealthProfileActionRecommendation] {
        var actions: [HealthProfileActionRecommendation] = []
        let unauthorized = completeness.filter { $0.state == .unauthorized }
        if !unauthorized.isEmpty {
            let names = unauthorized.map(\.title).joined(separator: "、")
            actions.append(
                action(
                    "补齐关键健康权限",
                    "先开启\(names)权限，让档案能看见睡眠、恢复和活动底盘。",
                    "当前有关键数据未授权",
                    .high,
                    .healthKit
                )
            )
        }

        let insufficientCore = completeness.filter {
            ["睡眠", "心率与 HRV", "活动"].contains($0.title) && $0.state == .insufficient
        }
        if !insufficientCore.isEmpty {
            let weakest = insufficientCore.min { $0.sampleCount < $1.sampleCount }
            actions.append(
                action(
                    "继续积累基础样本",
                    "优先补足\(weakest?.title ?? "关键健康")数据，满 7 天后画像会更稳定。",
                    weakest?.detail ?? "样本不足时结论会自动降级",
                    .medium,
                    module(forCompletenessTitle: weakest?.title)
                )
            )
        }

        for risk in risks {
            switch risk.module {
            case .sleep:
                actions.append(action("先稳住睡眠锚点", "今晚只抓一个动作：固定起床时间或提前 15 分钟收尾。", risk.detail, .high, .sleep))
            case .sedentary:
                actions.append(action("安排一个固定起身点", "在最容易长坐的时段前放一个短步行或站立提醒。", risk.detail, .high, .sedentary))
            case .stress:
                actions.append(action("插入 3 分钟短恢复", "压力偏高日先做一次呼吸、闭眼或轻伸展，降低后续负荷。", risk.detail, .high, .stress))
            case .habits:
                actions.append(action("减少一次晚间刺激", "下午后先少一杯咖啡因饮品，观察今晚睡眠和明早恢复。", risk.detail, .medium, .habits))
            case .activity:
                actions.append(action("补一段 10 分钟轻活动", "用低门槛步行或拉伸把活动底盘拉起来。", risk.detail, .medium, .activity))
            case .healthKit:
                actions.append(action("保持数据同步", "继续同步睡眠、心率、活动和日常记录，先让档案成形。", risk.detail, .medium, .healthKit))
            case .reproductive, .symptoms:
                actions.append(action("补一条主观观察", "记录一次身体感受或周期背景，帮助解释后续波动。", risk.detail, .low, risk.module))
            }
        }

        if actions.isEmpty {
            if let strongest = dimensions.filter({ $0.score != nil }).max(by: { ($0.score ?? 0) < ($1.score ?? 0) }) {
                actions.append(
                    action(
                        "保留\(strongest.title)的有效节奏",
                        "最近不用大改，优先维持已经起作用的那一两个习惯。",
                        "\(strongest.title)是当前较稳定的支撑",
                        .low,
                        module(for: strongest.kind)
                    )
                )
            } else {
                actions.append(
                    action(
                        "先完成一条轻记录",
                        "记录今天睡眠、活动或恢复动作，让档案开始有可回看的线索。",
                        "档案还在建立",
                        .medium,
                        .habits
                    )
                )
            }
        }

        return uniqueActions(actions)
            .sorted { lhs, rhs in
                let lhsKey = actionSortKey(lhs)
                let rhsKey = actionSortKey(rhs)
                if lhsKey.priority != rhsKey.priority { return lhsKey.priority < rhsKey.priority }
                if lhsKey.module != rhsKey.module { return lhsKey.module < rhsKey.module }
                return lhs.title < rhs.title
            }
            .prefix(4)
            .map { $0 }
    }

    func makeCompleteness(_ data: HealthProfileData) -> [HealthProfileDataCompleteness] {
        let sleepDays = recordedDayCount([data.sleepDurations, data.sleepScores])
        let recoveryDays = recordedDayCount([data.hrv, data.restingHeartRate])
        let activityDays = recordedDayCount([data.steps, data.exerciseMinutes, data.standHours])
        let subjectiveDays = selfAssessmentDayCount(data)
        let symptomDays = symptomObservationDayCount(data)
        return [
            completeness("睡眠", module: .sleep, sampleCount: sleepDays, required: 7, override: data.authorization[.sleep]),
            completeness("心率与 HRV", module: .healthKit, sampleCount: recoveryDays, required: 7, override: data.authorization[.healthKit]),
            completeness("活动", module: .activity, sampleCount: activityDays, required: 7, override: data.authorization[.activity]),
            HealthProfileDataCompleteness(title: "压力", state: estimatedStress(data).count >= 3 ? .generated : .insufficient, detail: estimatedStress(data).count >= 3 ? "已根据 HRV、心率和静息心率生成。" : "暂无足够数据生成稳定压力趋势。", sampleCount: estimatedStress(data).count),
            HealthProfileDataCompleteness(title: "习惯记录", state: recordedHabitDays(data) >= 3 ? .synced : .insufficient, detail: recordedHabitDays(data) >= 3 ? "已有日常记录可参与档案。" : "建议补充补水、日照、放松或行动记录。", sampleCount: recordedHabitDays(data)),
            HealthProfileDataCompleteness(title: "主观状态", state: subjectiveDays >= 3 ? .synced : .insufficient, detail: subjectiveDays >= 3 ? "档案已有主观体感记录可用于解释长期变化。" : "在健康档案内补充最多 3 项体感，可提高主观状态的解释完整度。", sampleCount: subjectiveDays),
            HealthProfileDataCompleteness(title: "周期健康", state: data.periodEnabled ? .synced : .notEnabled, detail: data.periodEnabled ? "周期记录已作为解释背景。" : "未启用或当前不适用。", sampleCount: data.periodEnabled ? 1 : 0),
            HealthProfileDataCompleteness(title: "症状观察", state: symptomDays > 0 ? .synced : .notApplicable, detail: symptomDays > 0 ? "已有按需记录，可作为波动解释背景。" : "没有症状时无需记录，也不会降低档案可信度。", sampleCount: symptomDays)
        ]
    }

    func completeness(_ title: String, module: HealthProfileModule, sampleCount: Int, required: Int, override: HealthProfileDataCompletenessState?) -> HealthProfileDataCompleteness {
        let state: HealthProfileDataCompletenessState
        if override == .unauthorized {
            state = .unauthorized
        } else if sampleCount >= required {
            state = .synced
        } else {
            state = .insufficient
        }
        let detail: String
        switch state {
        case .synced: detail = "已有 \(sampleCount) 天样本，可生成趋势。"
        case .unauthorized: detail = "开启权限后，档案会更准确。"
        default: detail = "当前 \(sampleCount) 天样本，建议继续同步。"
        }
        return HealthProfileDataCompleteness(title: title, state: state, detail: detail, sampleCount: sampleCount)
    }
}

private extension HealthProfileEngine {
    func sleepScore(_ data: HealthProfileData) -> Int? {
        let values = positive(data.sleepDurations).map(\.value)
        let recordedScores = positive(data.sleepScores).map { max(0, min(100, $0.value)) }
        var components: [(score: Double, weight: Double)] = []
        if let avg = average(values) {
            let durationScore = max(0, min(100, 100 - abs(avg - 450) / 3.2))
            let regularityScore = max(0, min(100, 100 - standardDeviation(values) / 2.0))
            components.append((durationScore * 0.62 + regularityScore * 0.38, 0.70))
        }
        if let scoreAverage = average(recordedScores) {
            components.append((scoreAverage, 0.30))
        }
        return weightedAvailableScore(components)
    }

    func recoveryScore(_ data: HealthProfileData) -> Int? {
        let hrvValues = positive(data.hrv).map(\.value)
        let rhrValues = positive(data.restingHeartRate).map(\.value)
        guard !hrvValues.isEmpty || !rhrValues.isEmpty else { return nil }
        var trendAdjustments: [(value: Double, weight: Double)] = []
        if let hrvTrend = deltaPercent(data.hrv) {
            trendAdjustments.append((hrvTrend * 120, 0.55))
        }
        if let rhrTrend = deltaPercent(data.restingHeartRate) {
            trendAdjustments.append((-rhrTrend * 90, 0.45))
        }
        guard !trendAdjustments.isEmpty else { return nil }
        let usedWeight = trendAdjustments.reduce(0) { $0 + $1.weight }
        let adjustment = trendAdjustments.reduce(0) { $0 + $1.value * $1.weight } / usedWeight
        let score = 70 + adjustment
        return Int(max(0, min(100, score)).rounded())
    }

    func stressScore(_ data: HealthProfileData) -> Int? {
        let values = estimatedStress(data).map(\.value)
        guard !values.isEmpty else { return nil }
        let avg = values.reduce(0, +) / Double(values.count)
        let variation = standardDeviation(values)
        return Int(max(0, min(100, 100 - avg * 0.72 - variation * 0.45)).rounded())
    }

    func activityScore(_ data: HealthProfileData) -> Int? {
        let stepValues = positive(data.steps).map(\.value)
        let exerciseValues = positive(data.exerciseMinutes).map(\.value)
        let standValues = positive(data.standHours).map(\.value)
        guard !stepValues.isEmpty || !exerciseValues.isEmpty || !standValues.isEmpty else { return nil }
        var components: [(score: Double, weight: Double)] = []
        if let steps = average(stepValues) {
            components.append((min(100, steps / 75.0), 0.50))
        }
        if let exercise = average(exerciseValues) {
            components.append((min(100, exercise / 0.3), 0.30))
        }
        if let stand = average(standValues) {
            components.append((min(100, stand / 0.1), 0.20))
        }
        return weightedAvailableScore(components)
    }

    func habitScore(_ data: HealthProfileData, generatedAt: Date) -> Int? {
        let summary = LongTermHabitEngine(calendar: calendar).evaluate(
            endingAt: generatedAt,
            dailyRecords: data.dailyWellnessRecords,
            actionRecords: data.actionRecords,
            challengeRecords: data.challengeRecords
        )
        guard summary.recordedDays90 > 0 else { return nil }
        return summary.score
    }

    func sleepDetail(_ data: HealthProfileData) -> String {
        let durationAverage = average(positive(data.sleepDurations).map(\.value))
        let recordedScoreAverage = average(positive(data.sleepScores).map(\.value))
        if let durationAverage, let recordedScoreAverage {
            return String(localized: "近期平均睡眠约 \(Int((durationAverage / 60.0).rounded())) 小时，睡眠评分均值约 \(Int(recordedScoreAverage.rounded())) 分。")
        }
        if let durationAverage {
            return String(localized: "近期平均睡眠约 \(Int((durationAverage / 60.0).rounded())) 小时，适合和 HRV、压力一起看。")
        }
        if let recordedScoreAverage {
            return String(localized: "近期睡眠评分均值约 \(Int(recordedScoreAverage.rounded())) 分，等待时长样本后可补充节律判断。")
        }
        return String(localized: "等待睡眠样本同步后，会判断睡眠时长和节律稳定度。")
    }

    func recoveryDetail(_ data: HealthProfileData) -> String {
        if let hrv = average(positive(data.hrv).map(\.value)) {
            return recoveryScore(data) == nil
                ? "近期 HRV 均值约 \(Int(hrv.rounded())) ms，继续积累前后基线后再判断恢复趋势。"
                : "近期 HRV 均值约 \(Int(hrv.rounded())) ms，用作恢复背景信号。"
        }
        if let resting = average(positive(data.restingHeartRate).map(\.value)) {
            return String(localized: "近期静息心率均值约 \(Int(resting.rounded())) 次/分，继续积累前后基线后再判断恢复趋势。")
        }
        return String(localized: "等待 HRV 和静息心率样本。")
    }

    func stressDetail(_ data: HealthProfileData) -> String {
        guard let stress = average(estimatedStress(data).map(\.value)) else {
            return String(localized: "压力趋势会根据 HRV、心率和静息心率本地估算。")
        }
        return String(localized: "近期压力估算均值约 \(Int(stress.rounded()))，只用于生活节律参考。")
    }

    func activityDetail(_ data: HealthProfileData) -> String {
        if let steps = average(positive(data.steps).map(\.value)) {
            return String(localized: "近期日均步数约 \(Int(steps.rounded())) 步，活动底盘正在形成。")
        }
        if let exercise = average(positive(data.exerciseMinutes).map(\.value)) {
            return String(localized: "近期日均运动约 \(Int(exercise.rounded())) 分钟，当前活动判断基于可用信号。")
        }
        if let stand = average(positive(data.standHours).map(\.value)) {
            return String(localized: "近期日均站立约 \(Int(stand.rounded())) 小时，当前活动判断基于可用信号。")
        }
        return String(localized: "等待步数、运动分钟或站立小时样本。")
    }

    func habitDetail(_ data: HealthProfileData) -> String {
        let count = recordedHabitDays(data)
        return count > 0 ? "最近已有 \(count) 天日常记录进入档案。" : "补水、日照、呼吸和起身记录会帮助形成成长线。"
    }

    func subjectiveDetail(_ data: HealthProfileData) -> String {
        let records = data.subjectiveRecords
        guard !records.isEmpty else {
            let days = subjectiveObservationDayCount(data)
            return days > 0
                ? "已有 \(days) 天主观状态或情绪记录，继续积累后会和睡眠、恢复信号一起解释。"
                : "状态有明显变化时再记录即可；没有症状不需要补记，也不会影响档案可信度。"
        }
        let days = selfAssessmentDayCount(data)
        var metrics: [String] = []
        if let value = average(dailySubjectiveAverage(records, value: { $0.selfRating.map { Double($0) } })) {
            metrics.append(String(format: String(localized: "整体感受 %.1f/5"), value))
        }
        if let value = average(dailySubjectiveAverage(records, value: { $0.energy.map { Double($0) } })) {
            metrics.append(String(format: String(localized: "精力 %.1f/5"), value))
        }
        if let value = average(dailySubjectiveAverage(records, value: { $0.stressLoad.map { Double($0) } })) {
            metrics.append(String(format: String(localized: "压力 %.1f/5"), value))
        }
        if let value = average(dailySubjectiveAverage(records, value: { $0.sleepQuality.map { Double($0) } })) {
            metrics.append(String(format: String(localized: "睡眠感受 %.1f/5"), value))
        }
        guard !metrics.isEmpty else {
            return String(localized: "已有 \(days) 天主观状态记录，可用于解释近期变化。")
        }
        return "已有 \(days) 天体感记录，日均" + metrics.joined(separator: "、") + "。"
    }

    func subjectiveTrend(_ data: HealthProfileData) -> HealthProfileTrend {
        let points = subjectiveWellbeingPoints(data)
        guard !points.isEmpty else {
            return subjectiveObservationDayCount(data) > 0 ? .observing : .missing
        }
        guard points.count >= 4 else { return .observing }
        let split = points.count / 2
        guard let previous = average(points.prefix(split).map(\.value)),
              let current = average(points.suffix(points.count - split).map(\.value)) else {
            return .observing
        }
        if current - previous >= 8 { return .improving }
        if previous - current >= 8 { return .declining }
        return .stable
    }
}

private extension HealthProfileEngine {
    func windowedData(_ data: HealthProfileData, days: Int, endingAt endDate: Date) -> HealthProfileData {
        let endDay = calendar.startOfDay(for: endDate)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) ?? endDay
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDate

        func contains(_ date: Date) -> Bool {
            let day = calendar.startOfDay(for: date)
            return day >= start && day < end
        }

        let moodRecordDates = data.moodRecordDates.filter { contains($0) }
        let subjectiveRecords = data.subjectiveRecords.filter { contains($0.recordedAt) }
        let symptomRecordDates = data.symptomRecordDates.filter { contains($0) }
        let moodRecordDays = data.moodRecordDates.isEmpty
            ? min(data.moodRecordDays, days)
            : uniqueDays(moodRecordDates).count
        let selfAssessmentRecordDays = data.subjectiveRecords.isEmpty
            ? min(data.selfAssessmentRecordDays, days)
            : uniqueDays(subjectiveRecords.map(\.recordedAt)).count
        let symptomRecordDays = data.symptomRecordDates.isEmpty
            ? min(data.symptomRecordDays, days)
            : uniqueDays(symptomRecordDates).count

        return HealthProfileData(
            sleepDurations: data.sleepDurations.filter { contains($0.date) },
            sleepScores: data.sleepScores.filter { contains($0.date) },
            hrv: data.hrv.filter { contains($0.date) },
            restingHeartRate: data.restingHeartRate.filter { contains($0.date) },
            heartRate: data.heartRate.filter { contains($0.date) },
            steps: data.steps.filter { contains($0.date) },
            exerciseMinutes: data.exerciseMinutes.filter { contains($0.date) },
            standHours: data.standHours.filter { contains($0.date) },
            vo2Max: data.vo2Max.filter { contains($0.date) },
            caffeine: data.caffeine.filter { contains($0.date) },
            sedentarySummaries: data.sedentarySummaries.filter { contains($0.date) },
            dailyWellnessRecords: data.dailyWellnessRecords.filter { contains($0.date) },
            actionRecords: data.actionRecords.filter { contains($0.date) },
            challengeRecords: data.challengeRecords.filter {
                contains($0.completedAt ?? $0.failedAt ?? $0.abandonedAt ?? $0.startDate)
            },
            moodRecordDates: moodRecordDates,
            subjectiveRecords: subjectiveRecords,
            symptomRecordDates: symptomRecordDates,
            moodRecordDays: moodRecordDays,
            selfAssessmentRecordDays: selfAssessmentRecordDays,
            symptomRecordDays: symptomRecordDays,
            periodEnabled: data.periodEnabled,
            authorization: data.authorization
        )
    }

    func positive(_ points: [TimeSeriesPointDouble]) -> [TimeSeriesPointDouble] {
        points.filter { $0.value > 0 }.sorted { $0.date < $1.date }
    }

    func recordedDayCount(_ series: [[TimeSeriesPointDouble]]) -> Int {
        uniqueDays(
            series
                .flatMap { $0 }
                .filter { $0.value > 0 }
                .map(\.date)
        ).count
    }

    func uniqueDays(_ dates: [Date]) -> [Date] {
        Array(Set(dates.map { calendar.startOfDay(for: $0) })).sorted()
    }

    func moodRecordDayCount(_ data: HealthProfileData) -> Int {
        max(uniqueDays(data.moodRecordDates).count, data.moodRecordDays)
    }

    func selfAssessmentDayCount(_ data: HealthProfileData) -> Int {
        max(uniqueDays(data.subjectiveRecords.map(\.recordedAt)).count, data.selfAssessmentRecordDays)
    }

    func symptomObservationDayCount(_ data: HealthProfileData) -> Int {
        let datedCount = uniqueDays(data.symptomRecordDates).count
        return max(datedCount, data.symptomRecordDays)
    }

    func subjectiveObservationDayCount(_ data: HealthProfileData) -> Int {
        let datedCount = uniqueDays(
            data.moodRecordDates + data.subjectiveRecords.map(\.recordedAt)
        ).count
        return [datedCount, data.moodRecordDays, data.selfAssessmentRecordDays].max() ?? 0
    }

    func subjectiveWellbeingPoints(_ data: HealthProfileData) -> [TimeSeriesPointDouble] {
        let recordsByDay = Dictionary(grouping: data.subjectiveRecords) {
            calendar.startOfDay(for: $0.recordedAt)
        }
        return recordsByDay.compactMap { date, records in
            guard let score = average(records.compactMap(\.wellbeingScore)) else { return nil }
            return point(date, score)
        }.sorted { $0.date < $1.date }
    }

    func dailySubjectiveAverage(
        _ records: [HealthProfileSubjectiveRecord],
        value: (HealthProfileSubjectiveRecord) -> Double?
    ) -> [Double] {
        Dictionary(grouping: records) { calendar.startOfDay(for: $0.recordedAt) }
            .values
            .compactMap { average($0.compactMap(value)) }
    }

    func weightedAvailableScore(_ components: [(score: Double, weight: Double)]) -> Int? {
        guard !components.isEmpty else { return nil }
        let usedWeight = components.reduce(0) { $0 + $1.weight }
        guard usedWeight > 0 else { return nil }
        let weighted = components.reduce(0) { $0 + $1.score * $1.weight } / usedWeight
        return Int(max(0, min(100, weighted)).rounded())
    }

    func estimatedStress(_ data: HealthProfileData) -> [TimeSeriesPointDouble] {
        HealthStressEstimator.estimateDailyStress(hrv: data.hrv, heartRate: data.heartRate, restingHeartRate: data.restingHeartRate)
    }

    func primarySampleCount(_ data: HealthProfileData) -> Int {
        [
            recordedDayCount([data.sleepDurations, data.sleepScores]),
            recordedDayCount([data.hrv, data.restingHeartRate]),
            recordedDayCount([data.steps, data.exerciseMinutes, data.standHours]),
            recordedHabitDays(data)
        ].max() ?? 0
    }

    func recordedHabitDays(_ data: HealthProfileData) -> Int {
        let dates = data.dailyWellnessRecords.map(\.date) + data.actionRecords.map(\.date)
        return Set(dates.map { calendar.startOfDay(for: $0) }).count
    }

    func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func averageLast(_ points: [TimeSeriesPointDouble], days: Int, endingAt endDate: Date? = nil) -> Double? {
        guard let endDate else {
            return average(positive(points).suffix(days).map(\.value))
        }
        return average(pointsInLastWindow(points, days: days, endingAt: endDate).map(\.value))
    }

    func averagePrevious(_ points: [TimeSeriesPointDouble], currentDays: Int, previousDays: Int, endingAt endDate: Date? = nil) -> Double? {
        if let endDate {
            return average(pointsInPreviousWindow(points, currentDays: currentDays, previousDays: previousDays, endingAt: endDate).map(\.value))
        }
        let values = positive(points)
        guard values.count > currentDays else { return nil }
        return average(values.dropLast(currentDays).suffix(previousDays).map(\.value))
    }

    func deltaPercent(_ points: [TimeSeriesPointDouble]) -> Double? {
        guard let current = averageLast(points, days: 7),
              let previous = averagePrevious(points, currentDays: 7, previousDays: 7),
              abs(previous) > 0.01 else { return nil }
        return (current - previous) / previous
    }

    func pointsInLastWindow(_ points: [TimeSeriesPointDouble], days: Int, endingAt endDate: Date) -> [TimeSeriesPointDouble] {
        let endDay = calendar.startOfDay(for: endDate)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) ?? endDay
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDate
        return positive(points).filter { $0.date >= start && $0.date < end }
    }

    func pointsInPreviousWindow(_ points: [TimeSeriesPointDouble], currentDays: Int, previousDays: Int, endingAt endDate: Date) -> [TimeSeriesPointDouble] {
        let endDay = calendar.startOfDay(for: endDate)
        let currentStart = calendar.date(byAdding: .day, value: -(currentDays - 1), to: endDay) ?? endDay
        let previousStart = calendar.date(byAdding: .day, value: -previousDays, to: currentStart) ?? currentStart
        return positive(points).filter { $0.date >= previousStart && $0.date < currentStart }
    }

    func actionRecordsInLastWindow(_ records: [LocalActionDayRecord], days: Int, endingAt endDate: Date) -> [LocalActionDayRecord] {
        let endDay = calendar.startOfDay(for: endDate)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) ?? endDay
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDate
        return records.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= start && day < end
        }
    }

    func dailyRecordsInLastWindow(_ records: [DailyWellnessDayRecord], days: Int, endingAt endDate: Date) -> [DailyWellnessDayRecord] {
        let endDay = calendar.startOfDay(for: endDate)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) ?? endDay
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDate
        return records.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= start && day < end
        }
    }

    func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1, let mean = average(values) else { return 0 }
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }

    func longestStreak(_ values: [Bool]) -> Int {
        var current = 0
        var best = 0
        for value in values {
            current = value ? current + 1 : 0
            best = max(best, current)
        }
        return best
    }

    func streakAchievementDate(
        _ points: [TimeSeriesPointDouble],
        target: Int,
        qualifies: (TimeSeriesPointDouble) -> Bool
    ) -> Date? {
        guard target > 0 else { return nil }
        var streak = 0
        var previousDay: Date?
        for point in points.sorted(by: { $0.date < $1.date }) {
            let day = calendar.startOfDay(for: point.date)
            if let previousDay,
               calendar.dateComponents([.day], from: previousDay, to: day).day != 1 {
                streak = 0
            }
            streak = qualifies(point) ? streak + 1 : 0
            previousDay = day
            if streak >= target { return day }
        }
        return nil
    }

    func point(_ date: Date, _ value: Double) -> TimeSeriesPointDouble {
        TimeSeriesPointDouble(timestamp: Int64(date.timeIntervalSince1970), value: value)
    }

    func priority(_ kind: HealthProfileChangeKind) -> Int {
        switch kind {
        case .positive: return 0
        case .risk: return 1
        case .stable: return 2
        case .observing: return 3
        }
    }

    func preferredDaypart(_ summary: SedentaryDaySummary) -> String? {
        SedentaryDaySummary.preferredSedentaryDaypart(in: [summary])?.title
    }

    func tag(
        _ title: String,
        _ detail: String,
        _ confidence: HealthProfileConfidence,
        _ evidence: [String],
        firstDetectedAt: Date? = nil
    ) -> HealthProfileTag {
        HealthProfileTag(title: title, detail: detail, confidence: confidence, evidence: evidence, firstDetectedAt: firstDetectedAt)
    }

    func milestone(_ title: String, _ detail: String, _ date: Date, _ module: HealthProfileModule) -> HealthProfileMilestone {
        HealthProfileMilestone(title: title, detail: detail, achievedAt: date, relatedModule: module)
    }

    func risk(_ title: String, _ detail: String, _ suggestion: String, _ module: HealthProfileModule) -> HealthProfileRiskTendency {
        HealthProfileRiskTendency(title: title, detail: detail, suggestion: suggestion, module: module)
    }

    func action(_ title: String, _ detail: String, _ reason: String, _ priority: HealthProfileActionPriority, _ module: HealthProfileModule) -> HealthProfileActionRecommendation {
        HealthProfileActionRecommendation(title: title, detail: detail, reason: reason, priority: priority, module: module)
    }

    func uniqueActions(_ actions: [HealthProfileActionRecommendation]) -> [HealthProfileActionRecommendation] {
        var seenModules: Set<HealthProfileModule> = []
        var seenTitles: Set<String> = []
        var result: [HealthProfileActionRecommendation] = []
        for action in actions {
            guard !seenTitles.contains(action.title) else { continue }
            if action.priority != .high, seenModules.contains(action.module) { continue }
            seenTitles.insert(action.title)
            seenModules.insert(action.module)
            result.append(action)
        }
        return result
    }

    func actionPriority(_ priority: HealthProfileActionPriority) -> Int {
        switch priority {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }

    func actionSortKey(_ action: HealthProfileActionRecommendation) -> (priority: Int, module: Int) {
        (actionPriority(action.priority), modulePriority(action.module))
    }

    func modulePriority(_ module: HealthProfileModule) -> Int {
        switch module {
        case .healthKit: return 0
        case .sleep: return 1
        case .stress: return 2
        case .sedentary: return 3
        case .activity: return 4
        case .habits: return 5
        case .symptoms: return 6
        case .reproductive: return 7
        }
    }

    func module(forCompletenessTitle title: String?) -> HealthProfileModule {
        switch title {
        case "睡眠": return .sleep
        case "心率与 HRV": return .healthKit
        case "活动": return .activity
        default: return .healthKit
        }
    }

    func module(for kind: HealthProfileDimensionKind) -> HealthProfileModule {
        switch kind {
        case .sleepRhythm: return .sleep
        case .recoveryVitals: return .healthKit
        case .stressStability: return .stress
        case .activityBase: return .activity
        case .habitConsistency: return .habits
        case .menstrualWellbeing: return .reproductive
        case .symptomObservation: return .symptoms
        }
    }
}
