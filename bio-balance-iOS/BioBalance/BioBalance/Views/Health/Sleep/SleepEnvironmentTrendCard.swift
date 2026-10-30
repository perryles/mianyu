/// SleepEnvironmentTrendCard 由睡眠详情页调用，作为「睡眠环境趋势」关联分析卡片。
/// 负责展示环境准备与睡眠质量的相关性分析及逐项因子影响。

import SwiftUI

/// 睡眠环境趋势卡片：展示环境准备与睡眠质量的关联分析和逐项影响。
struct SleepEnvironmentTrendCard: View {
    let summary: SleepEnvironmentTrendSummary
    var onOpenChecklist: (() -> Void)? = nil

    var body: some View {
        BBCard(style: .standard) {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                correlationSection

                if summary.correlation != .insufficient {
                    Divider()
                        .background(Theme.Colors.lightGray)
                    factorImpactsSection
                }

                Divider()
                    .background(Theme.Colors.lightGray)

                completionRateSection

                if let onOpenChecklist {
                    Button(action: onOpenChecklist) {
                        HStack {
                            Image(systemName: "checklist")
                            Text("今晚环境准备")
                        }
                        .font(.appSystem(.body, design: .rounded).bold())
                        .foregroundColor(Theme.Colors.mintGreen)
                    }
                }
            }
        }
    }

    // MARK: - 头部

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: summary.correlation.symbol)
                .font(.appSystem(size: 24, weight: .medium))
                .foregroundColor(correlationColor)
                .frame(width: 44, height: 44)
                .background(correlationColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.headline)
                    .font(.appSystem(.headline, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(summary.correlation.label)
                    .font(.appSystem(.caption, design: .rounded).bold())
                    .foregroundColor(correlationColor)
            }

            Spacer()
        }
    }

    // MARK: - 关联分析

    @ViewBuilder
    private var correlationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.insight)
                .font(.appSystem(.footnote, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if summary.correlation == .insufficient {
                insufficientSampleBox
            } else if let prepared = summary.preparedAvgScore,
               let unprepared = summary.unpreparedAvgScore {
                HStack(spacing: 12) {
                    scoreChip(
                        label: "有准备",
                        score: prepared,
                        nights: summary.preparedNights,
                        color: Theme.Colors.mintGreen
                    )
                    scoreChip(
                        label: "无准备",
                        score: unprepared,
                        nights: summary.unpreparedNights,
                        color: Theme.Colors.textTertiary
                    )
                    if let diff = summary.scoreDifference {
                        VStack(alignment: .center, spacing: 2) {
                            Text("差值")
                                .font(.appSystem(.caption2, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                            Text(signedScoreText(diff))
                                .font(.appSystem(.subheadline, design: .rounded).bold())
                                .foregroundColor(diff >= 3 ? Theme.Colors.mintGreen : Theme.Colors.textTertiary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var insufficientSampleBox: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.appSystem(.footnote, design: .rounded).bold())
                .foregroundColor(Theme.Colors.accentOrange)
                .frame(width: 28, height: 28)
                .background(Theme.Colors.accentOrange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("至少还需 \(max(0, 5 - summary.totalNights)) 晚有效样本")
                    .font(.appSystem(.footnote, design: .rounded).bold())
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("今晚完成清单后，明早睡眠评分会自动参与分析。")
                    .font(.appSystem(.caption, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Theme.Colors.accentOrange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func scoreChip(label: String, score: Int, nights: Int, color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.appSystem(.caption2, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("\(score)")
                .font(.appSystem(.title3, design: .rounded).bold())
                .foregroundColor(color)
            Text("\(nights) 晚")
                .font(.appSystem(.caption2, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 逐项影响

    @ViewBuilder
    private var factorImpactsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("环境因子影响")
                .font(.appSystem(.subheadline, design: .rounded).bold())
                .foregroundColor(Theme.Colors.textPrimary)

            let impactful = summary.factorImpacts
                .filter { $0.hasImpact }
                .sorted { $0.scoreDifference > $1.scoreDifference }

            if impactful.isEmpty {
                Text("各因子样本量不足，继续记录后会自动分析。")
                    .font(.appSystem(.caption, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            } else {
                ForEach(impactful.prefix(3)) { impact in
                    factorRow(impact: impact)
                }
            }
        }
    }

    @ViewBuilder
    private func factorRow(impact: EnvironmentFactorImpact) -> some View {
        HStack(spacing: 10) {
            Image(systemName: impact.symbol)
                .font(.appSystem(.footnote))
                .foregroundColor(Theme.Colors.mintGreen)
                .frame(width: 28, height: 28)
                .background(Theme.Colors.mintGreen.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(impact.title)
                    .font(.appSystem(.footnote, design: .rounded).bold())
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("完成 \(impact.nightsCompleted) 晚 | 跳过 \(impact.nightsSkipped) 晚")
                    .font(.appSystem(.caption2, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(impact.impactLabel)
                    .font(.appSystem(.caption2, design: .rounded).bold())
                    .foregroundColor(impactColor(impact))

                if impact.hasImpact {
                    Text("\(signedScoreText(impact.scoreDifference)) 分")
                        .font(.appSystem(.caption, design: .rounded).bold())
                        .foregroundColor(impactColor(impact))
                }
            }
        }
    }

    // MARK: - 近期完成率

    @ViewBuilder
    private var completionRateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("近 7 天完成率")
                    .font(.appSystem(.subheadline, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                Spacer()

                Text(String(format: "%.0f%%", summary.recentCompletionRate * 100))
                    .font(.appSystem(.subheadline, design: .rounded).bold())
                    .foregroundColor(rateColor(summary.recentCompletionRate))
            }

            // 进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.Colors.lightGray)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(rateColor(summary.recentCompletionRate))
                        .frame(width: geo.size.width * summary.recentCompletionRate, height: 6)
                }
            }
            .frame(height: 6)

            Text(summary.suggestion)
                .font(.appSystem(.caption, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 辅助颜色

    private var correlationColor: Color {
        switch summary.correlation {
        case .strong: return Theme.Colors.mintGreen
        case .moderate: return Theme.Colors.accentBlue
        case .weak: return Theme.Colors.textTertiary
        case .insufficient: return Theme.Colors.accentOrange
        }
    }

    private func impactColor(_ impact: EnvironmentFactorImpact) -> Color {
        if impact.scoreDifference >= 8 { return Theme.Colors.mintGreen }
        if impact.scoreDifference >= 3 { return Theme.Colors.accentBlue }
        if impact.scoreDifference <= -3 { return Theme.Colors.accentRed }
        return Theme.Colors.textTertiary
    }

    private func rateColor(_ rate: Double) -> Color {
        if rate >= 0.7 { return Theme.Colors.mintGreen }
        if rate >= 0.4 { return Theme.Colors.accentOrange }
        return Theme.Colors.textTertiary
    }

    private func signedScoreText(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}
