/// HRVBaselineNightAnalysisView 由 HRV 详情的「夜间 HRV 基线」入口调用。
/// 负责展示夜间 HRV 基线趋势与 14 天对比。

import SwiftUI
import Charts

/// 负责展示睡眠记录、恢复分析以及睡眠与其他指标的关联。
struct HRVBaselineNightAnalysisView: View {
    @State private var viewModel = HRVBaselineViewModel()
    @State private var days: Int = 14
    
    private struct Point: Identifiable {
        let id: String
        let date: Date
        let value: Double
        
        init(date: Date, value: Double) {
            self.date = date
            self.value = value
            self.id = "\(date.timeIntervalSince1970)"
        }
    }
    
    private var points: [Point] {
        viewModel.nights.map { Point(date: $0.date, value: $0.avgMs) }
    }
    
    private var deltaText: String? {
        guard let base = viewModel.baselineMs, let last = viewModel.lastNightMs, base > 0 else { return nil }
        let pct = (last - base) / base * 100.0
        let sign = pct >= 0 ? "+" : ""
        return String(format: "%@%.0f%%", sign, pct)
    }

    private var baselineQualityText: String {
        let state = viewModel.baselineState
        guard state.isUsable else {
            return String(localized: "样本不足 · 还差 \(state.remainingSamplesUntilUsable) 夜 · Apple Health · SDNN")
        }
        let trust = state.isTrusted ? "稳定估算" : "估算基线 · 距稳定还差 \(state.remainingSamplesUntilTrusted) 夜"
        return String(localized: "\(trust) · Apple Health · SDNN · \(state.sampleCount) 夜")
    }
    
    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: HealthDetailDesignSystem.sectionSpacing) {
                    Picker("天数", selection: $days) {
                        Text("7天").tag(7)
                        Text("14天").tag(14)
                        Text("30天").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.black)
                    
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(Theme.Colors.textPrimary)
                            .padding(.top, 24)
                    } else if let msg = viewModel.errorMessage {
                        Text(msg)
                            .font(Theme.Typography.cardTitle)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(.top, 24)
                    } else if viewModel.nights.isEmpty {
                        Text("暂无夜间 HRV 数据")
                            .font(Theme.Typography.cardTitle)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(.top, 24)
                    } else {
                        headlineCard
                        trendCard
                        listCard
                    }
                }
                .padding(.horizontal, HealthDetailDesignSystem.pageHorizontalPadding)
                .padding(.top, HealthDetailDesignSystem.pageTopPadding)
                .padding(.bottom, Theme.Spacing.section)
            }
        }
        .navigationTitle("HRV 基线 / 夜间")
        .onAppear {
            viewModel.load(days: days)
        }
        .onChange(of: days) {
            viewModel.load(days: days)
        }
    }
    
    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("概览")
                .font(Theme.Typography.cardTitle)
                .foregroundColor(Theme.Colors.textPrimary)
            
            HStack(spacing: Theme.Spacing.medium) {
                metric(title: "基线(中位数)", value: valueText(viewModel.baselineMs), unit: "ms")
                metric(title: "昨夜均值", value: valueText(viewModel.lastNightMs), unit: "ms", badge: deltaText)
            }

            Label(baselineQualityText, systemImage: viewModel.baselineState.isUsable ? "checkmark.shield" : "hourglass")
                .font(Theme.Typography.label)
                .foregroundColor(Theme.Colors.textSecondary)
            
            Text("基线用于衡量你在相对放松状态下的长期水平；夜间均值更接近恢复状态，可用于观察压力与疲劳累积。")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .healthDetailSurface()
    }
    
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("夜间 HRV 趋势")
                .font(Theme.Typography.cardTitle)
                .foregroundColor(Theme.Colors.textPrimary)
            
            Chart {
                ForEach(points) { p in
                    LineMark(
                        x: .value("日期", p.date),
                        y: .value("HRV", p.value)
                    )
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .interpolationMethod(.catmullRom)
                    
                    PointMark(
                        x: .value("日期", p.date),
                        y: .value("HRV", p.value)
                    )
                    .foregroundStyle(Theme.Colors.mintGreen)
                }
                
                if let base = viewModel.baselineMs {
                    RuleMark(y: .value("Baseline", base))
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(0.7))
                }
            }
            .frame(height: 240)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.month().day())
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine().foregroundStyle(Theme.Colors.textTertiary.opacity(0.2))
                    AxisValueLabel().foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .healthDetailSurface()
    }
    
    private var listCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("明细")
                .font(Theme.Typography.cardTitle)
                .foregroundColor(Theme.Colors.textPrimary)
            
            ForEach(viewModel.nights.suffix(30).reversed()) { n in
                HStack {
                    Text(n.date.formatted(.dateTime.month().day()))
                        .font(.appSystem(.caption, design: .monospaced))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Spacer()
                    Text("\(Int(n.avgMs.rounded())) ms")
                        .font(.appSystem(.caption, design: .monospaced).weight(.semibold))
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                .padding(.vertical, 6)
            }
        }
        .healthDetailSurface()
    }
    
    private func metric(title: String, value: String, unit: String, badge: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            HStack(spacing: Theme.Spacing.compact) {
                Text(title)
                    .font(Theme.Typography.supporting)
                    .foregroundColor(Theme.Colors.textTertiary)
                if let badge {
                    Text(badge)
                        .font(Theme.Typography.label)
                        .foregroundColor(Theme.Colors.mintGreen)
                        .padding(.horizontal, Theme.Spacing.compact)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.mintGreen.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.Typography.pageTitle)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(unit)
                    .font(Theme.Typography.label)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func valueText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))"
    }
}

#Preview {
    NavigationStack {
        HRVBaselineNightAnalysisView()
    }
}
