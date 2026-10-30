import SwiftUI

/// watchOS 参考样式页面仅依赖现有的最小化同步快照。
/// 情绪标签只是对压力信号的健康管理解读，不属于医学诊断。
struct WatchMindRhythmView: View {
    let snapshot: WatchRealtimeHealth

    private var rows: [MindRhythmRow] {
        let samples = snapshot.stressHistory.filter { $0.value > 0 }
        let values = samples.isEmpty ? (snapshot.stress_value > 0 ? [snapshot.stress_value] : []) : samples.map(\.value)
        let total = max(values.count, 1)
        let relaxed = values.filter { $0 < 35 }.count
        let focused = values.filter { (35..<65).contains($0) }.count
        let tense = values.filter { $0 >= 65 }.count
        return [
            MindRhythmRow(title: String(localized: "悠闲"), color: .mint, count: relaxed, percent: percent(relaxed, total)),
            MindRhythmRow(title: String(localized: "专注"), color: Color(red: 0.58, green: 0.65, blue: 1), count: focused, percent: percent(focused, total)),
            MindRhythmRow(title: String(localized: "紧绷"), color: .pink, count: tense, percent: percent(tense, total))
        ].sorted { $0.count > $1.count }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("身心节奏")
                            .font(.watchAppSystem(size: 18, weight: .bold, design: .rounded))
                        Text("依据今日压力信号推断")
                            .font(.watchAppSystem(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                }

                ForEach(rows) { row in
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(row.color)
                            .frame(width: 7, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.watchAppSystem(size: 15, weight: .bold, design: .rounded))
                            Text("\(row.percent)% · 最近同步")
                                .font(.watchAppSystem(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("×\(row.count)")
                            .font(.watchAppSystem(size: 16, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(WatchReferenceBackground(accent: .mint))
        .navigationTitle("节奏")
    }

    private func percent(_ value: Int, _ total: Int) -> Int {
        Int((Double(value) / Double(total) * 100).rounded())
    }
}

private struct MindRhythmRow: Identifiable {
    let title: String
    let color: Color
    let count: Int
    let percent: Int
    var id: String { title }
}

struct WatchNightSleepView: View {
    let snapshot: WatchRealtimeHealth

    private var duration: Int { max(0, snapshot.sleepDurationMinutes) }
    private var score: Int { max(0, snapshot.sleepScore) }
    private var durationText: String {
        duration > 0 ? String(localized: "\(duration / 60)时\(duration % 60)分") : String(localized: "暂无记录")
    }
    private var qualityText: String {
        guard score > 0 else { return String(localized: "等待同步") }
        return score >= 85 ? String(localized: "优秀") : score >= 70 ? String(localized: "良好") : String(localized: "待恢复")
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "moon.stars.fill")
                        .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 1))
                    Text("夜间睡眠")
                        .font(.watchAppSystem(size: 17, weight: .bold, design: .rounded))
                    Spacer()
                    Text("♥︎")
                        .foregroundStyle(.pink)
                }

                SleepQualityStrip(score: score)
                    .frame(height: 54)

                HStack {
                    Label(score > 0 ? String(localized: "睡眠评分 \(score) 分") : String(localized: "等待睡眠数据"), systemImage: "bolt.fill")
                    Spacer()
                }
                .font(.watchAppSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.orange)

                HStack(alignment: .firstTextBaseline) {
                    Text(durationText)
                        .font(.watchAppSystem(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.59, green: 0.61, blue: 1))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(score > 0 ? "\(score)%" : "--")
                            .font(.watchAppSystem(size: 17, weight: .bold, design: .rounded))
                        Text(qualityText)
                            .font(.watchAppSystem(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(WatchReferenceBackground(accent: Color(red: 0.35, green: 0.37, blue: 0.95)))
        .navigationTitle("睡眠")
    }

}

private struct SleepQualityStrip: View {
    let score: Int

    private let heights: [CGFloat] = [18, 30, 22, 42, 28, 20, 38, 46, 25, 33, 18, 41]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index.isMultiple(of: 4) ? Color.mint : (index.isMultiple(of: 3) ? Color.indigo : Color.blue))
                    .frame(maxWidth: .infinity)
                    .frame(height: height * (score > 0 ? 1 : 0.42))
                    .opacity(score > 0 ? 0.95 : 0.45)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("睡眠质量概览")
    }
}

struct WatchMotivationView: View {
    let snapshot: WatchRealtimeHealth
    @AppStorage("watch.motivation.favorite") private var isFavorite = false

    private var quote: String {
        if snapshot.stress_value >= 70 {
            return String(localized: "你不需要一次解决所有事情。先让呼吸慢下来，再完成眼前最小的一步。")
        }
        if snapshot.sleepScore > 0 && snapshot.sleepScore < 70 {
            return String(localized: "休息不是落后，而是在为下一段清醒积蓄力量。")
        }
        return String(localized: "相信自己。你已经经历了很多，而今天仍在认真照顾自己。")
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Motivation")
                    .font(.watchAppSystem(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(context.date, style: .time)
                        .font(.watchAppSystem(size: 10, weight: .bold, design: .rounded))
                }
            }

            Spacer(minLength: 2)
            Text(quote)
                .font(.watchAppSystem(size: 13, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)

            HStack(spacing: 24) {
                ShareLink(item: quote) {
                    Image(systemName: "square.and.arrow.up")
                }
                Button {
                    isFavorite.toggle()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? .pink : .white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")
            }
            .font(.system(size: 23, weight: .medium))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color.black)
        .navigationTitle("鼓励")
    }
}

struct WatchTodayPressureView: View {
    let snapshot: WatchRealtimeHealth

    private var points: [WatchStressHistoryPoint] {
        let values = snapshot.stressHistory.filter { $0.value > 0 }.sorted { $0.timestamp < $1.timestamp }
        if !values.isEmpty { return Array(values.suffix(24)) }
        return snapshot.stress_value > 0
            ? [WatchStressHistoryPoint(timestamp: snapshot.timestamp, value: snapshot.stress_value)]
            : []
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("今日压力")
                        .font(.watchAppSystem(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    Text(snapshot.stress_value > 0 ? "\(snapshot.stress_value)" : "--")
                        .font(.watchAppSystem(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(pressureColor(for: snapshot.stress_value))
                }

                PressureRibbon(points: points)
                    .frame(height: 66)

                HStack {
                    Label(snapshot.stress_value > 0 ? pressureLevelText(for: snapshot.stress_value) : String(localized: "等待同步"), systemImage: "waveform.path.ecg")
                    Spacer()
                    Text(snapshot.stressTrend.isEmpty ? "—" : snapshot.stressTrend)
                }
                .font(.watchAppSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

                Text(snapshot.stress_value > 0 ? pressureAdvice(for: snapshot.stress_value) : String(localized: "同步后会显示今日压力趋势。"))
                    .font(.watchAppSystem(size: 11, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(8)
        }
        .background(WatchReferenceBackground(accent: pressureColor(for: snapshot.stress_value)))
        .navigationTitle("压力")
    }
}

private struct PressureRibbon: View {
    let points: [WatchStressHistoryPoint]

    var body: some View {
        GeometryReader { proxy in
            let step = points.count > 1 ? proxy.size.width / CGFloat(points.count - 1) : proxy.size.width / 2
            ZStack(alignment: .bottomLeading) {
                ForEach(1..<4, id: \.self) { line in
                    Path { path in
                        let y = proxy.size.height * CGFloat(line) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                Path { path in
                    for (index, point) in points.enumerated() {
                        let x = points.count == 1 ? proxy.size.width / 2 : CGFloat(index) * step
                        let y = proxy.size.height * (1 - CGFloat(min(max(point.value, 0), 100)) / 100)
                        index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(Color.mint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日压力趋势")
    }
}

private struct WatchReferenceBackground: View {
    let accent: Color

    var body: some View {
        LinearGradient(
            colors: [accent.opacity(0.32), Color(red: 0.07, green: 0.09, blue: 0.08), .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
