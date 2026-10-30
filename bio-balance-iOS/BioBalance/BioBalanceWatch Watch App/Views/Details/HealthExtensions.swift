/// Health Extensions 定义 Apple Watch 端的界面或同步逻辑，负责在手表上展示核心健康信息并与 iPhone 侧保持数据联动。
import SwiftUI
import Combine

/// 压力视图 由上级页面或路由调用，作为Apple Watch 应用里的界面或内容组件。
/// 负责Apple Watch 端展示与同步。
struct StressDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let snapshot: WatchRealtimeHealth
    let liveBpm: Int

    private var resolvedBpm: Int {
        liveBpm > 0 ? liveBpm : snapshot.bpm
    }

    private var chartPoints: [WatchStressHistoryPoint] {
        let history = snapshot.stressHistory
            .filter { $0.value > 0 }
            .sorted { $0.timestamp < $1.timestamp }
        if history.isEmpty {
            return demoChartPoints
        }
        return Array(history.suffix(6))
    }

    var body: some View {
        ZStack {
            WatchDetailBackground()
                .ignoresSafeArea()

            VStack {
                Spacer(minLength: 6)

                StressInsightCard(
                    snapshot: snapshot,
                    resolvedBpm: resolvedBpm,
                    points: chartPoints
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .navigationTitle("HRV")
        .navigationBarBackButtonHidden(true)
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.watchAppSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.10), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.leading, 10)
        }
    }
}

private struct WatchDetailBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.05, green: 0.07, blue: 0.14),
                    Color(red: 0.07, green: 0.09, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.mint.opacity(0.10))
                .frame(width: 130, height: 130)
                .blur(radius: 26)
                .offset(x: 40, y: -120)

            Circle()
                .fill(Color(red: 0.42, green: 0.33, blue: 0.88).opacity(0.12))
                .frame(width: 140, height: 140)
                .blur(radius: 30)
                .offset(x: -55, y: 115)
        }
    }
}

private struct StressInsightCard: View {
    let snapshot: WatchRealtimeHealth
    let resolvedBpm: Int
    let points: [WatchStressHistoryPoint]

    private var latestPoint: WatchStressHistoryPoint? {
        points.last
    }

    private var todayAverage: Int {
        if points.isEmpty {
            return snapshot.hrv > 0 ? Int(snapshot.hrv.rounded()) : 32
        }
        return Int((Double(points.map(\.value).reduce(0, +)) / Double(points.count)).rounded())
    }

    private var rollingAverage: Int {
        let base = snapshot.hrv > 0 ? Int(snapshot.hrv.rounded()) : todayAverage
        return max(base, todayAverage + 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(pressureLevelText(for: snapshot.stress_value))
                    .font(.watchAppSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(pressureColor(for: snapshot.stress_value))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.10), in: Capsule())

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text(latestPoint.map { Date(timeIntervalSince1970: TimeInterval($0.timestamp)).formatted(date: .omitted, time: .shortened) } ?? "14:40")
                        .font(.watchAppSystem(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("HRV")
                        .font(.watchAppSystem(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }

            HStack(spacing: 18) {
                statBlock(title: String(localized: "今日均值"), value: "\(todayAverage)ms")
                statBlock(title: String(localized: "月均参考"), value: "\(rollingAverage)ms")
            }

            HRVLineChartCard(points: points)

            HStack(spacing: 10) {
                legendItem(color: pressureColor(for: snapshot.stress_value), text: pressureAdvice(for: snapshot.stress_value))
                Spacer()
                Text("心率 \(resolvedBpm > 0 ? "\(resolvedBpm)" : "--")")
                    .font(.watchAppSystem(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    Color.black,
                    Color.black.opacity(0.96),
                    Color(red: 0.05, green: 0.05, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.05), lineWidth: 0.8)
        }
    }

    private func statBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.watchAppSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
            Text(value)
                .font(.watchAppSystem(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .stroke(color, lineWidth: 4)
                .frame(width: 14, height: 14)
            Text(text)
                .font(.watchAppSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(color)
        }
    }
}

private struct HRVLineChartCard: View {
    let points: [WatchStressHistoryPoint]

    private var normalizedPoints: [ChartPlotPoint] {
        let values = points.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max(), !points.isEmpty else { return [] }
        let range = max(1, maxValue - minValue)
        return points.enumerated().map { index, point in
            ChartPlotPoint(
                id: index,
                label: Date(timeIntervalSince1970: TimeInterval(point.timestamp)).formatted(date: .omitted, time: .shortened),
                value: point.value,
                yRatio: CGFloat(point.value - minValue) / CGFloat(range)
            )
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let plotted = normalizedPoints
                let width = proxy.size.width
                let height = proxy.size.height
                let stepX = plotted.count > 1 ? width / CGFloat(plotted.count - 1) : width

                ZStack {
                    HStack(spacing: 0) {
                        ForEach(plotted.indices, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                            if plotted.count > 1 {
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    Path { path in
                        for (index, point) in plotted.enumerated() {
                            let x = CGFloat(index) * stepX
                            let y = height - 8 - point.yRatio * (height - 20)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    ForEach(plotted) { point in
                        let x = CGFloat(point.id) * stepX
                        let y = height - 8 - point.yRatio * (height - 20)

                        Circle()
                            .fill(Color.black)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .stroke(chartColor(for: point.value), lineWidth: 4)
                            )
                            .position(x: x, y: y)
                    }
                }
            }
            .frame(height: 84)

            HStack {
                if let first = normalizedPoints.first {
                    Text(first.label)
                }
                Spacer()
                if normalizedPoints.count > 2 {
                    Text(normalizedPoints[normalizedPoints.count / 2].label)
                }
                Spacer()
                if let last = normalizedPoints.last {
                    Text(last.label)
                }
            }
            .font(.watchAppSystem(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.66))
        }
    }

    private func chartColor(for value: Int) -> Color {
        switch value {
        case ..<16:
            return Color(red: 0.93, green: 0.47, blue: 0.63)
        case 16..<24:
            return Color(red: 0.99, green: 0.74, blue: 0.52)
        case 24..<41:
            return Color(red: 0.72, green: 0.74, blue: 0.98)
        default:
            return Color(red: 0.63, green: 0.91, blue: 0.70)
        }
    }
}

private struct ChartPlotPoint: Identifiable {
    let id: Int
    let label: String
    let value: Int
    let yRatio: CGFloat
}

private let demoChartPoints: [WatchStressHistoryPoint] = [
    WatchStressHistoryPoint(timestamp: 1715508000, value: 20),
    WatchStressHistoryPoint(timestamp: 1715510880, value: 14),
    WatchStressHistoryPoint(timestamp: 1715513280, value: 14),
    WatchStressHistoryPoint(timestamp: 1715515620, value: 34),
    WatchStressHistoryPoint(timestamp: 1715519220, value: 14),
    WatchStressHistoryPoint(timestamp: 1715520900, value: 17),
    WatchStressHistoryPoint(timestamp: 1715522100, value: 18),
    WatchStressHistoryPoint(timestamp: 1715524500, value: 36)
]

private struct StressHeaderCard: View {
    let snapshot: WatchRealtimeHealth

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("压力状态", systemImage: "waveform.path.ecg")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text(Date(timeIntervalSince1970: TimeInterval(snapshot.timestamp)).formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.68))
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pressureHeadline(for: snapshot.stress_value))
                        .font(.watchAppSystem(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(pressureLevelText(for: snapshot.stress_value))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(pressureColor(for: snapshot.stress_value))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.14), in: Capsule())
                }

                Spacer()

                StressMascot(
                    accent: pressureColor(for: snapshot.stress_value),
                    isElevated: snapshot.stressState.map({ ["highStress", "overloaded"].contains($0) }) == true
                )
            }

            Text("最近同步 \(Date(timeIntervalSince1970: TimeInterval(snapshot.timestamp)).formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.74))
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.15, blue: 0.36),
                    Color.black.opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

private struct StressMeterCard: View {
    let snapshot: WatchRealtimeHealth

    private var progress: CGFloat {
        CGFloat(min(max(snapshot.stress_value, 0), 100)) / 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前压力值")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("0 - 100 区间")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.82))
                }
                Spacer()
                Text("\(snapshot.stress_value)")
                    .font(.watchAppSystem(size: 30, weight: .bold, design: .rounded))
                Text("/100")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.10))

                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.mint, .cyan, .orange, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.18), lineWidth: 2)
                        }
                        .offset(x: max(0, min(proxy.size.width - 18, proxy.size.width * progress - 9)))
                }
            }
            .frame(height: 16)

            HStack {
                Text("轻松")
                Spacer()
                Text("平衡")
                Spacer()
                Text("偏高")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(pressureAdvice(for: snapshot.stress_value))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct StressDetailActionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout.weight(.bold))
                .foregroundStyle(.mint)
                .frame(width: 28, height: 28)
                .background(Color.mint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct StressMiniStat: View {
    let title: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.headline.bold())
                    .foregroundStyle(.primary)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct StressMascot: View {
    let accent: Color
    let isElevated: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.12))
                .frame(width: 68, height: 68)

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 50, height: 50)

                Circle()
                    .fill(isElevated ? Color.orange.opacity(0.92) : Color.yellow.opacity(0.92))
                    .frame(width: 22, height: 22)
                    .offset(y: -2)
            }

            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
                .offset(x: 18, y: -18)
        }
    }
}

/// 压力视图 由上级页面或路由调用，作为Apple Watch 应用里的界面或内容组件。
/// 负责Apple Watch 端展示与同步。
struct StressChartView: View {
    let snapshot: WatchRealtimeHealth

    private var points: [WatchStressHistoryPoint] {
        snapshot.stressHistory
            .filter { $0.value > 0 }
            .sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        ZStack {
            WatchDetailBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if points.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("今日压力")
                                .font(.headline.weight(.semibold))
                            Text("等待同步历史数据")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("iPhone 下发当天压力序列后，这里会显示 24 小时波动。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("实时压力")
                                        .font(.headline.weight(.semibold))
                                    Text("今天的压力波动与峰值变化")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("24h")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(.white.opacity(0.08), in: Capsule())
                            }
                            StressHistoryPlot(points: points)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .navigationTitle("今日状态")
    }
}

private struct StressHistoryPlot: View {
    let points: [WatchStressHistoryPoint]

    private var sampledPoints: [WatchStressHistoryPoint] {
        guard points.count > 36 else { return points }
        let bucketSize = Double(points.count) / 36.0
        return stride(from: 0.0, to: Double(points.count), by: bucketSize).compactMap { start in
            let lowerBound = Int(start.rounded(.down))
            let upperBound = min(points.count, Int((start + bucketSize).rounded(.up)))
            guard lowerBound < upperBound else { return nil }
            let bucket = Array(points[lowerBound..<upperBound])
            let average = Int((Double(bucket.map(\.value).reduce(0, +)) / Double(bucket.count)).rounded())
            return WatchStressHistoryPoint(timestamp: bucket[bucket.count / 2].timestamp, value: average)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let chartHeight = proxy.size.height
                let stepX = sampledPoints.count > 1 ? proxy.size.width / CGFloat(sampledPoints.count - 1) : proxy.size.width

                ZStack(alignment: .bottomLeading) {
                    VStack(spacing: chartHeight / 3) {
                        ForEach(0..<4, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.white.opacity(0.10))
                                .frame(height: 1)
                        }
                    }

                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(sampledPoints) { point in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(stressBarColor(value: point.value))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(6, chartHeight * CGFloat(point.value) / 100))
                        }
                    }

                    Path { path in
                        for (index, point) in sampledPoints.enumerated() {
                            let x = CGFloat(index) * stepX
                            let y = chartHeight - (chartHeight * CGFloat(point.value) / 100)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
            .frame(height: 110)

            HStack {
                Text("00:00")
                Spacer()
                Text("12:00")
                Spacer()
                Text("00:00")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ChartLegendChip(title: String(localized: "低"), tint: .mint)
                ChartLegendChip(title: String(localized: "中"), tint: .orange)
                ChartLegendChip(title: String(localized: "高"), tint: .red)
            }
        }
    }

    private func stressBarColor(value: Int) -> LinearGradient {
        switch value {
        case 0..<35:
            return LinearGradient(colors: [.mint.opacity(0.8), .cyan.opacity(0.95)], startPoint: .bottom, endPoint: .top)
        case 35..<70:
            return LinearGradient(colors: [.orange.opacity(0.82), .pink.opacity(0.88)], startPoint: .bottom, endPoint: .top)
        default:
            return LinearGradient(colors: [.pink.opacity(0.82), .red.opacity(0.92)], startPoint: .bottom, endPoint: .top)
        }
    }
}

private struct ChartLegendChip: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.06), in: Capsule())
    }
}

/// Habit详情枚举 作为Apple Watch 应用里的状态与分类定义。
/// 负责描述Apple Watch 端展示与同步过程中会用到的状态、分类或分支。
enum HabitDetailFocus {
    case water
    case caffeine
}

/// Habit视图 由上级页面或路由调用，作为Apple Watch 应用里的界面或内容组件。
/// 负责Apple Watch 端展示与同步。
struct HabitDetailView: View {
    let snapshot: WatchRealtimeHealth
    let focus: HabitDetailFocus

    var body: some View {
        ZStack {
            WatchDetailBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch focus {
                    case .water:
                        habitCard(
                            title: String(localized: "喝水"),
                            value: "\(snapshot.waterIntakeMl) ml",
                            subtitle: String(localized: "目标 \(snapshot.waterTargetMl) ml"),
                            accent: .cyan,
                            advice: snapshot.waterCompletionRate >= 1 ? String(localized: "今天的补水目标已完成。") : String(localized: "离目标还差 \(max(0, snapshot.waterTargetMl - snapshot.waterIntakeMl)) ml。")
                        )
                    case .caffeine:
                        habitCard(
                            title: String(localized: "咖啡因"),
                            value: "\(snapshot.caffeineRemainedMg) mg",
                            subtitle: String(localized: "剩余建议摄入"),
                            accent: .orange,
                            advice: snapshot.caffeineRemainedMg > 80 ? String(localized: "今天还可以适量摄入。") : String(localized: "建议后半天尽量少喝，帮助夜间恢复。")
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .navigationTitle(focus == .water ? String(localized: "喝水") : String(localized: "咖啡因"))
    }

    private func habitCard(title: String, value: String, subtitle: String, accent: Color, advice: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: focus == .water ? "drop.fill" : "cup.and.saucer.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer()
                Text("详情")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            Text(value)
                .font(.watchAppSystem(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(advice)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// 身体年龄视图 由上级页面或路由调用，作为Apple Watch 应用里的界面或内容组件。
/// 负责Apple Watch 端展示与同步。
struct BodyAgeDetailView: View {
    let snapshot: WatchRealtimeHealth

    private var estimate: BodyAgeEstimate {
        makeBodyAgeEstimate(snapshot: snapshot)
    }

    var body: some View {
        ZStack {
            WatchDetailBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("身体年龄")
                            .font(.headline.weight(.semibold))
                        Text(estimate.valueText)
                            .font(.watchAppSystem(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                        Text(estimate.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前判断")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(bodyAgeSummary)
                            .font(.caption)
                        if let directionText = estimate.directionText {
                            Text(directionText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                        if let coverageText = estimate.coverageText {
                            Text(coverageText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("同步说明")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(estimate.guidance)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .navigationTitle("身体年龄")
    }

    private var bodyAgeSummary: String {
        if estimate.isSynced {
            return estimate.subtitle
        }
        return String(localized: "还没有拿到 iPhone 端正式身体年龄结果。同步完成后，这里会显示真实数值和状态文案。")
    }
}

/// 呼吸Session视图 由上级页面或路由调用，作为Apple Watch 应用里的界面或内容组件。
/// 负责Apple Watch 端展示与同步。
@Observable
private final class BreathingSessionPresentationState {
    var isBreathingIn = false
    var textPhase = String(localized: "吸气...")
}

struct BreathingSessionView: View {
    @State private var presentationState = BreathingSessionPresentationState()
    let timer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            WatchDetailBackground()
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("2 分钟呼吸放松")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(presentationState.textPhase)
                    .font(.title3)
                    .animation(.easeInOut(duration: 0.5), value: presentationState.textPhase)
                    .onReceive(timer) { _ in
                        presentationState.isBreathingIn.toggle()
                        presentationState.textPhase = presentationState.isBreathingIn ? String(localized: "呼气...") : String(localized: "吸气...")
                    }

                ZStack {
                    Circle()
                        .fill(Color.mint.opacity(0.28))
                        .frame(width: presentationState.isBreathingIn ? 150 : 80, height: presentationState.isBreathingIn ? 150 : 80)
                        .animation(.easeInOut(duration: 4), value: presentationState.isBreathingIn)

                    Circle()
                        .fill(Color.mint.opacity(0.56))
                        .frame(width: presentationState.isBreathingIn ? 120 : 60, height: presentationState.isBreathingIn ? 120 : 60)
                        .animation(.easeInOut(duration: 4), value: presentationState.isBreathingIn)
                }

                Text("跟随圆形节奏，慢慢吸气与呼气。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            presentationState.isBreathingIn = true
            presentationState.textPhase = String(localized: "吸气...")
        }
        .navigationTitle("呼吸放松")
    }
}

/// 睡眠Tab视图 由上级页面或路由调用，作为Apple Watch 应用里的界面或内容组件。
/// 负责Apple Watch 端展示与同步。
struct SleepTabView: View {
    var receiver: WatchConnectivityReceiver
    @AppStorage("daily_sleep_goal_hours") private var sleepGoalHours: Double = 8.0

    private var sleepDurationText: String {
        let minutes = receiver.latest?.sleepDurationMinutes ?? AppGroupManager.shared.getSleepDurationMinutes() ?? 0
        guard minutes > 0 else { return String(localized: "暂无同步数据") }
        return String(localized: "\(minutes / 60)小时\(minutes % 60)分")
    }

    private var sleepScoreText: String {
        let score = receiver.latest?.sleepScore ?? AppGroupManager.shared.getSleepScore() ?? 0
        return score > 0 ? String(localized: "\(score) 分") : String(localized: "等待记录")
    }

    var body: some View {
        ZStack {
            WatchDetailBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("昨夜睡眠")
                            .font(.headline.weight(.semibold))
                        Text(sleepDurationText)
                            .font(.watchAppSystem(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.mint)
                        Text("睡眠评分 \(sleepScoreText)")
                            .font(.caption)
                        Text("目标 \(sleepGoalHours, specifier: "%.1f") 小时")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .navigationTitle("睡眠")
        .onAppear {
            migrateLegacySleepGoalIfNeeded()
        }
    }

    private func migrateLegacySleepGoalIfNeeded() {
        let defaults = UserDefaults.standard
        let legacyKey = "sleepGoalHours"
        let currentKey = "daily_sleep_goal_hours"
        guard defaults.object(forKey: legacyKey) != nil else { return }
        if defaults.object(forKey: currentKey) == nil {
            defaults.set(defaults.double(forKey: legacyKey), forKey: currentKey)
        }
        defaults.removeObject(forKey: legacyKey)
    }
}

/// Activity摘要视图 由上级页面或路由调用，作为Apple Watch 应用里的界面或内容组件。
/// 负责Apple Watch 端展示与同步。
struct ActivitySummaryView: View {
    var receiver: WatchConnectivityReceiver

    private var snapshot: WatchRealtimeHealth? { receiver.latest }

    var body: some View {
        ZStack {
            WatchDetailBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let snapshot {
                        MetricProgressCard(title: String(localized: "步数"), valueText: "\(snapshot.steps)", goalText: "/ \(snapshot.stepsGoal)", progress: ratio(snapshot.steps, snapshot.stepsGoal), color: .green, icon: "figure.walk")
                        MetricProgressCard(title: String(localized: "消耗"), valueText: "\(snapshot.activeEnergy)", goalText: String(localized: "/ \(snapshot.activeEnergyGoal) 千卡"), progress: ratio(snapshot.activeEnergy, snapshot.activeEnergyGoal), color: .orange, icon: "flame.fill")
                        MetricProgressCard(title: String(localized: "锻炼"), valueText: String(localized: "\(snapshot.exerciseMinutes) 分钟"), goalText: String(localized: "/ \(snapshot.exerciseMinutesGoal) 分钟"), progress: ratio(snapshot.exerciseMinutes, snapshot.exerciseMinutesGoal), color: .mint, icon: "figure.run")
                        MetricProgressCard(title: String(localized: "站立"), valueText: String(localized: "\(snapshot.standHours) 小时"), goalText: String(localized: "/ \(snapshot.standHoursGoal) 小时"), progress: ratio(snapshot.standHours, snapshot.standHoursGoal), color: .cyan, icon: "figure.stand")
                    } else {
                        WatchSyncStatusCard(receiver: receiver)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .navigationTitle("活动")
    }
}

private struct MetricProgressCard: View {
    let title: String
    let valueText: String
    let goalText: String
    let progress: Double
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Text(goalText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(valueText)
                .font(.headline.bold())

            ProgressView(value: progress)
                .tint(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private func ratio(_ value: Int, _ goal: Int) -> Double {
    guard goal > 0 else { return 0 }
    return min(1, Double(value) / Double(goal))
}
