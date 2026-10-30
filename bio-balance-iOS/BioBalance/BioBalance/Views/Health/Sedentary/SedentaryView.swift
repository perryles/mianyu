/// SedentaryView 由 HealthHubView 调用，作为「久坐提醒」详情页入口。
/// 负责汇总展示当天久坐状态、打断计划、今日日志、提醒设置与往日日志入口。

import SwiftUI

/// 主久坐提醒总页 由 [HealthHubView] 调用，作为健康页面里「久坐提醒」详情页入口。
/// 负责汇总展示当天久坐状态、打断计划、今日日志、设置，以及进入往日日志子页的入口。
///
/// 与睡眠、鼾声报告统一阅读层级：状态摘要 → 指标分布 → 洞察与记录 → 行动与设置。
struct SedentaryView: View {
    @Bindable var viewModel: DashboardViewModel
    var showsDismissButtons: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingHistoryPage = false
    @State private var showingNotificationDeniedAlert = false
    @State private var selectedBreakMinutes = 3
    private let reminderIntervalOptions = [30, 45, 60, 90, 120]

    var body: some View {
        ZStack {
            Theme.Colors.surface.ignoresSafeArea()

            AdaptivePageScrollView(style: .reading, topPadding: 20, bottomPadding: 64, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    pageHeroSection
                    reportSection { standingDistribution }
                    reportSection { rhythmInsightCard }
                    reportSection { todayLogCard }
                    reportSection { breakDurationCard }
                    reportSection { settingsCard }
                    reportSection { historyEntryButton }
                    reportSection { dataEvidenceCard }
                }
            }
        }
        .healthDetailNavigation(title: HealthPageName.sedentaryReminder)
        .toolbarBackground(Theme.Colors.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if showsDismissButtons {
                ToolbarItem(placement: .topBarLeading) {
                    HealthNavigationDismissButton {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if !viewModel.sedentaryBreakProgress.isActive {
                selectedBreakMinutes = SedentaryBreakProgressState.defaultTargetMinutes(for: state)
            }
            viewModel.refreshSedentaryBreakProgress()
        }
        .sheet(isPresented: $showingHistoryPage) {
            NavigationStack {
                SedentaryHistoryView(viewModel: viewModel)
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .alert("通知未开启", isPresented: $showingNotificationDeniedAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("请先在系统设置中允许眠屿发送通知，久坐提醒才能正常送达。")
        }
    }

    // MARK: 首屏卡片

    private var pageHeroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("久坐与站立")
                .font(.appSystem(size: 28, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(summary.date.formatted(.dateTime.month().day().weekday(.wide)))
                .font(.appSystem(size: 12))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.top, 8)

            Text(heroMetricTitle)
                .font(.appSystem(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.top, 28)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(heroValueText)
                    .font(.appSystem(size: 84, weight: .heavy))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("分钟")
                    .font(.appSystem(size: 16, weight: .semibold))
            }
            .foregroundStyle(heroAccent)
            .accessibilityElement(children: .combine)

            Label(breakProgress.isActive ? String(localized: "打断进行中") : state.statusTitle, systemImage: statusSymbol)
                .font(.appSystem(size: 15, weight: .semibold))
                .foregroundStyle(heroAccent)
            Text(heroBubbleText)
                .font(.appSystem(size: 13))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            heroActionButton
                .padding(.top, 24)
        }
        .padding(.bottom, 28)
    }

    /// 与鼾声连续报告一致，模块之间只保留分隔线和留白，不嵌套整块卡片。
    private func reportSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.Colors.textTertiary.opacity(0.16))
                .frame(height: 1)
                .accessibilityHidden(true)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, adaptiveLayout.usesExpandedLayout ? 37 : 28)
                .padding(.bottom, 28)
        }
    }

    private var heroAccent: Color {
        // 小字号状态文案使用深色，保留绿色主题同时确保浅色背景上的对比度。
        if breakProgress.isActive || (state.sourceStatus == .ready && state.elapsedMinutes < 60) {
            return Color(hex: "268365")
        }
        if state.sourceStatus == .ready && state.elapsedMinutes < 90 {
            return Color(hex: "A36B16")
        }
        return tint
    }

    private var standingDistribution: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("今日站立分布")
                .font(.appSystem(size: 20, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                alignment: .leading,
                spacing: 20
            ) {
                ForEach(standingMetrics) { metric in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(metric.title, systemImage: metric.symbol ?? "circle")
                            .font(.appSystem(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(metric.value)
                            .font(.appSystem(size: 22, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var standingMetrics: [ModernReportMetric] {
        [
            ModernReportMetric(
                title: String(localized: "最长久坐"),
                value: summary.longestSessionMinutes.bbFormattedDurationHoursMinutes,
                tint: Color(hex: "FF9A32"),
                symbol: "timer"
            ),
            ModernReportMetric(
                title: String(localized: "站立次数"),
                value: String(localized: "\(summary.activeBreakCount) 次"),
                tint: Theme.Colors.mintGreen,
                symbol: "figure.walk.motion"
            ),
            ModernReportMetric(
                title: String(localized: "站立时长"),
                value: summary.totalReliefMinutes.bbFormattedDurationHoursMinutes,
                tint: Color(hex: "2F91FF"),
                symbol: "figure.stand"
            ),
            ModernReportMetric(
                title: String(localized: "久坐时间"),
                value: summary.totalSedentaryMinutes.bbFormattedDurationHoursMinutes,
                tint: Color(hex: "FF5F7E"),
                symbol: "chair.lounge"
            )
        ]
    }

    private var heroActionButton: some View {
        Button(action: performHeroAction) {
            Label(heroActionTitle, systemImage: heroActionSymbol)
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(heroAccent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func heroFact(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.appSystem(size: 12, weight: .black))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.11), in: Circle())
            Text(title)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.Colors.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: 打断时长选择

    private var breakDurationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("现在就动一动")
                        .font(.appSystem(size: 20, weight: .bold))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("选择一段你愿意完成的轻量活动")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "7A8794"))
                }
                Spacer()
                Image(systemName: "figure.walk.motion")
                    .foregroundColor(Color(hex: "316DF4"))
                    .padding(9)
                    .background(Color(hex: "EAF0FF"), in: Circle())
            }

            HStack(spacing: 8) {
                ForEach(breakTargetOptions, id: \.self) { minute in
                    Button {
                        selectedBreakMinutes = minute
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(minute)")
                                .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(selectedBreakMinutes == minute ? Color(hex: "316DF4") : Color(hex: "1A2030"))
                            Text("分钟")
                                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedBreakMinutes == minute
                                      ? Color(hex: "316DF4").opacity(0.08)
                                      : Theme.Colors.secondarySurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selectedBreakMinutes == minute
                                        ? Color(hex: "316DF4")
                                        : Color(hex: "E7EAF2"),
                                        lineWidth: selectedBreakMinutes == minute ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(minute) 分钟"))
                    .accessibilityAddTraits(selectedBreakMinutes == minute ? .isSelected : [])
                    .sensoryFeedback(.selection, trigger: selectedBreakMinutes)
                }
            }
        }
    }

    // MARK: 今日节律洞察

    private var rhythmInsightCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今日洞察")
                    .font(.appSystem(size: 20, weight: .bold))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(rhythmInsightSummary)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                insightRow(
                    title: "最长连续久坐",
                    value: summary.longestSessionMinutes.bbFormattedDurationCompact,
                    detail: longestSession?.timeRangeText ?? String(localized: "等待形成记录"),
                    symbol: "hourglass.bottomhalf.filled",
                    accent: summary.longestSessionMinutes >= 60 ? Color(hex: "FF7A59") : Color(hex: "316DF4")
                )
                insightRow(
                    title: "累计活动",
                    value: summary.totalReliefMinutes.bbFormattedDurationCompact,
                    detail: String(localized: "来自今日主动打断"),
                    symbol: "figure.walk.motion",
                    accent: Color(hex: "2E9B68")
                )
                insightRow(
                    title: "最近一次打断",
                    value: summary.lastBreakKind?.title ?? String(localized: "暂无"),
                    detail: summary.activeBreakCount > 0
                        ? String(localized: "今天已完成 \(summary.activeBreakCount) 次")
                        : String(localized: "起身活动后会记录在这里"),
                    symbol: summary.lastBreakKind?.symbol ?? "figure.stand",
                    accent: Color(hex: "586CDE")
                )
            }
        }
    }

    private func insightRow(
        title: LocalizedStringKey,
        value: String,
        detail: String,
        symbol: String,
        accent: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.appSystem(size: 15, weight: .black))
                .foregroundColor(accent)
                .frame(width: 38, height: 38)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                Text(detail)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "8A95A3"))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(accent)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: 今日记录时间轴

    private var todayLogCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日记录")
                    .font(.appSystem(size: 20, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Image(systemName: "chart.bar.xaxis")
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "8B98A6"))
            }

            if summary.sourceStatus == .ready, !summary.sessions.isEmpty {
                SedentaryTimelineChartView(summary: summary)
            } else {
                detailEmptyState(
                    title: summary.sourceStatus == .needsAuthorization ? "授权后开始记录日志" : "今天还没有形成日志",
                    detail: summary.sourceStatus == .needsAuthorization
                        ? "允许读取步数、运动和站立数据后，这里会补上今天的久坐时间轴。"
                        : "等今天出现更连续的久坐段后，这里会按时间轴展示它们。"
                )
            }
        }
    }

    // MARK: 数据依据

    private var dataEvidenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.appSystem(size: 16, weight: .black))
                    .foregroundColor(Color(hex: "316DF4"))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: "EAF0FF"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("数据依据")
                        .font(.appSystem(size: 20, weight: .bold))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("帮助你理解久坐记录从哪里来")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            evidenceRow(title: "识别依据", value: String(localized: "活动、步数与站立数据"), symbol: "applewatch.radiowaves.left.and.right")
            evidenceRow(title: "睡眠保护", value: String(localized: "睡眠期间自动暂停"), symbol: "moon.zzz.fill")
            evidenceRow(
                title: "最近更新",
                value: summary.updatedAt.formatted(.dateTime.hour().minute()),
                symbol: "arrow.clockwise"
            )
        }
    }

    private func evidenceRow(title: LocalizedStringKey, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "586CDE"))
                .frame(width: 26)
            Text(title)
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "536172"))
            Spacer(minLength: 8)
            Text(value)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: 提醒设置开关

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: viewModel.sedentaryReminderEnabled ? "bell.badge.fill" : "bell.slash.fill")
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "2E9B68"))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: "DFF7EA"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("久坐提醒")
                        .font(.appSystem(size: 20, weight: .bold))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(viewModel.sedentaryReminderEnabled ? "每 \(viewModel.sedentaryReminderIntervalMinutes) 分钟提醒一次" : "提醒已暂停")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.sedentaryReminderEnabled },
                    set: updateReminderEnabled
                ))
                .labelsHidden()
                .accessibilityLabel("久坐提醒")
                .tint(Color(hex: "63D471"))
            }
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 10) {
                Text("提醒频率")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    ForEach(reminderIntervalOptions, id: \.self) { minute in
                        reminderIntervalButton(minute)
                    }
                }
                .disabled(!viewModel.sedentaryReminderEnabled)
                .opacity(viewModel.sedentaryReminderEnabled ? 1 : 0.45)
            }
            .padding(12)
            .background(Color(hex: "F4FBF7"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            settingDivider()

            settingToggleRow(
                title: "自动识别久坐",
                isOn: viewModel.sedentaryAutoStartEnabled,
                tint: Color(hex: "63D471")
            ) {
                viewModel.setSedentaryAutoStartEnabled($0)
            }

            settingDivider()

            settingInfoRow(title: "睡眠期间", value: "自动暂停", symbol: "moon.zzz.fill")

            settingDivider()

            settingInfoRow(title: "提醒依据", value: "活动与站立数据", symbol: "applewatch.radiowaves.left.and.right")
        }
    }

    // MARK: 往日日志入口

    private var historyEntryButton: some View {
        Button {
            showingHistoryPage = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.appSystem(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: "586CDE"))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: "EEF1FF"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("往日日志")
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("\(historySummaries.count) 天记录")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "586CDE"))
                    .frame(width: 30, height: 30)
                    .background(Color(hex: "F3F5FF"), in: Circle())
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Hero 计算属性

    private var heroValueText: String {
        if breakProgress.isActive {
            return "\(max(1, breakProgress.elapsedMinutes(now: Date())))"
        }
        return state.isCounting ? "\(state.elapsedMinutes)" : "--"
    }

    private var heroMetricTitle: String {
        breakProgress.isActive ? String(localized: "活动分钟") : String(localized: "连续久坐分钟")
    }

    private var heroHeadline: String {
        if breakProgress.isActive { return "正在打断久坐" }
        if state.isCounting { return "已坐 \(state.elapsedMinutes) 分钟" }
        return state.statusTitle
    }

    private var longestSession: SedentaryTimelineSegment? {
        summary.sessions.max { $0.durationMinutes < $1.durationMinutes }
    }

    private var rhythmInsightSummary: String {
        guard summary.sourceStatus == .ready else {
            return String(localized: "数据就绪后，这里会解释今天的久坐节律。")
        }
        guard summary.totalSedentaryMinutes > 0 else {
            return String(localized: "今天还没有明显的连续久坐，继续保持自然活动。")
        }
        if summary.longestSessionMinutes >= 90 {
            return String(localized: "今天已经出现较长的连续久坐，优先打断最长的一段。")
        }
        if summary.activeBreakCount > 0 {
            return String(localized: "你已经主动拆开了部分久坐，继续保持这个节奏。")
        }
        return String(localized: "累计时长仍在形成，第一次主动打断会让节律更清晰。")
    }

    private var heroProgress: CGFloat {
        if breakProgress.isActive {
            let elapsed = max(1, breakProgress.elapsedMinutes(now: Date()))
            return min(max(CGFloat(elapsed) / CGFloat(max(breakProgress.targetMinutes, 1)), 0.08), 1)
        }
        guard state.isCounting else { return 0.10 }
        return min(max(CGFloat(state.elapsedMinutes) / 120, 0.08), 1)
    }

    private var heroBubbleText: String {
        if breakProgress.isActive {
            return String(localized: "打断进行中 · 目标 \(breakProgress.targetMinutes) 分钟")
        }
        if state.isCounting {
            return String(localized: "建议打断 · \(state.recommendedBreakText)")
        }
        return state.statusDetail
    }

    private var heroBubbleSymbol: String {
        breakProgress.isActive ? "figure.walk.motion" : statusSymbol
    }

    private var heroActionTitle: String {
        if state.sourceStatus == .needsAuthorization { return "开启健康权限" }
        if breakProgress.isActive { return "继续本次打断" }
        if breakProgress.isCompletedFeedbackVisible { return "查看打断结果" }
        if breakPlanCanStart { return "开始 \(selectedBreakMinutes) 分钟打断" }
        return String(localized: "查看今日行动")
    }

    private var heroActionSymbol: String {
        state.sourceStatus == .needsAuthorization ? "heart.text.square.fill" : "figure.walk.motion"
    }

    private func performHeroAction() {
        if state.sourceStatus == .needsAuthorization {
            Task {
                try? await HealthKitManager.shared.requestAuthorization()
                await viewModel.refreshSedentaryState()
            }
        } else if breakPlanCanStart && !breakProgress.isActive && !breakProgress.isCompletedFeedbackVisible {
            viewModel.startSedentaryBreak(durationMinutes: selectedBreakMinutes)
        }
    }

    private var heroBackgroundColor: Color {
        if breakProgress.isActive { return Color(hex: "E2F7EF") }
        switch state.sourceStatus {
        case .needsAuthorization: return Color(hex: "E7F1FD")
        case .sleeping: return Color(hex: "EFEAFC")
        case .autoStartDisabled, .noActivitySamples: return Color(hex: "EAF1F6")
        case .unavailable: return Color(hex: "FDECE7")
        case .ready:
            if state.elapsedMinutes >= 90 { return Color(hex: "FDECE7") }
            if state.elapsedMinutes >= 60 { return Color(hex: "FDF2D9") }
            return state.isCounting ? Color(hex: "E7F1FD") : Color(hex: "E2F7EF")
        }
    }

    // MARK: 数据

    private var state: DashboardSedentaryState { viewModel.sedentaryState }
    private var summary: SedentaryDaySummary { viewModel.sedentaryTodaySummary }
    private var historySummaries: [SedentaryDaySummary] {
        viewModel.sedentaryRecentSummaries
            .filter { !Calendar.current.isDateInToday($0.date) }
            .sorted { $0.date > $1.date }
    }

    private var breakProgress: SedentaryBreakProgressState {
        viewModel.sedentaryBreakProgress
    }

    private var breakTargetOptions: [Int] { [3, 5, 10] }

    private var breakPlanCanStart: Bool {
        switch state.sourceStatus {
        case .ready:
            return state.isCounting
        case .needsAuthorization, .sleeping, .autoStartDisabled, .noActivitySamples, .unavailable:
            return false
        }
    }

    private var tint: Color {
        if breakProgress.isActive { return Color(hex: "63D471") }
        if state.sourceStatus == .needsAuthorization { return Color(hex: "5E8CFF") }
        if state.sourceStatus == .autoStartDisabled { return Theme.Colors.textTertiary }
        if state.sourceStatus == .noActivitySamples { return Theme.Colors.textTertiary }
        if state.sourceStatus == .unavailable { return Theme.Colors.accentRed }
        if state.elapsedMinutes >= 90 { return Color(hex: "FF7A59") }
        if state.elapsedMinutes >= 60 { return Color(hex: "F4C430") }
        return Color(hex: "63D471")
    }

    private var statusSymbol: String {
        if breakProgress.isActive { return "figure.walk.motion" }
        if state.sourceStatus == .needsAuthorization { return "heart.text.square.fill" }
        if state.sourceStatus == .autoStartDisabled { return "pause.circle.fill" }
        if state.sourceStatus == .noActivitySamples { return "applewatch.radiowaves.left.and.right" }
        if state.sourceStatus == .unavailable { return "exclamationmark.icloud.fill" }
        return state.isCounting ? "figure.seated.side" : "figure.walk.motion"
    }

    // MARK: 卡片基础组件

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(Theme.Colors.textTertiary)
    }

    private func statItem(value: String, label: String, valueColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.appSystem(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(valueColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func statDivider() -> some View {
        Rectangle()
            .fill(Theme.Colors.secondaryBackground)
            .frame(width: 1, height: 32)
    }

    private func settingToggleRow(
        title: String,
        isOn: Bool,
        tint: Color,
        action: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { isOn }, set: action))
                .labelsHidden()
                .tint(tint)
        }
        .padding(.vertical, 10)
    }

    private func settingDivider() -> some View {
        Divider()
            .overlay(Theme.Colors.surfaceBorder)
    }

    private func settingInfoRow(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundColor(Color(hex: "2E9B68"))
                .frame(width: 28)
            Text(title)
                .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
            Text(value)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.vertical, 11)
    }

    private func reminderIntervalButton(_ minute: Int) -> some View {
        let isSelected = viewModel.sedentaryReminderIntervalMinutes == minute
        return Button {
            viewModel.setSedentaryReminderIntervalMinutes(minute)
        } label: {
            Text("\(minute) 分钟")
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(isSelected ? .white : Color(hex: "35644F"))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    isSelected ? Color(hex: "2E9B68") : Color.white,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.clear : Color(hex: "D5E9DE"), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("每 \(minute) 分钟提醒一次")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func updateReminderEnabled(_ enabled: Bool) {
        guard enabled else {
            viewModel.setSedentaryReminderEnabled(false)
            return
        }

        Task {
            let granted = await LocalNotificationScheduler.requestAuthorizationIfNeeded()
            guard granted else {
                showingNotificationDeniedAlert = true
                return
            }
            viewModel.setSedentaryReminderEnabled(true)
        }
    }

    private func detailEmptyState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(detail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

private struct SedentaryHeroMeter: View {
    let valueText: String
    let metricTitle: String
    let progress: CGFloat
    let accent: Color
    let symbol: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.62))
                .frame(width: 124, height: 124)

            Circle()
                .stroke(accent.opacity(0.14), lineWidth: 9)
                .frame(width: 112, height: 112)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 112, height: 112)

            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 14, weight: .black))
                    .foregroundColor(accent)

                Text(valueText)
                    .font(.appSystem(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(metricTitle)
                    .font(.appSystem(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metricTitle) \(valueText)")
    }
}

/// 往日久坐日志子页 由 [SedentaryView] 调用，作为“往日日志”二级页面内容承载页。
/// 负责按天展示最近几天的久坐节律、打断记录与重点时段回顾，并支持展开单日时间轴。
private struct SedentaryHistoryView: View {
    @Bindable var viewModel: DashboardViewModel
    @State private var expandedDayIDs = Set<TimeInterval>()
    @State private var selectedHistoryDate = Calendar.current.startOfDay(for: Date())
    @State private var showingHistoryDatePicker = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("往日日志")
                            .font(.appSystem(size: 28, weight: .heavy, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("按天回看最近几天的久坐节律、打断频率和最需要调整的时段。")
                            .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    historyDatePickerButton

                    if historySummaries.isEmpty {
                        historyEmptyState(
                            title: "还没有形成往日记录",
                            detail: "继续佩戴 Apple Watch 并保持健康同步，系统会逐步补齐最近几天的久坐日志。"
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                historyHeroPill(title: "记录天数", value: "\(historySummaries.count)天", tint: Color(hex: "75C7E8"))
                                historyHeroPill(title: "日均久坐", value: averageSedentaryText, tint: Color(hex: "FF946E"))
                                historyHeroPill(title: "日均打断", value: averageBreaksText, tint: Color(hex: "63D471"))
                            }
                        }

                        ForEach(historySummaries) { day in
                            sedentaryHistoryDayCard(day)
                                .id(day.id)
                        }

                        historyLoadMoreSection
                    }
                }
                .padding(.horizontal, Theme.Layout.padding)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .background(Theme.Colors.pageBackground.ignoresSafeArea())
            .navigationTitle("往日日志")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingHistoryDatePicker) {
                SedentaryHistoryDatePickerSheet(
                    selectedDate: $selectedHistoryDate,
                    minimumDate: viewModel.sedentaryHistoryMinimumDate
                )
                .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
            }
            .onAppear {
                if let firstHistoryDate = historySummaries.first?.date {
                    selectedHistoryDate = firstHistoryDate
                }
            }
            .onChange(of: selectedHistoryDate) { _, newValue in
                Task {
                    await viewModel.ensureSedentaryHistoryContains(date: newValue)
                    await MainActor.run {
                        scrollToHistoryDate(newValue, proxy: proxy)
                    }
                }
            }
        }
    }

    private var historyDatePickerButton: some View {
        Button {
            showingHistoryDatePicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(width: 30, height: 30)
                    .bbTintedChip(tint: Color(hex: "C9D7E8"), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("选择日期")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(historySelectedDateText)
                        .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.appSystem(size: 11, weight: .bold))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var historyLoadMoreSection: some View {
        if viewModel.isLoadingMoreSedentaryHistory {
            HStack {
                Spacer(minLength: 0)
                ProgressView("正在加载更早记录")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        } else if viewModel.hasMoreSedentaryHistory {
            Button {
                Task {
                    await viewModel.loadMoreSedentaryHistory()
                }
            } label: {
                HStack {
                    Spacer(minLength: 0)
                    Text("加载更早记录")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private var historySelectedDateText: String {
        selectedHistoryDate.formatted(.dateTime.year().month(.wide).day().weekday(.wide))
    }

    private func scrollToHistoryDate(_ date: Date, proxy: ScrollViewProxy) {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        if let targetDay = historySummaries.first(where: { calendar.isDate($0.date, inSameDayAs: targetDate) }) {
            proxy.scrollTo(targetDay.id, anchor: .top)
        }
    }

    private var historySummaries: [SedentaryDaySummary] {
        viewModel.sedentaryRecentSummaries
            .filter { !Calendar.current.isDateInToday($0.date) }
            .sorted { $0.date > $1.date }
    }

    private var averageSedentaryText: String {
        guard !historySummaries.isEmpty else { return "暂无" }
        let average = Int((Double(historySummaries.reduce(0) { $0 + $1.totalSedentaryMinutes }) / Double(historySummaries.count)).rounded())
        return average.bbFormattedDurationCompact
    }

    private var averageBreaksText: String {
        guard !historySummaries.isEmpty else { return "暂无" }
        let average = Double(historySummaries.reduce(0) { $0 + $1.activeBreakCount }) / Double(historySummaries.count)
        return String(format: String(localized: "%.1f次"), average)
    }

    private func sedentaryHistoryDayCard(_ day: SedentaryDaySummary) -> some View {
        let isExpanded = expandedDayIDs.contains(day.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).weekday(.abbreviated)))
                        .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(historyStatusText(for: day))
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                Button {
                    toggleExpanded(day)
                } label: {
                    HStack(spacing: 6) {
                        Text(isExpanded ? "收起时间轴" : "查看时间轴")
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.appSystem(size: 11, weight: .bold))
                    }
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                historyMetricPill(title: "累计久坐", value: day.totalSedentaryMinutes.bbFormattedDurationHoursMinutes, tint: Color(hex: "75C7E8"))
                historyMetricPill(title: "打断次数", value: "\(day.activeBreakCount)次", tint: Color(hex: "63D471"))
                historyMetricPill(title: "最长单次", value: day.longestSessionMinutes.bbFormattedDurationCompact, tint: Color(hex: "FF946E"))
            }

            if day.sourceStatus == .ready, !day.sessions.isEmpty {
                SedentarySummaryStripView(summary: day)

                if let focusSession = day.focusSession {
                    historyFocusRow(day: day, session: focusSession)
                }

                Text(viewModel.sedentaryHistoryTakeaway(for: day))
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                historyEmptyState(
                    title: "当天没有形成可读日志",
                    detail: day.sourceStatus == .needsAuthorization
                        ? "当天缺少健康权限，暂时没法恢复久坐判断。"
                        : "当天没有足够连续的久坐段，因此没有生成时段时间轴。"
                )
            }

            if isExpanded, day.sourceStatus == .ready, !day.sessions.isEmpty {
                SedentaryTimelineChartView(summary: day)
            }
        }
        .padding(16)
    }

    private func historyFocusRow(day: SedentaryDaySummary, session: SedentaryTimelineSegment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: session.kind.symbol)
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundColor(SedentaryVisualPalette.text(for: session.kind))
                .frame(width: 24, height: 24)
                .background(SedentaryVisualPalette.fill(for: session.kind), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(historyFocusText(for: day, session: session))
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(session.timeRangeText)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .bbTintedSurface(tint: SedentaryVisualPalette.stroke(for: session.kind), in: RoundedRectangle(cornerRadius: 18, style: .continuous), tintStrength: 0.08, shadow: false)
    }

    private func toggleExpanded(_ day: SedentaryDaySummary) {
        if expandedDayIDs.contains(day.id) {
            expandedDayIDs.remove(day.id)
        } else {
            expandedDayIDs.insert(day.id)
        }
    }

    private func historyStatusText(for day: SedentaryDaySummary) -> String {
        switch day.sourceStatus {
        case .ready:
            if day.totalSedentaryMinutes == 0 {
                return String(localized: "当日没有明显久坐段")
            }
            return String(localized: "久坐 \(day.totalSedentaryMinutes.bbFormattedDurationCompact) · 打断 \(day.activeBreakCount) 次")
        case .needsAuthorization:
            return String(localized: "当天缺少健康权限")
        case .noData:
            return "当天没有足够活动样本"
        case .unavailable:
            return String(localized: "当天日志暂时不可用")
        }
    }

    private func historyFocusText(for day: SedentaryDaySummary, session: SedentaryTimelineSegment) -> String {
        if session.isOngoing {
            return String(localized: "当天最后一段持续到了记录结束")
        }
        if session == day.sessions.max(by: { $0.durationMinutes < $1.durationMinutes }) {
            return String(localized: "这一天最长的久坐段")
        }
        return String(localized: "这一天最近一次明显久坐段")
    }

    private func historyHeroPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .bbTintedChip(tint: tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func historyMetricPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .bbTintedChip(tint: tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func historyEmptyState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(detail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

}

private extension View {
    func sedentaryFlatCard(cornerRadius: CGFloat = 24) -> some View {
        background(Theme.Colors.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.86), lineWidth: 1)
            )
            .shadow(color: Color(hex: "84A7D9").opacity(0.08), radius: 12, x: 0, y: 7)
    }

}

private struct SedentaryHistoryDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    let minimumDate: Date
    @State private var draftDate = Calendar.current.startOfDay(for: Date())

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("选择往日日志日期")
                        .font(.appSystem(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("选择某一天后，页面会定位到对应日期的久坐记录；未来日期不可选择。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DatePicker(
                    "往日日志日期",
                    selection: $draftDate,
                    in: minimumDate...Calendar.current.startOfDay(for: Date()),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()

                Button {
                    selectedDate = Calendar.current.startOfDay(for: draftDate)
                    dismiss()
                } label: {
                    Text("确定")
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .bbTintedPrimaryButton(tint: Color(hex: "7AA7D9"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                draftDate = Calendar.current.startOfDay(for: selectedDate)
            }
        }
    }
}
