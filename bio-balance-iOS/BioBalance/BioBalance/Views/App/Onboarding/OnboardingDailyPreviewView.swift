import SwiftUI

struct OnboardingDailyPreviewView: View {
    let step: AppOnboardingStep
    let goBack: (() -> Void)?

    var body: some View {
        OnboardingStepScaffold(
            step: step,
            title: String(localized: "每天，不用看懂所有数字"),
            detail: String(localized: "眠屿会先替你整理重点：一句状态、一件值得关注的事，再慢慢看长期趋势。"),
            goBack: goBack
        ) {
            DailyPreviewHero()
        }
    }
}

private struct DailyPreviewHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringProgress: CGFloat = 0

    var body: some View {
        OnboardingHeroSurface {
            ZStack {
                Circle()
                    .fill(Color(hex: "C2F0DE").opacity(0.34))
                    .frame(width: 166, height: 166)
                    .offset(x: 154, y: -130)

                VStack(spacing: 14) {
                    VStack(spacing: 0) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("今天的眠屿")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(OnboardingV3Palette.textTertiary)
                                Text("恢复不错")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(OnboardingV3Palette.textPrimary)
                                Text("睡眠与压力都在你的日常范围内")
                                    .font(.system(size: 10))
                                    .foregroundStyle(OnboardingV3Palette.textTertiary)
                            }
                            Spacer()
                            ScoreRing(progress: ringProgress)
                        }

                        HStack(spacing: 16) {
                            DailyMetricTile(
                                label: String(localized: "睡眠"),
                                value: String(localized: "7小时45分"),
                                tint: Color(hex: "EDF3FD"),
                                decoration: .sleep
                            )
                            DailyMetricTile(
                                label: String(localized: "压力"),
                                value: "32 / 100",
                                tint: OnboardingV3Palette.heroBackground,
                                decoration: .pressure
                            )
                        }
                        .padding(.top, 11)
                    }
                    .padding(17)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(OnboardingV3Palette.border, lineWidth: 1)
                    }
                    .shadow(color: Color(hex: "0F291F").opacity(0.10), radius: 22, y: 8)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("今天，只关注一件事")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(OnboardingV3Palette.darkGreen)
                        Text("下午活动偏少，晚间早点休息就好")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(OnboardingV3Palette.textPrimary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                    .padding(.horizontal, 15)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(alignment: .leading) {
                        Capsule().fill(OnboardingV3Palette.brandGreen).frame(width: 4, height: 46)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(OnboardingV3Palette.border, lineWidth: 1)
                    }
                    .shadow(color: Color(hex: "0F291F").opacity(0.08), radius: 12, y: 4)
                }
                .padding(17)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .clipped()
            .task {
                if reduceMotion {
                    ringProgress = 0.82
                    return
                }

                withAnimation(OnboardingMotion.scoreRing) {
                    ringProgress = 0.82
                }
            }
        }
    }
}

private struct ScoreRing: View {
    let progress: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color(hex: "E2F4EE"), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color(hex: "BCEAD9"),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("82")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(OnboardingV3Palette.brandGreen)
        }
        .frame(width: 72, height: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("综合状态")
        .accessibilityValue("82")
    }
}

private struct DailyMetricTile: View {
    enum Decoration { case sleep, pressure }

    let label: String
    let value: String
    let tint: Color
    let decoration: Decoration

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 9)).foregroundStyle(OnboardingV3Palette.muted)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(OnboardingV3Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 4)
            switch decoration {
            case .sleep:
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array([20, 26, 18, 31, 24].enumerated()), id: \.offset) { _, height in
                        Capsule()
                            .fill(Color(hex: "6185DB").opacity(0.52))
                            .frame(width: 4, height: CGFloat(height))
                    }
                }
            case .pressure:
                HStack(alignment: .center, spacing: 4) {
                    ForEach(0..<4) { index in
                        Circle()
                            .fill(OnboardingV3Palette.brandGreen.opacity(Double(index + 2) / 5))
                            .frame(width: 5, height: 5)
                            .offset(y: index.isMultiple(of: 2) ? -2 : 1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(tint, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}
