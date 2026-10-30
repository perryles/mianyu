/// ReproductiveRecentLogsCard 作为趋势模块的内容展示卡片，负责展示生理周期最近记录。
/// 负责按时间汇总血量、体感与情绪变化并展示空态引导。

import SwiftUI

// 生理周期详情专属组件集中放在这里维护，
// 让周期阅读和记录入口模块与趋势首页外壳解耦。

/// 生理周期RecentLogs卡片组件 作为趋势模块里的内容展示卡片。
/// 负责趋势分析展示。用于趋势页面的‘生理周期’。
struct ReproductiveRecentLogsCard: View {
    @Bindable var viewModel: PeriodViewModel
    private let accent = Color(hex: "C97C7A")
    private let inkTint = Color(hex: "14253D")
    private let borderTint = Color(hex: "E8E2DD")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.recentLogs.isEmpty {
                Text("最近还没有可回顾的记录。补充当天状态后，这里会按时间汇总出血量、体感与情绪变化。")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    summaryPill(title: "记录数", value: "\(viewModel.recentLogs.count)")
                    summaryPill(title: "最近状态", value: latestRecordLabel)
                }

                VStack(spacing: 8) {
                    ForEach(viewModel.recentLogs) { log in
                        recentLogRow(log)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(borderTint, lineWidth: 1)
        )
    }

    private var latestRecordLabel: String {
        guard let log = viewModel.recentLogs.first else { return "--" }
        return flowDisplayText(log.flowLevel)
    }

    private func flowDisplayText(_ value: Int?) -> String {
        guard let value else { return "--" }
        return value == 0 ? "无" : viewModel.flowText(for: value)
    }

    private func metricDisplayText(_ value: Int?) -> String {
        value.map(String.init) ?? "--"
    }

    private func recentLogRow(_ log: PeriodDayLog) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(log.date.map(viewModel.displayDay) ?? "未命名日期")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundColor(inkTint)

                Text(
                    [
                        "出血 \(flowDisplayText(log.flowLevel))",
                        "痛经 \(metricDisplayText(log.painLevel))",
                        "情绪 \(metricDisplayText(log.moodLevel))"
                    ].joined(separator: " / ")
                )
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)

                let tags = viewModel.eventTags(for: log)
                if !tags.isEmpty {
                    reproductiveEventTagWrap(tags)
                }

                if let note = viewModel.residualNote(for: log), !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderTint, lineWidth: 1)
        )
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(inkTint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderTint, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func reproductiveEventTagWrap(_ tags: [PeriodEventTag]) -> some View {
        FlexibleTagLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(tags) { tag in
                reproductiveEventTagChip(tag)
            }
        }
    }

    private func reproductiveEventTagChip(_ tag: PeriodEventTag) -> some View {
        let palette = reproductiveEventPalette(tag.style)
        return Text(tag.title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(palette.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.background, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(palette.border, lineWidth: 1)
            )
    }

    private func reproductiveEventPalette(_ style: PeriodEventTag.Style) -> (foreground: Color, background: Color, border: Color) {
        switch style {
        case .alert:
            return (accent, accent.opacity(0.10), accent.opacity(0.16))
        case .neutral:
            return (inkTint.opacity(0.84), inkTint.opacity(0.08), inkTint.opacity(0.12))
        case .positive:
            let tint = Color(hex: "2D8C63")
            return (tint, tint.opacity(0.10), tint.opacity(0.16))
        case .fertile:
            return (Color(hex: "7A8FAE"), Color(hex: "7A8FAE").opacity(0.10), Color(hex: "7A8FAE").opacity(0.16))
        }
    }
}

struct ReproductiveEventSummaryCard: View {
    @Bindable var viewModel: PeriodViewModel

    private let accent = Color(hex: "C97C7A")
    private let fertileTint = Color(hex: "7A8FAE")
    private let inkTint = Color(hex: "14253D")
    private let borderTint = Color(hex: "E8E2DD")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(PeriodViewModel.StructuredEventGroup.allCases) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)

                    VStack(spacing: 10) {
                        ForEach(viewModel.latestStructuredEventSummary(for: group)) { item in
                            eventRow(item)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(borderTint, lineWidth: 1)
        )
    }

    private func eventRow(_ item: PeriodViewModel.StructuredEventSummaryItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.tint.opacity(0.14))
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(item.tint.opacity(0.22), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                Text(item.value)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(inkTint)
                Text(item.dateText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke((item.tint == fertileTint ? fertileTint : accent).opacity(0.10), lineWidth: 1)
        )
    }
}

/// 生理周期ReadOnly条目卡片组件 作为趋势模块里的内容展示卡片。
/// 负责趋势分析展示。用于趋势页面的‘生理周期’。
struct ReproductiveReadOnlyEntryCard: View {
    let predictionHint: String?
    let latestLogDate: String?
    private let borderTint = Color(hex: "E8E2DD")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: "C97C7A").opacity(0.12))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(hex: "A6635C"))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("补充周期记录")
                        .font(.system(size: 16, weight: .heavy, design: .serif))
                        .foregroundColor(Color(hex: "14253D"))
                    Text(predictionHint ?? "进入记录页后，可以补当天状态、更新周期起止时间，或重新同步健康 App 的周期数据。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "A6635C"))
            }

            if let latestLogDate {
                Text("最近一次记录：\(latestLogDate)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "A6635C"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(hex: "C97C7A").opacity(0.08), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(borderTint, lineWidth: 1)
        )
    }

}

/// 生理周期解读摘要卡片组件 作为趋势模块里的内容展示卡片。
/// 负责趋势分析展示。用于趋势页面的‘生理周期’。
struct ReproductiveInsightSummaryCard: View {
    let detail: ReproductiveTrendDetailModel
    private let accent = Color(hex: "C97C7A")
    private let secondary = Color(hex: "7A8FAE")
    private let inkTint = Color(hex: "14253D")
    private let borderTint = Color(hex: "E8E2DD")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                dashboardTrendIcon(
                    primary: "calendar.badge.clock",
                    badge: "waveform.path.ecg",
                    accent: accent,
                    secondary: secondary,
                    size: 42
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("当前结论")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(detail.cycleStatusText)
                        .font(.system(size: 20, weight: .black, design: .serif))
                        .foregroundColor(inkTint)
                    Text(detail.cycleStatusDetail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                reproductiveSummaryPill(title: "最近记录", value: detail.latestLogSummary)
                reproductiveSummaryPill(title: "当前关注", value: detail.latestLogDetail)
            }
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(borderTint, lineWidth: 1)
        )
    }

    private func reproductiveSummaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(inkTint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderTint, lineWidth: 1)
        )
    }
}

/// 生理周期解读卡片组件 作为趋势模块里的内容展示卡片。
/// 负责趋势分析展示。
struct ReproductiveInsightCard: View {
    let item: ReproductiveInsightItem
    private let borderTint = Color(hex: "E8E2DD")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(Color(hex: "14253D"))
            Text(item.detail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(borderTint, lineWidth: 1)
        )
    }
}
