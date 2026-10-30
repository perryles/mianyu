/// WalkingAsymmetryDetailView 由 HealthHubView 调用，作为「步态不对称」详情页。
/// 负责展示步态平衡节律摘要、信号解读、影响来源与周趋势，样式参考 ActiveEnergyDetailView / BodyAgeView。

import SwiftUI

/// 步态不对称详情视图 由 `HealthHubView` 调用，作为健康页里"步态不对称"入口对应的专属详情页面。
/// 负责展示步态平衡摘要、今日解读、影响来源和不对称趋势，样式参考 BodyAgeView / ActiveEnergyDetailView。
struct WalkingAsymmetryDetailView: View {
    let metric: DashboardOtherMetricCardModel
    var showsDismissButton: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var interpretation = WalkingAsymmetryInterpretationViewModel()
    @State private var interpretationTab: InterpretationTab = .signals
    @State private var showingReminderSettings = false
    private var subscriptionManager = SubscriptionManager.shared

    init(
        metric: DashboardOtherMetricCardModel,
        initialDate: Date = Date(),
        showsDismissButton: Bool = false
    ) {
        self.metric = metric
        self.showsDismissButton = showsDismissButton
    }

    enum InterpretationTab: String, CaseIterable {
        case signals
        case fluctuation
        case abnormal

        var title: String {
            switch self {
            case .signals: return "信号解读"
            case .fluctuation: return "波动"
            case .abnormal: return "异常日"
            }
        }

        var symbol: String {
            switch self {
            case .signals: return "waveform.path.ecg"
            case .fluctuation: return "chart.line.flattrend.xyaxis"
            case .abnormal: return "exclamationmark.triangle"
            }
        }
    }

    private let accentCyan = Color(hex: "2E9BC6")
    private let accentCyanGlow = Color(hex: "9FDCFF")
    private let accentSlate = Color(hex: "5F6F86")

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    walkingAsymmetrySpotlight
                    walkingAsymmetryInterpretationSection
                    walkingAsymmetryFactorsSection
                    walkingAsymmetryTrendSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HealthDetailDesignSystem.pageHorizontalPadding)
                    .padding(.top, HealthDetailDesignSystem.pageTopPadding)
                    .padding(.bottom, 120)
            }
        }
        .healthDetailNavigation(title: HealthPageName.walkingAsymmetry)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    HealthNavigationDismissButton {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("设置") { showingReminderSettings = true }
                }
            }
        }
        .sheet(isPresented: $showingReminderSettings) {
            NavigationStack {
                MetricReminderSettingsView(metricKey: "walking_asymmetry", metricTitle: metric.title)
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .task {
            await interpretation.load()
        }
    }

    // MARK: - 核心指标

    private var walkingAsymmetrySpotlight: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("近 7 天评估")
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "1E3340"))
                    Text("每天随健康数据更新")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "5F7784"))
                }

                Spacer(minLength: 8)

                Label(interpretation.dataCoverageText, systemImage: "checkmark.seal.fill")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "1A739B"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .bbTintedChip(tint: accentCyan, in: Capsule(), tintOpacity: 0.10)
            }

            WalkingAsymmetryVitalOrb(
                valueText: metric.valueText == "暂无" ? "--" : metric.valueText,
                unitText: metric.unitText.isEmpty ? "%" : metric.unitText,
                comparisonText: comparisonText,
                statusText: interpretation.dailySummary?.riskTitle ?? interpretation.state.title,
                isWaiting: metric.statusTone == .muted
            )
            .frame(maxWidth: .infinity)

            WalkingAsymmetryBalanceScale(balance: interpretation.balanceScore)

            walkingAsymmetryGuidanceCard
        }
        .padding(20)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.top, 4)
    }

    private var comparisonText: String {
        if metric.statusTone == .muted {
            return String(localized: "补齐样本后再看步态平衡区间")
        }
        if let recent = interpretation.recentAverage, let baseline = interpretation.baselineAverage, recent > 0, baseline > 0 {
            let delta = recent - baseline
            if abs(delta) < 1 {
                return String(localized: "与近一个月均值基本一致")
            }
            if delta < 0 {
                return String(localized: "比近一个月更均衡 \(String(format: "%.1f", abs(delta)))%")
            }
            return String(localized: "比近一个月更不对称 \(String(format: "%.1f", delta))%")
        }
        return String(localized: "等待趋势数据")
    }

    private var walkingAsymmetryGuidanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: guidanceSymbol)
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundColor(accentCyan)
                    .frame(width: 30, height: 30)
                    .bbTintedChip(tint: accentCyan, in: Circle(), tintOpacity: 0.12)

                Text(guidanceHeadline)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "1E3A47"))

                Spacer(minLength: 0)

                Text(interpretation.dailySummary?.riskTitle ?? interpretation.state.title)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "1A739B"))
            }

            Text(guidanceDetail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "4A606D"))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .bbTintedSurface(
            tint: accentCyan,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            tintStrength: 0.055,
            shadow: false
        )
    }

    private var guidanceHeadline: String {
        guard let summary = interpretation.dailySummary else {
            return String(localized: "继续累积健康数据")
        }
        switch summary.riskLevel {
        case .stable: return String(localized: "步态节律稳定")
        case .mild: return String(localized: "轻微波动在正常范围")
        case .caution: return String(localized: "优先看连续几天的走向")
        case .high: return String(localized: "先降低步态负荷再观察")
        }
    }

    private var guidanceSymbol: String {
        guard let summary = interpretation.dailySummary else { return "figure.walk.motion" }
        switch summary.riskLevel {
        case .stable: return "checkmark.circle.fill"
        case .mild: return "arrow.down.heart.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .high: return "bolt.slash.fill"
        }
    }

    private var guidanceDetail: String {
        guard let summary = interpretation.dailySummary else {
            return String(localized: "继续佩戴 Apple Watch 并保持健康同步，样本更完整后会生成更稳定的步态平衡判断。")
        }
        switch summary.riskLevel {
        case .stable:
            return String(localized: "当前步态不对称处在连贯的低位区间。继续保持日常走路节律，适合按周观察方向，不必放大单日读数。")
        case .mild:
            return String(localized: "当前步态不对称有轻微抬升。优先观察是否与疲劳、负重或走路姿势有关，看接下来一周是否回到常态。")
        case .caution:
            return String(localized: "近期步态不对称连续偏高。适合先降低大负荷训练与长时间负重行走，把节奏放匀后再回看趋势。")
        case .high:
            return String(localized: "多条步态信号都在同方向偏移。适合先给身体留恢复窗口、减少不对称负重，再回看平衡度是否回稳。")
        }
    }

    // MARK: - 解读区

    private var walkingAsymmetryInterpretationSection: some View {
        healthSection(
            title: "今日解读",
            subtitle: ""
        ) {
            VStack(alignment: .leading, spacing: 12) {
                walkingAsymmetryDailyStatusCard

                if interpretation.state == .ready {
                    walkingAsymmetryDeepInterpretationCard
                }

                Text("仅供日常自我管理参考，不构成医疗诊断或治疗建议。若持续出现明显步态异常或身体不适，请及时就医。")
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }

    @ViewBuilder
    private var walkingAsymmetryDeepInterpretationCard: some View {
        let availableTabs = InterpretationTab.allCases.filter { tab in
            switch tab {
            case .signals:
                return interpretation.signalLanguageCard != nil || interpretation.manualProfile != nil
            case .fluctuation:
                return !interpretation.interpretationCards.isEmpty
            case .abnormal:
                return !interpretation.abnormalDays.isEmpty
            }
        }

        if !availableTabs.isEmpty {
            let activeTab = availableTabs.contains(interpretationTab) ? interpretationTab : (availableTabs.first ?? .signals)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(availableTabs, id: \.self) { tab in
                        interpretationTabButton(tab, isActive: tab == activeTab)
                    }
                }

                Group {
                    switch activeTab {
                    case .signals:
                        walkingAsymmetrySignalsTabContent
                    case .fluctuation:
                        walkingAsymmetryFluctuationTabContent
                    case .abnormal:
                        walkingAsymmetryAbnormalTabContent
                    }
                }

            }
            .padding(16)
            .bbTintedSurface(
                tint: Theme.Colors.onAccent,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                tintStrength: 0.07
            )
        }
    }

    private func interpretationTabButton(_ tab: InterpretationTab, isActive: Bool) -> some View {
        Button {
            interpretationTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.appSystem(size: 12, weight: .bold))
                Text(tab.title)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
            }
            .foregroundColor(isActive ? Color(hex: "15325D") : Color(hex: "70819A"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isActive
                    ? Color.white.opacity(0.8)
                    : Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? Color(hex: "15325D").opacity(0.12) : Color.clear, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isActive ? "已选中" : "")
    }

    @ViewBuilder
    private var walkingAsymmetrySignalsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = interpretation.signalLanguageCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(item.summary)
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        interpretationBadge(text: item.badge, tint: item.tint)
                    }
                    Text(item.detail)
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .background(Theme.Colors.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            if let profile = interpretation.manualProfile {
                Button {
                    showingReminderSettings = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "book.closed.fill")
                            .font(.appSystem(size: 13, weight: .bold))
                            .foregroundColor(profile.tint)
                            .frame(width: 32, height: 32)
                            .bbTintedChip(tint: profile.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous), tintOpacity: 0.10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("步态平衡说明书")
                                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(profile.title)
                                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.appSystem(size: 11, weight: .bold))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .padding(12)
                    .background(Theme.Colors.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看完整步态平衡说明书")
            }
        }
    }

    @ViewBuilder
    private var walkingAsymmetryFluctuationTabContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(interpretation.interpretationCards.prefix(3))) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.title)
                            .font(.appSystem(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer(minLength: 0)
                        interpretationBadge(text: item.badge, tint: item.tint)
                    }
                    Text(item.summary)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.detail)
                        .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Theme.Colors.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var walkingAsymmetryAbnormalTabContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(interpretation.abnormalDays.prefix(2))) { day in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(day.dateText)
                            .font(.appSystem(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer(minLength: 0)
                        interpretationBadge(text: day.levelText, tint: day.tint)
                    }
                    Text(day.reason)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(day.actionSuggestion)
                        .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(day.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Theme.Colors.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var walkingAsymmetryDailyStatusCard: some View {
        let summary = interpretation.dailySummary
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    interpretationBadge(
                        text: summary?.riskTitle ?? interpretation.state.title,
                        tint: summary?.accentColor ?? accentSlate
                    )

                    Text(summary?.headline ?? interpretation.state.headline)
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(summary?.narrative ?? interpretation.state.detail)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    Text(summary?.scoreText ?? "--")
                        .font(.appSystem(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("平衡分")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .frame(width: 86, height: 92)
                .bbTintedSurface(
                    tint: summary?.accentColor ?? accentCyan,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                    tintStrength: 0.09,
                    shadow: false
                )
            }

            if let summary {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Array(summary.signalPills.prefix(4))) { pill in
                        signalPill(pill)
                    }
                }

                Text(summary.explanation)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .bbTintedSurface(
            tint: Theme.Colors.onAccent,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            tintStrength: 0.07
        )
    }

    private func signalPill(_ pill: WalkingAsymmetryDailySummary.SignalPill) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(pill.title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(pill.value)
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(pill.note)
                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(pill.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func interpretationBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: - 影响因素区

    private var walkingAsymmetryFactorsSection: some View {
        healthSection(
            title: "影响来源",
            subtitle: ""
        ) {
            WalkingAsymmetryImpactSourcesCard()
        }
    }

    // MARK: - 趋势区

    private var walkingAsymmetryTrendSection: some View {
        HealthLockedModuleContainer(isUnlocked: subscriptionManager.isPro) {
            trendSection
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            LockedTrendCard(
                title: "步态不对称周趋势",
                points: interpretation.trendPoints,
                unit: "%",
                tint: accentCyan,
                usesTintedSurface: true,
                tintedSurfaceTint: .white
            )
            LockedTrendCard(
                title: "步态平稳度趋势",
                points: interpretation.steadinessTrendPoints,
                unit: "%",
                tint: Color(hex: "5B8CFF"),
                usesTintedSurface: true,
                tintedSurfaceTint: .white
            )
        }
    }

    // MARK: - 共享组件

    private func healthSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !title.isEmpty || !subtitle.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !title.isEmpty {
                        Text(title)
                            .font(.appSystem(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            content()
        }
    }
}

// MARK: - Vital Orb

private struct WalkingAsymmetryVitalOrb: View {
    let valueText: String
    let unitText: String
    let comparisonText: String
    let statusText: String
    let isWaiting: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.secondarySurface, lineWidth: 24)
                .padding(16)
            Circle()
                .stroke(
                    AngularGradient(colors: [Color(hex: "BFE3F2"), Theme.Colors.pastelCyan, Color(hex: "D6EEF8"), Color(hex: "BFE3F2")], center: .center),
                    lineWidth: 24
                )
                .padding(16)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(valueText)
                        .font(.appSystem(size: 52, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "12303D"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if !unitText.isEmpty {
                        Text(unitText)
                            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "43637A"))
                    }
                }

                Text("步态不对称")
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .tracking(2.2)
                    .foregroundColor(Color(hex: "4A6B7D"))

                Text(comparisonText)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "1A739B"))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .padding(.horizontal, 28)
            }
            .opacity(isWaiting ? 0.72 : 1)
        }
        .frame(width: 264, height: 264)
        .overlay(alignment: .bottom) {
            Text(statusText)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "14667F"))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
                .overlay(Capsule().stroke(Color(hex: "C4E5F2"), lineWidth: 1))
                .offset(y: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("步态不对称 \(valueText) \(unitText)，\(comparisonText)，\(statusText)")
    }
}

// MARK: - Balance Scale

private struct WalkingAsymmetryBalanceScale: View {
    /// balanceScore 越高代表左右越对称（0-100）。
    let balance: Double?

    private var normalizedScore: CGFloat {
        let value = min(max(CGFloat(balance ?? 90), 60), 100)
        return (value - 60) / 40
    }

    private var valueText: String {
        guard let balance else { return "--" }
        return String(format: "%.0f", balance)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("步态平衡度")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "1E3340"))
                Spacer(minLength: 0)
                Text(valueText)
                    .font(.appSystem(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "1E3A47"))
            }

            HStack {
                Label("偏斜", systemImage: "figure.walk.motion")
                Spacer(minLength: 0)
                Label("对称", systemImage: "checkmark.seal.fill")
            }
            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: "5F7784"))

            GeometryReader { proxy in
                let markerX = max(5, min(proxy.size.width - 5, proxy.size.width * normalizedScore))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(hex: "D8E8EF"))
                        .frame(height: 4)
                        .position(x: proxy.size.width / 2, y: 20)

                    ForEach(0..<41, id: \.self) { index in
                        Capsule()
                            .fill(index == 20 ? Color(hex: "5FAECB") : Color(hex: "B5CCD6"))
                            .frame(width: index % 10 == 0 ? 2 : 1, height: index % 10 == 0 ? 24 : 14)
                            .position(x: proxy.size.width * CGFloat(index) / 40, y: 20)
                    }

                    Capsule()
                        .fill(Color(hex: "1A739B"))
                        .frame(width: 4, height: 38)
                        .position(x: markerX, y: 20)
                        .shadow(color: Color(hex: "1A739B").opacity(0.24), radius: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(hex: "1A739B"), lineWidth: 3))
                        .position(x: markerX, y: 3)
                }
                .opacity(balance == nil ? 0.55 : 1)
            }
            .frame(height: 40)

            HStack {
                Text("低")
                Spacer(minLength: 0)
                Text("90 基准")
                Spacer(minLength: 0)
                Text("高")
            }
            .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(Color(hex: "77909C"))
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("步态平衡度 \(valueText)，范围 60 到 100，越高左右越对称")
    }
}

// MARK: - Factors Card

private struct WalkingAsymmetryImpactSourcesCard: View {
    @MainActor
    @Observable
    final class ViewModel {
        var seriesByKey: [HealthFactorKey: [TimeSeriesPointDouble]] = [:]

        func load() {
            Task {
                var next: [HealthFactorKey: [TimeSeriesPointDouble]] = [:]
                for key in HealthFactorKey.allCases {
                    next[key] = await key.loadSeries(days: 60)
                }
                seriesByKey = next
            }
        }
    }

    fileprivate struct FactorItem: Identifiable {
        let key: HealthFactorKey

        var id: String { key.id }
        var title: String { key.title }
        var icon: String { key.icon }
        var iconColor: Color { key.iconColor }
    }

    fileprivate struct ImpactDescriptor {
        let value: Double?
        let color: Color
        let symbol: String

        var formattedText: String {
            guard let value else { return "--" }
            return String(format: String(localized: "%+.1f%%"), value)
        }
    }

    fileprivate struct ImpactDetailSnapshot: Identifiable {
        let factor: FactorItem
        let descriptor: ImpactDescriptor
        let recentAverage: Double?
        let baselineAverage: Double?
        let explanation: String

        var id: String { factor.id }
    }

    @State private var viewModel = ViewModel()
    @State private var selectedDetail: ImpactDetailSnapshot?

    /// 步态不对称与全身活动底盘、疲劳恢复和下肢力量的关系更直接，因此只展示相关因素。
    private let items: [FactorItem] = [
        .init(key: .steps),
        .init(key: .sleepDuration),
        .init(key: .aerobicTraining),
        .init(key: .strengthTraining),
        .init(key: .restingHeartRate),
        .init(key: .vo2Max)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    selectedDetail = buildDetailSnapshot(for: item)
                } label: {
                    factorRow(item)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)

                if index < items.count - 1 {
                    Divider()
                        .overlay(Theme.Colors.surfaceBorder)
                }
            }
        }
        .padding(.horizontal, 18)
        .background(Color.clear)
        .bbTintedSurface(
            tint: Theme.Colors.onAccent,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            tintStrength: 0.07
        )
        .onAppear {
            viewModel.load()
        }
        .sheet(item: $selectedDetail) { detail in
            WalkingAsymmetryImpactDetailSheet(detail: detail)
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
    }

    private func factorRow(_ item: FactorItem) -> some View {
        let latestValue = viewModel.seriesByKey[item.key]?.last(where: { $0.value > 0 })?.value
        let descriptor = impactDescriptor(for: item.key, latestValue: latestValue)

        return HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundColor(item.iconColor)
                    .frame(width: 34, height: 34)
                    .bbTintedSurface(
                        tint: item.iconColor,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                        tintStrength: 0.10,
                        shadow: false
                    )

                Text(item.title)
                    .font(.appSystem(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Text(descriptor.formattedText)
                    .font(.appSystem(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(descriptor.color)
                    .monospacedDigit()

                Image(systemName: descriptor.symbol)
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundColor(descriptor.color)

                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .bold))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.leading, 2)
            }
        }
    }

    private func impactDescriptor(for key: HealthFactorKey, latestValue: Double?) -> ImpactDescriptor {
        guard let latestValue, latestValue > 0 else {
            return ImpactDescriptor(value: nil, color: Color(hex: "9BA8B8"), symbol: "minus")
        }

        let impact: Double
        switch key {
        case .steps:
            if latestValue >= 8000 {
                impact = -0.8
            } else if latestValue >= 5000 {
                impact = -0.2
            } else {
                impact = 0.6
            }
        case .sleepDuration:
            let hours = latestValue / 60.0
            if hours >= 7.5 {
                impact = -0.6
            } else if hours >= 6.5 {
                impact = -0.2
            } else {
                impact = 0.7
            }
        case .aerobicTraining:
            if latestValue >= 45 {
                impact = -0.5
            } else if latestValue >= 20 {
                impact = -0.1
            } else {
                impact = 0.3
            }
        case .strengthTraining:
            if latestValue >= 30 {
                impact = -0.6
            } else if latestValue >= 10 {
                impact = -0.2
            } else {
                impact = 0.5
            }
        case .restingHeartRate:
            if latestValue <= 62 {
                impact = -0.4
            } else if latestValue <= 72 {
                impact = -0.1
            } else {
                impact = 0.6
            }
        case .vo2Max:
            if latestValue >= 38 {
                impact = -0.6
            } else if latestValue >= 32 {
                impact = -0.2
            } else {
                impact = 0.5
            }
        case .sleepConsistency:
            if latestValue >= 80 {
                impact = -0.4
            } else if latestValue >= 70 {
                impact = -0.1
            } else {
                impact = 0.5
            }
        case .bodyFat:
            impact = 0
        }

        if impact < 0 {
            return ImpactDescriptor(value: impact, color: Theme.Colors.mintGreen, symbol: "chevron.down")
        }
        if impact > 0 {
            return ImpactDescriptor(value: impact, color: Color(hex: "E29A63"), symbol: "chevron.up")
        }
        return ImpactDescriptor(value: impact, color: Color(hex: "9BA8B8"), symbol: "minus")
    }

    private func buildDetailSnapshot(for item: FactorItem) -> ImpactDetailSnapshot {
        let series = viewModel.seriesByKey[item.key] ?? []
        let validValues = series.map(\.value).filter { $0 > 0 }
        let recentWindow = Array(validValues.suffix(14))
        let baselineWindow = Array(validValues.suffix(60))

        let recentAverage = average(of: recentWindow)
        let baselineAverage = average(of: baselineWindow)
        let descriptor = impactDescriptor(for: item.key, latestValue: validValues.last)

        return ImpactDetailSnapshot(
            factor: item,
            descriptor: descriptor,
            recentAverage: recentAverage,
            baselineAverage: baselineAverage,
            explanation: explanation(for: item.key, descriptor: descriptor, recentAverage: recentAverage, baselineAverage: baselineAverage)
        )
    }

    private func average(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func explanation(
        for key: HealthFactorKey,
        descriptor: ImpactDescriptor,
        recentAverage: Double?,
        baselineAverage: Double?
    ) -> String {
        let recentText = recentAverage.map { key.displayValue($0) } ?? "暂无记录"
        let baselineText = baselineAverage.map { key.displayValue($0) } ?? "暂无记录"

        switch key {
        case .steps:
            return String(localized: "近 14 天步数约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))日常活动底盘稳定时，左右步伐通常更容易保持均衡。")
        case .sleepDuration:
            return String(localized: "近 14 天睡眠约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))睡眠不足会放大疲劳侧倾，步态不对称通常更难回落。")
        case .aerobicTraining:
            return String(localized: "近 14 天有氧训练约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))有氧负荷连续堆高时，疲劳侧更容易先露出不对称。")
        case .strengthTraining:
            return String(localized: "近 14 天力量训练约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))双侧力量更均衡时，走路的不对称通常更小。")
        case .restingHeartRate:
            return String(localized: "近 14 天静息心率约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))静息状态更平稳时，疲劳对步态的干扰通常更小。")
        case .vo2Max:
            return String(localized: "近 14 天最大摄氧量约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))心肺储备更好时，同等步速下身体更不容易出现代偿。")
        case .sleepConsistency:
            return String(localized: "近 14 天作息一致性约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))先把入睡和起床时间拉回稳定区间。")
        case .bodyFat:
            return String(localized: "近 14 天体脂率约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))身体组成更适合看长期方向，不用放大单次波动。")
        }
    }

    private func descriptorNarrative(_ descriptor: ImpactDescriptor) -> String {
        guard let value = descriptor.value else { return String(localized: "目前影响还不明显。") }
        if value < 0 {
            return String(localized: "它现在大约让步态不对称低 \(String(format: "%.1f", abs(value)))%。")
        }
        if value > 0 {
            return String(localized: "它现在大约让步态不对称高 \(String(format: "%.1f", value))%。")
        }
        return String(localized: "它现在基本是中性影响。")
    }
}

private struct WalkingAsymmetryImpactDetailSheet: View {
    let detail: WalkingAsymmetryImpactSourcesCard.ImpactDetailSnapshot

    @Environment(\.dismiss) private var dismiss

    private var detailTint: Color { detail.factor.iconColor }
    private var impactPillTint: Color { detail.descriptor.color }
    private var baselineValue: Double? { detail.baselineAverage }
    private var recentValue: Double? { detail.recentAverage }
    private var comparisonScaleMax: Double {
        let values = [baselineValue, recentValue].compactMap { $0 }.filter { $0 > 0 }
        return max(values.max() ?? 1, minimumScaleMax(for: detail.factor.key))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader
                    comparisonCard
                    explanationCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .background(Theme.Colors.pageBackground.ignoresSafeArea())
            .navigationTitle("影响因素")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.appSystem(size: 16, weight: .semibold))
                            .foregroundColor(detail.factor.iconColor.opacity(0.85))
                    }
                }
            }
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.clear)
                    .frame(width: 52, height: 52)
                    .bbTintedSurface(tint: detailTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous), tintStrength: 0.14, shadow: false)
                    .overlay {
                        Image(systemName: detail.factor.icon)
                            .font(.appSystem(size: 22, weight: .bold))
                            .foregroundColor(detailTint)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.factor.title)
                        .font(.appSystem(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("对步态不对称的当前影响")
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(detail.descriptor.formattedText)
                    .font(.appSystem(size: 46, weight: .bold, design: .rounded))
                    .foregroundColor(impactPillTint)
                    .monospacedDigit()
            }
        }
        .padding(22)
        .background(Color.clear)
        .bbTintedSurface(
            tint: Theme.Colors.onAccent,
            in: RoundedRectangle(cornerRadius: 30, style: .continuous),
            tintStrength: 0.08
        )
    }

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 28) {
                comparisonMetric(
                    title: "近60天",
                    value: formattedAverage(detail.baselineAverage, for: detail.factor.key),
                    accent: Color(hex: "F2A97A"),
                    caption: "长期基线"
                )
                comparisonMetric(
                    title: "近14天",
                    value: formattedAverage(detail.recentAverage, for: detail.factor.key),
                    accent: Theme.Colors.mintGreen,
                    caption: "近期状态"
                )
            }

            comparisonInsightPill

            walkingAsymmetryImpactBalanceBar(
                leftAccent: Color(hex: "F2A97A"),
                rightAccent: Theme.Colors.mintGreen
            )
        }
        .padding(20)
        .background(Color.clear)
        .bbTintedSurface(
            tint: Theme.Colors.onAccent,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous),
            tintStrength: 0.06,
            shadow: false
        )
    }

    private func comparisonMetric(title: String, value: String, accent: Color, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)

            Text(value)
                .font(.appSystem(size: 28, weight: .medium, design: .rounded))
                .foregroundColor(accent)
                .monospacedDigit()

            Text(caption)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(accent.opacity(0.88))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .bbTintedChip(tint: accent, in: Capsule(), tintOpacity: 0.12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var comparisonInsightPill: some View {
        Text(comparisonDeltaText)
            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(comparisonDeltaTint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .bbTintedChip(tint: comparisonDeltaTint, in: Capsule(), tintOpacity: 0.12)
    }

    private func walkingAsymmetryImpactBalanceBar(leftAccent: Color, rightAccent: Color) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let baselinePosition = fillWidth(for: baselineValue, totalWidth: width)
            let recentPosition = fillWidth(for: recentValue, totalWidth: width)
            let contentWidth = max(baselinePosition, recentPosition, 12)

            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Theme.Colors.secondaryBackground)
                        .frame(width: width, height: 18)

                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [leftAccent.opacity(0.94), rightAccent.opacity(0.94)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: contentWidth, height: 18)

                    comparisonBubble(
                        value: formattedAverage(detail.baselineAverage, for: detail.factor.key),
                        tint: leftAccent,
                        anchor: .bottom
                    )
                    .offset(x: bubbleOffset(for: baselinePosition, totalWidth: width, bubbleWidth: 72), y: 28)

                    comparisonBubble(
                        value: formattedAverage(detail.recentAverage, for: detail.factor.key),
                        tint: rightAccent,
                        anchor: .top
                    )
                    .offset(x: bubbleOffset(for: recentPosition, totalWidth: width, bubbleWidth: 72), y: -28)
                }
                .frame(height: 74)

                HStack {
                    Text("0")
                    Spacer()
                    Text(formattedScaleMax)
                }
                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .frame(height: 78)
    }

    private func formattedAverage(_ value: Double?, for key: HealthFactorKey) -> String {
        guard let value else { return "0" }
        return key.displayValue(value)
    }

    private func comparisonBubble(
        value: String,
        tint: Color,
        anchor: Edge
    ) -> some View {
        VStack(spacing: 0) {
            if anchor == .bottom {
                triangle(tint: tint)
            }

            Text(value)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(tint, in: Capsule())

            if anchor == .top {
                triangle(tint: tint)
            }
        }
        .frame(width: 72)
    }

    private func triangle(tint: Color) -> some View {
        Triangle()
            .fill(tint)
            .frame(width: 12, height: 8)
    }

    private func bubbleOffset(for position: CGFloat, totalWidth: CGFloat, bubbleWidth: CGFloat) -> CGFloat {
        let centered = position - bubbleWidth / 2
        return min(max(centered, 0), max(totalWidth - bubbleWidth, 0))
    }

    private func fillWidth(for value: Double?, totalWidth: CGFloat) -> CGFloat {
        guard let value, value > 0 else { return 0 }
        let progress = min(max(value / comparisonScaleMax, 0), 1)
        return totalWidth * CGFloat(progress)
    }

    private func minimumScaleMax(for key: HealthFactorKey) -> Double {
        switch key {
        case .sleepDuration:
            return 480
        case .sleepConsistency:
            return 100
        case .aerobicTraining, .strengthTraining:
            return 60
        case .steps:
            return 10000
        case .vo2Max:
            return 40
        case .restingHeartRate:
            return 90
        case .bodyFat:
            return 0.35
        }
    }

    private var formattedScaleMax: String {
        scaleLabel(for: comparisonScaleMax)
    }

    private func scaleLabel(for value: Double) -> String {
        switch detail.factor.key {
        case .sleepDuration:
            return String(format: "%.1fh", value / 60.0)
        case .sleepConsistency:
            return "\(Int(value.rounded()))%"
        case .aerobicTraining, .strengthTraining:
            return String(localized: "\(Int(value.rounded()))分")
        case .steps:
            if value >= 10000 {
                return String(format: String(localized: "%.1f万步"), value / 10000.0)
            }
            return String(localized: "\(Int(value.rounded()))步")
        case .vo2Max:
            return String(format: "%.1f", value)
        case .restingHeartRate:
            return String(localized: "\(Int(value.rounded()))次/分")
        case .bodyFat:
            return String(format: "%.1f%%", value * 100.0)
        }
    }

    private var comparisonDeltaText: String {
        guard let baseline = baselineValue, let recent = recentValue else {
            return String(localized: "样本不足，先继续记录")
        }
        let delta = recent - baseline
        let threshold = minimumScaleMax(for: detail.factor.key) * 0.06
        if abs(delta) < threshold {
            return String(localized: "近期和长期基线接近")
        }
        let deltaText = scaleLabel(for: abs(delta))
        return delta > 0 ? "近期高于基线 \(deltaText)" : "近期低于基线 \(deltaText)"
    }

    private var comparisonDeltaTint: Color {
        guard let baseline = baselineValue, let recent = recentValue else {
            return Color(hex: "9BA5B4")
        }
        let delta = recent - baseline
        let threshold = minimumScaleMax(for: detail.factor.key) * 0.06
        if abs(delta) < threshold {
            return Color(hex: "8D99A8")
        }
        return delta > 0 ? Color(hex: "E29A63") : Theme.Colors.mintGreen
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(.clear)
                    .frame(width: 34, height: 34)
                    .bbTintedSurface(
                        tint: detailTint,
                        in: Circle(),
                        tintStrength: 0.10,
                        shadow: false
                    )
                    .overlay {
                        Image(systemName: "text.book.closed.fill")
                            .font(.appSystem(size: 14, weight: .bold))
                            .foregroundColor(detailTint)
                    }

                Text("结果解读")
                    .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            Text(detail.explanation)
                .font(.appSystem(size: 18, weight: .regular, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(Color.clear)
        .bbTintedSurface(
            tint: Theme.Colors.onAccent,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous),
            tintStrength: 0.06,
            shadow: false
        )
    }
}

nonisolated private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Interpretation Models

struct WalkingAsymmetryInterpretationCard: Identifiable {
    let id: String
    let title: String
    let badge: String
    let summary: String
    let detail: String
    let tint: Color
}

struct WalkingAsymmetryDailySummary {
    enum RiskLevel: String {
        case stable = "稳定"
        case mild = "轻波动"
        case caution = "需留意"
        case high = "高扰动"

        /// 本地化标题：rawValue 仅作标识，UI 展示走 String Catalog。
        var displayName: String {
            switch self {
            case .stable: return String(localized: "稳定")
            case .mild: return String(localized: "轻波动")
            case .caution: return String(localized: "需留意")
            case .high: return String(localized: "高扰动")
            }
        }
    }

    struct SignalPill: Identifiable {
        let id: String
        let title: String
        let value: String
        let note: String
        let tint: Color
    }

    let riskLevel: RiskLevel
    let score: Int
    let headline: String
    let narrative: String
    let explanation: String
    let signalPills: [SignalPill]
    let accentColor: Color

    var riskTitle: String { riskLevel.displayName }
    var scoreText: String { "\(score)" }
}

struct WalkingAsymmetryAbnormalDay: Identifiable {
    let id: String
    let date: Date
    let dateText: String
    let reason: String
    let actionSuggestion: String
    let levelText: String
    let tint: Color
}

struct WalkingAsymmetryManualProfile {
    let title: String
    let badge: String
    let tint: Color
}

@MainActor
/// 步态不对称解读视图模型 由 `WalkingAsymmetryDetailView` 持有。
/// 负责读取近 30 天步态不对称与平稳度样本，生成平衡分、风险分级、信号解读和异常日列表。
@Observable
final class WalkingAsymmetryInterpretationViewModel {
    enum LoadState: Equatable {
        case loading
        case ready
        case empty

        var title: String {
            switch self {
            case .loading: return "正在整理"
            case .ready: return "已生成"
            case .empty: return "等待样本"
            }
        }

        var headline: String {
            switch self {
            case .loading: return "正在整理最近的步态平衡说明"
            case .ready: return "步态平衡说明已经整理完成"
            case .empty: return "最近样本还不够形成稳妥判断"
            }
        }

        var detail: String {
            switch self {
            case .loading: return "先把健康 App 里可读到的步态样本整理出来。"
            case .ready: return "最近的步态平衡已经开始能拼出一张更完整的说明图。"
            case .empty: return "继续佩戴 Apple Watch 记录几天后，再回来会更完整。"
            }
        }
    }

    private(set) var state: LoadState = .loading
    private(set) var dailySummary: WalkingAsymmetryDailySummary?
    private(set) var abnormalDays: [WalkingAsymmetryAbnormalDay] = []
    private(set) var manualProfile: WalkingAsymmetryManualProfile?
    private(set) var signalLanguageCard: WalkingAsymmetryInterpretationCard?
    private(set) var interpretationCards: [WalkingAsymmetryInterpretationCard] = []
    private(set) var trendPoints: [HealthAgeTrendPoint] = []
    private(set) var steadinessTrendPoints: [HealthAgeTrendPoint] = []
    private(set) var recentAverage: Double?
    private(set) var baselineAverage: Double?
    private(set) var balanceScore: Double?
    private(set) var dataCoverageText: String = String(localized: "正在读取健康 App")

    func load() async {
        state = .loading
        let hk = HealthKitManager.shared

        async let asymmetry30Task = try? hk.fetchDailyWalkingAsymmetryAverages(days: 30)
        async let steadiness30Task = try? hk.fetchDailyWalkingSteadinessAverages(days: 30)

        let asymmetry30 = await asymmetry30Task ?? []
        let steadiness30 = await steadiness30Task ?? []
        let validAsymmetry = asymmetry30.filter { $0.value > 0 }.sorted { $0.date < $1.date }
        let validSteadiness = steadiness30.filter { $0.value > 0 }.sorted { $0.date < $1.date }

        trendPoints = validAsymmetry.map { HealthAgeTrendPoint(date: $0.date, value: $0.value) }
        steadinessTrendPoints = validSteadiness.map { HealthAgeTrendPoint(date: $0.date, value: $0.value) }

        let populatedDays = Set(validAsymmetry.map { Calendar.current.startOfDay(for: $0.date) }).count
        dataCoverageText = populatedDays == 0
            ? String(localized: "健康 App 暂无数据")
            : String(localized: "近 30 天 \(populatedDays) 天有记录")

        guard !validAsymmetry.isEmpty else {
            state = .empty
            return
        }

        recentAverage = average(of: validAsymmetry.suffix(7).map(\.value))
        baselineAverage = average(of: validAsymmetry.dropLast(7).suffix(23).map(\.value))
        let latest = validAsymmetry.last?.value ?? recentAverage
        balanceScore = latest.map { max(60, min(100, 100 - $0 * 2.2)) }

        analyze(asymmetry: validAsymmetry, steadiness: validSteadiness)
        state = .ready
    }

    private func analyze(asymmetry: [TimeSeriesPointDouble], steadiness: [TimeSeriesPointDouble]) {
        let calendar = Calendar.current
        let values = asymmetry.map(\.value)
        let recent = average(of: asymmetry.suffix(7).map(\.value)) ?? values.last ?? 0
        let baseline = baselineAverage ?? recent
        let steadinessRecent = steadiness.suffix(7).map(\.value)
        let steadinessAvg = steadinessRecent.isEmpty ? nil : steadinessRecent.reduce(0, +) / Double(steadinessRecent.count)

        var signals: [String] = []
        var score = 88

        if recent > 18 {
            signals.append("近 7 天不对称均值偏高")
            score -= 22
        } else if recent > 14 {
            signals.append("近 7 天不对称均值抬升")
            score -= 12
        }

        if baseline > 0, recent > baseline * 1.25 {
            signals.append("比近一个月明显更不对称")
            score -= 12
        }

        let highDays = asymmetry.suffix(7).filter { $0.value >= 15 }.count
        if highDays >= 3 {
            signals.append("连续 \(highDays) 天超过 15%")
            score -= 14
        }

        if let steadinessAvg, steadinessAvg < 42 {
            signals.append("步态平稳度偏低")
            score -= 10
        }

        score = max(36, min(95, score))

        let riskLevel: WalkingAsymmetryDailySummary.RiskLevel
        if score >= 80 {
            riskLevel = .stable
        } else if score >= 68 {
            riskLevel = .mild
        } else if score >= 52 {
            riskLevel = .caution
        } else {
            riskLevel = .high
        }

        let headline: String
        switch riskLevel {
        case .stable:
            headline = "左右步伐整体保持在均衡区间。"
        case .mild:
            headline = "步态出现了轻微不对称，还没有到明显失衡。"
        case .caution:
            headline = "近几天步态不对称在连续抬升，值得结合疲劳一起看。"
        case .high:
            headline = "多条步态信号一起提示，先照顾身体再观察走路。"
        }

        let narrative: String
        if signals.isEmpty {
            narrative = String(localized: "步态样本暂时没有出现需要放大的同向偏移。")
        } else {
            narrative = "最值得优先看的是\(signals.prefix(2).joined(separator: "、"))。"
        }

        var parts: [String] = []
        if recent > 0 {
            parts.append(String(format: "近 7 天均值 %.1f%%", recent))
        }
        if let steadinessAvg {
            parts.append(String(format: "平稳度 %.0f%%", steadinessAvg))
        }
        let populated = Set(asymmetry.map { calendar.startOfDay(for: $0.date) }).count
        parts.append("覆盖 \(populated) 个有效日")
        let explanation = "这次判断主要综合了 \(parts.joined(separator: "、"))。"

        let dailySummary = WalkingAsymmetryDailySummary(
            riskLevel: riskLevel,
            score: score,
            headline: headline,
            narrative: narrative,
            explanation: explanation,
            signalPills: signalPills(recent: recent, baseline: baseline, steadinessAvg: steadinessAvg, highDays: highDays),
            accentColor: tint(for: riskLevel)
        )
        self.dailySummary = dailySummary

        interpretationCards = [
            WalkingAsymmetryInterpretationCard(
                id: "single-day",
                title: "单日解释",
                badge: riskLevel == .stable ? String(localized: "今天偏稳") : String(localized: "轻微偏移"),
                summary: riskLevel == .stable
                    ? String(localized: "单日读数更适合放在趋势里看，不必因为某一天抬高就调整节奏。")
                    : String(localized: "单日抬升更像是疲劳或走路姿势的临时影响，先看连续几天的方向。"),
                detail: String(localized: "步态不对称在 10% 以内属于常见波动；10%-15% 之间值得继续观察；超过 15% 且连续出现时，才更值得结合负荷与恢复一起理解。"),
                tint: tint(for: riskLevel)
            ),
            WalkingAsymmetryInterpretationCard(
                id: "week",
                title: "7 天解释",
                badge: highDays >= 3 ? String(localized: "连续偏高") : String(localized: "近一周观察"),
                summary: highDays >= 3
                    ? String(localized: "最近 7 天里有 \(highDays) 天超过 15%，更像是连续偏移而不是单日波动。")
                    : String(localized: "最近 7 天整体更接近常规波动，没有形成持续的单方向偏移。"),
                detail: String(localized: "一周维度更适合看方向，不适合拿单日高低做硬判断。"),
                tint: Color(hex: "5B8CFF")
            ),
            WalkingAsymmetryInterpretationCard(
                id: "month",
                title: "30 天解释",
                badge: String(localized: "长期画像"),
                summary: recent > baseline
                    ? String(localized: "最近 7 天比前几周略更不对称，可以回顾一下训练量与走路姿势。")
                    : String(localized: "最近 30 天没有形成明显的单方向迁移。"),
                detail: String(localized: "月度层面更适合拿来理解你的步态画像，而不是判断某一天是不是异常。"),
                tint: Color(hex: "39B98A")
            )
        ]

        abnormalDays = buildAbnormalDays(asymmetry: asymmetry, calendar: calendar)

        if highDays >= 3 || recent > 15 {
            manualProfile = WalkingAsymmetryManualProfile(
                title: String(localized: "负荷侧倾型"),
                badge: String(localized: "步态优先"),
                tint: Color(hex: "FF9F0A")
            )
        } else {
            manualProfile = WalkingAsymmetryManualProfile(
                title: String(localized: "均衡维持型"),
                badge: String(localized: "整体平稳"),
                tint: Color(hex: "39B98A")
            )
        }

        signalLanguageCard = WalkingAsymmetryInterpretationCard(
            id: "signal-language",
            title: String(localized: "步态信号合读"),
            badge: signals.isEmpty ? String(localized: "看组合") : String(localized: "单点待复核"),
            summary: signals.isEmpty
                ? String(localized: "不对称百分比和平稳度暂时没有同向偏移，单个数字轻微变化更像普通波动。")
                : "\(signals.prefix(2).joined(separator: "、"))，先和睡眠、负荷一起看，不把它当成结论。",
            detail: String(localized: "步态不对称反映左右迈步时间差，10% 以内常见；步态平稳度反映走路是否稳；两条信号连续几天同向偏移时，才值得提高关注。"),
            tint: signals.isEmpty ? Color(hex: "39B98A") : Color(hex: "5B8CFF")
        )
    }

    private func signalPills(recent: Double, baseline: Double?, steadinessAvg: Double?, highDays: Int) -> [WalkingAsymmetryDailySummary.SignalPill] {
        [
            .init(
                id: "recent",
                title: String(localized: "近 7 天均值"),
                value: String(format: "%.1f%%", recent),
                note: String(localized: "当前状态"),
                tint: Color(hex: "2E9BC6")
            ),
            .init(
                id: "baseline",
                title: String(localized: "前期均值"),
                value: baseline.map { String(format: "%.1f%%", $0) } ?? "--",
                note: String(localized: "对比基线"),
                tint: Color(hex: "5B8CFF")
            ),
            .init(
                id: "steadiness",
                title: String(localized: "步态平稳度"),
                value: steadinessAvg.map { String(format: "%.0f%%", $0) } ?? "--",
                note: String(localized: "稳定性线索"),
                tint: Color(hex: "39B98A")
            ),
            .init(
                id: "highdays",
                title: String(localized: "超 15% 天数"),
                value: "\(highDays) 天",
                note: String(localized: "近 7 天统计"),
                tint: highDays >= 3 ? Color(hex: "F46B5A") : Color(hex: "8D7AFF")
            )
        ]
    }

    private func buildAbnormalDays(asymmetry: [TimeSeriesPointDouble], calendar: Calendar) -> [WalkingAsymmetryAbnormalDay] {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")

        return asymmetry.suffix(30).compactMap { point in
            guard point.value >= 15 else { return nil }
            let level = point.value >= 20
            return WalkingAsymmetryAbnormalDay(
                id: "abnormal-\(Int(point.date.timeIntervalSince1970))",
                date: point.date,
                dateText: formatter.string(from: point.date),
                reason: level
                    ? String(localized: "这一天步态不对称明显抬高，更像是值得单独留意的信号。")
                    : String(localized: "这一天步态不对称越过了 15% 参考线。"),
                actionSuggestion: level
                    ? String(localized: "回看当天的训练量、负重和睡眠，优先按恢复日理解。")
                    : String(localized: "把它放回前后几天一起看，判断是不是连续在偏移。"),
                levelText: level ? String(localized: "高扰动日") : String(localized: "需留意日"),
                tint: level ? Color(hex: "F46B5A") : Color(hex: "FF9F0A")
            )
        }
        .sorted { $0.date > $1.date }
        .prefix(5)
        .map { $0 }
    }

    private func average(of values: [Double]) -> Double? {
        let valid = values.filter { $0 > 0 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    private func tint(for riskLevel: WalkingAsymmetryDailySummary.RiskLevel) -> Color {
        switch riskLevel {
        case .stable: return Color(hex: "39B98A")
        case .mild: return Color(hex: "5B8CFF")
        case .caution: return Color(hex: "FF9F0A")
        case .high: return Color(hex: "F46B5A")
        }
    }
}

#Preview {
    WalkingAsymmetryDetailView(
        metric: DashboardOtherMetricCardModel(
            id: "walking_asymmetry",
            title: "步态不对称",
            valueText: "8.2",
            unitText: "%",
            statusText: "平衡良好",
            statusTone: .positive,
            deltaText: "与昨天基本一致",
            lastUpdatedText: "今天 08:30",
            trendPoints: [],
            isInteractive: true,
            destination: .walkingAsymmetry
        )
    )
}
