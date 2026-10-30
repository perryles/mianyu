/// CareTaskCardView 是照护任务事件的卡片视图。
/// 用于在 CareHubView 今日列表中展示单个任务。
///
/// 与 JournalCardView 的区别：
/// - JournalCardView：统一日志卡片，侧重记录回看（已完成项）
/// - CareTaskCardView：任务卡片，强调当前待完成状态和快速打卡交互

import SwiftUI

struct CareTaskCardView: View {
    let event: CareTaskEvent
    var onTap: (() -> Void)? = nil
    var onQuickComplete: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil

    private var categoryColor: Color {
        switch event.category {
        case .medication: return .orange
        case .rehabilitation: return .blue
        case .habit: return .green
        case .symptom: return .purple
        }
    }

    var body: some View {
        BBCard(style: .standard, tint: statusColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    iconView

                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title)
                            .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(2)

                        detailRow
                    }

                    Spacer(minLength: 0)

                    statusBadge
                }

                if event.status == .scheduled || event.status == .overdue {
                    actionRow
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    // MARK: - 子视图

    private var statusColor: Color {
        switch event.status {
        case .completed: return .green
        case .scheduled: return categoryColor.opacity(0.5)
        case .overdue: return .red
        case .skipped: return .gray
        }
    }

    @ViewBuilder
    private var iconView: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.12))
                .frame(width: 40, height: 40)

            Image(systemName: event.status == .completed ? "checkmark" : event.icon)
                .font(.appSystem(size: 16, weight: .semibold))
                .foregroundColor(statusColor)
        }
    }

    @ViewBuilder
    private var detailRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let target = event.targetValue, let unit = event.unit {
                Text("\(formattedTime) · \(String(localized: "目标")) \(formattedNumber(target)) \(unit)")
                    .font(.appSystem(size: 12, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
            } else if event.durationMinutes > 0 {
                Text("\(formattedTime) · \(event.durationMinutes)\(String(localized: "分钟"))")
                    .font(.appSystem(size: 12, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
            } else {
                Text(formattedTime)
                    .font(.appSystem(size: 12, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            if let instructions = event.instructions {
                Text(instructions)
                    .font(.appSystem(size: 11, weight: .medium))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: event.status.symbol)
                .font(.appSystem(size: 11, weight: .bold))
            Text(event.status.title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(statusColor.opacity(0.1)))
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 8) {
            if event.status == .scheduled || event.status == .overdue {
                quickCompleteButton
                if event.category != .medication {
                    skipButton
                }
            }
        }
    }

    @ViewBuilder
    private var quickCompleteButton: some View {
        Button {
            onQuickComplete?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.appSystem(size: 14, weight: .semibold))
                Text(event.category == .medication ? String(localized: "记录用药") : String(localized: "完成打卡"))
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(categoryColor))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var skipButton: some View {
        Button {
            onSkip?()
        } label: {
            Text(String(localized: "跳过"))
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: event.scheduledAt)
    }

    private func formattedNumber(_ value: Double) -> String {
        if floor(value) == value { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }
}

// MARK: - 快速完成辅助

extension CareTaskEngine {
    /// 快速完成某任务事件（通用打卡）
    func quickComplete(event: CareTaskEvent) {
        let outcome = CareOutcome(
            logicalTaskID: event.logicalTaskID,
            taskID: event.taskID,
            taskRevision: event.taskRevision,
            category: event.category,
            completedAt: Date(),
            scheduledDate: Calendar.current.startOfDay(for: event.scheduledAt),
            values: event.targetValue.map { target in
                [.init(kind: .numeric, label: event.unit ?? "", numericValue: target)]
            } ?? [],
            note: nil
        )
        recordOutcome(outcome)

        // 回写到对应模块的 Store（MedicationStore / ActionRecordStore），保证数据一致
        CareWritebackManager.shared.performWriteback(for: event)
    }
}
