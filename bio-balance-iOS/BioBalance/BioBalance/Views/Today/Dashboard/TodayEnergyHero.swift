/// TodayEnergyHero 由 DashboardView 调用，作为今日页首屏状态总览。
/// 以静态渐变椭圆、友好表情和能量进度表达综合压力的反向余量，不改变底层健康数据口径。

import SwiftUI

struct TodayEnergyHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artworkPresented = false

    let assessment: StressPresentationAssessment
    let prefersWideLayout: Bool
    let topSafeAreaInset: CGFloat
    let openAI: () -> Void

    private let progressTeal = Color(hex: "59B998")

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                heroBackdrop(in: proxy.size)

                if prefersWideLayout {
                    wideContent
                } else {
                    compactContent(in: proxy.size)
                }

                heroControls
            }
            .clipped()
        }
        .frame(height: prefersWideLayout ? 372 : 340)
        .accessibilityElement(children: .contain)
        .onAppear {
            artworkPresented = true
        }
    }

    private func heroBackdrop(in size: CGSize) -> some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [
                        TodayVisualTokens.mistBlue,
                        TodayVisualTokens.mistGreen,
                        TodayVisualTokens.softYellow
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(
                width: prefersWideLayout ? size.width * 0.78 : size.width * 1.46,
                height: prefersWideLayout ? size.height * 1.28 : size.height * 1.02
            )
            .position(
                x: prefersWideLayout ? size.width * 0.27 : size.width * 0.38,
                y: prefersWideLayout ? size.height * 0.42 : size.height * 0.18
            )
            .blur(radius: prefersWideLayout ? 8 : 5)
            .scaleEffect(reduceMotion ? 1 : (artworkPresented ? 1 : 0.88))
            .offset(y: reduceMotion ? 0 : (artworkPresented ? 0 : -18))
            .animation(
                reduceMotion ? nil : .spring(response: 0.82, dampingFraction: 0.72),
                value: artworkPresented
            )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var heroControls: some View {
        VStack {
            HStack {
                Spacer(minLength: 0)

                TodayAIEntryCapsule(action: openAI)
            }
            .padding(.horizontal, 24)
            .padding(.top, topSafeAreaInset + 14)

            Spacer(minLength: 0)
        }
    }

    private func compactContent(in size: CGSize) -> some View {
        let mascotSize = min(172, max(120, size.width * 0.38))
        return HStack(alignment: .center, spacing: 8) {
            heroSummary
                .frame(maxWidth: .infinity, alignment: .leading)

            heroMascot
                .frame(width: mascotSize, height: mascotSize)
        }
        .padding(.horizontal, 24)
        .padding(.top, topSafeAreaInset + 58)
        .padding(.bottom, 18)
    }

    private var wideContent: some View {
        HStack(spacing: 24) {
            heroMascot
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            heroSummary
                .frame(maxWidth: 370)
                .padding(.trailing, 34)
        }
        .padding(.top, topSafeAreaInset + 24)
        .padding(.leading, 16)
    }

    private var heroMascot: some View {
        TodayMascotView(assessment: assessment)
            .frame(
                width: prefersWideLayout ? 272 : 172,
                height: prefersWideLayout ? 272 : 172
            )
        .scaleEffect(reduceMotion ? 1 : (artworkPresented ? 1 : 0.88))
        .rotationEffect(.degrees(reduceMotion ? 0 : (artworkPresented ? 0 : -3)))
        .offset(y: reduceMotion ? 7 : (artworkPresented ? 7 : 25))
        .animation(
            reduceMotion ? nil : .spring(response: 0.78, dampingFraction: 0.68).delay(0.05),
            value: artworkPresented
        )
    }

    private var heroSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(greetingTitle)
                .font(.appSystem(size: prefersWideLayout ? 17 : 15, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "555B62"))
                .multilineTextAlignment(.leading)

            Text(energyStatusTitle)
                .font(.appSystem(size: prefersWideLayout ? 38 : 31, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "202329"))
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.76)
                .lineLimit(2)

            if assessment.hasData {
                availableEnergySummary
            } else {
                Label("先等待样本同步", systemImage: "arrow.triangle.2.circlepath")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var availableEnergySummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("可用余量")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color(hex: "666E73"))

                Spacer(minLength: 8)

                Text(energyPercentText)
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: "287D66"))
            }

            energyProgress
        }
        .padding(.top, 3)
    }

    private var energyProgress: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.secondaryBackground)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "8ED5BE"), progressTeal],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: max(
                            18,
                            proxy.size.width * (reduceMotion || artworkPresented ? energyCompletion : 0.06)
                        )
                    )
            }
            .overlay(Capsule().stroke(Color(hex: "D8DEDB"), lineWidth: 1))
            .animation(
                reduceMotion ? nil : .spring(response: 0.78, dampingFraction: 0.76).delay(0.12),
                value: artworkPresented
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.58, dampingFraction: 0.80),
                value: energyCompletion
            )
        }
        .frame(height: 11)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("能量潜力")
        .accessibilityValue(energyPercentText)
    }

    private var greetingTitle: String {
        String(localized: "今天的能量潜力")
    }

    private var energyStatusTitle: String {
        guard assessment.hasData else { return String(localized: "等待同步") }

        switch assessment.band {
        case .waiting:
            return String(localized: "等待同步")
        case .relaxed:
            return String(localized: "能量充沛")
        case .steady:
            return String(localized: "节奏平稳")
        case .mild:
            return String(localized: "稍微放缓")
        case .caution:
            return String(localized: "优先恢复")
        case .high:
            return String(localized: "先休息")
        }
    }

    private var energyCompletion: CGFloat {
        guard assessment.hasData, let score = assessment.score else { return 0 }
        return CGFloat(min(1, max(0.08, Double(100 - score) / 100)))
    }

    private var energyPercentText: String {
        localizedPercent(Int((energyCompletion * 100).rounded()))
    }
}
