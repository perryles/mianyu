import Foundation

enum PersonalizedReminderKind: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case lowRecovery
    case bedtimeWindDown
    case afternoonReset
    case lateCaffeine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lowRecovery:
            return String(localized: "低恢复提醒")
        case .bedtimeWindDown:
            return String(localized: "睡前提醒")
        case .afternoonReset:
            return String(localized: "午后提醒")
        case .lateCaffeine:
            return String(localized: "晚咖啡因提醒")
        }
    }

    var symbol: String {
        switch self {
        case .lowRecovery:
            return "heart.text.square.fill"
        case .bedtimeWindDown:
            return "moon.stars.fill"
        case .afternoonReset:
            return "sun.max.fill"
        case .lateCaffeine:
            return "cup.and.saucer.fill"
        }
    }

    var identifierPrefix: String {
        "personalized.reminder.\(rawValue)"
    }

    var defaultTime: (hour: Int, minute: Int) {
        switch self {
        case .lowRecovery:
            return (9, 30)
        case .bedtimeWindDown:
            return (21, 30)
        case .afternoonReset:
            return (15, 0)
        case .lateCaffeine:
            return (14, 0)
        }
    }

    var accentHex: String {
        switch self {
        case .lowRecovery:
            return "FF7A70"
        case .bedtimeWindDown:
            return "5E5CE6"
        case .afternoonReset:
            return "F4A259"
        case .lateCaffeine:
            return "B7791F"
        }
    }
}

struct PersonalizedReminderPreference: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var hour: Int
    var minute: Int
    var allowsCycleAdjustment: Bool
    var lastAdoptedRecommendationAt: Date?
    var lastAdoptedRecommendationVersion: String?

    init(
        isEnabled: Bool = false,
        hour: Int,
        minute: Int,
        allowsCycleAdjustment: Bool = true,
        lastAdoptedRecommendationAt: Date? = nil,
        lastAdoptedRecommendationVersion: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.hour = hour
        self.minute = minute
        self.allowsCycleAdjustment = allowsCycleAdjustment
        self.lastAdoptedRecommendationAt = lastAdoptedRecommendationAt
        self.lastAdoptedRecommendationVersion = lastAdoptedRecommendationVersion
    }

    init(kind: PersonalizedReminderKind) {
        self.init(
            isEnabled: false,
            hour: kind.defaultTime.hour,
            minute: kind.defaultTime.minute,
            allowsCycleAdjustment: true,
            lastAdoptedRecommendationAt: nil
        )
    }

    var timeSummary: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

struct PersonalizedReminderRecommendation: Identifiable, Equatable, Sendable {
    let kind: PersonalizedReminderKind
    let isRecommended: Bool
    let reason: String
    let suggestedHour: Int
    let suggestedMinute: Int
    let body: String
    let contextSummary: String
    let recommendationVersion: String
    let generatedAt: Date

    var id: String { kind.rawValue }

    var suggestedTimeSummary: String {
        String(format: "%02d:%02d", suggestedHour, suggestedMinute)
    }
}

struct PersonalizedReminderContext: Sendable {
    let generatedAt: Date
    let healthContext: HealthAIContext
    let assessment: StressPresentationAssessment
    let recoveryPlan: RecoveryScriptPlan
    let periodPhase: CyclePhaseKind
    let cycleDay: Int?
    let caffeineAssessment: CaffeineSleepRiskAssessment
    let caffeineSnapshot: CaffeineBurdenSnapshot
    let caffeineEvents: [CaffeineDoseEvent]
    let recommendedBedtime: Date
    let daylightMinutes: Int?
    let sedentaryElapsedMinutes: Int?
}

private struct PersonalizedReminderPreferencePayload: Codable, Sendable {
    var values: [String: PersonalizedReminderPreference]

    init(values: [String: PersonalizedReminderPreference] = [:]) {
        self.values = values
    }
}

protocol PersonalizedReminderScheduling: Sendable {
    func scheduleOnce(
        identifier: String,
        date: Date,
        title: String,
        body: String,
        categoryIdentifier: String?,
        priority: Int
    )
    func cancel(identifiers: [String])
}

struct SystemPersonalizedReminderScheduler: PersonalizedReminderScheduling {
    func scheduleOnce(
        identifier: String,
        date: Date,
        title: String,
        body: String,
        categoryIdentifier: String?,
        priority: Int
    ) {
        UnifiedReminderWindowCoordinator.shared.scheduleOnce(
            identifier: identifier,
            date: date,
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            source: .personalized,
            priority: priority
        )
    }

    func cancel(identifiers: [String]) {
        UnifiedReminderWindowCoordinator.shared.cancel(identifiers: identifiers)
    }
}

final class PersonalizedReminderCenter {
    static let shared = PersonalizedReminderCenter()

    private let defaults: UserDefaults
    private let scheduler: PersonalizedReminderScheduling
    private let nowProvider: @Sendable () -> Date
    private let contextResolver: @Sendable (Date) async -> PersonalizedReminderContext?
    private let preferencesKey = "personalizedReminderCenter.preferences.v1"
    private let calendar = Calendar.current

    init(
        defaults: UserDefaults = .standard,
        scheduler: PersonalizedReminderScheduling = SystemPersonalizedReminderScheduler(),
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        contextResolver: @escaping @Sendable (Date) async -> PersonalizedReminderContext? = PersonalizedReminderCenter.makeDefaultContext
    ) {
        self.defaults = defaults
        self.scheduler = scheduler
        self.nowProvider = nowProvider
        self.contextResolver = contextResolver
    }

    func loadPreferences() -> [PersonalizedReminderKind: PersonalizedReminderPreference] {
        var resolved = Dictionary(
            uniqueKeysWithValues: PersonalizedReminderKind.allCases.map { kind in
                (kind, PersonalizedReminderPreference(kind: kind))
            }
        )

        guard let data = defaults.data(forKey: preferencesKey),
              let payload = try? JSONDecoder().decode(PersonalizedReminderPreferencePayload.self, from: data) else {
            return resolved
        }

        for kind in PersonalizedReminderKind.allCases {
            if let saved = payload.values[kind.rawValue] {
                resolved[kind] = saved
            }
        }
        return resolved
    }

    func savePreferences(_ preferences: [PersonalizedReminderKind: PersonalizedReminderPreference]) {
        let payload = PersonalizedReminderPreferencePayload(
            values: Dictionary(uniqueKeysWithValues: preferences.map { ($0.key.rawValue, $0.value) })
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: preferencesKey)
    }

    func buildRecommendations(now: Date? = nil) async -> [PersonalizedReminderRecommendation] {
        let reference = now ?? nowProvider()
        guard let context = await contextResolver(reference) else {
            return PersonalizedReminderKind.allCases.map {
                let fallback = PersonalizedReminderPreference(kind: $0)
                return PersonalizedReminderRecommendation(
                    kind: $0,
                    isRecommended: false,
                    reason: String(localized: "数据小仓库还没攒够料，再多记录几天睡眠、压力或咖啡因吧。"),
                    suggestedHour: fallback.hour,
                    suggestedMinute: fallback.minute,
                    body: String(localized: "等素材攒齐，这里就会端上专属你节律的提醒菜单～"),
                    contextSummary: String(localized: "等待更多恢复线索"),
                    recommendationVersion: "\($0.rawValue)-fallback-v1",
                    generatedAt: reference
                )
            }
        }

        return PersonalizedReminderKind.allCases.map { makeRecommendation(for: $0, context: context) }
    }

    func evaluateAndReschedule(now: Date? = nil) async {
        let notificationPreferences = NotificationManagementPreferencesStore.shared.load()
        guard notificationPreferences.recoveryAdviceEnabled else {
            cancelAllPersonalized()
            return
        }

        let reference = now ?? nowProvider()
        let preferences = loadPreferences()
        guard let context = await contextResolver(reference) else {
            cancelAllPersonalized()
            return
        }

        let recommendations = PersonalizedReminderKind.allCases.map { makeRecommendation(for: $0, context: context) }
        let recommendationMap = Dictionary(uniqueKeysWithValues: recommendations.map { ($0.kind, $0) })
        let scheduledKinds = Set(
            recommendations
                .filter(\.isRecommended)
                .sorted { reminderPriority($0.kind, context: context) < reminderPriority($1.kind, context: context) }
                .prefix(2)
                .map(\.kind)
        )

        for kind in PersonalizedReminderKind.allCases {
            guard let preference = preferences[kind] else { continue }
            guard preference.isEnabled else {
                cancel(kind: kind)
                continue
            }

            guard scheduledKinds.contains(kind) else {
                cancel(kind: kind)
                continue
            }

            guard let recommendation = recommendationMap[kind], recommendation.isRecommended else {
                cancel(kind: kind)
                continue
            }

            guard let fireDate = scheduledDate(
                for: kind,
                preference: preference,
                recommendation: recommendation,
                reference: reference
            ) else {
                cancel(kind: kind)
                continue
            }

            scheduler.scheduleOnce(
                identifier: identifier(for: kind, on: fireDate),
                date: fireDate,
                title: kind.title,
                body: resolvedBody(
                    for: kind,
                    recommendation: recommendation,
                    preference: preference,
                    context: context
                ),
                categoryIdentifier: LocalNotificationScheduler.personalizedCategoryIdentifier,
                priority: unifiedWindowPriority(kind, context: context)
            )
        }
    }

    private func reminderPriority(_ kind: PersonalizedReminderKind, context: PersonalizedReminderContext) -> Int {
        let protecting = context.recoveryPlan.readinessBand == .protect || context.recoveryPlan.readinessBand == .recover
        switch kind {
        case .lowRecovery:
            return protecting ? 0 : 3
        case .lateCaffeine:
            return context.caffeineAssessment.riskLevel == .recoveryRisk || context.caffeineAssessment.riskLevel == .lateRisk ? 0 : 2
        case .bedtimeWindDown:
            return protecting ? 1 : 0
        case .afternoonReset:
            return 2
        }
    }

    private func unifiedWindowPriority(_ kind: PersonalizedReminderKind, context: PersonalizedReminderContext) -> Int {
        let kindTieBreaker: Int
        switch kind {
        case .lowRecovery: kindTieBreaker = 4
        case .lateCaffeine: kindTieBreaker = 3
        case .bedtimeWindDown: kindTieBreaker = 2
        case .afternoonReset: kindTieBreaker = 1
        }
        return 500 - reminderPriority(kind, context: context) * 20 + kindTieBreaker
    }

    func cancel(kind: PersonalizedReminderKind) {
        let identifiers = notificationIdentifiers(for: kind, around: nowProvider())
        scheduler.cancel(identifiers: identifiers)
    }

    func cancelAllPersonalized() {
        let identifiers = PersonalizedReminderKind.allCases.flatMap { notificationIdentifiers(for: $0, around: nowProvider()) }
        scheduler.cancel(identifiers: identifiers)
    }

    private func makeRecommendation(
        for kind: PersonalizedReminderKind,
        context: PersonalizedReminderContext
    ) -> PersonalizedReminderRecommendation {
        switch kind {
        case .lowRecovery:
            let shouldRecommend = context.recoveryPlan.confidence >= 0.5
                && (context.recoveryPlan.readinessBand == .protect || context.recoveryPlan.readinessBand == .recover)
            let focusBlockMinutes = recommendedFocusBlockMinutes(for: context.recoveryPlan.readinessBand)
            let baseBody = context.recoveryPlan.readinessBand == .protect
                ? String(localized: "今天电量有点吃紧，重要任务留一段 \(focusBlockMinutes) 分钟冲刺就好，其余都调成省电模式。")
                : String(localized: "上午状态在线，先冲一段 \(focusBlockMinutes) 分钟的硬任务，中途记得喝口水、遛个弯。")
            return PersonalizedReminderRecommendation(
                kind: kind,
                isRecommended: shouldRecommend,
                reason: shouldRecommend
                    ? String(localized: "恢复信号今天有点紧绷，上午先稳着来，看情况再决定要不要加码。")
                    : String(localized: "恢复状态目前稳得住，这条提醒想开就开，随你心情。"),
                suggestedHour: kind.defaultTime.hour,
                suggestedMinute: kind.defaultTime.minute,
                body: cycleAdjustedBody(base: baseBody, phase: context.periodPhase, cycleDay: context.cycleDay),
                contextSummary: context.recoveryPlan.readinessBand.title,
                recommendationVersion: "low-recovery-v1",
                generatedAt: context.generatedAt
            )
        case .bedtimeWindDown:
            let suggested = dateComponents(from: context.recommendedBedtime.addingTimeInterval(-90 * 60))
            let baseBody = context.recoveryPlan.eveningScript
            return PersonalizedReminderRecommendation(
                kind: kind,
                isRecommended: true,
                reason: context.healthContext.sleep.durationMinutes == nil
                    ? String(localized: "睡眠窗口还没摸清，先用一条稳妥的睡前提醒把节律看住。")
                    : String(localized: "看最近的睡眠窗口，今晚提前一点收尾会睡得更香。"),
                suggestedHour: suggested.hour,
                suggestedMinute: suggested.minute,
                body: cycleAdjustedBody(base: baseBody, phase: context.periodPhase, cycleDay: context.cycleDay),
                contextSummary: String(localized: "提前收尾更稳节律"),
                recommendationVersion: "bedtime-wind-down-v1",
                generatedAt: context.generatedAt
            )
        case .afternoonReset:
            let needsReset = (context.daylightMinutes ?? 0) < 10
                || (context.sedentaryElapsedMinutes ?? 0) >= 60
                || (context.recoveryPlan.readinessBand == .protect || context.recoveryPlan.readinessBand == .recover)
            let breakMinutes = recommendedBreakMinutes(sedentaryElapsedMinutes: context.sedentaryElapsedMinutes)
            let baseBody = String(localized: "午后小卡顿？出去晒晒太阳或起身 \(breakMinutes) 分钟，给下半场重启一下。")
            return PersonalizedReminderRecommendation(
                kind: kind,
                isRecommended: needsReset,
                reason: needsReset
                    ? String(localized: "午后是久坐和犯困的高发区，插播一次小重启正合适。")
                    : String(localized: "今天午后节奏挺顺，这条提醒当个备用小闹钟就好。"),
                suggestedHour: kind.defaultTime.hour,
                suggestedMinute: kind.defaultTime.minute,
                body: cycleAdjustedBody(base: baseBody, phase: context.periodPhase, cycleDay: context.cycleDay),
                contextSummary: String(localized: "补光 / 起身 / 收节奏"),
                recommendationVersion: "afternoon-reset-v1",
                generatedAt: context.generatedAt
            )
        case .lateCaffeine:
            let threshold = kind.defaultTime
            let latestDoseHour = context.caffeineEvents
                .map { Calendar.current.component(.hour, from: $0.consumedAt) }
                .max()
            let isDoseLate = (latestDoseHour ?? -1) >= threshold.hour
            let shouldRecommend = isDoseLate
                && (context.caffeineAssessment.riskLevel == .lateRisk
                    || context.caffeineAssessment.riskLevel == .recoveryRisk)
            let baseBody = context.caffeineAssessment.todayAdvice
            return PersonalizedReminderRecommendation(
                kind: kind,
                isRecommended: shouldRecommend,
                reason: shouldRecommend
                    ? String(localized: "今天的咖啡因存货有点多，晚上想睡好，下半场就别再续杯啦。")
                    : String(localized: "咖啡因目前还在安全区，这条提醒备着就行。"),
                suggestedHour: threshold.hour,
                suggestedMinute: threshold.minute,
                body: cycleAdjustedBody(base: baseBody, phase: context.periodPhase, cycleDay: context.cycleDay),
                contextSummary: context.caffeineAssessment.riskLevel.title,
                recommendationVersion: "late-caffeine-v1",
                generatedAt: context.generatedAt
            )
        }
    }

    private func resolvedBody(
        for kind: PersonalizedReminderKind,
        recommendation: PersonalizedReminderRecommendation,
        preference: PersonalizedReminderPreference,
        context: PersonalizedReminderContext
    ) -> String {
        let baseBody: String
        switch kind {
        case .lowRecovery:
            let focusBlockMinutes = recommendedFocusBlockMinutes(for: context.recoveryPlan.readinessBand)
            baseBody = context.recoveryPlan.readinessBand == .protect
                ? String(localized: "今天电量有点吃紧，重要任务留一段 \(focusBlockMinutes) 分钟冲刺就好，其余都调成省电模式。")
                : String(localized: "上午状态在线，先冲一段 \(focusBlockMinutes) 分钟的硬任务，中途记得喝口水、遛个弯。")
        case .bedtimeWindDown:
            baseBody = context.recoveryPlan.eveningScript
        case .afternoonReset:
            baseBody = String(localized: "午后小卡顿？出去晒晒太阳或起身 \(recommendedBreakMinutes(sedentaryElapsedMinutes: context.sedentaryElapsedMinutes)) 分钟，给下半场重启一下。")
        case .lateCaffeine:
            baseBody = context.caffeineAssessment.todayAdvice
        }

        guard preference.allowsCycleAdjustment else {
            return managedNotificationBody(
                base: baseBody,
                recommendation: recommendation,
                context: context
            )
        }
        return managedNotificationBody(
            base: recommendation.body,
            recommendation: recommendation,
            context: context
        )
    }

    private func managedNotificationBody(
        base: String,
        recommendation: PersonalizedReminderRecommendation,
        context: PersonalizedReminderContext
    ) -> String {
        let preferences = NotificationManagementPreferencesStore.shared.load()
        let actionText = preferences.includeActionSuggestion ? base : String(localized: "你的恢复状态有新剧情，得空打开 眠屿 追个更新～")

        switch preferences.contentDetailLevel {
        case .brief:
            return firstSentence(actionText)
        case .balanced:
            var parts = [firstSentence(actionText)]
            if preferences.includeReasonExplanation {
                parts.append(firstSentence(recommendation.reason))
            }
            return joinedNotificationParts(parts)
        case .detailed:
            var parts = [actionText]
            if preferences.includeReasonExplanation {
                parts.append(recommendation.reason)
            }
            if preferences.includeTrendSummary {
                parts.append(String(localized: "当前线索：\(recommendation.contextSummary)。"))
            }
            if preferences.includeHealthValues {
                let stressText = context.assessment.score.map { String(localized: "压力约 \($0) 分") } ?? String(localized: "压力样本暂缺")
                parts.append(String(localized: "\(stressText)，睡眠目标 \(SleepGoalResolver.goalMinutes() / 60) 小时左右。"))
            }
            return joinedNotificationParts(parts)
        }
    }

    private func firstSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        for marker in ["。", "！", "？", ".", "!", "?"] {
            if let range = trimmed.range(of: marker) {
                return String(trimmed[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return trimmed
    }

    private func joinedNotificationParts(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func recommendedFocusBlockMinutes(for band: RecoveryReadinessBand) -> Int {
        switch band {
        case .protect:
            return 20
        case .recover:
            return 25
        case .balanced:
            return 35
        case .pushLight:
            return 45
        }
    }

    private func recommendedBreakMinutes(sedentaryElapsedMinutes: Int?) -> Int {
        let elapsed = sedentaryElapsedMinutes ?? 0
        if elapsed >= 90 { return 5 }
        if elapsed >= 60 { return 3 }
        return 2
    }

    private func scheduledDate(
        for kind: PersonalizedReminderKind,
        preference: PersonalizedReminderPreference,
        recommendation: PersonalizedReminderRecommendation,
        reference: Date
    ) -> Date? {
        switch kind {
        case .lateCaffeine:
            let threshold = date(on: reference, hour: preference.hour, minute: preference.minute)
            if reference < threshold {
                return threshold
            }
            let immediate = reference.addingTimeInterval(60)
            return calendar.isDate(immediate, inSameDayAs: reference) ? immediate : nil
        default:
            let target = date(on: reference, hour: preference.hour, minute: preference.minute)
            guard target > reference else { return nil }
            return target
        }
    }

    private func date(on reference: Date, hour: Int, minute: Int) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: reference)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? reference
    }

    private func dateComponents(from date: Date) -> (hour: Int, minute: Int) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 21, components.minute ?? 30)
    }

    private func identifier(for kind: PersonalizedReminderKind, on date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return "\(kind.identifierPrefix).\(formatter.string(from: date))"
    }

    private func notificationIdentifiers(for kind: PersonalizedReminderKind, around date: Date) -> [String] {
        (-1...1).compactMap { offset in
            guard let shifted = calendar.date(byAdding: .day, value: offset, to: date) else { return nil }
            return identifier(for: kind, on: shifted)
        }
    }

    private func cycleAdjustedBody(base: String, phase: CyclePhaseKind, cycleDay: Int?) -> String {
        guard phase != .unknown else { return base }
        let suffix: String
        switch phase {
        case .menstruation:
            suffix = String(localized: " 正值经期，今天请把舒服和休息排在第一位，其他都可以等等。")
        case .follicular:
            suffix = String(localized: " 正值卵泡期，状态回暖中，稳住节奏就能顺顺地往前推。")
        case .ovulation:
            suffix = String(localized: " 正值排卵期，火力虽足，也记得留点恢复余量。")
        case .luteal:
            suffix = String(localized: " 正值黄体期，后半天容易变敏感，对自己温柔一点。")
        case .unknown:
            suffix = ""
        }

        if let cycleDay {
            return "\(base)\(suffix) " + String(localized: "周期第 \(cycleDay) 天。")
        }
        return base + suffix
    }

    private static func makeDefaultContext(now: Date) async -> PersonalizedReminderContext? {
        let healthKitManager = HealthKitManager.shared
        let healthDataManager = HealthDataManager.shared
        let appGroupManager = AppGroupManager.shared
        let actionRecordStore = ActionRecordStore.shared
        let caffeineCoach = CaffeineSleepStressCoachEngine()

        let cachedCurrent = (try? StressStore().load())?.current
        let currentEvaluation = StressPresentation.evaluation(from: healthDataManager.realtimeHealth)
        let assessment = StressPresentation.assessment(
            from: currentEvaluation.result == nil ? (cachedCurrent ?? currentEvaluation) : currentEvaluation
        )

        async let restingHeartRateTask = try? healthKitManager.fetchRestingHeartRate()
        async let hrvAveragesTask = try? healthKitManager.fetchDailyHRVAverages(days: 14)
        async let restingAveragesTask = try? healthKitManager.fetchDailyRestingHeartRateAverages(days: 14)
        async let sleepIntervalTask = try? healthKitManager.fetchLatestSleepInterval()
        async let nightlyHrvTask = try? healthKitManager.fetchNightlyHRVAverages(days: 1)
        async let respiratoryRateTask = try? healthKitManager.fetchLatestRespiratoryRate()
        async let wristTemperatureTask = try? healthKitManager.fetchLatestSleepingWristTemperature()
        async let sedentarySummaryTask = try? healthKitManager.fetchSedentaryDaySummary(on: now)

        let sleepInterval = await sleepIntervalTask ?? nil
        let nightlyHrv = (await nightlyHrvTask ?? []).last?.avgMs
        let dailyHrvAverages = await hrvAveragesTask ?? []
        let restingAverages = await restingAveragesTask ?? []
        let record = actionRecordStore.record(for: now)
        let caffeineEvents = actionRecordStore.caffeineDoseEvents(on: now)
        let consumedToday = max(record.caffeineMg, caffeineEvents.reduce(0) { $0 + $1.amountMg })
        let sleepGoalMinutes = SleepGoalResolver.goalMinutes()
        let targetBedtime = resolveTargetBedtime(from: sleepInterval, now: now, sleepGoalMinutes: sleepGoalMinutes)
        let caffeineAssessment = caffeineCoach.assessSleepRisk(
            dailyTotalMg: consumedToday,
            doseEvents: caffeineEvents,
            now: now,
            targetBedtime: targetBedtime,
            sleepGoalMinutes: sleepGoalMinutes,
            stressScore: assessment.score,
            lastNightSleepMinutes: healthDataManager.currentSleep?.duration_minutes ?? appGroupManager.getSleepDurationMinutes(),
            lastNightSleepScore: healthDataManager.currentSleep?.sleep_score ?? appGroupManager.getSleepScore()
        )
        let caffeineSnapshot = caffeineCoach.burdenSnapshot(
            dailyTotalMg: consumedToday,
            doseEvents: caffeineEvents,
            now: now
        )
        let sunlightMinutes: Int? = appGroupManager.getValue(forKey: AppGroupManager.Keys.sunlightMinutesToday)
        let sedentaryElapsed = appGroupManager.getSedentaryElapsedMinutes()
        let sedentarySummary = await sedentarySummaryTask ?? nil

        let sleepData = healthDataManager.currentSleep ?? SleepData(
            sleep_score: appGroupManager.getSleepScore() ?? 0,
            duration_minutes: appGroupManager.getSleepDurationMinutes() ?? 0,
            stages: []
        )

        let healthContext = HealthAIContextBuilder().makeContext(
            assessment: assessment,
            realtimeHealth: healthDataManager.realtimeHealth,
            restingHeartRate: await restingHeartRateTask ?? nil,
            avgHrvToday: positiveDouble(dailyHrvAverages.last?.value) ?? healthDataManager.realtimeHealth.flatMap { $0.hrv > 0 ? $0.hrv : nil },
            recentAvgHrv: HealthBaselineStrategy.usableValue(for: dailyHrvAverages.map(\.value), metric: .hrvSDNN),
            recentAvgRestingHeartRate: HealthBaselineStrategy.usableValue(for: restingAverages.map(\.value), metric: .restingHeartRate),
            sleepData: sleepData.duration_minutes > 0 || sleepData.sleep_score > 0 ? sleepData : nil,
            sleepInterval: sleepInterval,
            nightlyHrv: nightlyHrv,
            nightlyRespiratoryRate: await respiratoryRateTask ?? nil,
            sleepingWristTemperature: await wristTemperatureTask ?? nil,
            sedentaryState: makeSedentaryState(appGroupManager: appGroupManager),
            sedentarySummary: sedentarySummary,
            activityPoints: [],
            walkingSpeedMpsToday: healthDataManager.currentActivity?.walking_speed_mps,
            waterMlToday: appGroupManager.getWaterIntakeMl().map { Int($0.rounded()) },
            caffeineConsumedTodayMg: consumedToday,
            daylightMinutesToday: sunlightMinutes
        )

        guard let recoveryPlan = healthContext.recoveryScriptPlan else {
            return nil
        }

        let periodSummary = PeriodStore.shared.summary(referenceDate: now)
        let periodCurrent = periodSummary.current
        return PersonalizedReminderContext(
            generatedAt: now,
            healthContext: healthContext,
            assessment: assessment,
            recoveryPlan: recoveryPlan,
            periodPhase: CyclePhaseKind(phaseRawValue: periodCurrent?.phase),
            cycleDay: periodCurrent?.dayIndex,
            caffeineAssessment: caffeineAssessment,
            caffeineSnapshot: caffeineSnapshot,
            caffeineEvents: caffeineEvents,
            recommendedBedtime: targetBedtime,
            daylightMinutes: sunlightMinutes,
            sedentaryElapsedMinutes: sedentaryElapsed
        )
    }

    private static func resolveTargetBedtime(from interval: SleepInterval?, now: Date, sleepGoalMinutes: Int) -> Date {
        let calendar = Calendar.current
        if let interval {
            return interval.start.addingTimeInterval(24 * 60 * 60)
        }
        return calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now) ?? now
    }

    private static func positiveDouble(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func medianPositive(_ values: [Double]) -> Double? {
        let positive = values.filter { $0 > 0 }.sorted()
        guard !positive.isEmpty else { return nil }
        let middle = positive.count / 2
        if positive.count.isMultiple(of: 2) {
            return (positive[middle - 1] + positive[middle]) / 2
        }
        return positive[middle]
    }

    private static func makeSedentaryState(appGroupManager: AppGroupManager) -> DashboardSedentaryState? {
        guard let elapsed = appGroupManager.getSedentaryElapsedMinutes() else { return nil }
        return DashboardSedentaryState(
            seatedStartAt: appGroupManager.getSedentarySeatedStartAt(),
            lastActivityAt: appGroupManager.getSedentaryLastActivityAt(),
            elapsedMinutes: elapsed,
            isCounting: appGroupManager.getSedentaryIsCounting() ?? false,
            pausedBySleep: appGroupManager.getSedentaryPausedBySleep() ?? false,
            sourceStatus: .ready
        )
    }
}
