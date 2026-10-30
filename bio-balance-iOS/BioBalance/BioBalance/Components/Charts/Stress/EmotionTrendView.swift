import SwiftUI
import Charts

/// 情绪趋势视图 由上级页面或路由调用，作为压力模块里的界面或内容组件。
/// 负责展示压力状态、记录、分析结果以及调节建议。
struct EmotionTrendView: View {
    @State private var viewModel = EmotionViewModel()
    @State private var selectedDays = 7
    @State private var selectedPointID: String?

    private var points: [EmotionTrendPoint] {
        viewModel.records.compactMap(EmotionTrendPoint.init)
    }

    private var selectedPoint: EmotionTrendPoint? {
        guard let selectedPointID else { return nil }
        return points.first(where: { $0.id == selectedPointID })
    }

    private var averageIntensity: Double? {
        guard !points.isEmpty else { return nil }
        return Double(points.map(\.intensity).reduce(0, +)) / Double(points.count)
    }

    private var latestPoint: EmotionTrendPoint? {
        points.last
    }

    private var dateDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(
            byAdding: .day,
            value: -(selectedDays - 1),
            to: calendar.startOfDay(for: end)
        ) ?? end.addingTimeInterval(-Double(selectedDays - 1) * 86_400)
        return start...end
    }

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    rangePicker
                    trendSummary
                    trendCard
                    distributionCard
                    factorCard

                    if !viewModel.records.isEmpty {
                        recentRecordsCard
                    }
                    NavigationLink("查看情绪日历") { MoodLogView() }
                        .buttonStyle(BBSecondaryButtonStyle(isFullWidth: true))
                    NavigationLink("记录历史") { EmotionHistoryView() }
                        .buttonStyle(BBPrimaryButtonStyle(isFullWidth: true))
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 96)
            }
        }
        .navigationTitle("情绪趋势")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    EmotionStressCorrelationView()
                } label: {
                    Image(systemName: "chart.dots.scatter")
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                .accessibilityLabel("查看情绪与压力关联")
            }
        }
        .onAppear {
            viewModel.load(days: selectedDays)
        }
        .onChange(of: selectedDays) { _, days in
            selectedPointID = nil
            viewModel.load(days: days)
        }
        .onChange(of: viewModel.records.map(\.id)) { _, _ in
            selectedPointID = points.last?.id
        }
    }

    private var rangePicker: some View {
        Picker("时间范围", selection: $selectedDays) {
            Text("7天").tag(7)
            Text("30天").tag(30)
            Text("6个月").tag(180)
        }
        .pickerStyle(.segmented)
        .tint(Theme.Colors.mintGreen)
    }

    private var trendSummary: some View {
        EmotionStressCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("本期状态").font(.caption.weight(.bold)).foregroundStyle(EmotionStressStyle.secondary)
                Text(stabilityScore.map { "\($0) / 100" } ?? "-- / 100")
                    .font(.system(size: 30, weight: .bold)).foregroundStyle(EmotionStressStyle.ink)
                Text(points.count >= 3 ? "根据当前周期的真实情绪记录计算" : "记录不足，暂不比较上一周期")
                    .font(.caption).foregroundStyle(EmotionStressStyle.secondary)
            }
        }
    }

    private var stabilityScore: Int? {
        guard points.count >= 3 else { return nil }
        let values = points.map { Double($0.intensity) }
        let mean = values.reduce(0, +) / Double(values.count)
        let deviation = values.map { abs($0 - mean) }.reduce(0, +) / Double(values.count)
        return max(0, min(100, Int((100 - deviation).rounded())))
    }

    private var trendCard: some View {
        BBChartCard(
            title: "情绪强度",
            subtitle: "彩色节点代表记录时的情绪，虚线为这一周期的平均强度。",
            isEmpty: points.isEmpty,
            emptyTitle: "这一周期还没有情绪记录",
            emptySystemImage: "waveform.path.ecg"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                emotionLegend
                trendChart
                Divider().overlay(Theme.Colors.surfaceBorder)
                summaryStrip
            }
        }
    }

    private var emotionLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(["happy", "neutral", "tired", "anxious", "sad"], id: \.self) { emotion in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(BBChartStyle.Emotion.color(for: emotion))
                            .frame(width: 8, height: 8)
                        Text(BBChartStyle.Emotion.title(for: emotion))
                            .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .scrollDisabled(true)
    }

    private var trendChart: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("时间", point.date),
                    yStart: .value("下界", 0),
                    yEnd: .value("强度", point.intensity)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            BBChartStyle.trendLine.opacity(0.14),
                            BBChartStyle.trendLine.opacity(0.01)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("时间", point.date),
                    y: .value("强度", point.intensity)
                )
                .foregroundStyle(BBChartStyle.trendLine.opacity(0.72))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("时间", point.date),
                    y: .value("强度", point.intensity)
                )
                .symbolSize(selectedPoint?.id == point.id ? 92 : 62)
                .foregroundStyle(Theme.Colors.onAccent)
                .annotation(position: .overlay, alignment: .center) {
                    EmotionIconView(
                        emotion: EmotionKind.resolve(moodID: point.emotion, backendCode: point.emotion),
                        size: selectedPoint?.id == point.id ? 24 : 20
                    )
                }
                .accessibilityLabel(BBChartStyle.Emotion.title(for: point.emotion))
                .accessibilityValue("强度 \(point.intensity)")
            }

            if let averageIntensity {
                RuleMark(y: .value("周期平均", averageIntensity))
                    .foregroundStyle(BBChartStyle.baseline.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("均值")
                            .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(BBChartStyle.baseline)
                    }
            }

            if let selectedPoint {
                RuleMark(x: .value("选中", selectedPoint.date))
                    .foregroundStyle(BBChartStyle.selection.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))

                PointMark(
                    x: .value("时间", selectedPoint.date),
                    y: .value("强度", selectedPoint.intensity)
                )
                .foregroundStyle(Color.clear)
                .annotation(
                    position: .top,
                    spacing: 10,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    selectionTooltip(for: selectedPoint)
                }
            }
        }
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [2, 4]))
                    .foregroundStyle(BBChartStyle.grid.opacity(0.65))
                AxisTick().foregroundStyle(Color.clear)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.month().day()))
                            .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7, dash: [2, 3]))
                    .foregroundStyle(BBChartStyle.grid.opacity(0.85))
                AxisTick().foregroundStyle(Color.clear)
                AxisValueLabel {
                    if let intensity = value.as(Int.self) {
                        Text("\(intensity)")
                            .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(BBChartStyle.plotBackground)
                .clipped()
                .padding(.top, 6)
                .padding(.trailing, 8)
                .padding(.bottom, 6)
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updateSelection(at: value.location, frame: frame, proxy: proxy)
                                }
                        )
                }
            }
        }
        .frame(height: 250)
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryItem(
                title: "最近情绪",
                value: latestPoint.map { BBChartStyle.Emotion.title(for: $0.emotion) } ?? "--",
                color: latestPoint.map { BBChartStyle.Emotion.color(for: $0.emotion) } ?? Theme.Colors.textTertiary
            )

            summaryDivider

            summaryItem(
                title: "平均强度",
                value: averageIntensity.map { String(format: "%.0f", $0) } ?? "--",
                color: BBChartStyle.baseline
            )

            summaryDivider

            summaryItem(
                title: "记录次数",
                value: "\(points.count)",
                color: Theme.Colors.textPrimary
            )
        }
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Theme.Colors.surfaceBorder)
            .frame(width: 1, height: 34)
    }

    private func summaryItem(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var recentRecordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近记录")
                .font(.appSystem(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            ForEach(viewModel.records.reversed().prefix(12)) { record in
                EmotionRow(record: record)
            }
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private var distributionCard: some View {
        EmotionStressCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("情绪分布").font(.headline.weight(.bold)).foregroundStyle(EmotionStressStyle.ink)
                if points.isEmpty {
                    Text("还没有情绪记录").font(.subheadline).foregroundStyle(EmotionStressStyle.secondary)
                } else {
                    ForEach(emotionDistribution, id: \.kind.id) { item in
                        HStack(spacing: 10) {
                            EmotionIconView(emotion: item.kind, size: 22)
                            Text(item.kind.title).font(.caption.weight(.semibold)).frame(width: 42, alignment: .leading)
                            ProgressView(value: item.ratio)
                                .tint(item.kind == .anxious || item.kind == .low ? EmotionStressStyle.coral.opacity(0.7) : EmotionStressStyle.mintMuted)
                            Text("\(Int((item.ratio * 100).rounded()))%").font(.caption.weight(.bold)).frame(width: 38, alignment: .trailing)
                        }.accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var factorCard: some View {
        let entries = MoodStore.shared.allEntries().filter { $0.loggedAt >= dateDomain.lowerBound }
        let counts = Dictionary(grouping: entries.flatMap { $0.factors ?? [] }, by: { $0 }).mapValues(\.count).sorted { $0.value > $1.value }
        return EmotionStressCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("状态影响").font(.headline.weight(.bold)).foregroundStyle(EmotionStressStyle.ink)
                if counts.isEmpty {
                    Text("记录影响因素后，这里会展示共同出现的趋势。")
                        .font(.subheadline).foregroundStyle(EmotionStressStyle.secondary)
                } else {
                    ForEach(Array(counts.prefix(2)), id: \.key) { item in
                        HStack {
                            Image(systemName: "checkmark.circle").foregroundStyle(EmotionStressStyle.mint)
                            Text("\(item.key)与情绪记录共同出现").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(item.value) 次").font(.caption.weight(.bold)).foregroundStyle(EmotionStressStyle.mint)
                        }.frame(minHeight: 44).accessibilityElement(children: .combine)
                    }
                    Text("共同出现不代表因果关系。").font(.caption).foregroundStyle(EmotionStressStyle.tertiary)
                }
            }
        }
    }

    private var emotionDistribution: [(kind: EmotionKind, ratio: Double)] {
        guard !points.isEmpty else { return [] }
        let kinds = points.map { EmotionKind.resolve(moodID: $0.emotion, backendCode: $0.emotion) }
        let counts = Dictionary(grouping: kinds, by: { $0 }).mapValues(\.count)
        return EmotionKind.allCases.compactMap { kind in
            guard let count = counts[kind], count > 0 else { return nil }
            return (kind, Double(count) / Double(points.count))
        }.sorted { $0.ratio > $1.ratio }
    }

    private func selectionTooltip(for point: EmotionTrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(BBChartStyle.Emotion.title(for: point.emotion))
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(BBChartStyle.Emotion.color(for: point.emotion))
            Text("强度 \(point.intensity) · \(point.date.formatted(.dateTime.month().day().hour().minute()))")
                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.Colors.surface.opacity(0.98), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BBChartStyle.Emotion.color(for: point.emotion).opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    private func updateSelection(at location: CGPoint, frame: CGRect, proxy: ChartProxy) {
        guard frame.contains(location) else { return }
        let xPosition = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: xPosition) else { return }
        selectedPointID = points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }?.id
    }
}

private nonisolated struct EmotionTrendPoint: Identifiable {
    let id: String
    let emotion: String
    let intensity: Int
    let date: Date

    init?(_ record: EmotionRecord) {
        guard let timestamp = record.timestamp else { return nil }
        id = record.id
        emotion = record.emotion
        intensity = record.intensity
        date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

private struct EmotionRow: View {
    let record: EmotionRecord

    var body: some View {
        HStack(spacing: 12) {
            EmotionIconView(emotion: emotionKind, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(BBChartStyle.Emotion.title(for: record.emotion))
                    .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                if let timestamp = record.timestamp {
                    Text(Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(.dateTime.month().day().hour().minute()))
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            Spacer(minLength: 8)

            Text("\(record.intensity)")
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(BBChartStyle.Emotion.color(for: record.emotion))
                .frame(minWidth: 32, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private var emotionKind: EmotionKind {
        EmotionKind.resolve(moodID: record.emotion, backendCode: record.emotion)
    }
}
