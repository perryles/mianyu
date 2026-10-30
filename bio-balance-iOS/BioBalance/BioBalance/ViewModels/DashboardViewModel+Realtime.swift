import Foundation
import SwiftUI
import HealthKit
import WidgetKit
import OSLog


/// DashboardViewModel 实时链路：实时数据接收 / 压力评估 / 本地评估刷新 / 通知调度。
/// 从原 DashboardViewModel.swift 拆出，对外接口不变。

@MainActor
extension DashboardViewModel {

    static func estimateStress(hrv: Double, heartRate: Double, restingHeartRate: Double?) -> Int {
        StressDailyEngine.instantaneousStress(
            hrv: hrv,
            heartRate: heartRate,
            restingHeartRate: restingHeartRate
        )
    }

    static func averagePositive(_ values: [Double]) -> Double? {
        let valid = values.filter { $0 > 0 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    func refreshOtherMetrics() async {
        let calendar = Calendar.current
        let referenceDate = calendar.startOfDay(for: selectedDate)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
        let isViewingToday = calendar.isDate(referenceDate, inSameDayAs: now())
        let rangeEnd = min(
            calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate,
            now()
        )

        async let averageHrvToday = try? HealthKitManager.shared.fetchAverageHRV(on: referenceDate)
        // 聚合查询的 endDate 是时间上界。传当天 00:00 会把当天已有样本排除，
        // 造成单日当前值有数据、趋势和“最近更新”仍显示等待同步的不一致。
        async let dailyHrv = try? HealthKitManager.shared.fetchDailyHRVAverages(days: 7, endDate: rangeEnd)
        async let restingToday = try? HealthKitManager.shared.fetchRestingHeartRate(on: referenceDate)
        async let restingYesterday = try? HealthKitManager.shared.fetchRestingHeartRate(on: yesterday)
        async let dailyResting = try? HealthKitManager.shared.fetchDailyRestingHeartRateAverages(days: 7, endDate: rangeEnd)
        async let daylightToday = try? HealthKitManager.shared.fetchTimeInDaylightMinutes(on: referenceDate)
        async let daylightYesterday = try? HealthKitManager.shared.fetchTimeInDaylightMinutes(on: yesterday)
        async let dailyDaylight = try? HealthKitManager.shared.fetchTimeInDaylightSeries(
            start: calendar.date(byAdding: .day, value: -6, to: referenceDate) ?? referenceDate,
            end: rangeEnd,
            interval: DateComponents(day: 1)
        )
        async let wristLatest = try? HealthKitManager.shared.fetchLatestSleepingWristTemperature()
        async let dailyWrist = try? HealthKitManager.shared.fetchDailySleepingWristTemperatureAverages(days: 7, endDate: rangeEnd)
        async let asymmetryToday = try? HealthKitManager.shared.fetchWalkingAsymmetryPercentage(on: referenceDate)
        async let asymmetryYesterday = try? HealthKitManager.shared.fetchWalkingAsymmetryPercentage(on: yesterday)
        async let dailyAsymmetry = try? HealthKitManager.shared.fetchDailyWalkingAsymmetryAverages(days: 7, endDate: rangeEnd)
        async let latestAsymmetry = try? HealthKitManager.shared.fetchLatestWalkingAsymmetryPercentage()
        async let heartRhythmSignals = HealthKitManager.shared.fetchHeartRhythmSignals(referenceDate: rangeEnd)

        let hrvTrend = sanitizeTrend((await dailyHrv) ?? [])
        let hrvCurrent = positiveValue(await averageHrvToday) ?? hrvTrend.last?.value
        let hrvPrevious = previousValue(in: hrvTrend, relativeTo: referenceDate)

        let restingTrend = sanitizeTrend((await dailyResting) ?? [])
        let restingCurrent = positiveValue(await restingToday) ?? restingTrend.last?.value
        let restingPrevious = positiveValue(await restingYesterday) ?? previousValue(in: restingTrend, relativeTo: referenceDate)

        let daylightTrend = sanitizeTrend((await dailyDaylight) ?? [])
        let daylightCurrent = (await daylightToday).map { Double(max(0, $0)) } ?? daylightTrend.last?.value
        let daylightPrevious = (await daylightYesterday).map { Double(max(0, $0)) } ?? previousValue(in: daylightTrend, relativeTo: referenceDate)

        let wristTrend = sanitizeTrend((await dailyWrist) ?? [])
        let wristCurrent = (isViewingToday ? positiveValue(await wristLatest) : nil) ?? wristTrend.last?.value
        let wristPrevious = previousValue(in: wristTrend, relativeTo: referenceDate)

        let asymmetryTrend = sanitizeTrend((await dailyAsymmetry) ?? [])
        let latestAsymmetryValue = isViewingToday ? positiveValue(await latestAsymmetry) : nil
        let asymmetryCurrent = positiveValue(await asymmetryToday) ?? latestAsymmetryValue
        let asymmetryPrevious = positiveValue(await asymmetryYesterday) ?? previousValue(in: asymmetryTrend, relativeTo: referenceDate)

        let rhythmResult = HeartRhythmStabilityHealthKitAdapter.evaluate(
            signals: await heartRhythmSignals,
            referenceDate: rangeEnd
        )

        let cards = [
            makeHRVCard(current: hrvCurrent, previous: hrvPrevious, trend: hrvTrend),
            makeRestingHeartRateCard(current: restingCurrent, previous: restingPrevious, trend: restingTrend),
            makeWristTemperatureCard(current: wristCurrent, previous: wristPrevious, trend: wristTrend),
            makeSunlightCard(current: daylightCurrent, previous: daylightPrevious, trend: daylightTrend),
            makeWalkingAsymmetryCard(current: asymmetryCurrent, previous: asymmetryPrevious, trend: asymmetryTrend),
            makeHeartRhythmCard(result: rhythmResult)
        ]

        guard calendar.isDate(selectedDate, inSameDayAs: referenceDate) else { return }
        heartRhythmResult = rhythmResult
        otherMetrics = cards
    }

    func refreshLocalAssessment(for loadDate: Date? = nil) async {
        let referenceDate = Calendar.current.startOfDay(for: loadDate ?? selectedDate)
        do {
            let isViewingToday = Calendar.current.isDate(referenceDate, inSameDayAs: now())
            let queryEnd = min(
                Calendar.current.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate,
                now()
            )
            let realHrv = isViewingToday ? try await HealthKitManager.shared.fetchLatestHRV() : 0
            let resting = try? await HealthKitManager.shared.fetchRestingHeartRate(on: referenceDate)
            let avgHrv = try? await HealthKitManager.shared.fetchAverageHRV(on: referenceDate)
            let recentHrvPoints = (try? await HealthKitManager.shared.fetchDailyHRVAverages(days: 14, endDate: queryEnd)) ?? []
            let recentRestingPoints = (try? await HealthKitManager.shared.fetchDailyRestingHeartRateAverages(days: 14, endDate: queryEnd)) ?? []
            let vo2Assessments = await resolvedVO2Assessments(days: 30, endDate: queryEnd)

            restingHeartRate = resting.flatMap { $0 > 0 ? $0 : nil }
            if let avgHrv, avgHrv > 0 {
                avgHrvToday = avgHrv
            } else if realHrv > 0 {
                avgHrvToday = realHrv
            } else {
                avgHrvToday = nil
            }
            recentAvgHrv = HealthBaselineStrategy.usableValue(for: recentHrvPoints.map(\.value), metric: .hrvSDNN)
            recentAvgRestingHeartRate = HealthBaselineStrategy.usableValue(for: recentRestingPoints.map(\.value), metric: .restingHeartRate)
            applyVO2Assessments(vo2Assessments, on: referenceDate)

            refreshStressEvaluations(referenceDate: referenceDate, isViewingToday: isViewingToday)
        } catch {
            vo2MaxAssessment = nil
            vo2MaxHistory = []
            vo2Max = nil
            recentAvgVo2Max = nil
            vo2MaxIsEstimated = false
            refreshStressEvaluations(
                referenceDate: referenceDate,
                isViewingToday: Calendar.current.isDate(referenceDate, inSameDayAs: now())
            )
        }
    }

    func refreshAssessmentFromCurrentState() {
        refreshStressEvaluations(referenceDate: selectedDate, isViewingToday: isViewingToday)
    }

    func refreshStressEvaluations(referenceDate: Date, isViewingToday: Bool) {
        guard isViewingToday else {
            currentStressEvaluation = .unavailable(.noPhysiologicalSignal)
            dailyStressEvaluation = .unavailable(.noDailySamples)
            currentStressAssessment = StressPresentation.assessment(from: currentStressEvaluation)
            dailyStressAssessment = StressPresentation.assessment(from: dailyStressEvaluation)
            logStressResolution(operation: "assessmentRefreshHistorical")
            return
        }

        let current = StressPresentation.evaluation(
            from: realtimeHealth ?? HealthDataManager.shared.realtimeHealth
        )
        let cached = try? stressStore.load()
        let calendar = Calendar.current
        var samples = (cached?.dailySamples ?? []).filter { calendar.isDate($0.date, inSameDayAs: referenceDate) }
        if let result = current.result,
           result.algorithmVersion == StressResult.currentAlgorithmVersion,
           result.quality != .unavailable {
            samples.append(StressDailySample(
                timestamp: result.timestamp,
                score: result.score,
                confidence: result.confidence,
                quality: result.quality,
                algorithmVersion: result.algorithmVersion,
                source: .realtime,
                dominantDriver: result.dominantDriver
            ))
        }
        samples = Dictionary(grouping: samples, by: \.timestamp)
            .compactMap { _, duplicates in duplicates.max(by: { $0.confidence < $1.confidence }) }
            .sorted { $0.timestamp < $1.timestamp }
        let daily = StressDailyEngine.evaluate(input: StressDailyInput(now: referenceDate, samples: samples))
        currentStressEvaluation = current
        dailyStressEvaluation = daily
        currentStressAssessment = StressPresentation.assessment(from: current)
        dailyStressAssessment = StressPresentation.assessment(from: daily)
        persistStressSyncMetadata(current: current, daily: daily)
        stressStore.save(StressSnapshot(
            schemaVersion: StressSnapshot.schemaVersion,
            current: current,
            daily: daily,
            dailySamples: samples,
            savedAt: now()
        ))
        logStressResolution(operation: "assessmentRefresh")
    }

    func logStressResolution(operation: String) {
        let currentReason = currentStressAssessment.unavailableReason?.rawValue ?? "none"
        let dailyReason = dailyStressAssessment.unavailableReason?.rawValue ?? "none"
        let calendar = Calendar.current
        let referenceDate = selectedDate
        let todayHistoryCount = (history?.stressPoints ?? []).lazy.filter {
            $0.value > 0 && calendar.isDate($0.date, inSameDayAs: referenceDate)
        }.count
        let source = cardStressSource
        let logKey = [
            source,
            currentReason,
            dailyReason,
            String(currentStressAssessment.hasData),
            String(dailyStressAssessment.hasData),
            String(todaySevenMinuteStressPoints.count),
            String(todayHistoryCount)
        ].joined(separator: "|")
        guard logKey != lastStressResolutionLogKey || operation == "loadComplete" else { return }
        lastStressResolutionLogKey = logKey
        let cardAvailable = cardStressAssessment.hasData
        let currentAvailable = currentStressAssessment.hasData
        let dailyAvailable = dailyStressAssessment.hasData
        let sevenMinuteCount = todaySevenMinuteStressPoints.count

        Self.signalsLogger.info(
            "[Today][Signals] operation=\(operation, privacy: .public) cardSource=\(source, privacy: .public) cardAvailable=\(cardAvailable, privacy: .public) currentAvailable=\(currentAvailable, privacy: .public) currentReason=\(currentReason, privacy: .public) dailyAvailable=\(dailyAvailable, privacy: .public) dailyReason=\(dailyReason, privacy: .public) sevenMinuteCount=\(sevenMinuteCount, privacy: .public) todayHistoryCount=\(todayHistoryCount, privacy: .public)"
        )
    }

    func persistStressSyncMetadata(current: StressEvaluation, daily: StressEvaluation) {
        let currentResult = current.result
        let dailyResult = daily.result
        let appGroup = AppGroupManager.shared
        appGroup.set(value: currentResult?.quality.rawValue, forKey: AppGroupSchema.Keys.stressQuality)
        appGroup.set(value: currentResult?.algorithmVersion, forKey: AppGroupSchema.Keys.stressAlgorithmVersion)
        appGroup.set(value: dailyResult?.score, forKey: AppGroupSchema.Keys.dailyStress)
        appGroup.set(value: dailyResult?.quality.rawValue, forKey: AppGroupSchema.Keys.dailyStressQuality)
        appGroup.set(value: dailyResult?.algorithmVersion, forKey: AppGroupSchema.Keys.dailyStressAlgorithmVersion)
    }

    func handleRealtimeUpdate(
        _ value: RealtimeHealth,
        syncToHealthDataManager: Bool = true
    ) {
        guard isViewingToday else { return }
        realtimeHealth = value
        handleRealtimeAlertIfNeeded(value)
        refreshAssessmentFromCurrentState()
        persistForWidgets(value, syncToHealthDataManager: syncToHealthDataManager)
    }

    func makeHistoricalRealtime(from hrvToday: [TimeSeriesPointDouble], heartRate: [TimeSeriesPoint]) -> RealtimeHealth? {
        let latestHrv = hrvToday.last?.value ?? 0
        let latestHeartRate = Double(heartRate.last?.value ?? 0)
        guard latestHrv > 0 || latestHeartRate > 0 else { return nil }
        let stress = Self.estimateStress(
            hrv: latestHrv,
            heartRate: latestHeartRate,
            restingHeartRate: restingHeartRate
        )
        return RealtimeHealth(
            bpm: Int(latestHeartRate.rounded()),
            hrv_sdnn: latestHrv,
            stress_value: stress,
            timestamp: hrvToday.last?.timestamp ?? Int64(selectedDate.timeIntervalSince1970)
        )
    }

    func mergeHealthKitTodayHistory(hrvToday: [TimeSeriesPointDouble], heartRateToday: [TimeSeriesPoint]) {
        let hrvHistory = hrvToday.map {
            HrvHistoryPoint(sdnn: $0.value, timestamp: $0.timestamp)
        }

        let dayStart = Calendar.current.startOfDay(for: selectedDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(24 * 60 * 60)
        let sevenMinuteStressPoints = StressDailyEngine.sevenMinuteStressPoints(
            hrv: hrvToday,
            heartRate: heartRateToday,
            restingHeartRate: restingHeartRate,
            restingHeartRateBaseline: recentAvgRestingHeartRate,
            hrvBaseline: recentAvgHrv,
            in: DateInterval(start: dayStart, end: dayEnd)
        )
        todaySevenMinuteStressPoints = sevenMinuteStressPoints
        let stressHistory = sevenMinuteStressPoints.map { point in
            return StressHistoryPoint(
                stressLevel: point.value,
                analysis: "健康 App",
                timestamp: point.timestamp
            )
        }

        let bpmHistory = heartRateToday.map {
            BpmHistoryPoint(heartRate: $0.value, timestamp: $0.timestamp)
        }

        guard !hrvHistory.isEmpty || !stressHistory.isEmpty || !bpmHistory.isEmpty else { return }

        let current = history ?? HealthHistory()
        history = HealthHistory(
            bpmHistory: bpmHistory.isEmpty ? current.bpmHistory : bpmHistory,
            stressHistory: stressHistory.isEmpty ? current.stressHistory : stressHistory,
            hrvHistory: hrvHistory.isEmpty ? current.hrvHistory : hrvHistory,
            emotionHistory: current.emotionHistory
        )
        if isViewingToday {
            persistStressHistoryForWatch()
        }
    }

    func handleRealtimeAlertIfNeeded(_ data: RealtimeHealth) {
        let now = Date()
        if let lastAlertAt, now.timeIntervalSince(lastAlertAt) < 60 {
            return
        }

        if data.bpm > 120 {
            scheduleNotification(title: String(localized: "❤️ 心跳有点小跑"), body: String(localized: "心率冲到 \(data.bpm) BPM 了，先停一停，深呼吸让它慢下来。"))
            lastAlertAt = now
            return
        }
        if data.bpm > 0 && data.bpm < 50 {
            scheduleNotification(title: String(localized: "💙 心跳有点安静"), body: String(localized: "心率只有 \(data.bpm) BPM，如果觉得不舒服，别硬扛，及时就医。"))
            lastAlertAt = now
            return
        }
        let currentStress = realtimeHealth?.stress_value ?? data.stress_value
        if currentStress > 80 {
            scheduleNotification(title: String(localized: "🌊 压力有点上头"), body: String(localized: "压力值冲到 \(currentStress)/100 了，来组深呼吸，把它按回去～"))
            lastAlertAt = now
            return
        }
    }

    func scheduleNotification(title: String, body: String) {
        LocalNotificationScheduler.scheduleAfter(
            identifier: "health.alert.\(UUID().uuidString)",
            seconds: 1,
            title: title,
            body: body,
            bypassesQuietHours: true
        )
    }

    func syncSedentaryReminder() {
        cancelSedentaryReminders()
        guard sedentaryReminderEnabled,
              !sedentaryBreakProgress.isActive,
              sedentaryState.isCounting,
              sedentaryReminderIntervalMinutes > 0 else {
            return
        }

        let nextMinute = DashboardSedentaryState.nextReminderMinute(
            elapsedMinutes: sedentaryState.elapsedMinutes,
            intervalMinutes: sedentaryReminderIntervalMinutes
        )

        let remainingSeconds = TimeInterval(max(1, nextMinute - sedentaryState.elapsedMinutes) * 60)
        let identifier = "\(sedentaryNotificationPrefix)\(nextMinute)"
        LocalNotificationScheduler.scheduleAfter(
            identifier: identifier,
            seconds: remainingSeconds,
            title: String(localized: "🪑 椅子说它累了"),
            body: String(localized: "你已经稳坐 \(nextMinute) 分钟啦，起来晃两分钟，让腿也刷刷存在感。")
        )
    }

    func cancelSedentaryReminders() {
        let identifiers = (DashboardSedentaryState.reminderMinutes + [15, 30, 45, 60, 90, 120, 180, 240])
            .map { "\(sedentaryNotificationPrefix)\($0)" }
        LocalNotificationScheduler.cancel(identifiers: identifiers)
    }

    func clearSedentaryBreakState(
        preserveCompletionFeedback: Bool,
        completedMinutes: Int? = nil,
        completedAt: Date? = nil
    ) {
        HealthDataManager.shared.pushSedentaryBreakToWatch(
            isActive: false,
            durationMinutes: nil,
            startedAt: nil
        )

        if preserveCompletionFeedback {
            sedentaryBreakProgress = .completed(
                minutes: max(1, completedMinutes ?? sedentaryBreakProgress.elapsedMinutes(now: completedAt ?? now())),
                completedAt: completedAt ?? now()
            )
        } else {
            sedentaryBreakProgress = .idle
        }
    }

}
