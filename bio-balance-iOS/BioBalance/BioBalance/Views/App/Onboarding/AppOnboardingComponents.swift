import SwiftUI

enum OnboardingV3Palette {
    static let pageBackground = Theme.Colors.pageBackground
    static let heroBackground = Theme.Colors.secondarySurface
    static let heroBorder = Theme.Colors.surfaceBorder
    static let brandGreen = Theme.Colors.mintGreen
    static let darkGreen = Color(hex: "0E6E5E")
    static let textPrimary = Theme.Colors.textPrimary
    static let textSecondary = Theme.Colors.textSecondary
    static let textTertiary = Theme.Colors.textTertiary
    static let muted = Theme.Colors.textSecondary
    static let progressTrack = Theme.Colors.secondaryBackground
    static let border = Theme.Colors.surfaceBorder.opacity(0.85)
}

enum OnboardingMotion {
    static let progress: Animation = .easeOut(duration: 0.28)
    static let scoreRing: Animation = .easeOut(duration: 0.70)
    static let transitionHalfDuration: TimeInterval = 0.13
    static let transitionHalf: Animation = .easeOut(duration: transitionHalfDuration)
}

enum OnboardingTransitionDirection: Equatable {
    case forward
    case backward

    var initialOffset: CGFloat { self == .forward ? 1 : -1 }
    var finalOffset: CGFloat { -initialOffset }
}

struct OnboardingTransitionWash: View {
    let direction: OnboardingTransitionDirection
    let offsetProgress: CGFloat
    let opacity: Double

    var body: some View {
        GeometryReader { proxy in
            let travel = proxy.size.width * 0.86

            ZStack {
                RoundedRectangle(cornerRadius: 46, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                OnboardingV3Palette.brandGreen.opacity(0),
                                Color(hex: "C8F0E2").opacity(0.30),
                                Color.white.opacity(0.72),
                                OnboardingV3Palette.brandGreen.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * 0.64, height: proxy.size.height * 1.16)
                    .rotationEffect(.degrees(direction == .forward ? -7 : 7))

                Circle()
                    .fill(OnboardingV3Palette.brandGreen.opacity(0.08))
                    .frame(width: 150, height: 150)
                    .offset(x: direction == .forward ? 54 : -54, y: -70)
            }
            .offset(x: travel * offsetProgress)
            .opacity(opacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct OnboardingStepScaffold<Hero: View>: View {
    let step: AppOnboardingStep
    let title: String
    let detail: String
    let goBack: (() -> Void)?
    @ViewBuilder let hero: () -> Hero

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                OnboardingStepProgress(step: step, goBack: goBack)
                hero()
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(.system(.title, design: .default, weight: .bold))
                        .foregroundStyle(OnboardingV3Palette.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(detail)
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(OnboardingV3Palette.textSecondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

struct OnboardingStepProgress: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let step: AppOnboardingStep
    let goBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if let goBack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(OnboardingV3Palette.darkGreen)
                .accessibilityLabel("上一步")
                .padding(.vertical, -10)
            }

            Text("眠屿  ·  \(step.number.formatted(.number.grouping(.never)))/06  ·  \(step.shortTitle)")
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(OnboardingV3Palette.darkGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(AppOnboardingStep.allCases) { item in
                    Capsule()
                        .fill(item == step ? OnboardingV3Palette.brandGreen : OnboardingV3Palette.progressTrack)
                        .frame(width: item == step ? 26 : 10, height: 4)
                        .animation(reduceMotion ? nil : OnboardingMotion.progress, value: step)
                }
            }
        }
        .frame(minHeight: 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("首次引导进度")
        .accessibilityValue("第 \(step.number) 步，共 6 步")
    }
}

struct OnboardingHeroSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(minHeight: 300)
            .background(OnboardingV3Palette.heroBackground)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(OnboardingV3Palette.heroBorder, lineWidth: 1)
            }
            .shadow(color: Color(hex: "0A2E21").opacity(0.04), radius: 14, y: 10)
    }
}

struct OnboardingMetricCard: View {
    let label: String
    let value: String
    var accent: Color? = nil
    var valueColor: Color = OnboardingV3Palette.textPrimary

    var body: some View {
        HStack(spacing: 7) {
            if let accent {
                Capsule().fill(accent.opacity(0.82)).frame(width: 3, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(OnboardingV3Palette.muted)
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(OnboardingV3Palette.border, lineWidth: 1)
        }
        .shadow(color: Color(hex: "0F291F").opacity(0.08), radius: 12, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

struct OnboardingFooter: View {
    let step: AppOnboardingStep
    let isLoading: Bool
    let healthPhase: HealthAuthorizationPhase
    let primaryAction: () -> Void
    let secondaryAction: (() -> Void)?

    private var primaryTitle: String {
        if step == .healthPermission, healthPhase.canContinueWithoutRequest {
            return String(localized: "继续")
        }
        return step.primaryButtonTitle
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: primaryAction) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().tint(Theme.Colors.onAccent)
                    }
                    Text(primaryTitle)
                        .font(.system(.headline, design: .default, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(OnboardingV3Palette.brandGreen, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color(hex: "0F1724").opacity(0.08), radius: 11, y: 8)
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(isLoading)
            .accessibilityLabel(primaryTitle)
            .accessibilityValue(isLoading ? "处理中" : "")

            if let secondaryAction {
                Button("暂时跳过", action: secondaryAction)
                    .font(.system(size: 12))
                    .foregroundStyle(OnboardingV3Palette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)
                    .accessibilityHint("现在不会请求健康数据权限")
            } else if let note = step.footerNote {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(OnboardingV3Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(OnboardingV3Palette.pageBackground.opacity(0.98))
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

private extension AppOnboardingStep {
    var footerNote: String? {
        switch self {
        case .focus: String(localized: "之后可以随时调整")
        case .watch: String(localized: "Apple Watch 不是必需项")
        case .welcome, .healthPermission, .dailyPreview, .ready: nil
        }
    }
}
