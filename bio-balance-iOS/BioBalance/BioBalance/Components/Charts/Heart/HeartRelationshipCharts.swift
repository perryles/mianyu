import Charts
import Foundation
import SwiftUI

private enum HeartRelationshipKind: String, CaseIterable, Identifiable {
    case hrvAndRestingHeartRate
    case hrvAndHeartRate
    case heartRateAndWalkingHeartRate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hrvAndRestingHeartRate: return "恢复与静息"
        case .hrvAndHeartRate: return "恢复与心率"
        case .heartRateAndWalkingHeartRate: return "日常与步行"
        }
    }

    var systemImage: String {
        switch self {
        case .hrvAndRestingHeartRate: return "heart.text.square"
        case .hrvAndHeartRate: return "waveform.path.ecg"
        case .heartRateAndWalkingHeartRate: return "figure.walk"
        }
    }

    var xTitle: String {
        switch self {
        case .hrvAndRestingHeartRate, .hrvAndHeartRate: return "心率变异性（HRV）"
        case .heartRateAndWalkingHeartRate: return "心率"
        }
    }

    var yTitle: String {
        switch self {
        case .hrvAndRestingHeartRate: return "静息心率"
        case .hrvAndHeartRate: return "心率"
        case .heartRateAndWalkingHeartRate: return "步行平均心率"
        }
    }
}

private struct HeartRelationshipOption: Identifiable {
    var id: HeartRelationshipKind { kind }

    let kind: HeartRelationshipKind
    let xMetric: TrendCategoryMetricModel
    let yMetric: TrendCategoryMetricModel
}

/// 参考 AnxietyWatch 的相关性散点图，并补齐 Mianyu 所需的时间配对、基线象限、回归线和拖动读数。
struct HeartMetricRelationshipChartCard: View {
    let metrics: [TrendCategoryMetricModel]
    let range: TrendsRange
    var isStaticForExport: Bool = false

    @State private var selectedKind: HeartRelationshipKind = .hrvAndRestingHeartRate
    @State private var selectedPoint: HeartRelationshipPoint?
    @State private var hapticSelectionTick = 0
    @State private var showsThreeDimensions = false

    private let tint = Color(hex: "5E5CE6")
    private let regressionTint = Color(hex: "00A79D")

    private var options: [HeartRelationshipOption] {
        HeartRelationshipKind.allCases.compactMap { kind in
            guard let xMetric = metrics.first(where: { $0.title == kind.xTitle }),
                  let yMetric = metrics.first(where: { $0.title == kind.yTitle }),
                  !xMetric.points.isEmpty,
                  !yMetric.points.isEmpty else { return nil }
            return HeartRelationshipOption(kind: kind, xMetric: xMetric, yMetric: yMetric)
        }
    }

    private var activeOption: HeartRelationshipOption? {
        options.first(where: { $0.kind == selectedKind }) ?? options.first
    }

    private var points: [HeartRelationshipPoint] {
        guard let activeOption else { return [] }
        return HeartRelationshipAnalyzer.pairedPoints(
            xPoints: activeOption.xMetric.points,
            yPoints: activeOption.yMetric.points,
            range: range
        )
    }

    private var summary: HeartRelationshipSummary {
        HeartRelationshipAnalyzer.summary(for: points)
    }

    private var activePoint: HeartRelationshipPoint? {
        selectedPoint ?? points.last
    }

    private var threeDimensionalMetrics: (x: TrendCategoryMetricModel, y: TrendCategoryMetricModel, z: TrendCategoryMetricModel)? {
        // 三维模式固定使用语义明确且量纲独立的三项心率指标，避免随二维下拉选项改变坐标含义。
        guard let x = metrics.first(where: { $0.title == "心率变异性（HRV）" }),
              let y = metrics.first(where: { $0.title == "静息心率" }),
              let z = metrics.first(where: { $0.title == "心率" }) else { return nil }
        return (x, y, z)
    }

    private var threeDimensionalPoints: [HeartRelationship3DPoint] {
        guard let threeDimensionalMetrics else { return [] }
        return HeartRelationshipAnalyzer.triplePoints(
            xPoints: threeDimensionalMetrics.x.points,
            yPoints: threeDimensionalMetrics.y.points,
            zPoints: threeDimensionalMetrics.z.points,
            range: range
        )
    }

    private var xDomain: ClosedRange<Double> {
        paddedDomain(points.map(\.xValue))
    }

    private var yDomain: ClosedRange<Double> {
        paddedDomain(points.map(\.yValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BBChartHeader(
                title: "指标关系图",
                subtitle: "将同一时段的两项读数配对，观察它们是否经常一起变化。",
                systemImage: "chart.dots.scatter",
                tint: tint
            )

            if options.count > 1 {
                relationshipPicker
            }

            if let activeOption, !points.isEmpty {
                HStack(spacing: 8) {
                    BBChartMetricPill(
                        title: "配对样本",
                        value: "\(summary.sampleCount) 组",
                        tint: tint
                    )
                    BBChartMetricPill(
                        title: "相关系数",
                        value: correlationValueText,
                        tint: regressionTint
                    )
                    BBChartMetricPill(
                        title: "同步关系",
                        value: relationshipStrengthText,
                        tint: Color(hex: "F05275")
                    )
                }

                // Chart3D 仅在 iOS 26 可用；导出仍保持稳定、易阅读的二维静态图。
                if #available(iOS 26.0, *), !isStaticForExport, threeDimensionalPoints.count >= 3 {
                    HStack(spacing: 8) {
                        Text(showsThreeDimensions ? "旋转观察三项心率指标的聚类" : "2D 模式适合读取相关系数和回归趋势")
                            .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showsThreeDimensions.toggle()
                            }
                        } label: {
                            Label(showsThreeDimensions ? "查看 2D" : "探索 3D", systemImage: showsThreeDimensions ? "square" : "cube")
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .foregroundStyle(showsThreeDimensions ? Color.white : tint)
                                .background(showsThreeDimensions ? tint : tint.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if #available(iOS 26.0, *), showsThreeDimensions, !isStaticForExport, threeDimensionalPoints.count >= 3 {
                    relationshipChart3D
                } else {
                    relationshipChart(option: activeOption)
                }

                if let activePoint {
                    BBChartSelectionReadout(
                        title: TrendsSelectionFormatter.title(for: activePoint.date, range: range),
                        value: "\(formatted(activePoint.xValue, metric: activeOption.xMetric)) · \(formatted(activePoint.yValue, metric: activeOption.yMetric))",
                        detail: "\(activeOption.xMetric.title) · \(activeOption.yMetric.title)",
                        tint: tint
                    )
                }

                Text(relationshipFootnote)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TrendMetricEmptyStateView(
                    status: .noData,
                    title: "指标关系",
                    message: "至少需要两项心率指标在同一区间内有可配对样本，才能绘制关系图。",
                    accent: tint
                )
            }
        }
        .padding(16)
        .bbChartSurface(tint: tint, cornerRadius: 28)
        .sensoryFeedback(.selection, trigger: hapticSelectionTick)
        .onChange(of: selectedKind) { _, _ in
            selectedPoint = nil
        }
        .onChange(of: range) { _, _ in
            selectedPoint = nil
            showsThreeDimensions = false
        }
    }

    private var relationshipPicker: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                Button {
                    selectedKind = option.kind
                } label: {
                    Label(option.kind.title, systemImage: option.kind.systemImage)
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(activeOption?.kind == option.kind ? Color.white : Theme.Colors.textSecondary)
                        .background(
                            activeOption?.kind == option.kind ? tint : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(activeOption?.kind == option.kind ? .isSelected : [])
            }
        }
        .padding(4)
        .background(BBChartStyle.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func relationshipChart(option: HeartRelationshipOption) -> some View {
        Chart {
            if let meanX = summary.meanX {
                RuleMark(x: .value("X 均值", meanX))
                    .foregroundStyle(tint.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            if let meanY = summary.meanY {
                RuleMark(y: .value("Y 均值", meanY))
                    .foregroundStyle(tint.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            ForEach(summary.regressionLine) { item in
                LineMark(
                    x: .value(option.xMetric.title, item.xValue),
                    y: .value(option.yMetric.title, item.yValue),
                    series: .value("系列", "回归趋势")
                )
                .foregroundStyle(regressionTint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            ForEach(points) { point in
                PointMark(
                    x: .value(option.xMetric.title, point.xValue),
                    y: .value(option.yMetric.title, point.yValue)
                )
                .foregroundStyle(selectedPoint == nil || selectedPoint?.id == point.id ? tint : tint.opacity(0.35))
                .symbolSize(selectedPoint?.id == point.id ? 90 : 46)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                    .foregroundStyle(BBChartStyle.grid.opacity(0.72))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(axisValue(number))
                    }
                }
                .font(.appSystem(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                    .foregroundStyle(BBChartStyle.grid.opacity(0.72))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(axisValue(number))
                    }
                }
                .font(.appSystem(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartPlotStyle { plot in
            plot
                .padding(8)
                .bbChartPlotSurface(tint: tint, cornerRadius: 18)
        }
        .frame(height: 250)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrameAnchor = proxy.plotFrame {
                    let frame = geometry[plotFrameAnchor]
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .allowsHitTesting(!isStaticForExport)
                        .gesture(
                            LongPressGesture(minimumDuration: 0.18)
                                .sequenced(before: DragGesture(minimumDistance: 0))
                                .onChanged { value in
                                    guard case .second(true, let drag) = value, let drag else { return }
                                    updateScatterSelection(at: drag.location, frame: frame, proxy: proxy)
                                }
                        )
                }
            }
        }
        .accessibilityLabel("\(option.xMetric.title)与\(option.yMetric.title)关系图")
        .accessibilityValue("\(summary.sampleCount)组配对样本，相关系数\(correlationValueText)")
    }

    @available(iOS 26.0, *)
    private var relationshipChart3D: some View {
        // 3D 用于旋转观察聚类；相关系数和回归判断仍以默认二维图为准。
        Chart3D(threeDimensionalPoints) { point in
            PointMark(
                x: .value("HRV", point.xValue),
                y: .value("静息心率", point.yValue),
                z: .value("日常心率", point.zValue)
            )
            .foregroundStyle(tint)
        }
        .frame(height: 300)
        .accessibilityLabel("HRV、静息心率与日常心率三维关系图")
        .accessibilityValue("\(threeDimensionalPoints.count)组配对样本，可旋转图表观察聚类")
    }

    private var correlationValueText: String {
        guard let correlation = summary.correlation else { return "样本不足" }
        return String(format: "%.2f", correlation)
    }

    private var relationshipStrengthText: String {
        guard let correlation = summary.correlation else { return "待积累" }
        let magnitude = abs(correlation)
        let strength: String
        switch magnitude {
        case 0.7...: strength = "较明显"
        case 0.4..<0.7: strength = "中等"
        case 0.2..<0.4: strength = "较弱"
        default: strength = "不明显"
        }
        guard magnitude >= 0.2 else { return strength }
        return correlation > 0 ? "同向\(strength)" : "反向\(strength)"
    }

    private var relationshipFootnote: String {
        if summary.correlation == nil {
            return String(localized: "当前先展示已配对读数；至少 3 组且两项指标都有变化时，才计算相关系数与回归趋势。")
        }
        return String(localized: "虚线表示两项指标各自的区间均值，绿色线表示线性趋势。相关性只描述同步变化，不代表因果或医学诊断。")
    }

    private func updateScatterSelection(at location: CGPoint, frame: CGRect, proxy: ChartProxy) {
        guard frame.contains(location), !points.isEmpty else { return }
        let localPoint = CGPoint(x: location.x - frame.minX, y: location.y - frame.minY)
        let nearest = points.min { lhs, rhs in
            scatterDistance(from: lhs, to: localPoint, proxy: proxy) < scatterDistance(from: rhs, to: localPoint, proxy: proxy)
        }
        guard nearest?.id != selectedPoint?.id else { return }
        selectedPoint = nearest
        hapticSelectionTick += 1
    }

    private func scatterDistance(from point: HeartRelationshipPoint, to location: CGPoint, proxy: ChartProxy) -> CGFloat {
        guard let x = proxy.position(forX: point.xValue),
              let y = proxy.position(forY: point.yValue) else { return .greatestFiniteMagnitude }
        return hypot(x - location.x, y - location.y)
    }

    private func formatted(_ value: Double, metric: TrendCategoryMetricModel) -> String {
        TrendMetricValueFormatter.string(for: value, unit: metric.unit)
    }

    private func axisValue(_ value: Double) -> String {
        if abs(value) >= 100 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    private func paddedDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let spread = max(maximum - minimum, max(abs(maximum), 1) * 0.08)
        let padding = max(spread * 0.16, 0.5)
        return (minimum - padding)...(maximum + padding)
    }
}
