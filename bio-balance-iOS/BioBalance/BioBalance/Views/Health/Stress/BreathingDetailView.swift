/// BreathingDetailView 由压力模块呼吸入口调用，作为「呼吸训练」详情页。
/// 负责展示呼吸训练 Hero、趋势图表与指导卡片。

import SwiftUI
import Charts

/// 呼吸视图 由上级页面或路由调用，作为压力模块里的界面或内容组件。
/// 负责展示压力状态、记录、分析结果以及调节建议。
struct BreathingDetailView: View {
    @State private var viewModel = BreathingMindfulnessViewModel()

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: HealthDetailDesignSystem.sectionSpacing) {
                    heroCard
                    chartCard
                    guidanceCard
                }
                .padding(.horizontal, HealthDetailDesignSystem.pageHorizontalPadding)
                .padding(.top, HealthDetailDesignSystem.pageTopPadding)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("呼吸")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.reload()
        }
        .onChange(of: viewModel.range) { _, _ in
            viewModel.reload()
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(alignment: .top, spacing: Theme.Spacing.small) {
                VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                    Text("呼吸频率")
                        .font(Theme.Typography.pageTitle)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("来自健康 App 的呼吸频率记录，用于观察恢复和睡眠状态。")
                        .font(Theme.Typography.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    viewModel.requestAuthorizationAndReload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.appSystem(size: 16, weight: .bold))
                        .foregroundColor(Theme.Colors.mintGreen)
                        .frame(width: 40, height: 40)
                        .background(Theme.Colors.mintGreen.opacity(0.11), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: Theme.Spacing.compact) {
                metric(title: "最新", value: formatted(viewModel.latestValue), unit: "次/分")
                metric(title: "平均", value: formatted(viewModel.averageValue), unit: "次/分")
                metric(title: "范围", value: rangeText, unit: "")
            }
        }
        .healthDetailSurface()
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("趋势")
                        .font(Theme.Typography.cardTitle)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("横轴为记录时间")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                Picker("", selection: $viewModel.range) {
                    ForEach(BreathingMindfulnessViewModel.Range.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 132)
            }

            if viewModel.isLoading {
                ProgressView("正在读取健康 App 数据")
                    .frame(maxWidth: .infinity)
                    .frame(height: 230)
            } else if viewModel.points.isEmpty {
                emptyState
                    .frame(height: 230)
            } else {
                Chart(viewModel.points) { point in
                    AreaMark(
                        x: .value("时间", point.date),
                        y: .value("呼吸", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.Colors.mintGreen.opacity(0.24), Theme.Colors.mintGreen.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("呼吸", point.value)
                    )
                    .foregroundStyle(Theme.Colors.mintGreen)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 230)
                .chartPlotStyle { plotArea in
                    plotArea.clipped()
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day(.defaultDigits).hour(.twoDigits(amPM: .omitted)))
                            .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Theme.Colors.textTertiary.opacity(0.16))
                        AxisValueLabel()
                            .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }

            if let message = viewModel.errorMessage {
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .healthDetailSurface()
    }

    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("解读")
                .font(Theme.Typography.cardTitle)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(guidanceText)
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                viewModel.range = .day
                viewModel.reload()
            } label: {
                Text("查看今日")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.mintGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.small)
                    .background(Theme.Colors.mintGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .healthDetailSurface()
    }

    private var rangeText: String {
        guard let min = viewModel.minValue, let max = viewModel.maxValue else { return "--" }
        return "\(formatted(min))-\(formatted(max))"
    }

    private var guidanceText: String {
        guard let avg = viewModel.averageValue else {
            return String(localized: "授权健康 App 并佩戴设备记录后，这里会显示呼吸频率趋势。")
        }
        if avg < 12 {
            return String(localized: "平均呼吸频率偏低，若伴随不适请留意身体状态。")
        }
        if avg <= 20 {
            return String(localized: "平均呼吸频率处于常见平稳区间，恢复节奏较稳定。")
        }
        return String(localized: "平均呼吸频率偏高，建议结合压力、睡眠和心率变化一起观察。")
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.compact) {
            Image(systemName: "wind")
                .font(.appSystem(size: 28, weight: .semibold))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("暂无呼吸频率记录")
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func metric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.compact)
        .background(Theme.Colors.mintGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f", value)
    }
}
