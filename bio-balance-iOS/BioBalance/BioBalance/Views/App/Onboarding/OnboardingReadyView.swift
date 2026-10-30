import SwiftUI

struct OnboardingReadyView: View {
    let step: AppOnboardingStep
    let goBack: (() -> Void)?

    var body: some View {
        OnboardingStepScaffold(
            step: step,
            title: String(localized: "从今天开始，\n按自己的节奏了解自己"),
            detail: String(localized: "不用一次改变很多。先从今天的一条线索开始，之后随时都可以调整权限和提醒。"),
            goBack: goBack
        ) {
            ReadyCeremonyHero()
        }
    }
}

private struct ReadyCeremonyHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var coreScale: CGFloat = 0.86
    @State private var haloVisible = false
    @State private var visibleSparkles = 0

    private let rows: [(String, String)] = [
        (String(localized: "今天 · 看懂状态"), String(localized: "先看最重要的一件事")),
        (String(localized: "这周 · 观察节律"), String(localized: "睡眠、压力与活动趋势")),
        (String(localized: "长期 · 认识自己"), String(localized: "按你的节奏持续记录"))
    ]

    var body: some View {
        OnboardingHeroSurface {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .stroke(Color(hex: "D8F1E7").opacity(haloVisible ? 0.7 : 0), lineWidth: 10)
                        .frame(width: 122, height: 122)
                    Circle()
                        .fill(Color(hex: "E7F8F1").opacity(haloVisible ? 1 : 0))
                        .frame(width: 104, height: 104)
                    Circle()
                        .fill(OnboardingV3Palette.brandGreen)
                        .frame(width: 70, height: 70)
                        .shadow(color: Color(hex: "085745").opacity(0.20), radius: 20, y: 8)
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)

                    sparkle(color: Color(hex: "63BCAF"), size: 8, index: 0).offset(x: -98, y: -32)
                    sparkle(color: Color(hex: "8BA7E1"), size: 6, index: 1).offset(x: 100, y: -18)
                    sparkle(color: Color(hex: "F0C97D"), size: 10, index: 2).offset(x: 116, y: 30)
                    sparkle(color: Color(hex: "EAAAB1"), size: 5, index: 3).offset(x: -116, y: 30)
                }
                .frame(height: 112)
                .scaleEffect(reduceMotion ? 1 : coreScale)

                Text("眠屿已经为你点亮")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(OnboardingV3Palette.darkGreen)

                VStack(spacing: 7) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(OnboardingV3Palette.darkGreen)
                                .frame(width: 22, height: 22)
                                .background(OnboardingV3Palette.heroBackground, in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.0)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(OnboardingV3Palette.textPrimary)
                                Text(row.1)
                                    .font(.system(size: 9))
                                    .foregroundStyle(OnboardingV3Palette.textTertiary)
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(13)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(OnboardingV3Palette.border, lineWidth: 1)
                }
                .shadow(color: Color(hex: "0F291F").opacity(0.10), radius: 22, y: 8)
                .padding(.horizontal, 17)
                .padding(.top, 18)
            }
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .top)
            .task {
                if reduceMotion {
                    coreScale = 1
                    haloVisible = true
                    visibleSparkles = 4
                    return
                }

                withAnimation(.easeOut(duration: 0.20)) {
                    haloVisible = true
                    coreScale = 1.06
                }
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(.easeOut(duration: 0.22)) {
                    coreScale = 1
                }
                for count in 1...4 {
                    withAnimation(.easeOut(duration: 0.16)) {
                        visibleSparkles = count
                    }
                    try? await Task.sleep(for: .milliseconds(45))
                }
            }
        }
    }

    private func sparkle(color: Color, size: CGFloat, index: Int) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(visibleSparkles > index ? 1 : 0)
            .scaleEffect(visibleSparkles > index ? 1 : 0.65)
            .accessibilityHidden(true)
    }
}
