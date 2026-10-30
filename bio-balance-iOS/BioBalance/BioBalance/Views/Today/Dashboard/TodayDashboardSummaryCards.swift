import SwiftUI

nonisolated enum TodayDashboardContentPolicy {
    static let maximumVisiblePatterns = 2
}

struct TodaySummaryCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.035 : 0))
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous))
    }
}

struct TodayHealthPatternsCard: View {
    let patterns: [TodayDashboardPattern]
    let isLoading: Bool

    private var visiblePatterns: [TodayDashboardPattern] {
        Array(patterns.prefix(TodayDashboardContentPolicy.maximumVisiblePatterns))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("健康规律", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer(minLength: 0)

                Text("近30天")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Color(hex: "6D8390"))
            }

            if isLoading && visiblePatterns.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color(hex: "3C88A5"))
                    Text("正在归纳健康规律")
                        .font(Theme.Typography.supporting)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(visiblePatterns.enumerated()), id: \.offset) { _, pattern in
                        TodayHealthPatternRow(pattern: pattern)
                    }
                }
            }
        }
        .padding(16)
        .todayCardSurface(tint: Theme.Colors.mintGreen)
    }
}

private struct TodayHealthPatternRow: View {
    let pattern: TodayDashboardPattern

    private var tone: (foreground: Color, background: Color) {
        switch pattern.tone {
        case .positive: return (Color(hex: "18866B"), Color(hex: "DDF3E9"))
        case .attention: return (Color(hex: "B56B25"), Color(hex: "FFF0DA"))
        case .neutral: return (Color(hex: "4479A2"), Color(hex: "E2EFF8"))
        case .muted: return (Color(hex: "737D85"), Color(hex: "EEF1F2"))
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pattern.systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tone.foreground)
                .frame(width: 30, height: 30)
                .background(tone.background, in: Circle())

            Text(pattern.title)
                .font(Theme.Typography.supporting)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
    }
}

struct TodayPreviousWeekSummaryCard: View {
    let review: WeeklyHealthReview
    let rangeText: String

    private var presentation: TodayPreviousWeekCardPresentation {
        TodayPreviousWeekCardPresentationBuilder.make(review: review)
    }

    private var accent: Color {
        switch review.direction {
        case .improving: return Color(hex: "2D91C9")
        case .declining: return Color(hex: "D78237")
        case .stable: return Color(hex: "628E73")
        case .unavailable: return Color(hex: "7B858D")
        }
    }

    private var directionImage: String {
        switch review.direction {
        case .improving: return "arrow.up.right"
        case .declining: return "arrow.down.right"
        case .stable: return "arrow.right"
        case .unavailable: return "clock"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("上周小结", systemImage: "doc.text.image.fill")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Color(hex: "9A642E"))

                Spacer(minLength: 0)

                Text(rangeText)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Color(hex: "78856E"))
            }

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Image(systemName: directionImage)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(accent)
                            .frame(width: 28, height: 28)
                            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                        Text(presentation.primaryValue)
                            .font(.appSystem(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(accent)

                        Text(presentation.primaryLabel)
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Text(presentation.comparisonText)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(accent)
                }

                Spacer(minLength: 8)

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color(hex: "D8954E"))
                    .frame(width: 58, height: 58)
                    .background(Color(hex: "FFE7BD"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.Colors.onAccent, accent)
                    }
            }

        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(hex: "FFF9EC"), Color(hex: "FFFDF7")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous)
                .stroke(Color(hex: "F3E7CF"), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开周报详情")
    }

}
