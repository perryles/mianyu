import CloudKit
import Foundation

/// Social分享数据模型 作为视图模型层里的数据载体。
/// 负责界面状态管理与业务编排。
struct SocialShareSnapshot: Sendable {
    let title: String
    let subtitle: String
    let shareSummary: String
    let stressTitle: String
    let stressValueText: String
    let hrvValueText: String
    let bpmValueText: String
    let sleepValueText: String
    let moodTitle: String
    let moodIntensityText: String
    let trendSummary: String
    let adviceText: String
    let lastUpdatedText: String
    let shareText: String
    let assessment: StressPresentationAssessment
}

/// Social视图模型 作为视图模型层里的界面状态管理入口。
/// 负责界面状态管理与业务编排。
@MainActor
@Observable
final class SocialViewModel {
    private(set) var snapshot: SocialShareSnapshot
    private(set) var sharingState: SocialSharingState
    var activeShareSheet: CloudKitShareInvitePayload?
    private(set) var isAuthorizingInvite = false
    private(set) var inviteAuthorizationMessage: String?

    private var shouldLaunchInviteAfterDismiss = false
    private var realtimeHealth: RealtimeHealth?
    private var history: HealthHistory?
    private var sleepData: SleepData?
    private var emotionRecords: [EmotionRecord] = []
    private let sharingStore: SharedHealthDataStore
    private let actionStore: ActionRecordStore
    private let countdownStore: CountdownStore
    private var observationTask: Task<Void, Never>?

    init(
        sharingStore: SharedHealthDataStore? = nil,
        actionStore: ActionRecordStore? = nil,
        countdownStore: CountdownStore? = nil
    ) {
        let resolvedSharingStore = sharingStore ?? .shared
        let resolvedActionStore = actionStore ?? .shared
        let resolvedCountdownStore = countdownStore ?? .shared

        self.sharingStore = resolvedSharingStore
        self.actionStore = resolvedActionStore
        self.countdownStore = resolvedCountdownStore
        let initialAssessment = StressPresentation.unavailableAssessment(reason: .noDailySamples)
        self.snapshot = Self.makeSnapshot(
            realtimeHealth: nil,
            history: nil,
            sleepData: nil,
            emotionRecords: [],
            assessment: initialAssessment,
            actionStore: resolvedActionStore,
            countdownStore: resolvedCountdownStore
        )
        self.sharingState = resolvedSharingStore.state
        startObservation()
    }

    private func startObservation() {
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                // VM 释放后（weak self 为空）立即退出循环，避免 1 秒轮询成为僵尸任务。
                guard let self else { return }
                // 从存储同步共享状态
                let currentState = self.sharingStore.state
                if currentState != self.sharingState {
                    self.sharingState = currentState
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func loadData() {
        print("[SocialSharing] SocialViewModel loadData")
        Task {
            await sharingStore.bootstrap()
        }
        loadLocalSocialData()
    }

    func refreshSharing() {
        Task {
            await sharingStore.refresh()
        }
    }

    func lookupFriend(handle: String) async throws -> PublicUserProfile {
        try await sharingStore.lookupPublicProfile(handle: handle)
    }

    func beginInviteFlow() {
        print("[社交共享] 视图模型开始邀请流程")
        inviteAuthorizationMessage = nil
        sharingStore.beginInviteFlow()
        shouldLaunchInviteAfterDismiss = false
    }

    func cancelInviteFlow() {
        print("[社交共享] 视图模型取消邀请流程")
        shouldLaunchInviteAfterDismiss = false
        inviteAuthorizationMessage = nil
        sharingStore.cancelInviteFlow()
    }

    func confirmInviteFlow() {
        print("[社交共享] 视图模型确认继续邀请")
        guard !isAuthorizingInvite else { return }
        inviteAuthorizationMessage = nil

        let currentState = sharingStore.state
        if SocialInvitePolicy.requiresHealthAuthorization(currentState.myStatus.permissionState) {
            isAuthorizingInvite = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.sharingStore.requestAuthorization()
                self.isAuthorizingInvite = false

                guard self.sharingStore.state.inviteFlowState == .confirming else { return }
                guard SocialInvitePolicy.canPrepareInvite(
                    permissionState: self.sharingStore.state.myStatus.permissionState,
                    hasSnapshot: self.sharingStore.state.myStatus.snapshot != nil,
                    isICloudAvailable: self.sharingStore.state.isICloudAvailable
                ) else {
                    self.inviteAuthorizationMessage = "还没有可共享的健康摘要。请允许至少一项健康数据权限，并确认已登录 iCloud。"
                    return
                }
                self.completeInviteConfirmation()
            }
            return
        }

        guard SocialInvitePolicy.canPrepareInvite(
            permissionState: currentState.myStatus.permissionState,
            hasSnapshot: currentState.myStatus.snapshot != nil,
            isICloudAvailable: currentState.isICloudAvailable
        ) else {
            inviteAuthorizationMessage = "好友邀请需要可用的 iCloud 账号和至少一项健康摘要。"
            return
        }
        completeInviteConfirmation()
    }

    private func completeInviteConfirmation() {
        shouldLaunchInviteAfterDismiss = true
        sharingStore.cancelInviteFlow()
    }

    func introInviteSheetWillDismiss() {
        print("[社交共享] 介绍弹窗即将关闭 shouldLaunchInviteAfterDismiss=\(shouldLaunchInviteAfterDismiss)")
        if !shouldLaunchInviteAfterDismiss {
            cancelInviteFlow()
        }
    }

    func introInviteSheetDidDismiss() {
        print("[社交共享] 介绍弹窗已关闭 shouldLaunchInviteAfterDismiss=\(shouldLaunchInviteAfterDismiss)")
        let shouldLaunch = shouldLaunchInviteAfterDismiss
        shouldLaunchInviteAfterDismiss = false
        sharingStore.cancelInviteFlow()
        if shouldLaunch {
            print("[社交共享] 准备启动系统分享面板")
            launchInviteFlow()
        }
    }

    private func launchInviteFlow() {
        print("[社交共享] 开始生成分享 payload")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let payload = try await self.sharingStore.prepareInvitePayload()
                print("[SocialSharing] SocialViewModel presenting CloudKitSharingSheet share=\(payload.share.recordID.recordName)")
                self.activeShareSheet = payload
                self.sharingStore.markInviteSheetPresented()
            } catch {
                print("[社交共享] 生成分享 payload 失败 mappedError=\(self.sharingStore.currentErrorMessage(for: error))")
                var nextState = self.sharingState
                nextState.errorMessage = self.sharingStore.currentErrorMessage(for: error)
                self.sharingState = nextState
            }
        }
    }

    func inviteConfigurationSheetDismissed(willPresentShareComposer: Bool) {
        print("[社交共享] 系统共享配置面板已关闭 pendingDelivery=\(willPresentShareComposer)")
        activeShareSheet = nil
        guard !willPresentShareComposer else { return }
        guard sharingStore.state.inviteFlowState != .failed else { return }
        Task {
            await sharingStore.markInviteSheetDismissed()
        }
    }

    func inviteShareDidPrepare() {
        print("[社交共享] 邀请链接已准备，等待选择发送方式")
        sharingStore.markInviteReadyToSend()
    }

    func inviteDeliveryDidFinish(completed: Bool, error: Error?) {
        if let error {
            inviteShareDidFail(error)
        } else if completed {
            print("[社交共享] 邀请已通过系统分享发送")
            sharingStore.markInviteSent()
            refreshSharing()
        } else {
            print("[社交共享] 用户取消发送邀请")
            sharingStore.markInviteDeliveryCancelled()
        }
    }

    func inviteShareDidFail(_ error: Error) {
        print("[社交共享] 分享发送失败 mappedError=\(sharingStore.currentErrorMessage(for: error))")
        sharingStore.markInviteFailed(error)
    }

    func inviteShareDidStopSharing() {
        print("[社交共享] 用户在系统面板里停止了共享")
        sharingStore.markInviteStopped()
        refreshSharing()
    }

    func clearSharingError() {
        var nextState = sharingState
        nextState.errorMessage = nil
        sharingState = nextState
    }

    func consumePostAcceptNavigationTarget() -> FriendHealthProfile? {
        sharingStore.consumePostAcceptNavigationTarget()
    }

    func removeFriend(_ friend: FriendHealthProfile) {
        Task {
            await sharingStore.removeFriend(friend)
        }
    }

    func removeOutgoingShare(_ profile: OutgoingShareProfile) {
        Task {
            await sharingStore.removeOutgoingShare(profile)
        }
    }

    func stopSharing() {
        Task {
            await sharingStore.stopSharing()
        }
    }

    private func refreshSnapshot() {
        let assessment = Self.resolveAssessment(realtimeHealth: realtimeHealth, history: history)
        snapshot = Self.makeSnapshot(
            realtimeHealth: realtimeHealth,
            history: history,
            sleepData: sleepData,
            emotionRecords: emotionRecords,
            assessment: assessment,
            actionStore: actionStore,
            countdownStore: countdownStore
        )
    }

    private func loadLocalSocialData() {
        let manager = HealthDataManager.shared
        manager.loadFromLocalStore()
        let shared = AppGroupManager.shared

        let resolvedRealtime: RealtimeHealth? = {
            if let realtime = manager.realtimeHealth,
               realtime.bpm > 0 || realtime.hrv_sdnn > 0 || realtime.stress_value > 0 {
                return realtime
            }

            let bpm = Int((shared.getLatestHeartRate() ?? 0).rounded())
            let hrv = shared.getLatestHRV() ?? 0
            let stress = Int((shared.getLatestStress() ?? 0).rounded())

            guard bpm > 0 || hrv > 0 || stress > 0 else { return nil }

            return RealtimeHealth(
                bpm: bpm,
                hrv_sdnn: hrv,
                stress_value: stress,
                stress_level: nil,
                timestamp: Int64(Date().timeIntervalSince1970)
            )
        }()

        let resolvedSleep: SleepData? = {
            if let sleep = manager.currentSleep,
               sleep.duration_minutes > 0 || sleep.sleep_score > 0 {
                return sleep
            }

            let duration = shared.getSleepDurationMinutes() ?? 0
            let score = shared.getSleepScore() ?? 0
            guard duration > 0 || score > 0 else { return nil }

            return SleepData(
                sleep_score: score,
                duration_minutes: duration,
                stages: [],
                avg_heart_rate: nil,
                avg_respiration_rate: nil,
                awake_count: nil,
                start_time: nil,
                end_time: nil
            )
        }()

        realtimeHealth = resolvedRealtime
        sleepData = resolvedSleep
        history = Self.makeLocalHistory(realtime: resolvedRealtime)
        refreshSnapshot()

        Task { @MainActor [weak self] in
            guard let self else { return }
            let stateOfMind = try? await HealthKitManager.shared.fetchLatestStateOfMind()
            self.emotionRecords = stateOfMind.map {
                [
                    EmotionRecord(
                        emotion: Self.emotionCode(for: $0.title),
                        intensity: $0.intensity,
                        source: "HEALTHKIT",
                        timestamp: Int($0.date.timeIntervalSince1970)
                    )
                ]
            } ?? []
            self.refreshSnapshot()
        }
    }

    private static func resolveAssessment(realtimeHealth: RealtimeHealth?, history: HealthHistory?) -> StressPresentationAssessment {
        let historyStressValues = history?.stressHistory.map(\.stressLevel) ?? []
        if let current = StressPresentation.assessment(from: realtimeHealth, now: Date()) {
            return current
        }
        guard !historyStressValues.isEmpty else {
            return StressPresentation.unavailableAssessment(reason: .noDailySamples)
        }
        let average = Double(historyStressValues.reduce(0, +)) / Double(historyStressValues.count)
        return StressPresentation.assessmentFromScore(Int(average.rounded()), now: Date(), updatedAtSeconds: nil)
    }

    private static func makeSnapshot(
        realtimeHealth: RealtimeHealth?,
        history: HealthHistory?,
        sleepData: SleepData?,
        emotionRecords: [EmotionRecord],
        assessment: StressPresentationAssessment,
        actionStore: ActionRecordStore,
        countdownStore: CountdownStore
    ) -> SocialShareSnapshot {
        let latestEmotion = emotionRecords.sorted { ($0.timestamp ?? 0) > ($1.timestamp ?? 0) }.first
        let moodTitle = latestEmotion.map { emotionTitle(for: $0.emotion) } ?? "等待记录"
        let moodIntensityText = latestEmotion.map { "强度 \($0.intensity)" } ?? "还没有记录"

        let sleepValueText: String
        if let sleepData, sleepData.duration_minutes > 0 {
            let hours = Double(sleepData.duration_minutes) / 60.0
            if sleepData.sleep_score > 0 {
                sleepValueText = String(format: String(localized: "%.1f h · %d 分"), hours, sleepData.sleep_score)
            } else {
                sleepValueText = String(format: "%.1f h", hours)
            }
        } else {
            sleepValueText = "等待同步"
        }

        let hrvValueText = metricValue(realtimeHealth?.hrv_sdnn, unit: "ms", digits: 0, placeholder: "等待同步")
        let bpmValueText = realtimeHealth.map { "\($0.bpm) bpm" } ?? "等待同步"
        let stressValueText = assessment.hasData ? "分数 \(assessment.valueText)" : "等待同步"

        let trendSummary = makeTrendSummary(history: history)
        let lastUpdatedText = makeLastUpdatedText(
            realtimeTimestamp: realtimeHealth?.timestamp,
            emotionTimestamp: latestEmotion?.timestamp
        )

        let shareSummary = [
            "状态 \(assessment.title)",
            "HRV \(hrvValueText)",
            "心情 \(moodTitle)",
            "睡眠 \(sleepValueText)",
            "行动 \(actionStore.recentSharedRecords().count) 条",
            "倒数日 \(countdownStore.recentSharedItems().count) 个"
        ].joined(separator: " · ")

        let shareText = makeShareText(
            assessment: assessment,
            shareSummary: shareSummary,
            stressValueText: stressValueText,
            hrvValueText: hrvValueText,
            bpmValueText: bpmValueText,
            sleepValueText: sleepValueText,
            moodTitle: moodTitle,
            moodIntensityText: moodIntensityText,
            trendSummary: trendSummary,
            sharedActionCount: actionStore.recentSharedRecords().count,
            sharedCountdownCount: countdownStore.recentSharedItems().count
        )

        return SocialShareSnapshot(
            title: assessment.title,
            subtitle: assessment.adviceTitle,
            shareSummary: shareSummary,
            stressTitle: "身体压力",
            stressValueText: stressValueText,
            hrvValueText: hrvValueText,
            bpmValueText: bpmValueText,
            sleepValueText: sleepValueText,
            moodTitle: moodTitle,
            moodIntensityText: moodIntensityText,
            trendSummary: trendSummary,
            adviceText: assessment.adviceDetail,
            lastUpdatedText: lastUpdatedText,
            shareText: shareText,
            assessment: assessment
        )
    }

    private static func metricValue(_ value: Double?, unit: String, digits: Int, placeholder: String) -> String {
        guard let value, value > 0 else { return placeholder }
        return String(format: "%.\(digits)f %@", value, unit)
    }

    private static func makeTrendSummary(history: HealthHistory?) -> String {
        guard let history else { return "近几天的状态趋势会在同步后逐步变清楚。" }

        let hrvValues = history.hrvHistory.compactMap(\.sdnn).filter { $0 > 0 }
        let stressValues = history.stressHistory.map(\.stressLevel).filter { $0 > 0 }

        if let firstStress = stressValues.first, let lastStress = stressValues.last, stressValues.count >= 2 {
            let delta = lastStress - firstStress
            if abs(delta) >= 6 {
                return delta > 0 ? "最近压力有抬头迹象，今天更适合主动降负荷。" : "最近压力在回落，恢复节奏开始回来。"
            }
        }

        if let firstHrv = hrvValues.first, let lastHrv = hrvValues.last, hrvValues.count >= 2 {
            let delta = lastHrv - firstHrv
            if abs(delta) >= 5 {
                return delta > 0 ? "HRV 比前几天更好一些，今天的恢复手感可能更轻松。" : "HRV 比前几天偏低一点，今天先别把节奏拉得太满。"
            }
        }

        return String(localized: "这几天整体比较平稳，继续观察睡眠和心情有没有一起变好。")
    }

    private static func makeLastUpdatedText(realtimeTimestamp: Int64?, emotionTimestamp: Int?) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.unitsStyle = .short

        if let realtimeTimestamp {
            return String(localized: "实时状态 \(formatter.localizedString(for: Date(timeIntervalSince1970: TimeInterval(realtimeTimestamp)), relativeTo: Date()))")
        }

        if let emotionTimestamp {
            return String(localized: "心情记录 \(formatter.localizedString(for: Date(timeIntervalSince1970: TimeInterval(emotionTimestamp)), relativeTo: Date()))")
        }

        return String(localized: "等待新的同步")
    }

    private static func makeShareText(
        assessment: StressPresentationAssessment,
        shareSummary: String,
        stressValueText: String,
        hrvValueText: String,
        bpmValueText: String,
        sleepValueText: String,
        moodTitle: String,
        moodIntensityText: String,
        trendSummary: String,
        sharedActionCount: Int,
        sharedCountdownCount: Int
    ) -> String {
        [
            "眠屿 好友状态",
            shareSummary,
            "压力 \(stressValueText)",
            "HRV \(hrvValueText)",
            "心率 \(bpmValueText)",
            "睡眠 \(sleepValueText)",
            "心情 \(moodTitle) · \(moodIntensityText)",
            "建议：\(assessment.adviceTitle)",
            "趋势：\(trendSummary)",
            sharedActionCount == 0 ? nil : "行动共享：最近 \(sharedActionCount) 条",
            sharedCountdownCount == 0 ? nil : "倒数日共享：最近 \(sharedCountdownCount) 个"
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private static func emotionTitle(for emotion: String) -> String {
        switch emotion {
        case "happy": return "开心"
        case "neutral": return "平静"
        case "tired": return "疲惫"
        case "anxious": return "焦虑"
        case "sad": return "低落"
        default: return "有感觉"
        }
    }
    
    private static func makeLocalHistory(realtime: RealtimeHealth?) -> HealthHistory {
        let stressHistory = AppGroupManager.shared.getStressHistory().map {
            StressHistoryPoint(stressLevel: $0.value, analysis: nil, timestamp: Int64($0.timestamp))
        }

        let hrvHistory: [HrvHistoryPoint]
        if let realtime, realtime.hrv_sdnn > 0 {
            hrvHistory = [HrvHistoryPoint(sdnn: realtime.hrv_sdnn, timestamp: realtime.timestamp)]
        } else if let hrv = AppGroupManager.shared.getLatestHRV(), hrv > 0 {
            hrvHistory = [HrvHistoryPoint(sdnn: hrv, timestamp: Int64(Date().timeIntervalSince1970))]
        } else {
            hrvHistory = []
        }

        let bpmHistory: [BpmHistoryPoint]
        if let realtime, realtime.bpm > 0 {
            bpmHistory = [BpmHistoryPoint(heartRate: realtime.bpm, timestamp: realtime.timestamp)]
        } else if let bpm = AppGroupManager.shared.getLatestHeartRate(), bpm > 0 {
            bpmHistory = [BpmHistoryPoint(heartRate: Int(bpm.rounded()), timestamp: Int64(Date().timeIntervalSince1970))]
        } else {
            bpmHistory = []
        }

        return HealthHistory(
            bpmHistory: bpmHistory,
            stressHistory: stressHistory,
            hrvHistory: hrvHistory,
            emotionHistory: []
        )
    }

    private static func emotionCode(for title: String) -> String {
        switch title {
        case let title where title.contains("开心"):
            return "happy"
        case let title where title.contains("焦虑"):
            return "anxious"
        case let title where title.contains("疲惫"):
            return "tired"
        case let title where title.contains("低落"):
            return "sad"
        case let title where title.contains("平静"):
            return "neutral"
        default:
            return "neutral"
        }
    }
}
