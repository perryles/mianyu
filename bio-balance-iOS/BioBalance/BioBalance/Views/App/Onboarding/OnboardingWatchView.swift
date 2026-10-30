import SwiftUI

struct OnboardingWatchView: View {
    let step: AppOnboardingStep
    let goBack: (() -> Void)?

    var body: some View {
        OnboardingStepScaffold(
            step: step,
            title: String(localized: "有 Apple Watch，\n眠屿会更完整"),
            detail: String(localized: "它会自动补全睡眠、心率和活动趋势；没有手表，也不影响使用。"),
            goBack: goBack
        ) {
            WatchExperienceHero()
        }
    }
}

private struct WatchExperienceHero: View {
    @State private var watchService = WatchConnectivitySyncService.shared

    private var pairingStatus: String {
        switch watchService.watchActivationState {
        case .activated:
            watchService.isWatchPaired ? String(localized: "已配对") : String(localized: "未配对")
        case .notSupported, .notActivated, .inactive:
            String(localized: "不可检测")
        }
    }

    var body: some View {
        OnboardingHeroSurface {
            ZStack {
                Circle()
                    .fill(Color(hex: "C4E9DC").opacity(0.62))
                    .frame(width: 196, height: 196)

                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color(hex: "D1E5DE"))
                    .frame(width: 72, height: 250)
                    .overlay {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(Color(hex: "B2D1C7").opacity(0.65), lineWidth: 1)
                    }

                watchBody

                OnboardingMetricCard(label: String(localized: "昨夜睡眠"), value: "7h45")
                    .frame(width: 110)
                    .offset(x: -108, y: 82)

                OnboardingMetricCard(label: String(localized: "当前心率"), value: "62 bpm")
                    .frame(width: 102)
                    .offset(x: 108, y: -84)

                Text("没有 Apple Watch，也可以正常使用眠屿。")
                    .font(.system(size: 10))
                    .foregroundStyle(OnboardingV3Palette.textTertiary)
                    .offset(y: 136)

                Text(pairingStatus)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(OnboardingV3Palette.brandGreen)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Color(hex: "EBFAF5"), in: Capsule())
                    .overlay { Capsule().stroke(Theme.Colors.surfaceBorder, lineWidth: 1) }
                    .offset(x: 112, y: -130)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .clipped()
            .task {
                watchService.activateIfNeeded()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Apple Watch 使用预览")
            .accessibilityValue("\(pairingStatus)，昨夜睡眠 7 小时 45 分，当前心率每分钟 62 次")
        }
    }

    private var watchBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color(hex: "1A1F24"))
                .frame(width: 148, height: 170)
                .shadow(color: Color(hex: "081412").opacity(0.25), radius: 26, y: 12)
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(Color(hex: "131B1B"))
                .frame(width: 118, height: 142)
            VStack(spacing: 4) {
                Text("82").font(.system(size: 29, weight: .bold)).foregroundStyle(.white)
                Text("状态不错").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: "C4EDDB"))
                Text("睡眠 · 心率 · 活动 · 恢复")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(hex: "A3B0B8"))
                    .padding(.top, 14)
                HStack(spacing: 9) {
                    Circle().fill(Color(hex: "5FC3B2")).frame(width: 6, height: 6)
                    Circle().fill(Color(hex: "6B94DC")).frame(width: 6, height: 6)
                    Circle().fill(Color(hex: "DD6B76")).frame(width: 6, height: 6)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
