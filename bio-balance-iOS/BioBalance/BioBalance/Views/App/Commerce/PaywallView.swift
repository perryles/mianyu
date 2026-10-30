//
//  PaywallView.swift
//  BioBalance
//

/// PaywallView 由订阅入口与功能解锁引导调用，作为「付费墙」展示页。
/// 负责展示订阅方案选择、权益对比、隐私/条款跳转和转化引导。

import SwiftUI

/// Paywall视图 由上级页面或路由调用，作为订阅付费模块里的界面或内容组件。
/// 负责订阅付费展示与转化。
struct PaywallView: View {
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @Environment(\.dismiss) private var dismiss
    @Bindable private var subscriptionManager = SubscriptionManager.shared

    private let initialSku: String?
    @State private var selectedPlan: Int
    @State private var showingPrivacyPolicy = false
    @State private var showingTerms = false

    nonisolated static func unauthenticatedButtonTitle() -> String {
        "订阅"
    }

    init(initialSku: String? = nil) {
        self.initialSku = initialSku
        switch initialSku {
        case SubscriptionManager.MembershipSKU.monthly.rawValue:
            _selectedPlan = State(initialValue: 1)
        case SubscriptionManager.MembershipSKU.lifetime.rawValue:
            _selectedPlan = State(initialValue: 2)
        default:
            _selectedPlan = State(initialValue: 0)
        }
    }

    var body: some View {
        ZStack {
            paywallBackground
                .ignoresSafeArea()

            AdaptivePageScrollView(style: .hero, topPadding: 12, bottomPadding: 140) {
                VStack(spacing: 18) {
                    topBar
                    AdaptiveTwoPaneSection {
                        VStack(spacing: 18) {
                            heroCard
                            comparisonStrip
                        }
                    } secondary: {
                        VStack(spacing: 18) {
                            planSection
                            purchaseSupportSection
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            stickyPurchaseBar
        }
        .task {
            await subscriptionManager.loadProducts()
        }
    }

    private var paywallBackground: some View {
        ZStack {
            Theme.Colors.secondaryBackground

            LinearGradient(
                colors: [
                    Color(hex: "F8FFFD"),
                    Color(hex: "EEF9F6"),
                    Color(hex: "F7F7FB")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(hex: "B6F3EC").opacity(0.55))
                .frame(width: 280, height: 280)
                .blur(radius: 20)
                .offset(x: -120, y: -260)

            Circle()
                .fill(Color(hex: "DDF1FF").opacity(0.65))
                .frame(width: 300, height: 300)
                .blur(radius: 30)
                .offset(x: 150, y: -180)
        }
    }

    private var topBar: some View {
        HStack {
            Text(subscriptionManager.isPro ? "当前已解锁 Pro" : "支持恢复购买与测试购买")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(subscriptionManager.isPro ? Theme.Colors.mintGreen : Theme.Colors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Color.white.opacity(0.76),
                    in: Capsule()
                )

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Theme.Colors.surface.opacity(0.88), in: Circle())
            }
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            Color(hex: "F4FFFD"),
                            Color(hex: "EDF7F5")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.98), lineWidth: 1)
                )

            Circle()
                .fill(Color(hex: "98EFE6").opacity(0.55))
                .frame(width: 240, height: 240)
                .blur(radius: 18)
                .offset(x: 150, y: -72)

            Circle()
                .fill(Color(hex: "D9F4FF").opacity(0.75))
                .frame(width: 180, height: 180)
                .blur(radius: 20)
                .offset(x: -76, y: -86)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("眠屿 Pro")
                            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.mintGreen)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Theme.Colors.mintGreen.opacity(0.12),
                                in: Capsule()
                            )

                        Text("把每天的身体信号")
                            .font(.appSystem(size: 29, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("整理成更能行动的节奏")
                            .font(.appSystem(size: 29, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.82))
                            .frame(width: 52, height: 52)

                        Image(systemName: "crown.fill")
                            .font(.appSystem(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.Colors.mintGreen)
                    }
                }

                Text("连续趋势、关联分析和恢复建议会被放在同一套页面里，让你不只看到数字，还能更快判断下一步该做什么。")
                    .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(3)

                VStack(spacing: 10) {
                    heroFeatureRow(
                        icon: "waveform.path.ecg",
                        title: "把压力、心率、睡眠放在同一条线里看",
                        detail: "判断不再依赖单点数据，而是看连续变化和互相影响。"
                    )
                    heroFeatureRow(
                        icon: "sparkles",
                        title: "把“看懂数据”变成“更容易行动”",
                        detail: "重点提醒、恢复建议和每日动作会一起给到，而不是散落在不同模块。"
                    )
                }

                HStack(spacing: 10) {
                    ProStatPill(value: "长期趋势", label: "365 天记录")
                    ProStatPill(value: "关联分析", label: "压力 心率 睡眠")
                    ProStatPill(value: "App Store", label: "直接购买恢复")
                }
            }
            .padding(22)
        }
        .frame(minHeight: 208)
        .shadow(color: Color(hex: "8ADFD6").opacity(0.14), radius: 22, x: 0, y: 10)
    }

    private var comparisonStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("专业版带来的变化")
                    .font(.appSystem(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("不是多几个数据，而是把关键变化解释得更完整。")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            VStack(spacing: 10) {
                CapabilityRow(
                    icon: "waveform.path.ecg.rectangle",
                    title: "压力、心率、睡眠交叉解读",
                    freeText: "基础查看",
                    proText: "完整关联"
                )
                CapabilityRow(
                    icon: "calendar.badge.clock",
                    title: "长期趋势记录与对比",
                    freeText: "有限",
                    proText: "无限"
                )
                CapabilityRow(
                    icon: "sparkles.rectangle.stack",
                    title: "每日恢复建议与重点提醒",
                    freeText: "无",
                    proText: "已开启"
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.white.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("选择方案")
                    .font(.appSystem(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("先选适合当前节奏的方案，后续都可以通过 App Store 管理。")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            HStack(spacing: 10) {
                selectionMetaPill(title: "当前推荐", value: "年度会员", tint: Theme.Colors.mintGreen)
                selectionMetaPill(title: "灵活尝试", value: "月度会员", tint: Color(hex: "4CA7FF"))
                selectionMetaPill(title: "长期拥有", value: "终身会员", tint: Color(hex: "FF9D42"))
            }

            VStack(spacing: 12) {
                PremiumPlanCard(
                    title: "年度会员",
                    subtitle: "最适合长期记录、稳定追踪和持续改善",
                    price: "\(subscriptionManager.displayPrice(for: .yearly) ?? "¥198.00") / 年",
                    badge: "推荐",
                    tint: Color(hex: "007F79"),
                    isSelected: selectedPlan == 0
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        selectedPlan = 0
                    }
                }

                PremiumPlanCard(
                    title: "月度会员",
                    subtitle: "先完整体验，再决定是否长期保留",
                    price: "\(subscriptionManager.displayPrice(for: .monthly) ?? "¥28.00") / 月",
                    badge: nil,
                    tint: Color(hex: "4CA7FF"),
                    isSelected: selectedPlan == 1
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        selectedPlan = 1
                    }
                }

                PremiumPlanCard(
                    title: "终身会员",
                    subtitle: "一次买断，适合已经确定会长期使用的人",
                    price: "\(subscriptionManager.displayPrice(for: .lifetime) ?? "¥398.00") / 永久",
                    badge: "买断",
                    tint: Color(hex: "FF9D42"),
                    isSelected: selectedPlan == 2
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        selectedPlan = 2
                    }
                }
            }
        }
    }

    private var purchaseSupportSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            purchaseNotesCard

            HStack {
                Button(action: {
                    Task {
                        let ok = await subscriptionManager.restorePurchases()
                        if ok {
                            dismiss()
                        }
                    }
                }) {
                    Text("恢复购买")
                        .font(Theme.Typography.bodyMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .disabled(subscriptionManager.isPurchasing)

                Spacer()

                Text(subscriptionManager.usesSimulatedStoreKit ? "模拟器本地测试购买" : "通过 App Store 付款")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            if !subscriptionManager.lastError.isEmpty {
                Text(subscriptionManager.lastError)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(subscriptionManager.usesSimulatedStoreKit ? Theme.Colors.textSecondary : Color(hex: "B84728"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        subscriptionManager.usesSimulatedStoreKit ? Color(hex: "F3FBF8") : Color(hex: "FFF2ED"),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }

            subscriptionDisclosureCard
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.white.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.94), lineWidth: 1)
        )
        .sheet(isPresented: $showingPrivacyPolicy) {
            NavigationStack {
                PrivacyPolicyView()
            }
        }
        .sheet(isPresented: $showingTerms) {
            NavigationStack {
                TermsOfServiceView()
            }
        }
    }

    private var purchaseNotesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("当前选择", systemImage: "checkmark.seal.fill")
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.mintGreen)

            Text(selectedPlanSummaryTitle)
                .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(selectedPlanSummarySubtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(3)

            HStack(spacing: 10) {
                selectionMetaPill(title: "适合", value: selectedPlanBestFor, tint: selectedPlanTint)
                selectionMetaPill(title: "价格", value: selectedPlanPrice, tint: selectedPlanTint.opacity(0.92))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.secondaryBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var subscriptionDisclosureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("订阅说明", systemImage: "info.circle.fill")
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textSecondary)

            Text(selectedPlanDisclosure)
                .font(.appSystem(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Button("服务条款") {
                    showingTerms = true
                }

                Button("隐私政策") {
                    showingPrivacyPolicy = true
                }
            }
            .font(.appSystem(size: 12, weight: .semibold))
            .foregroundStyle(Theme.Colors.mintGreen)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface.opacity(0.70), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.92), lineWidth: 1)
        )
    }

    private var stickyPurchaseBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.0))
                .frame(height: 8)

            VStack(spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(selectedPlanSummaryTitle)
                                .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Text(selectedPlanBestFor)
                                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(selectedPlanTint)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(selectedPlanTint.opacity(0.12), in: Capsule())
                        }
                        Text(selectedPlanPrice)
                            .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer()

                    Button(action: {
                        Task {
                            let ok = await subscriptionManager.purchase(sku: selectedSku())
                            if ok {
                                dismiss()
                            }
                        }
                    }) {
                        ZStack {
                            Text(buttonTitle())
                                .opacity(subscriptionManager.isPurchasing ? 0 : 1)

                            if subscriptionManager.isPurchasing {
                                ProgressView()
                                    .tint(Theme.Colors.onAccent)
                            }
                        }
                        .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: adaptiveLayout.prefersTwoPaneLayout ? 172 : 162)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Theme.Colors.mintGreen, Color(hex: "34D1BF")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .disabled(subscriptionManager.isPurchasing)
                }

                Text(subscriptionManager.usesSimulatedStoreKit ? "模拟器下会自动切到本地测试购买；真机与 TestFlight 仍然直接走 App Store。" : "订阅与恢复购买都直接走 App Store，不依赖业务后台。")
                    .font(.appSystem(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.82), lineWidth: 1)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .background(Color.clear)
    }

    private var selectedPlanSummaryTitle: String {
        switch selectedPlan {
        case 0: "年度会员"
        case 1: "月度会员"
        default: "终身会员"
        }
    }

    private var selectedPlanSummarySubtitle: String {
        switch selectedPlan {
        case 0: "更适合稳定追踪长期变化，整体更划算"
        case 1: "先轻量开始，用一个月把核心能力体验完整"
        default: "一次购买后长期可用，适合已经确认长期使用"
        }
    }

    private var selectedPlanPrice: String {
        switch selectedPlan {
        case 0:
            return subscriptionManager.displayPrice(for: .yearly) ?? "¥198.00"
        case 1:
            return subscriptionManager.displayPrice(for: .monthly) ?? "¥28.00"
        default:
            return subscriptionManager.displayPrice(for: .lifetime) ?? "¥398.00"
        }
    }

    private var selectedPlanDisclosure: String {
        switch selectedPlan {
        case 0:
            return String(localized: "年度会员为自动续订订阅，确认购买后将通过 Apple ID 扣款；除非在当前订阅期结束前至少 24 小时取消，否则会自动续订。购买后可在 App Store 账号订阅设置中管理或取消。")
        case 1:
            return String(localized: "月度会员为自动续订订阅，确认购买后将通过 Apple ID 扣款；除非在当前订阅期结束前至少 24 小时取消，否则会自动续订。购买后可在 App Store 账号订阅设置中管理或取消。")
        default:
            return String(localized: "终身会员为一次性购买，不会自动续订。确认购买后将通过 Apple ID 扣款，权益用于解锁 眠屿 Pro 的 iOS 功能。")
        }
    }

    private var selectedPlanBestFor: String {
        switch selectedPlan {
        case 0: "长期记录"
        case 1: "先试一个月"
        default: "一次买断"
        }
    }

    private var selectedPlanTint: Color {
        switch selectedPlan {
        case 0: Color(hex: "007F79")
        case 1: Color(hex: "4CA7FF")
        default: Color(hex: "FF9D42")
        }
    }

    private func selectedSku() -> SubscriptionManager.MembershipSKU {
        switch selectedPlan {
        case 0: .yearly
        case 1: .monthly
        default: .lifetime
        }
    }

    private func buttonTitle() -> String {
        switch selectedPlan {
        case 0, 1: "立即订阅"
        default: "立即购买"
        }
    }
}

private func heroFeatureRow(icon: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .frame(width: 40, height: 40)

            Image(systemName: icon)
                .font(.appSystem(size: 16, weight: .bold))
                .foregroundStyle(Theme.Colors.mintGreen)
        }

        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.56))
    )
    .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.white.opacity(0.9), lineWidth: 1)
    )
}

private func selectionMetaPill(title: String, value: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.Colors.textTertiary)
        Text(value)
            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.Colors.textPrimary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
        tint.opacity(0.10),
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(tint.opacity(0.18), lineWidth: 1)
    )
}

private struct ProStatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(
            Color.white.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.92), lineWidth: 1)
        )
    }
}

private struct CapabilityRow: View {
    let icon: String
    let title: String
    let freeText: String
    let proText: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Colors.mintGreen.opacity(0.12))
                    .frame(width: 42, height: 42)

                Image(systemName: icon)
                    .font(.appSystem(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.mintGreen)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)

                HStack(spacing: 8) {
                    Text("免费版 \(freeText)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)

                    Text("Pro \(proText)")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.mintGreen)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Theme.Colors.secondaryBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PremiumPlanCard: View {
    let title: String
    let subtitle: String
    let price: String
    let badge: String?
    let tint: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    if let badge {
                        Text(badge)
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? .white : tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                isSelected ? tint : tint.opacity(0.12),
                                in: Capsule()
                            )
                    }
                }

                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(3)

                Text(price)
                    .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(isSelected ? tint : Theme.Colors.lightGray, lineWidth: 2)
                    .frame(width: 26, height: 26)

                if isSelected {
                    Circle()
                        .fill(tint)
                        .frame(width: 14, height: 14)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isSelected ? tint.opacity(0.12) : .white.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isSelected ? tint.opacity(0.9) : Color.white.opacity(0.92), lineWidth: 1.4)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.04), radius: isSelected ? 18 : 10, x: 0, y: 8)
    }
}

#Preview {
    PaywallView()
}
