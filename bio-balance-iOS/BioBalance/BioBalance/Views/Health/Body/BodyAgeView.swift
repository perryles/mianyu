/// BodyAgeView 由 HealthHubView 调用，作为「身体年龄」详情页。
/// 负责展示身体年龄结果、周趋势、影响因子、身体状态解读与手动录入入口。

import SwiftUI

/// Body Age View 由 `HealthHubView` 调用，作为健康页里"身体年龄"入口对应的专属详情页面。
/// 负责展示身体年龄结果摘要、周趋势、影响因子和身体状态解读。
struct BodyAgeView: View {
    @AppStorage("onboarding_age") private var onboardingAge: Int = 25

    @State private var healthAge: Int? = nil
    @State private var healthInsights = BodyAgeInsightsViewModel()
    @State private var bodyAgeInterpretation = BodyAgeInterpretationViewModel()
    @State private var interpretationTab: InterpretationTab = .signals
    @State private var showingManualSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var subscriptionManager = SubscriptionManager.shared

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

    private let accentBlue = Color(hex: "4C7DFF")
    private let accentAmber = Color(hex: "F3A53B")
    private let accentSlate = Color(hex: "5F6F86")
    private let accentMint = Theme.Colors.mintGreen

    var body: some View {
        ZStack {
            HealthDetailPageBackground(
                topGlow: Color(hex: "F1D5C1"),
                lowerGlow: Color(hex: "F9E9DC")
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    bodyAgeSpotlight
                    bodyAgeInterpretationSection
                    bodyAgeFactorsSection
                    bodyAgeTrendSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HealthDetailDesignSystem.pageHorizontalPadding)
                    .padding(.top, HealthDetailDesignSystem.pageTopPadding)
                    .padding(.bottom, 120)
            }
        }
        .healthDetailNavigation(title: HealthPageName.bodyAge)
        .task {
            healthAge = await HealthKitManager.shared.fetchChronologicalAge()
            healthInsights.load(chronologicalAge: healthAge ?? onboardingAge)
            await bodyAgeInterpretation.load()
        }
    }

    private var bodyAgeInterpretationSection: some View {
        healthSection(
            title: "今日解读",
            subtitle: ""
        ) {
            VStack(alignment: .leading, spacing: 12) {
                bodyAgeDailyStatusCard

                if bodyAgeInterpretation.state == .ready {
                    bodyAgeDeepInterpretationCard
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
    private var bodyAgeDeepInterpretationCard: some View {
        let availableTabs = InterpretationTab.allCases.filter { tab in
            switch tab {
            case .signals:
                return bodyAgeInterpretation.signalLanguageCard != nil || bodyAgeInterpretation.manualProfile != nil
            case .fluctuation:
                return !bodyAgeInterpretation.interpretationCards.isEmpty
            case .abnormal:
                return !bodyAgeInterpretation.abnormalDays.isEmpty
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
                        bodyAgeSignalsTabContent
                    case .fluctuation:
                        bodyAgeFluctuationTabContent
                    case .abnormal:
                        bodyAgeAbnormalTabContent
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
    private var bodyAgeSignalsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = bodyAgeInterpretation.signalLanguageCard {
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
                        bodyAgeInterpretationBadge(text: item.badge, tint: item.tint)
                    }
                    Text(item.detail)
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .background(Theme.Colors.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            if let profile = bodyAgeInterpretation.manualProfile {
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
                            Text("身体状态说明书")
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
                .accessibilityLabel("查看完整身体状态说明书")
                .sheet(isPresented: $showingManualSheet) {
                    NavigationStack {
                        bodyAgeManualSheetView(profile: profile)
                    }
                    .adaptiveSheetChrome(style: .page, detents: [.medium, .large], dragIndicator: .visible)
                }
            }
        }
    }

    @ViewBuilder
    private var bodyAgeFluctuationTabContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(bodyAgeInterpretation.interpretationCards.prefix(3))) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.title)
                            .font(.appSystem(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer(minLength: 0)
                        bodyAgeInterpretationBadge(text: item.badge, tint: item.tint)
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
    private var bodyAgeAbnormalTabContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(bodyAgeInterpretation.abnormalDays.prefix(2))) { day in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(day.dateText)
                            .font(.appSystem(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer(minLength: 0)
                        bodyAgeInterpretationBadge(text: day.levelText, tint: day.tint)
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

    private func bodyAgeManualSheetView(profile: BodyAgeManualProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("身体状态说明书")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text(profile.title)
                        .font(.appSystem(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    bodyAgeInterpretationBadge(text: profile.badge, tint: profile.tint)
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
                    bodyAgeProfileRow(title: "近期优先看", value: profile.priorities)
                    bodyAgeProfileRow(title: "轻动作建议", value: profile.action)
                    bodyAgeProfileRow(title: "不要过度放大", value: profile.dontOverread)
                }
                .padding(14)
                .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(20)
        }
        .healthDetailNavigation(title: "状态说明书")
    }

    private var bodyAgeFactorsSection: some View {
        healthSection(
            title: "影响来源",
            subtitle: ""
        ) {
            BodyAgeImpactSourcesCard()
        }
    }


    private var bodyAgeTrendSection: some View {
        HealthLockedModuleContainer(isUnlocked: subscriptionManager.isPro) {
            trendSection
        }
    }

    private var bodyAgeDailyStatusCard: some View {
        let summary = bodyAgeInterpretation.dailySummary
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    bodyAgeInterpretationBadge(
                        text: summary?.riskTitle ?? bodyAgeInterpretation.state.title,
                        tint: summary?.accentColor ?? accentSlate
                    )

                    Text(summary?.headline ?? bodyAgeInterpretation.state.headline)
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(summary?.narrative ?? bodyAgeInterpretation.state.detail)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    ZStack {
                        Text("--")
                            .font(.appSystem(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .opacity(summary == nil ? 1 : 0)
                        Text(summary?.scoreText ?? "")
                            .font(.appSystem(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .opacity(summary == nil ? 0 : 1)
                            .contentTransition(reduceMotion ? MotionTokens.numberTransitionReduced : MotionTokens.numberTransition)
                            .animation(reduceMotion ? MotionTokens.numberAnimationReduced : MotionTokens.numberAnimation, value: summary?.scoreText)
                    }
                    Text("今日状态")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .frame(width: 86, height: 92)
                .bbTintedSurface(
                    tint: summary?.accentColor ?? accentBlue,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                    tintStrength: 0.09,
                    shadow: false
                )
            }

            if let summary {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Array(summary.signalPills.prefix(4))) { pill in
                        bodyAgeSignalPill(pill)
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

    private func bodyAgeSignalPill(_ pill: BodyAgeDailySummary.SignalPill) -> some View {
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

    private func bodyAgeInterpretationBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func bodyAgeProfileRow(title: String, value: String) -> some View {
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

    private var bodyAgeSpotlight: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("近 7 天评估")
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "183A34"))
                    Text("每天随健康数据更新")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "6D7D78"))
                }

                Spacer(minLength: 8)

                Label(healthInsights.dataCoverageText, systemImage: "checkmark.seal.fill")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "177B69"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .bbTintedChip(tint: accentMint, in: Capsule(), tintOpacity: 0.10)
            }

            BodyAgeVitalOrb(
                valueText: bodyAgeDisplayText,
                comparisonText: chronologicalCompareText,
                statusText: healthInsights.statusText,
                isWaiting: healthInsights.bodyAge == nil
            )
            .frame(maxWidth: .infinity)

            BodyAgePaceScale(rate: healthInsights.agingRate)

            bodyAgeGuidanceCard
        }
        .padding(20)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.top, 4)
    }

    private var bodyAgeGuidanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: bodyAgeGuidanceSymbol)
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundColor(accentMint)
                    .frame(width: 30, height: 30)
                    .bbTintedChip(tint: accentMint, in: Circle(), tintOpacity: 0.12)

                Text(healthRecommendationHeadline)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "173B35"))

                Spacer(minLength: 0)

                Text(healthInsights.statusText)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "177B69"))
            }

            Text(bodyAgeGuidanceDetail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "526B65"))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .bbTintedSurface(
            tint: accentMint,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            tintStrength: 0.055,
            shadow: false
        )
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            LockedTrendCard(title: "身体年龄周趋势", points: healthInsights.bodyAgeTrend, unit: "岁", tint: accentBlue, usesTintedSurface: true, tintedSurfaceTint: .white)
            LockedTrendCard(title: "年龄变化速率", points: healthInsights.agingRateTrend, unit: "", tint: accentAmber, usesTintedSurface: true, tintedSurfaceTint: .white)
            LockedTrendCard(title: "年龄差趋势", points: healthInsights.ageGapTrend, unit: "岁", tint: accentMint, usesTintedSurface: true, tintedSurfaceTint: .white)
        }
    }

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

    private var bodyAgeDisplayText: String {
        if let bodyAge = healthInsights.bodyAge {
            return String(format: "%.1f", bodyAge)
        }
        return "--"
    }

    private var chronologicalCompareText: String {
        guard let bodyAge = healthInsights.bodyAge else {
            return String(localized: "补齐样本后再和实际年龄比较")
        }

        let delta = bodyAge - Double(healthAge ?? onboardingAge)
        if abs(delta) < 1 {
            return String(localized: "与实际年龄基本一致")
        }
        if delta < 0 {
            return String(localized: "比实际年龄年轻 \(Int(abs(delta).rounded())) 岁")
        }
        return String(localized: "比实际年龄偏高 \(Int(delta.rounded())) 岁")
    }

    private var healthRecommendationHeadline: String {
        guard let agingRate = healthInsights.agingRate else { return String(localized: "继续累积健康数据") }
        if agingRate <= 1 {
            return String(localized: "恢复节奏稳定")
        }
        if agingRate <= 1.5 {
            return String(localized: "优先补恢复与睡眠")
        }
        return String(localized: "先降低恢复压力")
    }

    private var bodyAgeGuidanceSymbol: String {
        guard let agingRate = healthInsights.agingRate else { return "waveform.path.ecg" }
        return agingRate <= 1 ? "checkmark.circle.fill" : "arrow.down.heart.fill"
    }

    private var bodyAgeGuidanceDetail: String {
        guard let agingRate = healthInsights.agingRate else {
            return String(localized: "继续同步睡眠、活动、HRV、静息心率和心肺数据，样本更完整后会生成更稳定的身体年龄判断。")
        }
        if agingRate <= 1 {
            return String(localized: "当前变化速率处在稳定区间。继续保持睡眠和活动节律，更适合按周观察方向，不必放大单日波动。")
        }
        if agingRate <= 1.5 {
            return String(localized: "当前变化速率略快。优先补足睡眠并减少连续高负荷，观察接下来一周是否逐步回到基准线。")
        }
        return String(localized: "近期恢复信号提示负荷累积较快。先降低额外消耗、保证连续睡眠，再结合身体感受持续观察。")
    }
}

/// 身体年龄首屏的生命体主视觉。使用原生 Shape 与固定粒子坐标，保证浅色主题下稳定、可缩放，
/// 同时避免把健康结果固化进位图资源。
private struct BodyAgeVitalOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let valueText: String
    let comparisonText: String
    let statusText: String
    let isWaiting: Bool

    private let particles: [BodyAgeOrbParticle] = [
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
                    AngularGradient(colors: [Theme.Colors.pastelCyan, Theme.Colors.pastelGreen, Theme.Colors.pastelYellow, Theme.Colors.pastelCyan], center: .center),
                    lineWidth: 24
                )
                .padding(16)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                ZStack {
                    Text("--")
                        .font(.appSystem(size: 52, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "102D29"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .opacity(valueText == "--" ? 1 : 0)
                    Text(valueText == "--" ? "" : valueText)
                        .font(.appSystem(size: 52, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "102D29"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .opacity(valueText == "--" ? 0 : 1)

                }

                Text("身体年龄")
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .tracking(2.2)
                    .foregroundColor(Color(hex: "5A746E"))

                Text(comparisonText)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "15765F"))
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
                .foregroundColor(Color(hex: "146B59"))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
                .overlay(Capsule().stroke(Color(hex: "BCEBDD"), lineWidth: 1))
                .offset(y: 5)
        }

        .accessibilityElement(children: .ignore)
        .accessibilityLabel("身体年龄 \(valueText)，\(comparisonText)，\(statusText)")
    }
}

private struct BodyAgePaceScale: View {
    let rate: Double?

    private var normalizedRate: CGFloat {
        let value = min(max(rate ?? 1, -1), 3)
        return CGFloat((value + 1) / 4)
    }

    private var valueText: String {
        guard let rate else { return "--" }
        return String(format: "%.1fx", rate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("年龄变化速率")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "183A34"))
                Spacer(minLength: 0)
                Text(valueText)
                    .font(.appSystem(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "173B35"))
            }

            HStack {
                Label("慢", systemImage: "tortoise.fill")
                Spacer(minLength: 0)
                Label("快", systemImage: "hare.fill")
            }
            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: "7A8985"))

            GeometryReader { proxy in
                let markerX = max(5, min(proxy.size.width - 5, proxy.size.width * normalizedRate))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(hex: "DCE8E4"))
                        .frame(height: 4)
                        .position(x: proxy.size.width / 2, y: 20)

                    ForEach(0..<41, id: \.self) { index in
                        Capsule()
                            .fill(index == 20 ? Color(hex: "63B8A3") : Color(hex: "B8C8C3"))
                            .frame(width: index % 10 == 0 ? 2 : 1, height: index % 10 == 0 ? 24 : 14)
                            .position(x: proxy.size.width * CGFloat(index) / 40, y: 20)
                    }

                    Capsule()
                        .fill(Color(hex: "117A63"))
                        .frame(width: 4, height: 38)
                        .position(x: markerX, y: 20)
                        .shadow(color: Color(hex: "117A63").opacity(0.24), radius: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(hex: "117A63"), lineWidth: 3))
                        .position(x: markerX, y: 3)
                }
                .opacity(rate == nil ? 0.55 : 1)
            }
            .frame(height: 40)

            HStack {
                Text("-1.0x")
                Spacer(minLength: 0)
                Text("1.0x 基准")
                Spacer(minLength: 0)
                Text("3.0x")
            }
            .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(Color(hex: "81908C"))
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("年龄变化速率 \(valueText)，范围负一点零倍到三点零倍，一点零倍为基准")
    }
}

private struct BodyAgeOrbParticle {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
}


private struct BodyAgeImpactSourcesCard: View {
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
            return String(format: String(localized: "%+.1f岁"), value)
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

    private let items = HealthFactorKey.allCases.map(FactorItem.init)

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
            BodyAgeImpactDetailSheet(detail: detail)
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
            if hours >= 8 {
                impact = -0.7
            } else if hours >= 7 {
                impact = -0.3
            } else if hours < 6 {
                impact = 0.8
            } else {
                impact = 0.3
            }
        case .sleepConsistency:
            if latestValue >= 85 {
                impact = -0.7
            } else if latestValue >= 75 {
                impact = -0.2
            } else if latestValue < 60 {
                impact = 0.7
            } else {
                impact = 0.3
            }
        case .aerobicTraining:
            if latestValue >= 45 {
                impact = -0.5
            } else if latestValue >= 20 {
                impact = -0.1
            } else {
                impact = 0.4
            }
        case .strengthTraining:
            if latestValue >= 30 {
                impact = -0.4
            } else if latestValue >= 10 {
                impact = -0.1
            } else {
                impact = 0.5
            }
        case .steps:
            if latestValue >= 8000 {
                impact = -0.8
            } else if latestValue >= 5000 {
                impact = -0.2
            } else {
                impact = 0.6
            }
        case .vo2Max:
            if latestValue >= 38 {
                impact = -0.8
            } else if latestValue >= 32 {
                impact = -0.2
            } else {
                impact = 0.6
            }
        case .restingHeartRate:
            if latestValue <= 62 {
                impact = -0.6
            } else if latestValue <= 72 {
                impact = -0.2
            } else {
                impact = 0.6
            }
        case .bodyFat:
            let percent = latestValue * 100.0
            if percent <= 18 {
                impact = -0.4
            } else if percent <= 24 {
                impact = -0.1
            } else {
                impact = 0.5
            }
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
        case .sleepDuration:
            return String(localized: "近 14 天睡眠约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))先把连续几晚睡够，身体年龄通常会更容易回稳。")
        case .sleepConsistency:
            return String(localized: "近 14 天作息一致性约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))先把入睡和起床时间拉回稳定区间。")
        case .aerobicTraining:
            return String(localized: "近 14 天有氧训练约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))先看这一段时间的基础活动有没有跟上。")
        case .strengthTraining:
            return String(localized: "近 14 天力量训练约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))力量刺激偏少时，身体年龄更容易停在保守判断。")
        case .steps:
            return String(localized: "近 14 天步数约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))先把日常活动底盘补回来，比偶发一天走很多更有用。")
        case .vo2Max:
            return String(localized: "近 14 天最大摄氧量约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))心肺储备是身体年龄里很关键的一条长期线索。")
        case .restingHeartRate:
            return String(localized: "近 14 天静息心率约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))静息状态更平稳时，恢复压力通常也更低。")
        case .bodyFat:
            return String(localized: "近 14 天体脂率约 \(recentText)，近 60 天约 \(baselineText)。\(descriptorNarrative(descriptor))身体组成更适合看长期方向，不用放大单次波动。")
        }
    }

    private func descriptorNarrative(_ descriptor: ImpactDescriptor) -> String {
        guard let value = descriptor.value else { return String(localized: "目前影响还不明显。") }
        if value < 0 {
            return String(localized: "它现在大约让身体年龄低 \(String(format: "%.1f", abs(value))) 岁。")
        }
        if value > 0 {
            return String(localized: "它现在大约让身体年龄高 \(String(format: "%.1f", value)) 岁。")
        }
        return String(localized: "它现在基本是中性影响。")
    }
}

private struct BodyAgeImpactDetailSheet: View {
    let detail: BodyAgeImpactSourcesCard.ImpactDetailSnapshot

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

                    Text("对身体年龄的当前影响")
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

            bodyAgeImpactBalanceBar(
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

    private func bodyAgeImpactBalanceBar(leftAccent: Color, rightAccent: Color) -> some View {
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

/// Health Age Trend Point 由 `BodyAgeInsightsViewModel` 生成，作为身体年龄趋势图的单日点位数据。
/// 负责承载某一天的身体年龄、年龄差或变化速率数值，供趋势卡片和图表复用。
struct HealthAgeTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

@MainActor
/// Body Age Insights View Model 由 `BodyAgeView` 持有，作为身体年龄专属页面的数据整理层。
/// 负责读取近 7 天健康样本，估算身体年龄、变化速率和年龄差趋势，并生成页面摘要文案。
@Observable
final class BodyAgeInsightsViewModel {
    var bodyAge: Double?
    var agingRate: Double?
    var bodyAgeTrend: [HealthAgeTrendPoint] = []
    var agingRateTrend: [HealthAgeTrendPoint] = []
    var ageGapTrend: [HealthAgeTrendPoint] = []
    var dataCoverageText: String = String(localized: "正在读取健康 App")
    var statusText: String = String(localized: "等待数据")
    var suggestionText: String = String(localized: "补齐睡眠、HRV 与活动记录")

    func load(chronologicalAge: Int) {
        Task {
            async let sleep = HealthFactorKey.sleepDuration.loadSeries(days: 7)
            async let steps = HealthFactorKey.steps.loadSeries(days: 7)
            async let vo2 = HealthFactorKey.vo2Max.loadSeries(days: 7)
            async let rhr = HealthFactorKey.restingHeartRate.loadSeries(days: 7)

            let hrvSeries = (try? await HealthKitManager.shared.fetchDailyHRVAverages(days: 7)) ?? []
            let sleepSeries = await sleep
            let stepSeries = await steps
            let vo2Series = await vo2
            let rhrSeries = await rhr

            let calendar = Calendar.current
            let end = calendar.startOfDay(for: Date())
            let sortedDates = (0..<7).compactMap { offset in
                calendar.date(byAdding: .day, value: -(6 - offset), to: end)
            }

            let hrvByDay = valuesByDay(hrvSeries)
            let sleepByDay = valuesByDay(sleepSeries)
            let stepsByDay = valuesByDay(stepSeries)
            let vo2ByDay = valuesByDay(vo2Series)
            let rhrByDay = valuesByDay(rhrSeries)

            let ages = sortedDates.map { day -> HealthAgeTrendPoint in
                HealthAgeTrendPoint(
                    date: day,
                    value: estimateBodyAge(
                        chronologicalAge: chronologicalAge,
                        hrv: hrvByDay[day],
                        sleepMinutes: sleepByDay[day],
                        steps: stepsByDay[day],
                        vo2Max: vo2ByDay[day],
                        restingHeartRate: rhrByDay[day]
                    )
                )
            }

            let rates = ages.enumerated().map { index, point -> HealthAgeTrendPoint in
                let previous = index > 0 ? ages[index - 1].value : Double(chronologicalAge)
                let delta = point.value - previous
                return HealthAgeTrendPoint(date: point.date, value: max(-1, min(3, 1 + delta / 2.0)))
            }

            let gaps = ages.map { point in
                HealthAgeTrendPoint(
                    date: point.date,
                    value: point.value - Double(chronologicalAge)
                )
            }

            let latestAge = ages.last?.value
            let latestRate = rates.last?.value
            bodyAgeTrend = ages
            agingRateTrend = rates
            ageGapTrend = gaps
            bodyAge = latestAge
            agingRate = latestRate

            let populatedDays = sortedDates.filter { day in
                hrvByDay[day] != nil || sleepByDay[day] != nil || stepsByDay[day] != nil || vo2ByDay[day] != nil || rhrByDay[day] != nil
            }.count
            dataCoverageText = populatedDays == 0
                ? String(localized: "健康 App 暂无数据")
                : String(localized: "\(populatedDays)/7 天有记录")
            if let latestAge {
                let delta = latestAge - Double(chronologicalAge)
                statusText = abs(delta) < 1
                    ? String(localized: "接近实际年龄")
                    : (delta < 0
                        ? String(localized: "年轻 \(Int(abs(delta).rounded())) 岁")
                        : String(localized: "偏高 \(Int(delta.rounded())) 岁"))
                suggestionText = latestRate.map {
                    $0 <= 1 ? String(localized: "恢复节奏稳定") : String(localized: "优先改善睡眠和恢复")
                } ?? String(localized: "继续累积健康数据")
            } else {
                statusText = String(localized: "等待数据")
                suggestionText = String(localized: "授权健康 App 并佩戴设备记录")
            }
        }
    }

    private func valuesByDay(_ points: [TimeSeriesPointDouble]) -> [Date: Double] {
        let calendar = Calendar.current
        return Dictionary(uniqueKeysWithValues: points.map { (calendar.startOfDay(for: $0.date), $0.value) })
    }

    private func estimateBodyAge(
        chronologicalAge: Int,
        hrv: Double?,
        sleepMinutes: Double?,
        steps: Double?,
        vo2Max: Double?,
        restingHeartRate: Double?
    ) -> Double {
        var adjustment = 0.0

        if let hrv, hrv > 0 {
            adjustment += hrv >= 55 ? -1.2 : (hrv < 30 ? 1.5 : 0)
        }
        if let sleepMinutes, sleepMinutes > 0 {
            adjustment += sleepMinutes >= 420 ? -0.9 : (sleepMinutes < 360 ? 1.2 : 0)
        }
        if let steps, steps > 0 {
            adjustment += steps >= 8000 ? -0.8 : (steps < 4000 ? 0.8 : 0)
        }
        if let vo2Max, vo2Max > 0 {
            adjustment += vo2Max >= 38 ? -1.0 : (vo2Max < 28 ? 1.0 : 0)
        }
        if let restingHeartRate, restingHeartRate > 0 {
            adjustment += restingHeartRate <= 62 ? -0.6 : (restingHeartRate >= 78 ? 0.9 : 0)
        }

        return max(12, Double(chronologicalAge) + adjustment)
    }
}

#Preview {
    BodyAgeView()
}
