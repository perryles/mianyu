/// ReportsActionCard 作为报告模块的内容展示卡片，负责展示报告操作入口。
/// 负责以图标+标题+副标题形式呈现可点击的操作建议。

import SwiftUI
import Charts
import Combine

/// 报告操作卡片组件 作为报告模块里的内容展示卡片。
/// 负责报告展示与分享。
struct ReportsActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(accentColor.opacity(0.11))

                        Image(systemName: systemImage)
                            .font(.appSystem(size: 16, weight: .bold))
                            .foregroundColor(accentColor)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.appSystem(size: 18, weight: .black))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(categoryText)
                            .font(.appSystem(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "716986"))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(hex: "F0EDF8"), in: Capsule())
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 12, weight: .heavy))
                        .foregroundColor(Color(hex: "A3A39E"))
                }

                Text(subtitle)
                    .font(.appSystem(size: 12, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(actionMetaText)
                    .font(.appSystem(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "535350"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.045), radius: 10, x: 0, y: 4)
    }

    private var accentColor: Color {
        switch systemImage {
        case "sun.max.fill":
            return Color(hex: "F3A53B")
        case "calendar":
            return Color(hex: "5B8CFF")
        case "calendar.circle.fill":
            return Theme.Colors.mintGreen
        case "bell.badge.fill":
            return Color(hex: "F46B5A")
        case "square.and.arrow.up":
            return Color(hex: "8E6CFF")
        default:
            return Theme.Colors.mintGreen
        }
    }

    private var categoryText: String {
        switch systemImage {
        case "sun.max.fill":
            return String(localized: "当天速览")
        case "calendar":
            return String(localized: "周内聚合")
        case "calendar.circle.fill":
            return "长期变化"
        case "bell.badge.fill":
            return String(localized: "异常提醒")
        case "square.and.arrow.up":
            return String(localized: "分享卡片")
        default:
            return String(localized: "报告工具")
        }
    }

    private var actionMetaText: String {
        switch systemImage {
        case "sun.max.fill":
            return String(localized: "日报 · 看今天")
        case "calendar":
            return String(localized: "周报 · 看一周")
        case "calendar.circle.fill":
            return String(localized: "月报 · 看趋势")
        case "bell.badge.fill":
            return String(localized: "记录 · 看提醒")
        case "square.and.arrow.up":
            return String(localized: "卡片 · 可分享")
        default:
            return String(localized: "报告 · 查看")
        }
    }
}

/// 报告指标标签组件 作为报告模块里的信息标签组件。
/// 负责报告展示与分享。

struct ReportsTakeawaysCard: View {
    let title: String
    let subtitle: String
    let items: [ReportsTakeaway]

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader(title, subtitle: subtitle)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(item.tint.opacity(0.10))
                            Image(systemName: item.systemImage)
                                .font(.appSystem(size: 16, weight: .bold))
                                .foregroundColor(item.tint)
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.title)
                                    .font(.appSystem(size: 12, weight: .bold))
                                    .foregroundColor(Color(hex: "747470"))
                                Text(item.value)
                                    .font(.appSystem(size: 15, weight: .black))
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }

                            Text(item.detail)
                                .font(.appSystem(size: 12, weight: .medium))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)

                    if index < items.count - 1 {
                        Divider()
                            .overlay(Theme.Colors.surfaceBorder)
                            .padding(.leading, 52)
                    }
                }
            }
        }
    }
}

struct ReportsReadableConclusionStrip: View {
    let judgment: String
    let evidence: String
    let action: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.appSystem(size: 16, weight: .black))
                    .foregroundColor(Color(hex: "D39A00"))
                    .frame(width: 22, height: 22)

                Text(judgment)
                    .font(.appSystem(size: 17, weight: .black))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                conclusionRow(title: "依据", text: evidence, systemImage: "chart.xyaxis.line", tint: Color(hex: "776A9B"))
                conclusionRow(title: "行动", text: action, systemImage: "arrow.turn.down.right", tint: Color(hex: "B88300"))
            }
        }
        .padding(14)
        .background(Color(hex: "F3F0FA"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.09), lineWidth: 1)
        )
    }

    private func conclusionRow(title: String, text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(.appSystem(size: 12, weight: .black))
                .foregroundColor(tint)
                .frame(width: 18, height: 18)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.appSystem(size: 10, weight: .black))
                    .foregroundColor(tint)
                Text(text)
                    .font(.appSystem(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "5F5F5B"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

struct ReportMetricCompositeTrendCard: View {
    let title: String
    let subtitle: String
    let points: [ReportDaySummary]
    let kinds: [ReportMetricKind]
    @State private var inspectedDate: Date?

    private var plotPoints: [ReportMetricPlotPoint] {
        ReportMetricFormatter.plotPoints(from: points, kinds: kinds)
    }

    private var averageByKind: [ReportMetricKind: Int] {
        Dictionary(uniqueKeysWithValues: kinds.compactMap { kind in
            ReportMetricFormatter.averageNormalizedValue(for: kind, in: points).map { (kind, $0) }
        })
    }

    private var strongestKind: ReportMetricKind? {
        averageByKind.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.rawValue > rhs.key.rawValue
            }
            return lhs.value < rhs.value
        }?.key
    }

    private var weakestKind: ReportMetricKind? {
        averageByKind.min { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.rawValue < rhs.key.rawValue
            }
            return lhs.value < rhs.value
        }?.key
    }

    private var availableDates: [Date] {
        Array(Dictionary(grouping: plotPoints, by: { $0.date.reportsDayKey() }).values.compactMap { $0.first?.date })
            .sorted()
    }

    private var inspectedDay: Date? {
        guard !availableDates.isEmpty else { return nil }
        guard let inspectedDate else { return availableDates.last }
        return availableDates.min { lhs, rhs in
            abs(lhs.timeIntervalSince(inspectedDate)) < abs(rhs.timeIntervalSince(inspectedDate))
        }
    }

    private var inspectedPoints: [ReportMetricPlotPoint] {
        guard let inspectedDay else { return [] }
        return plotPoints.filter { Calendar.current.isDate($0.date, inSameDayAs: inspectedDay) }
    }

    private var usesCompactMatrix: Bool {
        availableDates.count <= 10
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader(title, subtitle: subtitle)

            if plotPoints.isEmpty {
                ReportsInlineEmptyState(text: "当前还没有足够指标样本形成多指标趋势")
            } else {
                if !usesCompactMatrix {
                    HStack(spacing: 8) {
                        ForEach(kinds) { kind in
                            ReportsCompactMetricPill(
                                title: kind.title,
                                value: ReportMetricFormatter.averageNormalizedValue(for: kind, in: points).map { "\($0)" } ?? "--",
                                tint: kind.tint
                            )
                        }
                    }
                }

                if usesCompactMatrix {
                    compactMetricMatrix

                    VStack(alignment: .leading, spacing: 7) {
                        Text("底色表示状态分区")
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                        ReportsScoreBandLegend()
                    }
                } else {
                    Chart {
                        ForEach(plotPoints) { point in
                            LineMark(
                                x: .value("日期", point.date),
                                y: .value("归一化", point.value),
                                series: .value("指标", point.kind.title)
                            )
                            .foregroundStyle(by: .value("指标", point.kind.title))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))

                            PointMark(
                                x: .value("日期", point.date),
                                y: .value("归一化", point.value)
                            )
                            .foregroundStyle(by: .value("指标", point.kind.title))
                            .symbolSize(28)
                        }

                        if let inspectedDay {
                            RuleMark(x: .value("当前选择", inspectedDay))
                                .reportsSelectionRule()
                        }
                    }
                    .chartForegroundStyleScale(metricStyleScale)
                    .reportsScoreChartFrame(height: 178)
                    .chartXSelection(value: $inspectedDate)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: max(1, points.count / 5))) { _ in
                            AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                            AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(ReportsChartStyle.axisLabel)
                        }
                    }
                }

                if let inspectedDay {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(inspectedDay.reportsShortDateString())
                                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Spacer(minLength: 0)
                            Text("状态分")
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }

                        HStack(spacing: 8) {
                            ForEach(kinds) { kind in
                                ReportsCompactMetricPill(
                                    title: kind.title,
                                    value: inspectedValue(for: kind),
                                    tint: kind.tint
                                )
                            }
                        }
                    }
                    .padding(12)
                    .background(Theme.Colors.surface.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(hex: "DDE6EF").opacity(0.82), lineWidth: 1)
                    )
                }

                ReportsReadableConclusionStrip(
                    judgment: trendJudgment,
                    evidence: trendEvidence,
                    action: trendAction,
                    tint: weakestKind?.tint ?? Theme.Colors.mintGreen
                )

                Text("图中已把睡眠、压力、HRV 和活动统一换算成 0-100 的状态分，便于比较方向。")
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var trendNarrative: String {
        guard let strongestKind, let weakestKind else {
            return String(localized: "当前周期样本还不够完整，先关注哪一项的均值最先补齐。")
        }
        if strongestKind == weakestKind {
            return String(localized: "当前各指标均值较接近，说明这一段时间的状态结构比较均衡。")
        }
        return String(localized: "整体上\(strongestKind.title)更稳，\(weakestKind.title)是更值得先补强的方向。")
    }

    private var trendJudgment: String {
        guard let strongestKind, let weakestKind else {
            return String(localized: "当前多指标趋势还不能形成强判断。")
        }
        if strongestKind == weakestKind {
            return String(localized: "四项状态分比较接近，近期结构相对均衡。")
        }
        return String(localized: "\(strongestKind.title)在托住整体状态，\(weakestKind.title)是优先补强项。")
    }

    private var trendEvidence: String {
        guard let strongestKind, let weakestKind,
              let strongest = averageByKind[strongestKind],
              let weakest = averageByKind[weakestKind] else {
            return String(localized: "至少需要补齐睡眠、压力、HRV 或活动中的两项趋势。")
        }
        return String(localized: "\(strongestKind.title)均值 \(strongest)，\(weakestKind.title)均值 \(weakest)，差值 \(max(0, strongest - weakest)) 分。")
    }

    private var trendAction: String {
        guard let weakestKind else {
            return String(localized: "先继续同步健康样本，再判断真正的优先项。")
        }
        switch weakestKind {
        case .sleep:
            return String(localized: "优先固定睡眠窗口，不急着增加训练或工作强度。")
        case .stress:
            return String(localized: "优先减少高压连续时段，给白天插入短恢复。")
        case .hrv:
            return String(localized: "优先降低刺激和强度，让恢复弹性先回升。")
        case .activity:
            return String(localized: "优先补轻步行、站立和拉伸，不需要追求高强度。")
        }
    }

    private var metricStyleScale: KeyValuePairs<String, Color> {
        [
            ReportMetricKind.sleep.title: ReportMetricKind.sleep.tint,
            ReportMetricKind.stress.title: ReportMetricKind.stress.tint,
            ReportMetricKind.hrv.title: ReportMetricKind.hrv.tint,
            ReportMetricKind.activity.title: ReportMetricKind.activity.tint
        ]
    }

    private func inspectedValue(for kind: ReportMetricKind) -> String {
        guard let point = inspectedPoints.first(where: { $0.kind == kind }) else { return "--" }
        return String(localized: "\(Int(point.value.rounded())) 分")
    }

    private var compactMetricMatrix: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text("指标")
                    .frame(width: 40, alignment: .leading)

                ForEach(availableDates, id: \.self) { date in
                    Text(date, format: .dateTime.day())
                        .frame(maxWidth: .infinity)
                        .foregroundColor(isInspected(date) ? Color(hex: "15325D") : ReportsChartStyle.axisLabel)
                }
            }
            .font(.appSystem(size: 10, weight: .bold, design: .rounded))

            ForEach(kinds) { kind in
                HStack(spacing: 5) {
                    Text(kind.title)
                        .font(.appSystem(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(kind.tint)
                        .frame(width: 40, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    ForEach(availableDates, id: \.self) { date in
                        let point = plotPoint(for: kind, on: date)
                        Button {
                            inspectedDate = date
                        } label: {
                            Text(point.map { "\(Int($0.value.rounded()))" } ?? "--")
                                .font(.appSystem(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(point == nil ? Theme.Colors.textTertiary : Color(hex: "29415F"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(
                                    cellTint(for: point).opacity(cellOpacity(for: point)),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(
                                            isInspected(date) ? cellTint(for: point) : Color.clear,
                                            lineWidth: isInspected(date) ? 1.5 : 0
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(date.reportsShortDateString())，\(kind.title)，\(point.map { "\(Int($0.value.rounded())) 分" } ?? "暂无数据")")
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.Colors.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "DDE6EF").opacity(0.82), lineWidth: 1)
        }
    }

    private func cellTint(for point: ReportMetricPlotPoint?) -> Color {
        guard let point else { return Color(hex: "DCE4EE") }
        return ReportsScorePalette.tint(for: Int(point.value.rounded()))
    }

    private func plotPoint(for kind: ReportMetricKind, on date: Date) -> ReportMetricPlotPoint? {
        plotPoints.first { point in
            point.kind == kind && Calendar.current.isDate(point.date, inSameDayAs: date)
        }
    }

    private func cellOpacity(for point: ReportMetricPlotPoint?) -> Double {
        guard let point else { return 0.04 }
        return 0.08 + min(1, max(0, point.value / 100)) * 0.18
    }

    private func isInspected(_ date: Date) -> Bool {
        guard let inspectedDay else { return false }
        return Calendar.current.isDate(date, inSameDayAs: inspectedDay)
    }

}

private struct ReportHRVRecoveryPoint: Identifiable {
    let date: Date
    let hrv: Double
    let stress: Double?

    var id: Int64 {
        Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
    }
}

struct ReportHRVRecoveryTrendCard: View {
    let title: String
    let subtitle: String
    let points: [ReportDaySummary]
    @State private var inspectedDate: Date?

    private var plotPoints: [ReportHRVRecoveryPoint] {
        points.compactMap { point in
            guard let hrv = point.hrv, hrv > 0 else { return nil }
            return ReportHRVRecoveryPoint(date: point.date, hrv: hrv, stress: point.stress)
        }
        .sorted { $0.date < $1.date }
    }

    private var baseline: Double {
        guard !plotPoints.isEmpty else { return 0 }
        return plotPoints.map(\.hrv).reduce(0, +) / Double(plotPoints.count)
    }

    private var selectedPoint: ReportHRVRecoveryPoint? {
        guard !plotPoints.isEmpty else { return nil }
        guard let inspectedDate else { return plotPoints.last }
        return plotPoints.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(inspectedDate)) < abs(rhs.date.timeIntervalSince(inspectedDate))
        }
    }

    private var stressEventPoint: ReportHRVRecoveryPoint? {
        let candidate = plotPoints
            .filter { $0.stress != nil }
            .max { ($0.stress ?? 0) < ($1.stress ?? 0) }
        guard let candidate, (candidate.stress ?? 0) >= 60 else { return nil }
        return candidate
    }

    private var hrvDomain: ClosedRange<Double> {
        let values = plotPoints.map(\.hrv) + [baseline]
        guard let minimum = values.min(), let maximum = values.max() else { return 0...100 }
        let padding = max(4, (maximum - minimum) * 0.22)
        return max(0, minimum - padding)...max(minimum + 8, maximum + padding)
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader(title, subtitle: subtitle)

            if plotPoints.isEmpty {
                ReportsInlineEmptyState(text: "当前周期暂无可用 HRV 样本")
            } else {
                HStack(spacing: 8) {
                    ReportsCompactMetricPill(title: "周期基线", value: hrvText(baseline), tint: BBChartStyle.baseline)
                    ReportsCompactMetricPill(title: "最近", value: selectedPoint.map { hrvText($0.hrv) } ?? "--", tint: selectedTint)
                    ReportsCompactMetricPill(title: "压力事件", value: stressEventText, tint: Color(hex: "F46B5A"))
                }

                HStack(spacing: 14) {
                    BBChartLegendItem(title: "HRV", tint: ReportMetricKind.hrv.tint, symbol: .dot)
                    BBChartLegendItem(title: "周期基线", tint: ReportsChartStyle.stabilityLine)
                    BBChartLegendItem(title: "压力高点", tint: Color(hex: "F46B5A"), symbol: .triangle)
                }

                Chart {
                    ForEach(plotPoints) { point in
                        AreaMark(
                            x: .value("日期", point.date),
                            yStart: .value("基线", baseline),
                            yEnd: .value("HRV", point.hrv)
                        )
                        .reportsScoreArea(tint: ReportMetricKind.hrv.tint)

                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("HRV", point.hrv)
                        )
                        .reportsScoreLine(tint: ReportMetricKind.hrv.tint)

                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("HRV", point.hrv)
                        )
                        .reportsScorePoint(tint: point.hrv >= baseline ? Theme.Colors.mintGreen : Color(hex: "F3A53B"))
                    }

                    RuleMark(y: .value("周期基线", baseline))
                        .foregroundStyle(ReportsChartStyle.stabilityLine)
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))

                    if let stressEventPoint {
                        PointMark(
                            x: .value("压力事件日期", stressEventPoint.date),
                            y: .value("压力事件 HRV", stressEventPoint.hrv)
                        )
                        .foregroundStyle(Color(hex: "F46B5A"))
                        .symbol(.triangle)
                        .symbolSize(76)
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("当前选择", selectedPoint.date))
                            .reportsSelectionRule(tint: selectedTint)
                    }
                }
                .frame(height: 180)
                .chartYScale(domain: hrvDomain)
                .chartXSelection(value: $inspectedDate)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, plotPoints.count / 5))) { _ in
                        AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ReportsChartStyle.axisLabel)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                        AxisValueLabel()
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ReportsChartStyle.axisLabel)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .bbChartPlotSurface(tint: ReportMetricKind.hrv.tint, cornerRadius: 10)
                }

                if let selectedPoint {
                    HStack(spacing: 8) {
                        ReportsCompactMetricPill(title: "日期", value: selectedPoint.date.reportsShortDateString(), tint: selectedTint)
                        ReportsCompactMetricPill(title: "HRV", value: hrvText(selectedPoint.hrv), tint: ReportMetricKind.hrv.tint)
                        ReportsCompactMetricPill(title: "压力", value: selectedPoint.stress.map { "\(Int($0.rounded()))" } ?? "--", tint: ReportMetricKind.stress.tint)
                    }
                }
            }
        }
    }

    private var selectedTint: Color {
        guard let selectedPoint else { return ReportMetricKind.hrv.tint }
        return selectedPoint.hrv >= baseline ? Theme.Colors.mintGreen : Color(hex: "F3A53B")
    }

    private var stressEventText: String {
        guard let stressEventPoint, let stress = stressEventPoint.stress else { return "未出现" }
        return "\(Int(stress.rounded())) · \(stressEventPoint.date.reportsShortDateString())"
    }

    private func hrvText(_ value: Double) -> String {
        "\(Int(value.rounded())) ms"
    }

}

struct ReportPeriodReviewCard: View {
    let title: String
    let subtitle: String
    let scope: String
    let points: [ReportDaySummary]

    private var validPoints: [ReportDaySummary] {
        points.filter { $0.score != nil }.sorted { $0.date < $1.date }
    }

    private var averageScore: Int? {
        validPoints.reportsAverageScore
    }

    private var bestPoint: ReportDaySummary? {
        validPoints.max { $0.scoreValue < $1.scoreValue }
    }

    private var weakestPoint: ReportDaySummary? {
        validPoints.min { $0.scoreValue < $1.scoreValue }
    }

    private var trendDelta: Int? {
        guard let first = validPoints.first, let last = validPoints.last, first.id != last.id else { return nil }
        return last.scoreValue - first.scoreValue
    }

    private var metricRanks: [ReportMetricRankItem] {
        ReportMetricFormatter.metricRankItems(from: validPoints)
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader(title, subtitle: subtitle)

            if validPoints.isEmpty {
                ReportsInlineEmptyState(text: "\(scope)暂无足够数据形成周期复盘")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        ReportsCompactMetricPill(title: "平均", value: averageScore.map { "\($0)分" } ?? "--", tint: ReportsScorePalette.tint(for: averageScore))
                        ReportsCompactMetricPill(title: "有效", value: "\(validPoints.count)天", tint: Color(hex: "5B8CFF"))
                        ReportsCompactMetricPill(title: "趋势", value: trendText, tint: trendTint)
                    }

                    HStack(spacing: 8) {
                        ReportsCompactMetricPill(title: "最好", value: bestPoint.map { "\($0.scoreValue) · \($0.date.reportsShortDateString())" } ?? "--", tint: Theme.Colors.mintGreen)
                        ReportsCompactMetricPill(title: "低点", value: weakestPoint.map { "\($0.scoreValue) · \($0.date.reportsShortDateString())" } ?? "--", tint: Color(hex: "F46B5A"))
                    }

                    if let strongest = metricRanks.first {
                        reviewRow(
                            title: "主要支撑",
                            value: "\(strongest.kind.title) \(strongest.score)",
                            detail: strongest.note,
                            systemImage: strongest.kind.systemImage,
                            tint: strongest.kind.tint
                        )
                    }

                    if let weakest = metricRanks.last, metricRanks.count > 1 {
                        reviewRow(
                            title: "优先改善",
                            value: "\(weakest.kind.title) \(weakest.score)",
                            detail: weakest.note,
                            systemImage: weakest.kind.systemImage,
                            tint: weakest.kind.tint
                        )
                    }

                    Text(reviewNarrative)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var trendText: String {
        guard let trendDelta else { return "样本不足" }
        if trendDelta > 0 { return "+\(trendDelta)" }
        if trendDelta < 0 { return "\(trendDelta)" }
        return String(localized: "持平")
    }

    private var trendTint: Color {
        guard let trendDelta else { return Color(hex: "8AA0B8") }
        if trendDelta >= 4 { return Theme.Colors.mintGreen }
        if trendDelta <= -4 { return Color(hex: "F46B5A") }
        return Color(hex: "5B8CFF")
    }

    private var reviewNarrative: String {
        let averageText = averageScore.map { "\($0)分" } ?? "暂无评分"
        let bestText = bestPoint.map { "\($0.date.reportsShortDateString())最好" } ?? "暂无最佳日期"
        let weakText = weakestPoint.map { "\($0.date.reportsShortDateString())最低" } ?? "暂无低点日期"
        return String(localized: "\(scope)平均 \(averageText)，\(bestText)，\(weakText)。优先把低点日期的睡眠、压力和活动安排回看一遍。")
    }

    private func reviewRow(title: String, value: String, detail: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.13))
                Image(systemName: systemImage)
                    .font(.appSystem(size: 16, weight: .bold))
                    .foregroundColor(tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text(value)
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Text(detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.Colors.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}




struct ReportDailyMetricBalanceCard: View {
    let summary: ReportDaySummary?

    private var availableKinds: [ReportMetricKind] {
        ReportMetricKind.allCases.filter { kind in
            guard let summary else { return false }
            return ReportMetricFormatter.normalizedValue(for: kind, in: summary) != nil
        }
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("当天指标结构", subtitle: "表现分越高，当前状态越好；每项下方同时显示当天实测数据。")

            if let summary, !availableKinds.isEmpty {
                VStack(spacing: 10) {
                    ForEach(availableKinds) { kind in
                        metricRow(kind: kind, summary: summary)
                    }
                }
            } else {
                ReportsInlineEmptyState(text: "当前还没有足够指标样本形成结构图")
            }
        }
    }

    private func metricRow(kind: ReportMetricKind, summary: ReportDaySummary) -> some View {
        let value = ReportMetricFormatter.normalizedValue(for: kind, in: summary) ?? 0
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(kind.title, systemImage: kind.systemImage)
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(kind.tint)
                Spacer()
                Text("表现分")
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "7C8BA1"))
                Text("\(Int(value.rounded())) 分")
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "29415F"))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(kind.tint.opacity(0.10))
                    Capsule(style: .continuous)
                        .fill(kind.tint)
                        .frame(width: proxy.size.width * CGFloat(value / 100.0))
                }
            }
            .frame(height: 9)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("当天实测")
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "7C8BA1"))
                Spacer(minLength: 8)
                Text(measurementText(for: kind, in: summary))
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "52657F"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(12)
        .background(Theme.Colors.surface.opacity(0.70), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func measurementText(for kind: ReportMetricKind, in summary: ReportDaySummary) -> String {
        switch kind {
        case .sleep:
            return summary.sleepHours.map { String(format: String(localized: "睡眠时长 %.1f 小时"), $0) } ?? "睡眠时长 --"
        case .stress:
            return summary.stress.map { "压力水平 \(Int($0.rounded())) / 100" } ?? "压力水平 --"
        case .hrv:
            return summary.hrv.map { "HRV \(Int($0.rounded())) 毫秒" } ?? "HRV --"
        case .activity:
            return summary.steps.map { "步数 \(Int($0.rounded())) 步" } ?? "步数 --"
        }
    }
}

struct ReportCalendarHeatmapCard: View {
    let title: String
    let subtitle: String
    let points: [ReportDaySummary]
    let interval: DateInterval

    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        var result: [Date] = []
        var cursor = start
        while cursor < end {
            result.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
        }
        return result
    }

    private var scoreByDay: [Int64: Int] {
        var result: [Int64: Int] = [:]
        for point in points {
            guard let score = point.score else { continue }
            let day = Calendar.current.startOfDay(for: point.date)
            result[Int64(day.timeIntervalSince1970)] = score
        }
        return result
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader(title, subtitle: subtitle)

            if days.isEmpty {
                ReportsInlineEmptyState(text: "暂无可展示的日期")
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("底色表示评分状态")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    ReportsScoreBandLegend()
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(days, id: \.timeIntervalSince1970) { day in
                        let key = Int64(Calendar.current.startOfDay(for: day).timeIntervalSince1970)
                        let score = scoreByDay[key]
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(heatColor(score))
                            .frame(height: 28)
                            .overlay {
                                Text(dayNumber(day))
                                    .font(.appSystem(size: 9, weight: .black, design: .rounded))
                                    .foregroundColor(score == nil ? Theme.Colors.textTertiary : .white)
                            }
                    }
                }

                HStack(spacing: 8) {
                    ReportsCompactMetricPill(title: "有效天数", value: "\(points.filter { $0.score != nil }.count)", tint: Color(hex: "5B8CFF"))
                    ReportsCompactMetricPill(title: "最高", value: points.compactMap(\.score).max().map(String.init) ?? "--", tint: Theme.Colors.mintGreen)
                    ReportsCompactMetricPill(title: "最低", value: points.compactMap(\.score).min().map(String.init) ?? "--", tint: Color(hex: "F46B5A"))
                }
            }
        }
    }

    private func heatColor(_ score: Int?) -> Color {
        guard let score else { return Color(hex: "DCE4EE").opacity(0.75) }
        return ReportsScorePalette.tint(for: score).opacity(score >= 85 ? 0.92 : 0.78)
    }

    private func dayNumber(_ date: Date) -> String {
        "\(Calendar.current.component(.day, from: date))"
    }
}

struct ReportDataCoverageCard: View {
    let title: String
    let subtitle: String
    let points: [ReportDaySummary]
    let expectedCount: Int

    private var coverageItems: [ReportMetricCoverageItem] {
        ReportMetricFormatter.coverageItems(from: points, expectedCount: expectedCount)
    }

    private var validDays: Int {
        points.filter(\.hasData).count
    }

    private var overallPercent: Int {
        ReportMetricFormatter.overallCoveragePercent(from: points, expectedCount: expectedCount)
    }

    private var weakestItem: ReportMetricCoverageItem? {
        coverageItems.min { lhs, rhs in
            if lhs.availableCount == rhs.availableCount {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.availableCount < rhs.availableCount
        }
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader(title, subtitle: subtitle)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ReportsCompactMetricPill(title: "可信度", value: "\(overallPercent)%", tint: confidenceTint)
                    ReportsCompactMetricPill(title: "有效天数", value: "\(validDays)/\(max(expectedCount, 1))", tint: Color(hex: "5B8CFF"))
                    ReportsCompactMetricPill(title: "待补齐", value: weakestItem?.kind.title ?? "--", tint: weakestItem?.kind.tint ?? Color(hex: "8AA0B8"))
                }

                VStack(spacing: 10) {
                    ForEach(coverageItems) { item in
                        coverageRow(item)
                    }
                }

                Text(coverageNarrative)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var confidenceTint: Color {
        switch overallPercent {
        case 80...: return Theme.Colors.mintGreen
        case 55..<80: return Color(hex: "5B8CFF")
        case 30..<55: return Color(hex: "F3A53B")
        default: return Color(hex: "F46B5A")
        }
    }

    private var coverageNarrative: String {
        guard validDays > 0 else {
            return String(localized: "当前周期还没有足够健康样本，报告会先保持空态，等睡眠、压力、HRV 和活动同步后再生成判断。")
        }
        if overallPercent >= 80 {
            return String(localized: "睡眠、压力、HRV 和活动覆盖较完整，当前报告可以作为这段时间的主要复盘依据。")
        }
        if let weakestItem, weakestItem.availableCount < max(expectedCount / 2, 1) {
            return String(localized: "\(weakestItem.kind.title)样本偏少，相关结论会更保守；补齐后，趋势和行动建议会更稳定。")
        }
        return String(localized: "当前样本已经可读，但仍有部分指标缺口，建议把结论当作近期方向而不是单点定论。")
    }

    private func coverageRow(_ item: ReportMetricCoverageItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(item.kind.title, systemImage: item.kind.systemImage)
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(item.kind.tint)

                Spacer()

                Text("\(item.availableCount)/\(item.expectedCount) · \(item.percentText)")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "52657F"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(item.kind.tint.opacity(0.10))
                    Capsule(style: .continuous)
                        .fill(item.kind.tint)
                        .frame(width: proxy.size.width * CGFloat(item.ratio))
                }
            }
            .frame(height: 9)
        }
        .padding(12)
        .background(Theme.Colors.surface.opacity(0.70), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}



/// 报告图表图例：只解释图表视觉编码，业务结论统一放到结论条里。
struct ReportsChartReferenceLegend: View {
    let averageTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReportsScoreBandLegend()

            HStack(spacing: 14) {
                BBChartLegendItem(title: averageTitle, tint: ReportsChartStyle.averageLine)
                BBChartLegendItem(title: "稳定参考", tint: ReportsChartStyle.stabilityLine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ReportsScoreBandLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            legendItem(title: "承压", range: "<50", score: 40)
            legendItem(title: "波动", range: "50-69", score: 60)
            legendItem(title: "稳定", range: "70-84", score: 75)
            legendItem(title: "良好", range: "≥85", score: 90)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func legendItem(title: String, range: String, score: Int) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ReportsScorePalette.tint(for: score))
                .frame(width: 9, height: 9)

            Text("\(title) \(range)")
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(ReportsChartStyle.axisLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReportsChartSelectionBar: View {
    let title: String
    let value: String
    let comparison: String
    let tint: Color

    var body: some View {
        BBChartSelectionReadout(
            title: title,
            value: value,
            detail: comparison,
            tint: tint,
            systemImage: "chart.xyaxis.line"
        )
    }
}

struct ReportsSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 18, weight: .black))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.appSystem(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "747470"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ReportsContentCard<Content: View>: View {
    let spacing: CGFloat
    let isContinuous: Bool
    let content: Content

    init(spacing: CGFloat = 12, isContinuous: Bool = false, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.isContinuous = isContinuous
        self.content = content()
    }

    var body: some View {
        if isContinuous {
            reportContent
        } else {
            reportContent
                .padding(16)
                .bbChartSurface(tint: ReportsChartStyle.score, cornerRadius: 22)
        }
    }

    private var reportContent: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
    }
}

struct ReportsControlCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ReportsContentCard(spacing: 10) {
            ReportsSectionHeader(title, subtitle: subtitle)
            content
        }
    }
}

struct ReportsHeroMetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        BBChartMetricPill(title: title, value: value, tint: tint, size: .regular)
    }
}

/// 报告封面的单项摘要。日报、周报和月报共用同一套信息层级，
/// 避免三个周期在字号、间距和无障碍朗读顺序上逐渐分叉。
struct ReportsHeroMetric: Identifiable {
    let title: String
    let value: String
    let tint: Color

    var id: String { title }
}

/// 日报、周报与月报共用的自适应封面。
/// 横向空间不足或动态字体较大时自动改为纵向排列，不压缩结论文本。
struct ReportsPeriodHeroCard: View {
    let reportTitle: String
    let periodText: String
    let eyebrow: String
    let headline: String
    let detail: String
    let score: Int?
    let scoreLabel: String
    let tint: Color
    let metrics: [ReportsHeroMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(reportTitle)
                    .font(.appSystem(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer(minLength: 8)

                Text(periodText)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.trailing)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    conclusion
                    Spacer(minLength: 0)
                    scoreGauge
                }

                VStack(alignment: .leading, spacing: 16) {
                    conclusion
                    scoreGauge
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    metricPills
                }

                VStack(spacing: 8) {
                    metricPills
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Theme.Colors.background)
                .overlay(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint)
                        .frame(width: 56, height: 4)
                        .padding(20)
                        .accessibilityHidden(true)
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports-period-hero")
    }

    private var conclusion: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(eyebrow)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint.opacity(0.12), in: Capsule())

            Text(headline)
                .font(.appSystem(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scoreGauge: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.12), lineWidth: 9)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(score.map(String.init) ?? "--")
                    .font(.appSystem(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.7)
                Text(scoreLabel)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scoreLabel)
        .accessibilityValue(score.map { "\($0) 分" } ?? "暂无")
    }

    @ViewBuilder
    private var metricPills: some View {
        ForEach(metrics) { metric in
            ReportsHeroMetricPill(title: metric.title, value: metric.value, tint: metric.tint)
                .frame(maxWidth: .infinity)
        }
    }

    private var progress: CGFloat {
        CGFloat(min(max(Double(score ?? 0) / 100, 0), 1))
    }
}

/// 报告页小指标胶囊：薄包装设计系统组件，保留旧调用点的命名语义。
struct ReportsCompactMetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        BBChartMetricPill(title: title, value: value, tint: tint)
    }
}

/// 报告占位卡片组件 作为报告模块里的内容展示卡片。
/// 负责报告展示与分享。

struct ReportsInsightCard: View {
    let title: String
    let subtitle: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        ReportsContentCard(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint.opacity(0.10))
                    Image(systemName: systemImage)
                        .font(.appSystem(size: 18, weight: .bold))
                        .foregroundColor(tint)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.appSystem(size: 16, weight: .black))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(.appSystem(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "716986"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            Color(hex: "F0EDF8"),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.appSystem(size: 12, weight: .medium))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

struct ReportsBodyAgeOverviewCard: View {
    let title: String
    let subtitle: String
    let actionTitle: String?
    let onOpen: (() -> Void)?

    @State private var viewModel = BodyAgeInterpretationViewModel()

    init(
        title: String = "身体年龄",
        subtitle: String = "把身体年龄、恢复趋势和近期状态说明放在一起看。",
        actionTitle: String? = nil,
        onOpen: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.onOpen = onOpen
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                signalBadge
            }

            switch viewModel.state {
            case .loading:
                ReportsInlineEmptyState(text: "正在整理最近的身体年龄说明...")
            case .needsAuthorization:
                compactMessage(
                    headline: "等待健康授权",
                    detail: "连接健康 App 后，这里会开始解释睡眠、恢复、压力、活动与上下文信号。"
                )
            case .empty:
                compactMessage(
                    headline: "等待更多样本",
                    detail: "继续同步几天或补一点生活记录后，这里会生成更完整的波动判断。"
                )
            case .ready:
                readyContent
            }

            if let actionTitle, let onOpen {
                Button(action: onOpen) {
                    HStack(spacing: 8) {
                        Text(actionTitle)
                            .font(.appSystem(size: 13, weight: .black, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.appSystem(size: 11, weight: .black))
                    }
                    .foregroundColor(signalTint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(signalTint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            if viewModel.state == .loading && viewModel.dailySummary == nil {
                await viewModel.load()
            }
        }
    }

    private var signalTint: Color {
        viewModel.dailySummary?.accentColor ?? Color(hex: "5B8CFF")
    }

    @ViewBuilder
    private var signalBadge: some View {
        Text(viewModel.dailySummary?.riskTitle ?? viewModel.state.title)
            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(signalTint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(signalTint.opacity(0.12), in: Capsule())
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = viewModel.dailySummary {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary.headline)
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(summary.narrative)
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 4) {
                        Text(summary.scoreText)
                            .font(.appSystem(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("今日状态")
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "7A8AA0"))
                    }
                    .frame(width: 82, height: 86)
                    .background(Theme.Colors.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(summary.signalPills.prefix(4))) { pill in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pill.title)
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                            Text(pill.value)
                                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(pill.note)
                                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(pill.tint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.Colors.surface.opacity(0.74), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }

            HStack(spacing: 8) {
                compactFactPill(title: "单日", value: viewModel.interpretationCards.first?.badge ?? "已生成")
                compactFactPill(title: "异常日", value: viewModel.abnormalDays.isEmpty ? "暂无" : "\(viewModel.abnormalDays.count) 天")
                compactFactPill(title: "说明书", value: viewModel.manualProfile?.badge ?? "待整理")
            }

            if let weekly = viewModel.interpretationCards.dropFirst().first {
                Text(weekly.summary)
                    .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "35506F"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func compactMessage(headline: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(detail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func compactFactPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(value)
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Theme.Colors.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
