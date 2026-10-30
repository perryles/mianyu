/// BehaviorImpactView 由报告页「深入分析 → 行为影响」入口调用。
/// 负责展示饮水/咖啡因等生活行为与睡眠压力的同步变化散点图，帮助发现关联线索。

import Charts
import Foundation
import SwiftUI

/// 展示生活行为与健康结果的同步变化。相关性用于帮助用户发现线索，不代表因果关系或医学诊断。
struct BehaviorImpactView: View {
    @State private var days: Int = 14
    @State private var data: [DailySleepStressAnalytics] = []
    @State private var isLoading = false
    @State private var selectedWaterX: Double?
    @State private var selectedCaffeineX: Double?

    private var sorted: [DailySleepStressAnalytics] {
        data.sorted { $0.date < $1.date }
    }

    private var waterPoints: [BehaviorImpactPoint] {
        sorted.compactMap { item in
            guard let rate = item.water_completion_rate,
                  let stress = item.avg_stress,
                  rate.isFinite else { return nil }
            return BehaviorImpactPoint(date: item.date, x: rate * 100, y: Double(stress))
        }
    }

    private var caffeinePoints: [BehaviorImpactPoint] {
        sorted.compactMap { item in
            guard let caffeine = item.caffeine_remained_mg,
                  let score = item.sleep_score,
                  caffeine.isFinite else { return nil }
            return BehaviorImpactPoint(date: item.date, x: caffeine, y: Double(score))
        }
    }

    var body: some View {
        ZStack {
            HealthDetailPageBackground()

            AdaptivePageScrollView(style: .reading, topPadding: 18, bottomPadding: 96) {
                VStack(spacing: 16) {
                    Picker("天数", selection: $days) {
                        Text("7天").tag(7)
                        Text("14天").tag(14)
                        Text("30天").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .tint(Theme.Colors.mintGreen)

                    if isLoading {
                        ProgressView().tint(Theme.Colors.textPrimary)
                            .padding(.top, 24)
                    } else if data.isEmpty {
                        Text("暂无分析数据")
                            .font(.appSystem(.headline, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(.top, 24)
                    } else {
                        impactCard(
                            title: "喝水完成率 vs 压力",
                            subtitle: "观察补水完成度和平均压力是否同步变化。",
                            points: waterPoints,
                            tint: Theme.Colors.mintGreen,
                            xTitle: "喝水完成率",
                            yTitle: "平均压力",
                            xUnit: "%",
                            yUnit: "",
                            xDomain: 0...120,
                            yDomain: 0...100,
                            referenceY: 70,
                            selectedX: $selectedWaterX
                        )

                        impactCard(
                            title: "咖啡因残留 vs 睡眠得分",
                            subtitle: "观察咖啡因残留和睡眠得分之间的关联。",
                            points: caffeinePoints,
                            tint: Color(hex: "A2845E"),
                            xTitle: "咖啡因残留",
                            yTitle: "睡眠得分",
                            xUnit: "mg",
                            yUnit: "分",
                            xDomain: paddedDomain(caffeinePoints.map(\.x), lowerBound: 0),
                            yDomain: 0...100,
                            referenceY: 70,
                            selectedX: $selectedCaffeineX
                        )
                    }
                }
                .padding(.vertical)
            }
        }
        .healthDetailNavigation(title: HealthPageName.behaviorImpact)
        .onAppear { load() }
        .onChange(of: days) { _, _ in
            selectedWaterX = nil
            selectedCaffeineX = nil
            load()
        }
    }

    private func impactCard(
        title: String,
        subtitle: String,
        points: [BehaviorImpactPoint],
        tint: Color,
        xTitle: String,
        yTitle: String,
        xUnit: String,
        yUnit: String,
        xDomain: ClosedRange<Double>,
        yDomain: ClosedRange<Double>,
        referenceY: Double,
        selectedX: Binding<Double?>
    ) -> some View {
        let summary = BehaviorImpactAnalyzer.summary(for: points)
        // Swift Charts 返回连续的 X 坐标；吸附到最近样本，读数卡才会显示真实采集值。
        let selectedPoint = selectedX.wrappedValue.flatMap { selected in
            points.min { abs($0.x - selected) < abs($1.x - selected) }
        } ?? points.last

        return VStack(alignment: .leading, spacing: 12) {
            ReportsSectionHeader(title, subtitle: subtitle)

            if points.isEmpty {
                ReportsInlineEmptyState(text: "这一周期还没有足够的配对数据")
            } else {
                HStack(spacing: 8) {
                    BBChartMetricPill(title: "配对样本", value: "\(summary.sampleCount) 组", tint: tint)
                    BBChartMetricPill(title: "相关系数", value: correlationText(summary.correlation), tint: tint)
                    BBChartMetricPill(title: "同步关系", value: relationshipText(summary.correlation), tint: tint)
                }

                Chart {
                    if let meanX = summary.meanX {
                        // 均值线帮助判断样本位于个人本周期基线的哪一侧，不代表健康阈值。
                        RuleMark(x: .value("X 均值", meanX))
                            .foregroundStyle(tint.opacity(0.18))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    // 70 是产品既有的压力/睡眠参考线，与统计回归线使用不同视觉层级。
                    RuleMark(y: .value("参考值", referenceY))
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(0.24))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))

                    ForEach(summary.regressionLine) { point in
                        LineMark(
                            x: .value(xTitle, point.x),
                            y: .value(yTitle, point.y),
                            series: .value("系列", "回归趋势")
                        )
                        .foregroundStyle(tint.opacity(0.82))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }

                    ForEach(points) { point in
                        PointMark(
                            x: .value(xTitle, point.x),
                            y: .value(yTitle, point.y)
                        )
                        .foregroundStyle(selectedPoint?.id == point.id ? tint : tint.opacity(0.48))
                        .symbolSize(selectedPoint?.id == point.id ? 86 : 42)
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("当前选择", selectedPoint.x))
                            .foregroundStyle(tint.opacity(0.28))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                }
                .chartXScale(domain: xDomain)
                .chartYScale(domain: yDomain)
                .chartXSelection(value: selectedX)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(BBChartStyle.grid.opacity(0.72))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(axisText(number, unit: xUnit))
                            }
                        }
                        .font(.appSystem(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(BBChartStyle.grid.opacity(0.72))
                        AxisValueLabel()
                            .font(.appSystem(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .frame(height: 230)
                .chartPlotStyle { plotArea in
                    plotArea
                        .padding(6)
                        .background(ReportsChartStyle.plotBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityLabel("\(title)散点图")
                .accessibilityValue("\(summary.sampleCount)组样本，相关系数\(correlationText(summary.correlation))，\(relationshipText(summary.correlation))")

                if let selectedPoint {
                    BBChartSelectionReadout(
                        title: selectedPoint.date,
                        value: "\(valueText(selectedPoint.x, unit: xUnit)) · \(valueText(selectedPoint.y, unit: yUnit))",
                        detail: "\(xTitle) · \(yTitle)",
                        tint: tint
                    )
                }

                Text(footnote(summary.correlation))
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.90), lineWidth: 1))
    }

    private func paddedDomain(_ values: [Double], lowerBound: Double) -> ClosedRange<Double> {
        guard let maximum = values.max(), maximum > lowerBound else { return lowerBound...(lowerBound + 100) }
        return lowerBound...max(lowerBound + 20, ceil(maximum * 1.12 / 10) * 10)
    }

    private func axisText(_ value: Double, unit: String) -> String {
        "\(Int(value.rounded()))\(unit)"
    }

    private func valueText(_ value: Double, unit: String) -> String {
        let number = abs(value.rounded() - value) < 0.05 ? String(Int(value.rounded())) : String(format: "%.1f", value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    private func correlationText(_ correlation: Double?) -> String {
        correlation.map { String(format: "%.2f", $0) } ?? "样本不足"
    }

    private func relationshipText(_ correlation: Double?) -> String {
        guard let correlation else { return "待积累" }
        let magnitude = abs(correlation)
        let strength: String
        switch magnitude {
        case 0.7...: strength = "较明显"
        case 0.4..<0.7: strength = "中等"
        case 0.2..<0.4: strength = "较弱"
        default: return "不明显"
        }
        return correlation > 0 ? "同向\(strength)" : "反向\(strength)"
    }

    private func footnote(_ correlation: Double?) -> String {
        if correlation == nil {
            return String(localized: "至少 3 组且两项数据都有变化时，才计算相关系数与回归趋势。")
        }
        return String(localized: "虚线表示区间均值，实线表示线性趋势。相关性只描述同步变化，不代表因果或医学诊断。")
    }

    private func load() {
        isLoading = true
        Task {
            // 本地优先：无自建后端，行为影响分析以本机数据为准。
            data = []
            isLoading = false
        }
    }
}
