/// EmotionStressCorrelationView 由压力模块关联入口调用，作为「情绪-压力关联」分析页。
/// 负责展示不同情绪对应的平均压力散点图与分组统计。

import SwiftUI
import Charts

/// 情绪压力关联视图 由上级页面或路由调用，作为压力模块里的界面或内容组件。
/// 负责展示压力状态、记录、分析结果以及调节建议。
struct EmotionStressCorrelationView: View {
    @State private var days: Int = 14
    @State private var items: [DailySleepStressAnalytics] = []
    @State private var isLoading = false
    
    private var points: [EmotionStressPoint] {
        items.compactMap { item in
            guard let emo = item.top_emotion, let stress = item.avg_stress else { return nil }
            return EmotionStressPoint(date: item.date, emotion: emo, avgStress: stress)
        }
    }
    
    private var summaryByEmotion: [EmotionStressSummary] {
        let grouped = Dictionary(grouping: points, by: \.emotion)
        return grouped.map { emo, list in
            let avg = Double(list.map(\.avgStress).reduce(0, +)) / Double(max(1, list.count))
            return EmotionStressSummary(emotion: emo, avgStress: avg, count: list.count)
        }
        .sorted { $0.avgStress > $1.avgStress }
    }
    
    private var moodStressCorrelation: Double? {
        let xs = points.compactMap { moodScore(for: $0.emotion) }
        let ys = points.map { Double($0.avgStress) }
        guard xs.count == ys.count, xs.count >= 3 else { return nil }
        return pearsonCorrelation(xs: xs, ys: ys)
    }
    
    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    Picker("天数", selection: $days) {
                        Text("7天").tag(7)
                        Text("14天").tag(14)
                        Text("30天").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.black)
                    .padding(.horizontal)
                    
                    if isLoading {
                        ProgressView()
                            .tint(Theme.Colors.textPrimary)
                            .padding(.top, 24)
                    } else if points.isEmpty {
                        Text("暂无情绪与压力相关性数据")
                            .font(.appSystem(.headline, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(.top, 24)
                    } else {
                        summaryCard
                        detailCard
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("情绪 × 压力")
        .onAppear { load() }
        .onChange(of: days) { _, _ in load() }
    }
    
    private var summaryCard: some View {
        BBChartCard(
            title: "情绪分组平均压力",
            subtitle: correlationSubtitle,
            isEmpty: summaryByEmotion.isEmpty,
            emptyTitle: "这一周期还没有可关联的数据",
            emptySystemImage: "chart.bar.xaxis"
        ) {
            Chart(summaryByEmotion) { item in
                BarMark(
                    x: .value("情绪", emotionTitle(item.emotion)),
                    y: .value("平均压力", item.avgStress),
                    width: .ratio(0.62)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            color(for: item.emotion).opacity(0.62),
                            color(for: item.emotion)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(7)
                .annotation(position: .top, spacing: 5) {
                    Text("\(Int(item.avgStress.rounded()))")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(color(for: item.emotion))
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks { _ in
                    AxisTick().foregroundStyle(Color.clear)
                    AxisValueLabel()
                        .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7, dash: [2, 3]))
                        .foregroundStyle(BBChartStyle.grid.opacity(0.85))
                    AxisTick().foregroundStyle(Color.clear)
                    AxisValueLabel {
                        if let stress = value.as(Int.self) {
                            Text("\(stress)")
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
                    .padding(.top, 12)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
            }
            .frame(height: 238)
        }
        .padding(.horizontal)
    }

    private var correlationSubtitle: String {
        guard let correlation = moodStressCorrelation else {
            return String(localized: "按记录情绪汇总平均压力，至少 3 天数据后可计算相关系数。")
        }
        return String(format: String(localized: "相关系数 r = %.2f。数值越接近 -1 或 1，关联越明显。"), correlation)
    }
    
    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("按天明细")
                .font(.appSystem(.headline, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            
            ForEach(points.suffix(30).reversed()) { point in
                HStack(spacing: 12) {
                    Text(point.date)
                        .font(.appSystem(.caption, design: .monospaced))
                        .foregroundColor(Theme.Colors.textSecondary)
                    
                    Spacer()
                    
                    Text(emotionTitle(point.emotion))
                        .font(.appSystem(.caption, design: .default).weight(.semibold))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(color(for: point.emotion).opacity(0.12))
                        .cornerRadius(10)
                    
                    Text("\(point.avgStress)")
                        .font(.appSystem(.caption, design: .monospaced).weight(.semibold))
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                .padding(.vertical, 6)
            }
        }
        .padding()
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
        .padding(.horizontal)
    }
    
    private func load() {
        isLoading = true
        Task {
            // 本地优先：无自建后端，情绪-压力关联以本机数据为准。
            items = []
            isLoading = false
        }
    }
    
    private func emotionTitle(_ code: String) -> String {
        BBChartStyle.Emotion.title(for: code)
    }
    
    private func moodScore(for code: String) -> Double? {
        switch code {
        case "happy": return 2
        case "neutral": return 1
        case "tired": return 0
        case "anxious": return -1
        case "sad": return -2
        default: return nil
        }
    }
    
    private func color(for emotion: String) -> Color {
        BBChartStyle.Emotion.color(for: emotion)
    }
    
    private func pearsonCorrelation(xs: [Double], ys: [Double]) -> Double {
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        
        var cov = 0.0
        var varX = 0.0
        var varY = 0.0
        for (x, y) in zip(xs, ys) {
            let dx = x - meanX
            let dy = y - meanY
            cov += dx * dy
            varX += dx * dx
            varY += dy * dy
        }
        
        let denom = sqrt(varX * varY)
        guard denom > 0.000001 else { return 0 }
        return cov / denom
    }
}

private struct EmotionStressPoint: Identifiable {
    let id: String
    let date: String
    let emotion: String
    let avgStress: Int
    
    init(date: String, emotion: String, avgStress: Int) {
        self.id = "\(date)-\(emotion)"
        self.date = date
        self.emotion = emotion
        self.avgStress = avgStress
    }
}

private struct EmotionStressSummary: Identifiable {
    var id: String { emotion }
    let emotion: String
    let avgStress: Double
    let count: Int
}

#Preview {
    NavigationStack {
        EmotionStressCorrelationView()
    }
}
