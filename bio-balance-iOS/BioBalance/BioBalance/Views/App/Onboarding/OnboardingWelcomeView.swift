import SwiftUI

struct OnboardingWelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let step: AppOnboardingStep
    let goBack: (() -> Void)?

    var body: some View {
        OnboardingStepScaffold(
            step: step,
            title: String(localized: "欢迎来到眠屿，\n先从今天的自己开始"),
            detail: String(localized: "睡眠、压力、活动和身体变化，会被整理成更安静、更容易理解的日常线索。"),
            goBack: goBack
        ) {
            WelcomeIslandHero(reduceMotion: reduceMotion)
        }
    }
}

private struct WelcomeIslandHero: View {
    let reduceMotion: Bool
    @State private var haloExpanded = false

    var body: some View {
        OnboardingHeroSurface {
            ZStack {
                Circle()
                    .fill(Color(hex: "D6EDFC").opacity(0.26))
                    .frame(width: 148, height: 148)
                    .offset(x: -154, y: 132)

                Circle()
                    .fill(Color(hex: "C2F0DE").opacity(0.34))
                    .frame(width: 170, height: 170)
                    .offset(x: 152, y: -104)

                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 188, height: 188)
                        .shadow(color: Color(hex: "0F291F").opacity(0.10), radius: 11, y: 8)
                    Circle().fill(Color(hex: "E9F8F2")).frame(width: 120, height: 120)
                    Circle().fill(Color(hex: "CCF0E0")).frame(width: 66, height: 66)
                    IslandMark()
                }
                .scaleEffect(reduceMotion ? 1 : (haloExpanded ? 1.02 : 0.97))
                .offset(y: -18)

                OnboardingMetricCard(
                    label: String(localized: "睡眠"),
                    value: "7h 45m",
                    accent: Color(hex: "6986D6")
                )
                .frame(width: 118)
                .offset(x: -102, y: 86)

                OnboardingMetricCard(
                    label: String(localized: "压力"),
                    value: "32",
                    accent: OnboardingV3Palette.brandGreen,
                    valueColor: OnboardingV3Palette.brandGreen
                )
                .frame(width: 102)
                .offset(x: 104, y: -82)

                OnboardingMetricCard(
                    label: String(localized: "心率"),
                    value: "62 bpm",
                    accent: Color(hex: "CC5563")
                )
                .frame(width: 112)
                .offset(x: 98, y: 90)

                Text("一座安静的小岛，慢慢看懂自己")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(OnboardingV3Palette.brandGreen, in: Capsule())
                    .shadow(color: Color(hex: "084738").opacity(0.17), radius: 12, y: 5)
                    .offset(y: 116)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .clipped()
            .task {
                guard !reduceMotion else { return }

                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    haloExpanded = true
                }
            }
        }
    }
}

private struct IslandMark: View {
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(.white.opacity(0.98)).frame(width: 22, height: 22)
                Circle()
                    .fill(Color(hex: "CCF0E0"))
                    .frame(width: 22, height: 22)
                    .offset(x: 7, y: -3)
            }
            .frame(width: 28, height: 23)
            Capsule().fill(OnboardingV3Palette.brandGreen.opacity(0.92)).frame(width: 40, height: 8)
            HStack(spacing: 4) {
                Capsule().fill(OnboardingV3Palette.brandGreen.opacity(0.56)).frame(width: 16, height: 2)
                Capsule().fill(OnboardingV3Palette.brandGreen.opacity(0.34)).frame(width: 14, height: 2)
            }
        }
        .accessibilityHidden(true)
    }
}
