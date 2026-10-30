/// Watch Connectivity Receiver 定义 Apple Watch 端的界面或同步逻辑，负责在手表上展示核心健康信息并与 iPhone 侧保持数据联动。
import Foundation
import Observation
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif
import WidgetKit
import OSLog

/// 手表Realtime健康结构体 作为Apple Watch 应用里的辅助类型。
/// 负责Apple Watch 端展示与同步。
struct WatchRealtimeHealth: Decodable, Equatable {
    let bpm: Int
    let hrv: Double
    let stress_value: Int
    let stressState: String?
    let stressExplanationCode: String?
    let stressConfidence: Double?
    var stressQuality: String? = nil
    var stressAlgorithmVersion: String? = nil
    var dailyStress: Int? = nil
    var dailyStressQuality: String? = nil
    var dailyStressAlgorithmVersion: String? = nil
    let stressTrend: String
    let timestamp: Int
    let steps: Int
    let activeEnergy: Int
    let exerciseMinutes: Int
    let standHours: Int
    let walkingSpeedMps: Double?
    let walkingPaceSecondsPerKm: Int?
    let stepsGoal: Int
    let activeEnergyGoal: Int
    let exerciseMinutesGoal: Int
    let standHoursGoal: Int
    let sleepDurationMinutes: Int
    let sleepScore: Int
    let lateNightRecoveryPrompt: String?
    let lateNightRecoverySeverity: String?
    let sleepEnvironmentCompletionRate: Double?
    let sleepEnvironmentPrompt: String?
    let recoveryPlan: WatchRecoveryPlanSnapshot?
    let waterIntakeMl: Int
    let waterTargetMl: Int
    let waterCompletionRate: Double
    let caffeineRemainedMg: Int
    let sedentaryElapsedMinutes: Int
    let sedentaryIsCounting: Bool
    let sedentaryPausedBySleep: Bool
    let sedentarySeatedStartAt: Int
    let sedentaryLastActivityAt: Int
    let sedentaryUpdatedAt: Int
    let sedentaryBreakIsActive: Bool
    let sedentaryBreakDurationMinutes: Int
    let sedentaryBreakStartedAt: Int
    let periodPhase: String?
    let periodCycleDay: Int?
    let periodIsFertile: Bool
    let periodNextStart: String?
    let periodFertileStart: String?
    let periodFertileEnd: String?
    let periodPredictionSource: String?
    let defaultComplicationTemplate: String?
    let watchThemeId: String?
    let bodyAgeValueYears: Double?
    let bodyAgeStatusText: String?
    let bodyAgeComparisonText: String?
    let bodyAgeSuggestionText: String?
    let bodyAgeCoverageText: String?
    let bodyAgeDirectionText: String?
    let vo2MaxValue: Double?
    let vo2MaxConfidence: Int?
    let vo2MaxTrend: String?
    let vo2MaxFitnessLevel: String?
    let vo2MaxSource: String?
    let vo2MaxDriverSummary: String?
    let stressHistory: [WatchStressHistoryPoint]
    let sleepMonitoringPhase: String?
    let sleepMonitoringActive: Bool
    let sleepSnoreIntensity: String?
    let sleepSnoreDurationMinutes: Double?
    let sleepInsightHeadline: String?
    let sleepWatchConfidence: Double?
}

struct WatchAIAnswer: Equatable {
    let question: String
    let summary: String
    let basis: [String]
    let actions: [String]
    let risks: [String]
    let followUps: [String]
    let rawMarkdown: String
}

/// 手表ConnectivityReceiver类 作为Apple Watch 应用里的能力封装类型。
/// 负责Apple Watch 端展示与同步。
@Observable
final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityReceiver()
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "WatchSync")
    private static let recoveryPlanCacheKey = "watch.recovery-plan.snapshot.v1"

    var latest: WatchRealtimeHealth?
    var isReachable = false
    var lastSyncDate: Date?
    var isSyncing = false
    var syncErrorMessage: String?
    var defaultComplicationTemplate: String = AppGroupManager.shared.getDefaultComplicationTemplate() ?? "overview"
    var watchThemeId: String = AppGroupManager.shared.getWatchThemeId() ?? "joey"
    var watchCustomThemeId: String? = AppGroupManager.shared.getWatchCustomThemeId()
    var watchMascotEnabled: Bool = AppGroupManager.shared.getWatchMascotEnabled() ?? true
    var watchMascotMessage: String? = AppGroupManager.shared.getWatchMascotMessage()
    var sleepStatusPayload: WatchSleepStatePayload = .idle
    var aiAnswer: WatchAIAnswer?
    var isAIWorking = false
    var aiErrorMessage: String?
    var hasUnreadAIAnswer = false

    @ObservationIgnored private var lastRequestAt: Date?
    @ObservationIgnored private var lastLocalHeartRatePublishedAt: Date?
    @ObservationIgnored private var lastAcceptedRemoteSnapshotTimestamp: Int?
    @ObservationIgnored private let sleepStatusViewModel = WatchSleepStatusViewModel()

    private override init() {
        super.init()
        // Watch 每次从干净会话启动，界面只展示本次新接收的数据。
        // 缓存值仍供表盘复杂功能使用，但不会恢复到 Watch App 界面。
        UserDefaults.standard.removeObject(forKey: "watch.ai.cached-answer.v1")
        UserDefaults.standard.removeObject(forKey: "watch.ai.has-unread-answer.v1")
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let error {
                Self.logger.error("[WatchSync][Watch] activation failed error=\(error.localizedDescription, privacy: .public)")
            }
            Self.logger.info("[WatchSync][Watch] activation state=\(String(describing: activationState.rawValue), privacy: .public) reachable=\(session.isReachable, privacy: .public)")
            self.isReachable = session.isReachable
            if session.receivedApplicationContext.isEmpty == false {
                self.handle(payload: session.receivedApplicationContext)
            }
            if activationState == .activated {
                self.requestLatestFromiPhone()
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            Self.logger.info("[WatchSync][Watch] reachability changed reachable=\(session.isReachable, privacy: .public)")
            self.isReachable = session.isReachable
            if session.receivedApplicationContext.isEmpty == false {
                self.handle(payload: session.receivedApplicationContext)
            }
            self.requestLatestFromiPhone()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handle(payload: applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handle(payload: userInfo)
    }

    func session(_ session: WCSession, didReceiveComplicationUserInfo complicationUserInfo: [String : Any] = [:]) {
        handle(payload: complicationUserInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handle(payload: message)
    }

    /// 接收 iPhone 传来的主题素材文件，按 metadata 落盘到主题目录。
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        guard let themeId = metadata[WatchCustomThemeFileStore.MetaKey.themeId] as? String,
              let slotRaw = metadata[WatchCustomThemeFileStore.MetaKey.slot] as? String,
              let slot = WatchThemeSlot(rawValue: slotRaw) else {
            return
        }
        let fileExtension = (metadata[WatchCustomThemeFileStore.MetaKey.fileExtension] as? String) ?? "png"
        let isAnimated = (metadata[WatchCustomThemeFileStore.MetaKey.isAnimated] as? Bool) ?? false
        let fileSize = (metadata[WatchCustomThemeFileStore.MetaKey.fileSize] as? Int) ?? 0

        DispatchQueue.main.async {
            do {
                let directory = WatchCustomThemeFileStore.themeDirectory(themeId: themeId)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = WatchCustomThemeFileStore.slotFileURL(themeId: themeId, slot: slot, fileExtension: fileExtension)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: file.fileURL, to: destination)

                var theme = WatchCustomThemeFileStore.readMeta(themeId: themeId)
                    ?? CustomWatchTheme(
                        id: themeId,
                        name: (metadata[WatchCustomThemeFileStore.MetaKey.themeName] as? String) ?? "自定义主题",
                        slots: [:]
                    )
                theme.slots[slot] = WatchThemeSlotMedia(
                    slot: slot,
                    fileExtension: fileExtension,
                    isAnimated: isAnimated,
                    fileSize: fileSize
                )
                try WatchCustomThemeFileStore.writeMeta(theme)
                Self.logger.info("[WatchSync][Watch] theme file stored theme=\(themeId, privacy: .public) slot=\(slotRaw, privacy: .public)")
            } catch {
                Self.logger.error("[WatchSync][Watch] theme file store failed error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// iPhone 端删除主题时同步清理本地素材。
    private func handleWatchThemeRemoved(_ themeId: String) {
        DispatchQueue.main.async {
            WatchCustomThemeFileStore.deleteTheme(themeId: themeId)
            if self.watchCustomThemeId == themeId {
                self.watchCustomThemeId = nil
                AppGroupManager.shared.saveWatchCustomThemeId(nil)
            }
            Self.logger.info("[WatchSync][Watch] theme removed theme=\(themeId, privacy: .public)")
        }
    }

#if !os(watchOS)
    // WCSessionDelegate 在 iOS 上额外要求这两个回调（watchOS 上不存在该要求）。
    // 仅用于 iOS 模拟器构建通过，watchOS 端不参与编译。
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // 模拟器构建产物不会真正运行；按惯例重新激活以保持会话有效。
        WCSession.default.activate()
    }
#endif

    func requestLatestFromiPhone() {
        let now = Date()
        if let lastRequestAt, now.timeIntervalSince(lastRequestAt) < 2.0 {
            return
        }
        lastRequestAt = now
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isReachable else { return }

        isSyncing = true
        syncErrorMessage = nil

        let request = WatchSyncEnvelope.requestSnapshot(requestId: UUID().uuidString).toDictionary(now: now)
        session.sendMessage(request, replyHandler: { [weak self] reply in
            self?.handle(payload: reply)
            DispatchQueue.main.async {
                self?.isSyncing = false
            }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                self?.syncErrorMessage = error.localizedDescription
            }
        })
    }

    func recordHabit(type: String, amount: Int) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isReachable else { return }
        let payload = WatchSyncEnvelope.recordHabit(type: type, amount: amount, requestId: UUID().uuidString).toDictionary()
        session.sendMessage(payload, replyHandler: { [weak self] reply in
            self?.handle(payload: reply)
        }, errorHandler: nil)
    }

    func updateComplicationTemplate(_ template: String) {
        defaultComplicationTemplate = template
        AppGroupManager.shared.saveDefaultComplicationTemplate(template)
        refreshComplicationTimeline()

        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload = WatchSyncEnvelope
            .complicationTemplate(template: template, requestId: UUID().uuidString)
            .toDictionary()
        session.sendMessage(payload, replyHandler: { [weak self] reply in
            self?.handle(payload: reply)
        }, errorHandler: nil)
    }

    func publishLocalHeartRate(_ bpm: Int) {
        guard bpm > 0 else { return }
        let now = Date()
        if let lastLocalHeartRatePublishedAt, now.timeIntervalSince(lastLocalHeartRatePublishedAt) < 1.0 {
            return
        }
        lastLocalHeartRatePublishedAt = now

        DispatchQueue.main.async {
            let base = self.latest ?? self.makeCachedSnapshot()
            let realtime = WatchRealtimeHealth(
                bpm: bpm,
                hrv: base.hrv,
                stress_value: base.stress_value,
                stressState: base.stressState,
                stressExplanationCode: base.stressExplanationCode,
                stressConfidence: base.stressConfidence,
                stressTrend: base.stressTrend,
                timestamp: Int(Date().timeIntervalSince1970),
                steps: base.steps,
                activeEnergy: base.activeEnergy,
                exerciseMinutes: base.exerciseMinutes,
                standHours: base.standHours,
                walkingSpeedMps: base.walkingSpeedMps,
                walkingPaceSecondsPerKm: base.walkingPaceSecondsPerKm,
                stepsGoal: base.stepsGoal,
                activeEnergyGoal: base.activeEnergyGoal,
                exerciseMinutesGoal: base.exerciseMinutesGoal,
                standHoursGoal: base.standHoursGoal,
                sleepDurationMinutes: base.sleepDurationMinutes,
                sleepScore: base.sleepScore,
                lateNightRecoveryPrompt: base.lateNightRecoveryPrompt,
                lateNightRecoverySeverity: base.lateNightRecoverySeverity,
                sleepEnvironmentCompletionRate: base.sleepEnvironmentCompletionRate,
                sleepEnvironmentPrompt: base.sleepEnvironmentPrompt,
                recoveryPlan: base.recoveryPlan?.isValid(at: now) == true ? base.recoveryPlan : nil,
                waterIntakeMl: base.waterIntakeMl,
                waterTargetMl: base.waterTargetMl,
                waterCompletionRate: base.waterCompletionRate,
                caffeineRemainedMg: base.caffeineRemainedMg,
                sedentaryElapsedMinutes: base.sedentaryElapsedMinutes,
                sedentaryIsCounting: base.sedentaryIsCounting,
                sedentaryPausedBySleep: base.sedentaryPausedBySleep,
                sedentarySeatedStartAt: base.sedentarySeatedStartAt,
                sedentaryLastActivityAt: base.sedentaryLastActivityAt,
                sedentaryUpdatedAt: base.sedentaryUpdatedAt,
                sedentaryBreakIsActive: base.sedentaryBreakIsActive,
                sedentaryBreakDurationMinutes: base.sedentaryBreakDurationMinutes,
                sedentaryBreakStartedAt: base.sedentaryBreakStartedAt,
                periodPhase: base.periodPhase,
                periodCycleDay: base.periodCycleDay,
                periodIsFertile: base.periodIsFertile,
                periodNextStart: base.periodNextStart,
                periodFertileStart: base.periodFertileStart,
                periodFertileEnd: base.periodFertileEnd,
                periodPredictionSource: base.periodPredictionSource,
                defaultComplicationTemplate: base.defaultComplicationTemplate,
                watchThemeId: base.watchThemeId,
                bodyAgeValueYears: base.bodyAgeValueYears,
                bodyAgeStatusText: base.bodyAgeStatusText,
                bodyAgeComparisonText: base.bodyAgeComparisonText,
                bodyAgeSuggestionText: base.bodyAgeSuggestionText,
                bodyAgeCoverageText: base.bodyAgeCoverageText,
                bodyAgeDirectionText: base.bodyAgeDirectionText,
                vo2MaxValue: base.vo2MaxValue,
                vo2MaxConfidence: base.vo2MaxConfidence,
                vo2MaxTrend: base.vo2MaxTrend,
                vo2MaxFitnessLevel: base.vo2MaxFitnessLevel,
                vo2MaxSource: base.vo2MaxSource,
                vo2MaxDriverSummary: base.vo2MaxDriverSummary,
                stressHistory: base.stressHistory,
                sleepMonitoringPhase: base.sleepMonitoringPhase,
                sleepMonitoringActive: base.sleepMonitoringActive,
                sleepSnoreIntensity: base.sleepSnoreIntensity,
                sleepSnoreDurationMinutes: base.sleepSnoreDurationMinutes,
                sleepInsightHeadline: base.sleepInsightHeadline,
                sleepWatchConfidence: base.sleepWatchConfidence
            )

            self.publishRealtime(realtime, sendToiPhone: true)
        }
    }

    private func handle(payload: [String: Any]) {
        DispatchQueue.main.async {
            let typeRaw = payload["type"] as? String
            let type = typeRaw ?? "untyped"
            let timestamp = Self.intValue(payload["timestamp"]) ?? 0
            Self.logger.info("[WatchSync][Watch] received payload type=\(type, privacy: .public) timestamp=\(timestamp, privacy: .public)")

            if typeRaw == WatchSyncMessageType.aiAnswer.rawValue {
                if let error = payload["error"] as? String, !error.isEmpty {
                    self.aiErrorMessage = error
                } else {
                    self.acceptAIAnswer(WatchAIAnswer(
                        question: payload["question"] as? String ?? "",
                        summary: payload["summary"] as? String ?? "",
                        basis: payload["basis"] as? [String] ?? [],
                        actions: payload["actions"] as? [String] ?? [],
                        risks: payload["risks"] as? [String] ?? [],
                        followUps: payload["followUps"] as? [String] ?? [],
                        rawMarkdown: payload["rawMarkdown"] as? String ?? ""
                    ))
                    self.aiErrorMessage = nil
                }
                self.isAIWorking = false
                return
            }

            if typeRaw == WatchSyncMessageType.complicationTemplate.rawValue {
                if let template = payload["defaultComplicationTemplate"] as? String, !template.isEmpty {
                    self.defaultComplicationTemplate = template
                    AppGroupManager.shared.saveDefaultComplicationTemplate(template)
                    self.refreshComplicationTimeline()
                }
                return
            }

            if typeRaw == "watch_theme_removed" {
                if let themeId = payload[WatchCustomThemeFileStore.MetaKey.themeId] as? String, !themeId.isEmpty {
                    self.handleWatchThemeRemoved(themeId)
                }
                return
            }

            // 新旧格式都先经过协议模型归一；从这里开始业务层只消费强类型快照。
            guard case .snapshot(let snapshot, _) = WatchSyncEnvelope.fromDictionary(payload) else {
                Self.logger.info("[WatchSync][Watch] ignored non-snapshot payload type=\(type, privacy: .public)")
                return
            }

            let incomingTimestamp = snapshot.timestamp
            let storedTimestamp = Int(AppGroupSnapshotStore.load()?.generatedAt.timeIntervalSince1970 ?? 0)
            let currentTimestamp = max(self.latest?.timestamp ?? 0, storedTimestamp)
            guard WatchSnapshotArbitration.shouldAcceptRemoteSnapshot(
                incomingTimestamp: incomingTimestamp,
                lastAcceptedRemoteTimestamp: self.lastAcceptedRemoteSnapshotTimestamp
            ) else {
                Self.logger.info("[WatchSync][Watch] ignored stale remote snapshot incoming=\(incomingTimestamp, privacy: .public) lastRemote=\(self.lastAcceptedRemoteSnapshotTimestamp ?? 0, privacy: .public)")
                return
            }
            self.lastAcceptedRemoteSnapshotTimestamp = incomingTimestamp

            let resolvedTimestamp = WatchSnapshotArbitration.resolvedTimestamp(
                incomingTimestamp: incomingTimestamp,
                currentTimestamp: currentTimestamp
            )
            let preserveLocalHeartRate = WatchSnapshotArbitration.shouldPreserveLocalHeartRate(
                localPublishedAt: self.lastLocalHeartRatePublishedAt,
                incomingTimestamp: incomingTimestamp
            )

            let resolvedRecoveryPlan = snapshot.recoveryPlan?.isValid(at: Date()) == true ? snapshot.recoveryPlan : nil

            let resolvedWalkingSpeed = snapshot.walkingSpeedMps ?? AppGroupManager.shared.getWalkingSpeedMps()
            let resolvedWalkingPace = snapshot.walkingPaceSecondsPerKm ?? AppGroupManager.shared.getWalkingPaceSecondsPerKm()
            let resolvedVO2Value = snapshot.vo2MaxValue ?? AppGroupManager.shared.getVO2MaxValue()
            let resolvedVO2Confidence = snapshot.vo2MaxConfidence ?? AppGroupManager.shared.getVO2MaxConfidence()
            let resolvedVO2Trend = snapshot.vo2MaxTrend ?? AppGroupManager.shared.getVO2MaxTrend()
            let resolvedVO2FitnessLevel = snapshot.vo2MaxFitnessLevel ?? AppGroupManager.shared.getVO2MaxFitnessLevel()
            let resolvedVO2Source = snapshot.vo2MaxSource ?? AppGroupManager.shared.getVO2MaxSource()
            let resolvedVO2DriverSummary = snapshot.vo2MaxDriverSummary ?? AppGroupManager.shared.getVO2MaxDriverSummary()

            let realtime = WatchRealtimeHealth(
                bpm: preserveLocalHeartRate
                    ? (self.latest?.bpm ?? snapshot.bpm)
                    : snapshot.bpm,
                hrv: snapshot.hrv,
                stress_value: snapshot.stress,
                stressState: snapshot.stressState,
                stressExplanationCode: snapshot.stressExplanationCode,
                stressConfidence: snapshot.stressConfidence,
                stressTrend: snapshot.stressTrend,
                timestamp: resolvedTimestamp,
                steps: snapshot.steps,
                activeEnergy: snapshot.activeEnergy,
                exerciseMinutes: snapshot.exerciseMinutes,
                standHours: snapshot.standHours,
                walkingSpeedMps: resolvedWalkingSpeed,
                walkingPaceSecondsPerKm: resolvedWalkingPace,
                stepsGoal: snapshot.stepsGoal,
                activeEnergyGoal: snapshot.activeEnergyGoal,
                exerciseMinutesGoal: snapshot.exerciseMinutesGoal,
                standHoursGoal: snapshot.standHoursGoal,
                sleepDurationMinutes: snapshot.sleepDurationMinutes,
                sleepScore: snapshot.sleepScore,
                lateNightRecoveryPrompt: snapshot.lateNightRecoveryPrompt,
                lateNightRecoverySeverity: snapshot.lateNightRecoverySeverity,
                sleepEnvironmentCompletionRate: snapshot.sleepEnvironmentCompletionRate,
                sleepEnvironmentPrompt: snapshot.sleepEnvironmentPrompt,
                recoveryPlan: resolvedRecoveryPlan,
                waterIntakeMl: snapshot.waterIntakeMl,
                waterTargetMl: snapshot.waterTargetMl,
                waterCompletionRate: snapshot.waterCompletionRate,
                caffeineRemainedMg: snapshot.caffeineRemainedMg,
                sedentaryElapsedMinutes: snapshot.sedentaryElapsedMinutes,
                sedentaryIsCounting: snapshot.sedentaryIsCounting,
                sedentaryPausedBySleep: snapshot.sedentaryPausedBySleep,
                sedentarySeatedStartAt: snapshot.sedentarySeatedStartAtSeconds ?? 0,
                sedentaryLastActivityAt: snapshot.sedentaryLastActivityAtSeconds ?? 0,
                sedentaryUpdatedAt: snapshot.sedentaryUpdatedAtSeconds ?? Int(Date().timeIntervalSince1970),
                sedentaryBreakIsActive: snapshot.sedentaryBreakIsActive,
                sedentaryBreakDurationMinutes: snapshot.sedentaryBreakDurationMinutes,
                sedentaryBreakStartedAt: snapshot.sedentaryBreakStartedAtSeconds ?? 0,
                periodPhase: snapshot.periodPhase,
                periodCycleDay: snapshot.periodCycleDay,
                periodIsFertile: snapshot.periodIsFertile ?? false,
                periodNextStart: snapshot.periodNextStart,
                periodFertileStart: snapshot.periodFertileStart,
                periodFertileEnd: snapshot.periodFertileEnd,
                periodPredictionSource: snapshot.periodPredictionSource,
                defaultComplicationTemplate: snapshot.defaultComplicationTemplate,
                watchThemeId: snapshot.watchThemeId,
                bodyAgeValueYears: snapshot.bodyAgeValueYears,
                bodyAgeStatusText: snapshot.bodyAgeStatusText,
                bodyAgeComparisonText: snapshot.bodyAgeComparisonText,
                bodyAgeSuggestionText: snapshot.bodyAgeSuggestionText,
                bodyAgeCoverageText: snapshot.bodyAgeCoverageText,
                bodyAgeDirectionText: snapshot.bodyAgeDirectionText,
                vo2MaxValue: resolvedVO2Value,
                vo2MaxConfidence: resolvedVO2Confidence,
                vo2MaxTrend: resolvedVO2Trend,
                vo2MaxFitnessLevel: resolvedVO2FitnessLevel,
                vo2MaxSource: resolvedVO2Source,
                vo2MaxDriverSummary: resolvedVO2DriverSummary,
                stressHistory: snapshot.stressHistory,
                sleepMonitoringPhase: snapshot.sleepMonitoringPhase,
                sleepMonitoringActive: snapshot.sleepMonitoringActive,
                sleepSnoreIntensity: snapshot.sleepSnoreIntensity,
                sleepSnoreDurationMinutes: snapshot.sleepSnoreDurationMinutes,
                sleepInsightHeadline: snapshot.sleepInsightHeadline,
                sleepWatchConfidence: snapshot.sleepWatchConfidence
            )
            self.latest = realtime
            self.lastSyncDate = Date(timeIntervalSince1970: TimeInterval(realtime.timestamp))
            // 只要拿到一份有效快照，就清掉上一次同步失败提示。
            self.syncErrorMessage = nil
            if let template = realtime.defaultComplicationTemplate, !template.isEmpty {
                self.defaultComplicationTemplate = template
            }
            if let watchThemeId = realtime.watchThemeId, !watchThemeId.isEmpty {
                self.watchThemeId = watchThemeId
            }
            if let customThemeId = snapshot.watchCustomThemeId, !customThemeId.isEmpty {
                // 素材可能尚未传完；渲染层对缺失槽位有回退，这里直接应用标记。
                self.watchCustomThemeId = customThemeId
            } else if snapshot.watchCustomThemeId != nil {
                self.watchCustomThemeId = nil
            }
            if let watchMascotEnabled = snapshot.watchMascotEnabled {
                self.watchMascotEnabled = watchMascotEnabled
            }
            self.watchMascotMessage = WatchMascotMessageUpdatePolicy.resolve(
                current: self.watchMascotMessage,
                incoming: snapshot.watchMascotMessage,
                isConfigured: snapshot.watchMascotMessageConfigured
            )
            AppGroupManager.shared.saveWatchMascotConfiguration(
                isEnabled: self.watchMascotEnabled,
                message: self.watchMascotMessage
            )
            let phase = SleepMonitoringPhase(rawValue: realtime.sleepMonitoringPhase ?? "") ?? .idle
            let payload = WatchSleepStatePayload(
                phase: phase,
                watchConnected: self.isReachable,
                watchConfidence: realtime.sleepWatchConfidence ?? 0,
                probableSleepStartAt: nil,
                lastUpdatedAt: Date(timeIntervalSince1970: TimeInterval(realtime.timestamp)),
                summary: self.makeSummary(from: realtime)
            )
            self.sleepStatusPayload = payload
            self.sleepStatusViewModel.apply(payload)
            self.publishRealtime(realtime)
        }
    }

    func syncNow() {
        guard isReachable else {
            syncErrorMessage = String(localized: "iPhone 暂时不可连接")
            return
        }
        requestLatestFromiPhone()
    }

    func askAI(_ question: String) {
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            acceptAIAnswer(WatchLocalAIResponder.answer(question: normalized, snapshot: latest))
            aiErrorMessage = nil
            return
        }
        guard session.isReachable else {
            acceptAIAnswer(WatchLocalAIResponder.answer(question: normalized, snapshot: latest))
            aiErrorMessage = nil
            return
        }

        aiErrorMessage = nil
        isAIWorking = true
        let payload = WatchSyncEnvelope
            .aiQuestion(question: normalized, requestId: UUID().uuidString)
            .toDictionary()
        session.sendMessage(payload, replyHandler: { [weak self] reply in
            self?.handle(payload: reply)
            DispatchQueue.main.async { self?.isAIWorking = false }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.isAIWorking = false
                self?.aiErrorMessage = error.localizedDescription
            }
        })
    }

    func markAIAnswerRead() {
        guard hasUnreadAIAnswer else { return }
        hasUnreadAIAnswer = false
    }

    private func acceptAIAnswer(_ answer: WatchAIAnswer) {
        aiAnswer = answer
        hasUnreadAIAnswer = true
        #if os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
    }

    private func publishRealtime(_ realtime: WatchRealtimeHealth, sendToiPhone: Bool = false) {
        latest = realtime
        lastSyncDate = Date(timeIntervalSince1970: TimeInterval(realtime.timestamp))
        syncErrorMessage = nil
        saveToAppGroup(realtime: realtime)
        saveRecoveryPlanCache(realtime.recoveryPlan)
        saveAppGroupHealthSnapshot(realtime: realtime)
        refreshComplicationTimeline()
        Self.logger.info("[WatchSync][Watch] published realtime timestamp=\(realtime.timestamp, privacy: .public) sharedState=\(AppGroupSnapshotStore.debugState(), privacy: .public)")
        if sendToiPhone {
            sendRealtimeToiPhone(realtime)
        }
    }

    /// 心率样本产生于 Watch；当 iPhone 暂时不可达时先进入队列，
    /// 避免后台传输机会丢失。
    private func sendRealtimeToiPhone(_ realtime: WatchRealtimeHealth) {
        let payload: [String: Any] = [
            "schemaVersion": WatchSyncEnvelope.schemaVersion,
            "type": WatchSyncMessageType.snapshot.rawValue,
            "sentAt": Int(Date().timeIntervalSince1970),
            "timestamp": realtime.timestamp,
            "bpm": realtime.bpm,
            "hrv": realtime.hrv,
            "stress": realtime.stress_value,
            "stressTrend": realtime.stressTrend
        ]
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                Self.logger.error("[WatchSync][Watch] realtime send failed error=\(error.localizedDescription, privacy: .public)")
                Self.queueRealtimeForiPhone(payload, session: session)
            }
        } else {
            Self.queueRealtimeForiPhone(payload, session: session)
        }
    }

    private static func queueRealtimeForiPhone(_ payload: [String: Any], session: WCSession) {
        do {
            try session.updateApplicationContext(payload)
        } catch {
            // 上下文传输短暂失败时保留队列兜底。
            session.transferUserInfo(payload)
        }
    }

    private func makeCachedSnapshot() -> WatchRealtimeHealth {
        WatchRealtimeHealth(
            bpm: Int(AppGroupManager.shared.getLatestHeartRate() ?? 0),
            hrv: AppGroupManager.shared.getLatestHRV() ?? 0,
            stress_value: Int(AppGroupManager.shared.getLatestStress() ?? 0),
            stressState: nil,
            stressExplanationCode: nil,
            stressConfidence: nil,
            stressTrend: AppGroupManager.shared.getStressTrend() ?? String(localized: "稳定"),
            timestamp: Int(AppGroupManager.shared.getLastSyncTime()?.timeIntervalSince1970 ?? Date().timeIntervalSince1970),
            steps: AppGroupManager.shared.getSteps() ?? 0,
            activeEnergy: AppGroupManager.shared.getActiveEnergy() ?? 0,
            exerciseMinutes: AppGroupManager.shared.getExerciseMinutes() ?? 0,
            standHours: AppGroupManager.shared.getStandHours() ?? 0,
            walkingSpeedMps: AppGroupManager.shared.getWalkingSpeedMps(),
            walkingPaceSecondsPerKm: AppGroupManager.shared.getWalkingPaceSecondsPerKm(),
            stepsGoal: AppGroupManager.shared.getStepsGoal() ?? 8000,
            activeEnergyGoal: AppGroupManager.shared.getActiveEnergyGoal() ?? 500,
            exerciseMinutesGoal: AppGroupManager.shared.getExerciseMinutesGoal() ?? 30,
            standHoursGoal: AppGroupManager.shared.getStandHoursGoal() ?? 12,
            sleepDurationMinutes: AppGroupManager.shared.getSleepDurationMinutes() ?? 0,
            sleepScore: AppGroupManager.shared.getSleepScore() ?? 0,
            lateNightRecoveryPrompt: AppGroupManager.shared.getLateNightRecoveryPrompt(),
            lateNightRecoverySeverity: AppGroupManager.shared.getLateNightRecoverySeverity(),
            sleepEnvironmentCompletionRate: AppGroupManager.shared.getSleepEnvironmentCompletionRate(),
            sleepEnvironmentPrompt: AppGroupManager.shared.getSleepEnvironmentPrompt(),
            recoveryPlan: loadCachedRecoveryPlan(),
            waterIntakeMl: Int(AppGroupManager.shared.getWaterIntakeMl() ?? 0),
            waterTargetMl: AppGroupManager.shared.getWaterTargetMl() ?? 2000,
            waterCompletionRate: AppGroupManager.shared.getWaterCompletionRate() ?? 0,
            caffeineRemainedMg: Int(AppGroupManager.shared.getCaffeineRemainedMg() ?? 0),
            sedentaryElapsedMinutes: AppGroupManager.shared.getSedentaryElapsedMinutes() ?? 0,
            sedentaryIsCounting: AppGroupManager.shared.getSedentaryIsCounting() ?? false,
            sedentaryPausedBySleep: AppGroupManager.shared.getValue(forKey: AppGroupManager.Keys.sedentaryPausedBySleep) ?? false,
            sedentarySeatedStartAt: Int(AppGroupManager.shared.getSedentarySeatedStartAt()?.timeIntervalSince1970 ?? 0),
            sedentaryLastActivityAt: Int(AppGroupManager.shared.getSedentaryLastActivityAt()?.timeIntervalSince1970 ?? 0),
            sedentaryUpdatedAt: Int(AppGroupManager.shared.getSedentaryUpdatedAt()?.timeIntervalSince1970 ?? 0),
            sedentaryBreakIsActive: AppGroupManager.shared.getSedentaryBreakIsActive() ?? false,
            sedentaryBreakDurationMinutes: AppGroupManager.shared.getSedentaryBreakDurationMinutes() ?? 0,
            sedentaryBreakStartedAt: Int(AppGroupManager.shared.getSedentaryBreakStartedAt()?.timeIntervalSince1970 ?? 0),
            periodPhase: AppGroupManager.shared.getPeriodPhase(),
            periodCycleDay: AppGroupManager.shared.getPeriodCycleDay(),
            periodIsFertile: AppGroupManager.shared.getPeriodIsFertile() ?? false,
            periodNextStart: AppGroupManager.shared.getPeriodNextStart(),
            periodFertileStart: AppGroupManager.shared.getPeriodFertileStart(),
            periodFertileEnd: AppGroupManager.shared.getPeriodFertileEnd(),
            periodPredictionSource: AppGroupManager.shared.getPeriodPredictionSource(),
            defaultComplicationTemplate: AppGroupManager.shared.getDefaultComplicationTemplate(),
            watchThemeId: AppGroupManager.shared.getWatchThemeId(),
            bodyAgeValueYears: AppGroupManager.shared.getBodyAgeValueYears(),
            bodyAgeStatusText: AppGroupManager.shared.getBodyAgeStatusText(),
            bodyAgeComparisonText: AppGroupManager.shared.getBodyAgeComparisonText(),
            bodyAgeSuggestionText: AppGroupManager.shared.getBodyAgeSuggestionText(),
            bodyAgeCoverageText: AppGroupManager.shared.getBodyAgeCoverageText(),
            bodyAgeDirectionText: AppGroupManager.shared.getBodyAgeDirectionText(),
            vo2MaxValue: AppGroupManager.shared.getVO2MaxValue(),
            vo2MaxConfidence: AppGroupManager.shared.getVO2MaxConfidence(),
            vo2MaxTrend: AppGroupManager.shared.getVO2MaxTrend(),
            vo2MaxFitnessLevel: AppGroupManager.shared.getVO2MaxFitnessLevel(),
            vo2MaxSource: AppGroupManager.shared.getVO2MaxSource(),
            vo2MaxDriverSummary: AppGroupManager.shared.getVO2MaxDriverSummary(),
            stressHistory: AppGroupManager.shared.getStressHistory(),
            sleepMonitoringPhase: AppGroupManager.shared.getSleepMonitoringState()?.phase.rawValue,
            sleepMonitoringActive: AppGroupManager.shared.getSleepMonitoringState()?.phase == .monitoring,
            sleepSnoreIntensity: AppGroupManager.shared.getSleepSnoreIntensity(),
            sleepSnoreDurationMinutes: AppGroupManager.shared.getSleepSnoreDurationMinutes(),
            sleepInsightHeadline: AppGroupManager.shared.getSleepInsightHeadline(),
            sleepWatchConfidence: AppGroupManager.shared.getSleepWatchConfidence()
        )
    }

    private func saveRecoveryPlanCache(_ recoveryPlan: WatchRecoveryPlanSnapshot?) {
        guard let recoveryPlan, recoveryPlan.isValid(at: Date()),
              let data = try? JSONEncoder().encode(recoveryPlan) else {
            UserDefaults.standard.removeObject(forKey: Self.recoveryPlanCacheKey)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.recoveryPlanCacheKey)
    }

    private func loadCachedRecoveryPlan() -> WatchRecoveryPlanSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: Self.recoveryPlanCacheKey),
              let recoveryPlan = try? JSONDecoder().decode(WatchRecoveryPlanSnapshot.self, from: data),
              recoveryPlan.isValid(at: Date()) else {
            UserDefaults.standard.removeObject(forKey: Self.recoveryPlanCacheKey)
            return nil
        }
        return recoveryPlan
    }

    private func saveToAppGroup(realtime: WatchRealtimeHealth) {
        AppGroupManager.shared.saveHeartRate(Double(realtime.bpm))
        AppGroupManager.shared.saveHRV(realtime.hrv)
        AppGroupManager.shared.saveStress(Double(realtime.stress_value), trend: realtime.stressTrend)
        AppGroupManager.shared.saveStressHistory(realtime.stressHistory)
        AppGroupManager.shared.saveHabitSummary(
            waterIntakeMl: Double(realtime.waterIntakeMl),
            waterTargetMl: realtime.waterTargetMl,
            waterCompletionRate: realtime.waterCompletionRate,
            caffeineRemainedMg: Double(realtime.caffeineRemainedMg)
        )
        AppGroupManager.shared.saveActivitySummary(
            steps: realtime.steps,
            activeEnergy: realtime.activeEnergy,
            exerciseMinutes: realtime.exerciseMinutes,
            standHours: realtime.standHours,
            stepsGoal: realtime.stepsGoal,
            activeEnergyGoal: realtime.activeEnergyGoal,
            exerciseMinutesGoal: realtime.exerciseMinutesGoal,
            standHoursGoal: realtime.standHoursGoal
        )
        AppGroupManager.shared.saveWalkingMobilitySummary(
            speedMps: realtime.walkingSpeedMps,
            paceSecondsPerKm: realtime.walkingPaceSecondsPerKm
        )
        AppGroupManager.shared.saveSleepSummary(durationMinutes: realtime.sleepDurationMinutes, score: realtime.sleepScore)
        AppGroupManager.shared.saveSleepGuidance(
            lateNightRecoveryPrompt: realtime.lateNightRecoveryPrompt,
            lateNightRecoverySeverity: realtime.lateNightRecoverySeverity,
            environmentCompletionRate: realtime.sleepEnvironmentCompletionRate,
            environmentPrompt: realtime.sleepEnvironmentPrompt
        )
        let phase = SleepMonitoringPhase(rawValue: realtime.sleepMonitoringPhase ?? "") ?? .idle
        AppGroupManager.shared.saveSleepMonitoringState(
            SleepMonitoringState(
                phase: phase,
                activationSource: .watchSignal,
                startedAt: nil,
                updatedAt: Date(timeIntervalSince1970: TimeInterval(realtime.timestamp)),
                watchConnected: true,
                watchConfidence: realtime.sleepWatchConfidence ?? 0,
                isAudioMonitoringActive: realtime.sleepMonitoringActive,
                lastErrorDescription: nil
            )
        )
        if let summary = makeSummary(from: realtime) {
            AppGroupManager.shared.saveSleepLatestSummary(summary)
        }
        AppGroupManager.shared.saveSedentaryState(
            elapsedMinutes: realtime.sedentaryElapsedMinutes,
            isCounting: realtime.sedentaryIsCounting,
            pausedBySleep: realtime.sedentaryPausedBySleep,
            seatedStartAt: realtime.sedentarySeatedStartAt > 0 ? Date(timeIntervalSince1970: TimeInterval(realtime.sedentarySeatedStartAt)) : nil,
            lastActivityAt: realtime.sedentaryLastActivityAt > 0 ? Date(timeIntervalSince1970: TimeInterval(realtime.sedentaryLastActivityAt)) : nil,
            updatedAt: realtime.sedentaryUpdatedAt > 0 ? Date(timeIntervalSince1970: TimeInterval(realtime.sedentaryUpdatedAt)) : nil
        )
        AppGroupManager.shared.saveSedentaryBreakState(
            isActive: realtime.sedentaryBreakIsActive,
            durationMinutes: realtime.sedentaryBreakDurationMinutes > 0 ? realtime.sedentaryBreakDurationMinutes : nil,
            startedAt: realtime.sedentaryBreakStartedAt > 0 ? Date(timeIntervalSince1970: TimeInterval(realtime.sedentaryBreakStartedAt)) : nil
        )
        AppGroupManager.shared.savePeriodSummary(
            phase: realtime.periodPhase,
            cycleDay: realtime.periodCycleDay,
            isFertile: realtime.periodIsFertile,
            nextPeriodStart: realtime.periodNextStart,
            fertileStart: realtime.periodFertileStart,
            fertileEnd: realtime.periodFertileEnd,
            predictionSource: realtime.periodPredictionSource
        )
        if let template = realtime.defaultComplicationTemplate, !template.isEmpty {
            AppGroupManager.shared.saveDefaultComplicationTemplate(template)
            defaultComplicationTemplate = template
        }
        if let watchThemeId = realtime.watchThemeId, !watchThemeId.isEmpty {
            AppGroupManager.shared.saveWatchThemeId(watchThemeId)
            self.watchThemeId = watchThemeId
        }
        AppGroupManager.shared.saveWatchCustomThemeId(self.watchCustomThemeId)
        AppGroupManager.shared.saveBodyAgeSummary(
            valueYears: realtime.bodyAgeValueYears,
            statusText: realtime.bodyAgeStatusText,
            comparisonText: realtime.bodyAgeComparisonText,
            suggestionText: realtime.bodyAgeSuggestionText,
            coverageText: realtime.bodyAgeCoverageText,
            directionText: realtime.bodyAgeDirectionText
        )
        AppGroupManager.shared.saveLastSyncTime(
            Date(timeIntervalSince1970: TimeInterval(realtime.timestamp))
        )
    }

    private func makeSummary(from realtime: WatchRealtimeHealth) -> SleepSessionSummary? {
        guard realtime.sleepDurationMinutes > 0 || realtime.sleepInsightHeadline != nil || realtime.sleepSnoreDurationMinutes != nil else {
            return nil
        }
        let end = Date(timeIntervalSince1970: TimeInterval(max(realtime.timestamp, 1)))
        let start = Calendar.current.date(byAdding: .minute, value: -max(realtime.sleepDurationMinutes, 1), to: end) ?? end
        let intensity = SleepSnoreIntensity(rawValue: realtime.sleepSnoreIntensity ?? "none") ?? .none
        return SleepSessionSummary(
            sessionId: "watch-\(realtime.timestamp)",
            sourceDate: Calendar.current.startOfDay(for: end),
            startTime: start,
            endTime: end,
            sleepDurationMinutes: realtime.sleepDurationMinutes,
            sleepScore: realtime.sleepScore,
            sleepContinuityScore: max(0, min(100, realtime.sleepScore - 6)),
            stageSummary: .empty,
            snoreSummary: SnoreAnalysisSummary(
                snoreDetected: (realtime.sleepSnoreDurationMinutes ?? 0) > 0,
                snoreDurationMinutes: realtime.sleepSnoreDurationMinutes ?? 0,
                snoreFrequencyPerHour: 0,
                intensity: intensity,
                disturbanceScore: max(0, min(100, Int(((realtime.sleepSnoreDurationMinutes ?? 0) * 3).rounded()))),
                riskFlag: intensity == .high ? .elevated : .none,
                segments: [],
                histogram: Array(repeating: 0, count: 6)
            ),
            insight: SleepInsightSnapshot(
                headline: realtime.sleepInsightHeadline ?? String(localized: "昨夜睡眠已同步"),
                summary: realtime.sleepInsightHeadline ?? String(localized: "昨夜睡眠已同步"),
                recommendationCode: "watch_realtime",
                recommendationText: String(localized: "打开 iPhone 睡眠页查看完整分析。"),
                riskFlag: intensity == .high ? .elevated : .none,
                generatedAt: end,
                modelVersion: "watch-realtime-v1"
            ),
            watchConfidence: realtime.sleepWatchConfidence ?? 0,
            deviceSource: "watch",
            analysisVersion: "watch-realtime-v1",
            createdAt: end,
            updatedAt: end,
            source: .watchSignal
        )
    }

    private func refreshComplicationTimeline() {
        Self.logger.info("[WatchSync][Watch] request complication reload")
        for kind in AppGroupSchema.Kind.allComplicationKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        if #available(watchOS 26.0, *) {
            WidgetCenter.shared.invalidateRelevance(ofKind: AppGroupSchema.Kind.complicationRelevance)
        }
    }

    private func saveAppGroupHealthSnapshot(realtime: WatchRealtimeHealth) {
        let snapshot = AppGroupHealthSnapshot.fromSource(
            realtime,
            healthSummary: AppGroupManager.shared.getHealthSummary()
        )
        AppGroupSnapshotStore.save(snapshot)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

private enum WatchLocalAIResponder {
    static func answer(question: String, snapshot: WatchRealtimeHealth?) -> WatchAIAnswer {
        let lowercased = question.lowercased()
        let summary: String
        let basis: [String]
        let actions: [String]

        if lowercased.contains("睡") || lowercased.contains("sleep") {
            if let snapshot, snapshot.sleepDurationMinutes > 0 {
                summary = String(localized: "昨夜已有睡眠摘要，今天先按恢复状态调整节奏，不必急着补做高强度训练。")
                basis = [
                    String(localized: "睡眠时长：\(snapshot.sleepDurationMinutes) 分钟。"),
                    snapshot.sleepScore > 0 ? String(localized: "睡眠评分：\(snapshot.sleepScore) 分。") : String(localized: "睡眠评分暂未同步。")
                ]
                actions = [String(localized: "先补水并完成轻量活动。"), String(localized: "今晚保持固定的入睡时间。")]
            } else {
                summary = String(localized: "当前没有足够的睡眠摘要，先完成同步或在 iPhone 端查看昨夜详情。")
                basis = [String(localized: "Watch 尚未拿到有效睡眠样本。")]
                actions = [String(localized: "打开 iPhone 端完成同步。"), String(localized: "暂时按体感安排轻量活动。")]
            }
        } else if lowercased.contains("压力") || lowercased.contains("stress") {
            let score = snapshot?.stress_value ?? 0
            summary = score > 0 ? String(localized: "当前压力信号为 \(score) 分，先降低节奏并观察身体反馈。") : String(localized: "当前没有足够的压力样本。")
            basis = score > 0 ? [String(localized: "最近同步压力评分：\(score)/100。")] : [String(localized: "Watch 尚未拿到有效压力样本。")]
            actions = [String(localized: "做 2 到 3 分钟缓慢呼吸。"), String(localized: "暂缓连续高强度任务。")]
        } else {
            let hrv = snapshot?.hrv ?? 0
            summary = hrv > 0 ? String(localized: "目前更适合按恢复信号安排今天的节奏，避免只看单个指标做决定。") : String(localized: "当前只有有限的本地摘要，建议先完成 iPhone 同步。")
            basis = hrv > 0 ? [String(localized: "最近同步 HRV：\(Int(hrv.rounded())) ms。")] : [String(localized: "Watch 暂无足够的 HRV 或睡眠样本。")]
            actions = [String(localized: "先完成补水和轻量活动。"), String(localized: "如有明显不适，以体感和专业意见为准。")]
        }

        return WatchAIAnswer(
            question: question,
            summary: summary,
            basis: basis,
            actions: actions,
            risks: [String(localized: "这是离线本机摘要，不构成医疗诊断或治疗建议。")],
            followUps: [String(localized: "打开 iPhone 后继续追问。"), String(localized: "补充今天的体感后再判断。")],
            rawMarkdown: summary
        )
    }
}

extension WatchRealtimeHealth: HealthSnapshotSource {
    var stress: Int { stress_value }
}
