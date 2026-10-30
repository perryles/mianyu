/// ReportBehaviorTimelineReplayCard 作为报告模块的内容展示卡片，负责组织时间线回放。
/// 负责展示回放的加载态、空态、负荷轨迹图与节点列表。

import SwiftUI
import Charts

// 行为回放卡依赖时间线领域模型，并包含负荷轨迹、行为分布和节点列表三种呈现。

// MARK: - 回放卡片

/// 组织时间线的加载态、空态、图表与节点详情。
struct ReportBehaviorTimelineReplayCard: View {
    let replay: BehaviorTimelineReplay?
    let isLoading: Bool

    var body: some View {
        ReportsContentCard {
            ReportsSectionHeader("生活行为时间线回放", subtitle: "回看这一天是怎么一步步把状态推成现在这样的。")

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.Colors.mintGreen)
                    Text("正在整理当天的行为与状态时间线…")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.vertical, 8)
            } else if let replay, !replay.displayNodes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(replay.headline)
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(ReportsEditorialStyle.ink)
                    Text(replay.summary)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(ReportsEditorialStyle.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    BehaviorTimelineReplayChart(replay: replay)

                    BehaviorTimelineKindDistributionChart(replay: replay)

                    VStack(spacing: 0) {
                        ForEach(Array(replay.displayNodes.enumerated()), id: \.element.id) { index, node in
                            timelineNodeRow(node: node, isLast: index == replay.displayNodes.count - 1)
                        }
                    }

                    if !replay.coverageFlags.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("数据覆盖提示")
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                            ForEach(replay.coverageFlags, id: \.self) { item in
                                Text("• \(item)")
                                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.Colors.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            } else {
                ReportsInlineEmptyState(text: "暂时无法形成完整回放，请继续补充咖啡因、情绪、睡眠或压力样本。")
            }
        }
    }

    @ViewBuilder
    private func timelineNodeRow(node: BehaviorTimelineReplay.DisplayNode, isLast: Bool) -> some View {
        // 最后一个节点不继续绘制连接线，以保持时间线的明确终点。
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(toneColor(node.tone).opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: node.symbolName)
                        .font(.appSystem(size: 12, weight: .bold))
                        .foregroundColor(toneColor(node.tone))
                }

                if !isLast {
                    Capsule()
                        .fill(toneColor(node.tone).opacity(0.18))
                        .frame(width: 2, height: 40)
                        .padding(.top, 4)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(timeText(node.timestamp))
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)

                Text(node.title)
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(node.detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(ReportsEditorialStyle.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func toneColor(_ tone: BehaviorTimelineTone) -> Color {
        switch tone {
        case .calm:
            return Theme.Colors.mintGreen
        case .neutral:
            return Color(hex: "5B8CFF")
        case .caution:
            return Color(hex: "F3A53B")
        case .alert:
            return Color(hex: "F46B5A")
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 负荷轨迹

/// 将定性的行为色调映射为统一的 0-100 负荷轨迹。
private struct BehaviorTimelineReplayChart: View {
    let replay: BehaviorTimelineReplay

    private var chartPoints: [BehaviorTimelineReplayChartPoint] {
        replay.displayNodes.map { node in
            BehaviorTimelineReplayChartPoint(
                id: node.id,
                timestamp: node.timestamp,
                load: loadValue(for: node.tone),
                label: node.title,
                tone: node.tone
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("负荷轨迹")
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(ReportsEditorialStyle.ink)
                Spacer()
                Text("按行为节点估算")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Chart(chartPoints) { point in
                AreaMark(
                    x: .value("时间", point.timestamp),
                    y: .value("负荷", point.load)
                )
                .reportsScoreArea()

                LineMark(
                    x: .value("时间", point.timestamp),
                    y: .value("负荷", point.load)
                )
                .reportsScoreLine()

                PointMark(
                    x: .value("时间", point.timestamp),
                    y: .value("负荷", point.load)
                )
                .foregroundStyle(toneColor(point.tone))
                .symbolSize(48)
            }
            .frame(height: 142)
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                    AxisValueLabel(format: .dateTime.hour())
                        .foregroundStyle(ReportsChartStyle.axisLabel)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [25, 50, 75, 100]) { _ in
                    AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                    AxisValueLabel()
                        .foregroundStyle(ReportsChartStyle.axisLabel)
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(ReportsChartStyle.plotBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(13)
        .background(ReportsEditorialStyle.neutralPanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ReportsEditorialStyle.border, lineWidth: 1)
        )
    }

    private func loadValue(for tone: BehaviorTimelineTone) -> Double {
        // 固定档位只用于视觉回放，不表示医学测量值。
        switch tone {
        case .calm:
            return 24
        case .neutral:
            return 48
        case .caution:
            return 72
        case .alert:
            return 92
        }
    }

    private func toneColor(_ tone: BehaviorTimelineTone) -> Color {
        switch tone {
        case .calm:
            return Theme.Colors.mintGreen
        case .neutral:
            return ReportsEditorialStyle.lavenderAccent
        case .caution:
            return Color(hex: "F3A53B")
        case .alert:
            return Color(hex: "F46B5A")
        }
    }
}

// MARK: - 事件分布

/// 按行为类型聚合当日节点，用条形图表达构成比重。
private struct BehaviorTimelineKindDistributionChart: View {
    let replay: BehaviorTimelineReplay

    private var counts: [BehaviorTimelineKindCount] {
        var grouped: [String: Int] = [:]
        for node in replay.displayNodes {
            grouped[kindTitle(for: node)] = (grouped[kindTitle(for: node)] ?? 0) + 1
        }
        return grouped
            .map { BehaviorTimelineKindCount(title: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.title < $1.title
                }
                return $0.count > $1.count
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("行为分布")
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(ReportsEditorialStyle.ink)
                Spacer()
                Text("\(replay.events.count) 个行为节点")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Chart(counts) { item in
                BarMark(
                    x: .value("次数", item.count),
                    y: .value("类型", item.title)
                )
                .foregroundStyle(behaviorTint(for: item.title))
                .cornerRadius(5)
            }
            .frame(height: CGFloat(max(86, counts.count * 28)))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                    AxisValueLabel()
                        .foregroundStyle(ReportsChartStyle.axisLabel)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(ReportsChartStyle.axisLabel)
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(ReportsChartStyle.plotBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(13)
        .background(ReportsEditorialStyle.neutralPanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ReportsEditorialStyle.border, lineWidth: 1)
        )
    }

    private func kindTitle(for node: BehaviorTimelineReplay.DisplayNode) -> String {
        switch node.kind {
        case .event(let kind):
            return kind.title
        case .explanation:
            return String(localized: "解释")
        }
    }

    private func behaviorTint(for title: String) -> Color {
        switch title {
        case BehaviorTimelineEventKind.caffeine.title: return Color(hex: "E5922D")
        case BehaviorTimelineEventKind.hydration.title: return Color(hex: "3988E6")
        case BehaviorTimelineEventKind.daylight.title: return Color(hex: "D39A00")
        case BehaviorTimelineEventKind.mood.title: return Color(hex: "8A62C7")
        case BehaviorTimelineEventKind.sleep.title: return ReportMetricKind.sleep.tint
        case BehaviorTimelineEventKind.stress.title: return ReportMetricKind.stress.tint
        default: return ReportsChartStyle.score
        }
    }
}

/// 负荷轨迹的文件内绘图模型，不向报告其他子系统暴露。
private struct BehaviorTimelineReplayChartPoint: Identifiable {
    let id: String
    let timestamp: Date
    let load: Double
    let label: String
    let tone: BehaviorTimelineTone
}

/// 行为分布图的文件内聚合结果。
private struct BehaviorTimelineKindCount: Identifiable {
    let title: String
    let count: Int

    var id: String { title }
}
