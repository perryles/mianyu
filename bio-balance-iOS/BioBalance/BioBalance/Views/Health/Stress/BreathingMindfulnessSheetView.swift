/// BreathingMindfulnessSheetView 由每日打卡与压力模块调用，作为「呼吸正念」弹层。
/// 负责提供呼吸引导动画、练习记录与趋势展示。

import SwiftUI
import Charts

/// 呼吸正念视图 由上级页面或路由调用，作为压力模块里的界面或内容组件。
/// 负责展示压力状态、记录、分析结果以及调节建议。
struct BreathingMindfulnessSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = BreathingMindfulnessViewModel()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.secondaryBackground
                    .ignoresSafeArea()
                sheetAmbientBackground
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerCard
                        overviewCard
                        rhythmCard
                        trendCard
                        guidanceCard
                        noteCard
                    }
                    .padding(Theme.Layout.padding)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("呼吸正念")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.prepareSession()
                viewModel.reload()
            }
            .onChange(of: viewModel.selectedSessionLength) { _, _ in
                viewModel.prepareSession()
            }
        }
    }
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("呼吸正念")
                        .font(.appSystem(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(Theme.Colors.textPrimary)
                    
                    Text("查看呼吸趋势与正念练习状态")
                        .font(.appSystem(.subheadline, design: .default))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                
                Spacer()
                
                if viewModel.isLoading {
                    ProgressView()
                        .tint(Theme.Colors.textPrimary)
                }
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(valueText(viewModel.latestValue))
                    .font(.appSystem(size: 56, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text("次/分")
                    .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            
            Picker("", selection: $viewModel.range) {
                ForEach(BreathingMindfulnessViewModel.Range.allCases) { r in
                    Text(r.label).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.range) { _, _ in
                viewModel.reload()
            }

            HStack(spacing: 12) {
                metricPill(title: "平均", value: valueText(viewModel.averageValue), unit: "次/分")
                metricPill(title: "最低", value: valueText(viewModel.minValue), unit: "次/分")
                metricPill(title: "最高", value: valueText(viewModel.maxValue), unit: "次/分")
            }
        }
        .glassCard()
    }

    private var overviewCard: some View {
        HStack(spacing: 12) {
            metricPill(title: "当前", value: valueText(viewModel.latestValue), unit: "次/分")
            metricPill(title: "平均", value: valueText(viewModel.averageValue), unit: "次/分")
            metricPill(title: "状态", value: statusText, unit: "")
        }
    }

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("练习节律")
                        .font(.appSystem(size: 20, weight: .bold, design: .serif))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("完成一次正念呼吸后，会写入健康记录并同步习惯打卡。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                sectionBadge(statusText, tint: statusTint)
            }

            HStack(spacing: 10) {
                ForEach(BreathingMindfulnessViewModel.SessionLength.allCases) { item in
                    Button {
                        viewModel.selectedSessionLength = item
                    } label: {
                        Text(item.shortTitle)
                            .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(viewModel.selectedSessionLength == item ? Theme.Colors.white : Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                (viewModel.selectedSessionLength == item ? Theme.Colors.textPrimary : Theme.Colors.mintGreen.opacity(0.10)),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSessionRunning)
                }
            }

            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Theme.Colors.mintGreen.opacity(0.14), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: progressValue)
                        .stroke(
                            LinearGradient(
                                colors: [Theme.Colors.mintGreen, Theme.Colors.accentBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 118, height: 118)
                .overlay {
                    VStack(spacing: 4) {
                        Text(timerText)
                            .font(.appSystem(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(viewModel.isSessionRunning ? "保持缓慢呼吸" : "准备开始")
                            .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(sessionHint)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button {
                            if viewModel.isSessionRunning {
                                viewModel.cancelSession()
                            } else {
                                viewModel.startSession()
                            }
                        } label: {
                            Text(viewModel.isSessionRunning ? "结束" : "开始练习")
                                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(viewModel.isSessionRunning ? Theme.Colors.textPrimary : Theme.Colors.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    (viewModel.isSessionRunning ? Theme.Colors.secondaryBackground : Theme.Colors.textPrimary),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.requestAuthorizationAndReload()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.appSystem(size: 15, weight: .bold))
                                .foregroundColor(Theme.Colors.textPrimary)
                                .frame(width: 46, height: 46)
                                .background(Theme.Colors.secondaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isSessionRunning)
                    }
                }
            }
        }
        .detailCardSurface(tint: Theme.Colors.mintGreen)
    }
    
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("呼吸趋势")
                        .font(.appSystem(.headline, design: .default))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("按当前范围查看真实呼吸频率记录，帮助观察节奏变化。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                sectionBadge(viewModel.range.label, tint: Theme.Colors.mintGreen)
            }

            HStack(spacing: 10) {
                chartMetricChip(title: "最低", value: valueText(viewModel.minValue))
                chartMetricChip(title: "最高", value: valueText(viewModel.maxValue))
                chartMetricChip(title: "样本", value: "\(viewModel.points.count)")
            }
            
            if viewModel.points.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.errorMessage ?? "暂无数据")
                        .font(.appSystem(.subheadline, design: .default))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Button {
                        viewModel.requestAuthorizationAndReload()
                    } label: {
                        Text("重新授权并读取")
                            .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Theme.Colors.textPrimary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else {
                Chart(viewModel.chartPoints) { p in
                    LineMark(
                        x: .value("时间", p.date),
                        y: .value("呼吸频率", p.value)
                    )
                    .foregroundStyle(Theme.Colors.mintGreen)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("时间", p.date),
                        y: .value("呼吸频率", p.value)
                    )
                    .foregroundStyle(Theme.Colors.mintGreen.opacity(0.16))
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 220)
                .chartLegend(.hidden)
                .chartXScale(domain: viewModel.xAxisDomain)
                .chartYScale(domain: (viewModel.yAxisValues.first ?? 10)...(viewModel.yAxisValues.last ?? 22))
                .chartPlotStyle { plotArea in
                    plotArea
                        .clipped()
                        .padding(.bottom, 8)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: viewModel.yAxisValues) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Theme.Colors.textTertiary.opacity(0.16))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(String(format: "%.0f", amount))
                            }
                        }
                        .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: viewModel.xAxisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(for: date))
                            }
                        }
                        .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }

                Text(breathingInsightText)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .detailCardSurface(tint: Theme.Colors.mintGreen)
    }
    
    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("练习建议")
                    .font(.appSystem(.headline, design: .default))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                sectionBadge("恢复辅助", tint: Theme.Colors.accentBlue)
            }
            
            summaryRow(title: "当前状态", value: statusText, unit: "")
            summaryRow(title: "练习提示", value: sessionHint, unit: "")
            summaryRow(title: "平均呼吸", value: valueText(viewModel.averageValue), unit: "次/分")
            
            if let last = viewModel.points.last?.date {
                    summaryRow(title: "最新记录", value: timeText(last), unit: "")
            }
        }
        .detailCardSurface()
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("说明")
                .font(.appSystem(.headline, design: .default))
                .foregroundColor(Theme.Colors.textPrimary)
            Text("趋势会读取健康 App 中的呼吸频率记录；正念练习完成后，会把本次练习写入健康记录。")
            Text("如果没有数据，通常是因为健康权限尚未开启，或者当前时间范围内还没有有效样本。")
        }
        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
        .foregroundColor(Theme.Colors.textSecondary)
        .detailCardSurface(tint: Theme.Colors.accentBlue)
    }

    private func metricPill(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(unit)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.Colors.mintGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private func summaryRow(title: String, value: String, unit: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            HStack(spacing: 4) {
                Text(value)
                    .foregroundColor(Theme.Colors.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .font(.appSystem(.subheadline, design: .rounded).weight(.semibold))
        }
    }
    
    private func valueText(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        if value >= 100 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }
    
    private func timeText(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func axisLabel(for date: Date) -> String {
        switch viewModel.range {
        case .day:
            return Self.hourFormatter.string(from: date)
        case .week:
            return Self.weekdayFormatter.string(from: date)
        case .month:
            return Self.monthDayFormatter.string(from: date)
        }
    }

    private var progressValue: Double {
        let total = Double(viewModel.selectedSessionLength.rawValue)
        guard total > 0 else { return 0.02 }
        let elapsed = total - Double(viewModel.remainingSeconds)
        return max(0.02, min(1.0, elapsed / total))
    }

    private var timerText: String {
        let minutes = viewModel.remainingSeconds / 60
        let seconds = viewModel.remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var sessionHint: String {
        switch viewModel.sessionState {
        case .idle:
            return String(localized: "吸气 4 秒，停顿 1 秒，呼气 6 秒，跟着自己的节奏慢慢来。")
        case .running:
            return String(localized: "把注意力放在呼吸和胸腔起伏上，尽量保持身体稳定。")
        case .saving:
            return String(localized: "正在把这次练习写入健康记录并刷新趋势。")
        case .completed:
            return String(localized: "这次练习已完成，习惯打卡和趋势会一起刷新。")
        case .failed(let message):
            return message
        }
    }

    private var statusText: String {
        switch viewModel.sessionState {
        case .idle:
            return String(localized: "待开始")
        case .running:
            return String(localized: "进行中")
        case .saving:
            return String(localized: "保存中")
        case .completed:
            return String(localized: "已完成")
        case .failed:
            return "失败"
        }
    }

    private var statusTint: Color {
        switch viewModel.sessionState {
        case .completed:
            return Theme.Colors.mintGreen
        case .failed:
            return Color(hex: "FF6B6B")
        case .running, .saving:
            return Theme.Colors.accentBlue
        case .idle:
            return Theme.Colors.textTertiary
        }
    }

    private var breathingInsightText: String {
        if viewModel.points.isEmpty {
            return String(localized: "没有样本时不补假数据，完成一次练习或等待健康同步后，这里会开始形成趋势。")
        }
        if let average = viewModel.averageValue, average <= 12 {
            return String(localized: "整体呼吸频率偏平稳，通常出现在状态更放松或练习完成后的时段。")
        }
        if let average = viewModel.averageValue, average <= 18 {
            return String(localized: "当前趋势处在常见范围内，可以继续通过短时练习让节奏更稳定。")
        }
        return String(localized: "最近呼吸频率偏快，适合配合 2 到 5 分钟的呼吸练习把节奏慢慢降下来。")
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "E"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private var sheetAmbientBackground: some View {
        VStack {
            HStack {
                Circle()
                    .fill(Theme.Colors.mintGreen.opacity(0.16))
                    .frame(width: 150, height: 150)
                    .blur(radius: 26)
                    .offset(x: -44, y: -42)
                Spacer()
                Circle()
                    .fill(Color(hex: "EAF8F1").opacity(0.75))
                    .frame(width: 120, height: 120)
                    .blur(radius: 24)
                    .offset(x: 30, y: -20)
            }
            Spacer()
        }
        .ignoresSafeArea()
    }

    private func chartMetricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sectionBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.appSystem(size: 10, weight: .heavy, design: .rounded))
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private extension View {
    func detailCardSurface(tint: Color? = nil) -> some View {
        self
            .padding(18)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.96), tint?.opacity(0.05) ?? Color.white.opacity(0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
    }
}
