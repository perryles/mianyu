/// Health Data Manager 负责健康数据访问与加工，管理 HealthKit 授权、查询和应用内可用数据的整理。
import Foundation
import HealthKit
import OSLog

extension Notification.Name {
    static let healthDataManagerRealtimeHealthDidChange = Notification.Name(
        "HealthDataManager.realtimeHealthDidChange"
    )
}

/// 健康数据管理器 作为健康数据能力层里的服务或调度入口。
/// 负责健康数据读取与授权管理。
@MainActor
@Observable
final class HealthDataManager: NSObject {
    static let shared = HealthDataManager()
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "WatchSync")
    private let appGroup = AppGroupManager.shared
    private let stressEngine: StressRealtimeEvaluating = StressRealtimeEngine()
    private let minimumAutoSyncInterval: TimeInterval = 5 * 60
    nonisolated enum LocalCacheKeys {
        static let activity = "lastActivityData"
        static let stress = "lastStressData"
        static let sleep = "lastSleepData"
        static let realtime = "lastRealtimeHealth"

        static let all = [
            activity,
            stress,
            sleep,
            realtime
        ]
    }
    
    var currentActivity: ActivityData?
    var currentStress: StressData?
    var currentSleep: SleepData?
    var realtimeHealth: RealtimeHealth? {
        didSet {
            guard realtimeHealth != oldValue else { return }
            NotificationCenter.default.post(
                name: .healthDataManagerRealtimeHealthDidChange,
                object: self
            )
        }
    }
    private(set) var bodyAgeSummary: WatchBodyAgeSummary?
    private var latestBodyAgeSummary: WatchBodyAgeSummary?
    private var lastAutoSyncAt: Date?
    
    private override init() {
        super.init()
        latestBodyAgeSummary = Self.loadStoredBodyAgeSummary()
        bodyAgeSummary = latestBodyAgeSummary
        setupWatchSync()
        loadFromLocalStore()
        refreshAppGroupHealthSnapshotFromLocalCache()
        Task {
            await refreshBodyAgeSummary()
        }
    }

    func pushRealtimeToWatch(_ realtime: RealtimeHealth) {
        let resolved = Self.mergingRealtimeVitals(
            realtime,
            preservingCanonicalStressFrom: realtimeHealth
        )
        realtimeHealth = resolved
        saveToLocalStore()
        saveToAppGroup(realtime: resolved)
        WidgetSyncService.refresh([.overall, .stress, .vitals, .complication], reason: .healthUpdate)
        sendToWatch(realtime: resolved)
    }

    /// 主观记录可参与本地趋势，但不会替代今日页和小组件使用的 3.1 生理实时评估。
    func recordManualStress(_ value: Int, at date: Date = Date()) {
        let score = StressRules.clamp(value)
        let timestamp = Int64(date.timeIntervalSince1970)
        let history: [TimeSeriesPoint]
        if score > 0 {
            history = mergedStressHistory(
                existing: currentStress?.history ?? [],
                newPoint: TimeSeriesPoint(timestamp: timestamp, value: score)
            )
        } else {
            history = currentStress?.history ?? []
        }
        let average = history.isEmpty
            ? score
            : Int((Double(history.map(\.value).reduce(0, +)) / Double(history.count)).rounded())

        currentStress = StressData(
            current_stress: score,
            average_stress: average,
            history: history
        )
        saveToLocalStore()
        appGroup.saveStressHistory(history.map {
            WatchStressHistoryPoint(timestamp: Int($0.timestamp), value: $0.value)
        })
        WidgetSyncService.refresh([.stress, .complication], reason: .healthUpdate)
        flushLatestToWatch()
        Self.logger.info("[Stress][HealthDataManager] operation=recordManualStress")
    }

    static func mergingRealtimeVitals(
        _ incoming: RealtimeHealth,
        preservingCanonicalStressFrom existing: RealtimeHealth?
    ) -> RealtimeHealth {
        let incomingHasCanonicalStress = isCanonicalStressSnapshot(incoming)
        let existingHasCanonicalStress = existing.map(isCanonicalStressSnapshot) ?? false
        let stressSource: RealtimeHealth? = if incomingHasCanonicalStress {
            incoming
        } else if existingHasCanonicalStress {
            existing
        } else {
            nil
        }

        let incomingHasCanonicalDailyStress =
            incoming.daily_stress_algorithm_version == StressResult.currentAlgorithmVersion
        let existingHasCanonicalDailyStress =
            existing?.daily_stress_algorithm_version == StressResult.currentAlgorithmVersion
        let dailyStressSource: RealtimeHealth? = if incomingHasCanonicalDailyStress {
            incoming
        } else if existingHasCanonicalDailyStress {
            existing
        } else {
            nil
        }

        let usesIncomingVitalsAsCompleteSnapshot = incomingHasCanonicalStress
        let bpm = usesIncomingVitalsAsCompleteSnapshot
            ? incoming.bpm
            : (incoming.bpm > 0 ? incoming.bpm : existing?.bpm ?? 0)
        let hrv = usesIncomingVitalsAsCompleteSnapshot
            ? incoming.hrv
            : (incoming.hrv > 0 ? incoming.hrv : existing?.hrv ?? 0)
        let timestamp = incomingHasCanonicalStress || stressSource == nil
            ? incoming.timestamp
            : stressSource?.timestamp ?? incoming.timestamp

        return RealtimeHealth(
            bpm: bpm,
            hrv_sdnn: hrv,
            stress_value: stressSource?.stress_value ?? 0,
            stress_level: stressSource?.stress_level,
            stress_explanation_code: stressSource?.stress_explanation_code,
            stress_confidence: stressSource?.stress_confidence,
            stress_quality: stressSource?.stress_quality,
            stress_algorithm_version: stressSource?.stress_algorithm_version,
            stress_unavailable_reason: stressSource?.stress_unavailable_reason,
            daily_stress_value: dailyStressSource?.daily_stress_value,
            daily_stress_quality: dailyStressSource?.daily_stress_quality,
            daily_stress_algorithm_version: dailyStressSource?.daily_stress_algorithm_version,
            timestamp: timestamp,
            hr_abnormal: incoming.hr_abnormal ?? existing?.hr_abnormal,
            hr_abnormal_type: incoming.hr_abnormal_type ?? existing?.hr_abnormal_type
        )
    }

    private static func isCanonicalStressSnapshot(_ realtime: RealtimeHealth) -> Bool {
        realtime.stress_algorithm_version == StressResult.currentAlgorithmVersion
            || realtime.stress_unavailable_reason != nil
    }

    func pushSedentaryToWatch(elapsedMinutes: Int, isCounting: Bool, pausedBySleep: Bool, seatedStartAt: Date?, lastActivityAt: Date?) {
        appGroup.saveSedentaryState(
            elapsedMinutes: elapsedMinutes,
            isCounting: isCounting,
            pausedBySleep: pausedBySleep,
            seatedStartAt: seatedStartAt,
            lastActivityAt: lastActivityAt
        )

        flushLatestToWatch()
    }

    func pushSedentaryBreakToWatch(isActive: Bool, durationMinutes: Int?, startedAt: Date?) {
        appGroup.saveSedentaryBreakState(
            isActive: isActive,
            durationMinutes: durationMinutes,
            startedAt: startedAt
        )

        flushLatestToWatch()
    }

    var isWatchReachable: Bool {
        WatchConnectivitySyncService.shared.isWatchReachable
    }

    var watchActivationState: WatchSessionState {
        WatchConnectivitySyncService.shared.watchActivationState
    }

    var lastWatchSyncDate: Date? {
        WatchConnectivitySyncService.shared.lastWatchSyncDate
    }

    var isWatchPaired: Bool {
        WatchConnectivitySyncService.shared.isWatchPaired
    }

    var isWatchAppInstalled: Bool {
        WatchConnectivitySyncService.shared.isWatchAppInstalled
    }

    func syncAllDataIfNeeded(force: Bool = false) {
        let now = Date()
        if force == false,
           let lastAutoSyncAt,
           now.timeIntervalSince(lastAutoSyncAt) < minimumAutoSyncInterval {
            return
        }
        lastAutoSyncAt = now
        Task {
            await syncAllData(forceRefresh: force)
        }
    }

    private func setupWatchSync() {
        let watchSync = WatchConnectivitySyncService.shared
        watchSync.onRequestSnapshot = { [weak self] _ in
            self?.watchPayload(realtime: self?.realtimeHealth) ?? [:]
        }
        watchSync.onRecordHabit = { [weak self] type, amount, completion in
            self?.handleHabitFromWatch(type: type, amount: amount, completion: completion)
        }
        watchSync.onComplicationTemplate = { template in
            self.appGroup.saveDefaultComplicationTemplate(template)
            WidgetSyncService.refresh([.complication], reason: .settings)
        }
        watchSync.onAIQuestion = { [weak self] question, completion in
            self?.answerAIQuestionFromWatch(question: question, completion: completion)
        }
        watchSync.onSnapshotReceived = { [weak self] snapshot in
            self?.applySnapshotFromWatch(snapshot)
        }
        watchSync.onRealtimeVitalsReceived = { [weak self] vitals in
            self?.applyRealtimeVitalsFromWatch(vitals)
        }
        watchSync.activateIfNeeded()
    }
    
    func syncAllData(forceRefresh: Bool = false) async {
        if forceRefresh {
            HealthKitRepositoryCache.shared.invalidateAll()
        }

        // 同步活动数据
        async let steps = try? HealthKitManager.shared.fetchStepsCountOptional()
        async let energy = try? HealthKitManager.shared.fetchActiveEnergyBurnedOptional()
        async let exercise = try? HealthKitManager.shared.fetchExerciseTimeOptional()
        async let stand = try? HealthKitManager.shared.fetchStandHoursOptional()
        async let sunlight = try? HealthKitManager.shared.fetchTimeInDaylightMinutes(on: Date())
        async let walkingSpeed = try? HealthKitManager.shared.fetchAverageWalkingSpeedToday()
        async let environmentalDb = try? HealthKitManager.shared.fetchEnvironmentalAudioExposure()
        async let headphoneDb = try? HealthKitManager.shared.fetchHeadphoneAudioExposureToday()
        
        let fetchedSteps = await steps
        let fetchedEnergy = await energy
        let fetchedExercise = await exercise
        let fetchedStand = await stand
        let fetchedSunlight = await sunlight
        let fetchedWalkingSpeed = await walkingSpeed
        let fetchedEnvironmentalDb = await environmentalDb
        let fetchedHeadphoneDb = await headphoneDb
        
        let previousActivity = currentActivity
        let activity = ActivityData(
            steps: fetchedSteps ?? previousActivity?.steps ?? 0,
            active_energy: fetchedEnergy ?? previousActivity?.active_energy ?? 0,
            exercise_time: fetchedExercise ?? previousActivity?.exercise_time ?? 0,
            stand_hours: fetchedStand ?? previousActivity?.stand_hours ?? 0,
            walking_speed_mps: fetchedWalkingSpeed ?? previousActivity?.walking_speed_mps ?? nil,
            environmental_audio_exposure_db: fetchedEnvironmentalDb ?? previousActivity?.environmental_audio_exposure_db ?? nil,
            headphone_audio_exposure_db: fetchedHeadphoneDb ?? previousActivity?.headphone_audio_exposure_db ?? nil
        )
        
        // 同步实时数据与压力
        let realtime = await buildRealtimeHealth(previous: realtimeHealth)
        let resolvedStress = realtime.stress_value
        
        let nowTimestamp = Int64(Date().timeIntervalSince1970)
        let stressHistory = resolvedStress > 0
            ? mergedStressHistory(
                existing: currentStress?.history ?? [],
                newPoint: TimeSeriesPoint(timestamp: nowTimestamp, value: resolvedStress)
            )
            : (currentStress?.history ?? [])
        let stressAverage = stressHistory.isEmpty
            ? (resolvedStress > 0 ? resolvedStress : currentStress?.average_stress ?? 0)
            : Int((Double(stressHistory.map(\.value).reduce(0, +)) / Double(stressHistory.count)).rounded())
        let stressData = StressData(
            current_stress: resolvedStress,
            average_stress: stressAverage,
            history: stressHistory
        )
        
        // 同步睡眠数据
        async let sleepDur = try? HealthKitManager.shared.fetchSleepDurationInMinutes()
        async let sleepStages = try? HealthKitManager.shared.fetchDetailedSleepStages()
        
        let previousSleep = currentSleep
        let fetchedSleepDuration = await sleepDur
        let duration = fetchedSleepDuration ?? previousSleep?.duration_minutes ?? 0
        let stages = (await sleepStages).flatMap { $0.isEmpty ? nil : $0 } ?? previousSleep?.stages ?? []
        let sleep = SleepData(
            sleep_score: previousSleep?.sleep_score ?? 0,
            duration_minutes: duration,
            stages: stages
        )
        
        // HealthKit queries may return even after the background task expires.
        // Do not persist, publish widgets, or notify Watch for a cancelled sync.
        guard !Task.isCancelled else { return }
        currentActivity = activity
        realtimeHealth = realtime
        currentStress = stressData
        currentSleep = sleep
        
        saveToLocalStore()
        appGroup.saveActivitySummary(
            steps: activity.steps > 0 ? activity.steps : previousActivity?.steps,
            activeEnergy: activity.active_energy > 0 ? activity.active_energy : previousActivity?.active_energy,
            exerciseMinutes: activity.exercise_time > 0 ? activity.exercise_time : previousActivity?.exercise_time,
            standHours: activity.stand_hours > 0 ? activity.stand_hours : previousActivity?.stand_hours
        )
        appGroup.saveWalkingMobilitySummary(
            speedMps: activity.walking_speed_mps,
            paceSecondsPerKm: WatchSyncMetrics.paceSecondsPerKilometer(from: activity.walking_speed_mps)
        )
        appGroup.saveSunlightSummary(minutesToday: fetchedSunlight)
        let persistedSleepDuration = sleep.duration_minutes > 0 ? sleep.duration_minutes : previousSleep?.duration_minutes
        appGroup.saveSleepSummary(
            durationMinutes: persistedSleepDuration,
            score: sleep.sleep_score > 0 ? sleep.sleep_score : previousSleep?.sleep_score
        )
        saveToAppGroup(realtime: realtime)
        WidgetSyncService.refresh([.overall, .sunlight, .activity, .activityConfigurable, .sleep, .stress, .vitals, .complication], reason: .healthUpdate)
        sendToWatch(realtime: realtime)
        Task {
            await refreshBodyAgeSummary()
            await PersonalizedReminderCenter.shared.evaluateAndReschedule()
        }
    }
    
    private func buildRealtimeHealth(previous: RealtimeHealth?) async -> RealtimeHealth {
        async let restingHeartRate = try? HealthKitManager.shared.fetchRestingHeartRate()
        async let recentHeartRateSamples = try? HealthKitManager.shared.fetchRecentHeartRateSeries(minutes: 30, maxPoints: 180)
        async let recentHrvSamples = try? HealthKitManager.shared.fetchRecentHRVSamples(minutes: 240, maxPoints: 240)
        async let baselineHrv = try? HealthKitManager.shared.fetchDailyHRVAverages(days: 14)
        async let baselineResting = try? HealthKitManager.shared.fetchDailyRestingHeartRateAverages(days: 14)
        async let sleepInterval = try? HealthKitManager.shared.fetchLatestSleepInterval()
        async let nightlyHrv = try? HealthKitManager.shared.fetchNightlyHRVAverages(days: 1)
        async let sleepSummaries = try? HealthKitManager.shared.fetchSleepNightSummaries(days: 7)
        async let workoutContext = try? HealthKitManager.shared.fetchLatestWorkoutContext()
        async let age = HealthKitManager.shared.fetchChronologicalAge()
        async let habitualSleepWindow = try? HealthKitManager.shared.fetchStressHabitualSleepWindow(days: 7)

        let referenceNow = Date()
        let restingValue = (await restingHeartRate).flatMap { $0 > 0 ? $0 : nil }
        let recentHeartRatePoints = await recentHeartRateSamples ?? []
        let recentHrvPoints = await recentHrvSamples ?? []
        // 不允许一两晚数据直接成为个人基线。校准期间压力引擎仍可使用实时信号，
        // 但不能基于不稳定的中位数输出偏离基线的判断。
        let baselineHrvState = HealthBaselineStrategy.state(
            for: (await baselineHrv ?? []).map(\.value),
            metric: .hrvSDNN
        )
        let baselineRestingState = HealthBaselineStrategy.state(
            for: (await baselineResting ?? []).map(\.value),
            metric: .restingHeartRate
        )
        let latestInterval = await sleepInterval ?? nil
        let latestNightlyHrv = (await nightlyHrv ?? []).last?.avgMs
        let latestSleepSummary = (await sleepSummaries ?? []).last
        let overnightMinHeartRate = try? await HealthKitManager.shared.fetchOvernightMinimumHeartRate(interval: latestInterval)
        let workout = await workoutContext ?? nil
        let resolvedAge = await age
        let engineInput = StressHealthKitAdapter.makeRealtimeInput(
            now: referenceNow,
            heartRatePoints: recentHeartRatePoints,
            hrvPoints: recentHrvPoints,
            restingHeartRate: restingValue,
            restingBaseline: baselineRestingState,
            hrvBaseline: baselineHrvState,
            sleepInterval: latestInterval,
            sleepMinutes: latestSleepSummary?.asleepMinutes,
            sleepEfficiency: latestSleepSummary?.efficiency,
            nightlyHrv: latestNightlyHrv,
            overnightMinHeartRate: overnightMinHeartRate ?? nil,
            workoutContext: workout,
            chronologicalAge: resolvedAge,
            habitualSleepWindow: await habitualSleepWindow ?? .fallback
        )
        let evaluation = stressEngine.evaluate(input: engineInput, previous: previous.flatMap(Self.outputFromRealtime))
        let latestHeartRate = recentHeartRatePoints.last.map { Double($0.value) } ?? 0
        let latestHrv = recentHrvPoints.last?.value ?? 0
        let result = evaluation.result
        let unavailableReason: StressUnavailableReason? = {
            guard case let .unavailable(reason) = evaluation else { return nil }
            return reason
        }()
        Self.logger.info("[Stress][HealthDataManager] operation=evaluate")
        return RealtimeHealth(
            bpm: Int(latestHeartRate.rounded()),
            hrv_sdnn: latestHrv,
            stress_value: result?.score ?? 0,
            stress_level: result?.state.rawValue,
            stress_explanation_code: result?.explanationCode.rawValue,
            stress_confidence: result?.confidence,
            stress_quality: result?.quality.rawValue,
            stress_algorithm_version: result?.algorithmVersion,
            stress_unavailable_reason: unavailableReason?.rawValue,
            daily_stress_value: previous?.daily_stress_value,
            daily_stress_quality: previous?.daily_stress_quality,
            daily_stress_algorithm_version: previous?.daily_stress_algorithm_version,
            timestamp: result?.timestamp ?? Int64(referenceNow.timeIntervalSince1970),
            hr_abnormal: nil,
            hr_abnormal_type: nil
        )
    }

    private static func outputFromRealtime(_ realtime: RealtimeHealth) -> StressResult? {
        guard realtime.stress_level != nil || realtime.stress_value > 0 else { return nil }
        let state = StressState(rawValue: realtime.stress_level ?? "") ?? StressRules.state(for: realtime.stress_value)
        let recovery = StressRecoverySnapshot(recoveryScore: 50, recoveryDebt: 50, sleepMinutes: nil, sleepEfficiency: nil, nightlyHrv: nil, overnightMinHeartRate: nil)
        let confidence = StressRules.clamp(realtime.stress_confidence ?? 0.5, lower: 0, upper: 1)
        return StressResult(
            timestamp: realtime.timestamp,
            rawScore: realtime.stress_value,
            smoothedScore: realtime.stress_value,
            state: state,
            band: StressRules.band(for: state),
            dominantDriver: .hrvDeviation,
            dominantDrivers: [.hrvDeviation],
            explanationCode: StressExplanationCode(rawValue: realtime.stress_explanation_code ?? "") ?? .fallback,
            confidence: confidence,
            quality: StressDataQuality(rawValue: realtime.stress_quality ?? "") ?? StressRules.quality(for: confidence),
            algorithmVersion: realtime.stress_algorithm_version ?? StressResult.currentAlgorithmVersion,
            recovery: recovery,
            workout: .inactive,
            components: StressComponentScores(
                hrvDeviation: realtime.stress_value,
                hrDeviation: realtime.stress_value,
                hrvTrend: 50,
                hrTrend: 50,
                recoveryDebt: 50,
                circadian: 50,
                workoutLoad: 20,
                mentalRaw: realtime.stress_value,
                physicalRaw: realtime.stress_value,
                rawScore: realtime.stress_value,
                smoothedScore: realtime.stress_value
            )
        )
    }

    private static func medianPositive(_ values: [Double]) -> Double? {
        let filtered = values.filter { $0 > 0 }.sorted()
        guard !filtered.isEmpty else { return nil }
        let middle = filtered.count / 2
        if filtered.count.isMultiple(of: 2) {
            return (filtered[middle - 1] + filtered[middle]) / 2
        }
        return filtered[middle]
    }

    /// 方法说明：把新的实时压力点合并进今天的本地压力历史。
    /// 合并策略会做三件事：
    /// 1. 只保留今天的点，避免昨天的数据污染“今日压力”；
    /// 2. 以 5 分钟为一个时间桶，同桶只保留最新点，和今日页曲线的展示口径保持一致；
    /// 3. 限制总点数，避免本地缓存无限增长。
    private func mergedStressHistory(existing: [TimeSeriesPoint], newPoint: TimeSeriesPoint) -> [TimeSeriesPoint] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let existingToday = existing.filter {
            $0.value > 0 && $0.date >= startOfToday
        }

        var deduped: [Int64: TimeSeriesPoint] = [:]
        for point in existingToday + [newPoint] {
            let bucket = point.timestamp / 300
            deduped[bucket] = point
        }

        return Array(deduped.values)
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(96)
            .map { $0 }
    }
    
    // MARK: - 本地存储
    private func saveToLocalStore() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(currentActivity) {
            defaults.set(data, forKey: LocalCacheKeys.activity)
        }
        if let data = try? JSONEncoder().encode(currentStress) {
            defaults.set(data, forKey: LocalCacheKeys.stress)
        }
        if let data = try? JSONEncoder().encode(currentSleep) {
            defaults.set(data, forKey: LocalCacheKeys.sleep)
        }
        if let data = try? JSONEncoder().encode(realtimeHealth) {
            defaults.set(data, forKey: LocalCacheKeys.realtime)
        }
    }
    
    func loadFromLocalStore() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: LocalCacheKeys.activity),
           let activity = try? JSONDecoder().decode(ActivityData.self, from: data) {
            self.currentActivity = activity
        }
        if let data = defaults.data(forKey: LocalCacheKeys.stress),
           let stress = try? JSONDecoder().decode(StressData.self, from: data) {
            self.currentStress = stress
        }
        if let data = defaults.data(forKey: LocalCacheKeys.sleep),
           let sleep = try? JSONDecoder().decode(SleepData.self, from: data) {
            self.currentSleep = sleep
        }
        if let data = defaults.data(forKey: LocalCacheKeys.realtime) {
            if let realtime = try? JSONDecoder().decode(RealtimeHealth.self, from: data),
               realtime.stress_algorithm_version == StressResult.currentAlgorithmVersion {
                self.realtimeHealth = realtime
            } else {
                // 算法版本升级后旧实时压力与今日压力历史不得继续混合展示。
                defaults.removeObject(forKey: LocalCacheKeys.realtime)
                defaults.removeObject(forKey: LocalCacheKeys.stress)
                currentStress = nil
                realtimeHealth = nil
            }
        }
    }

    func clearLocalCaches() {
        let defaults = UserDefaults.standard
        LocalCacheKeys.all.forEach { defaults.removeObject(forKey: $0) }
        HealthKitRepositoryCache.shared.clearAll()

        currentActivity = nil
        currentStress = nil
        currentSleep = nil
        realtimeHealth = nil
    }

    private func sendToWatch(realtime: RealtimeHealth) {
        let payload = watchPayload(realtime: realtime)
        Self.logger.info("[WatchSync][iPhone] operation=sendSnapshot")
        WatchConnectivitySyncService.shared.syncSnapshot(payload)
    }

    private func watchPayload(realtime: RealtimeHealth?) -> [String: Any] {
        let snapshot = makeWatchSnapshot(realtime: realtime)
        return watchPayload(snapshot: snapshot)
    }

    private func watchPayload(snapshot: WatchSyncSnapshot) -> [String: Any] {
        WatchSyncEnvelope
            .snapshot(snapshot, requestId: nil)
            .toDictionary()
    }

    private func answerAIQuestionFromWatch(question: String, completion: @escaping ([String: Any]?) -> Void) {
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            completion(["type": WatchSyncMessageType.aiAnswer.rawValue, "error": "请输入想问的问题。"])
            return
        }

        let context = makeWatchAIContext()
        Task {
            do {
                let answer = try await HealthAIService().ask(
                    question: normalized,
                    scope: .today(context),
                    history: []
                )
                let payload: [String: Any] = [
                    "type": WatchSyncMessageType.aiAnswer.rawValue,
                    "question": normalized,
                    "summary": answer.summary ?? "",
                    "basis": answer.basis,
                    "actions": answer.actions,
                    "risks": answer.risks,
                    "followUps": answer.followUps,
                    "rawMarkdown": answer.rawMarkdown
                ]
                completion(payload)
            } catch {
                completion([
                    "type": WatchSyncMessageType.aiAnswer.rawValue,
                    "question": normalized,
                    "error": error.localizedDescription
                ])
            }
        }
    }

    private func makeWatchAIContext() -> HealthAIContext {
        let realtime = realtimeHealth
        let assessment = StressPresentation.assessment(from: realtime, now: Date()) ?? StressPresentationAssessment(
            score: nil,
            band: .waiting,
            title: "等待数据",
            adviceTitle: "等待健康样本",
            adviceDetail: "当前还没有足够的压力样本。",
            tint: .tertiary,
            updatedAtSeconds: nil
        )
        return HealthAIContextBuilder().makeContext(
            assessment: assessment,
            realtimeHealth: realtime,
            restingHeartRate: nil,
            avgHrvToday: realtime?.hrv,
            recentAvgHrv: nil,
            recentAvgRestingHeartRate: nil,
            sleepData: currentSleep,
            sleepInterval: nil,
            nightlyHrv: nil,
            nightlyRespiratoryRate: nil,
            sleepingWristTemperature: nil,
            sedentaryState: nil,
            sedentarySummary: nil,
            activityPoints: [],
            walkingSpeedMpsToday: currentActivity?.walking_speed_mps,
            waterMlToday: Int(AppGroupManager.shared.getWaterIntakeMl() ?? 0),
            caffeineConsumedTodayMg: nil,
            daylightMinutesToday: nil,
            healthProfileSummary: nil
        )
    }

    private func makeWatchSnapshot(realtime: RealtimeHealth?) -> WatchSyncSnapshot {
        WatchSyncSnapshotFactory(
            latestBodyAgeSummary: latestBodyAgeSummary,
            realtimeHealth: realtimeHealth,
            currentActivity: currentActivity,
            currentSleep: currentSleep,
            currentStress: currentStress
        ).makeSnapshot(realtime: realtime)
    }

    private func refreshAppGroupHealthSnapshotFromLocalCache() {
        let snapshot = makeWatchSnapshot(realtime: realtimeHealth)
        saveAppGroupHealthSnapshot(snapshot)
    }

    private func saveAppGroupHealthSnapshot(_ snapshot: WatchSyncSnapshot) {
        let sharedSnapshot = AppGroupHealthSnapshot.fromSource(
            snapshot,
            healthSummary: AppGroupManager.shared.getHealthSummary()
        )
        AppGroupSnapshotStore.save(sharedSnapshot)
        Self.logger.info("[WatchSync][iPhone] operation=saveSharedSnapshot")
    }

    private func refreshBodyAgeSummary() async {
        let summary = await Self.buildBodyAgeSummary()
        appGroup.saveBodyAgeSummary(
            valueYears: summary.valueYears,
            statusText: summary.statusText,
            comparisonText: summary.comparisonText,
            suggestionText: summary.suggestionText,
            coverageText: summary.coverageText,
            directionText: summary.directionText
        )
        latestBodyAgeSummary = summary
        bodyAgeSummary = summary
        flushLatestToWatch()
    }

    private static func buildBodyAgeSummary() async -> WatchBodyAgeSummary {
        let storedOnboardingAge = UserDefaults.standard.integer(forKey: "onboarding_age")
        let fallbackChronologicalAge = storedOnboardingAge > 0 ? storedOnboardingAge : 25
        let chronologicalAge = await HealthKitManager.shared.fetchChronologicalAge() ?? fallbackChronologicalAge

        async let sleep = HealthFactorKey.sleepDuration.loadSeries(days: 7)
        async let steps = HealthFactorKey.steps.loadSeries(days: 7)
        async let vo2 = HealthFactorKey.vo2Max.loadSeries(days: 7)
        async let rhr = HealthFactorKey.restingHeartRate.loadSeries(days: 7)

        let hrvSeries = (try? await HealthKitManager.shared.fetchDailyHRVAverages(days: 7)) ?? []
        let sleepSeries = await sleep
        let stepSeries = await steps
        let vo2Series = await vo2
        let rhrSeries = await rhr

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let sortedDates = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -(6 - offset), to: end)
        }

        let hrvByDay = valuesByDay(hrvSeries)
        let sleepByDay = valuesByDay(sleepSeries)
        let stepsByDay = valuesByDay(stepSeries)
        let vo2ByDay = valuesByDay(vo2Series)
        let rhrByDay = valuesByDay(rhrSeries)

        let ages = sortedDates.map { day in
            estimateBodyAge(
                chronologicalAge: chronologicalAge,
                hrv: hrvByDay[day],
                sleepMinutes: sleepByDay[day],
                steps: stepsByDay[day],
                vo2Max: vo2ByDay[day],
                restingHeartRate: rhrByDay[day]
            )
        }

        let rates = ages.enumerated().map { index, age in
            let previous = index > 0 ? ages[index - 1] : Double(chronologicalAge)
            let delta = age - previous
            return max(-1, min(3, 1 + delta / 2.0))
        }

        let populatedDays = sortedDates.filter { day in
            hrvByDay[day] != nil || sleepByDay[day] != nil || stepsByDay[day] != nil || vo2ByDay[day] != nil || rhrByDay[day] != nil
        }.count

        let coverageText = populatedDays == 0 ? "健康 App 暂无数据" : "\(populatedDays)/7 天有记录"

        guard populatedDays > 0, let latestAge = ages.last else {
            return WatchBodyAgeSummary(
                valueYears: nil,
                statusText: "等待数据",
                comparisonText: "补齐样本后再和实际年龄比较",
                suggestionText: "授权健康 App 并佩戴设备记录",
                coverageText: coverageText,
                directionText: "等待趋势样本",
                trendValues: ages
            )
        }

        let delta = latestAge - Double(chronologicalAge)
        let statusText: String
        if abs(delta) < 1 {
            statusText = "接近实际年龄"
        } else if delta < 0 {
            statusText = "年轻 \(Int(abs(delta).rounded())) 岁"
        } else {
            statusText = "偏高 \(Int(delta.rounded())) 岁"
        }

        let comparisonText: String
        if abs(delta) < 1 {
            comparisonText = "与实际年龄基本一致"
        } else if delta < 0 {
            comparisonText = "比实际年龄年轻 \(Int(abs(delta).rounded())) 岁"
        } else {
            comparisonText = "比实际年龄偏高 \(Int(delta.rounded())) 岁"
        }

        let latestRate = rates.last
        let suggestionText = latestRate.map { $0 <= 1 ? "恢复节奏稳定" : "优先改善睡眠和恢复" } ?? "继续累积健康数据"

        let directionText: String
        if let latestRate {
            if latestRate <= 1 {
                directionText = "恢复节奏稳定"
            } else if latestRate <= 1.5 {
                directionText = "轻微走高，适合补恢复"
            } else {
                directionText = "恢复压力偏高"
            }
        } else {
            directionText = "等待趋势样本"
        }

        return WatchBodyAgeSummary(
            valueYears: latestAge,
            statusText: statusText,
            comparisonText: comparisonText,
            suggestionText: suggestionText,
            coverageText: coverageText,
            directionText: directionText,
            trendValues: ages
        )
    }

    private static func valuesByDay(_ points: [TimeSeriesPointDouble]) -> [Date: Double] {
        let calendar = Calendar.current
        return Dictionary(uniqueKeysWithValues: points.map { (calendar.startOfDay(for: $0.date), $0.value) })
    }

    private static func estimateBodyAge(
        chronologicalAge: Int,
        hrv: Double?,
        sleepMinutes: Double?,
        steps: Double?,
        vo2Max: Double?,
        restingHeartRate: Double?
    ) -> Double {
        var adjustment = 0.0

        if let hrv, hrv > 0 {
            adjustment += hrv >= 55 ? -1.2 : (hrv < 30 ? 1.5 : 0)
        }
        if let sleepMinutes, sleepMinutes > 0 {
            adjustment += sleepMinutes >= 420 ? -0.9 : (sleepMinutes < 360 ? 1.2 : 0)
        }
        if let steps, steps > 0 {
            adjustment += steps >= 8000 ? -0.8 : (steps < 4000 ? 0.8 : 0)
        }
        if let vo2Max, vo2Max > 0 {
            adjustment += vo2Max >= 38 ? -1.0 : (vo2Max < 28 ? 1.0 : 0)
        }
        if let restingHeartRate, restingHeartRate > 0 {
            adjustment += restingHeartRate <= 62 ? -0.6 : (restingHeartRate >= 78 ? 0.9 : 0)
        }

        return max(12, Double(chronologicalAge) + adjustment)
    }

    fileprivate static func loadStoredBodyAgeSummary() -> WatchBodyAgeSummary? {
        let appGroup = AppGroupManager.shared
        let valueYears = appGroup.getBodyAgeValueYears()
        let statusText = appGroup.getBodyAgeStatusText()
        let comparisonText = appGroup.getBodyAgeComparisonText()
        let suggestionText = appGroup.getBodyAgeSuggestionText()
        let coverageText = appGroup.getBodyAgeCoverageText()
        let directionText = appGroup.getBodyAgeDirectionText()

        guard valueYears != nil
            || statusText != nil
            || comparisonText != nil
            || suggestionText != nil
            || coverageText != nil
            || directionText != nil else {
            return nil
        }

        return WatchBodyAgeSummary(
            valueYears: valueYears,
            statusText: statusText,
            comparisonText: comparisonText,
            suggestionText: suggestionText,
            coverageText: coverageText,
            directionText: directionText,
            trendValues: nil
        )
    }

    func updateDefaultComplicationTemplate(_ template: String) {
        appGroup.saveDefaultComplicationTemplate(template)
        flushLatestToWatch()
        WidgetSyncService.refresh([.complication], reason: .settings)
        WatchConnectivitySyncService.shared.syncComplicationTemplate(template)
    }

    func syncWatchThemeSelection(_ themeId: String) {
        appGroup.saveWatchThemeId(themeId)
        flushLatestToWatch()
    }

    /// 同步自定义主题使用状态：nil 表示恢复官方主题。
    func syncWatchCustomThemeSelection(_ themeId: String?) {
        appGroup.saveWatchCustomThemeId(themeId)
        flushLatestToWatch()
    }

    func syncWatchMascotConfiguration(isEnabled: Bool, message: String?) {
        appGroup.saveWatchMascotConfiguration(isEnabled: isEnabled, message: message)
        flushLatestToWatch()
    }

    private func flushLatestToWatch(preferredPayload: [String: Any]? = nil) {
        let snapshot = makeWatchSnapshot(realtime: realtimeHealth)
        saveAppGroupHealthSnapshot(snapshot)
        let payload = preferredPayload ?? watchPayload(snapshot: snapshot)
        WatchConnectivitySyncService.shared.syncSnapshot(payload, preferred: true)
    }
    
    private func saveToAppGroup(realtime: RealtimeHealth) {
        let previousStress = AppGroupManager.shared.getLatestStress() ?? Double(realtime.stress_value)
        let delta = Double(realtime.stress_value) - previousStress
        let trend: String
        if abs(delta) < 1 {
            trend = "稳定"
        } else if delta > 0 {
            trend = "上升"
        } else {
            trend = "下降"
        }
        
        appGroup.saveHeartRate(Double(realtime.bpm))
        appGroup.saveHRV(realtime.hrv)
        appGroup.saveStress(
            (realtime.stress_level != nil ? realtime.stress_value : nil).map(Double.init),
            trend: trend
        )
        Self.logger.info("[Stress][AppGroup] saved realtime snapshot")
    }

    func refreshWatchSessionState() {
        WatchConnectivitySyncService.shared.refreshSessionState()
    }

    private func applySnapshotFromWatch(_ snapshot: WatchSyncSnapshot) {
        guard snapshot.bpm > 0 || snapshot.hrv > 0 || snapshot.stress > 0 else { return }
        let incoming = RealtimeHealth(
            bpm: snapshot.bpm,
            hrv_sdnn: snapshot.hrv,
            stress_value: snapshot.stress,
            stress_level: snapshot.stressState,
            stress_explanation_code: snapshot.stressExplanationCode,
            stress_confidence: snapshot.stressConfidence,
            stress_quality: snapshot.stressQuality,
            stress_algorithm_version: snapshot.stressAlgorithmVersion,
            daily_stress_value: snapshot.dailyStress,
            daily_stress_quality: snapshot.dailyStressQuality,
            daily_stress_algorithm_version: snapshot.dailyStressAlgorithmVersion,
            timestamp: Int64(snapshot.timestamp),
            hr_abnormal: nil,
            hr_abnormal_type: nil
        )
        let realtime = Self.mergingRealtimeVitals(
            incoming,
            preservingCanonicalStressFrom: realtimeHealth
        )
        self.realtimeHealth = realtime
        saveToLocalStore()
        saveToAppGroup(realtime: realtime)
        WidgetSyncService.refresh([.overall, .stress, .vitals, .complication], reason: .healthUpdate)
        flushLatestToWatch()
    }

    private func applyRealtimeVitalsFromWatch(_ vitals: WatchRealtimeVitals) {
        var updated = false
        var newBpm = realtimeHealth?.bpm ?? 0
        var newHrv = realtimeHealth?.hrv ?? 0.0

        if let bpm = vitals.bpm {
            newBpm = bpm
            updated = true
        }
        if let hrv = vitals.hrv {
            newHrv = hrv
            updated = true
        }
        if vitals.stress != nil {
            updated = true
        }

        if updated {
            let incoming = RealtimeHealth(
                bpm: newBpm,
                hrv_sdnn: newHrv,
                stress_value: vitals.stress ?? 0,
                timestamp: vitals.timestamp.map(Int64.init) ?? Int64(Date().timeIntervalSince1970),
                hr_abnormal: nil,
                hr_abnormal_type: nil
            )
            let realtime = Self.mergingRealtimeVitals(
                incoming,
                preservingCanonicalStressFrom: realtimeHealth
            )
            self.realtimeHealth = realtime
            saveToLocalStore()
            saveToAppGroup(realtime: realtime)
            WidgetSyncService.refresh([.overall, .stress, .vitals, .complication], reason: .healthUpdate)
            flushLatestToWatch()
        }
    }

    private func handleHabitFromWatch(type: String, amount: Int, completion: (([String: Any]?) -> Void)?) {
        let resolvedType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedType.isEmpty, amount > 0 else {
            completion?([:])
            return
        }

        let store = ActionRecordStore.shared
        store.updateRecord(for: Date()) { record in
            switch resolvedType {
            case "water":
                record.waterMl += amount
                if !record.completedActions.contains(.water) {
                    record.completedActions.append(.water)
                }
            case "caffeine":
                record.caffeineMg += amount
            default:
                break
            }
        }

        let todayRecord = store.record(for: Date())
        let targetMl = AppGroupManager.shared.getWaterTargetMl() ?? 2000
        let completionRate = targetMl > 0 ? min(1.0, Double(todayRecord.waterMl) / Double(targetMl)) : 0.0

        appGroup.saveHabitSummary(
            waterIntakeMl: Double(todayRecord.waterMl),
            waterTargetMl: targetMl,
            waterCompletionRate: completionRate,
            caffeineRemainedMg: Double(todayRecord.caffeineMg)
        )
        WidgetSyncService.refresh([.overall], reason: .healthUpdate)

        Task {
            switch resolvedType {
            case "water":
                try? await HealthKitManager.shared.saveDietaryWater(milliliters: amount)
            case "caffeine":
                try? await HealthKitManager.shared.saveDietaryCaffeine(milligrams: amount)
            default:
                break
            }
        }

        let payload = self.watchPayload(realtime: self.realtimeHealth)
        self.flushLatestToWatch(preferredPayload: payload)
        completion?(payload)
    }
}
