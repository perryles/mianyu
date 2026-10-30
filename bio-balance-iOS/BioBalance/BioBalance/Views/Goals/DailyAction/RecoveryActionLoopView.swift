import SwiftUI

struct RecoveryActionLoopEntryLink: View {
    @State private var review = RecoveryActionLoopEngine.make(records: [])
    private let store = DailyRecoveryOrchestrationStore.shared

    var body: some View {
        NavigationLink {
            RecoveryActionLoopView()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "checkmark.arrow.trianglehead.counterclockwise")
                    .font(.appSystem(size: 18, weight: .black))
                    .foregroundColor(Theme.Colors.mintGreen)
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.mintGreen.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("恢复行动闭环")
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(entrySubtitle)
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .black))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(16)
            .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .dailyRecoveryActionStateDidChange)) { _ in reload() }
    }

    private var entrySubtitle: String {
        guard let rate = review.completionRate else {
            return String(localized: "回看最近 7 天的完成事实与主观体感")
        }
        return String(localized: "最近 7 天完成率 \(Int((rate * 100).rounded()))% · \(review.feedbackCount) 项有体感")
    }

    private func reload() {
        review = RecoveryActionLoopEngine.make(records: store.allActionStateRecords())
    }
}

struct RecoveryActionLoopView: View {
    @State private var review = RecoveryActionLoopEngine.make(records: [])
    @State private var records: [DailyRecoveryActionStateRecord] = []
    private let store = DailyRecoveryOrchestrationStore.shared

    var body: some View {
        ZStack {
            HealthDetailPageBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    feedbackCard
                    recentRecordsCard
                    safetyCard
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
        }
        .healthDetailNavigation(title: "恢复行动闭环")
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .dailyRecoveryActionStateDidChange)) { _ in reload() }
    }

    private var summaryCard: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("最近 7 天", subtitle: review.headline)
            Text(review.detail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                metric("计划", "\(review.plannedCount)", Color(hex: "4C7DFF"))
                metric("完成", "\(review.completedCount)", Theme.Colors.mintGreen)
                metric("已处理", "\(review.processedCount)", Color(hex: "8B6F9E"))
            }
        }
    }

    private var feedbackCard: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("完成后体感", subtitle: "体感是可选的个人记录，不代表行动疗效。")
            HStack(spacing: 8) {
                feedbackMetric(.better, count: review.betterCount, tint: Theme.Colors.mintGreen)
                feedbackMetric(.similar, count: review.similarCount, tint: Color(hex: "4C7DFF"))
                feedbackMetric(.harder, count: review.harderCount, tint: Color(hex: "F3A53B"))
            }
        }
    }

    private var recentRecordsCard: some View {
        ReportsContentCard(spacing: 12) {
            ReportsSectionHeader("最近行动", subtitle: "按计划日期展示，最多 12 条。")
            if records.isEmpty {
                ReportsInlineEmptyState(text: "暂无恢复行动记录")
            } else {
                ForEach(Array(records.prefix(12).enumerated()), id: \.element.actionID) { index, record in
                    if index > 0 { Divider().overlay(Color.black.opacity(0.05)) }
                    HStack(spacing: 10) {
                        Image(systemName: stateSymbol(record.state))
                            .foregroundColor(stateTint(record.state))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.actionTitle ?? String(localized: "恢复行动"))
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text((record.plannedFor ?? record.updatedAt).reportsShortDateString())
                                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        Spacer()
                        Text(stateTitle(record.state))
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(stateTint(record.state))
                        if let feedback = record.feedback {
                            Image(systemName: feedback.systemImage)
                                .foregroundColor(Theme.Colors.mintGreen)
                                .accessibilityLabel(feedback.title)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var safetyCard: some View {
        Label(
            "完成与体感只用于个人回看。跳过、不适用或感觉更吃力都不会降低健康评分，也不代表健康状态变差。",
            systemImage: "shield.checkered"
        )
        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
        .foregroundColor(Theme.Colors.textSecondary)
        .padding(14)
        .background(Theme.Colors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metric(_ title: String, _ value: String, _ tint: Color) -> some View {
        ReportsCompactMetricPill(title: title, value: value, tint: tint)
    }

    private func feedbackMetric(_ feedback: DailyRecoveryActionFeedback, count: Int, tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: feedback.systemImage)
            Text(feedback.title)
                .font(.appSystem(size: 9, weight: .bold, design: .rounded))
            Text("\(count)")
                .font(.appSystem(size: 18, weight: .black, design: .rounded))
        }
        .foregroundColor(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stateTitle(_ state: DailyRecoveryActionState) -> String {
        switch state {
        case .pending: return String(localized: "待处理")
        case .completed: return String(localized: "已完成")
        case .snoozed: return String(localized: "稍后")
        case .skipped: return String(localized: "已跳过")
        case .notApplicable: return String(localized: "不适用")
        }
    }

    private func stateSymbol(_ state: DailyRecoveryActionState) -> String {
        switch state {
        case .pending: return "circle"
        case .completed: return "checkmark.circle.fill"
        case .snoozed: return "clock.fill"
        case .skipped: return "forward.end.fill"
        case .notApplicable: return "nosign"
        }
    }

    private func stateTint(_ state: DailyRecoveryActionState) -> Color {
        switch state {
        case .pending: return Color(hex: "8AA0B8")
        case .completed: return Theme.Colors.mintGreen
        case .snoozed: return Color(hex: "4C7DFF")
        case .skipped: return Color(hex: "7C879B")
        case .notApplicable: return Color(hex: "8B6F9E")
        }
    }

    private func reload() {
        records = store.allActionStateRecords()
        review = RecoveryActionLoopEngine.make(records: records)
    }
}
