/// BasalEnergyDetailView 由 HealthHubView 调用，作为「基础代谢」详情页。
/// 负责展示基础代谢稳定性摘要、影响来源、底盘消耗解读与手动录入入口。

import SwiftUI

/// 基础代谢详情视图 由 `HealthHubView` 调用，作为健康页里"基础代谢"入口对应的专属详情页面。
/// 负责展示基础代谢稳定性摘要、影响来源和底盘消耗解读，样式参考 BodyAgeView。
struct BasalEnergyDetailView: View {
    let card: HabitBodyMetricCardModel
    let selectedDate: Date
    let summary: String
    var showsDismissButton: Bool = false

    @State private var interpretation = BasalEnergyInterpretationViewModel()
    @State private var interpretationTab: InterpretationTab = .signals
    @State private var showingManualSheet = false
    private var subscriptionManager = SubscriptionManager.shared

    init(
        card: HabitBodyMetricCardModel,
        selectedDate: Date,
        summary: String,
        showsDismissButton: Bool = false
    ) {
        self.card = card
        self.selectedDate = selectedDate
        self.summary = summary
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

    private let accentAmber = Color(hex: "E89B3B")
    private let accentBlue = Color(hex: "4C7DFF")
    private let accentSlate = Color(hex: "5F6F86")

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    basalEnergySpotlight
                    basalEnergyInterpretationSection
                    basalEnergyFactorsSection
                    basalEnergyTrendSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HealthDetailDesignSystem.pageHorizontalPadding)
                    .padding(.top, HealthDetailDesignSystem.pageTopPadding)
                    .padding(.bottom, 120)
            }
        }
        .healthDetailNavigation(title: HealthPageName.basalEnergy)
        .task {
            await interpretation.load()
        }
    }

    // MARK: - 核心指标

    private var basalEnergySpotlight: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("近 7 天评估")
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "3A2E1A"))
                    Text("每天随健康数据更新")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "7D6E58"))
                }

                Spacer(minLength: 8)

                Label(card.trendSummaryText, systemImage: "checkmark.seal.fill")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "B86A1E"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .bbTintedChip(tint: accentAmber, in: Capsule(), tintOpacity: 0.10)
            }

            BasalEnergyVitalOrb(
                valueText: card.valueText == "暂无" ? "--" : card.valueText,
                unitText: card.unitText.isEmpty ? "kcal" : card.unitText,
                comparisonText: comparisonText,
                statusText: interpretation.dailySummary?.riskTitle ?? interpretation.state.title,
                isWaiting: card.isEmpty
            )
            .frame(maxWidth: .infinity)

            BasalEnergyStabilityScale(score: interpretation.dailySummary?.score)

            basalEnergyGuidanceCard
        }
        .padding(20)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.top, 4)
    }

    private var comparisonText: String {
        if card.isEmpty {
            return String(localized: "补齐样本后再看底盘消耗区间")
        }
        if let baseline = card.referenceValue, baseline > 0, let today = card.highlightValue, today > 0 {
            let delta = today - baseline
            let ratio = abs(delta) / baseline
            if ratio < 0.05 {
                return String(localized: "与近一周均值基本一致")
            }
            if delta < 0 {
                return String(localized: "低于均值 \(Int(abs(delta).rounded())) kcal")
            }
            return String(localized: "高于均值 \(Int(delta.rounded())) kcal")
        }
        return String(localized: "等待趋势数据")
    }

    private var basalEnergyGuidanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: guidanceSymbol)
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundColor(accentAmber)
                    .frame(width: 30, height: 30)
                    .bbTintedChip(tint: accentAmber, in: Circle(), tintOpacity: 0.12)

                Text(guidanceHeadline)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "3B2E1C"))

                Spacer(minLength: 0)

                Text(interpretation.dailySummary?.riskTitle ?? interpretation.state.title)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "B86A1E"))
            }

            Text(guidanceDetail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "5A4A38"))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .bbTintedSurface(
            tint: accentAmber,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            tintStrength: 0.055,
            shadow: false
        )
    }

    private var guidanceHeadline: String {
        guard let summary = interpretation.dailySummary else {
            return String(localized: "继续累积健康数据")
        }
        switch summary.stabilityLevel {
        case .stable: return String(localized: "底盘消耗稳定")
        case .mild: return String(localized: "优先补恢复与睡眠")
        case .caution: return String(localized: "适当降低负荷")
        case .high: return String(localized: "先照顾恢复")
        }
    }

    private var guidanceSymbol: String {
        guard let summary = interpretation.dailySummary else { return "flame" }
        switch summary.stabilityLevel {
        case .stable: return "checkmark.circle.fill"
        case .mild: return "arrow.down.heart.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .high: return "bolt.slash.fill"
        }
    }

    private var guidanceDetail: String {
        guard let summary = interpretation.dailySummary else {
            return String(localized: "继续同步基础代谢、睡眠、HRV 和活动数据，样本更完整后会生成更稳定的底盘消耗判断。")
        }
        switch summary.stabilityLevel {
        case .stable:
            return String(localized: "当前底盘消耗处在稳定区间。继续保持睡眠和活动节律，更适合按周观察方向，不必放大单日波动。")
        case .mild:
            return String(localized: "当前底盘消耗有轻微波动。优先补足睡眠并减少连续高负荷，观察接下来一周是否逐步回到基准线。")
        case .caution:
            return String(localized: "近期恢复信号提示负荷累积较快。先降低额外消耗、保证连续睡眠，再结合身体感受持续观察。")
        case .high:
            return String(localized: "多条核心信号都在同方向偏移。适合先把训练和刺激输入压下来，给身体留恢复窗口，再回看基础代谢是否回稳。")
        }
    }

    // MARK: - 解读区

    private var basalEnergyInterpretationSection: some View {
        healthSection(
            title: "今日解读",
            subtitle: ""
        ) {
            VStack(alignment: .leading, spacing: 12) {
                basalEnergyDailyStatusCard

                if interpretation.state == .ready {
                    basalEnergyDeepInterpretationCard
                }

                Text("仅供日常自我管理参考，不构成医疗诊断或治疗建议。若出现持续明显不适，请及时就医。")
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }

    @ViewBuilder
    private var basalEnergyDeepInterpretationCard: some View {
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
                        basalEnergySignalsTabContent
                    case .fluctuation:
                        basalEnergyFluctuationTabContent
                    case .abnormal:
                        basalEnergyAbnormalTabContent
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
    private var basalEnergySignalsTabContent: some View {
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
                    showingManualSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "book.closed.fill")
                            .font(.appSystem(size: 13, weight: .bold))
                            .foregroundColor(profile.tint)
                            .frame(width: 32, height: 32)
                            .bbTintedChip(tint: profile.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous), tintOpacity: 0.10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("底盘消耗说明书")
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
                .accessibilityLabel("查看完整底盘消耗说明书")
                .sheet(isPresented: $showingManualSheet) {
                    NavigationStack {
                        manualSheetView(profile: profile)
                    }
                    .adaptiveSheetChrome(style: .page, detents: [.medium, .large], dragIndicator: .visible)
                }
            }
        }
    }

    @ViewBuilder
    private var basalEnergyFluctuationTabContent: some View {
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
    private var basalEnergyAbnormalTabContent: some View {
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

    private func manualSheetView(profile: BasalEnergyManualProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("底盘消耗说明书")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text(profile.title)
                        .font(.appSystem(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    interpretationBadge(text: profile.badge, tint: profile.tint)
                }

                Text(profile.definition)
                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .bbTintedSurface(
                        tint: profile.tint,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                        tintStrength: 0.06
                    )

                VStack(spacing: 14) {
                    profileRow(title: "近期优先看", value: profile.priorities)
                    profileRow(title: "轻动作建议", value: profile.action)
                    profileRow(title: "不要过度放大", value: profile.dontOverread)
                }
                .padding(14)
                .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(20)
        }
        .healthDetailNavigation(title: "底盘消耗说明书")
    }

    private var basalEnergyDailyStatusCard: some View {
        let dailySummary = interpretation.dailySummary
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    interpretationBadge(
                        text: dailySummary?.riskTitle ?? interpretation.state.title,
                        tint: dailySummary?.accentColor ?? accentSlate
                    )

                    Text(dailySummary?.headline ?? interpretation.state.headline)
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(dailySummary?.narrative ?? interpretation.state.detail)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    Text(dailySummary?.scoreText ?? "--")
                        .font(.appSystem(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("稳定性")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .frame(width: 86, height: 92)
                .bbTintedSurface(
                    tint: dailySummary?.accentColor ?? accentAmber,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                    tintStrength: 0.09,
                    shadow: false
                )
            }

            if let dailySummary {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Array(dailySummary.signalPills.prefix(4))) { pill in
                        signalPill(pill)
                    }
                }

                Text(dailySummary.explanation)
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

    private func signalPill(_ pill: BasalEnergyDailySummary.SignalPill) -> some View {
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

    private func profileRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(value)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 影响因素区

    private var basalEnergyFactorsSection: some View {
        healthSection(
            title: "影响来源",
            subtitle: ""
        ) {
            BasalEnergyImpactSourcesCard()
        }
    }

    // MARK: - 趋势区

    private var basalEnergyTrendSection: some View {
        HealthLockedModuleContainer(isUnlocked: subscriptionManager.isPro) {
            trendSection
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            LockedTrendCard(
                title: "基础代谢周趋势",
                points: card.trendPoints.map { HealthAgeTrendPoint(date: $0.date, value: $0.value) },
                unit: "kcal",
                tint: accentAmber,
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

private struct BasalEnergyVitalOrb: View {
    let valueText: String
    let unitText: String
    let comparisonText: String
    let statusText: String
    let isWaiting: Bool

    private let particles: [BasalEnergyOrbParticle] = [
        .init(x: 0.19, y: 0.31, size: 4, opacity: 0.72),
        .init(x: 0.25, y: 0.20, size: 3, opacity: 0.58),
        .init(x: 0.34, y: 0.15, size: 5, opacity: 0.76),
        .init(x: 0.45, y: 0.11, size: 3, opacity: 0.62),
        .init(x: 0.57, y: 0.13, size: 6, opacity: 0.82),
        .init(x: 0.70, y: 0.20, size: 3, opacity: 0.66),
        .init(x: 0.79, y: 0.31, size: 5, opacity: 0.72),
        .init(x: 0.84, y: 0.44, size: 3, opacity: 0.48),
        .init(x: 0.82, y: 0.60, size: 6, opacity: 0.68),
        .init(x: 0.74, y: 0.73, size: 3, opacity: 0.58),
        .init(x: 0.62, y: 0.82, size: 5, opacity: 0.76),
        .init(x: 0.48, y: 0.86, size: 3, opacity: 0.60),
        .init(x: 0.34, y: 0.82, size: 6, opacity: 0.70),
        .init(x: 0.22, y: 0.72, size: 3, opacity: 0.52),
        .init(x: 0.14, y: 0.58, size: 5, opacity: 0.68),
        .init(x: 0.13, y: 0.43, size: 3, opacity: 0.56),
        .init(x: 0.29, y: 0.42, size: 2, opacity: 0.42),
        .init(x: 0.67, y: 0.39, size: 2, opacity: 0.44),
        .init(x: 0.37, y: 0.68, size: 2, opacity: 0.46),
        .init(x: 0.66, y: 0.66, size: 2, opacity: 0.48)
    ]

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.secondarySurface, lineWidth: 24)
                .padding(16)
            Circle()
                .stroke(
                    AngularGradient(colors: [Theme.Colors.pastelYellow, Theme.Colors.pastelGreen, Theme.Colors.pastelCyan, Theme.Colors.pastelYellow], center: .center),
                    lineWidth: 24
                )
                .padding(16)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(valueText)
                        .font(.appSystem(size: 52, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "2E1F0E"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if !unitText.isEmpty {
                        Text(unitText)
                            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "6B5238"))
                    }
                }

                Text("基础代谢")
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .tracking(2.2)
                    .foregroundColor(Color(hex: "7A6042"))

                Text(comparisonText)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "9C5A1A"))
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
                .foregroundColor(Color(hex: "8C5012"))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
                .overlay(Capsule().stroke(Color(hex: "F5D5A8"), lineWidth: 1))
                .offset(y: 5)
        }

        .accessibilityElement(children: .ignore)
        .accessibilityLabel("基础代谢 \(valueText) \(unitText)，\(comparisonText)，\(statusText)")
    }
}

private struct BasalEnergyOrbParticle {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
}


// MARK: - Stability Scale

private struct BasalEnergyStabilityScale: View {
    let score: Int?

    private var normalizedScore: CGFloat {
        let value = min(max(CGFloat(score ?? 84), 36), 95)
        return (value - 36) / (95 - 36)
    }

    private var valueText: String {
        guard let score else { return "--" }
        return "\(score)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("底盘稳定性")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "3A2E1A"))
                Spacer(minLength: 0)
                Text(valueText)
                    .font(.appSystem(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "3B2E1C"))
            }

            HStack {
                Label("低", systemImage: "thermometer.low")
                Spacer(minLength: 0)
                Label("高", systemImage: "thermometer.high")
            }
            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: "8A7B68"))

            GeometryReader { proxy in
                let markerX = max(5, min(proxy.size.width - 5, proxy.size.width * normalizedScore))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(hex: "F0E6D8"))
                        .frame(height: 4)
                        .position(x: proxy.size.width / 2, y: 20)

                    ForEach(0..<41, id: \.self) { index in
                        Capsule()
                            .fill(index == 20 ? Color(hex: "D9A84A") : Color(hex: "D4C8B8"))
                            .frame(width: index % 10 == 0 ? 2 : 1, height: index % 10 == 0 ? 24 : 14)
                            .position(x: proxy.size.width * CGFloat(index) / 40, y: 20)
                    }

                    Capsule()
                        .fill(Color(hex: "B86A1E"))
                        .frame(width: 4, height: 38)
                        .position(x: markerX, y: 20)
                        .shadow(color: Color(hex: "B86A1E").opacity(0.24), radius: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(hex: "B86A1E"), lineWidth: 3))
                        .position(x: markerX, y: 3)
                }
                .opacity(score == nil ? 0.55 : 1)
            }
            .frame(height: 40)

            HStack {
                Text("波动大")
                Spacer(minLength: 0)
                Text("基准")
                Spacer(minLength: 0)
                Text("稳定")
            }
            .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(Color(hex: "9A8B78"))
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("底盘稳定性 \(valueText)，范围 36 到 95，越高越稳定")
    }
}

// MARK: - Factors Card

private struct BasalEnergyImpactSourcesCard: View {
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
            return String(format: String(localized: "%+.0f kcal"), value)
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

    private let items: [FactorItem] = [
        .init(key: .sleepDuration),
        .init(key: .sleepConsistency),
        .init(key: .steps),
        .init(key: .vo2Max),
        .init(key: .restingHeartRate),
        .init(key: .bodyFat)
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
            BasalEnergyImpactDetailSheet(detail: detail)
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
        case .sleepDuration:
            let hours = latestValue / 60.0
            if hours >= 7.5 {
                impact = 45
            } else if hours >= 6.5 {
                impact = 15
            } else {
                impact = -55
            }
        case .sleepConsistency:
            if latestValue >= 80 {
                impact = 35
            } else if latestValue >= 70 {
                impact = 10
            } else {
                impact = -45
            }
        case .aerobicTraining:
            impact = 0
        case .strengthTraining:
            impact = 0
        case .steps:
            if latestValue >= 8000 {
                impact = 50
            } else if latestValue >= 5000 {
                impact = 15
            } else {
                impact = -35
            }
        case .vo2Max:
            if latestValue >= 38 {
                impact = 55
            } else if latestValue >= 32 {
                impact = 20
            } else {
                impact = -40
            }
        case .restingHeartRate:
            if latestValue <= 62 {
                impact = 45
            } else if latestValue <= 72 {
                impact = 15
            } else {
                impact = -50
            }
        case .bodyFat:
            let percent = latestValue * 100.0
            if percent <= 18 {
                impact = 35
            } else if percent <= 24 {
                impact = 10
            } else {
                impact = -30
            }
        }

        if impact > 0 {
            return ImpactDescriptor(value: impact, color: Theme.Colors.mintGreen, symbol: "chevron.up")
        }
        if impact < 0 {
            return ImpactDescriptor(value: impact, color: Color(hex: "E29A63"), symbol: "chevron.down")
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
        case .sleepDuration:
            return String(localized: "近 14 天睡眠约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))先把连续几晚睡够，基础代谢的底盘通常更容易回稳。")
        case .sleepConsistency:
            return String(localized: "近 14 天作息一致性约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))先把入睡和起床时间拉回稳定区间。")
        case .aerobicTraining:
            return String(localized: "近 14 天有氧训练约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))心肺刺激稳定时，底盘消耗的判断也更可靠。")
        case .strengthTraining:
            return String(localized: "近 14 天力量训练约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))肌肉量是基础代谢里很关键的长期底盘。")
        case .steps:
            return String(localized: "近 14 天步数约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))先把日常活动底盘补回来，比偶发一天走很多更有用。")
        case .vo2Max:
            return String(localized: "近 14 天最大摄氧量约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))心肺储备好的时候，基础代谢通常也更足。")
        case .restingHeartRate:
            return String(localized: "近 14 天静息心率约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))静息状态更平稳时，恢复压力通常也更低。")
        case .bodyFat:
            return String(localized: "近 14 天体脂率约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))身体组成更适合看长期方向，不用放大单次波动。")
        }
    }

    private func descriptorNarrative(_ descriptor: ImpactDescriptor) -> String {
        guard let value = descriptor.value else { return String(localized: "目前影响还不明显。") }
        if value > 0 {
            return String(localized: "它现在大约让基础代谢抬高 \(Int(value)) kcal。")
        }
        if value < 0 {
            return String(localized: "它现在大约让基础代谢压低 \(Int(abs(value))) kcal。")
        }
        return String(localized: "它现在基本是中性影响。")
    }
}

private struct BasalEnergyImpactDetailSheet: View {
    let detail: BasalEnergyImpactSourcesCard.ImpactDetailSnapshot

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

                    Text("对基础代谢的当前影响")
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

            basalEnergyImpactBalanceBar(
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

    private func basalEnergyImpactBalanceBar(leftAccent: Color, rightAccent: Color) -> some View {
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

#Preview {
    BasalEnergyDetailView(
        card: HabitBodyMetricCardModel(
            kind: .basal,
            title: "基础代谢",
            valueText: "1650",
            unitText: "kcal",
            goalText: "静息消耗",
            subtitleText: "今日基础代谢",
            trendSummaryText: "本周底盘平稳",
            comparisonText: "与近一周均值基本一致",
            referenceValue: 1620,
            highlightValue: 1650,
            symbol: "flame",
            tintHex: "E89B3B",
            trendPoints: [],
            isEmpty: false
        ),
        selectedDate: Date(),
        summary: "与近一周均值基本一致"
    )
}
