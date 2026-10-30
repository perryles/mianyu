/// SleepEnvironmentChecklistCard 由睡眠页调用，作为「睡前环境清单」紧凑卡片。
/// 负责展示 5 项睡前环境检查并支持直接勾选。

import SwiftUI

/// 紧凑版卧室环境清单卡片：在睡眠页展示 5 项睡前环境检查，支持直接勾选。
struct SleepEnvironmentChecklistCard: View {
    @Bindable var viewModel: SleepViewModel
    var environmentInsight: SleepEnvironmentSnoreInsight?

    var body: some View {
        let summary = viewModel.sleepEnvironmentManagementSummary
        let tint = SleepEnvironmentChecklistCard.tint(for: summary?.tone)

        BBCard(style: .standard) {
            VStack(alignment: .leading, spacing: 12) {
                // 头部
                HStack(spacing: 10) {
                    Image(systemName: "bed.double.fill")
                        .font(.appSystem(size: 15, weight: .medium))
                        .foregroundColor(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("今晚卧室检查")
                            .font(.appSystem(.headline, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)

                        if let summary {
                            Text("\(summary.completedCount)/\(summary.checklistItems.count) 已完成")
                                .font(.appSystem(.caption, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }

                    Spacer()

                    if let score = summary?.score {
                        Text("\(score)")
                            .font(.appSystem(.title3, design: .rounded).bold())
                            .foregroundColor(tint)
                    }
                }

                // 清单
                if let summary {
                    ForEach(summary.checklistItems) { item in
                        checklistRow(
                            item: item,
                            isCompleted: summary.completedItemIDs.contains(item.id),
                            tint: tint
                        )
                    }
                } else {
                    ForEach(SleepBedroomChecklistItem.defaults) { item in
                        checklistRow(
                            item: item,
                            isCompleted: false,
                            tint: tint
                        )
                    }
                }

                // 建议文案
                if let suggestion = summary?.suggestionText {
                    Divider()
                        .background(Theme.Colors.lightGray)

                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.appSystem(.caption))
                            .foregroundColor(tint.opacity(0.7))
                        Text(suggestion)
                            .font(.appSystem(.caption, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - 清单行

    @ViewBuilder
    private func checklistRow(item: SleepBedroomChecklistItem, isCompleted: Bool, tint: Color) -> some View {
        Button {
            viewModel.toggleSleepEnvironmentChecklistItem(
                item.id,
                completed: !isCompleted,
                environmentInsight: environmentInsight
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : item.symbol)
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundColor(isCompleted ? Theme.Colors.mintGreen : tint)
                    .frame(width: 28, height: 28)
                    .background((isCompleted ? Theme.Colors.mintGreen : tint).opacity(0.10))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.appSystem(.footnote, design: .rounded).bold())
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(item.detail)
                        .font(.appSystem(.caption2, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 辅助

    static func tint(for tone: SleepEnvironmentManagementTone?) -> Color {
        switch tone {
        case .building:
            return Theme.Colors.textTertiary
        case .steady:
            return Theme.Colors.mintGreen
        case .watch:
            return Theme.Colors.accentOrange
        case .elevated:
            return Theme.Colors.accentRed
        case nil:
            return Theme.Colors.accentBlue
        }
    }
}
