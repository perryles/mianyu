/// FitnessCalendarScreen 由目标模块健身入口调用，作为「健身日历」主页。
/// 负责承载健身月历布局、训练中心内容、同步状态与 AI 入口。

import SwiftUI
import Combine

struct FitnessCalendarScreen: View {
    @State private var viewModel = FitnessCalendarViewModel()
    @State private var showingMonthCalendar = false
    @State private var showingFitnessAI = false
    @State private var showingBadges = false
    @State private var showingTrainingHistory = false
    @State private var pendingTrainingHistoryDay: HabitFitnessCalendarDay?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var showsHeroTitle: Bool = true
    var showsQuickActions: Bool = true
    var contentInset: CGFloat = 0
    var bottomPadding: CGFloat = 34

    init(showsHeroTitle: Bool = true, showsQuickActions: Bool = true, contentInset: CGFloat = 0, bottomPadding: CGFloat = 34) {
        self.showsHeroTitle = showsHeroTitle
        self.showsQuickActions = showsQuickActions
        self.contentInset = contentInset
        self.bottomPadding = bottomPadding
    }

    var body: some View {
        ZStack {
            fitnessPageBackground

            AdaptivePageScrollView(topPadding: 14, bottomPadding: bottomPadding, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    if showsHeroTitle {
                        fitnessPageHeader
                    }

                    if viewModel.isLoading && viewModel.calendarModel.days.isEmpty {
                        FitnessTrainingLoadingSkeleton()
                    } else {
                        trainingCenterContent
                    }
                }
                .padding(.horizontal, contentInset)
            }

            if let syncMessage = viewModel.syncMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 9) {
                        Image(systemName: syncMessage.contains("失败") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        Text(syncMessage)
                            .lineLimit(2)
                    }
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(FitnessVisualStyle.divider, lineWidth: 1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 82)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .navigationTitle("健身")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { viewModel.load() }
        .sheet(item: $viewModel.selectedDetail) { detail in
            FitnessCalendarDayDetailSheet(
                model: detail,
                analysisSource: viewModel,
                onShareChanged: { viewModel.setActionRecordShared($0, for: detail.date) },
                onSaveFitnessDetail: { draft in
                    viewModel.saveFitnessDetail(draft: draft)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showingChallengeCelebration) {
            GoalCelebrationView(
                presentation: .halfSheet,
                title: viewModel.challengeCelebrationTitle,
                subtitle: viewModel.challengeCelebrationSubtitle,
                closeTitle: "继续"
            ) {
                viewModel.dismissChallengeCelebration()
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingMonthCalendar, onDismiss: restoreWeekScope) {
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    FitnessCompactCalendarCard(
                        model: viewModel.calendarModel,
                        selectedContext: viewModel.selectedDayContext,
                        showsScopePicker: false,
                        onScopeChange: { _ in },
                        onShift: viewModel.shiftCalendar,
                        onScrollToToday: viewModel.scrollToToday,
                        onSelectDay: { day in
                            viewModel.selectDay(day)
                            showingMonthCalendar = false
                        },
                        onOpenDetail: {
                            showingMonthCalendar = false
                            DispatchQueue.main.async { viewModel.openSelectedDayDetail() }
                        }
                    )
                    .padding(18)
                }
                .background(FitnessVisualStyle.pageBackground.ignoresSafeArea())
                .navigationTitle("训练日历")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { showingMonthCalendar = false }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(FitnessVisualStyle.pageBackground)
        }
        .sheet(isPresented: $showingFitnessAI) {
            HealthAIView(
                fitnessContext: viewModel.fitnessInsightContext,
                initialPrompt: "请解释为什么最近训练状态是这个结论，并说明数据是否足够。"
            )
        }
        .sheet(isPresented: $showingBadges) {
            NavigationStack {
                FitnessBadgeGalleryView(badges: viewModel.badges)
            }
        }
        .sheet(isPresented: $showingTrainingHistory, onDismiss: openPendingTrainingHistoryDetail) {
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    FitnessTrainingLogSection(
                        items: viewModel.trainingLogs,
                        maximumItems: nil,
                        showsTitle: false,
                        onViewAll: nil,
                        onTap: openTrainingHistoryItem
                    )
                    .padding(18)
                }
                .background(FitnessVisualStyle.pageBackground.ignoresSafeArea())
                .navigationTitle("训练记录")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { showingTrainingHistory = false }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(FitnessVisualStyle.pageBackground)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: viewModel.syncMessage)
    }

    @ViewBuilder
    private var trainingCenterContent: some View {
        FitnessHomeHeroCard(
            context: viewModel.fitnessInsightContext,
            achievement: viewModel.achievementCard,
            performance: viewModel.performanceTrackModel,
            nextStep: viewModel.nextStepModel,
            onOpenCalendar: openMonthCalendar,
            onOpenHistory: {
                if hasFitnessHistory {
                    viewModel.openLatestWorkoutDetail()
                } else {
                    viewModel.openTodayDetail()
                }
            },
            onNextStepPrimary: { handleNextStepPrimary() },
            onNextStepSecondary: { handleNextStepSecondary() }
        )

        VStack(spacing: 12) {
            FitnessTrainingWeekStrip(
                model: viewModel.calendarModel,
                selectedDate: viewModel.selectedDate,
                onShiftWeek: viewModel.shiftCalendar,
                onOpenMonth: openMonthCalendar,
                onSelectDay: viewModel.selectDay,
                onToday: viewModel.scrollToToday
            )

            if showsQuickActions {
                FitnessQuickActionStrip(viewModel: viewModel)
            }
        }

        if hasFitnessHistory {
            workoutDetailSection
        }

        VStack(spacing: 12) {
            FitnessPerformanceBento(
                context: viewModel.fitnessInsightContext,
                achievement: viewModel.achievementCard,
                recovery: viewModel.recoveryManagementModel,
                performance: viewModel.performanceTrackModel
            )

            if hasFitnessHistory {
                trendSection
            }

            FitnessAIInsightCard(
                insight: viewModel.fitnessInsight,
                context: viewModel.fitnessInsightContext,
                onOpenAI: { showingFitnessAI = true }
            )
        }

        if !viewModel.trainingLogs.isEmpty {
            FitnessTrainingLogSection(
                items: viewModel.trainingLogs,
                maximumItems: 3,
                onViewAll: { showingTrainingHistory = true },
                onTap: { item in
                    if let day = item.day {
                        viewModel.openDetail(for: day)
                    }
                }
            )
        }

        if !viewModel.badges.isEmpty {
            FitnessBadgePreviewRow(
                badges: viewModel.badges,
                onTap: { showingBadges = true }
            )
        }

        if !viewModel.sharedHighlights.isEmpty {
            FitnessHighlightsSection(
                items: viewModel.sharedHighlights,
                onTap: { item in
                    if let day = item.day {
                        viewModel.openDetail(for: day)
                    }
                }
            )
        }
    }

    private func handleNextStepPrimary() {
        if let mode = viewModel.nextStepModel.primaryMode {
            viewModel.performTodayCheckinInline(mode)
        } else {
            viewModel.openTodayDetail()
        }
    }

    private func handleNextStepSecondary() {
        guard let day = viewModel.calendarModel.days.first(where: { Calendar.current.isDateInToday($0.date) }) ?? viewModel.calendarModel.days.last else { return }
        viewModel.openDetail(for: day)
    }

    private func openTrainingHistoryItem(_ item: FitnessTrainingLogItem) {
        guard let day = item.day else { return }
        pendingTrainingHistoryDay = day
        showingTrainingHistory = false
    }

    private func openPendingTrainingHistoryDetail() {
        guard let day = pendingTrainingHistoryDay else { return }
        pendingTrainingHistoryDay = nil
        viewModel.openDetail(for: day)
    }

    private var hasFitnessHistory: Bool {
        viewModel.fitnessInsightContext.totalSignalDays > 0 ||
            viewModel.fitnessInsightContext.recentTrainingDays > 0
    }

    private var workoutDetailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fitnessSectionTitle(
                "运动详情",
                subtitle: "快速回顾最近一次训练表现",
                symbol: "figure.run",
                tintHex: "246B57"
            )
            FitnessWorkoutReviewCard(
                model: viewModel.workoutReviewModel,
                onOpenLatestDetail: viewModel.openLatestWorkoutDetail
            )
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fitnessSectionTitle(
                "负荷与恢复",
                subtitle: "结合健康数据观察近期训练趋势",
                symbol: "waveform.path.ecg",
                tintHex: "527583"
            )
            FitnessHealthTrendCard(
                loadRecoveryModel: viewModel.loadRecoveryLinkModel,
                performanceModel: viewModel.performanceTrackModel,
                onSelectDate: viewModel.selectDate
            )
        }
    }

    private var fitnessPageBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "F3FAF7"), FitnessVisualStyle.pageBackground, Color(hex: "F1F6F8")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(FitnessVisualStyle.primary.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 72)
                .offset(x: -170, y: -330)

            Circle()
                .fill(FitnessVisualStyle.recovery.opacity(0.07))
                .frame(width: 240, height: 240)
                .blur(radius: 76)
                .offset(x: 180, y: 390)
        }
        .ignoresSafeArea()
    }

    private var fitnessPageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("健身")
                .font(.appSystem(size: 28, weight: .black, design: .rounded))
                .foregroundColor(FitnessVisualStyle.ink)
            Text("训练、恢复与节奏，一页看清")
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(FitnessVisualStyle.muted)
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    private func openMonthCalendar() {
        viewModel.updateCalendarScope(.month)
        showingMonthCalendar = true
    }

    private func restoreWeekScope() {
        if viewModel.calendarScope != .week {
            viewModel.updateCalendarScope(.week)
        }
    }

    private func fitnessSectionTitle(_ title: String, subtitle: String, symbol: String, tintHex: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.appSystem(size: 14, weight: .black))
                .foregroundColor(Color(hex: tintHex))
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }
}


struct FitnessQuickActionStrip: View {
    @Bindable var viewModel: FitnessCalendarViewModel

    var body: some View {
        HStack(spacing: 0) {
            quickAction(
                title: "训练",
                subtitle: "完成",
                systemImage: FitnessCheckinMode.workout.symbol,
                tint: FitnessVisualStyle.primary
            ) {
                viewModel.performTodayCheckin(.workout)
            }

            Divider()
                .padding(.vertical, 12)

            quickAction(
                title: "恢复",
                subtitle: "轻活动",
                systemImage: FitnessCheckinMode.recovery.symbol,
                tint: FitnessVisualStyle.recovery
            ) {
                viewModel.performTodayCheckin(.recovery)
            }

            Divider()
                .padding(.vertical, 12)

            quickAction(
                title: "记录",
                subtitle: "补详情",
                systemImage: "square.and.pencil",
                tint: FitnessVisualStyle.muted
            ) {
                viewModel.openTodayDetail()
            }
        }
        .padding(.horizontal, 6)
        .bbLiquidGlassSurface(
            tint: FitnessVisualStyle.primary,
            in: RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous),
            tintStrength: 0.055,
            shadow: false
        )
    }

    private func quickAction(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.appSystem(size: 18, weight: .bold))
                    .frame(height: 24)
                Text(title)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.appSystem(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(FitnessVisualStyle.muted)
                    .lineLimit(1)
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity, minHeight: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}




struct FitnessWorkoutReviewCard: View {
    let model: FitnessWorkoutReviewModel
    let onOpenLatestDetail: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if model.hasWorkout {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.workoutTitle)
                        .font(.appSystem(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(model.headline)
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(FitnessVisualStyle.semanticColor(for: model.accentHex))
                }

                Divider()
                    .overlay(Theme.Colors.textTertiary.opacity(0.14))

                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(model.metrics) { metric in
                        metricView(metric)
                    }
                }

                HStack(spacing: 9) {
                    statusLabel(model.intensityText, symbol: "bolt.heart.fill", tint: FitnessVisualStyle.warning)
                    statusLabel(model.recoveryText, symbol: "heart.text.square.fill", tint: FitnessVisualStyle.recovery)
                }

                Text(model.detailText)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onOpenLatestDetail) {
                    HStack(spacing: 7) {
                        Text("查看训练详情")
                        Image(systemName: "chevron.right")
                    }
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(FitnessVisualStyle.semanticColor(for: model.accentHex))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(alignment: .top) {
                        Divider()
                            .overlay(Theme.Colors.textTertiary.opacity(0.12))
                    }
                }
                .buttonStyle(.plain)

            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "figure.run.circle")
                        .font(.appSystem(size: 28, weight: .bold))
                        .foregroundColor(FitnessVisualStyle.semanticColor(for: model.accentHex))

                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.headline)
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(model.detailText)
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .fitnessRhythmCard(accentHex: model.accentHex)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "figure.run")
                .font(.appSystem(size: 21, weight: .black))
                .foregroundColor(FitnessVisualStyle.primary)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text("最近训练复盘")
                    .font(.appSystem(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(model.dateText)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer(minLength: 8)

            Text(model.badgeText)
                .font(.appSystem(size: 10, weight: .black, design: .rounded))
                .foregroundColor(FitnessVisualStyle.primary)
        }
    }

    private func metricView(_ metric: FitnessWorkoutReviewMetric) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: metric.symbol)
                .font(.appSystem(size: 14, weight: .black))
                .foregroundColor(FitnessVisualStyle.semanticColor(for: metric.tintHex))
                .frame(width: 25, height: 25)

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.title)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(metric.valueText)
                        .font(.appSystem(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if !metric.unitText.isEmpty {
                        Text(metric.unitText)
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }

    private func statusLabel(_ title: String, symbol: String, tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
    }
}

struct FitnessCompactCalendarCard: View {
    let model: HabitFitnessCalendarModel
    let selectedContext: FitnessSelectedDayContextModel
    var showsScopePicker: Bool = true
    let onScopeChange: (HabitCalendarScope) -> Void
    let onShift: (Int) -> Void
    let onScrollToToday: () -> Void
    let onSelectDay: (HabitFitnessCalendarDay) -> Void
    let onOpenDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsScopePicker {
                HStack(spacing: 8) {
                    ForEach(HabitCalendarScope.allCases) { scope in
                        Button {
                            onScopeChange(scope)
                        } label: {
                            Text(scope.title)
                                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                                .foregroundColor(model.scope == scope ? .white : Theme.Colors.textSecondary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(model.scope == scope ? Color(hex: "007F79") : Color.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 0)

                    Button("今天") { onScrollToToday() }
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "007F79"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.Colors.surface, in: Capsule())
                }
            }

            HStack(spacing: 10) {
                Button { onShift(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: 13, weight: .black))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)

                VStack(spacing: 3) {
                    Text(model.rangeTitle)
                        .font(.appSystem(size: 19, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(model.summaryPills.prefix(2).joined(separator: " · "))
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity)

                Button { onShift(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 13, weight: .black))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if model.scope == .week {
                HStack(alignment: .top, spacing: 9) {
                    ForEach(model.days) { day in
                        FitnessDayButton(day: day, compact: false) { onSelectDay(day) }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    HStack {
                        ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { label in
                            Text(label)
                                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 7), spacing: 9) {
                        ForEach(model.days) { day in
                            FitnessDayButton(day: day, compact: true) { onSelectDay(day) }
                        }
                    }
                }
            }

            calendarLegend
            selectedDaySummary
        }
        .fitnessRhythmCard(accentHex: "58CC6A")
    }

    private var calendarLegend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                calendarLegendItems
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 2), alignment: .leading, spacing: 8) {
                calendarLegendItems
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var calendarLegendItems: some View {
        calendarLegendItem("训练", symbol: FitnessCheckinMode.workout.symbol, tintHex: FitnessCheckinMode.workout.tintHex)
        calendarLegendItem("恢复", symbol: FitnessCheckinMode.recovery.symbol, tintHex: FitnessCheckinMode.recovery.tintHex)
        calendarLegendItem("休息", symbol: FitnessCheckinMode.rest.symbol, tintHex: FitnessCheckinMode.rest.tintHex)
        calendarLegendItem("健康识别", symbol: "sparkles", tintHex: "F4B46B")
    }

    private var selectedDaySummary: some View {
        Button(action: onOpenDetail) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedContext.title)
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(selectedContext.summaryText)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 7) {
                    Text(selectedContext.trainingText)
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: selectedContext.accentHex))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(hex: selectedContext.accentHex).opacity(0.11), in: Capsule())

                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 11, weight: .black))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            .padding(14)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: selectedContext.accentHex).opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开并编辑这一天的健身详情")
    }

    private func calendarLegendItem(_ title: String, symbol: String, tintHex: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.appSystem(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: tintHex))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}

struct FitnessHealthTrendCard: View {
    let loadRecoveryModel: FitnessLoadRecoveryLinkModel
    let performanceModel: FitnessPerformanceTrackModel
    let onSelectDate: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("趋势")
                    .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(performanceModel.changeText)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(FitnessVisualStyle.semanticColor(for: performanceModel.accentHex))
            }

            HStack(spacing: 14) {
                trendMetric(
                    title: "表现",
                    value: performanceModel.scoreText,
                    note: performanceModel.statusText,
                    tint: FitnessVisualStyle.primary
                )

                Rectangle()
                    .fill(FitnessVisualStyle.divider)
                    .frame(width: 1, height: 62)

                trendMetric(
                    title: "负荷",
                    value: loadText,
                    note: loadRecoveryModel.headline,
                    tint: FitnessVisualStyle.recovery
                )
            }

            if !loadRecoveryModel.days.isEmpty {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(loadRecoveryModel.days) { day in
                        Button {
                            onSelectDate(day.date)
                        } label: {
                            VStack(spacing: 7) {
                                Text(day.label)
                                    .font(.appSystem(size: 10, weight: .black, design: .rounded))
                                    .foregroundColor(Theme.Colors.textTertiary)
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(FitnessVisualStyle.semanticColor(for: day.tintHex).opacity(0.10))
                                        .frame(height: 58)
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(FitnessVisualStyle.semanticColor(for: day.tintHex))
                                        .frame(height: barHeight(for: day))
                                }
                                Text(day.stateText)
                                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(FitnessVisualStyle.semanticColor(for: day.tintHex))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                if day.isSelected {
                                    Rectangle()
                                        .fill(FitnessVisualStyle.primary)
                                        .frame(height: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(day.label)，负荷 \(day.loadScore)，恢复 \(day.recoveryScore)，\(day.stateText)"
                        )
                        .accessibilityAddTraits(day.isSelected ? .isSelected : [])
                    }
                }
            }

            Text(performanceModel.detailText)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fitnessRhythmCard(accentHex: performanceModel.accentHex)
    }

    private var loadText: String {
        guard let selected = loadRecoveryModel.days.first(where: \.isSelected) ?? loadRecoveryModel.days.last else {
            return "--"
        }
        return "\(selected.loadScore)/\(selected.recoveryScore)"
    }

    private func trendMetric(title: String, value: String, note: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.appSystem(size: 10, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 22, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(note)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func barHeight(for day: FitnessLoadRecoveryDayModel) -> CGFloat {
        let value = max(day.loadScore, day.recoveryScore)
        return CGFloat(max(14, min(58, value / 2)))
    }
}




private struct FitnessDayButton: View {
    let day: HabitFitnessCalendarDay
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 6 : 8) {
                if !compact {
                    Text(day.dayLabel)
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(day.isSelected ? .white.opacity(0.9) : Theme.Colors.textTertiary)
                }

                Text(day.numberLabel)
                    .font(.appSystem(size: compact ? 15 : 18, weight: .black, design: .rounded))
                    .foregroundColor(day.isSelected ? .white : (day.isInDisplayedMonth ? Theme.Colors.textPrimary : Theme.Colors.textTertiary.opacity(0.4)))

                Text(kcalText)
                    .font(.appSystem(size: compact ? 9 : 11, weight: .bold, design: .rounded))
                    .foregroundColor(day.isSelected ? .white.opacity(0.95) : Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Image(systemName: iconName)
                    .font(.appSystem(size: compact ? 12 : 14, weight: .bold))
                    .foregroundColor(day.isSelected ? .white : Color(hex: day.highlightHex))

                if !compact {
                    Text(day.displayWorkoutMinutes > 0 ? "\(day.displayWorkoutMinutes)m" : day.statusText)
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(day.isSelected ? .white.opacity(0.95) : Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 8 : 10)
            .frame(maxWidth: .infinity)
            .frame(minHeight: compact ? 82 : 138, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: compact ? 18 : 24, style: .continuous)
                    .fill(
                        day.isSelected
                            ? AnyShapeStyle(Color(hex: day.highlightHex))
                            : AnyShapeStyle(Color.white)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 18 : 24, style: .continuous)
                    .stroke(
                        day.isSelected
                            ? Color.white.opacity(0.95)
                            : (day.isInferredWorkoutOnly ? Color(hex: "F4B46B") : Color(hex: "DDEDE6")),
                        style: StrokeStyle(
                            lineWidth: day.isSelected || day.isInferredWorkoutOnly ? 1.6 : 1,
                            dash: day.isInferredWorkoutOnly && !day.isSelected ? [4, 3] : []
                        )
                    )
            )
            .shadow(
                color: day.isSelected || day.isInferredWorkoutOnly ? Color.black.opacity(0.24) : Color.clear,
                radius: 9,
                x: 0,
                y: 5
            )
            .opacity(day.isFuture ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(day.isFuture || !day.isInDisplayedMonth && compact)
        .accessibilityLabel("\(day.dayLabel) \(day.numberLabel) 日")
        .accessibilityValue(dayAccessibilityValue)
        .accessibilityHint(day.isFuture ? "未来日期不可选择" : "选择并查看这一天的健身摘要")
    }

    private var iconName: String {
        if let mode = day.checkinMode {
            return mode.symbol
        }
        if day.isInferredWorkoutOnly {
            return "sparkles"
        }
        return "circle.dashed"
    }

    private var kcalText: String {
        day.activeEnergy > 0 ? "\(day.activeEnergy) kcal" : "— kcal"
    }

    private var dayAccessibilityValue: String {
        let workoutText = day.displayWorkoutMinutes > 0 ? "训练 \(day.displayWorkoutMinutes) 分钟" : day.statusText
        let energyText = day.activeEnergy > 0 ? "活动能量 \(day.activeEnergy) 千卡" : "暂无活动能量"
        return "\(workoutText)，\(energyText)"
    }
}


struct FitnessBadgePreviewRow: View {
    let badges: [FitnessBadgeModel]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("徽章")
                        .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(FitnessVisualStyle.ink)
                    Spacer()
                    HStack(spacing: 5) {
                        Text("查看全部")
                        Image(systemName: "chevron.right")
                            .font(.appSystem(size: 9, weight: .bold))
                    }
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(FitnessVisualStyle.primary)
                }

                HStack(spacing: 10) {
                    ForEach(Array(badges.prefix(4))) { badge in
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill((badge.isUnlocked ? Color(hex: badge.tintHex) : Color(hex: "DDE4F0")).opacity(badge.isUnlocked ? 0.16 : 0.55))
                                    .frame(width: 52, height: 52)
                                Image(systemName: badge.symbol)
                                    .font(.appSystem(size: 18, weight: .black))
                                    .foregroundColor(badge.isUnlocked ? Color(hex: badge.tintHex) : Theme.Colors.textTertiary.opacity(0.5))
                            }
                            Text(badge.title)
                                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Text("已解锁 \(badges.filter(\.isUnlocked).count)/\(badges.count)")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}


struct FitnessHighlightsSection: View {
    let items: [FitnessSharedHighlightItem]
    let onTap: (FitnessSharedHighlightItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近亮点")
                        .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("共享记录和高光训练日。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
            }

            if items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("还没有亮点记录")
                        .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("训练或共享后，这里会出现高光记录。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    FitnessVisualStyle.surface,
                    in: RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous)
                        .stroke(FitnessVisualStyle.divider, lineWidth: 1)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            onTap(item)
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(ChineseDateText.writtenMonthDay(item.date))
                                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(FitnessVisualStyle.recovery)
                                    Text(item.title)
                                        .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    Text(item.subtitle)
                                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(Theme.Colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 10)

                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(FitnessVisualStyle.primary)
                                        .frame(width: 6, height: 6)
                                    Text(item.badgeText)
                                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(FitnessVisualStyle.primary)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < items.count - 1 {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(
                    FitnessVisualStyle.surface,
                    in: RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous)
                        .stroke(FitnessVisualStyle.divider, lineWidth: 1)
                }
            }
        }
    }
}

struct FitnessBadgeGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let badges: [FitnessBadgeModel]

    var body: some View {
        ScrollView(showsIndicators: false) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("全部徽章")
                        .font(.appSystem(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("已解锁 \(badges.filter(\.isUnlocked).count)/\(badges.count)")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.padding)
            .padding(.top, 20)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(badges) { badge in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill((badge.isUnlocked ? Color(hex: badge.tintHex) : Color(hex: "DDE4F0")).opacity(badge.isUnlocked ? 0.16 : 0.55))
                                    .frame(width: 56, height: 56)
                                Image(systemName: badge.symbol)
                                    .font(.appSystem(size: 22, weight: .black))
                                    .foregroundColor(badge.isUnlocked ? Color(hex: badge.tintHex) : Theme.Colors.textTertiary.opacity(0.45))
                            }
                            Spacer()
                            Text(badge.isUnlocked ? "已解锁" : "未解锁")
                                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(badge.isUnlocked ? Color(hex: badge.tintHex) : Theme.Colors.textTertiary)
                        }

                        Text(badge.title)
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(badge.subtitle)
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .padding(16)
                    .background(
                        badge.isUnlocked ? Theme.Colors.surface : Theme.Colors.secondaryBackground,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(badge.isUnlocked ? Color(hex: badge.tintHex).opacity(0.15) : Theme.Colors.surfaceBorder, lineWidth: 0.5)
                    )
                }
            }
            .padding(Theme.Layout.padding)
            .padding(.bottom, 24)
        }
        .background(
            Theme.Colors.pageBackground
            .ignoresSafeArea()
        )
        .navigationTitle("徽章")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
    }
}


struct FitnessTrainingLogSection: View {
    let items: [FitnessTrainingLogItem]
    var maximumItems: Int? = 4
    var showsTitle: Bool = true
    /// 迷你运动月历的数据源；为 nil 时列表上方不渲染月历卡。
    var miniMonthModel: MiniMonthModel? = nil
    let onViewAll: (() -> Void)?
    let onTap: (FitnessTrainingLogItem) -> Void

    struct MiniMonthModel {
        let days: [HabitFitnessCalendarDay]
        let displayedMonth: Date
        let selectedDate: Date
        let tint: Color
        let onShiftMonth: (Int) -> Void
        let onSelectDay: (HabitFitnessCalendarDay) -> Void
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsTitle {
                HStack(alignment: .firstTextBaseline) {
                    Text("训练记录")
                        .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(FitnessVisualStyle.ink)

                    Spacer()

                    if let onViewAll, items.count > displayedItems.count {
                        Button(action: onViewAll) {
                            HStack(spacing: 5) {
                                Text("查看全部")
                                Image(systemName: "chevron.right")
                                    .font(.appSystem(size: 9, weight: .bold))
                            }
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(FitnessVisualStyle.primary)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let miniMonthModel {
                FitnessMiniMonthCalendarView(
                    days: miniMonthModel.days,
                    displayedMonth: miniMonthModel.displayedMonth,
                    selectedDate: miniMonthModel.selectedDate,
                    tint: miniMonthModel.tint,
                    onShiftMonth: miniMonthModel.onShiftMonth,
                    onSelectDay: miniMonthModel.onSelectDay
                )
            }

            if items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("还没有训练记录")
                        .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("打卡或同步训练分钟后显示。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    FitnessVisualStyle.surface,
                    in: RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous)
                        .stroke(FitnessVisualStyle.divider, lineWidth: 1)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            onTap(item)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: item.mode?.symbol ?? "figure.run")
                                    .font(.appSystem(size: 16, weight: .bold))
                                    .foregroundColor(tint(for: item))
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title)
                                        .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    Text(item.statsLine)
                                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(Theme.Colors.textSecondary)
                                    if !item.note.isEmpty {
                                        Text(item.note)
                                            .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundColor(FitnessVisualStyle.primary)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer(minLength: 8)

                                VStack(alignment: .trailing, spacing: 8) {
                                    Text(item.subtitle)
                                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.Colors.textTertiary)
                                    Image(systemName: "chevron.right")
                                        .font(.appSystem(size: 10, weight: .bold))
                                        .foregroundColor(Theme.Colors.textTertiary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < displayedItems.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(
                    FitnessVisualStyle.surface,
                    in: RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous)
                        .stroke(FitnessVisualStyle.divider, lineWidth: 1)
                }
            }
        }
    }

    private var displayedItems: [FitnessTrainingLogItem] {
        guard let maximumItems else { return items }
        return Array(items.prefix(maximumItems))
    }

    private func tint(for item: FitnessTrainingLogItem) -> Color {
        switch item.mode {
        case .some(.recovery):
            return FitnessVisualStyle.recovery
        case .some(.rest):
            return FitnessVisualStyle.muted
        case .some(.workout), .none:
            return FitnessVisualStyle.primary
        }
    }
}



struct FitnessNextStepCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: FitnessNextStepModel
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(model.title)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(accent)
                Spacer()
                Text("今天")
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.surface.opacity(0.72), in: Capsule())
            }

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: model.symbol)
                    .font(.appSystem(size: 22, weight: .black))
                    .foregroundColor(accent)
                    .frame(width: 50, height: 50)
                    .background(Theme.Colors.surface.opacity(0.82), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(model.headline)
                        .font(.appSystem(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(FitnessVisualStyle.ink)
                    Text(model.detailText)
                        .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(FitnessVisualStyle.muted)
                        .lineLimit(3)
                }
            }

            HStack(spacing: 0) {
                ForEach(Array(model.chips.prefix(3).enumerated()), id: \.offset) { index, chip in
                    Group {
                        Text(chip)
                            .font(.appSystem(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(FitnessVisualStyle.muted)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, minHeight: 34)

                        if index < min(model.chips.count, 3) - 1 {
                            Divider()
                                .frame(height: 28)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.Colors.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            actionButtons
        }
        .padding(18)
        .bbLiquidGlassSurface(
            tint: accent,
            in: RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous),
            tintStrength: 0.11
        )
    }

    private var accent: Color {
        FitnessVisualStyle.semanticColor(for: model.accentHex)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalActions
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalActions
                verticalActions
            }
        }
    }

    private var horizontalActions: some View {
        HStack(spacing: 16) {
            primaryActionButton

            if model.primaryMode != nil {
                secondaryActionButton
            }
        }
    }

    private var verticalActions: some View {
        VStack(spacing: 6) {
            primaryActionButton

            if model.primaryMode != nil {
                secondaryActionButton
            }
        }
    }

    private var primaryActionButton: some View {
        Button(action: onPrimary) {
            Label(model.primaryActionTitle, systemImage: model.primaryMode?.symbol ?? "square.and.pencil")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 15)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(accent, in: RoundedRectangle(cornerRadius: FitnessVisualStyle.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var secondaryActionButton: some View {
        Button(action: onSecondary) {
            HStack(spacing: 6) {
                Text(model.secondaryActionTitle)
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 9, weight: .bold))
            }
            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


private func statusChip(title: String, tint: String) -> some View {
    Text(title)
        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
        .foregroundColor(Color(hex: tint))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(hex: tint).opacity(0.12), in: Capsule())
}

private func rhythmSectionHeader(title: String, subtitle: String? = nil) -> some View {
    HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 22, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Spacer()
    }
}

private struct FitnessRhythmCardModifier: ViewModifier {
    let accentHex: String
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .bbLiquidGlassSurface(
                tint: FitnessVisualStyle.semanticColor(for: accentHex),
                in: RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous),
                tintStrength: 0.055,
                shadow: false
            )
    }
}

private extension View {
    func fitnessRhythmCard(accentHex: String, padding: CGFloat = 20) -> some View {
        modifier(FitnessRhythmCardModifier(accentHex: accentHex, padding: padding))
    }
}

private func legendItem(symbol: String, title: String, tint: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: symbol)
            .font(.appSystem(size: 10, weight: .bold))
            .foregroundColor(Color(hex: tint))
        Text(title)
            .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.Colors.textTertiary)
    }
}

private func miniStat(title: String, value: String, tint: String) -> some View {
    VStack(alignment: .trailing, spacing: 3) {
        Text(title)
            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(Theme.Colors.textTertiary)
        Text(value)
            .font(.appSystem(size: 14, weight: .black, design: .rounded))
            .foregroundColor(Color(hex: tint))
    }
}
