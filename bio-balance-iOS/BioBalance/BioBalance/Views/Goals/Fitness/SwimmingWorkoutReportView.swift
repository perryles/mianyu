/// SwimmingWorkoutReportView 由健身训练详情调用，展示 HealthKit 识别出的单次游泳专属报告。
/// 页面只呈现设备已写入的游泳数据；缺少泳池、划水或分趟数据时明确降级，不补估算值。

import SwiftUI
import Charts

struct SwimmingWorkoutReportView: View {
    @State private var workoutAnalysis: SwimmingWorkoutAnalysis?
    @State private var historySummary: SwimmingWorkoutHistorySummary?
    @State private var heartRateLoadState: HeartRateLoadState = .loading

    let report: SwimmingWorkoutReport

    private let aqua = Color(hex: "23B7C9")
    private let deepAqua = Color(hex: "087D8E")
    private let navy = Color(hex: "173B5E")
    private let paleAqua = Color(hex: "E9F8F8")

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroCard
            historyRankCard
            overviewCard
            heartRateCard
            paceOverTimeCard
            techniqueCard
            if !report.laps.isEmpty {
                recentSegmentsCard
                lapRhythmCard
                lapTableCard
            }
            dataSourceNote
        }
        .task(id: report.workoutID) {
            await loadWorkoutAnalysis()
            await loadHistorySummary()
        }
    }

    private var heroCard: some View {
        SwimmingHeroCard(
            title: String(localized: "游泳"),
            value: distanceValueText,
            unit: distanceUnitText,
            intervalText: workoutIntervalText,
            sourceText: report.deviceName ?? String(localized: "健康 App"),
            contextTags: swimContextTags,
            completionText: String(localized: "已完成 · 数据来自健康 App")
        )
    }

    @ViewBuilder
    private var historyRankCard: some View {
        if let history = historySummary {
            HStack(spacing: 12) {
                Image(systemName: "medal.fill")
                    .font(.appSystem(size: 17, weight: .black))
                    .foregroundColor(Color(hex: "178ED0"))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: "178ED0").opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "本月第 \(history.monthRank) 次游泳"))
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(navy)
                    Text(yearlyHistoryText(history))
                        .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 8)

                Text(verbatim: "#\(history.monthRank)")
                    .font(.appSystem(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "178ED0"))
            }
            .reportCardStyle()
            .accessibilityElement(children: .combine)
        }
    }

    private var overviewCard: some View {
        ModernReportMetricsPanel(
            title: String(localized: "游泳数据"),
            metrics: [
                ModernReportMetric(
                    title: String(localized: "游泳时长"),
                    value: durationText(report.duration),
                    tint: aqua,
                    symbol: "timer"
                ),
                ModernReportMetric(
                    title: String(localized: "活动消耗"),
                    value: energyText,
                    tint: Color(hex: "E66C60"),
                    symbol: "flame.fill"
                ),
                ModernReportMetric(
                    title: String(localized: "平均配速"),
                    value: paceText,
                    tint: Color(hex: "627CE6"),
                    symbol: "speedometer"
                ),
                ModernReportMetric(
                    title: String(localized: "平均心率"),
                    value: averageHeartRateText,
                    tint: Color(hex: "DD5B72"),
                    symbol: "heart.fill"
                ),
                ModernReportMetric(
                    title: String(localized: "趟数"),
                    value: report.laps.isEmpty ? String(localized: "暂无") : String(localized: "\(report.laps.count) 趟"),
                    tint: Color(hex: "4BA76C"),
                    symbol: "arrow.left.and.right"
                ),
                ModernReportMetric(
                    title: "SWOLF",
                    value: report.swolfScore.map(String.init) ?? String(localized: "暂无"),
                    tint: deepAqua,
                    symbol: "water.waves"
                )
            ]
        )
    }

    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("心率变化", symbol: "heart.text.square.fill")
                Spacer()
                if let peak = workoutAnalysis?.peakHeartRate {
                    Text("最高 \(Int(peak.rounded())) bpm")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            if let analysis = workoutAnalysis, analysis.hasHeartRateChart {
                Chart(analysis.heartRateSamples) { sample in
                    AreaMark(
                        x: .value("时间", sample.offset),
                        y: .value("心率", sample.beatsPerMinute)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "DD5B72").opacity(0.22), Color(hex: "DD5B72").opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("时间", sample.offset),
                        y: .value("心率", sample.beatsPerMinute)
                    )
                    .foregroundStyle(Color(hex: "C44760"))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 180)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine().foregroundStyle(Theme.Colors.textTertiary.opacity(0.12))
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) { Text(shortDuration(seconds)) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Theme.Colors.textTertiary.opacity(0.12))
                        AxisValueLabel {
                            if let bpm = value.as(Double.self) { Text("\(Int(bpm.rounded()))") }
                        }
                    }
                }
                .accessibilityLabel("游泳训练心率曲线")
                .accessibilityValue(heartRateChartAccessibilityText(analysis))
            } else {
                unavailableChartState(
                    title: heartRateEmptyTitle,
                    detail: heartRateEmptyDetail,
                    symbol: "heart.slash"
                )
            }
        }
        .reportCardStyle()
    }

    private var paceOverTimeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("分趟配速", symbol: "speedometer")
                Spacer()
                Text("每 100 米")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            let paceLaps = report.laps.filter { $0.paceSecondsPer100Meters != nil }
            if paceLaps.isEmpty {
                unavailableChartState(
                    title: "暂无分趟配速",
                    detail: "需要有效的分趟时长和距离。",
                    symbol: "speedometer"
                )
            } else {
                Chart(paceLaps) { lap in
                    if let pace = lap.paceSecondsPer100Meters {
                        LineMark(
                            x: .value("趟数", lap.index),
                            y: .value("秒 / 100 米", pace)
                        )
                        .foregroundStyle(deepAqua)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        PointMark(
                            x: .value("趟数", lap.index),
                            y: .value("秒 / 100 米", pace)
                        )
                        .foregroundStyle(aqua)
                    }
                }
                .frame(height: 170)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(paceLaps.count, 6))) { value in
                        AxisValueLabel {
                            if let index = value.as(Int.self) { Text("\(index)") }
                        }
                        AxisGridLine().foregroundStyle(Color.clear)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Theme.Colors.textTertiary.opacity(0.12))
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) { Text(shortDuration(seconds)) }
                        }
                    }
                }
                .accessibilityLabel("游泳分趟配速曲线")
                .accessibilityValue("共 \(paceLaps.count) 个有效分趟配速点")
            }
        }
        .reportCardStyle()
    }

    private var techniqueCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                sectionTitle("泳姿与效率", symbol: "water.waves")
                Spacer()
                Text(report.dominantStroke?.title ?? "等待泳姿数据")
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(deepAqua)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(paleAqua, in: Capsule())
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                efficiencyTile(
                    value: report.swolfScore.map(String.init) ?? "--",
                    label: "SWOLF",
                    detail: report.swolfScore == nil ? "等待 HealthKit 或完整逐趟数据" : "来自 HealthKit 或完整逐趟数据"
                )
                efficiencyTile(
                    value: strokesPer100MetersText,
                    label: "每 100 米划水",
                    detail: report.strokeCount == nil || report.distanceMeters == nil ? "等待设备写入" : "用于观察动作经济性"
                )
                efficiencyTile(
                    value: strokeRateText,
                    label: "划水率（次/分钟）",
                    detail: report.strokesPerMinute == nil ? "等待划水与时长数据" : "来自本次训练的实际划水与记录时长"
                )
            }

            if !strokeDistribution.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(strokeDistribution, id: \.stroke) { item in
                        HStack(spacing: 10) {
                            Text(item.stroke.title)
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(navy)
                                .frame(width: 62, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(aqua.opacity(0.10))
                                    Capsule()
                                        .fill(aqua)
                                        .frame(width: proxy.size.width * item.fraction)
                                }
                            }
                            .frame(height: 8)
                            Text("\(Int((item.fraction * 100).rounded()))%")
                                .font(.appSystem(size: 11, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            } else {
                Label("设备未提供分趟泳姿，本次仅展示已同步的总量指标。", systemImage: "info.circle")
                    .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .reportCardStyle()
    }

    private var recentSegmentsCard: some View {
        let recentLaps = Array(report.laps.suffix(4))
        let fastestLap = recentLaps.min(by: { $0.duration < $1.duration })

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("分段表现", symbol: "square.split.2x1.fill")
                Spacer()
                Text(recentSegmentsSubtitle(recentLaps))
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            ForEach(Array(recentLaps.enumerated()), id: \.element.id) { offset, lap in
                if offset > 0 {
                    Divider().overlay(Theme.Colors.textTertiary.opacity(0.10))
                }
                recentSegmentRow(lap: lap, isFastest: lap.id == fastestLap?.id)
            }
        }
        .reportCardStyle()
    }

    private func recentSegmentRow(lap: SwimmingLapReport, isFastest: Bool) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(lap.index)")
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "178ED0"))
                .frame(width: 26, height: 26)
                .background(Color(hex: "178ED0").opacity(0.10), in: Circle())
                .accessibilityLabel(Text("第 \(lap.index) 趟"))

            VStack(alignment: .leading, spacing: 2) {
                Text(shortDuration(lap.duration))
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(navy)
                if let pace = lap.paceSecondsPer100Meters {
                    Text(String(localized: "配速 \(shortDuration(pace)) /100m"))
                        .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            Spacer(minLength: 8)

            if isFastest {
                Text("最快")
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "0E9D4A"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: "DDF8E9"), in: Capsule())
            } else if let fastestDuration = fastestRecentDuration, lap.duration > fastestDuration {
                Text(verbatim: "+\(Int((lap.duration - fastestDuration).rounded()))s")
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var fastestRecentDuration: TimeInterval? {
        report.laps.suffix(4).map(\.duration).min()
    }

    private func yearlyHistoryText(_ history: SwimmingWorkoutHistorySummary) -> String {
        let year = Calendar.current.component(.year, from: report.startDate)
        return String(localized: "\(year) 年累计 \(history.yearlyWorkoutCount) 次 · 共 \(historyDistanceText(history.yearlyDistanceMeters))")
    }

    private func historyDistanceText(_ meters: Double) -> String {
        guard meters.isFinite, meters > 0 else { return String(localized: "0 m") }
        if meters >= 1_000 {
            return String(format: "%.1f km", meters / 1_000)
        }
        return String(format: "%.0f m", meters)
    }

    private func recentSegmentsSubtitle(_ laps: [SwimmingLapReport]) -> String {
        let lapDistance = laps.compactMap(\.distanceMeters).first ?? report.poolLengthMeters
        if let lapDistance, lapDistance > 0 {
            return String(localized: "最近 \(laps.count) × \(meterText(lapDistance))")
        }
        return String(localized: "最近 \(laps.count) 趟")
    }

    private var lapRhythmCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("分趟节奏", symbol: "chart.xyaxis.line")
                Spacer()
                Text("每趟用时")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Chart(report.laps) { lap in
                AreaMark(
                    x: .value("趟数", lap.index),
                    y: .value("秒", lap.duration)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [aqua.opacity(0.24), aqua.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("趟数", lap.index),
                    y: .value("秒", lap.duration)
                )
                .foregroundStyle(deepAqua)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                PointMark(
                    x: .value("趟数", lap.index),
                    y: .value("秒", lap.duration)
                )
                .foregroundStyle(aqua)
                .symbolSize(22)
            }
            .frame(height: 180)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(report.laps.count, 6))) { value in
                    AxisValueLabel {
                        if let index = value.as(Int.self) { Text("\(index)") }
                    }
                    AxisGridLine().foregroundStyle(Color.clear)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Theme.Colors.textTertiary.opacity(0.12))
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) { Text(shortDuration(seconds)) }
                    }
                }
            }
            .accessibilityLabel("游泳分趟用时")
            .accessibilityValue(lapChartAccessibilityText)
        }
        .reportCardStyle()
    }

    private var lapTableCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("分趟明细", symbol: "list.number")

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 8) {
                    lapTableRow(
                        lap: nil,
                        labels: ["趟", "距离", "用时", "配速", "泳姿", "划水", "SWOLF"]
                    )

                    ForEach(report.laps.prefix(60)) { lap in
                        Divider().overlay(Theme.Colors.textTertiary.opacity(0.10))
                        lapTableRow(lap: lap)
                    }
                }
                .frame(minWidth: 400, alignment: .leading)
            }

            if report.laps.count > 60 {
                Text("本次共 \(report.laps.count) 趟，当前展示前 60 趟。")
                    .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .reportCardStyle()
    }

    private var dataSourceNote: some View {
        Label(
            "报告来自健康 App 中这次游泳训练的原始记录；未显示的指标代表设备没有写入或尚未授权。",
            systemImage: "heart.text.square.fill"
        )
        .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
        .foregroundColor(Theme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }

    private enum HeartRateLoadState {
        case loading
        case loaded
        case noData
        case insufficientData
        case unavailable
    }

    @MainActor
    private func loadHistorySummary() async {
        historySummary = try? await HealthKitManager.shared.fetchSwimmingWorkoutHistorySummary(for: report.workoutID)
    }

    @MainActor
    private func loadWorkoutAnalysis() async {
        heartRateLoadState = .loading
        workoutAnalysis = nil
        do {
            guard let analysis = try await HealthKitManager.shared.fetchSwimmingWorkoutAnalysis(for: report.workoutID) else {
                heartRateLoadState = .noData
                return
            }
            workoutAnalysis = analysis
            if analysis.heartRateSamples.isEmpty {
                heartRateLoadState = .noData
            } else if !analysis.hasHeartRateChart {
                heartRateLoadState = .insufficientData
            } else {
                heartRateLoadState = .loaded
            }
        } catch {
            heartRateLoadState = .unavailable
        }
    }

    private var averageHeartRateText: String {
        guard let average = workoutAnalysis?.averageHeartRate, average.isFinite, average > 0 else { return "暂无" }
        return "\(Int(average.rounded())) bpm"
    }

    private var heartRateEmptyTitle: String {
        switch heartRateLoadState {
        case .loading: return "正在读取心率"
        case .loaded: return "心率已加载"
        case .noData: return "暂无心率曲线"
        case .insufficientData: return "心率样本不足"
        case .unavailable: return "无法读取心率"
        }
    }

    private var heartRateEmptyDetail: String {
        switch heartRateLoadState {
        case .loading: return "正在读取这次训练关联的 HealthKit 样本。"
        case .loaded: return "心率曲线已加载。"
        case .noData: return "健康 App 没有返回这次训练的心率样本。"
        case .insufficientData: return "只返回了一个心率样本，无法绘制时间曲线。"
        case .unavailable: return "暂时无法读取这次训练的心率样本。"
        }
    }

    @ViewBuilder
    private func unavailableChartState(title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.appSystem(size: 24, weight: .semibold))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(title)
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(navy)
            Text(detail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .accessibilityElement(children: .combine)
    }

    private func heartRateChartAccessibilityText(_ analysis: SwimmingWorkoutAnalysis) -> String {
        guard let first = analysis.heartRateSamples.first,
              let last = analysis.heartRateSamples.last else { return "暂无心率曲线" }
        return "\(analysis.heartRateSamples.count) 个采样点，\(shortDuration(first.offset)) 至 \(shortDuration(last.offset))"
    }

    @ViewBuilder
    private func lapTableRow(lap: SwimmingLapReport?, labels: [String]? = nil) -> some View {
        HStack(spacing: 8) {
            tableText(labels?[0] ?? "\(lap?.index ?? 0)", width: 30, alignment: .leading, isHeader: labels != nil)
            tableText(labels?[1] ?? lap?.distanceMeters.map { meterText($0) } ?? "--", width: 56, alignment: .trailing, isHeader: labels != nil)
            tableText(labels?[2] ?? lap.map { shortDuration($0.duration) } ?? "--", width: 56, alignment: .trailing, isHeader: labels != nil)
            tableText(labels?[3] ?? lap?.paceSecondsPer100Meters.map { "\(shortDuration($0))" } ?? "--", width: 68, alignment: .trailing, isHeader: labels != nil)
            tableText(labels?[4] ?? lap?.stroke.title ?? "--", width: 72, alignment: .leading, isHeader: labels != nil)
            tableText(labels?[5] ?? lap?.strokeCount.map(String.init) ?? "--", width: 48, alignment: .trailing, isHeader: labels != nil)
            tableText(labels?[6] ?? lap?.swolfScore.map(String.init) ?? "--", width: 48, alignment: .trailing, isHeader: labels != nil)
        }
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.appSystem(size: 18, weight: .black, design: .rounded))
            .foregroundColor(navy)
    }

    private func efficiencyTile(value: String, label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.appSystem(size: 28, weight: .black, design: .rounded))
                .foregroundColor(deepAqua)
            Text(label)
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(navy)
            Text(detail)
                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(14)
        .background(paleAqua, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func tableText(
        _ text: String,
        width: CGFloat,
        alignment: Alignment,
        isHeader: Bool = false
    ) -> some View {
        Text(text)
            .font(.appSystem(size: isHeader ? 10 : 12, weight: isHeader ? .black : .semibold, design: .rounded))
            .foregroundColor(isHeader ? Theme.Colors.textTertiary : navy)
            .frame(width: width, alignment: alignment)
            .lineLimit(1)
    }

    private var distanceValueText: String {
        guard let meters = report.distanceMeters, meters.isFinite, meters >= 0 else { return "--" }
        if meters >= 10_000 {
            return String(format: "%.2f", meters / 1_000)
        }
        return Int(meters.rounded()).formatted(.number.grouping(.automatic))
    }

    private var distanceUnitText: String {
        guard let meters = report.distanceMeters, meters.isFinite, meters >= 0 else { return "m" }
        return meters >= 10_000 ? "km" : "m"
    }

    private var workoutIntervalText: String {
        let start = report.startDate.formatted(date: .abbreviated, time: .shortened)
        let end = report.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    private var swimContextTags: [String] {
        var tags = [swimmingTitle]
        if report.location == .pool, let poolLengthMeters = report.poolLengthMeters {
            tags.append(String(localized: "\(meterText(poolLengthMeters)) 泳池"))
        }
        if let dominantStroke = report.dominantStroke {
            tags.append(String(localized: "\(dominantStroke.title)为主"))
        }
        return tags
    }

    private var swimmingTitle: String {
        switch report.location {
        case .pool: return String(localized: "泳池游泳")
        case .openWater: return String(localized: "开放水域游泳")
        case .unknown: return String(localized: "游泳训练")
        }
    }

    private var lapChartAccessibilityText: String {
        guard let fastest = report.laps.min(by: { $0.duration < $1.duration }),
              let slowest = report.laps.max(by: { $0.duration < $1.duration }) else {
            return String(localized: "暂无分趟数据")
        }
        return String(localized: "共 \(report.laps.count) 趟，最快第 \(fastest.index) 趟 \(shortDuration(fastest.duration))，最慢第 \(slowest.index) 趟 \(shortDuration(slowest.duration))")
    }

    private var paceText: String {
        guard let seconds = report.averagePaceSecondsPer100Meters else { return "暂无" }
        return "\(shortDuration(seconds)) /100m"
    }

    private var poolLengthText: String {
        switch report.location {
        case .openWater: return "开放水域"
        case .pool, .unknown:
            return report.poolLengthMeters.map(meterText) ?? "暂无"
        }
    }

    private var strokesPer100MetersText: String {
        guard let strokes = report.strokeCount,
              let distance = report.distanceMeters,
              distance > 0 else { return "--" }
        return String(format: "%.1f", Double(strokes) / distance * 100)
    }

    private var strokeRateText: String {
        guard let rate = report.strokesPerMinute else { return "--" }
        return String(format: "%.1f", rate)
    }

    private var energyText: String {
        guard let energy = report.activeEnergyKilocalories,
              energy.isFinite, energy >= 0 else { return "暂无" }
        return "\(Int(energy.rounded())) kcal"
    }

    private var strokeDistribution: [(stroke: SwimmingStroke, fraction: Double)] {
        let knownLaps = report.laps.filter { $0.stroke != .unknown }
        let totalDuration = knownLaps.reduce(0) { $0 + max(0, $1.duration) }
        guard totalDuration > 0 else { return [] }
        return Dictionary(grouping: knownLaps, by: \.stroke)
            .map { stroke, laps in
                (stroke, laps.reduce(0) { $0 + max(0, $1.duration) } / totalDuration)
            }
            .sorted { $0.fraction > $1.fraction }
    }

    private func optionalCount(_ value: Int?) -> String {
        value.map { "\($0) 次" } ?? "暂无"
    }

    private func durationText(_ interval: TimeInterval) -> String {
        SwimmingMetricsCalculator.durationText(interval) ?? "00:00"
    }

    private func shortDuration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func meterText(_ meters: Double) -> String {
        if meters >= 10_000 { return String(format: "%.2f km", meters / 1_000) }
        return String(format: "%.0f m", meters)
    }
}

private struct SwimmingHeroCard: View {
    let title: String
    let value: String
    let unit: String
    let intervalText: String
    let sourceText: String
    let contextTags: [String]
    let completionText: String

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 23
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 78
    @ScaledMetric(relativeTo: .title) private var unitSize: CGFloat = 34
    @ScaledMetric(relativeTo: .caption) private var metaSize: CGFloat = 12

    private var foreground: Color {
        colorScheme == .dark ? Color(hex: "D9FBFF") : Color(hex: "0A5F98")
    }

    private var secondaryForeground: Color {
        colorScheme == .dark ? .white.opacity(0.70) : Color(hex: "697187")
    }

    private var heroBackground: [Color] {
        colorScheme == .dark
            ? [Color(hex: "063443"), Color(hex: "04212C"), Color(hex: "010D12")]
            : [Color(hex: "D8F7FF"), Color(hex: "EDFAFF"), Color(hex: "F8FBFD")]
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: heroBackground,
                startPoint: .top,
                endPoint: .bottom
            )

            SwimmingHeroSurface()
                .foregroundStyle(foreground.opacity(0.08))

            SwimmingHeroWave()
                .frame(height: 66)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.pool.swim")
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(foreground)
                    Text(verbatim: title)
                        .font(.appSystem(size: titleSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(foreground)
                }

                HStack(alignment: .lastTextBaseline, spacing: 7) {
                    Text(verbatim: value)
                        .font(.appSystem(size: valueSize, weight: .black, design: .rounded))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.36)
                        .allowsTightening(true)

                    Text(verbatim: unit)
                        .font(.appSystem(size: unitSize, weight: .heavy, design: .rounded).italic())
                        .foregroundStyle(foreground.opacity(0.20))
                        .textCase(.uppercase)
                }

                VStack(alignment: .leading, spacing: 5) {
                    metaRow(
                        items: [intervalText, sourceText],
                        symbols: ["calendar", "watch.smartphone"]
                    )
                    metaRow(items: contextTags, symbols: Array(repeating: "circle.fill", count: contextTags.count))
                }

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.appSystem(size: metaSize, weight: .black))
                    Text(verbatim: completionText)
                        .font(.appSystem(size: metaSize, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Color(hex: "0E9D4A"))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color(hex: "DDF8E9"), in: Capsule())
                .accessibilityLabel(Text(verbatim: completionText))
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 50)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func metaRow(items: [String], symbols: [String]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Label {
                        Text(verbatim: item)
                    } icon: {
                        Image(systemName: symbols[index])
                            .font(.system(size: 8, weight: .black))
                    }
                    .font(.appSystem(size: metaSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryForeground)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Label {
                        Text(verbatim: item)
                    } icon: {
                        Image(systemName: symbols[index])
                            .font(.system(size: 8, weight: .black))
                    }
                    .font(.appSystem(size: metaSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryForeground)
                }
            }
        }
    }
}

private struct SwimmingHeroSurface: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                SwimSurfaceShape()
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.92), Color.white.opacity(0.18), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ))

                Circle()
                    .fill(Color.white.opacity(0.70))
                    .frame(width: 74, height: 74)
                    .blur(radius: 6)
                    .position(x: proxy.size.width * 0.20, y: proxy.size.height * 0.09)

                Circle()
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 92, height: 92)
                    .blur(radius: 7)
                    .position(x: proxy.size.width * 0.72, y: proxy.size.height * 0.07)
            }
        }
        .allowsHitTesting(false)
    }
}

nonisolated private struct SwimSurfaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.72))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY * 0.72),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.18)
        )
        path.closeSubpath()
        return path
    }
}

private struct SwimmingHeroWave: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule()
                    .fill(Color(hex: "3FB5EB").opacity(0.23))
                    .frame(width: proxy.size.width * 1.28, height: 54)
                    .rotationEffect(.degrees(-2))
                    .position(x: proxy.size.width / 2, y: 24)

                Capsule()
                    .fill(Color(hex: "439CE0").opacity(0.16))
                    .frame(width: proxy.size.width * 1.28, height: 50)
                    .rotationEffect(.degrees(2))
                    .position(x: proxy.size.width / 2, y: 42)
            }
        }
        .accessibilityHidden(true)
    }
}

private extension View {
    func reportCardStyle() -> some View {
        self.healthDetailSurface(padding: 18)
    }
}
