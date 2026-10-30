/// DashboardHeaderBar 由 DashboardView 调用，作为「今日页顶部」品牌展示条。
/// 负责展示品牌 Logo 与 AI 健康助手入口按钮，不持有业务状态。

import SwiftUI

/// 今日页顶部仅负责品牌展示和 AI 入口，不持有 Dashboard 业务状态。
struct DashboardHeaderBar: View {
    let prefersTwoPaneLayout: Bool
    let openAI: () -> Void

    var body: some View {
        HStack {
            Image("TodayHeaderLogo")
                .resizable()
                .scaledToFit()
                .frame(
                    width: prefersTwoPaneLayout ? 296 : 214,
                    height: prefersTwoPaneLayout ? 62 : 44,
                    alignment: .leading
                )
                .accessibilityLabel("眠屿")

            Spacer(minLength: 0)

            TodayAIEntryCapsule(action: openAI)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// 今日页统一的 AI 入口。首屏 Hero 与关闭 Hero 后的标题栏共用同一视觉和交互规格。
struct TodayAIEntryCapsule: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.compact) {
                Image(systemName: "sparkles")
                    .font(Theme.Typography.captionBold)
                Text("AI")
                    .font(Theme.Typography.label)
            }
            .foregroundColor(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.medium)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.52), lineWidth: 1)
            }

            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI 健康助手")
    }
}

#Preview {
    DashboardHeaderBar(prefersTwoPaneLayout: false, openAI: {})
        .padding()
        .background(Theme.Colors.background)
}
