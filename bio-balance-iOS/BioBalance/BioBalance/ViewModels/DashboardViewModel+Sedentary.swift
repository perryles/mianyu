import Foundation
import SwiftUI
import HealthKit
import WidgetKit
import OSLog


/// DashboardViewModel 久坐域：状态刷新 / 历史分页 / 打断流程与久坐洞察文案构建。
/// 从原 DashboardViewModel.swift 拆出，对外接口不变。

@MainActor
extension DashboardViewModel {

    func refreshSedentaryState() async {
        let currentDate = now()
        async let summaryTask = HealthKitManager.shared.fetchSedentaryDaySummary(on: currentDate, now: currentDate)
        async let historyTask = HealthKitManager.shared.fetchSedentaryDaySummaries(
            days: sedentaryInitialHistoryDays,
            endDate: currentDate,
            now: currentDate
        )
        refreshSedentaryBreakProgress(now: currentDate)
        isLoadingMoreSedentaryHistory = false
        hasMoreSedentaryHistory = true
        nextSedentaryHistoryEndDate = Calendar.current.date(byAdding: .day, value: -sedentaryInitialHistoryDays, to: Calendar.current.startOfDay(for: currentDate))

        guard sedentaryAutoStartEnabled else {
            sedentaryState = DashboardSedentaryState(
                seatedStartAt: nil,
                lastActivityAt: nil,
                elapsedMinutes: 0,
                isCounting: false,
                pausedBySleep: false,
                sourceStatus: .autoStartDisabled
            )
            cancelSedentaryReminders()
            HealthDataManager.shared.pushSedentaryToWatch(
                elapsedMinutes: 0,
                isCounting: false,
                pausedBySleep: false,
                seatedStartAt: nil,
                lastActivityAt: nil
            )
            sedentaryTodaySummary = (try? await summaryTask) ?? SedentaryDaySummary.placeholder(on: currentDate, status: .unavailable, updatedAt: currentDate)
            sedentaryRecentSummaries = mergeSedentaryHistorySummaries((try? await historyTask) ?? [])
            updateSedentaryHistoryPaginationState(afterLoading: sedentaryRecentSummaries)
            return
        }

        do {
            let state = try await HealthKitManager.shared.fetchCurrentSedentaryState(now: currentDate)
            sedentaryState = DashboardSedentaryState(
                seatedStartAt: state.seatedStartAt,
                lastActivityAt: state.lastActivityAt,
                elapsedMinutes: state.elapsedMinutes,
                isCounting: state.isCounting,
                pausedBySleep: state.pausedBySleep,
                sourceStatus: DashboardSedentaryState.SourceStatus(state.sourceStatus)
            )
            syncSedentaryReminder()
            HealthDataManager.shared.pushSedentaryToWatch(
                elapsedMinutes: state.elapsedMinutes,
                isCounting: state.isCounting,
                pausedBySleep: state.pausedBySleep,
                seatedStartAt: state.seatedStartAt,
                lastActivityAt: state.lastActivityAt
            )
            sedentaryTodaySummary = (try? await summaryTask) ?? SedentaryDaySummary.placeholder(on: currentDate, status: .unavailable, updatedAt: currentDate)
            sedentaryRecentSummaries = mergeSedentaryHistorySummaries((try? await historyTask) ?? [])
            updateSedentaryHistoryPaginationState(afterLoading: sedentaryRecentSummaries)
        } catch {
            let authorizationStatus = await HealthKitManager.shared.sedentaryAuthorizationRequestStatus()
            let sourceStatus: DashboardSedentaryState.SourceStatus = authorizationStatus == .shouldRequest ? .needsAuthorization : .unavailable
            sedentaryState = DashboardSedentaryState(
                seatedStartAt: nil,
                lastActivityAt: nil,
                elapsedMinutes: 0,
                isCounting: false,
                pausedBySleep: false,
                sourceStatus: sourceStatus
            )
            cancelSedentaryReminders()
            HealthDataManager.shared.pushSedentaryToWatch(
                elapsedMinutes: 0,
                isCounting: false,
                pausedBySleep: false,
                seatedStartAt: nil,
                lastActivityAt: nil
            )
            let summaryStatus: SedentaryDaySummary.SourceStatus = authorizationStatus == .shouldRequest ? .needsAuthorization : .unavailable
            sedentaryTodaySummary = (try? await summaryTask) ?? SedentaryDaySummary.placeholder(on: currentDate, status: summaryStatus, updatedAt: currentDate)
            sedentaryRecentSummaries = mergeSedentaryHistorySummaries((try? await historyTask) ?? [])
            updateSedentaryHistoryPaginationState(afterLoading: sedentaryRecentSummaries)
        }
    }

    func loadMoreSedentaryHistory() async {
        guard !isLoadingMoreSedentaryHistory, hasMoreSedentaryHistory, let nextEndDate = nextSedentaryHistoryEndDate else { return }
        isLoadingMoreSedentaryHistory = true
        let requestNow = now()

        defer {
            isLoadingMoreSedentaryHistory = false
        }

        let olderSummaries = (try? await HealthKitManager.shared.fetchSedentaryDaySummaries(
            days: sedentaryHistoryPageDays,
            endDate: nextEndDate,
            now: requestNow
        )) ?? []

        sedentaryRecentSummaries = mergeSedentaryHistorySummaries(sedentaryRecentSummaries + olderSummaries)
        updateSedentaryHistoryPaginationState(afterLoading: olderSummaries)
    }

    func ensureSedentaryHistoryContains(date: Date, maxPages: Int = 12) async {
        let targetDate = Calendar.current.startOfDay(for: date)
        var loadedPages = 0

        while hasMoreSedentaryHistory,
              targetDate >= sedentaryHistoryMinimumDate,
              !sedentaryRecentSummaries.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: targetDate) }),
              loadedPages < maxPages {
            await loadMoreSedentaryHistory()
            loadedPages += 1
        }
    }

    func mergeSedentaryHistorySummaries(_ summaries: [SedentaryDaySummary]) -> [SedentaryDaySummary] {
        let merged = Dictionary(grouping: summaries, by: \.id)
            .compactMap { _, days in
                days.max(by: { $0.updatedAt < $1.updatedAt }) ?? days.first
            }
            .sorted { $0.date > $1.date }
        return merged
    }

    func updateSedentaryHistoryPaginationState(afterLoading loadedSummaries: [SedentaryDaySummary]) {
        guard let earliestDate = loadedSummaries.map(\.date).min() else {
            hasMoreSedentaryHistory = false
            nextSedentaryHistoryEndDate = nil
            return
        }

        guard let nextEndDate = Calendar.current.date(byAdding: .day, value: -1, to: earliestDate) else {
            hasMoreSedentaryHistory = false
            nextSedentaryHistoryEndDate = nil
            return
        }

        hasMoreSedentaryHistory = nextEndDate >= sedentaryHistoryMinimumDate
        nextSedentaryHistoryEndDate = hasMoreSedentaryHistory ? nextEndDate : nil
    }

    func refreshSedentaryBreakProgress(now: Date = Date()) {
        let isActive = AppGroupManager.shared.getSedentaryBreakIsActive() ?? false
        let targetMinutes = AppGroupManager.shared.getSedentaryBreakDurationMinutes() ?? 0
        let startedAt = AppGroupManager.shared.getSedentaryBreakStartedAt()

        if isActive, let startedAt, targetMinutes > 0 {
            sedentaryBreakProgress = .active(targetMinutes: targetMinutes, startedAt: startedAt)
            cancelSedentaryReminders()
            return
        }

        guard !sedentaryBreakProgress.isCompletedFeedbackVisible else { return }
        sedentaryBreakProgress = .idle
    }

    func startSedentaryBreak(durationMinutes: Int) {
        let startedAt = now()
        let targetMinutes = max(1, durationMinutes)
        sedentaryBreakProgress = .active(targetMinutes: targetMinutes, startedAt: startedAt)
        HealthDataManager.shared.pushSedentaryBreakToWatch(
            isActive: true,
            durationMinutes: targetMinutes,
            startedAt: startedAt
        )
        cancelSedentaryReminders()
    }

    func sedentaryHistoryTakeaway(for day: SedentaryDaySummary) -> String {
        Self.makeSedentaryHistoryTakeaway(for: day)
    }

    /// 方法说明：统一估算单个时间点的压力值。
    /// 今日页曲线、HealthKit 合成历史和部分回退逻辑都会走这里，确保“单点压力”口径一致。
    static func makeSedentaryInsightContent(
        state: DashboardSedentaryState,
        summary: SedentaryDaySummary,
        breakProgress: SedentaryBreakProgressState,
        remindersEnabled: Bool,
        historySummaries: [SedentaryDaySummary],
        now: Date
    ) -> SedentaryInsightContent {
        let historySummary = makeSedentaryHistoryInsight(summaries: historySummaries)
        let preferredBreakKind = preferredBreakKind(summary: summary, historySummaries: historySummaries)
        let preferredBreakText = preferredBreakKind?.title ?? "步行或站立"
        let focusBucket = preferredFocusBucket(summary: summary, historySummaries: historySummaries)
        let todayFocusText = SedentaryDaySummary.preferredSedentaryDaypart(in: [summary])?.title ?? focusBucket

        if breakProgress.isActive {
            let elapsed = max(1, breakProgress.elapsedMinutes(now: now))
            let reachedGoal = breakProgress.hasReachedGoal(now: now)
            let cardTitle = reachedGoal ? "这次打断已经达标" : "打断进行中"
            let cardSummary = reachedGoal
                ? "已经活动了 \(elapsed) 分钟，回来后可以直接完成本次打断。"
                : "目标 \(breakProgress.targetMinutes) 分钟，已经开始 \(elapsed) 分钟，继续保持就好。"
            return SedentaryInsightContent(
                cardTitle: cardTitle,
                cardSummary: cardSummary,
                cardValueText: "\(elapsed)",
                cardValueUnit: "min",
                dashboardActionTitle: reachedGoal ? "这次打断已经做到位了" : "你已经开始起身活动了",
                dashboardActionDetail: reachedGoal
                    ? "继续走动或拉伸一会儿都可以，回到详情页点一下“完成本次打断”就行。"
                    : "保持到 \(breakProgress.targetMinutes) 分钟会更稳，做完后再回来完成这次打断。",
                breakSectionTitle: reachedGoal ? "回来时记得完成这次打断" : "先把这次打断做完整",
                breakSectionDetail: reachedGoal
                    ? "目标已经达到，完成后会把当前久坐状态按最近活动重新恢复。"
                    : "目标先定在 \(breakProgress.targetMinutes) 分钟，过程中不用频繁看数据，只要持续活动就可以。",
                historySummary: historySummary,
                guidanceTitle: "打断建议",
                guidanceItems: [
                    SedentaryGuidanceItem(
                        title: "当前状态",
                        detail: reachedGoal
                            ? "这次打断已经达到 \(breakProgress.targetMinutes) 分钟目标，说明这段久坐已经被有效拆开。"
                            : "已经连续活动 \(elapsed) 分钟，再坚持一下，会比只起身几十秒更有价值。",
                        symbol: "figure.walk.motion"
                    ),
                    SedentaryGuidanceItem(
                        title: "完成动作",
                        detail: reachedGoal
                            ? "回到页面后直接完成本次打断即可；如果还在忙，也可以顺手多走一小段。"
                            : "优先保持 \(preferredBreakText)，不需要边走边盯数据，回来再统一完成这次记录。",
                        symbol: reachedGoal ? "checkmark.circle.fill" : "flag.checkered"
                    ),
                    SedentaryGuidanceItem(
                        title: "后续观察",
                        detail: historySummary,
                        symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                    )
                ]
            )
        }

        if breakProgress.isCompletedFeedbackVisible {
            let completedMinutes = max(1, breakProgress.completedMinutes ?? 1)
            return SedentaryInsightContent(
                cardTitle: "刚完成一次打断",
                cardSummary: "本次一共活动了 \(completedMinutes) 分钟，身体已经从刚才那段久坐里缓了一口气。",
                cardValueText: "完成",
                cardValueUnit: "",
                dashboardActionTitle: "这次打断已经完成了",
                dashboardActionDetail: "接下来继续把今天后面的长坐段拆开，节律会比只看累计时长更稳。",
                breakSectionTitle: "本次已完成 \(completedMinutes) 分钟打断",
                breakSectionDetail: "状态会按最近活动重新恢复，等下一段久坐重新形成后，再决定要不要继续打断。",
                historySummary: historySummary,
                guidanceTitle: "完成后怎么接",
                guidanceItems: [
                    SedentaryGuidanceItem(
                        title: "身体反馈",
                        detail: "这次 \(completedMinutes) 分钟的活动已经把刚才那段久坐拆开，当前更重要的是别马上又坐回很久。",
                        symbol: "sparkles"
                    ),
                    SedentaryGuidanceItem(
                        title: "接下来动作",
                        detail: "后面如果又连续坐到 30 到 45 分钟，可以提前起身一次，不必每次都等提醒出现。",
                        symbol: "arrow.clockwise.circle"
                    ),
                    SedentaryGuidanceItem(
                        title: "最近规律",
                        detail: historySummary,
                        symbol: "chart.xyaxis.line"
                    )
                ]
            )
        }

        switch state.sourceStatus {
        case .needsAuthorization:
            return SedentaryInsightContent(
                cardTitle: "先开启健康权限",
                cardSummary: "开启后会根据步数、运动和站立样本判断久坐状态，并同步今天的提醒和分布。",
                cardValueText: "待定",
                cardValueUnit: "",
                dashboardActionTitle: "先把健康权限补齐",
                dashboardActionDetail: "权限打开后，今天的久坐时段、打断次数和提醒节点才会开始变得可读。",
                breakSectionTitle: "先恢复数据，再开始打断",
                breakSectionDetail: "久坐打断依赖今天的步数、运动和站立样本。开启权限后，这里会自动切到可操作状态。",
                historySummary: historySummary,
                guidanceTitle: "开启后你会看到什么",
                guidanceItems: [
                    SedentaryGuidanceItem(
                        title: "当前缺什么",
                        detail: "现在缺的是步数、运动和站立样本，所以系统还不能判断你今天的长坐段到底出现在哪里。",
                        symbol: "heart.text.square.fill"
                    ),
                    SedentaryGuidanceItem(
                        title: "补齐后变化",
                        detail: "权限一开，页面会逐步补出今日时间轴、提醒节点和打断次数，内容会马上变得更具体。",
                        symbol: "waveform.path.ecg"
                    ),
                    SedentaryGuidanceItem(
                        title: "最近规律",
                        detail: historySummary,
                        symbol: "clock.badge"
                    )
                ]
            )
        case .sleeping:
            return SedentaryInsightContent(
                cardTitle: "睡眠中已暂停久坐判断",
                cardSummary: "现在优先保证休息，醒来后久坐计时和提醒会自己恢复，不需要额外操作。",
                cardValueText: "暂停中",
                cardValueUnit: "",
                dashboardActionTitle: "睡眠阶段先不用处理久坐",
                dashboardActionDetail: "醒来以后再看今天最久的那一段坐时，会比现在更有参考价值。",
                breakSectionTitle: "等醒来后再安排打断",
                breakSectionDetail: "当前不建议开始打断流程，等系统恢复久坐判断后，再决定今天哪一段最该拆开。",
                historySummary: historySummary,
                guidanceTitle: "当前更适合做什么",
                guidanceItems: [
                    SedentaryGuidanceItem(
                        title: "当前状态",
                        detail: "系统已经识别到你处于睡眠阶段，所以久坐计时和提醒都先暂停了，这是正常保护逻辑。",
                        symbol: "moon.zzz.fill"
                    ),
                    SedentaryGuidanceItem(
                        title: "醒来后动作",
                        detail: "等醒来并恢复活动后，再回来看今天最久的时段，会比现在安排打断更有参考价值。",
                        symbol: "sunrise.fill"
                    ),
                    SedentaryGuidanceItem(
                        title: "最近规律",
                        detail: historySummary,
                        symbol: "clock.badge"
                    )
                ]
            )
        case .autoStartDisabled:
            return SedentaryInsightContent(
                cardTitle: "久坐自动开始已关闭",
                cardSummary: remindersEnabled
                    ? "自动开始关闭后，当前计时与下一次提醒都会停止；重新开启后才会继续更新。"
                    : "自动开始和久坐提示都处于关闭状态，重新开启后这里才会继续恢复判断。",
                cardValueText: "已关闭",
                cardValueUnit: "",
                dashboardActionTitle: "先把自动开始重新打开",
                dashboardActionDetail: "久坐计时和提醒都跟着停下来了，打开后这里才会继续判断今天的节律。",
                breakSectionTitle: "恢复自动判断后再开始打断",
                breakSectionDetail: "现在没有稳定的当前状态，先重新开启自动开始，系统才知道什么时候值得你起身打断。",
                historySummary: historySummary,
                guidanceTitle: "恢复监测的重点",
                guidanceItems: [
                    SedentaryGuidanceItem(
                        title: "当前状态",
                        detail: "自动开始关闭后，系统不会再根据步数和站立样本自动判断久坐，所以今天的内容会停在不完整状态。",
                        symbol: "pause.circle.fill"
                    ),
                    SedentaryGuidanceItem(
                        title: "先做什么",
                        detail: "优先重新打开自动开始；如果你也关掉了提醒，建议一并开启，这样后续节律才会连续。",
                        symbol: "switch.2"
                    ),
                    SedentaryGuidanceItem(
                        title: "最近规律",
                        detail: historySummary,
                        symbol: "clock.badge"
                    )
                ]
            )
        case .noActivitySamples:
            return SedentaryInsightContent(
                cardTitle: "继续累积活动样本",
                cardSummary: "还没有足够样本，继续佩戴 Apple Watch 或保持健康同步后，这里会慢慢补齐。",
                cardValueText: "待同步",
                cardValueUnit: "",
                dashboardActionTitle: "先等今天的活动样本补上来",
                dashboardActionDetail: "一旦系统读到更完整的步数、运动和站立数据，就能开始告诉你久坐集中在哪些时段。",
                breakSectionTitle: "等数据补齐后再安排打断",
                breakSectionDetail: "当前还没有稳定的久坐判断，先让今天的数据流完整起来，会比现在硬做动作更有参考价值。",
                historySummary: historySummary,
                guidanceTitle: "样本不足时先看什么",
                guidanceItems: [
                    SedentaryGuidanceItem(
                        title: "为什么还没出来",
                        detail: "今天的步数、运动或站立样本还不够连续，所以系统暂时没法判断你是不是已经形成长坐段。",
                        symbol: "applewatch.radiowaves.left.and.right"
                    ),
                    SedentaryGuidanceItem(
                        title: "先做什么",
                        detail: "继续佩戴设备并保持健康同步，等样本补齐后，这里会自动开始给出时段和建议。",
                        symbol: "arrow.triangle.2.circlepath"
                    ),
                    SedentaryGuidanceItem(
                        title: "最近规律",
                        detail: historySummary,
                        symbol: "clock.badge"
                    )
                ]
            )
        case .unavailable:
            return SedentaryInsightContent(
                cardTitle: "暂时无法判断久坐状态",
                cardSummary: "当前数据暂不可用，请确认健康权限和 Apple Watch 同步状态，稍后会自动重试。",
                cardValueText: "异常",
                cardValueUnit: "",
                dashboardActionTitle: "先等同步恢复",
                dashboardActionDetail: "等久坐状态重新稳定下来后，这里会恢复今天的节律建议和打断入口。",
                breakSectionTitle: "同步恢复后再开始打断",
                breakSectionDetail: "因为当前状态不稳定，现在不建议直接开始打断流程，等数据恢复后再看会更准。",
                historySummary: historySummary,
                guidanceTitle: "恢复同步前先排查",
                guidanceItems: [
                    SedentaryGuidanceItem(
                        title: "先看哪里",
                        detail: "优先确认健康权限、手表连接和健康 App 同步是否正常，这三个环节最容易让久坐状态暂时失联。",
                        symbol: "exclamationmark.icloud.fill"
                    ),
                    SedentaryGuidanceItem(
                        title: "这段时间怎么处理",
                        detail: "在同步恢复前，先按常识每 30 到 60 分钟主动起身一次，比完全等数据更稳妥。",
                        symbol: "figure.stand"
                    ),
                    SedentaryGuidanceItem(
                        title: "最近规律",
                        detail: historySummary,
                        symbol: "clock.badge"
                    )
                ]
            )
        case .ready:
            if state.isCounting {
                let breakMinutes = SedentaryBreakProgressState.defaultTargetMinutes(for: state)
                let nextReminderText = state.reminderSummaryText(remindersEnabled: remindersEnabled)
                let focusSessionText: String
                if let focusSession = summary.focusSession, focusSession.isOngoing {
                    focusSessionText = "当前这段已经是今天最需要处理的一段。"
                } else if summary.longestSessionMinutes > 0 {
                    focusSessionText = "今天最长一段已经坐了 \(summary.longestSessionMinutes.bbFormattedDurationCompact)，更适合尽量别让当前这段继续追上它。"
                } else {
                    focusSessionText = "这会儿先把当前这段拆开，会比单看累计时间更有帮助。"
                }
                return SedentaryInsightContent(
                    cardTitle: "现在适合做一次短打断",
                    cardSummary: remindersEnabled
                        ? "已经连续坐了 \(state.elapsedMinutes) 分钟，建议马上起身活动 \(breakMinutes) 分钟。"
                        : "已经连续坐了 \(state.elapsedMinutes) 分钟，提醒虽然关着，但现在仍然值得主动起身一次。",
                    cardValueText: "\(state.elapsedMinutes)",
                    cardValueUnit: "min",
                    dashboardActionTitle: "已连续坐了 \(state.elapsedMinutes) 分钟",
                    dashboardActionDetail: "先做一次 \(breakMinutes) 分钟的短打断最划算，今天累计久坐 \(summary.totalSedentaryMinutes.bbFormattedDurationCompact)。",
                    breakSectionTitle: "这会儿最值得先起身一次",
                    breakSectionDetail: "不用等到更久再处理。先把这段长坐拆开，今天后面的节律通常会更稳一点。",
                    historySummary: historySummary,
                    guidanceTitle: "现在怎么拆这段久坐",
                    guidanceItems: [
                        SedentaryGuidanceItem(
                            title: "当前判断",
                            detail: "你已经连续坐了 \(state.elapsedMinutes) 分钟，\(state.elapsedMinutes >= 90 ? "这段久坐已经偏长" : "现在正是最适合提前打断的时候")。\(focusSessionText)",
                            symbol: state.elapsedMinutes >= 90 ? "exclamationmark.triangle.fill" : "figure.seated.side"
                        ),
                        SedentaryGuidanceItem(
                            title: "推荐动作",
                            detail: "先做 \(breakMinutes) 分钟 \(preferredBreakText)，\(remindersEnabled ? "下一次提醒阈值在 \(nextReminderText)" : "提醒目前已关闭，建议靠主动起身来兜底")。",
                            symbol: preferredBreakKind?.symbol ?? "figure.walk.motion"
                        ),
                        SedentaryGuidanceItem(
                            title: "规律提示",
                            detail: "你更容易在\(todayFocusText)形成长坐段。\(historySummary)",
                            symbol: "clock.badge"
                        )
                    ]
                )
            }

            if summary.totalSedentaryMinutes > 0 {
                return SedentaryInsightContent(
                    cardTitle: "身体正处在活动状态",
                    cardSummary: remindersEnabled
                        ? "当前已经从上一段久坐里出来了，继续保持打断节奏就好。"
                        : "当前虽然在活动中，但久坐提示是关闭的；如果怕忘，可以在详情页重新打开提醒。",
                    cardValueText: "活动中",
                    cardValueUnit: "",
                    dashboardActionTitle: "现在已经从久坐里缓出来了",
                    dashboardActionDetail: "今天最长一段是 \(summary.longestSessionMinutes.bbFormattedDurationCompact)，后面只要继续拆掉类似时段就行。",
                    breakSectionTitle: "当前不需要再额外开始打断",
                    breakSectionDetail: "你已经处在活动状态，更适合回看今天最久的那一段，想想它通常出现在什么时间。",
                    historySummary: historySummary,
                    guidanceTitle: "当前更适合复盘",
                    guidanceItems: [
                        SedentaryGuidanceItem(
                            title: "当前状态",
                            detail: "你已经从上一段久坐里出来了，现在不需要为了完成任务再强行开始一次打断。",
                            symbol: "figure.walk.motion"
                        ),
                        SedentaryGuidanceItem(
                            title: "今天重点",
                            detail: "今天最长一段是 \(summary.longestSessionMinutes.bbFormattedDurationCompact)，更值得关注的是它为什么会出现在\(todayFocusText)。",
                            symbol: "timeline.selection"
                        ),
                        SedentaryGuidanceItem(
                            title: "接下来留意",
                            detail: remindersEnabled
                                ? historySummary
                                : "久坐提醒现在是关闭的，后面如果工作一忙，建议记得手动给自己留一个起身点。",
                            symbol: remindersEnabled ? "clock.badge" : "bell.slash"
                        )
                    ]
                )
            }

            return SedentaryInsightContent(
                cardTitle: "今天还没有形成久坐段",
                cardSummary: "当前节律还比较干净，后面一旦出现连续久坐，这里会马上告诉你该不该起身。",
                cardValueText: "活动中",
                cardValueUnit: "",
                dashboardActionTitle: "先把现在的活动节律保持住",
                dashboardActionDetail: "等今天开始出现更长的静坐段后，这里会用分布条和建议帮你快速判断要不要打断。",
                breakSectionTitle: "当前不需要专门安排打断",
                breakSectionDetail: "现在更像是在预防阶段，继续保持站起、走动和小活动，通常就够了。",
                historySummary: historySummary,
                guidanceTitle: "预防阶段建议",
                guidanceItems: [
                    SedentaryGuidanceItem(
                        title: "当前状态",
                        detail: "今天还没有形成可识别的长坐段，说明现在的活动节律还比较干净。",
                        symbol: "checkmark.circle.fill"
                    ),
                    SedentaryGuidanceItem(
                        title: "保持方式",
                        detail: "继续维持小步走动、接水、站起回复消息这类短动作，通常就足以避免很快堆成长坐。",
                        symbol: "figure.stand"
                    ),
                    SedentaryGuidanceItem(
                        title: "最近规律",
                        detail: historySummary,
                        symbol: "clock.badge"
                    )
                ]
            )
        }
    }

    static func makeSedentaryHistoryInsight(summaries: [SedentaryDaySummary]) -> String {
        let history = summaries
            .filter { !Calendar.current.isDateInToday($0.date) && $0.sourceStatus == .ready }
            .filter { !$0.sessions.isEmpty }

        guard !history.isEmpty else {
            return String(localized: "继续同步几天后，这里会开始总结你更容易久坐的时段，以及哪种打断方式最适合你。")
        }

        let averageBreaks = Double(history.reduce(0) { $0 + $1.activeBreakCount }) / Double(history.count)
        let focusBucket = SedentaryDaySummary.preferredSedentaryDaypart(in: history)?.title ?? "白天"

        if averageBreaks >= 2 {
            return String(localized: "最近几天最需要留意的是\(focusBucket)那一段，不过你的打断频率已经有基础了，接下来更适合把第一段长坐提早拆开。")
        }

        return String(localized: "最近几天的久坐更常堆在\(focusBucket)，而且打断还不算稳定，先把那一段变成固定起身点会最有帮助。")
    }

    static func makeSedentaryHistoryTakeaway(for day: SedentaryDaySummary) -> String {
        switch day.sourceStatus {
        case .needsAuthorization:
            return String(localized: "这一天缺少健康权限，系统没法把久坐重点和打断节律还原出来。")
        case .noData:
            return String(localized: "这一天还没有足够样本，先把同步补齐，后面的时段判断才会更完整。")
        case .unavailable:
            return String(localized: "这一天的日志暂时不可用，等同步恢复后再回来复盘会更准。")
        case .ready:
            guard let focusSession = day.focusSession else {
                return String(localized: "这一天没有形成明显久坐段，整体节律算比较稳。")
            }

            let daypart = daypartLabel(for: focusSession.start)
            if let breakKind = day.dominantBreakKind {
                return String(localized: "这一天最需要留意的是\(daypart)这段，最长久坐 \(day.longestSessionMinutes.bbFormattedDurationCompact)，后来主要靠\(breakKind.title)把它拆开。")
            }

            return String(localized: "这一天的重点还是\(daypart)这段，最长一段坐了 \(day.longestSessionMinutes.bbFormattedDurationCompact)，下次更适合提前安排一次短打断。")
        }
    }

}
