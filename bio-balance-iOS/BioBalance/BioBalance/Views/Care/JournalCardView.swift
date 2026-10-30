/// JournalCardView 是症状日记与服药打卡强制复用的统一日志卡片组件。
///
/// 设计要求（来自需求文档）：
/// - 症状日记与服药打卡在数据模型与 UI 组件上强制复用，不得重复实现
/// - UI 层统一为"日志卡片"视图
/// - 与现有 DesignSystem (BBCard / Theme) 风格一致

import SwiftUI

struct JournalCardView: View {
    let item: JournalTimelineItem
    var onTap: (() -> Void)? = nil
    var onQuickComplete: ((JournalTimelineItem) -> Void)? = nil

    private var categoryColor: Color {
        switch item.category {
        case .medication: return .orange
        case .rehabilitation: return .blue
        case .habit: return .green
        case .symptom: return .purple
        }
    }

    var body: some View {
        BBCard(style: .standard, tint: categoryColor) {
            VStack(alignment: .leading, spacing: 10) {
                headerRow

                switch item {
                case .careTaskEvent(let event):
                    taskEventContent(event)
                case .careOutcome(let outcome):
                    outcomeContent(outcome)
                case .symptomRecord(let record):
                    symptomContent(record)
                case .medicationEntry(let entry):
                    medicationContent(entry)
                }
            }
        }
        .onTapGesture {
            onTap?()
        }
    }

    // MARK: - 标题区

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 8) {
            categoryBadge

            Text(formattedTimestamp)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            Spacer(minLength: 0)

            if let quickAction = quickActionLabel {
                quickActionButton(quickAction)
            }
        }
    }

    private var categoryBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: item.category.symbol)
                .font(.appSystem(size: 10, weight: .bold))
            Text(item.category.shortTitle)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(categoryColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(categoryColor.opacity(0.12))
        )
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: item.timestamp)
    }

    @ViewBuilder
    private func quickActionButton(_ label: String) -> some View {
        Button {
            onQuickComplete?(item)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.appSystem(size: 13, weight: .semibold))
                Text(label)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(categoryColor)
            )
        }
        .buttonStyle(.plain)
    }

    private var quickActionLabel: String? {
        switch item {
        case .careTaskEvent(let event):
            return event.status == .scheduled ? String(localized: "打卡") : nil
        default:
            return nil
        }
    }

    // MARK: - 内容变体

    @ViewBuilder
    private func taskEventContent(_ event: CareTaskEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: event.icon)
                .font(.appSystem(size: 22))
                .foregroundColor(categoryColor)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(categoryColor.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                if let target = event.targetValue, let unit = event.unit {
                    Text(String(localized: "目标 \(formattedNumber(target)) \(unit)"))
                        .font(.appSystem(size: 12, weight: .medium))
                        .foregroundColor(Theme.Colors.textSecondary)
                } else if let instructions = event.instructions {
                    Text(instructions)
                        .font(.appSystem(size: 12, weight: .medium))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            statusBadge(event.status)
        }
    }

    @ViewBuilder
    private func outcomeContent(_ outcome: CareOutcome) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !outcome.values.isEmpty {
                FlexibleTagLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(outcome.values, id: \.self) { value in
                        outcomeValueTag(value)
                    }
                }
            }

            if let note = outcome.note, !note.isEmpty {
                Text(note)
                    .font(.appSystem(size: 13, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func outcomeValueTag(_ value: CareOutcome.Value) -> some View {
        let displayText = outcomeValueText(value)
        HStack(spacing: 3) {
            if let label = value.label {
                Text(label)
                    .font(.appSystem(size: 11, weight: .medium))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            Text(displayText)
                .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(categoryColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(categoryColor.opacity(0.08))
        )
    }

    private func outcomeValueText(_ value: CareOutcome.Value) -> String {
        switch value.kind {
        case .numeric:
            if let num = value.numericValue {
                return formattedNumber(num)
            }
            return ""
        case .text, .reaction, .symptom:
            return value.textValue ?? ""
        case .rating:
            if let rating = value.ratingValue {
                return String(repeating: "★", count: max(0, min(5, rating)))
            }
            return ""
        }
    }

    @ViewBuilder
    private func symptomContent(_ record: SelfObservationRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !record.selectedSymptoms.isEmpty {
                FlexibleTagLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(record.selectedSymptoms, id: \.self) { symptom in
                        HStack(spacing: 3) {
                            Image(systemName: symptom.systemImage)
                                .font(.appSystem(size: 10))
                            Text(symptom.title)
                                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(categoryColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(categoryColor.opacity(0.08)))
                    }
                }
            }

            HStack(spacing: 12) {
                if record.symptomSeverity > 0 {
                    severityIndicator(record.symptomSeverity)
                }
                if record.energy > 0 && record.energy <= 5 {
                    ratingRow(String(localized: "精力"), rating: record.energy)
                }
            }

            if !record.note.isEmpty {
                Text(record.note)
                    .font(.appSystem(size: 13, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func medicationContent(_ entry: MedicationEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.category.symbol)
                .font(.appSystem(size: 20))
                .foregroundColor(categoryColor)
                .frame(width: 36, height: 36)
                .background(Circle().fill(categoryColor.opacity(0.1)))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("\(formattedNumber(entry.amount)) \(entry.unit)")
                    .font(.appSystem(size: 12, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)

            if let reaction = entry.reactionState {
                reactionBadge(reaction)
            }
        }
    }

    // MARK: - 子组件

    @ViewBuilder
    private func statusBadge(_ status: CareTaskEventStatus) -> some View {
        let color: Color = switch status {
        case .completed: .green
        case .scheduled: categoryColor.opacity(0.6)
        case .overdue: .red
        case .skipped: .gray
        }

        HStack(spacing: 3) {
            Image(systemName: status.symbol)
                .font(.appSystem(size: 11, weight: .bold))
            Text(status.title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.1)))
    }

    @ViewBuilder
    private func severityIndicator(_ severity: Int) -> some View {
        let bars = min(5, max(0, severity))
        HStack(spacing: 2) {
            Text(String(localized: "强度"))
                .font(.appSystem(size: 11, weight: .medium))
                .foregroundColor(Theme.Colors.textTertiary)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(index < bars ? categoryColor : Color.gray.opacity(0.2))
                        .frame(width: 8, height: 8)
                }
            }
        }
    }

    @ViewBuilder
    private func ratingRow(_ label: String, rating: Int) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.appSystem(size: 11, weight: .medium))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(String(repeating: "★", count: max(0, min(5, rating))))
                .font(.appSystem(size: 11, weight: .semibold))
                .foregroundColor(categoryColor)
        }
    }

    @ViewBuilder
    private func reactionBadge(_ reaction: MedicationReactionState) -> some View {
        let color: Color = switch reaction {
        case .improved: .green
        case .neutral: .gray
        case .uncomfortable: .red
        }

        HStack(spacing: 3) {
            Image(systemName: reaction.symbol)
                .font(.appSystem(size: 11, weight: .bold))
            Text(reaction.shortTitle)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.1)))
    }

    private func formattedNumber(_ value: Double) -> String {
        if floor(value) == value { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }
}

// MARK: - 预览

#if DEBUG
#Preview("Journal Card") {
    ScrollView {
        VStack(spacing: 12) {
            JournalCardView(
                item: .careTaskEvent(
                    CareTaskEvent(
                        id: "demo1",
                        taskID: "task1",
                        logicalTaskID: "logical1",
                        taskRevision: 1,
                        category: .rehabilitation,
                        title: "颈椎康复训练",
                        icon: "figure.cooldown",
                        slotIndex: 0,
                        scheduledAt: Date(),
                        durationMinutes: 15,
                        targetValue: 15,
                        unit: String(localized: "分钟"),
                        instructions: nil,
                        linkedModule: nil,
                        status: .scheduled,
                        outcome: nil
                    )
                )
            )

            JournalCardView(
                item: .medicationEntry(
                    MedicationEntry(
                        id: "demo2",
                        category: .medication,
                        name: "维生素 D",
                        amount: 1,
                        unit: String(localized: "粒"),
                        reactionState: .improved,
                        takenAt: Date()
                    )
                )
            )
        }
        .padding()
    }
}
#endif
