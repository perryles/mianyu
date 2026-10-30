/// SleepDetailSheetView 由睡眠入口调用，作为「睡眠详情」弹层。
/// 负责展示睡眠阶段图、鼾声评分、环境洞察、节律训练进度与分享功能。

import SwiftUI
import Charts
import Foundation
import UIKit

private func sleepSafeUnit(_ value: CGFloat, minimum: CGFloat = 0) -> CGFloat {
    guard value.isFinite else { return minimum }
    return min(1, max(minimum, value))
}

private func sleepSafeUnit(_ value: Double, minimum: Double = 0) -> Double {
    guard value.isFinite else { return minimum }
    return min(1, max(minimum, value))
}

enum SleepDetailContentState: Equatable {
    case loading
    case empty
    case content

    nonisolated static func resolve(
        sleepDurationMinutes: Int?,
        summaryDurationMinutes: Int?
    ) -> Self {
        if (sleepDurationMinutes ?? 0) > 0 || (summaryDurationMinutes ?? 0) > 0 {
            return .content
        }
        return sleepDurationMinutes == nil ? .loading : .empty
    }
}

enum SleepNightSummarySelection {
    nonisolated static func latestByDay(
        _ summaries: [SleepTrendNightSummary],
        calendar: Calendar
    ) -> [Date: SleepTrendNightSummary] {
        Dictionary(
            summaries.map { (calendar.startOfDay(for: $0.day), $0) },
            uniquingKeysWith: { earlier, later in
                earlier.endTime >= later.endTime ? earlier : later
            }
        )
    }
}

/// 睡眠视图 由上级页面或路由调用，作为睡眠模块里的界面或内容组件。
/// 负责展示睡眠记录、恢复分析以及睡眠与其他指标的关联。
struct SleepDetailSheetView: View {
    @Bindable var viewModel: SleepViewModel
    let showsDismissButton: Bool
    @AppStorage("app_font_scale_level") private var appFontScaleLevelRaw: Int = 2

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 分段卡入场动画状态：图标缩放淡入 + 占比条从 0 展开（仅非文字元素，文字保持静态）。
    @State private var sleepSegmentsAnimated = false
    /// 页面级内容入场动画：节律进度条、阶段占比条等非文字元素从 0 展开。
    @State private var pageContentAnimated = false
    /// 无阶段数据时的收缩说明是否展开。
    @State private var showStageEmptyDetail = false
    /// 无睡眠心率数据时的收缩说明是否展开。
    @State private var showHeartRateEmptyDetail = false
    @GestureState private var horizontalDragOffset: CGFloat = 0
    @State private var sleepStageShareItems: [Any] = []
    @State private var showingSleepStageShare = false
    @State private var showingSnoreReport = false
    @AppStorage("sleepRhythmTrainingMode") private var selectedRhythmModeRaw: String = SleepRhythmTrainingMode.rhythmTraining.rawValue
    @AppStorage("sleepRhythmProgramStartDate") private var rhythmProgramStartDate: String = ""
    @AppStorage("sleepRhythmCompletedDayKeys") private var rhythmCompletedDayKeysRaw: String = ""
    /// 节律重建默认只展示今晚最重要的信息，完整计划由用户主动展开。
    @State private var showRhythmRebuildDetails = false

    /// 背景延伸量与 Hero 内容补偿共用，避免顶部按钮再次被裁切。
    private let heroTopExtension: CGFloat = 20
    private static let tint = Color(hex: "4FA98B")
    private static let accent = Color(hex: "86E4E5")

    private var appFontScaleLevel: AppFontScaleLevel {
        AppFontScaleLevel(rawValue: appFontScaleLevelRaw) ?? .two
    }

    /// 今日页可能先恢复到持久化的昨夜摘要，再完成 HealthKit 明细查询。
    /// 摘要已经存在时直接用于首屏展示，避免被零时长的临时 sleepData
    /// 错判为“没有睡眠记录”。
    private var resolvedDisplaySleepData: SleepData? {
        if let data = viewModel.sleepData, data.duration_minutes > 0 {
            return data
        }
        guard let summary = viewModel.latestSleepSummary,
              summary.sleepDurationMinutes > 0 else {
            return nil
        }
        return SleepData(
            sleep_score: summary.sleepScore,
            duration_minutes: summary.sleepDurationMinutes,
            stages: [],
            avg_heart_rate: nil,
            avg_respiration_rate: nil,
            awake_count: nil,
            start_time: Int(summary.startTime.timeIntervalSince1970),
            end_time: Int(summary.endTime.timeIntervalSince1970)
        )
    }

    /// 睡眠详情始终使用同一套页面结构。数据尚未同步时以空摘要驱动各模块的
    /// 自身占位状态，而不是把用户切换到另一张“无数据页面”。
    private var displaySleepData: SleepData {
        resolvedDisplaySleepData ?? SleepData(
            sleep_score: 0,
            duration_minutes: 0,
            stages: [],
            avg_heart_rate: nil,
            avg_respiration_rate: nil,
            awake_count: nil,
            start_time: nil,
            end_time: nil
        )
    }

    private var contentState: SleepDetailContentState {
        SleepDetailContentState.resolve(
            sleepDurationMinutes: viewModel.sleepData?.duration_minutes,
            summaryDurationMinutes: viewModel.latestSleepSummary?.sleepDurationMinutes
        )
    }

    var body: some View {
        let data = displaySleepData

        NavigationStack {
            ZStack {
                HealthDetailPageBackground(
                    topGlow: Color(hex: "DCEFE8"),
                    lowerGlow: Color(hex: "E6EAF5"),
                    topGlowOpacity: 0.58,
                    lowerGlowOpacity: 0.46
                )
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        sleepSignalHero(data: data)
                            .padding(.top, -heroTopExtension)
                        sleepOverviewSection(data: data)

                        if contentState == .loading {
                            loadingCard
                        } else if contentState == .empty {
                            emptyState
                        } else {
                            stageAnalysisOverviewCard(data: data)
                            sleepSegmentsCard()
                            stagesCard(data: data)
                            lateNightCalendarCard()
                            rhythmCard(data: data)
                            rhythmRebuildSystemCard(data: resolvedDisplaySleepData)
                            detailAnalysisCard(data: data)
                            sleepHeartRateCard()
                        }

                        snoreAnalysisCard(data: data)
                        metricDisclaimerCard
                    }
                    .padding(.horizontal, Theme.Layout.padding)
                    .padding(.top, 0)
                    .padding(.bottom, 96)
                }
                .ignoresSafeArea(edges: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.Colors.textPrimary)
        .offset(x: showsDismissButton ? max(0, horizontalDragOffset) : 0)
        .gesture(showsDismissButton ? swipeToDismissGesture : nil)
        .onAppear {
            printSleepDebugData(viewModel: viewModel)
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.6)) {
                    pageContentAnimated = true
                }
            } else {
                pageContentAnimated = true
            }
            if viewModel.sleepData == nil {
                viewModel.loadData()
            }
        }
        .sheet(isPresented: $showingSleepStageShare) {
            ActivityShareSheet(items: sleepStageShareItems)
        }
        .sheet(isPresented: $showingSnoreReport) {
            SnoreAnalysisPage(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    private func sleepSignalHero(data: SleepData) -> some View {
        let hasSleepData = data.duration_minutes > 0
        let boundaryTimes = sleepBoundaryTimeTexts(data: data)
        let durationValue = hasSleepData ? durationText(minutes: data.duration_minutes) : "--"
        let scoreText = data.sleep_score > 0 ? "\(data.sleep_score) 分" : "等待样本"
        let description = hasSleepData
            ? "\(sleepReportDateText(data: data)) · \(boundaryTimes.bedtime)–\(boundaryTimes.wakeTime)"
            : "完成一次完整睡眠并保持健康数据同步，昨夜报告会自动出现在这里。"

        return ModernSignalSheetHero(
            eyebrow: String(localized: "夜间恢复"),
            title: String(localized: "睡眠"),
            value: durationValue,
            unit: "",
            state: data.sleep_score > 0 ? sleepQualityText(data.sleep_score) : String(localized: "等待数据"),
            description: description,
            progress: sleepSafeUnit(Double(data.sleep_score) / 100),
            tint: Self.tint,
            symbol: "moon.stars.fill",
            pills: [
                ModernSignalHeroPill(
                    symbol: "bed.double.fill",
                    text: hasSleepData ? "卧床 \(headerInBedMinutes(data: data).map(durationText(minutes:)) ?? "--")" : "卧床时间"
                ),
                ModernSignalHeroPill(symbol: "sparkles", text: scoreText),
                ModernSignalHeroPill(
                    symbol: "heart.fill",
                    text: averageHeartRateText(data: data) == "--" ? "夜间心率" : "心率 \(averageHeartRateText(data: data))"
                )
            ],
            contentTopPadding: 38 + heroTopExtension,
            onClose: { dismiss() }
        )
    }

    private func sleepOverviewSection(data: SleepData) -> some View {
        let deepMinutes = stageMinutes(stage: "Deep", stages: data.stages)
        let deepRatio = sleepSafeUnit(Double(deepMinutes) / Double(max(1, data.stageDistributionTotalMinutes)))

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("昨夜概览")
                    .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer(minLength: 8)
                Text(data.duration_minutes > 0 ? "已整理" : "等待样本")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Self.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Self.tint.opacity(0.10), in: Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.top, 17)
            .padding(.bottom, 14)

            Divider()
                .overlay(Theme.Colors.textTertiary.opacity(0.10))
                .padding(.horizontal, 18)

            HStack(alignment: .top, spacing: 0) {
                sleepOverviewMetric(
                    title: "睡眠评分",
                    value: data.sleep_score > 0 ? "\(data.sleep_score)" : "--",
                    detail: data.sleep_score > 0 ? sleepQualityText(data.sleep_score) : "等待数据",
                    symbol: "sparkles",
                    tint: Color(hex: "8C7EEA")
                )

                sleepOverviewDivider

                sleepOverviewMetric(
                    title: "睡眠效率",
                    value: headerSleepEfficiencyText(data: data),
                    detail: "卧床与睡眠",
                    symbol: "chart.bar.fill",
                    tint: Self.tint
                )

                sleepOverviewDivider

                sleepOverviewMetric(
                    title: "深睡比例",
                    value: deepMinutes > 0 ? localizedPercentRatio(deepRatio) : "--",
                    detail: deepMinutes > 0 ? "阶段样本" : "等待阶段",
                    symbol: "moon.zzz.fill",
                    tint: Color(hex: "6E84F7")
                )
            }
            .padding(.vertical, 16)
        }
        .modernReportPanelSurface()
    }

    private func sleepOverviewMetric(title: String, value: String, detail: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 11, weight: .bold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Text(value)
                .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(detail)
                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    private var sleepOverviewDivider: some View {
        Rectangle()
            .fill(Theme.Colors.textTertiary.opacity(0.12))
            .frame(width: 1, height: 62)
    }

    private var swipeToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($horizontalDragOffset) { value, state, _ in
                guard value.startLocation.x <= 36 else { return }
                guard value.translation.width > 0 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard value.startLocation.x <= 36 else { return }
                guard value.translation.width > 90 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dismiss()
            }
    }

    private func headerInBedMinutes(data: SleepData) -> Int? {
        if let interval = viewModel.sleepInterval {
            let minutes = Int((interval.end.timeIntervalSince(interval.start) / 60).rounded())
            return minutes > 0 ? minutes : nil
        }
        let awakeMinutes = stageMinutes(stage: "Awake", stages: data.stages)
        guard data.duration_minutes > 0, awakeMinutes > 0 else { return nil }
        return data.duration_minutes + awakeMinutes
    }

    private func headerSleepEfficiencyText(data: SleepData) -> String {
        guard let inBed = headerInBedMinutes(data: data),
              inBed > 0,
              data.duration_minutes > 0 else { return "--" }
        return localizedPercentRatio(Double(data.duration_minutes) / Double(inBed))
    }

    private func sleepReportDateText(data: SleepData) -> String {
        let date: Date
        if let interval = viewModel.sleepInterval {
            date = interval.end
        } else if let end = data.end_time {
            date = Date(timeIntervalSince1970: TimeInterval(end))
        } else {
            date = Date()
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EMMMd")
        return formatter.string(from: date)
    }

    private func sleepQualityText(_ score: Int) -> String {
        switch score {
        case 85...: return String(localized: "优秀")
        case 72..<85: return String(localized: "良好")
        case 60..<72: return String(localized: "一般")
        case 1..<60: return String(localized: "需关注")
        default: return String(localized: "等待样本")
        }
    }

    private func sleepBoundaryTimeTexts(data: SleepData) -> (bedtime: String, wakeTime: String) {
        if let interval = viewModel.sleepInterval {
            return (timeString(interval.start), timeString(interval.end))
        }
        guard let start = data.start_time, let end = data.end_time else {
            return ("--:--", "--:--")
        }
        return (
            timeString(Date(timeIntervalSince1970: TimeInterval(start))),
            timeString(Date(timeIntervalSince1970: TimeInterval(end)))
        )
    }

    /// 今日睡眠分段：主睡眠（最长段）+ 午睡等其余段，各自显示起止与时长。
    @ViewBuilder
    private func sleepSegmentsCard() -> some View {
        let intervals = viewModel.sleepIntervals
        if !intervals.isEmpty {
            let longestMinutes = intervals.map { Int(($0.end.timeIntervalSince($0.start) / 60).rounded()) }.max() ?? 0
            let totalMinutes = intervals.reduce(0) { $0 + Int(($1.end.timeIntervalSince($1.start) / 60).rounded()) }
            VStack(alignment: .leading, spacing: 14) {
                Color.clear
                    .frame(height: 0)
                    .onAppear {
                        if !reduceMotion {
                            withAnimation(.easeOut(duration: 0.55)) {
                                sleepSegmentsAnimated = true
                            }
                        } else {
                            sleepSegmentsAnimated = true
                        }
                    }
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.appSystem(size: 12, weight: .bold))
                        .foregroundColor(Self.tint)
                        .frame(width: 24, height: 24)
                        .background(Self.tint.opacity(0.10), in: Circle())
                    Text("今日睡眠分段")
                        .font(Theme.Typography.scaled(size: 16, weight: .black, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    Text("共 \(durationText(minutes: totalMinutes))")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                ForEach(Array(intervals.enumerated()), id: \.offset) { index, interval in
                    let minutes = Int((interval.end.timeIntervalSince(interval.start) / 60).rounded())
                    let isMain = minutes >= longestMinutes
                    let segmentColor = isMain ? Self.tint : Color(hex: "F09A50")
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: isMain ? "moon.stars.fill" : "sun.max.fill")
                                .font(.appSystem(size: 15, weight: .bold))
                                .foregroundColor(segmentColor)
                                .frame(width: 38, height: 38)
                                .background(segmentColor.opacity(0.12), in: Circle())
                                .scaleEffect(sleepSegmentsAnimated ? 1 : 0.5)
                                .opacity(sleepSegmentsAnimated ? 1 : 0)
                                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7), value: sleepSegmentsAnimated)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(isMain ? "主睡眠" : "午睡")
                                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    Text("\(minutes) 分")
                                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(segmentColor)
                                }
                                Text("\(timeString(interval.start)) - \(timeString(interval.end))")
                                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }
                            Spacer()
                        }

                        // 各段相对最长段的时长占比条（静态展示，不加动效）
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.Colors.textTertiary.opacity(0.10))
                                Capsule()
                                    .fill(segmentColor.opacity(0.75))
                                    .frame(width: sleepSegmentsAnimated ? max(6, proxy.size.width * CGFloat(minutes) / CGFloat(max(1, longestMinutes))) : 0)
                                    .animation(reduceMotion ? nil : .easeOut(duration: 0.55), value: sleepSegmentsAnimated)
                            }
                        }
                        .frame(height: 6)
                    }
                    if index < intervals.count - 1 {
                        Divider().opacity(0.5)
                    }
                }
            }
            .detailCardSurface(tint: Self.tint)
        }
    }

    private func rhythmCard(data: SleepData) -> some View {
        SleepRhythmCard(
            data: data,
            goalMinutes: viewModel.sleepGoalMinutes,
            sleepWindowText: sleepWindowText,
            bedTimeText: bedTimeText,
            wakeTimeText: wakeTimeText,
            averageHeartRateText: averageHeartRateText(data: data),
            fontScaleLevel: appFontScaleLevel
        )
    }

    private func lateNightCalendarCard() -> some View {
        let items = lateNightWeekItems
        let lateNightCount = items.filter(\.isLateNight).count

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("熬夜日历视图")
                    .font(Theme.Typography.scaled(size: 19, weight: .bold, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                sectionBadge(lateNightCount == 0 ? "本周稳定" : "本周 \(lateNightCount) 次", tint: Theme.Colors.mintGreen)
            }

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(currentWeekRangeTitle)
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("最近 7 天")
                        .font(.appSystem(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("熬夜次数")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text("\(lateNightCount)")
                        .font(.appSystem(size: 32, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("占总天数的\(localizedPercentRatio(Double(lateNightCount) / Double(max(items.count, 1))))")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            Text("用于快速查看最近一周是否出现晚于 1:00 的入睡记录。")
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                ForEach(items) { item in
                    VStack(spacing: 8) {
                        Text(item.weekday)
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)

                        Circle()
                            .fill(item.isLateNight ? Theme.Colors.pastelYellow : Theme.Colors.secondarySurface)
                            .frame(width: 40, height: 40)
                            .overlay {
                                if item.isLateNight {
                                    Image(systemName: "moon.stars.fill")
                                        .font(.appSystem(size: 14, weight: .bold))
                                        .foregroundColor(Theme.Colors.textPrimary)
                                } else {
                                    Text(item.dayText)
                                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                                        .foregroundColor(Theme.Colors.textPrimary)
                                }
                            }

                        Text(item.bedtimeText)
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text(item.isLateNight ? item.lateNightScoreText : "-")
                            .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(item.isLateNight ? Color(hex: "D08A39") : Theme.Colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 2)

            Text(lateNightCalendarSummaryText(lateNightCount: lateNightCount))
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .detailCardSurface(tint: Theme.Colors.mintGreen)
    }

    private func rhythmRebuildSystemCard(data: SleepData?) -> some View {
        let mode = selectedRhythmMode
        let plan = viewModel.makeRhythmRebuildPlan(mode: mode, data: data)
        let protection = rhythmProtectionSummary(mode: mode, plan: plan)
        let completedIDs = protection.completedStepIDs
        let completedCount = plan.routineSteps.filter { completedIDs.contains($0.id) }.count
        let trainingDay = protection.dayIndex
        let trainingProgress = sleepSafeUnit(CGFloat(protection.progress))
        let isTodayCompleted = protection.completedDayKeys.contains(routineProgressDayKey(Date()))
        let targetBedtimeForTonight = protection.targetBedtime
        let targetOffset = protection.targetOffsetMinutes
        let primaryAction = plan.actions.first ?? "按目标时间准备入睡"

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("节律重建")
                        .font(Theme.Typography.scaled(size: 17, weight: .black, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(data?.duration_minutes ?? 0 > 0 ? "今晚只做最关键的一步" : "先从固定睡眠窗口开始")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Spacer(minLength: 0)

                sectionBadge(plan.headline, tint: Self.tint)
            }

            Picker("", selection: selectedRhythmModeBinding) {
                ForEach(rhythmRebuildModes) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedRhythmModeRaw) { _, _ in
                rhythmProgramStartDate = routineProgressDayKey(Date())
                rhythmCompletedDayKeysRaw = ""
                viewModel.refreshRhythmProtectionSummary(mode: selectedRhythmMode)
            }

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("今晚目标")
                        .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(targetBedtimeForTonight.map(timeString) ?? "23:30")
                        .font(.appSystem(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(Self.tint)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(plan.score.map { "节律 \($0) 分" } ?? "等待完整样本")
                    Text("第 \(trainingDay) / \(plan.estimatedDays) 天")
                }
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Self.tint.opacity(0.12), Self.accent.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: mode.systemImageName)
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundColor(Self.tint)
                    .frame(width: 30, height: 30)
                    .background(Self.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("今晚先做")
                        .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(primaryAction)
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Theme.Colors.secondaryBackground)
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(LinearGradient(colors: [Self.tint, Self.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * trainingProgress * CGFloat(pageContentAnimated ? 1 : 0))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: pageContentAnimated)
                }
            }
            .frame(height: 7)

            Button {
                viewModel.toggleRhythmProtectionToday(mode: mode)
            } label: {
                Label(isTodayCompleted ? "今日已完成" : "完成今日训练", systemImage: isTodayCompleted ? "checkmark.seal.fill" : "checkmark.circle")
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(isTodayCompleted ? Color(hex: "35C759") : Self.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background((isTodayCompleted ? Color(hex: "35C759") : Self.tint).opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                showRhythmRebuildDetails.toggle()
            } label: {
                HStack {
                    Text(showRhythmRebuildDetails ? "收起完整计划" : "查看完整计划")
                    Spacer()
                    Image(systemName: showRhythmRebuildDetails ? "chevron.up" : "chevron.down")
                }
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            if showRhythmRebuildDetails {
                Divider()
                    .overlay(Color.black.opacity(0.05))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("调整今晚目标")
                                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(targetOffset == 0 ? "当前使用系统建议" : "已\(targetOffset > 0 ? "延后" : "提前") \(abs(targetOffset)) 分钟")
                                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        Spacer()
                        Text(targetBedtimeForTonight.map(timeString) ?? "23:30")
                            .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(Self.tint)
                    }

                    HStack(spacing: 10) {
                        targetAdjustButton(title: "提前 15 分", delta: -15, mode: mode)
                        targetAdjustButton(title: "重置", delta: nil, mode: mode)
                        targetAdjustButton(title: "延后 15 分", delta: 15, mode: mode)
                    }
                }

                rhythmCompletionTrail(totalDays: plan.estimatedDays)

                if mode == .lateNightRecovery || mode == .travelReset {
                    rhythmProtectionControl(summary: protection, mode: mode)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("其余行动")
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    ForEach(Array(plan.actions.dropFirst().prefix(2).enumerated()), id: \.offset) { index, action in
                        rhythmActionRow(index: index + 2, text: action)
                    }
                }

                rhythmRescueNote(title: plan.rescueTitle, detail: plan.rescueDetail)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("今晚锚点")
                            .font(.appSystem(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Text("\(completedCount)/\(plan.routineSteps.count)")
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Self.tint)
                    }

                    ForEach(plan.routineSteps.prefix(3)) { step in
                        routineAnchorStep(
                            step: step,
                            targetBedtime: targetBedtimeForTonight,
                            isCompleted: completedIDs.contains(step.id),
                            mode: mode
                        )
                    }
                }

                Button {
                    viewModel.startRhythmProtectionPlan(mode: mode)
                } label: {
                    Label("重新开始计划", systemImage: "arrow.counterclockwise")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.Colors.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Text("计划只调整今晚的行为安排，不会改写健康数据或睡眠评分。")
                    .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .onAppear {
            if selectedRhythmModeRaw == SleepRhythmTrainingMode.bedtimeRoutine.rawValue {
                selectedRhythmModeRaw = SleepRhythmTrainingMode.rhythmTraining.rawValue
            }
            ensureRhythmProgramStarted()
            viewModel.refreshRhythmProtectionSummary(mode: selectedRhythmMode)
        }
        .detailCardSurface(tint: Self.tint)
    }

    private func stagesCard(data: SleepData) -> some View {
        SleepStagesSummaryCard(
            data: data,
            sleepInterval: viewModel.sleepInterval,
            fontScaleLevel: appFontScaleLevel,
            tint: Self.tint,
            accent: Self.accent,
            onShare: {
                sleepStageShareItems = [sleepStageShareText(data: data)]
                showingSleepStageShare = true
            }
        )
    }

    private func stageAnalysisOverviewCard(data: SleepData) -> some View {
        let awakeMinutes = stageMinutes(stage: "Awake", stages: data.stages)
        let coreMinutes = stageMinutes(stage: "Core", stages: data.stages)
        let deepMinutes = stageMinutes(stage: "Deep", stages: data.stages)
        let remMinutes = stageMinutes(stage: "REM", stages: data.stages)
        let stageDistributionTotalMinutes = data.stageDistributionTotalMinutes
        let hasStageData = !data.stages.isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("睡眠阶段分析")
                        .font(Theme.Typography.scaled(size: 16, weight: .black, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("总览昨夜清醒、快速眼动、核心睡眠和深度睡眠的分布，先看结构，再看细节。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                sectionBadge(stageOverviewSummaryText(data), tint: Color(hex: "6E84F7"))
            }

            if hasStageData {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                stageHighlightCard(
                    title: "清醒时间",
                    minutes: awakeMinutes,
                    ratio: stageRatio(stage: "Awake", stages: data.stages, totalMinutes: stageDistributionTotalMinutes),
                    tint: Color(hex: "E8EAEC")
                )
                NavigationLink {
                    REMAnalysisView()
                } label: {
                    stageHighlightCard(
                        title: "快速眼动",
                        minutes: remMinutes,
                        ratio: stageRatio(stage: "REM", stages: data.stages, totalMinutes: stageDistributionTotalMinutes),
                        tint: Theme.Colors.pastelYellow,
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
                stageHighlightCard(
                    title: "核心睡眠",
                    minutes: coreMinutes,
                    ratio: stageRatio(stage: "Core", stages: data.stages, totalMinutes: stageDistributionTotalMinutes),
                    tint: Theme.Colors.pastelGreen
                )
                NavigationLink {
                    DeepSleepAnalysisView()
                } label: {
                    stageHighlightCard(
                        title: "深度睡眠",
                        minutes: deepMinutes,
                        ratio: stageRatio(stage: "Deep", stages: data.stages, totalMinutes: stageDistributionTotalMinutes),
                        tint: Theme.Colors.pastelCyan,
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
            }
            } else {
                stageAnalysisCollapsedEmptyState
            }

        }
        .detailCardSurface(tint: Color(hex: "6E84F7"))
    }

    /// 无睡眠阶段样本时的收缩展示（如仅有 inBed 记录、没有 asleep/阶段明细）：
    /// 默认一行提示，点击展开说明；有真实阶段数据时仍显示 4 宫格。
    private var stageAnalysisCollapsedEmptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showStageEmptyDetail.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "6E84F7"))
                    Text("暂无睡眠阶段数据")
                        .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    Image(systemName: showStageEmptyDetail ? "chevron.up" : "chevron.down")
                        .font(.appSystem(size: 12, weight: .bold))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .rotationEffect(.degrees(showStageEmptyDetail ? 180 : 0))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showStageEmptyDetail)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showStageEmptyDetail {
                Text("当前只获取到睡眠时长，还没有阶段明细。佩戴 Apple Watch 或由健康 App 记录完整睡眠后，这里会展示清醒、快速眼动、核心与深度四阶段的分布与占比。")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailAnalysisCard(data: SleepData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("睡眠生命体征")
                        .font(Theme.Typography.scaled(size: 16, weight: .black, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("结合评分、主睡眠时长、夜间心率、呼吸频率和体温变化，快速看昨夜恢复状态。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if sleepVitalAbnormalCount > 0 {
                    sectionBadge("\(sleepVitalAbnormalCount) 个异常值", tint: Self.tint)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    SleepVitalStatusOrb(
                        score: data.sleep_score,
                        durationMinutes: data.duration_minutes,
                        statusTitle: detailStatusTitle,
                        statusColor: detailStatusColor,
                        progress: detailStatusProgress
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        detailMetricPill(title: "主睡眠", value: durationText(minutes: data.duration_minutes), unit: "", tint: Self.tint)
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 12
                        ) {
                            detailMetricPill(title: "平均心率", value: detailHeartRateValue(data), unit: "次/分", tint: Color(hex: "D96563"))
                            detailMetricPill(title: "呼吸频率", value: sleepRespirationText, unit: "次/分", tint: Color(hex: "57C7B6"))
                            detailMetricPill(title: "血氧", value: sleepOxygenProxyText, unit: "%", tint: Color(hex: "5A6DF3"))
                            detailMetricPill(title: "温度", value: wristTemperatureText, unit: "°C", tint: Color(hex: "8A77F7"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.appSystem(size: 16, weight: .bold))
                                .foregroundColor(detailStatusColor)
                            Text(detailStatusTitle)
                                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                                .foregroundColor(detailStatusColor)
                        }

                        Text(detailStatusDescription(data))
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(detailStatusColor.opacity(0.18))
                        .frame(width: 112, height: 16)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(detailStatusColor)
                                .frame(width: 112 * sleepSafeUnit(detailStatusProgress, minimum: 0.18))
                                .overlay {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 14, height: 14)
                                }
                        }
                }
            }

            Text("继续往下可以看睡眠规律、熬夜日历、睡眠阶段与睡眠心率的更细拆解。")
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .detailCardSurface(tint: Color(hex: "6E84F7"))
    }

    /// 无睡眠心率数据时的收缩展示：默认一行提示，点击展开说明。
    private var sleepHeartRateCollapsedEmptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showHeartRateEmptyDetail.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.slash")
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "FF5F7A"))
                    Text("暂无昨晚睡眠心率")
                        .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    Image(systemName: showHeartRateEmptyDetail ? "chevron.up" : "chevron.down")
                        .font(.appSystem(size: 12, weight: .bold))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .rotationEffect(.degrees(showHeartRateEmptyDetail ? 180 : 0))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showHeartRateEmptyDetail)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showHeartRateEmptyDetail {
                Text("没有匹配到睡眠时段内的心率记录。佩戴 Apple Watch 或由健康 App 记录心率后，这里会展示入睡后到醒来前的真实心率波动。")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sleepHeartRateCard() -> some View {
        let data = heartRateChartData()

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("睡眠心率")
                        .font(Theme.Typography.scaled(size: 17, weight: .black, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("观察入睡后到醒来前的真实心率波动，重点看整体趋势是否平稳。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                sectionBadge("睡眠心率", tint: Color(hex: "FF5F7A"))
            }

            if data.isEmpty {
                sleepHeartRateCollapsedEmptyState
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        heartRateContextPill(title: "入睡区间", value: sleepWindowText)
                        heartRateContextPill(title: "波动幅度", value: heartRateSpreadText(from: data))
                        heartRateContextPill(title: "样本数", value: heartRateSampleCountText(from: data))
                    }

                    Chart(data) { point in
                        LineMark(
                            x: .value("时间", point.date),
                            y: .value("BPM", point.value)
                        )
                        .foregroundStyle(Color(hex: "FF5F7A"))
                        .lineStyle(StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("时间", point.date),
                            y: .value("BPM", point.value)
                        )
                        .foregroundStyle(Color(hex: "FF5F7A").opacity(0.15))
                        .interpolationMethod(.catmullRom)
                    }
                    .frame(height: 220)
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(Color(hex: "FFF3F5").opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .chartLegend(.hidden)
                    .chartYScale(domain: heartRateChartDomain(from: data))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
                            AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) {
                            AxisGridLine()
                                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.18))
                            AxisValueLabel()
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    HStack {
                        Text("入睡后")
                        Spacer()
                        Text("夜里")
                        Spacer()
                        Text("醒来前")
                    }
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                }
                .padding(16)
                .background(Theme.Colors.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }

            insightRibbon(icon: "heart.fill", text: heartRateInsightText(from: data))

            if !data.isEmpty {
                Text("睡眠心率更适合用来看趋势和波动幅度，不需要把每次小起伏都解读成异常。")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .detailCardSurface(tint: Color(hex: "FF5F7A"))
    }

    /// 「鼾声内容」卡保持精简：只保留状态徽章、一行摘要与整夜分布直方图。
    /// 完整的鼾声分析模块（报告/事件/趋势/历史）从今日页夜间恢复区入口进入。
    private func snoreAnalysisCard(data: SleepData) -> some View {
        let summary = viewModel.latestSleepSummary?.snoreSummary
        let snoreDetected = summary?.snoreDetected ?? false
        let intensity = summary?.intensity ?? .none
        let histogram = summary?.histogram ?? Array(repeating: 0, count: 6)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("鼾声内容")
                        .font(Theme.Typography.scaled(size: 19, weight: .bold, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(snoreDetected
                         ? "昨夜已经整理出本地鼾声摘要。"
                         : "当前还没有明显鼾声摘要，开启夜间本地检测后会逐步形成分布。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer()
                sectionBadge(snoreDetected ? intensity.title : "待检测", tint: Theme.Colors.mintGreen)
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(histogram.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(value > 0 ? Theme.Colors.pastelCyan : Theme.Colors.secondarySurface)
                            .frame(width: 28, height: max(18, CGFloat(value) * 12))
                        Text(snoreBucketTitle(index))
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .detailCardSurface(tint: Theme.Colors.mintGreen)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { showingSnoreReport = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("打开鼾声分析")
    }





    private var metricDisclaimerCard: some View {
        HealthDisclaimerCard(
            message: "本页睡眠时长、睡眠阶段、夜间心率与恢复解读仅供日常自我管理参考，不构成医疗诊断或治疗建议。若长期失眠、夜间频繁觉醒、白天困倦明显或需要做出重要健康决定，请咨询专业医生。",
            strokeColor: Self.accent.opacity(0.14)
        )
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Self.tint)
            Text("正在整理昨夜睡眠数据")
                .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .detailCardSurface(tint: Self.tint)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.appSystem(size: 22, weight: .black))
                    .foregroundColor(Self.tint)
                    .frame(width: 44, height: 44)
                    .background(Self.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("等待睡眠样本")
                        .font(.appSystem(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(emptyStateSubtitle)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .top, spacing: 0) {
                emptyStateStatusItem(
                    title: "健康权限",
                    value: sleepAuthorizationStatusText,
                    symbol: isSleepAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    tint: isSleepAuthorized ? Color(hex: "21A66B") : Self.tint
                )
                sleepOverviewDivider
                emptyStateStatusItem(
                    title: "昨夜状态",
                    value: emptyStateNightStatusText,
                    symbol: "moon.fill",
                    tint: Color(hex: "8C7EEA")
                )
                sleepOverviewDivider
                emptyStateStatusItem(
                    title: "同步后可见",
                    value: "阶段与节律",
                    symbol: "chart.xyaxis.line",
                    tint: Color(hex: "5B8DEF")
                )
            }
            .padding(.vertical, 13)
            .background(Theme.Colors.secondarySurface.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundStyle(Self.tint)
                    .frame(width: 28, height: 28)
                    .background(Self.tint.opacity(0.09), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(emptyStatePrimaryHint)
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(emptyStateSecondaryHint)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            emptyStateSyncButton
        }
        .detailCardSurface(tint: Self.tint)
    }

    private func emptyStateStatusItem(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(value)
                .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var emptyStateSyncButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                viewModel.loadData()
            } label: {
                emptyStateSyncLabel
            }
            .buttonStyle(.glassProminent)
            .tint(Self.tint)
        } else {
            Button {
                viewModel.loadData()
            } label: {
                emptyStateSyncLabel
                    .foregroundStyle(Self.tint)
                    .background(Self.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyStateSyncLabel: some View {
        Label(isSleepAuthorized ? "重新同步昨夜睡眠" : "检查权限并同步睡眠", systemImage: "arrow.clockwise")
            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    private var emptyStateNightStatusText: String {
        viewModel.sleepInterval == nil ? "未检测" : "待同步"
    }

    private var emptyStatePrimaryHint: String {
        isSleepAuthorized ? "现在主要缺的是昨夜样本。" : "现在主要缺的是权限和昨夜样本。"
    }

    private var emptyStateSecondaryHint: String {
        if isSleepAuthorized {
            return String(localized: "如果你昨夜已经佩戴设备睡眠，但这里仍为空，通常只是健康样本还没完全同步过来。")
        }
        return String(localized: "先把睡眠读取权限打开，再完成一次睡眠或补录，页面才会开始生成结构化分析。")
    }

    private func snoreBucketTitle(_ index: Int) -> String {
        switch index {
        case 0: return "入睡"
        case 1: return "前段"
        case 2: return "夜中"
        case 3: return "后段"
        case 4: return "清晨"
        default: return "醒前"
        }
    }




    @MainActor



    private func stageHighlightCard(
        title: String,
        minutes: Int,
        ratio: Double,
        tint: Color,
        showsDisclosure: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 11, weight: .bold))
                        .foregroundColor(tint.opacity(0.72))
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(minutes)")
                    .font(.appSystem(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("分")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            HStack(spacing: 6) {
                Text("占阶段总时长的 \(localizedPercentRatio(ratio))")
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                Text(stageToneText(title: title, ratio: ratio))
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(stageToneColor(title: title, ratio: ratio))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.secondarySurface)
                    Capsule().fill(tint).frame(width: proxy.size.width * sleepSafeUnit(ratio))
                }
            }
            .frame(height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.94), Color(hex: "FAFCFF").opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .shadow(color: Color(hex: "28395A").opacity(0.045), radius: 8, y: 5)
    }

    private func detailMetricPill(title: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.appSystem(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.92), Color(hex: "FAFCFF").opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func rhythmActionRow(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(format: "%02d", index))
                .font(.appSystem(size: 10, weight: .heavy, design: .rounded))
                .foregroundColor(Color(hex: "4E8B7B"))
                .frame(width: 28, height: 28)
                .background(Color(hex: "4E8B7B").opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(text)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func rhythmProtectionSummary(mode: SleepRhythmTrainingMode, plan: SleepRhythmRebuildPlan) -> SleepRhythmProtectionSummary {
        if let summary = viewModel.sleepRhythmProtectionSummary, summary.mode == mode {
            return summary
        }
        return SleepRhythmProtectionEngine().build(
            input: SleepRhythmProtectionEngine.Input(
                mode: mode,
                plan: plan,
                record: nil,
                now: Date(),
                calendar: .current
            )
        )
    }

    private func rhythmProtectionControl(summary: SleepRhythmProtectionSummary, mode: SleepRhythmTrainingMode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: mode == .travelReset ? "airplane.circle.fill" : "moon.zzz.fill")
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundColor(Self.tint)
                    .frame(width: 30, height: 30)
                    .background(Self.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.headline)
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(summary.tonightFocus)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.ensureRhythmProtectionPlan(mode: mode)
                } label: {
                    Label(summary.isActivePlan ? "保护中" : "启动保护", systemImage: summary.isActivePlan ? "shield.checkered" : "play.circle.fill")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(summary.isActivePlan ? Color(hex: "35C759") : Self.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background((summary.isActivePlan ? Color(hex: "35C759") : Self.tint).opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.toggleRhythmProtectionReminder(!summary.reminderEnabled, mode: mode)
                } label: {
                    Label(summary.reminderEnabled ? "提醒开" : "提醒关", systemImage: summary.reminderEnabled ? "bell.fill" : "bell")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Self.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Self.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Self.tint.opacity(0.08), Color.white.opacity(0.66)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func targetAdjustButton(title: String, delta: Int?, mode: SleepRhythmTrainingMode) -> some View {
        Button {
            viewModel.adjustRhythmProtectionTargetOffset(delta, mode: mode)
        } label: {
            Text(title)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(delta == nil ? Theme.Colors.textSecondary : Self.tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background((delta == nil ? Color.black.opacity(0.04) : Self.tint.opacity(0.10)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func rhythmCompletionTrail(totalDays: Int) -> some View {
        let days = rhythmTrailDays(totalDays: totalDays)
        return HStack(spacing: 7) {
            ForEach(days) { item in
                VStack(spacing: 6) {
                    Circle()
                        .fill(item.isCompleted ? Color(hex: "35C759") : (item.isToday ? Color(hex: "4E8B7B").opacity(0.18) : Color(hex: "E6EEE9")))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if item.isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.appSystem(size: 10, weight: .black))
                                    .foregroundColor(.white)
                            } else if item.isToday {
                                Circle()
                                    .stroke(Color(hex: "4E8B7B"), lineWidth: 1.5)
                            }
                        }
                    Text(item.label)
                        .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(item.isToday ? Color(hex: "4E8B7B") : Theme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 2)
    }

    private func rhythmRescueNote(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lifepreserver.fill")
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundColor(Color(hex: "F2A357"))
                .frame(width: 28, height: 28)
                .background(Color(hex: "F2A357").opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color(hex: "FFF7E8").opacity(0.78), Color.white.opacity(0.58)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func routineAnchorStep(step: SleepRhythmRoutineStep, targetBedtime: Date?, isCompleted: Bool, mode: SleepRhythmTrainingMode) -> some View {
        Button {
            viewModel.toggleRhythmProtectionStep(step.id, mode: mode)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : step.symbol)
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundColor(isCompleted ? Color(hex: "35C759") : Self.tint)
                    .frame(width: 26, height: 26)
                    .background((isCompleted ? Color(hex: "35C759") : Self.tint).opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(step.detail)
                        .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(routineStepTimeText(step: step, targetBedtime: targetBedtime))
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Self.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Self.tint.opacity(0.09), in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sleepVitalAbnormalCount: Int {
        var count = 0
        if let rate = viewModel.nightlyRespirationRate {
            if rate >= 18.5 { count += 1 }
        }
        if let heartRate = viewModel.sleepData?.avg_heart_rate {
            if heartRate >= 72 { count += 1 }
        }
        if let temp = viewModel.sleepingWristTemperature {
            if temp >= 36.5 || temp <= 35.0 { count += 1 }
        }
        // 血氧为呼吸率推导代理值：无呼吸率数据时（代理显示 "--"/94）不得计为异常。
        if let respiration = viewModel.nightlyRespirationRate, respiration > 0 {
            let oxygen = Int(sleepOxygenProxyText) ?? 94
            if oxygen <= 94 { count += 1 }
        }
        return min(4, max(0, count))
    }

    private var selectedRhythmMode: SleepRhythmTrainingMode {
        let mode = SleepRhythmTrainingMode(rawValue: selectedRhythmModeRaw) ?? .rhythmTraining
        return mode == .bedtimeRoutine ? .rhythmTraining : mode
    }

    private var selectedRhythmModeBinding: Binding<String> {
        Binding(
            get: {
                selectedRhythmMode.rawValue
            },
            set: { newValue in
                let mode = SleepRhythmTrainingMode(rawValue: newValue) ?? .rhythmTraining
                selectedRhythmModeRaw = (mode == .bedtimeRoutine ? SleepRhythmTrainingMode.rhythmTraining : mode).rawValue
            }
        )
    }

    private var rhythmRebuildModes: [SleepRhythmTrainingMode] {
        [.rhythmTraining, .lateNightRecovery, .travelReset]
    }


    private var rhythmCompletedDayKeys: Set<String> {
        guard !rhythmCompletedDayKeysRaw.isEmpty else { return [] }
        return Set(rhythmCompletedDayKeysRaw.split(separator: ",").map(String.init))
    }



    private func ensureRhythmProgramStarted() {
        if rhythmProgramStartDate.isEmpty {
            rhythmProgramStartDate = routineProgressDayKey(Date())
        }
    }






    private func rhythmTrailDays(totalDays: Int) -> [SleepRhythmTrailDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = rhythmProgressDateFormatter()
        let total = min(max(totalDays, 1), 7)
        let start = formatter.date(from: rhythmProgramStartDate).map { calendar.startOfDay(for: $0) } ?? today
        let completed = rhythmCompletedDayKeys

        return (0..<total).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = routineProgressDayKey(date)
            return SleepRhythmTrailDay(
                id: key,
                label: "D\(offset + 1)",
                isToday: calendar.isDate(date, inSameDayAs: today),
                isCompleted: completed.contains(key)
            )
        }
    }

    private func routineProgressDayKey(_ date: Date) -> String {
        rhythmProgressDateFormatter().string(from: date)
    }

    private func rhythmProgressDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func routineStepTimeText(step: SleepRhythmRoutineStep, targetBedtime: Date?) -> String {
        guard let targetBedtime,
              let date = Calendar.current.date(byAdding: .minute, value: step.offsetMinutes, to: targetBedtime) else {
            return step.offsetMinutes == 0 ? "睡前" : "睡前 \(abs(step.offsetMinutes)) 分"
        }
        return timeString(date)
    }




    private func insightRibbon(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.appSystem(size: 14, weight: .bold))
                .foregroundColor(Self.tint)
                .frame(width: 34, height: 34)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color(hex: "32425E").opacity(0.055), radius: 8, y: 5)

            Text(text)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "7C8595"))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.90), Color(hex: "F9FCFF").opacity(0.70)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .shadow(color: Color(hex: "2F3F5C").opacity(0.07), radius: 12, y: 8)
    }

    private var isSleepAuthorized: Bool {
        // sleepAnalysis 是只读数据。HealthKit 不公开读取授权结果，不能使用
        // authorizationStatus(for:)（写入权限）判断；统一消费授权协调器状态。
        HealthAuthorizationCoordinator.shared.phase.isAuthorizedLike
    }

    private var sleepAuthorizationStatusText: String {
        isSleepAuthorized ? "已开启" : "待开启"
    }

    private var emptyStateSubtitle: String {
        if isSleepAuthorized {
            return String(localized: "健康 App 还没有整理出可用的昨夜睡眠数据，通常在完成一次完整睡眠后会自动出现。")
        }
        return String(localized: "先打开健康权限，之后佩戴 Apple Watch 睡觉，这里才会生成睡眠阶段、评分和夜间心率。")
    }

    private var sleepWindowText: String {
        guard let interval = viewModel.sleepInterval else { return "暂无时间范围" }
        return "\(timeString(interval.start)) - \(timeString(interval.end))"
    }

    private var bedTimeText: String {
        guard let interval = viewModel.sleepInterval else { return "--:--" }
        return timeString(interval.start)
    }

    private var wakeTimeText: String {
        guard let interval = viewModel.sleepInterval else { return "--:--" }
        return timeString(interval.end)
    }

    private var currentWeekRangeTitle: String {
        let calendar = Calendar.current
        let today = Date()
        let interval = calendar.dateInterval(of: .weekOfYear, for: today)
        let start = interval?.start ?? calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale.autoupdatingCurrent
        monthFormatter.setLocalizedDateFormatFromTemplate("MMM")

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale.autoupdatingCurrent
        dayFormatter.setLocalizedDateFormatFromTemplate("d")
        return "\(monthFormatter.string(from: start))\n\(dayFormatter.string(from: start)) - \(dayFormatter.string(from: end))"
    }

    private var lateNightWeekItems: [SleepLateNightCalendarItem] {
        let calendar = Calendar.current
        let today = Date()
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? calendar.startOfDay(for: today)
        let summaryByDay = SleepNightSummarySelection.latestByDay(
            viewModel.recentNightSummaries,
            calendar: calendar
        )

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let day = calendar.startOfDay(for: date)
            let summary = summaryByDay[day]
            let bedtime = summary.map { timeString($0.startTime) } ?? "-"
            let isLateNight = summary.map { lateNightSeverity(for: $0.startTime) > 0 } ?? false
            let score = summary.map { lateNightSeverity(for: $0.startTime) }
            return SleepLateNightCalendarItem(
                weekday: weekdayShortText(date),
                dayText: "\(calendar.component(.day, from: date))",
                bedtimeText: bedtime,
                lateNightScoreText: score.map { "\($0)" } ?? "-",
                isLateNight: isLateNight
            )
        }
    }


    private func averageHeartRateText(data: SleepData) -> String {
        if let rate = data.avg_heart_rate, rate > 0 {
            return "\(rate) BPM"
        }
        let values = heartRateChartData().map(\.value)
        guard !values.isEmpty else { return "等待同步" }
        let avg = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        return "\(avg) BPM"
    }

    private func detailHeartRateValue(_ data: SleepData) -> String {
        if let rate = data.avg_heart_rate, rate > 0 {
            return "\(rate)"
        }
        let values = heartRateChartData().map(\.value)
        guard !values.isEmpty else { return "--" }
        let avg = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        return "\(avg)"
    }

    private func heartRateSpreadText(from data: [TimeSeriesPoint]) -> String {
        guard let minValue = data.map(\.value).min(),
              let maxValue = data.map(\.value).max() else {
            return "--"
        }
        return "\(maxValue - minValue) bpm"
    }

    private func heartRateSampleCountText(from data: [TimeSeriesPoint]) -> String {
        data.isEmpty ? "--" : "\(data.count) 条"
    }

    private func heartRateChartDomain(from data: [TimeSeriesPoint]) -> ClosedRange<Double> {
        let values = data.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 40...100
        }
        let lower = Double(max(30, minValue - 4))
        let upper = Double(maxValue + 4)
        return lower...upper
    }


    private var sleepRespirationText: String {
        if let value = viewModel.nightlyRespirationRate, value.isFinite, value > 0 {
            return String(format: "%.1f", value)
        }
        return "--"
    }

    private var sleepOxygenProxyText: String {
        if let respiration = viewModel.nightlyRespirationRate, respiration.isFinite, respiration > 0 {
            let proxy = Int(min(99, max(93, (99 - abs(respiration - 16) * 1.2).rounded())))
            return "\(proxy)"
        }
        return "94"
    }

    private var wristTemperatureText: String {
        guard let value = viewModel.sleepingWristTemperature else { return "--" }
        return String(format: "%.1f", value)
    }


    private func heartRateContextPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.92), Color(hex: "FAFCFF").opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func sleepStageShareText(data: SleepData) -> String {
        let awake = stageMinutes(stage: "Awake", stages: data.stages)
        let rem = stageMinutes(stage: "REM", stages: data.stages)
        let core = stageMinutes(stage: "Core", stages: data.stages)
        let deep = stageMinutes(stage: "Deep", stages: data.stages)
        let totalStageMinutes = data.stageDistributionTotalMinutes
        let range = sleepWindowText
        return """
        我的昨夜睡眠阶段
        睡眠区间：\(range)
        主睡眠：\(data.duration_minutes / 60)h\(data.duration_minutes % 60)m
        清醒：\(awake) 分钟（\(Int((stageRatio(stage: "Awake", stages: data.stages, totalMinutes: totalStageMinutes) * 100).rounded()))%）
        快速眼动：\(rem) 分钟（\(Int((stageRatio(stage: "REM", stages: data.stages, totalMinutes: totalStageMinutes) * 100).rounded()))%）
        核心睡眠：\(core) 分钟（\(Int((stageRatio(stage: "Core", stages: data.stages, totalMinutes: totalStageMinutes) * 100).rounded()))%）
        深度睡眠：\(deep) 分钟（\(Int((stageRatio(stage: "Deep", stages: data.stages, totalMinutes: totalStageMinutes) * 100).rounded()))%）
        来自 眠屿 睡眠详情
        """
    }


    private var detailStatusColor: Color {
        guard let data = viewModel.sleepData else { return Color(hex: "53CDAE") }
        if data.sleep_score >= 85 { return Color(hex: "53CDAE") }
        if data.sleep_score >= 72 { return Color(hex: "79C76F") }
        if data.sleep_score >= 60 { return Color(hex: "F2A357") }
        return Color(hex: "F46B5A")
    }

    private var detailStatusTitle: String {
        guard let data = viewModel.sleepData else { return "等待同步" }
        if data.sleep_score >= 85 { return "生命体征一切正常" }
        if data.sleep_score >= 72 { return "恢复状态稳定" }
        if data.sleep_score >= 60 { return "清醒欠缺" }
        return "恢复偏弱"
    }

    private var detailStatusProgress: CGFloat {
        guard let data = viewModel.sleepData else { return 0.5 }
        return sleepSafeUnit(CGFloat(Double(data.sleep_score) / 100.0), minimum: 0.18)
    }

    private func detailStatusDescription(_ data: SleepData) -> String {
        if let awake = data.awake_count, awake > 1 {
            return String(localized: "昨夜醒来 \(awake) 次，今天更适合把训练和咖啡因控制在温和区间。")
        }
        if let respiration = viewModel.nightlyRespirationRate, respiration > 0 {
            return "呼吸频率 \(String(format: "%.1f", respiration)) 次/分，结合夜间 HRV 一起看，恢复状态会更直观。"
        }
        return String(localized: "今天的健康指标显示，你的身体状态正逐步回到更稳定的恢复区间。")
    }

    private func lateNightSeverity(for bedtime: Date) -> Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: bedtime)
        let minute = calendar.component(.minute, from: bedtime)
        let totalMinutes = hour * 60 + minute

        if totalMinutes >= 180 || totalMinutes < 60 {
            return 80
        }
        if totalMinutes >= 120 {
            return 67
        }
        if totalMinutes >= 60 {
            return 48
        }
        return 0
    }

    private func stageToneText(title: String, ratio: Double) -> String {
        switch title {
        case "清醒":
            return ratio <= 0.06 ? "正常" : "偏多"
        case "REM":
            return ratio >= 0.10 ? "正常" : "偏少"
        case "核心睡眠":
            return ratio >= 0.55 ? "正常" : "偏低"
        case "深睡":
            return ratio >= 0.12 ? "正常" : "偏低"
        default:
            return String(localized: "观察")
        }
    }

    private func stageToneColor(title: String, ratio: Double) -> Color {
        stageToneText(title: title, ratio: ratio) == "正常" ? Color(hex: "53CDAE") : Color(hex: "F2A357")
    }

    private func stageOverviewSummaryText(_ data: SleepData) -> String {
        guard !data.stages.isEmpty else { return "暂无阶段数据" }
        let deep = stageRatio(stage: "Deep", stages: data.stages, totalMinutes: data.duration_minutes)
        let rem = stageRatio(stage: "REM", stages: data.stages, totalMinutes: data.duration_minutes)
        if deep >= 0.12 && rem >= 0.10 { return "结构稳定" }
        if deep < 0.12 { return "深睡偏少" }
        if rem < 0.10 { return "REM 偏少" }
        return String(localized: "等待同步")
    }

    private func lateNightCalendarSummaryText(lateNightCount: Int) -> String {
        switch lateNightCount {
        case 0:
            return String(localized: "最近一周没有明显熬夜记录，睡眠节律相对稳定。")
        case 1:
            return String(localized: "最近一周出现 1 次明显晚睡，注意别把它变成连续节律。")
        default:
            return String(localized: "最近一周熬夜次数偏多，优先把入睡时间往前收，会比单纯补觉更有效。")
        }
    }

    private func durationProgress(durationMinutes: Int) -> Double {
        let goal = max(1, viewModel.sleepGoalMinutes)
        return min(1.0, Double(durationMinutes) / Double(goal))
    }

    private func stageRatio(stage: String, stages: [SleepStage], totalMinutes: Int) -> Double {
        guard totalMinutes > 0 else { return 0 }
        return min(1.0, Double(stageMinutes(stage: stage, stages: stages)) / Double(totalMinutes))
    }

    private func stageMinutes(stage: String, stages: [SleepStage]) -> Int {
        let canonical = canonicalStageName(stage)
        return stages.reduce(0) { partialResult, item in
            guard canonicalStageName(item.stage) == canonical else { return partialResult }
            return partialResult + max(0, item.duration)
        }
    }

    private func canonicalStageName(_ stage: String) -> String {
        if stage.contains("深") || stage.caseInsensitiveCompare("Deep") == .orderedSame {
            return "Deep"
        }
        if stage.contains("快速") || stage.caseInsensitiveCompare("REM") == .orderedSame {
            return "REM"
        }
        if stage.contains("清醒") || stage.caseInsensitiveCompare("Awake") == .orderedSame {
            return "Awake"
        }
        if stage.contains("浅") || stage.contains("核心") || stage.caseInsensitiveCompare("Core") == .orderedSame {
            return "Core"
        }
        return stage
    }

    private func weekdayShortText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "E"
        return formatter.string(from: date).replacingOccurrences(of: "周", with: "")
    }

    private func heartRateChartData() -> [TimeSeriesPoint] {
        viewModel.sleepHeartRatePoints
    }

    private func heartRateInsightText(from data: [TimeSeriesPoint]) -> String {
        guard !data.isEmpty else {
            return String(localized: "如果昨夜没有生成睡眠心率，通常是因为睡眠记录还在同步或设备样本还不完整。")
        }
        let spread = (data.map(\.value).max() ?? 0) - (data.map(\.value).min() ?? 0)
        if spread <= 12 {
            return String(localized: "昨夜心率波动比较平稳，通常意味着入睡后的身体负荷没有明显抬升。")
        }
        return String(localized: "夜间心率有一定波动，建议结合昨晚的清醒次数和睡前节奏一起看。")
    }


    private func durationText(minutes: Int) -> String {
        "\(minutes / 60)小时\(minutes % 60)分钟"
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }


    private func sectionBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.appSystem(size: 11, weight: .heavy, design: .rounded))
            .foregroundColor(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.17), tint.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
    }
}

private extension View {
    /// 睡眠详情卡片使用统一的浅色表面；主题色只做轻微底色，避免长页面颜色互相争抢。
    @ViewBuilder
    func detailCardSurface(tint: Color? = nil) -> some View {
        let accent = tint ?? Color(hex: "4FA98B")
        if #available(iOS 26.0, *) {
            self
                .padding(16)
                .bbLiquidGlassSurface(
                    tint: accent,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                    tintStrength: 0.055,
                    shadow: false
                )
        } else {
            self
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.94))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [accent.opacity(0.035), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.92), lineWidth: 1)
                        }
                )
                .shadow(color: Color(hex: "28395A").opacity(0.045), radius: 10, y: 5)
        }
    }
}

private struct SleepRhythmCard: View {
    let data: SleepData
    let goalMinutes: Int
    let sleepWindowText: String
    let bedTimeText: String
    let wakeTimeText: String
    let averageHeartRateText: String
    let fontScaleLevel: AppFontScaleLevel

    private static let tint = Color(hex: "6175F6")

    private var normalizedGoalMinutes: Int {
        max(1, goalMinutes)
    }

    private var durationProgress: Double {
        sleepSafeUnit(Double(max(0, data.duration_minutes)) / Double(normalizedGoalMinutes))
    }

    private var restorativeSubtitle: String {
        let total = max(1, data.duration_minutes)
        let deepMinutes = stageMinutes(named: "Deep")
        let remMinutes = stageMinutes(named: "REM")
        let (sum, overflow) = deepMinutes.addingReportingOverflow(remMinutes)
        let minutes = overflow ? Int.max : sum
        let ratio = sleepSafeUnit(Double(minutes) / Double(total))
        return String(localized: "\(durationText(minutes: minutes)) · \(localizedPercentRatio(ratio)) 占比")
    }

    private var recentRhythmItems: [SleepRhythmDetailItem] {
        let calendar = Calendar.current
        let today = Date()
        return (0..<6).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -(5 - offset), to: today) else { return nil }
            let isToday = calendar.isDateInToday(date)
            return SleepRhythmDetailItem(
                weekday: weekdayShortText(date),
                dayText: "\(calendar.component(.day, from: date))",
                tint: isToday ? Self.tint : Color(hex: "ECEFF6"),
                isToday: isToday
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            sleepMetrics
            rhythmSchedule
            insight
        }
        .detailCardSurface(tint: Self.tint)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("睡眠节律")
                    .font(Theme.Typography.scaled(size: 17, weight: .black, design: .rounded, level: fontScaleLevel))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(summaryText)
                    .font(Theme.Typography.scaled(size: 13, weight: .medium, design: .rounded, level: fontScaleLevel))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text(goalMinutes > 0 && data.duration_minutes >= goalMinutes ? "已达标" : "待补恢复")
                .font(.appSystem(size: 10, weight: .heavy, design: .rounded))
                .foregroundColor(Self.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Self.tint.opacity(0.12), in: Capsule())
        }
    }

    private var sleepMetrics: some View {
        HStack(alignment: .center, spacing: 18) {
            SleepRingHeader(
                durationMinutes: data.duration_minutes,
                goalMinutes: goalMinutes,
                sleepScore: data.sleep_score
            )
            .frame(width: 142, height: 142)

            VStack(alignment: .leading, spacing: 10) {
                infoTag(title: "入睡区间", value: sleepWindowText)
                infoTag(title: "恢复性睡眠", value: restorativeSubtitle)
                infoTag(title: "平均心率", value: averageHeartRateText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rhythmSchedule: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("睡眠规律")
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(sleepWindowText)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Self.tint)
            }

            VStack(alignment: .leading, spacing: 12) {
                recentDays

                HStack(spacing: 12) {
                    rhythmTimePill(title: "入睡时间", value: bedTimeText, symbol: "face.smiling")
                    rhythmTimePill(title: "起床时间", value: wakeTimeText, symbol: "alarm")
                }
            }
        }
        .padding(14)
        .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var recentDays: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近 6 天")
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            HStack(spacing: 8) {
                ForEach(recentRhythmItems) { item in
                    VStack(spacing: 8) {
                        Text(item.weekday)
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Circle()
                            .fill(item.tint)
                            .frame(width: 36, height: 36)
                            .overlay {
                                if item.isToday {
                                    Image(systemName: "moon.stars.fill")
                                        .font(.appSystem(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                } else {
                                    Text(item.dayText)
                                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                                        .foregroundColor(Theme.Colors.textPrimary)
                                }
                            }
                    }
                }
            }
        }
    }

    private var insight: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundColor(Self.tint)
                .frame(width: 18, height: 18)

            Text(durationProgress >= 1
                 ? "昨夜睡眠时长已经达标，接下来更值得关注阶段结构和夜间心率是否一起稳定。"
                 : "时长还没补够时，先把总睡眠时间拉到目标附近，节律判断会更准确。")
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var summaryText: String {
        if data.sleep_score >= 85 && data.duration_minutes >= normalizedGoalMinutes {
            return String(localized: "你已经完成睡眠目标，整体恢复节奏也比较完整。")
        }
        if data.sleep_score >= 75 {
            return String(localized: "整体睡眠状态不错，再把作息规律性拉齐会更稳。")
        }
        if data.duration_minutes < normalizedGoalMinutes {
            return String(localized: "昨夜比目标少睡了 \(normalizedGoalMinutes - max(0, data.duration_minutes)) 分钟，今天更适合提早进入放松状态。")
        }
        return String(localized: "昨夜恢复一般，建议结合阶段分布和夜间心率继续观察。")
    }

    private func infoTag(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func rhythmTimePill(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundColor(Self.tint)
                Text(value)
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func stageMinutes(named name: String) -> Int {
        let canonicalName = canonicalStageName(name)
        return data.stages.reduce(into: 0) { total, stage in
            guard canonicalStageName(stage.stage) == canonicalName else { return }
            let (sum, overflow) = total.addingReportingOverflow(max(0, stage.duration))
            total = overflow ? Int.max : sum
        }
    }

    private func canonicalStageName(_ stage: String) -> String {
        if stage.contains("深") || stage.caseInsensitiveCompare("Deep") == .orderedSame { return "Deep" }
        if stage.contains("快速") || stage.caseInsensitiveCompare("REM") == .orderedSame { return "REM" }
        return stage
    }

    private func durationText(minutes: Int) -> String {
        "\(minutes / 60)小时\(minutes % 60)分钟"
    }

    private func weekdayShortText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "E"
        return formatter.string(from: date).replacingOccurrences(of: "周", with: "")
    }
}

/// 睡眠阶段Timeline图表组件 作为睡眠模块里的数据可视化组件。
/// 负责睡眠记录与恢复分析。
private struct SleepStagesSummaryCard: View {
    let data: SleepData
    let sleepInterval: SleepInterval?
    let fontScaleLevel: AppFontScaleLevel
    let tint: Color
    let accent: Color
    let onShare: () -> Void

    private var hasTimeline: Bool {
        SleepStageTimelineChart.hasRenderableData(data.stages)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if hasTimeline {
                timelineContent
            } else {
                emptyTimelineContent
            }
        }
        .detailCardSurface(tint: accent)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("睡眠")
                    .font(Theme.Typography.scaled(size: 17, weight: .black, design: .rounded, level: fontScaleLevel))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(hasTimeline ? "专业时间轴展示昨夜睡眠阶段的真实切换与分布。" : "当前还没有拿到带时间区间的睡眠阶段样本，先展示汇总摘要。")
                    .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: fontScaleLevel))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onShare) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up")
                        Text("分享")
                    }
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(tint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)

                Text(hasTimeline ? "阶段时间轴" : "估算摘要")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accent.opacity(0.12), in: Capsule())
            }
        }
    }

    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SleepStageTimelineChart(
                stages: data.stages,
                sleepInterval: sleepInterval,
                mode: .detailed
            )
            .frame(height: 276)

            SleepStageTimelineLegend()
        }
    }

    private var emptyTimelineContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("等待真实阶段样本", systemImage: "clock.badge.exclamationmark")
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(accent)

            Text("佩戴 Apple Watch 完成一次完整睡眠后，这里会自动切换成 Awake、REM、Core、Deep 四阶段专业图。")
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SleepStageTimelineChart: View {
    /// Mode 枚举，作为内部辅助类型，用于细分外层睡眠记录与恢复分析中的状态或分支。
    enum Mode {
        case compact
        case detailed

        var showsXAxisLabels: Bool {
            self == .detailed
        }

        var showsYAxisLabels: Bool {
            self == .detailed
        }

        var barInset: CGFloat {
            self == .detailed ? 0.34 : 0.28
        }
    }

    let stages: [SleepStage]
    let sleepInterval: SleepInterval?
    let mode: Mode

    private var timeline: SleepStageTimelineData? {
        SleepStageTimelineData(stages: stages, sleepInterval: sleepInterval)
    }

    var body: some View {
        if let timeline, !timeline.segments.isEmpty {
            Chart(timeline.segments) { segment in
                RectangleMark(
                    xStart: .value("开始", segment.startDate),
                    xEnd: .value("结束", segment.endDate),
                    yStart: .value("阶段下界", segment.stage.order - mode.barInset),
                    yEnd: .value("阶段上界", segment.stage.order + mode.barInset)
                )
                .foregroundStyle(segment.stage.color.gradient)
                .clipShape(RoundedRectangle(cornerRadius: mode == .detailed ? 6 : 4, style: .continuous))
            }
            .chartLegend(.hidden)
            .chartXScale(domain: timeline.visibleDomain)
            .chartYScale(domain: 0.5...4.5)
            .chartXAxis {
                AxisMarks(values: timeline.axisMarks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(mode == .detailed ? 0.18 : 0.12))
                    AxisTick(length: mode.showsXAxisLabels ? 5 : 0)
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(mode == .detailed ? 0.25 : 0))
                    if mode.showsXAxisLabels, let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(SleepStageTimelineData.axisLabel(for: date))
                                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: SleepTimelineStage.allCases.map(\.order)) { value in
                    AxisGridLine()
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(mode == .detailed ? 0.14 : 0.10))
                    if mode.showsYAxisLabels, let order = value.as(Double.self), let stage = SleepTimelineStage(order: Int(order.rounded())) {
                        AxisValueLabel {
                            Text(stage.axisLabel)
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.55))
                .overlay(
                    Text("等待睡眠阶段样本")
                        .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                )
        }
    }

    static func hasRenderableData(_ stages: [SleepStage]) -> Bool {
        SleepStageTimelineData(stages: stages, sleepInterval: nil) != nil
    }
}

/// 睡眠阶段Timeline结构体 作为睡眠模块里的辅助类型。
/// 负责睡眠记录与恢复分析。
struct SleepStageTimelineLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(SleepTimelineStage.allCases, id: \.self) { stage in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(stage.color)
                        .frame(width: 10, height: 10)
                    Text(stage.legendLabel)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SleepRhythmDetailItem: Identifiable {
    let id = UUID()
    let weekday: String
    let dayText: String
    let tint: Color
    let isToday: Bool
}

private struct SleepRhythmTrailDay: Identifiable {
    let id: String
    let label: String
    let isToday: Bool
    let isCompleted: Bool
}

private struct SleepLateNightCalendarItem: Identifiable {
    let id = UUID()
    let weekday: String
    let dayText: String
    let bedtimeText: String
    let lateNightScoreText: String
    let isLateNight: Bool
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct SleepStageTimelineData {
    let referenceDayStart: Date
    let segments: [SleepStageTimelineSegment]
    let visibleLowerBound: Date
    let visibleUpperBound: Date
    let occupiedLowerBound: Date
    let occupiedUpperBound: Date

    var visibleDomain: ClosedRange<Date> {
        visibleLowerBound...visibleUpperBound
    }

    var axisMarks: [Date] {
        SleepTimelineAxisHelper.axisDates(start: visibleLowerBound, end: visibleUpperBound)
    }

    init?(stages: [SleepStage], sleepInterval: SleepInterval?) {
        let timedStages = stages
            .filter { $0.duration > 0 }
            .compactMap { stage -> SleepStageTimelineSegmentSource? in
                guard
                    let stageKey = SleepTimelineStage(stage.stage),
                    let originalStart = stage.startDate,
                    let originalEnd = stage.endDate,
                    originalEnd > originalStart
                else {
                    return nil
                }

                let start: Date
                let end: Date
                if let sleepInterval {
                    start = max(originalStart, sleepInterval.start)
                    end = min(originalEnd, sleepInterval.end)
                } else {
                    start = originalStart
                    end = originalEnd
                }

                guard end > start else { return nil }
                return SleepStageTimelineSegmentSource(stage: stageKey, startDate: start, endDate: end)
            }
            .sorted { $0.startDate < $1.startDate }

        guard !timedStages.isEmpty else { return nil }

        let calendar = Calendar.current
        let anchorDate = sleepInterval?.end ?? timedStages.map(\.endDate).max() ?? Date()
        referenceDayStart = calendar.startOfDay(for: anchorDate)

        let rawWindowStart = sleepInterval?.start ?? timedStages.map(\.startDate).min() ?? anchorDate
        let rawWindowEnd = sleepInterval?.end ?? timedStages.map(\.endDate).max() ?? anchorDate

        let normalizedWindowStart = Self.normalizedDate(for: rawWindowStart, referenceDayStart: referenceDayStart, calendar: calendar)
        var normalizedWindowEnd = Self.normalizedDate(for: rawWindowEnd, referenceDayStart: referenceDayStart, calendar: calendar)
        let spansMidnight =
            calendar.startOfDay(for: rawWindowStart) != calendar.startOfDay(for: rawWindowEnd) ||
            normalizedWindowStart > normalizedWindowEnd

        if spansMidnight && normalizedWindowEnd <= normalizedWindowStart {
            normalizedWindowEnd = normalizedWindowEnd.addingTimeInterval(24 * 60 * 60)
        }

        var normalized: [SleepStageTimelineSegment] = []
        for stage in timedStages {
            normalized.append(
                contentsOf: SleepStageTimelineData.normalize(
                    stage: stage,
                    referenceDayStart: referenceDayStart,
                    calendar: calendar,
                    wrapsAcrossMidnight: spansMidnight,
                    normalizedWindowStart: normalizedWindowStart
                )
            )
        }

        let sortedSegments = normalized.sorted {
            if $0.startDate == $1.startDate {
                return $0.stage.order > $1.stage.order
            }
            return $0.startDate < $1.startDate
        }

        guard
            let occupiedLower = sortedSegments.map(\.startDate).min(),
            let occupiedUpper = sortedSegments.map(\.endDate).max()
        else {
            return nil
        }

        self.segments = sortedSegments
        self.visibleLowerBound = min(occupiedLower, normalizedWindowStart)
        self.visibleUpperBound = max(occupiedUpper, normalizedWindowEnd)
        self.occupiedLowerBound = occupiedLower
        self.occupiedUpperBound = max(occupiedUpper, normalizedWindowEnd)
    }

    static func axisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "H:mm"
        return formatter.string(from: date)
    }

    private static func normalize(
        stage: SleepStageTimelineSegmentSource,
        referenceDayStart: Date,
        calendar: Calendar,
        wrapsAcrossMidnight: Bool,
        normalizedWindowStart: Date
    ) -> [SleepStageTimelineSegment] {
        let dayStart = calendar.startOfDay(for: stage.startDate)
        let dayEnd = calendar.startOfDay(for: stage.endDate)
        let normalizedStart = normalizedDate(for: stage.startDate, referenceDayStart: referenceDayStart, calendar: calendar)
        let normalizedEnd = normalizedDate(for: stage.endDate, referenceDayStart: referenceDayStart, calendar: calendar)
        let dayBoundary = referenceDayStart.addingTimeInterval(24 * 60 * 60)

        if dayStart == dayEnd, normalizedEnd > normalizedStart {
            let baseSegment = SleepStageTimelineSegment(stage: stage.stage, startDate: normalizedStart, endDate: normalizedEnd)
            return [shiftedIfNeeded(baseSegment, wrapsAcrossMidnight: wrapsAcrossMidnight, normalizedWindowStart: normalizedWindowStart)]
        }

        var results: [SleepStageTimelineSegment] = []
        if normalizedStart < dayBoundary {
            results.append(SleepStageTimelineSegment(stage: stage.stage, startDate: normalizedStart, endDate: dayBoundary))
        }
        if normalizedEnd > referenceDayStart {
            results.append(SleepStageTimelineSegment(stage: stage.stage, startDate: referenceDayStart, endDate: normalizedEnd))
        }
        return results
            .filter { $0.endDate > $0.startDate }
            .map { shiftedIfNeeded($0, wrapsAcrossMidnight: wrapsAcrossMidnight, normalizedWindowStart: normalizedWindowStart) }
    }

    private static func shiftedIfNeeded(
        _ segment: SleepStageTimelineSegment,
        wrapsAcrossMidnight: Bool,
        normalizedWindowStart: Date
    ) -> SleepStageTimelineSegment {
        guard wrapsAcrossMidnight, segment.startDate < normalizedWindowStart else {
            return segment
        }

        return SleepStageTimelineSegment(
            stage: segment.stage,
            startDate: segment.startDate.addingTimeInterval(24 * 60 * 60),
            endDate: segment.endDate.addingTimeInterval(24 * 60 * 60)
        )
    }

    private static func normalizedDate(
        for date: Date,
        referenceDayStart: Date,
        calendar: Calendar
    ) -> Date {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return calendar.date(byAdding: components, to: referenceDayStart) ?? referenceDayStart
    }
}

enum SleepTimelineAxisHelper {
    static func axisDates(start: Date, end: Date) -> [Date] {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return [start] }

        let twoHours: TimeInterval = 2 * 60 * 60
        let sixHours: TimeInterval = 6 * 60 * 60
        let twelveHours: TimeInterval = 12 * 60 * 60
        let step: TimeInterval
        switch duration {
        case ..<twoHours:
            step = 30 * 60
        case ..<sixHours:
            step = 60 * 60
        case ..<twelveHours:
            step = 2 * 60 * 60
        default:
            step = 3 * 60 * 60
        }

        var marks: [Date] = [start]
        var cursor = start.addingTimeInterval(step)
        while cursor < end {
            marks.append(cursor)
            cursor = cursor.addingTimeInterval(step)
        }

        if marks.last != end {
            marks.append(end)
        }
        return marks
    }
}

private struct SleepStageTimelineSegmentSource {
    let stage: SleepTimelineStage
    let startDate: Date
    let endDate: Date
}

private struct SleepStageTimelineSegment: Identifiable {
    let id = UUID()
    let stage: SleepTimelineStage
    let startDate: Date
    let endDate: Date
}

private enum SleepTimelineStage: CaseIterable {
    case awake
    case rem
    case core
    case deep

    init?(_ rawStage: String) {
        if rawStage.contains("清醒") || rawStage.caseInsensitiveCompare("Awake") == .orderedSame {
            self = .awake
        } else if rawStage.contains("快速") || rawStage.caseInsensitiveCompare("REM") == .orderedSame {
            self = .rem
        } else if rawStage.contains("浅") || rawStage.contains("核心") || rawStage.caseInsensitiveCompare("Core") == .orderedSame {
            self = .core
        } else if rawStage.contains("深") || rawStage.caseInsensitiveCompare("Deep") == .orderedSame {
            self = .deep
        } else {
            return nil
        }
    }

    init?(order: Int) {
        switch order {
        case 4: self = .awake
        case 3: self = .rem
        case 2: self = .core
        case 1: self = .deep
        default: return nil
        }
    }

    var order: Double {
        switch self {
        case .awake: return 4
        case .rem: return 3
        case .core: return 2
        case .deep: return 1
        }
    }

    var color: Color {
        switch self {
        case .awake: return Color(hex: "8B6FF6")
        case .rem: return Color(hex: "38C8E7")
        case .core: return Color(hex: "2C8FFF")
        case .deep: return Color(hex: "7357F6")
        }
    }

    var axisLabel: String {
        switch self {
        case .awake: return "Awake"
        case .rem: return "REM"
        case .core: return "Core"
        case .deep: return "Deep"
        }
    }

    var legendLabel: String {
        switch self {
        case .awake: return "Awake 清醒"
        case .rem: return "REM 快速眼动"
        case .core: return "Core 核心睡眠"
        case .deep: return "Deep 深度睡眠"
        }
    }
}

private struct SleepRingHeader: View {
    let durationMinutes: Int
    let goalMinutes: Int
    let sleepScore: Int

    @State private var animatedProgress: Double = 0
    @State private var animatedScoreProgress: Double = 0
    @State private var contentVisible = false
    @State private var isLoading = true
    @State private var loaderRotation: Double = -90
    @State private var loaderOpacity: Double = 0.88

    private var progress: Double {
        guard goalMinutes > 0 else { return 0.0 }
        return sleepSafeUnit(Double(durationMinutes) / Double(goalMinutes))
    }

    private var scoreProgress: Double {
        sleepSafeUnit(Double(sleepScore) / 100.0)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "6175F6").opacity(0.16), style: StrokeStyle(lineWidth: 18, lineCap: .round))

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(Color(hex: "6175F6"), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(isLoading ? 0.2 : 1)

            Circle()
                .stroke(Color(hex: "86E4E5").opacity(0.16), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 108, height: 108)

            Circle()
                .trim(from: 0, to: animatedScoreProgress)
                .stroke(Color(hex: "86E4E5"), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 108, height: 108)
                .opacity(isLoading ? 0.2 : 1)

            Circle()
                .trim(from: 0.08, to: 0.34)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.9),
                            Color(hex: "A8F0EE").opacity(0.85),
                            Color.white.opacity(0.0)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(loaderRotation))
                .frame(width: 146, height: 146)
                .opacity(loaderOpacity)
                .blur(radius: 0.5)

            VStack(spacing: 6) {
                Image(systemName: "moon.fill")
                    .font(.appSystem(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "6175F6"))

                Text("\(durationMinutes / 60)h \(durationMinutes % 60)m")
                    .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(sleepScore > 0 ? "\(sleepScore)分" : "睡眠")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "6175F6"))
            }
            .opacity(contentVisible ? 1 : 0)
            .scaleEffect(contentVisible ? 1 : 0.92)
            .animation(.spring(response: 0.58, dampingFraction: 0.82).delay(0.12), value: contentVisible)
        }
        .onAppear {
            isLoading = true
            contentVisible = false
            animatedProgress = 0
            animatedScoreProgress = 0
            loaderRotation = -90
            loaderOpacity = 0.88

            withAnimation(.linear(duration: 0.92)) {
                loaderRotation = 270
            }

            withAnimation(.easeOut(duration: 0.24).delay(0.84)) {
                loaderOpacity = 0
            }

            withAnimation(.spring(response: 0.96, dampingFraction: 0.86).delay(0.2)) {
                animatedProgress = progress
            }

            withAnimation(.spring(response: 0.86, dampingFraction: 0.84).delay(0.28)) {
                animatedScoreProgress = scoreProgress
            }

            withAnimation(.spring(response: 0.6, dampingFraction: 0.84).delay(0.34)) {
                contentVisible = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.94) {
                isLoading = false
            }
        }
        .onChange(of: durationMinutes) { _, _ in
            withAnimation(.spring(response: 0.82, dampingFraction: 0.86)) {
                animatedProgress = progress
            }
        }
        .onChange(of: sleepScore) { _, _ in
            withAnimation(.spring(response: 0.82, dampingFraction: 0.86)) {
                animatedScoreProgress = scoreProgress
            }
        }
    }
}

private struct SleepVitalStatusOrb: View {
    let score: Int
    let durationMinutes: Int
    let statusTitle: String
    let statusColor: Color
    let progress: CGFloat

    @State private var animatedProgress: CGFloat = 0
    @State private var isBreathing = false
    @State private var contentVisible = false
    @State private var isLoading = true
    @State private var loaderRotation: Double = -90
    @State private var loaderOpacity: Double = 0.9

    private var durationLabel: String {
        "\(durationMinutes / 60)h \(durationMinutes % 60)m"
    }

    private var safeProgress: CGFloat {
        sleepSafeUnit(progress, minimum: 0.18)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color(hex: "F2F5FF").opacity(0.94),
                            Color(hex: "DDE6FF").opacity(0.62)
                        ],
                        center: .center,
                        startRadius: 24,
                        endRadius: 88
                    )
                )
                .overlay {
                    Circle()
                        .fill(statusColor.opacity(0.08))
                        .frame(width: 98, height: 98)
                        .blur(radius: 10)
                        .scaleEffect(isBreathing ? 1.06 : 0.94)
                        .animation(
                            .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
                            value: isBreathing
                        )
                }

            Circle()
                .stroke(Color(hex: "6E84F7").opacity(0.14), lineWidth: 10)
                .frame(width: 137, height: 137)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: "5AA8FF"),
                            Color(hex: "6E84F7"),
                            Color(hex: "9A7BFF"),
                            Color(hex: "5AA8FF")
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 137, height: 137)
                .opacity(isLoading ? 0.18 : 1)

            Circle()
                .stroke(Color.black.opacity(0.035), lineWidth: 5)
                .frame(width: 112, height: 112)

            Circle()
                .trim(from: 0, to: min(1.0, animatedProgress * 0.82))
                .stroke(statusColor.opacity(0.68), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(78))
                .frame(width: 112, height: 112)
                .opacity(isLoading ? 0.16 : 1)

            Circle()
                .stroke(Color.white.opacity(0.86), lineWidth: 1)
                .frame(width: 96, height: 96)

            Circle()
                .trim(from: 0.08, to: 0.34)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.9),
                            Color(hex: "A9B7FF").opacity(0.75),
                            Color.white.opacity(0.0)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(loaderRotation))
                .frame(width: 137, height: 137)
                .opacity(loaderOpacity)
                .blur(radius: 0.4)
                .allowsHitTesting(false)

            VStack(spacing: 6) {
                Text("\(score)")
                    .font(.appSystem(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .contentTransition(.numericText())

                Text(statusTitle)
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(statusColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)

                Text(durationLabel)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .padding(.horizontal, 14)
            .opacity(contentVisible ? 1 : 0)
            .scaleEffect(contentVisible ? 1 : 0.92)
            .animation(.spring(response: 0.58, dampingFraction: 0.82).delay(0.12), value: contentVisible)
        }
        .frame(width: 150, height: 150)
        .onAppear {
            isLoading = true
            animatedProgress = 0
            contentVisible = false
            loaderRotation = -90
            loaderOpacity = 0.9

            withAnimation(.linear(duration: 0.95)) {
                loaderRotation = 270
            }

            withAnimation(.easeOut(duration: 0.24).delay(0.88)) {
                loaderOpacity = 0
            }

            withAnimation(.spring(response: 1.0, dampingFraction: 0.86).delay(0.22)) {
                animatedProgress = safeProgress
            }

            withAnimation(.spring(response: 0.6, dampingFraction: 0.84).delay(0.34)) {
                contentVisible = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.96) {
                isLoading = false
            }

            isBreathing = true
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring(response: 0.82, dampingFraction: 0.86)) {
                animatedProgress = sleepSafeUnit(newValue, minimum: 0.18)
            }
        }
    }
}


// 调试用（用户要求）：打开睡眠弹窗时打印各数据源实际内容，便于定位“没有睡眠数据”。
fileprivate func printSleepDebugData(viewModel: SleepViewModel) {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm"
    func fmtDate(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return formatter.string(from: date)
    }
    func fmtEpoch(_ seconds: Int?) -> String {
        guard let seconds else { return "nil" }
        return fmtDate(Date(timeIntervalSince1970: TimeInterval(seconds)))
    }
    func fmtDuration(_ minutes: Int) -> String {
        String(format: "%d小时%02d分", minutes / 60, minutes % 60)
    }

    var lines: [String] = []
    lines.append("=== [SleepDebug] 睡眠弹窗打开 ===")
    if let data = viewModel.sleepData {
        lines.append("sleepData(HealthKit): duration=\(fmtDuration(data.duration_minutes)) score=\(data.sleep_score) stages=\(data.stages.count) start=\(fmtEpoch(data.start_time)) end=\(fmtEpoch(data.end_time))")
    } else {
        lines.append("sleepData(HealthKit): nil")
    }
    if let summary = viewModel.latestSleepSummary {
        lines.append("latestSleepSummary(本地): id=\(summary.sessionId) duration=\(fmtDuration(summary.sleepDurationMinutes)) score=\(summary.sleepScore) start=\(fmtDate(summary.startTime)) end=\(fmtDate(summary.endTime)) source=\(summary.source.rawValue) updatedAt=\(fmtDate(summary.updatedAt))")
    } else {
        lines.append("latestSleepSummary(本地): nil")
    }
    if let appGroup = AppGroupManager.shared.getSleepLatestSummary() {
        lines.append("AppGroup summary: duration=\(fmtDuration(appGroup.sleepDurationMinutes)) score=\(appGroup.sleepScore) updatedAt=\(fmtDate(appGroup.updatedAt))")
    } else {
        lines.append("AppGroup summary: nil")
    }
    let orchestrator = SleepMonitoringOrchestrator.shared
    if let latest = orchestrator.latestSummary {
        lines.append("orchestrator.latestSummary: duration=\(fmtDuration(latest.sleepDurationMinutes)) score=\(latest.sleepScore) updatedAt=\(fmtDate(latest.updatedAt))")
    } else {
        lines.append("orchestrator.latestSummary: nil")
    }
    lines.append("monitoringState: phase=\(viewModel.monitoringState.phase.rawValue) watchConnected=\(viewModel.monitoringState.watchConnected)")
    let intervals = viewModel.sleepIntervals
    lines.append("sleepIntervals(HealthKit): \(intervals.count) 条")
    for (index, interval) in intervals.enumerated() {
        lines.append("  [\(index)] \(fmtDate(interval.start)) ~ \(fmtDate(interval.end)) 共 \(Int(interval.end.timeIntervalSince(interval.start) / 60)) 分")
    }
    print(lines.joined(separator: "\n"))
}
