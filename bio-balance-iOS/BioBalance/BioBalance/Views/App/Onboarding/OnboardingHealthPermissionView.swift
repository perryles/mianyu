import SwiftUI

struct OnboardingHealthPermissionView: View {
    let step: AppOnboardingStep
    let phase: HealthAuthorizationPhase
    let goBack: (() -> Void)?

    var body: some View {
        OnboardingStepScaffold(
            step: step,
            title: String(localized: "数据属于你，权限也属于你"),
            detail: String(localized: "眠屿只会在你明确授权后访问所需项目。你可以现在选择，也可以之后再设置。"),
            goBack: goBack
        ) {
            HealthPermissionHero(phase: phase)
        }
    }
}

private struct HealthPermissionHero: View {
    let phase: HealthAuthorizationPhase

    private let rows: [(String, String, String, Color)] = [
        (String(localized: "睡眠"), String(localized: "睡眠阶段与时长"), "bed.double.fill", Color(hex: "6678C7")),
        (String(localized: "心率"), String(localized: "静息与日常心率"), "heart.fill", Color(hex: "C74D57")),
        (String(localized: "血氧"), String(localized: "血氧饱和度记录"), "drop.fill", Color(hex: "477AC7")),
        (String(localized: "呼吸率"), String(localized: "睡眠与静息呼吸率"), "wind", Color(hex: "C77A21"))
    ]

    var body: some View {
        OnboardingHeroSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("只连接你愿意分享的数据")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(OnboardingV3Palette.textPrimary)
                        Text("每项权限由你决定，也可以之后再改")
                            .font(.system(size: 11))
                            .foregroundStyle(OnboardingV3Palette.textTertiary)
                    }
                    Spacer()
                    Label(phase.onboardingStatusText, systemImage: "lock.shield.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(OnboardingV3Palette.brandGreen)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Color(hex: "EBFAF5"), in: Capsule())
                }

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 12) {
                            Image(systemName: row.2)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(row.3)
                                .frame(width: 28, height: 28)
                                .background(row.3.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.0).font(.system(size: 12, weight: .bold))
                                Text(row.1)
                                    .font(.system(size: 10))
                                    .foregroundStyle(OnboardingV3Palette.textTertiary)
                            }
                            Spacer()
                            Text("可选择")
                                .font(.system(size: 9))
                                .foregroundStyle(OnboardingV3Palette.darkGreen)
                        }
                        .frame(minHeight: 39)
                        .accessibilityElement(children: .combine)

                        if index < rows.count - 1 {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                Text("数据归你所有 · 明确允许后才能读取 · 可随时在系统设置中关闭")
                    .font(.system(size: 10))
                    .foregroundStyle(OnboardingV3Palette.darkGreen)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(OnboardingV3Palette.heroBackground, in: Capsule())
                    .overlay { Capsule().stroke(Color(hex: "CFE8DE"), lineWidth: 1) }
            }
            .padding(17)
            .frame(minHeight: 264)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(OnboardingV3Palette.border, lineWidth: 1)
            }
            .shadow(color: Color(hex: "0F291F").opacity(0.10), radius: 22, y: 8)
            .padding(17)
        }
    }
}
