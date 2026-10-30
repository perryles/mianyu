import SwiftUI
import Charts

enum StressTimelineChartPresentation: Equatable {
    case standard
    case compact
    case showcase
}

nonisolated struct StressChartInterpolationResult: Sendable {
    let points: [TimeSeriesPoint]
    let estimatedTimestamps: Set<Int64>
}

/// Fills only bounded internal gaps between real chart samples. The returned
/// timestamps stay on the original time axis and are never extrapolated.
nonisolated enum StressChartGapInterpolator {
    static func interpolate(
        points: [TimeSeriesPoint],
        bucketSeconds: Int64,
        maximumGapSeconds: Int64,
        domain: ClosedRange<Date>,
        now: Date
    ) -> StressChartInterpolationResult {
        guard bucketSeconds > 0, maximumGapSeconds >= bucketSeconds else {
            return StressChartInterpolationResult(points: points, estimatedTimestamps: [])
        }

        let domainStart = Int64(domain.lowerBound.timeIntervalSince1970)
        let domainEnd = Int64(domain.upperBound.timeIntervalSince1970)
        let cutoff = min(Int64(now.timeIntervalSince1970), domainEnd)
        var measuredByTimestamp: [Int64: TimeSeriesPoint] = [:]
        for point in points where point.timestamp >= domainStart
            && point.timestamp <= cutoff
            && (1...100).contains(point.value) {
            measuredByTimestamp[point.timestamp] = point
        }

        let measured = measuredByTimestamp.values.sorted { $0.timestamp < $1.timestamp }
        guard measured.count >= 2 else {
            return StressChartInterpolationResult(points: measured, estimatedTimestamps: [])
        }

        let calendar = Calendar.current
        var resolvedByTimestamp = measuredByTimestamp
        var estimatedTimestamps: Set<Int64> = []

        for index in 1..<measured.count {
            let previous = measured[index - 1]
            let next = measured[index]
            let gap = next.timestamp - previous.timestamp
            guard gap > bucketSeconds,
                  gap <= maximumGapSeconds,
                  gap.isMultiple(of: bucketSeconds),
                  calendar.isDate(previous.date, inSameDayAs: next.date) else {
                continue
            }

            let stepCount = gap / bucketSeconds
            for step in 1..<stepCount {
                let timestamp = previous.timestamp + step * bucketSeconds
                guard timestamp <= cutoff, resolvedByTimestamp[timestamp] == nil else { continue }
                let ratio = Double(step) / Double(stepCount)
                let interpolated = Double(previous.value)
                    + (Double(next.value - previous.value) * ratio)
                let value = min(100, max(1, Int(interpolated.rounded())))
                resolvedByTimestamp[timestamp] = TimeSeriesPoint(timestamp: timestamp, value: value)
                estimatedTimestamps.insert(timestamp)
            }
        }

        return StressChartInterpolationResult(
            points: resolvedByTimestamp.values.sorted { $0.timestamp < $1.timestamp },
            estimatedTimestamps: estimatedTimestamps
        )
    }
}

struct StressTimelineStyledChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let points: [TimeSeriesPoint]
    let domain: ClosedRange<Date>
    let axisDates: [Date]
    let axisLabel: (Date) -> String
    let accent: Color
    let emptyText: String
    var sleepIntervals: [DateInterval] = []
    var height: CGFloat = 220
    var metricName: String = "综合压力"
    var presentation: StressTimelineChartPresentation = .standard
    var bucketDuration: TimeInterval? = nil
    var estimatedTimestamps: Set<Int64> = []
    @Binding var selectedTimestamp: Int64?

    private var chartPoints: [StressChartPoint] {
        var pointsByTimestamp: [Int64: StressChartPoint] = [:]
        for point in points where point.value > 0 {
            pointsByTimestamp[point.timestamp] = StressChartPoint(
                timestamp: point.timestamp,
                value: Double(point.value),
                isEstimated: estimatedTimestamps.contains(point.timestamp)
            )
        }
        return pointsByTimestamp.values.sorted { $0.timestamp < $1.timestamp }
    }

    private var selectedPoint: StressChartPoint? {
        guard let selectedTimestamp else { return nil }
        return chartPoints.first(where: { $0.timestamp == selectedTimestamp })
    }

    private var displayedSelectedPoints: [StressChartPoint] {
        selectedPoint.map { [$0] } ?? []
    }

    private var visibleSleepIntervals: [StressChartSleepInterval] {
        guard domain.upperBound.timeIntervalSince(domain.lowerBound) < 36 * 60 * 60 else { return [] }
        return sleepIntervals.compactMap { interval in
            let start = max(interval.start, domain.lowerBound)
            let end = min(interval.end, domain.upperBound)
            guard end > start else { return nil }
            return StressChartSleepInterval(start: start, end: end)
        }
    }

    private var barWidth: MarkDimension {
        .fixed(presentation == .compact ? 2.25 : (presentation == .showcase ? 5.5 : 3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Chart {
                    ForEach(visibleSleepIntervals) { interval in
                        RectangleMark(
                            xStart: .value("睡眠开始", interval.start),
                            xEnd: .value("睡眠结束", interval.end),
                            yStart: .value("睡眠下界", 0),
                            yEnd: .value("睡眠上界", 100)
                        )
                        .foregroundStyle(Color(hex: "6269E8").opacity(0.08))

                        RectangleMark(
                            xStart: .value("睡眠开始", interval.start),
                            xEnd: .value("睡眠结束", interval.end),
                            yStart: .value("睡眠标记下界", 98.8),
                            yEnd: .value("睡眠标记上界", 100)
                        )
                        .foregroundStyle(Color(hex: "4F5BC9"))

                        PointMark(
                            x: .value("睡眠区间", interval.midpoint),
                            y: .value("睡眠图标", 100)
                        )
                        .foregroundStyle(Color.clear)
                        .annotation(position: .top, spacing: 4) {
                            StressChartSleepBadge(start: interval.start, end: interval.end)
                        }
                    }

                    ForEach(chartPoints) { item in
                        if let interval = fixedBucketInterval(for: item) {
                            RectangleMark(
                                xStart: .value("时间桶开始", interval.start),
                                xEnd: .value("时间桶结束", interval.end),
                                yStart: .value("起点", 0),
                                yEnd: .value("压力", item.value)
                            )
                            .foregroundStyle(stressColor(for: item.value))
                            .cornerRadius(presentation == .showcase ? 3 : 1.5)
                            .opacity(markOpacity(for: item))
                            .accessibilityLabel(Text(item.isEstimated ? String(localized: "综合压力估算") : String(localized: "综合压力样本")))
                            .accessibilityValue(Text("\(Int(item.value.rounded()))"))
                        } else {
                            BarMark(
                                x: .value("时间", item.date),
                                yStart: .value("起点", 0),
                                yEnd: .value("压力", item.value),
                                width: barWidth
                            )
                            .foregroundStyle(stressColor(for: item.value))
                            .cornerRadius(presentation == .showcase ? 3 : 1.5)
                            .opacity(markOpacity(for: item))
                            .accessibilityLabel(Text(item.isEstimated ? String(localized: "综合压力估算") : String(localized: "综合压力样本")))
                            .accessibilityValue(Text("\(Int(item.value.rounded()))"))
                        }
                    }

                    ForEach(displayedSelectedPoints) { selectedPoint in
                        RuleMark(x: .value("选中", selectedPoint.date))
                            .foregroundStyle(accent.opacity(0.26))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        PointMark(
                            x: .value("时间", selectedPoint.date),
                            y: .value("压力", selectedPoint.value)
                        )
                        .symbolSize(88)
                        .foregroundStyle(Theme.Colors.onAccent)
                        .annotation(position: .overlay, alignment: .center) {
                            Circle()
                                .fill(stressColor(for: selectedPoint.value))
                                .frame(width: 13, height: 13)
                        }
                        .annotation(position: .top) {
                            if presentation != .standard {
                                Text(selectedPoint.isEstimated
                                     ? String(localized: "约 \(Int(selectedPoint.value.rounded())) · 估算")
                                     : "\(Int(selectedPoint.value.rounded()))")
                                    .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundColor(stressColor(for: selectedPoint.value))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Theme.Colors.surface.opacity(0.98), in: Capsule())
                                    .shadow(color: stressColor(for: selectedPoint.value).opacity(0.12), radius: 6, x: 0, y: 3)
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartYScale(domain: 0...100)
                .chartXScale(domain: domain)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let plotFrame = proxy.plotFrame {
                            let frame = geometry[plotFrame]
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    LongPressGesture(minimumDuration: 0.25)
                                        .sequenced(before: DragGesture(minimumDistance: 0))
                                        .onChanged { value in
                                            switch value {
                                            case .first:
                                                break
                                            case .second(true, let drag):
                                                guard let drag else { return }
                                                updateSelection(at: drag.location, frame: frame, proxy: proxy)
                                            default:
                                                break
                                            }
                                        }
                                        .onEnded { value in
                                            switch value {
                                            case .second(true, let drag):
                                                if let drag {
                                                    updateSelection(at: drag.location, frame: frame, proxy: proxy)
                                                }
                                            default:
                                                break
                                            }
                                        }
                                )
                        } else {
                            Color.clear
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.55, dash: [2, 5]))
                            .foregroundStyle(Theme.Colors.textTertiary.opacity(presentation == .showcase ? 0.06 : 0.12))
                        AxisTick(length: 3)
                            .foregroundStyle(Theme.Colors.textTertiary.opacity(0.34))
                        AxisValueLabel(centered: true) {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(date))
                                    .font(.appSystem(size: presentation == .compact ? 9 : 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(
                        position: presentation == .showcase ? .trailing : .leading,
                        values: presentation == .showcase ? [0, 50, 100] : [0, 25, 50, 75, 100]
                    ) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 5]))
                            .foregroundStyle(accent.opacity(presentation == .showcase ? 0.12 : 0.18))
                        AxisTick().foregroundStyle(Color.clear)
                        AxisValueLabel {
                            if let percentage = value.as(Int.self) {
                                Text(localizedPercent(percentage))
                                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .chartPlotStyle { plotArea in
                    if presentation == .showcase {
                        plotArea
                            .clipped()
                            .modernReportChartPlotSurface(tint: accent, cornerRadius: 20)
                    } else {
                        plotArea
                            .background(Theme.Colors.secondarySurface)
                            .clipped()
                            .padding(.trailing, 4)
                    }
                }
                .frame(height: height)

                if chartPoints.isEmpty {
                    if presentation == .showcase {
                        ModernReportChartEmptyState(
                            symbol: "gauge.with.dots.needle.50percent",
                            title: "等待压力趋势",
                            message: emptyText.isEmpty
                                ? "保持 Apple Watch 佩戴和健康数据同步，获得有效的心率与 HRV 样本后会自动生成。"
                                : emptyText,
                            tint: accent
                        )
                        .padding(.horizontal, 4)
                    } else {
                        StressChartEmptyState(text: emptyText)
                            .padding(.horizontal, 24)
                            .background(Theme.Colors.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }

            Group {
                if let selectedPoint, presentation == .standard {
                    StressChartSelectionCard(point: selectedPoint, metricName: metricName)
                        .id(selectedPoint.id)
                        .transition(
                            reduceMotion
                                ? .identity
                                : .opacity.combined(with: .offset(y: MotionTokens.tooltipOffsetY))
                        )
                }
            }
            .animation(
                reduceMotion ? MotionTokens.tooltipAnimationReduced : MotionTokens.tooltipAnimation,
                value: selectedPoint?.id
            )
        }
    }

    private func updateSelection(at location: CGPoint, frame: CGRect, proxy: ChartProxy) {
        guard frame.contains(location) else {
            selectedTimestamp = nil
            return
        }
        let xPosition = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: xPosition) else { return }
        selectedTimestamp = nearestPoint(to: date)?.timestamp
    }

    private func nearestPoint(to date: Date) -> StressChartPoint? {
        chartPoints.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    private func fixedBucketInterval(for point: StressChartPoint) -> DateInterval? {
        guard let bucketDuration, bucketDuration > 0 else { return nil }
        let inset = bucketDuration * 0.10
        let start = point.date.addingTimeInterval(inset)
        let end = min(point.date.addingTimeInterval(bucketDuration - inset), domain.upperBound)
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func markOpacity(for point: StressChartPoint) -> Double {
        let baseOpacity = point.isEstimated ? 0.38 : 1
        guard let selectedPoint else { return baseOpacity }
        if selectedPoint.id == point.id {
            return point.isEstimated ? 0.58 : 1
        }
        return point.isEstimated ? 0.14 : 0.32
    }

    private func stressColor(for value: Double) -> Color {
        switch StressRules.band(for: Int(value.rounded())) {
        case .waiting: return Theme.Colors.textTertiary
        case .relaxed: return Color(hex: "34C759")
        case .steady: return Color(hex: "007F79")
        case .mild: return Color(hex: "FF9F0A")
        case .caution: return Color(hex: "FF7A00")
        case .high: return Color(hex: "D70015")
        }
    }
}

private struct StressChartSleepInterval: Identifiable {
    let start: Date
    let end: Date

    var id: String { "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
    var midpoint: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
}

private struct StressChartSleepBadge: View {
    let start: Date
    let end: Date

    var body: some View {
        Image(systemName: "bed.double.fill")
            .symbolRenderingMode(.hierarchical)
            .font(.appSystem(size: 15, weight: .bold))
            .foregroundStyle(Color(hex: "4F5BC9"))
            .frame(width: 30, height: 24)
            .background(Theme.Colors.surface.opacity(0.98), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(hex: "6269E8").opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color(hex: "3946B7").opacity(0.14), radius: 4, x: 0, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("睡眠时段")
            .accessibilityValue("\(timeText(start))至\(timeText(end))")
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

private struct StressChartPoint: Identifiable {
    let timestamp: Int64
    let value: Double
    let isEstimated: Bool

    var id: Int64 { timestamp }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
}

private struct StressChartSelectionCard: View {
    let point: StressChartPoint
    let metricName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(point.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("\(metricName) \(Int(point.value.rounded())) / 100")
                    .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(stressColor(for: point.value))
            }

            Text(description(for: point))
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func description(for point: StressChartPoint) -> String {
        let timeText = point.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        switch StressRules.band(for: Int(point.value.rounded())) {
        case .waiting:
            return String(localized: "\(timeText) 这一段还没有足够数据判断压力状态。")
        case .relaxed:
            return String(localized: "\(timeText) 这一段综合压力处在较低区间，身体负荷相对平稳。")
        case .steady, .mild:
            return String(localized: "\(timeText) 这一段综合压力有一定抬升，但还在可控范围内。")
        case .caution, .high:
            return String(localized: "\(timeText) 这一段综合压力进入偏高区间，适合优先安排恢复。")
        }
    }

    private func stressColor(for value: Double) -> Color {
        switch StressRules.band(for: Int(value.rounded())) {
        case .waiting: return Theme.Colors.textTertiary
        case .relaxed: return Color(hex: "34C759")
        case .steady: return Color(hex: "007F79")
        case .mild: return Color(hex: "FF9F0A")
        case .caution: return Color(hex: "FF7A00")
        case .high: return Color(hex: "D70015")
        }
    }
}

private struct StressChartEmptyState: View {
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.appSystem(size: 32, weight: .semibold))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("暂无实时压力数据")
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textPrimary)
            if !text.isEmpty {
                Text(text)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
