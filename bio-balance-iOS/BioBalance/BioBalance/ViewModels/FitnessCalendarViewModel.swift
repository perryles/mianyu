import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class FitnessCalendarViewModel {
    var selectedDate: Date
    var calendarScope: HabitCalendarScope
    var calendarModel: HabitFitnessCalendarModel
    var statsCards: [HabitFitnessStatsCardModel]
    var achievementCard: FitnessAchievementCardModel
    var selectedDayContext: FitnessSelectedDayContextModel
    var badges: [FitnessBadgeModel]
    var overviewModel: FitnessOverviewModel
    var workoutReviewModel: FitnessWorkoutReviewModel
    var recoveryManagementModel: FitnessRecoveryManagementModel
    var loadRecoveryLinkModel: FitnessLoadRecoveryLinkModel
    var performanceTrackModel: FitnessPerformanceTrackModel
    var performanceReviewModel: FitnessPerformanceReviewModel
    var nextStepModel: FitnessNextStepModel
    var checkinOpeningModel: FitnessCheckinOpeningModel
    var sharedHighlights: [FitnessSharedHighlightItem]
    var trainingLogs: [FitnessTrainingLogItem]
    var selectedDetail: ActionDayDetailModel?
    var cycleTrainingRhythmPlan: CycleTrainingRhythmPlan?
    var activeRecoveryChallenge: RecoveryChallengeRecord?
    var challengeHistoryPreview: [RecoveryChallengeHistoryPreviewItem]
    var challengeTodayProgress: RecoveryChallengeDayProgress?
    var challengeSelectionCards: [RecoveryChallengeSelectionCardModel]
    var showingChallengeCelebration = false
    var challengeCelebrationTitle = ""
    var challengeCelebrationSubtitle = ""
    var isLoading = false
    var syncMessage: String?
    var liveWorkoutState: FitnessLiveWorkoutState = .idle
    var fitnessInsightContext: FitnessAIInsightContext = .placeholder
    var fitnessInsight: FitnessAIInsightModel = FitnessAIInsightEngine().makeInsight(from: .placeholder)

    let healthKitManager: HealthKitManager
    let store: FitnessCalendarStore
    private let recoveryChallengeStore: RecoveryChallengeStore
    let calendar: Calendar
    let cycleRhythmEngine = CycleStressTrainingEngine()
    private let fitnessInsightEngine = FitnessAIInsightEngine()
    private let now: () -> Date

    var activeEnergyTrend: [TimeSeriesPointDouble] = []
    var standHoursTrend: [TimeSeriesPointDouble] = []
    var hrvTrend: [TimeSeriesPointDouble] = []
    var exerciseMinutesTrend: [TimeSeriesPointDouble] = []
    var workoutSummaries: [Date: WorkoutDaySummary] = [:]
    /// 迷你运动月历的独立月份锚点；nil 时跟随 selectedDate 所在月份。
    var miniMonthAnchor: Date?
    private var lastCelebratedChallengeID: UUID?
    private var syncMessageDismissTask: Task<Void, Never>?
    /// 加载代际：快速切月/切周时只允许最新一次加载写入结果。
    private var loadID = UUID()

    static let shortDateFormatter = makeDateFormatter("M月d日")
    static let monthFormatter = makeDateFormatter("yyyy年M月")
    static let weekdayFormatter = makeDateFormatter("E")
    static let dayNumberFormatter = makeDateFormatter("d")

    private static func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }

    init(
        selectedDate: Date = Date(),
        calendarScope: HabitCalendarScope = .week,
        healthKitManager: HealthKitManager? = nil,
        store: FitnessCalendarStore? = nil,
        recoveryChallengeStore: RecoveryChallengeStore? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        let normalizedSelectedDate = calendar.startOfDay(for: selectedDate)
        self.selectedDate = normalizedSelectedDate
        self.calendarScope = calendarScope
        self.healthKitManager = healthKitManager ?? .shared
        self.store = store ?? .shared
        self.recoveryChallengeStore = recoveryChallengeStore ?? .shared
        self.calendar = calendar
        self.now = now
        self.calendarModel = HabitFitnessCalendarModel(
            scope: calendarScope,
            rangeTitle: "",
            streakText: "等待同步",
            summaryPills: ["节奏 0 天", "训练 0 天", "本周 0/4"],
            days: []
        )
        self.statsCards = []
        self.achievementCard = FitnessAchievementCardModel(
            rhythmStreak: 0,
            trainingStreak: 0,
            weeklyTrainingDays: 0,
            weeklyGoal: 4,
            todayMode: nil,
            mascotTitle: "今天准备开练了吗？",
            mascotSubtitle: "先点一次打卡，把今天的训练节奏立住。",
            ctaText: "今天还没打卡"
        )
        self.selectedDayContext = FitnessSelectedDayContextModel(
            date: normalizedSelectedDate,
            title: "今天",
            statusText: "等待打卡",
            summaryText: "先选中一天，健身节律会把训练、恢复和负荷放在一起看。",
            trainingText: "--",
            energyText: "--",
            recoveryText: "--",
            loadText: "--",
            accentHex: "58CC6A",
            isShared: false,
            day: nil
        )
        self.badges = []
        self.overviewModel = FitnessOverviewModel(
            title: "本周训练摘要",
            subtitle: "等训练和活动数据同步后，这里会自动整理成一眼能看懂的训练结果。",
            bestDayText: "最佳一天：等待同步",
            coachTip: "先完成一次训练打卡，后面这里会越来越像你的训练复盘页。",
            statItems: [
                FitnessOverviewStatItem(id: "days", title: "训练天数", valueText: "--", tintHex: "58CC6A", symbol: "calendar"),
                FitnessOverviewStatItem(id: "minutes", title: "训练分钟", valueText: "--", tintHex: "73C8E8", symbol: "timer"),
                FitnessOverviewStatItem(id: "energy", title: "总消耗", valueText: "--", tintHex: "F4B46B", symbol: "flame.fill"),
                FitnessOverviewStatItem(id: "average", title: "日均训练", valueText: "--", tintHex: "2AA7A1", symbol: "chart.bar.fill")
            ]
        )
        self.workoutReviewModel = FitnessWorkoutReviewModel(
            date: nil,
            workoutTitle: "最近训练",
            dateText: "等待同步",
            badgeText: "暂无记录",
            headline: "完成一次训练后，这里会生成单次复盘",
            detailText: "训练时长、消耗、距离、配速和恢复指标会优先使用健康 App 中的真实记录。",
            intensityText: "暂无强度",
            recoveryText: "恢复待评估",
            accentHex: "58CC6A",
            metrics: []
        )
        self.recoveryManagementModel = FitnessRecoveryManagementModel(
            title: "恢复管理",
            scoreText: "--",
            statusText: "等待同步",
            detailText: "等训练和 HRV 样本稳定后，这里会把恢复管理整理成更直接的行动建议。",
            accentHex: "73C8E8",
            focusItems: []
        )
        self.loadRecoveryLinkModel = FitnessLoadRecoveryLinkModel(
            title: "负荷与恢复",
            headline: "先建立样本",
            detailText: "连续记录几天训练与恢复后，这里会开始提示什么时候该冲、什么时候该收。",
            actionText: "先从一次训练打卡开始",
            accentHex: "73C8E8",
            days: []
        )
        self.performanceTrackModel = FitnessPerformanceTrackModel(
            title: "体能追踪",
            scoreText: "--",
            changeText: "暂无趋势",
            statusText: "等待样本",
            detailText: "当训练频率、时长和恢复稳定起来后，这里会用一个简单分数帮你追踪体能走势。",
            accentHex: "73C8E8",
            ranges: [
                FitnessPerformanceTrackRangeModel(
                    range: .recent7,
                    scoreText: "--",
                    changeText: "暂无趋势",
                    statusText: "等待样本",
                    detailText: "当训练频率、时长和恢复稳定起来后，这里会用一个简单分数帮你追踪体能走势。",
                    accentHex: "73C8E8"
                )
            ]
        )
        self.performanceReviewModel = FitnessPerformanceReviewModel(
            title: "阶段复盘",
            badgeText: "等待同步",
            summaryText: "先把训练和恢复样本积起来，后面这里会自动生成一段更像复盘的总结。",
            accentHex: "73C8E8",
            items: [],
            bestDay: nil
        )
        self.nextStepModel = FitnessNextStepModel(
            title: "下一步建议",
            headline: "先建立今天的训练状态",
            detailText: "完成训练、轻恢复或休息打卡后，这里会把负荷、恢复和周期节奏合成一个更明确的下一步。",
            primaryActionTitle: "补充记录",
            primaryMode: nil,
            secondaryActionTitle: "查看详情",
            accentHex: "58CC6A",
            symbol: "sparkles",
            chips: ["等待打卡", "恢复 --", "负荷 --"]
        )
        self.checkinOpeningModel = FitnessCheckinOpeningModel(
            currentStreak: 0,
            longestStreak: 0,
            startDate: normalizedSelectedDate,
            monthTitle: "",
            todayStatusTitle: "待打卡",
            todayMode: nil,
            days: []
        )
        self.sharedHighlights = []
        self.trainingLogs = []
        self.activeRecoveryChallenge = nil
        self.challengeHistoryPreview = []
        self.challengeTodayProgress = nil
        self.challengeSelectionCards = RecoveryChallengeKind.allCases.map {
            let definition = $0.definition
            return RecoveryChallengeSelectionCardModel(
                kind: $0,
                title: definition.title,
                subtitle: definition.subtitle,
                ruleText: definition.ruleText,
                symbol: definition.symbol,
                tintHex: definition.tintHex
            )
        }
        self.syncMessage = nil
        self.liveWorkoutState = .idle
        self.fitnessInsightContext = .placeholder
        self.fitnessInsight = fitnessInsightEngine.makeInsight(from: .placeholder)
    }

    func load() {
        load(for: selectedDate)
    }

    func load(for date: Date) {
        let targetDate = calendar.startOfDay(for: date)
        selectedDate = targetDate
        loadID = UUID()
        let id = loadID
        isLoading = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            let range = self.calendarFetchRange(anchoredAt: targetDate)
            let workoutStartDate = self.calendar.date(
                byAdding: .day,
                value: -(max(range.days, 1) - 1),
                to: range.endDate
            ) ?? range.startDate
            let energyTrend = (try? await self.healthKitManager.fetchDailyActiveEnergySums(days: range.days, endDate: range.endDate)) ?? []
            let exerciseTrend = (try? await self.healthKitManager.fetchDailyExerciseTimeSums(days: range.days, endDate: range.endDate)) ?? []
            let standTrend = (try? await self.healthKitManager.fetchDailyStandHours(days: range.days, endDate: range.endDate)) ?? []
            let resolvedHrvTrend = (try? await self.healthKitManager.fetchDailyHRVAverages(days: range.days, endDate: range.endDate)) ?? []
            let summaries = (try? await self.healthKitManager.fetchWorkoutDaySummaries(startDate: workoutStartDate, endDate: range.endDate)) ?? []

            // 已切换到其他日期/范围或本任务被取代时丢弃过期结果。
            guard !Task.isCancelled, id == self.loadID else { return }

            self.activeEnergyTrend = energyTrend
            self.exerciseMinutesTrend = exerciseTrend
            self.standHoursTrend = standTrend
            self.hrvTrend = resolvedHrvTrend
            self.workoutSummaries = Dictionary(uniqueKeysWithValues: summaries.map { (self.calendar.startOfDay(for: $0.date), $0) })
            self.rebuild()
            self.isLoading = false
            await self.refreshRecoveryChallengeState()
        }
    }

    func updateCalendarScope(_ scope: HabitCalendarScope) {
        guard calendarScope != scope else { return }
        playSelectionFeedback()
        calendarScope = scope
        // 先用已加载的聚合数据立即切换布局，避免月历 Sheet 首帧仍显示周视图。
        rebuild()
        load(for: selectedDate)
    }

    func shiftCalendar(by step: Int) {
        let component: Calendar.Component = calendarScope == .week ? .weekOfYear : .month
        guard let newDate = calendar.date(byAdding: component, value: step, to: selectedDate) else { return }
        playSelectionFeedback()
        load(for: newDate)
    }

    func scrollToToday() {
        playSelectionFeedback()
        load(for: Date())
    }

    var todayDate: Date {
        calendar.startOfDay(for: Date())
    }

    var todayCalendarDay: HabitFitnessCalendarDay? {
        let normalizedToday = todayDate
        if let day = calendarModel.days.first(where: { calendar.isDate($0.date, inSameDayAs: normalizedToday) }) {
            return day
        }
        let record = store.record(for: normalizedToday)
        return buildDetachedDay(for: record)
    }

    func selectDay(_ day: HabitFitnessCalendarDay) {
        playSelectionFeedback()
        selectedDate = calendar.startOfDay(for: day.date)
        rebuild()
    }

    func selectDate(_ date: Date) {
        let normalized = calendar.startOfDay(for: date)
        playSelectionFeedback()
        if calendarModel.days.contains(where: { calendar.isDate($0.date, inSameDayAs: normalized) }) {
            selectedDate = normalized
            rebuild()
        } else {
            load(for: normalized)
        }
    }

    func openSelectedDayDetail() {
        guard let day = selectedCalendarDay else { return }
        playSelectionFeedback()
        selectedDetail = makeDetailModel(for: day)
    }

    func openDetail(for day: HabitFitnessCalendarDay) {
        selectDay(day)
        selectedDetail = makeDetailModel(for: day)
    }

    func openTodayDetail() {
        playSelectionFeedback()
        selectedDate = todayDate
        if !calendarModel.days.contains(where: { calendar.isDate($0.date, inSameDayAs: todayDate) }) {
            calendarScope = .week
            if let day = todayCalendarDay {
                selectedDetail = makeDetailModel(for: day)
            }
            load(for: todayDate)
            return
        }
        rebuild()
        if let day = todayCalendarDay {
            selectedDetail = makeDetailModel(for: day)
        }
    }

    func openLatestWorkoutDetail() {
        guard let date = workoutReviewModel.date else { return }
        playSelectionFeedback()
        selectedDate = calendar.startOfDay(for: date)
        let day = calendarModel.days.first(where: { calendar.isDate($0.date, inSameDayAs: date) })
            ?? buildDetachedDay(for: store.record(for: date))
        selectedDetail = makeDetailModel(for: day)
    }

    func quickMarkSelectedDay(_ mode: FitnessCheckinMode) {
        let targetDate = calendar.startOfDay(for: selectedDate)
        playSuccessFeedback()
        store.setFitnessCheckin(mode: mode, for: targetDate)
        rebuild()
        refreshSelectedDetailIfNeeded(for: targetDate)
        showSyncMessage(mode == .recovery ? "已标记为轻恢复" : mode == .rest ? "已标记为休息日" : "已标记为训练日")
        Task { await refreshRecoveryChallengeState(showCelebrationIfCompleted: false) }
    }

    func clearSelectedDayCheckin() {
        let targetDate = calendar.startOfDay(for: selectedDate)
        let record = store.record(for: targetDate)
        guard record.fitnessCheckinMode != nil ||
              record.manualWorkoutMinutes > 0 ||
              record.manualWorkoutEffort != nil ||
              !record.fitnessNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showSyncMessage("这一天还没有手动健身记录")
            return
        }

        playSelectionFeedback()
        store.clearFitnessCheckin(for: targetDate)
        rebuild()
        refreshSelectedDetailIfNeeded(for: targetDate)
        showSyncMessage("已清除当天手动记录")
        Task { await refreshRecoveryChallengeState(showCelebrationIfCompleted: false) }
    }

    func toggleSelectedDayShared() {
        let targetDate = calendar.startOfDay(for: selectedDate)
        let current = store.record(for: targetDate).isShared
        playSelectionFeedback()
        store.setShared(!current, for: targetDate)
        rebuild()
        refreshSelectedDetailIfNeeded(for: targetDate)
        showSyncMessage(current ? "已取消分享摘要" : "已分享当天摘要")
    }

    func performTodayCheckin(_ mode: FitnessCheckinMode) {
        let today = todayDate
        playSuccessFeedback()
        store.setFitnessCheckin(mode: mode, for: today)
        selectedDate = today
        if !calendarModel.days.contains(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            calendarScope = .week
            if let day = todayCalendarDay {
                selectedDetail = makeDetailModel(for: day)
            }
            load(for: today)
            showSyncMessage("今日已打卡")
            Task { await refreshRecoveryChallengeState(showCelebrationIfCompleted: false) }
            return
        }
        rebuild()
        refreshSelectedDetailIfNeeded(for: today)
        if let day = todayCalendarDay {
            selectedDetail = makeDetailModel(for: day)
        }
        showSyncMessage("今日已打卡")
        Task { await refreshRecoveryChallengeState(showCelebrationIfCompleted: false) }
    }

    func performTodayCheckinInline(_ mode: FitnessCheckinMode) {
        let today = todayDate
        playSuccessFeedback()
        store.setFitnessCheckin(mode: mode, for: today)
        selectedDate = today
        if !calendarModel.days.contains(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            load(for: today)
        } else {
            rebuild()
        }
        refreshSelectedDetailIfNeeded(for: today)
        showSyncMessage("已记录：\(mode.title)", duration: .milliseconds(1_600))
        Task { await refreshRecoveryChallengeState(showCelebrationIfCompleted: false) }
    }

    func saveFitnessDetail(draft: FitnessDayDetailDraft) {
        store.saveFitnessDetail(for: selectedDate, draft: draft)
        rebuild()
        refreshSelectedDetailIfNeeded(for: selectedDate)

        let hasHealthWriteback = draft.syncToHealthApp
            && ((draft.mode == .workout && draft.minutes > 0) || draft.mood != nil)
        guard hasHealthWriteback else {
            if let day = selectedCalendarDay {
                selectedDetail = makeDetailModel(for: day)
            }
            Task { await refreshRecoveryChallengeState(showCelebrationIfCompleted: false) }
            return
        }

        let date = selectedDate
        Task {
            let outcome = await FitnessHealthWritebackService.shared.sync(draft: draft, for: date)
            await MainActor.run {
                if outcome.didFail {
                    self.showSyncMessage("已保存在本地，写入健康 App 失败", duration: .seconds(2))
                    if let day = self.selectedCalendarDay {
                        self.selectedDetail = self.makeDetailModel(for: day)
                    }
                } else if outcome.didSyncAnything {
                    self.showSyncMessage("已同步到健康 App", duration: .seconds(2))
                    self.load(for: date)
                }
            }
        }
        Task { await refreshRecoveryChallengeState(showCelebrationIfCompleted: false) }
    }

    func setActionRecordShared(_ isShared: Bool, for date: Date) {
        store.setShared(isShared, for: date)
        rebuild()
        if let day = calendarModel.days.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            selectedDetail = makeDetailModel(for: day)
        }
        Task { await refreshRecoveryChallengeState(showCelebrationIfCompleted: false) }
    }

    func dismissChallengeCelebration() {
        showingChallengeCelebration = false
    }

    private func showSyncMessage(_ message: String, duration: Duration = .milliseconds(1_800)) {
        syncMessageDismissTask?.cancel()
        syncMessage = message
        syncMessageDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            syncMessage = nil
            syncMessageDismissTask = nil
        }
    }

    private func refreshRecoveryChallengeState(showCelebrationIfCompleted: Bool = true) async {
        let previousActiveID = activeRecoveryChallenge?.id
        let updated = await recoveryChallengeStore.evaluateAndRefresh(on: now())
        let active = updated?.status == .active ? updated : recoveryChallengeStore.activeChallenge()
        let history = recoveryChallengeStore.history(limit: 3)

        activeRecoveryChallenge = active
        challengeTodayProgress = active?.dayProgresses.first(where: { calendar.isDate($0.date, inSameDayAs: todayDate) })
        challengeHistoryPreview = history.map(makeHistoryPreview)

        if showCelebrationIfCompleted,
           let updated,
           updated.status == .completed,
           updated.id == previousActiveID,
           updated.id != lastCelebratedChallengeID {
            lastCelebratedChallengeID = updated.id
            challengeCelebrationTitle = updated.definition.successTitle
            challengeCelebrationSubtitle = updated.definition.successSubtitle
            showingChallengeCelebration = true
        }
    }

    func fitnessRecoveryInsight(for day: HabitFitnessCalendarDay?) -> FitnessRecoveryInsightModel {
        guard let day else {
            return FitnessRecoveryInsightModel(
                title: "恢复线索待建立",
                statusText: "等待同步",
                detailText: "先打卡，再同步训练与 HRV 样本，这里会逐渐长出恢复建议。",
                accentHex: "73C8E8"
            )
        }

        if let mode = day.checkinMode, mode == .recovery {
            return FitnessRecoveryInsightModel(
                title: "今天偏恢复模式",
                statusText: "节奏不断",
                detailText: "你今天已经保住训练节奏了，后续更适合做轻活动、拉伸或早点休息。",
                accentHex: mode.tintHex
            )
        }

        if let hrv = day.hrvValue, hrv > 0, day.displayWorkoutMinutes >= 30 {
            return FitnessRecoveryInsightModel(
                title: hrv < 35 ? "训练后更建议恢复" : "训练与恢复都在线",
                statusText: hrv < 35 ? "恢复偏紧" : "恢复不错",
                detailText: hrv < 35
                    ? "这一天训练负荷已经有了，后续更值得关注睡眠、补水和恢复强度。"
                    : "这一天既有训练刺激也有恢复样本，可以继续保持这类节奏。",
                accentHex: hrv < 35 ? "F06A7B" : "58CC6A"
            )
        }

        if day.checkinMode == .rest {
            return FitnessRecoveryInsightModel(
                title: "今天是计划休整日",
                statusText: "也算节奏的一部分",
                detailText: "休息不是断掉，而是为下一次更稳地接上训练留出空间。",
                accentHex: "94A3C3"
            )
        }

        if day.isInferredWorkoutOnly {
            return FitnessRecoveryInsightModel(
                title: "识别到训练，但你还没手动确认",
                statusText: "建议补个打卡",
                detailText: "补上今天的训练模式和备注，连续成就和徽章会更完整。",
                accentHex: "F4B46B"
            )
        }

        return FitnessRecoveryInsightModel(
            title: "可以把今天补完整",
            statusText: day.checkinMode == .workout ? "训练已打卡" : "等待打卡",
            detailText: day.checkinMode == .workout
                ? "如果方便，补上时长、主观强度或一句备注，后面回看会更有价值。"
                : "先打一张卡，哪怕只做轻恢复，也比把今天留空更容易保持节奏。",
            accentHex: day.checkinMode?.tintHex ?? "58CC6A"
        )
    }

    func intensityScore(for day: HabitFitnessCalendarDay) -> Double {
        let minutes = max(day.exerciseMinutes, day.manualWorkoutMinutes)
        guard minutes > 0 else { return 0 }
        return Double(day.activeEnergy) / Double(max(minutes, 1))
    }

    func intensityTier(for day: HabitFitnessCalendarDay) -> String {
        let score = intensityScore(for: day)
        switch score {
        case ..<1:
            return String(localized: "轻")
        case ..<4:
            return String(localized: "中")
        default:
            return String(localized: "高")
        }
    }

    var selectedCalendarDay: HabitFitnessCalendarDay? {
        calendarModel.days.first(where: { $0.isSelected })
            ?? calendarModel.days.first(where: { !$0.isFuture && $0.isInDisplayedMonth })
    }

    private func rebuild() {
        let calendarModel = makeCalendarModel()
        self.calendarModel = calendarModel
        self.statsCards = makeStatsCards(days: calendarModel.days)
        self.achievementCard = makeAchievementCard(days: calendarModel.days)
        self.selectedDayContext = makeSelectedDayContext(days: calendarModel.days)
        self.badges = makeBadges()
        self.trainingLogs = makeTrainingLogs(days: calendarModel.days)
        self.overviewModel = makeOverviewModel(days: calendarModel.days)
        self.workoutReviewModel = makeWorkoutReviewModel()
        self.recoveryManagementModel = makeRecoveryManagementModel(days: calendarModel.days)
        self.loadRecoveryLinkModel = makeLoadRecoveryLinkModel(days: calendarModel.days)
        self.performanceTrackModel = makePerformanceTrackModel(days: calendarModel.days)
        self.performanceReviewModel = makePerformanceReviewModel(days: calendarModel.days)
        self.nextStepModel = makeNextStepModel(days: calendarModel.days)
        self.checkinOpeningModel = makeCheckinOpeningModel(days: calendarModel.days)
        self.sharedHighlights = makeSharedHighlights(days: calendarModel.days)
        self.cycleTrainingRhythmPlan = makeCycleTrainingRhythmPlan()
        let insightContext = makeFitnessInsightContext()
        self.fitnessInsightContext = insightContext
        self.fitnessInsight = fitnessInsightEngine.makeInsight(from: insightContext)
    }

    private func makeFitnessInsightContext() -> FitnessAIInsightContext {
        let energyMap = pointsMap(activeEnergyTrend)
        let exerciseMap = pointsMap(exerciseMinutesTrend)
        let standMap = pointsMap(standHoursTrend)
        let hrvMap = pointsMap(hrvTrend)
        let end = calendar.startOfDay(for: selectedDate)
        let days = (0..<14).compactMap { offset -> HabitFitnessCalendarDay? in
            guard let date = calendar.date(byAdding: .day, value: -(13 - offset), to: end) else { return nil }
            return buildCalendarDay(
                for: date,
                energyMap: energyMap,
                exerciseMap: exerciseMap,
                standMap: standMap,
                hrvMap: hrvMap,
                isInDisplayedMonth: true
            )
        }
        let previous = Array(days.prefix(7))
        let recent = Array(days.suffix(7))
        let isTrainingDay: (HabitFitnessCalendarDay) -> Bool = {
            $0.displayWorkoutMinutes > 0 || $0.checkinMode == .workout || $0.isInferredWorkoutOnly
        }
        let recentTrainingDays = recent.filter(isTrainingDay).count
        let previousTrainingDays = previous.filter(isTrainingDay).count
        let recentMinutes = recent.reduce(0) { $0 + $1.displayWorkoutMinutes }
        let previousMinutes = previous.reduce(0) { $0 + $1.displayWorkoutMinutes }
        let activitySampleDays = recent.filter {
            $0.activeEnergy > 0 || $0.displayWorkoutMinutes > 0 || $0.standHours > 0 || $0.checkinMode != nil
        }.count
        let hrvSampleDays = recent.filter { ($0.hrvValue ?? 0) > 0 }.count
        let current = recent.last
        let hasLoadSignal = current.map {
            $0.activeEnergy > 0 || $0.displayWorkoutMinutes > 0 || $0.checkinMode == .workout || $0.isInferredWorkoutOnly
        } ?? false
        let hasRecoverySignal = current.map {
            ($0.hrvValue ?? 0) > 0 || $0.standHours > 0 || $0.checkinMode == .recovery || $0.checkinMode == .rest
        } ?? false
        let recentPerformance = activitySampleDays > 0 ? performanceScore(for: recent) : nil
        let previousHasSamples = previous.contains {
            $0.activeEnergy > 0 || $0.displayWorkoutMinutes > 0 || $0.standHours > 0 || ($0.hrvValue ?? 0) > 0 || $0.checkinMode != nil
        }
        let previousPerformance = previousHasSamples ? performanceScore(for: previous) : nil
        let latestWorkoutSummary: String?
        if workoutReviewModel.date != nil {
            latestWorkoutSummary = [workoutReviewModel.workoutTitle, workoutReviewModel.headline]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        } else {
            latestWorkoutSummary = nil
        }

        return FitnessAIInsightContext(
            dateText: ISO8601DateFormatter().string(from: end),
            recentTrainingDays: recentTrainingDays,
            previousTrainingDays: previousTrainingDays,
            recentMinutes: recentMinutes,
            previousMinutes: previousMinutes,
            currentLoadScore: hasLoadSignal ? current.map(trainingLoadScore(for:)) : nil,
            currentRecoveryScore: hasRecoverySignal ? current.map(recoveryScore(for:)) : nil,
            performanceScore: recentPerformance,
            performanceChange: recentPerformance.flatMap { recentScore in
                previousPerformance.map { recentScore - $0 }
            },
            hrvSampleDays: hrvSampleDays,
            activitySampleDays: activitySampleDays,
            latestWorkoutSummary: latestWorkoutSummary
        )
    }

}
