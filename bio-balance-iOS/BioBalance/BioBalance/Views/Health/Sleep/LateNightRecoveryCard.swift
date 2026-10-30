/// LateNightRecoveryCard 由睡眠页调用，作为「熬夜恢复」内容卡片。
/// 负责展示熬夜检测结果与次日恢复计划入口。

import SwiftUI

/// 熬夜恢复卡片：在睡眠页展示熬夜检测结果和次日恢复计划。
struct LateNightRecoveryCard: View {
    let summary: LateNightRecoverySummary
    var onStartRecovery: (() -> Void)? = nil

    var body: some View {
        if summary.hasNoSleepData {
            noSleepDataContent
        } else if summary.isActive, let plan = summary.plan {
            lateNightContent(plan: plan)
        } else {
            noLateNightContent
        }
    }

    // MARK: - 熬夜恢复内容

    @ViewBuilder
    private func lateNightContent(plan: LateNightRecoveryPlan) -> some View {
        BBCard(style: .standard) {
            VStack(alignment: .leading, spacing: 16) {
                headerSection(plan: plan)
                countdownSection(plan: plan)
                reasonsSection(plan: plan)

                Divider()
                    .background(Theme.Colors.lightGray)

                actionsSection(
                    title: "晨间恢复",
                    symbol: "sun.max.fill",
                    color: Theme.Colors.accentOrange,
                    actions: plan.morningActions
                )

                actionsSection(
                    title: "午后保护",
                    symbol: "cup.and.saucer.fill",
                    color: Theme.Colors.accentBlue,
                    actions: plan.afternoonActions
                )

                actionsSection(
                    title: "晚间收束",
                    symbol: "moon.stars.fill",
                    color: Theme.Colors.mintGreen,
                    actions: plan.eveningActions
                )

                Divider()
                    .background(Theme.Colors.lightGray)

                encouragementSection(plan: plan)

                if let onStartRecovery {
                    Button(action: onStartRecovery) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("启动熬夜恢复计划")
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
    private func headerSection(plan: LateNightRecoveryPlan) -> some View {
        let severity = plan.detection.severity
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: severity.symbol)
                .font(.appSystem(size: 28, weight: .medium))
                .foregroundColor(severityColor(severity))
                .frame(width: 44, height: 44)
                .background(severityColor(severity).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.headline)
                    .font(.appSystem(.headline, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                HStack(spacing: 8) {
                    Text(severity.label)
                        .font(.appSystem(.caption, design: .rounded).bold())
                        .foregroundColor(severityColor(severity))

                    if let deficit = plan.detection.deficitHours {
                        Text(String(format: String(localized: "睡眠债 %.1fh"), deficit))
                            .font(.appSystem(.caption, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }

                    if plan.detection.lateCaffeineMg > 50 {
                        Text("晚间咖啡因 \(plan.detection.lateCaffeineMg)mg")
                            .font(.appSystem(.caption, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - 恢复倒计时

    @ViewBuilder
    private func countdownSection(plan: LateNightRecoveryPlan) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("恢复倒计时")
                    .font(.appSystem(.caption, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(plan.recoveryCountdownDays)")
                        .font(.appSystem(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("天")
                        .font(.appSystem(.subheadline, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("今晚提前睡")
                    .font(.appSystem(.caption, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)

                Text("\(plan.targetBedtimeOffsetMinutes) 分钟")
                    .font(.appSystem(.subheadline, design: .rounded).bold())
                    .foregroundColor(Theme.Colors.mintGreen)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 熬夜原因

    @ViewBuilder
    private func reasonsSection(plan: LateNightRecoveryPlan) -> some View {
        if !plan.detection.reasons.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.detection.reasons, id: \.self) { reason in
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text(reason)
                            .font(.appSystem(.footnote, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - 行动项分组

    @ViewBuilder
    private func actionsSection(title: String, symbol: String, color: Color, actions: [RecoveryAction]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 15, weight: .medium))
                    .foregroundColor(color)
                Text(title)
                    .font(.appSystem(.subheadline, design: .rounded).bold())
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            ForEach(actions) { action in
                recoveryActionRow(action: action, color: color)
            }
        }
    }

    @ViewBuilder
    private func recoveryActionRow(action: RecoveryAction, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: action.symbol)
                .font(.appSystem(.footnote))
                .foregroundColor(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(action.title)
                        .font(.appSystem(.footnote, design: .rounded).bold())
                        .foregroundColor(Theme.Colors.textPrimary)

                    Spacer()

                    Text(action.timeWindow)
                        .font(.appSystem(.caption2, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Text(action.detail)
                    .font(.appSystem(.caption, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 鼓励文案

    @ViewBuilder
    private func encouragementSection(plan: LateNightRecoveryPlan) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.appSystem(.footnote))
                .foregroundColor(Theme.Colors.accentRed.opacity(0.7))

            Text(plan.encouragement)
                .font(.appSystem(.footnote, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 未熬夜状态

    @ViewBuilder
    private var noLateNightContent: some View {
        BBCard(style: .inset) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.appSystem(.title3))
                    .foregroundColor(Theme.Colors.mintGreen)

                Text("昨晚睡眠节律正常，继续保持。")
                    .font(.appSystem(.subheadline, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    // MARK: - 无睡眠数据状态

    @ViewBuilder
    private var noSleepDataContent: some View {
        BBCard(style: .inset) {
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz")
                    .font(.appSystem(.title3))
                    .foregroundColor(Theme.Colors.accentBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("暂无睡眠数据")
                        .font(.appSystem(.subheadline, design: .rounded).bold())
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("同步 Apple Health 中的睡眠记录后，系统会自动识别熬夜并生成恢复计划。")
                        .font(.appSystem(.caption, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 辅助

    private func severityColor(_ severity: LateNightSeverity) -> Color {
        switch severity {
        case .mild: return Theme.Colors.accentOrange
        case .moderate: return Theme.Colors.accentRed
        case .severe: return Theme.Colors.accentRed
        }
    }
}
