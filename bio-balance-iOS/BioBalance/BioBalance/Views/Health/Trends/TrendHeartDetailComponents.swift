/// HeartHealthMetricTrendCard 由 TrendCategoryDetailView 心率详情区调用，作为「核心心率趋势」单项指标卡片。
/// 负责展示单个心率指标的图表、当前值、区间均值、状态说明与趋势解读。

import SwiftUI
import Charts


/// Heart Health Metric Trend Card 由 [TrendCategoryDetailView] 内的心率详情区调用，作为“核心心率趋势”里的单项指标卡。
/// 负责展示单个心率指标的图表、当前值、区间均值、状态说明和趋势解读。
struct HeartHealthMetricTrendCard: View {
    let metric: TrendCategoryMetricModel
    let range: TrendsRange
    var isStaticForExport: Bool = false

    @State private var selectedPoint: TimeSeriesPointDouble?

    private var tint: Color { Color(hex: metric.accentHex) }

    // 心率与睡眠恢复统一日轴口径，单点时放到中午，避免整张图因为边界过窄而失真。
    private var chartPoints: [TimeSeriesPointDouble] {
        guard range == .day, metric.points.count == 1, let point = metric.points.first else {
            return metric.points.sorted { $0.date < $1.date }
        }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: point.date)
        let noon = calendar.date(byAdding: .hour, value: 12, to: startOfDay) ?? point.date
        return [TimeSeriesPointDouble(timestamp: Int64(noon.timeIntervalSince1970), value: point.value)]
    }

    private var hasTrendBaseline: Bool {
        chartPoints.count >= 2
    }

    private var averageValue: Double? {
        guard hasTrendBaseline else { return nil }
        return chartPoints.map(\.value).reduce(0, +) / Double(chartPoints.count)
    }

    private var latestValue: Double? {
        selectedPoint?.value ?? chartPoints.last?.value
    }

    private var latestValueText: String {
        guard let latestValue else { return "--" }
        return TrendMetricValueFormatter.string(for: latestValue, unit: metric.unit)
    }

    private var averageValueText: String {
        guard let averageValue else { return "--" }
        return TrendMetricValueFormatter.string(for: averageValue, unit: metric.unit)
    }

    private var peakValueText: String {
        guard let peak = chartPoints.map(\.value).max() else { return "--" }
        return TrendMetricValueFormatter.string(for: peak, unit: metric.unit)
    }

    private var statusText: String {
        guard hasTrendBaseline else {
            return String(localized: "\(metric.title) 当前样本不足，至少需要 2 个真实样本后才能形成趋势判断。")
        }
        guard let latestValue, let averageValue else {
            return String(localized: "继续同步健康样本后，这里会形成更稳定的心率趋势判断。")
        }
        let delta = latestValue - averageValue
        if abs(delta) <= max(0.1, abs(averageValue) * 0.05) {
            return String(localized: "\(metric.title) 与近期基线接近，当前整体还处在相对稳定的负荷区间。")
        }
        if delta > 0 {
            return String(localized: "\(metric.title) 当前高于近期基线，更适合继续结合 ECG 与监测记录一起判断负荷变化。")
        }
        return String(localized: "\(metric.title) 当前低于近期基线，建议继续结合恢复状态与近期活动负荷一起理解。")
    }

    private var detailText: String {
        guard hasTrendBaseline else {
            return String(localized: "当前样本不足，继续积累记录后再与近期基线比较。")
        }
        guard let latestValue, let averageValue else {
            return String(localized: "先看近期趋势，再判断单次波动是否值得重点关注。")
        }
        let delta = latestValue - averageValue
        let deltaText = TrendMetricValueFormatter.string(for: abs(delta), unit: metric.unit)
        if abs(delta) <= max(0.1, abs(averageValue) * 0.05) {
            return String(localized: "当前值与近期基线接近，短期内没有出现明显偏离。")
        }
        return delta > 0 ? "当前值较近期基线高 \(deltaText)。" : "当前值较近期基线低 \(deltaText)。"
    }

    private var yDomain: ClosedRange<Double> {
        let values = chartPoints.map(\.value) + [averageValue].compactMap { $0 }
        let domain = TrendYAxisDesigner.domain(for: values.isEmpty ? [0, 1] : values, range: range)
        if heartZeroBasedMetricTitles.contains(metric.title) {
            return 0...max(domain.upperBound, 1)
        }
        return domain
    }

    private var axisValues: [Double] {
        TrendYAxisDesigner.axisValues(for: yDomain, range: range)
    }

    private var dateDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        switch range {
        case .day:
            let start = calendar.startOfDay(for: chartPoints.first?.date ?? metric.points.first?.date ?? Date())
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return start...end
        case .week, .month:
            let start = calendar.startOfDay(for: range.startDate)
            let end = calendar.date(byAdding: .day, value: range.windowDays, to: start) ?? start
            return start...end
        }
    }

    private var axisDates: [Date] {
        TrendsSelectionFormatter.axisDates(for: range, dateDomain: dateDomain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BBChartHeader(
                title: metric.title,
                subtitle: statusText,
                systemImage: "heart.text.square.fill",
                tint: tint
            )

            HStack(spacing: 8) {
                heartMetricChip(title: "当前", value: latestValueText)
                heartMetricChip(title: "基线", value: averageValueText)
                heartMetricChip(title: "高点", value: peakValueText)
            }

            if chartPoints.isEmpty {
                TrendMetricEmptyStateView(
                    status: metric.status,
                    title: metric.title,
                    message: metric.emptyMessage,
                    accent: tint
                )
            } else {
                Chart(chartPoints) { item in
                    LineMark(
                        x: .value("时间", item.date),
                        y: .value(metric.title, item.value)
                    )
                    .foregroundStyle(tint.opacity(selectedPoint == nil || selectedPoint?.timestamp == item.timestamp ? 0.94 : 0.52))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("时间", item.date),
                        y: .value(metric.title, item.value)
                    )
                    .foregroundStyle(Theme.Colors.onAccent)
                    .symbolSize(selectedPoint?.timestamp == item.timestamp ? 84 : (item.timestamp == chartPoints.last?.timestamp ? 64 : 28))
                    .annotation(position: .overlay, alignment: .center) {
                        Circle()
                            .fill(tint)
                            .frame(
                                width: selectedPoint?.timestamp == item.timestamp ? 10 : (item.timestamp == chartPoints.last?.timestamp ? 9 : 7),
                                height: selectedPoint?.timestamp == item.timestamp ? 10 : (item.timestamp == chartPoints.last?.timestamp ? 9 : 7)
                            )
                    }
                    .opacity(selectedPoint == nil || selectedPoint?.timestamp == item.timestamp ? 1 : 0.42)

                    if let averageValue {
                        RuleMark(y: .value("近期基线", averageValue))
                            .foregroundStyle(tint.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    if let selectedPoint, selectedPoint.timestamp == item.timestamp {
                        RuleMark(x: .value("选中", item.date))
                            .foregroundStyle(tint.opacity(0.24))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .frame(height: 216)
                .padding(.top, 6)
                .padding(.leading, 6)
                .chartLegend(.hidden)
                .chartYScale(domain: yDomain)
                .chartXScale(domain: dateDomain)
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.08))
                        AxisValueLabel(centered: true) {
                            if let date = value.as(Date.self) {
                                Text(heartAxisLabel(for: date))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.72)
                                    .font(.system(size: range == .week ? 8.5 : 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: axisValues) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.08))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(heartAxisValueText(number))
                            }
                        }
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .padding(.top, 6)
                        .padding(.leading, 10)
                        .padding(.trailing, 8)
                        .padding(.bottom, 10)
                        .bbChartPlotSurface(tint: tint, cornerRadius: 18)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let plotFrame = proxy.plotFrame {
                            let frame = geometry[plotFrame]
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .allowsHitTesting(!isStaticForExport)
                                .gesture(
                                    LongPressGesture(minimumDuration: 0.2)
                                        .sequenced(before: DragGesture(minimumDistance: 12))
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
            }

            if let selectedPoint {
                BBChartSelectionReadout(
                    title: TrendsSelectionFormatter.title(for: selectedPoint.date, range: range),
                    value: TrendMetricValueFormatter.string(for: selectedPoint.value, unit: metric.unit),
                    detail: selectionDescription(for: selectedPoint),
                    tint: tint
                )
            }

            Text(detailText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .bbChartSurface(tint: tint, cornerRadius: 28)
        .onAppear {
            TrendDebugLogger.logMetricChart(
                source: "心率指标趋势卡",
                metric: metric,
                range: range,
                rawPoints: metric.points.sorted { $0.date < $1.date },
                renderedPoints: chartPoints,
                xDomain: dateDomain,
                xAxisDates: axisDates,
                yDomain: yDomain,
                yAxisValues: axisValues
            )
        }
    }

    private func heartMetricChip(title: String, value: String) -> some View {
        BBChartMetricPill(title: title, value: value, tint: tint)
    }

    private func updateSelection(at location: CGPoint, frame: CGRect, proxy: ChartProxy) {
        guard frame.contains(location) else { return }
        let relativeX = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: relativeX) else { return }
        selectedPoint = chartPoints.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    private func selectionDescription(for point: TimeSeriesPointDouble) -> String {
        guard hasTrendBaseline else {
            return String(localized: "当前样本不足，至少需要 2 个真实样本后才能判断与近期基线的差异。")
        }
        guard let averageValue else {
            return String(localized: "当前样本已记录，继续积累更多天后更适合做基线判断。")
        }
        let delta = point.value - averageValue
        let deltaText = TrendMetricValueFormatter.string(for: abs(delta), unit: metric.unit)
        if abs(delta) <= max(0.1, abs(averageValue) * 0.05) {
            return String(localized: "这一时点与近期基线接近，变化相对平稳。")
        }
        return delta > 0 ? "这一时点高于近期基线 \(deltaText)。" : "这一时点低于近期基线 \(deltaText)。"
    }

    private func heartAxisLabel(for date: Date) -> String {
        let label = TrendsSelectionFormatter.axisLabel(for: date, range: range)
        if range == .day, label == "24时" {
            return "24:00"
        }
        return label
    }

    private func heartAxisValueText(_ value: Double) -> String {
        let text = TrendMetricValueFormatter.string(for: value, unit: metric.unit)
        if metric.unit.isEmpty {
            return text
        }
        if text.hasSuffix(metric.unit) {
            return String(text.dropLast(metric.unit.count))
        }
        return text
    }

    private let heartZeroBasedMetricTitles = ["心率变异性（HRV）", "血压", "高血压通知"]
}

/// Heart ECG Section 由 [TrendCategoryDetailView] 内的心率详情区调用，作为“心电图（ECG）”阅读区块。
/// 负责展示最近 ECG 记录、关键参数和波形预览，帮助用户把离散心电记录和连续心率趋势一起阅读。
struct HeartECGSection: View {
    let summary: HeartECGSummaryModel
    let records: [HeartECGRecordModel]
    @State private var selectedRecordID: String?

    private var selectedRecord: HeartECGRecordModel? {
        if let selectedRecordID,
           let matched = records.first(where: { $0.id == selectedRecordID }) {
            return matched
        }
        return records.first ?? summary.latestRecord
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            topSummaryCard

            if let selectedRecord {
                if records.count > 1 {
                    historySelector
                }
                metricRow(for: selectedRecord)
                waveformCard(for: selectedRecord)
            } else {
                TrendMetricEmptyStateView(
                    status: summary.status,
                    title: "心电图（ECG）",
                    message: summary.detail,
                    accent: Color(hex: "F05275")
                )
            }
        }
        .onAppear {
            if selectedRecordID == nil {
                selectedRecordID = records.first?.id ?? summary.latestRecord?.id
            }
        }
        .onChange(of: records) { _, newRecords in
            guard let first = newRecords.first else {
                selectedRecordID = nil
                return
            }
            if let selectedRecordID, newRecords.contains(where: { $0.id == selectedRecordID }) {
                return
            }
            selectedRecordID = first.id
        }
    }

    private var topSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.headline)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(summary.detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text(summary.recordCountText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "F05275"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: "F05275").opacity(0.10), in: Capsule())
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.96), Color(hex: "F05275").opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(hex: "F2D7DD"), lineWidth: 1)
        )
    }

    private func metricRow(for record: HeartECGRecordModel) -> some View {
        let items: [(String, String)] = [
            ("记录时间", TrendsSelectionFormatter.title(for: record.sampledAt, range: .day)),
            ("平均心率", record.averageHeartRateText),
            ("采样频率", record.samplingFrequencyText),
            ("采样时长", record.durationText),
            ("症状状态", record.symptomsStatusText)
        ]

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(item.1)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.Colors.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var historySelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("历史记录")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text("可切换查看以往 ECG")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(records) { record in
                        historyPill(for: record)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func historyPill(for record: HeartECGRecordModel) -> some View {
        let isSelected = selectedRecord?.id == record.id

        return Button {
            selectedRecordID = record.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(TrendsSelectionFormatter.title(for: record.sampledAt, range: .day))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? Color(hex: "F05275") : Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(record.classificationTitle)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(record.averageHeartRateText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 136, alignment: .leading)
            .padding(12)
            .background(
                (isSelected ? Color(hex: "F05275").opacity(0.12) : Color.white.opacity(0.88)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color(hex: "F05275").opacity(0.28) : Color.black.opacity(0.04), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func waveformCard(for record: HeartECGRecordModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("波形预览")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(record.classificationTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "F05275"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "F05275").opacity(0.10), in: Capsule())
            }

            Text(record.classificationDetail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if record.voltagePoints.isEmpty {
                TrendMetricEmptyStateView(
                    status: .noData,
                    title: "ECG 波形",
                    message: "当前记录未返回可展示的 ECG 波形点列。",
                    accent: Color(hex: "F05275")
                )
            } else {
                Chart(record.voltagePoints) { point in
                    LineMark(
                        x: .value("时间", point.timeOffset),
                        y: .value("电压", point.millivolts)
                    )
                    .foregroundStyle(Color(hex: "F05275"))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Theme.Colors.textTertiary.opacity(0.10))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(String(format: "%.1f", number))
                            }
                        }
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom, values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(String(format: "%.1fs", number))
                            }
                        }
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .frame(height: 180)
                .padding(10)
                .background(Theme.Colors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(16)
        .background(Color(hex: "F05275").opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Heart Clinical Monitoring Section 由 [TrendCategoryDetailView] 内的心率详情区调用，作为“监测与告警”阅读区块。
/// 负责集中展示房颤历史、高心率通知、低心率通知、高血压通知和血压相关监测摘要。
struct HeartClinicalMonitoringSection: View {
    let summary: HeartClinicalMonitorSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.headline)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(summary.detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(summary.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.title)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                            Spacer(minLength: 8)
                            Text(item.status.title)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(item.status.tint)
                        }
                        Text(item.value)
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(item.detail)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.Colors.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
