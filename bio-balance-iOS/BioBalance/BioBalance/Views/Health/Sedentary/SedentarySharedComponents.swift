/// SedentaryVisualPalette 作为久坐模块的共享配色定义，负责统一久坐强度的视觉语义。
/// 负责为不同久坐强度（轻度/中度/重度/睡眠）提供一致的填充色、描边色和文本色。

import SwiftUI

/// 久坐共享配色枚举 由 [SedentaryView]、[SedentaryHistoryView] 等久坐子视图复用，作为模块内共享配色定义入口。
/// 负责统一不同久坐强度对应的填充色、描边色和文本色，保证模块内视觉语义一致。
enum SedentaryVisualPalette {
    static func fill(for kind: SedentaryTimelineKind) -> Color {
        switch kind {
        case .light:
            return Color(hex: "DFF9EE")
        case .moderate:
            return Color(hex: "FFF7D9")
        case .heavy:
            return Color(hex: "FFF0E8")
        case .sleep:
            return Color(hex: "EEF1FF")
        }
    }

    static func stroke(for kind: SedentaryTimelineKind) -> Color {
        switch kind {
        case .light:
            return Color(hex: "7CD9A6")
        case .moderate:
            return Color(hex: "F4C430")
        case .heavy:
            return Color(hex: "FF946E")
        case .sleep:
            return Color(hex: "8FA0FF")
        }
    }

    static func text(for kind: SedentaryTimelineKind) -> Color {
        switch kind {
        case .light:
            return Color(hex: "31A66A")
        case .moderate:
            return Color(hex: "C98D16")
        case .heavy:
            return Color(hex: "E06B45")
        case .sleep:
            return Color(hex: "586CDE")
        }
    }
}

/// 单日久坐摘要条组件 由 [SedentaryHistoryView] 调用，作为单日久坐记录的横向摘要条入口。
/// 负责压缩展示当天首末时间、时段分布，以及打断发生位置等时间轴概览信息。
struct SedentarySummaryStripView: View {
    let summary: SedentaryDaySummary

    private var leadingTimeText: String {
        let date = summary.sessions.first?.start ?? summary.date
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var trailingTimeText: String {
        let date = summary.sessions.last?.end ?? summary.updatedAt
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(leadingTimeText)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer(minLength: 0)
                Text(trailingTimeText)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            HStack(spacing: 4) {
                if summary.sourceStatus == .ready, !summary.sessions.isEmpty {
                    ForEach(summary.sessions) { session in
                        Capsule()
                            .fill(SedentaryVisualPalette.stroke(for: session.kind))
                            .frame(maxWidth: .infinity)
                            .frame(height: 12)
                            .overlay(alignment: .trailing) {
                                if session.endingBreakKind != nil {
                                    Circle()
                                        .fill(Color(hex: "7AE6BC"))
                                        .frame(width: 10, height: 10)
                                        .padding(.trailing, -2)
                                }
                            }
                    }
                } else {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(0.72))
                            .frame(maxWidth: .infinity)
                            .frame(height: 12)
                    }
                }
            }
        }
    }
}

/// 重点久坐时段卡片 由 [SedentaryView] 调用，作为“近期动态”区域里的重点内容卡片。
/// 负责展示当前最值得关注的久坐时段、持续时长、时间范围，以及对应打断状态。

/// 久坐建议卡片 由 [SedentaryView] 调用，作为“建议与提醒”区域的内容承载组件。
/// 负责承接历史摘要与分条行动建议，帮助用户快速理解当天该如何调整久坐节律。




/// 坐时摘要卡片 由 [SedentaryView] 调用，作为“坐时摘要”区域的统计拆解组件。
/// 负责展示累计久坐时长、强度分布、主要状态和最长单次等核心汇总指标。

/// 久坐时段洞察条目 由 [SedentaryRhythmInsightCard] 调用，作为久坐热区分布的展示模型。
/// 负责承接某个时段的累计分钟、次数与高亮状态，便于渲染统一的可视化行。
struct SedentaryRhythmInsightItem: Identifiable {
    let title: String
    let minutes: Int
    let sessionCount: Int
    let tint: Color
    let isHighlighted: Bool

    var id: String { title }
}

/// 久坐热区卡片 由 [SedentaryView] 调用，作为“容易堆长坐的时段”模块的主卡片。
/// 负责展示最近更容易堆成长坐的时间段，以及全天各时段的久坐分布。
struct SedentaryRhythmInsightCard: View {
    let headline: String
    let detail: String
    let items: [SedentaryRhythmInsightItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(items) { item in
                    rhythmRow(item: item)
                }
            }
        }
    }

    private func rhythmRow(item: SedentaryRhythmInsightItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    if item.isHighlighted {
                        Text("重点")
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(item.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .bbTintedChip(tint: item.tint, in: Capsule())
                    }
                }

                Text("累计 \(item.minutes.bbFormattedDurationCompact) · \(item.sessionCount) 次")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Text(item.minutes > 0 ? item.minutes.bbFormattedDurationCompact : "暂无")
                    .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(item.minutes > 0 ? item.tint : Theme.Colors.textTertiary)
                Capsule()
                    .fill(item.minutes > 0 ? item.tint : Color(hex: "E6EDF5"))
                    .frame(width: item.isHighlighted ? 52 : 34, height: 8)
            }
        }
        .padding(12)
        .bbTintedChip(
            tint: item.isHighlighted ? item.tint : Color(hex: "DCE7F3"),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

/// 久坐打断洞察条目 由 [SedentaryBreakPatternCard] 调用，作为打断方式分布的展示模型。
/// 负责描述某一种打断方式的次数、辅助说明和视觉信息。
struct SedentaryBreakPatternItem: Identifiable {
    let title: String
    let valueText: String
    let detailText: String
    let symbol: String
    let tint: Color

    var id: String { "\(title)-\(symbol)" }
}

/// 久坐打断方式卡片 由 [SedentaryView] 调用，作为“你通常怎么打断”模块的主卡片。
/// 负责汇总最近常见的打断方式、平均活动时长，以及对后续打断习惯的提示。
struct SedentaryBreakPatternCard: View {
    let headline: String
    let detail: String
    let items: [SedentaryBreakPatternItem]
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.appSystem(size: 14, weight: .bold))
                            .foregroundColor(item.tint)
                            .frame(width: 30, height: 30)
                            .bbTintedChip(tint: item.tint, in: Circle())

                        Text(item.title)
                            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text(item.valueText)
                            .font(.appSystem(size: 14, weight: .heavy, design: .rounded))
                            .foregroundColor(item.tint)

                        Text(item.detailText)
                            .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .bbTintedChip(tint: item.tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            Text(footnote)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 久坐日志时间轴图表 由 [SedentaryView] 和 [SedentaryHistoryView] 调用，作为单日久坐日志的主图表组件。
/// 负责按时间顺序排布单日久坐时段，并以纵向小时轴呈现每段记录的持续时长与打断结果。
struct SedentaryTimelineChartView: View {
    let summary: SedentaryDaySummary

    private let timeColumnWidth: CGFloat = 52
    private let axisWidth: CGFloat = 18
    private let eventTopPadding: CGFloat = 8
    private let hourHeight: CGFloat = 66
    private let eventColumnSpacing: CGFloat = 8
    private let minimumEventWidth: CGFloat = 156

    var body: some View {
        let timelineBounds = hourBounds
        let eventLayouts = eventLayouts(for: summary.sessions, lowerHour: timelineBounds.lowerBound)
        let columnCount = max(1, (eventLayouts.map(\.column).max() ?? 0) + 1)
        let chartHeight = chartHeight(eventLayouts: eventLayouts, timelineBounds: timelineBounds)

        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                let baseX = timeColumnWidth + axisWidth + 12
                let availableWidth = max(180, proxy.size.width - baseX)
                let eventWidth = max(
                    minimumEventWidth,
                    (availableWidth - CGFloat(columnCount - 1) * eventColumnSpacing) / CGFloat(columnCount)
                )

                ZStack(alignment: .topLeading) {
                    ForEach(Array(timelineBounds.lowerBound...timelineBounds.upperBound), id: \.self) { hour in
                        let y = CGFloat(hour - timelineBounds.lowerBound) * hourHeight

                        Text(String(format: "%02d:00", hour))
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(width: timeColumnWidth - 8, alignment: .leading)
                            .offset(x: 0, y: y - 8)

                        Circle()
                            .fill(Color(hex: "DDE6F1"))
                            .frame(width: 6, height: 6)
                            .offset(x: timeColumnWidth + 4, y: y + 4)

                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Theme.Colors.secondaryBackground)
                            .frame(width: 1.5, height: max(hourHeight - 6, 0))
                            .offset(x: timeColumnWidth + 6, y: y + 10)
                    }

                    ForEach(eventLayouts) { layout in
                        SedentaryTimelineEventCard(session: layout.session)
                            .frame(width: eventWidth, height: layout.height, alignment: .topLeading)
                            .offset(
                                x: baseX + CGFloat(layout.column) * (eventWidth + eventColumnSpacing),
                                y: layout.y
                            )
                    }
                }
                .frame(
                    width: max(proxy.size.width, contentWidth(baseX: baseX, eventWidth: eventWidth, columnCount: columnCount)),
                    height: chartHeight,
                    alignment: .topLeading
                )
            }
        }
        .frame(height: chartHeight)
    }

    private var hourBounds: ClosedRange<Int> {
        let calendar = Calendar.current
        let startHour = max(6, (summary.sessions.map { calendar.component(.hour, from: $0.start) }.min() ?? 9) - 1)
        let endHour = min(23, (summary.sessions.map { calendar.component(.hour, from: $0.end) }.max() ?? 21) + 1)
        return startHour...max(startHour + 1, endHour)
    }

    private func minutesFromLowerBound(_ date: Date, lowerHour: Int) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: summary.date)
        let lowerDate = calendar.date(byAdding: .hour, value: lowerHour, to: dayStart) ?? dayStart
        return max(0, Int(date.timeIntervalSince(lowerDate) / 60))
    }

    private func eventLayouts(for sessions: [SedentaryTimelineSegment], lowerHour: Int) -> [SedentaryTimelineEventLayout] {
        let sortedSessions = sessions.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }

        var columnBottoms: [CGFloat] = []
        var layouts: [SedentaryTimelineEventLayout] = []

        for session in sortedSessions {
            let startMinutes = minutesFromLowerBound(session.start, lowerHour: lowerHour)
            let endMinutes = minutesFromLowerBound(session.end, lowerHour: lowerHour)
            let y = CGFloat(startMinutes) / 60 * hourHeight + eventTopPadding
            let height = max(84, CGFloat(max(endMinutes - startMinutes, 24)) / 60 * hourHeight)

            let assignedColumn = columnBottoms.firstIndex(where: { y >= $0 + 12 }) ?? columnBottoms.count
            if assignedColumn == columnBottoms.count {
                columnBottoms.append(y + height)
            } else {
                columnBottoms[assignedColumn] = y + height
            }

            layouts.append(
                SedentaryTimelineEventLayout(
                    session: session,
                    column: assignedColumn,
                    y: y,
                    height: height
                )
            )
        }

        return layouts
    }

    private func chartHeight(
        eventLayouts: [SedentaryTimelineEventLayout],
        timelineBounds: ClosedRange<Int>
    ) -> CGFloat {
        let baseHeight = CGFloat(max(1, timelineBounds.upperBound - timelineBounds.lowerBound)) * hourHeight + 44
        let eventBottom = eventLayouts.map { $0.y + $0.height }.max() ?? 0
        return max(baseHeight, eventBottom + 24)
    }

    private func contentWidth(baseX: CGFloat, eventWidth: CGFloat, columnCount: Int) -> CGFloat {
        baseX + CGFloat(columnCount) * eventWidth + CGFloat(max(0, columnCount - 1)) * eventColumnSpacing
    }
}

/// 时间轴事件布局模型 由 [SedentaryTimelineChartView] 调用，作为单个久坐时段卡片的布局描述模型。
/// 负责记录久坐事件在时间轴中的列位置、纵向偏移和渲染高度，便于处理重叠排版。
private struct SedentaryTimelineEventLayout: Identifiable {
    let id = UUID()
    let session: SedentaryTimelineSegment
    let column: Int
    let y: CGFloat
    let height: CGFloat
}

/// 时间轴事件卡片 由 [SedentaryTimelineChartView] 调用，作为时间轴里的单个久坐事件展示卡片。
/// 负责展示该时段的持续时长、时间范围、久坐强度，以及对应的打断或进行中状态。
private struct SedentaryTimelineEventCard: View {
    let session: SedentaryTimelineSegment

    var body: some View {
        let stroke = SedentaryVisualPalette.stroke(for: session.kind)
        let text = SedentaryVisualPalette.text(for: session.kind)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(session.durationMinutes.bbFormattedDurationCompact)
                    .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Text(session.timeRangeText)
                    .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Text(session.kind.title)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            HStack {
                if let breakKind = session.endingBreakKind {
                    Label(breakKind.title, systemImage: breakKind.symbol)
                        .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                } else if session.isOngoing {
                    Text("当前正在继续")
                        .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(text)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bbTintedSurface(tint: stroke, in: RoundedRectangle(cornerRadius: 18, style: .continuous), tintStrength: 0.10, shadow: false)
    }
}

extension SedentaryDaySummary {
    func minutes(for kind: SedentaryTimelineKind) -> Int {
        switch kind {
        case .light:
            return lightMinutes
        case .moderate:
            return moderateMinutes
        case .heavy:
            return heavyMinutes
        case .sleep:
            return sleepMinutes
        }
    }
}

extension SedentaryTimelineKind {
    var symbol: String {
        switch self {
        case .light:
            return "clock"
        case .moderate:
            return "hourglass"
        case .heavy:
            return "exclamationmark.triangle.fill"
        case .sleep:
            return "bed.double.fill"
        }
    }
}

extension Int {
    var bbFormattedDurationCompact: String {
        let hours = self / 60
        let minutes = self % 60
        if hours > 0 {
            return minutes == 0 ? "\(hours)小时" : "\(hours)小时\(minutes)分钟"
        }
        return "\(minutes)分钟"
    }

    var bbFormattedDurationHoursMinutes: String {
        let hours = self / 60
        let minutes = self % 60
        if hours > 0 {
            return String(localized: "\(hours) 小时 \(minutes) 分钟")
        }
        return "\(minutes) 分钟"
    }
}
