/// PressureDetailView 由今日页压力卡片调用，作为「压力详情」深度分析页。
/// 负责展示压力趋势、HRV/静息心率联动、评估结果与历史关联。

import SwiftUI
import Charts
import OSLog

/// 压力视图 由上级页面或路由调用，作为压力模块里的界面或内容组件。
/// 负责压力模块展示与分析。
struct PressureDetailView: View {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "StressPage")
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let history: HealthHistory?
    let preferredAssessment: StressPresentationAssessment?
    let preferredRealtimeHealth: RealtimeHealth?
    let preferredAvgHrvToday: Double?
    let preferredRecentAvgHrv: Double?
    let preferredRestingHeartRate: Double?
    let preferredRecentAvgRestingHeartRate: Double?
    let preferredSevenMinuteStressPoints: [TimeSeriesPoint]
    let initialReferenceDate: Date
    let isModalPresentation: Bool

    private let dayStressBucketSeconds: Int64 = 20 * 60
    private let dayStressInterpolationBucketSeconds: Int64 = 10 * 60
    private let dayStressInterpolationMaximumGapSeconds: Int64 = 120 * 60

    @State private var healthKitPoints: [TimeSeriesPoint] = []
    @State private var localAssessment: StressPresentationAssessment
    @State private var currentHrv: Double?
    @State private var avgHrvToday: Double?
    @State private var recentAvgHrv: Double?
    @State private var currentBpm: Double?
    @State private var restingHeartRate: Double?
    @State private var recentAvgRestingHeartRate: Double?
    @State private var stressEstimationRestingHeartRateBaseline: Double?
    @State private var todayHrvSamples: [TimeSeriesPointDouble] = []
    @State private var todayHeartRateSamples: [TimeSeriesPoint] = []
    @State private var monthlyHrvAverages: [TimeSeriesPointDouble] = []
    @State private var restingHeartRateAverages: [TimeSeriesPointDouble] = []
    @State private var rangeHrvAverages: [TimeSeriesPointDouble] = []
    @State private var rangeHeartRateAverages: [TimeSeriesPointDouble] = []
    @State private var rangeRestingHeartRateAverages: [TimeSeriesPointDouble] = []
    @State private var sleepIntervals: [DateInterval] = []
    @State private var isLoading = false
    @State private var animateHero = false
    @State private var showingDeepAnalysis = false
    @State private var selectedPeriod: PressureDetailPeriod = .day
    @State private var referenceDate: Date
    @State private var selectedReferenceStressTimestamp: Int64?

    init(
        history: HealthHistory?,
        preferredAssessment: StressPresentationAssessment? = nil,
        preferredRealtimeHealth: RealtimeHealth? = nil,
        preferredAvgHrvToday: Double? = nil,
        preferredRecentAvgHrv: Double? = nil,
        preferredRestingHeartRate: Double? = nil,
        preferredRecentAvgRestingHeartRate: Double? = nil,
        preferredSevenMinuteStressPoints: [TimeSeriesPoint] = [],
        initialReferenceDate: Date = Date(),
        isModalPresentation: Bool = false
    ) {
        self.history = history
        self.preferredAssessment = preferredAssessment
        self.preferredRealtimeHealth = preferredRealtimeHealth
        self.preferredAvgHrvToday = preferredAvgHrvToday
        self.preferredRecentAvgHrv = preferredRecentAvgHrv
        self.preferredRestingHeartRate = preferredRestingHeartRate
        self.preferredRecentAvgRestingHeartRate = preferredRecentAvgRestingHeartRate
        self.preferredSevenMinuteStressPoints = preferredSevenMinuteStressPoints
        self.initialReferenceDate = Calendar.current.startOfDay(for: initialReferenceDate)
        self.isModalPresentation = isModalPresentation

        let fallbackAssessment = StressPresentation.assessment(
            from: StressPresentation.evaluation(from: preferredRealtimeHealth)
        )

        _localAssessment = State(initialValue: preferredAssessment ?? fallbackAssessment)
        _currentHrv = State(initialValue: preferredRealtimeHealth.flatMap { $0.hrv > 0 ? $0.hrv : nil })
        _avgHrvToday = State(initialValue: preferredAvgHrvToday)
        _recentAvgHrv = State(initialValue: preferredRecentAvgHrv)
        _currentBpm = State(initialValue: preferredRealtimeHealth.flatMap { $0.bpm > 0 ? Double($0.bpm) : nil })
        _restingHeartRate = State(initialValue: preferredRestingHeartRate)
        _recentAvgRestingHeartRate = State(initialValue: preferredRecentAvgRestingHeartRate)
        _stressEstimationRestingHeartRateBaseline = State(initialValue: preferredRestingHeartRate ?? preferredRecentAvgRestingHeartRate)
        self.referenceDate = self.initialReferenceDate
    }

    private var chartData: [TimeSeriesPoint] {
        if Calendar.current.isDateInToday(referenceDate), !healthKitPoints.isEmpty {
            return healthKitPoints
        }
        return todayHistoryStress
    }

    private var todayHistoryStress: [TimeSeriesPoint] {
        let start = Calendar.current.startOfDay(for: referenceDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
        return (history?.stressPoints ?? []).filter { $0.date >= start && $0.date < end }
    }

    private var style: StressVisualStyle {
        StressVisualStyle.style(for: activeAssessment.band)
    }

    private var preferredStressValue: Int? {
        if let realtime = preferredRealtimeHealth?.stress_value, realtime > 0 {
            return realtime
        }
        if let score = localAssessment.score, score > 0 {
            return score
        }
        return activeStressPoints.last?.value
    }

    private var latestStress: Int {
        if selectedPeriod == .day {
            return preferredStressValue ?? 0
        }
        return activeStressPoints.last?.value ?? 0
    }
    
    private var peakStress: Int {
        activeStressPoints.map(\.value).max() ?? localAssessment.score ?? 0
    }

    private var averageStress: Int {
        guard !activeStressPoints.isEmpty else { return localAssessment.score ?? 0 }
        let total = activeStressPoints.map(\.value).reduce(0, +)
        return Int((Double(total) / Double(activeStressPoints.count)).rounded())
    }

    private var chartDomain: ClosedRange<Date> {
        guard selectedPeriod == .day else { return periodRange }
        let start = Calendar.current.startOfDay(for: referenceDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(24 * 60 * 60)
        return start...end
    }

    private var axisDates: [Date] {
        let calendar = Calendar.current
        switch selectedPeriod {
        case .day:
            let start = calendar.startOfDay(for: referenceDate)
            return [0, 6, 12, 18, 24].compactMap { hour in
                calendar.date(byAdding: .hour, value: hour, to: start)
            }
        case .week:
            let start = calendar.startOfDay(for: periodRange.lowerBound)
            return [0, 2, 4, 6].compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: start)
            }
        case .month:
            let start = calendar.startOfDay(for: periodRange.lowerBound)
            let totalDays = max(1, calendar.dateComponents([.day], from: start, to: periodRange.upperBound).day ?? 30)
            let offsets = stride(from: 0, through: totalDays, by: max(1, totalDays / 4)).map { $0 }
            return offsets.compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: start)
            }
        case .year:
            let start = calendar.startOfDay(for: periodRange.lowerBound)
            return [0, 3, 6, 9, 11].compactMap { monthOffset in
                calendar.date(byAdding: .month, value: monthOffset, to: start)
            }
        }
    }

    private var stressAxisDates: [Date] {
        guard selectedPeriod == .day else { return axisDates }
        let start = Calendar.current.startOfDay(for: referenceDate)
        let bucketOffsets = stride(from: 0, to: 24 * 60, by: 20)
        let labeledOffsets = stride(from: 0, through: 24 * 60, by: 3 * 60)
        return Set(bucketOffsets).union(labeledOffsets).sorted().compactMap {
            Calendar.current.date(byAdding: .minute, value: $0, to: start)
        }
    }

    private var chartDayEnd: Date {
        chartDomain.upperBound
    }

    private var effectiveStressPoints: [TimeSeriesPoint] {
        if !healthKitPoints.isEmpty {
            return healthKitPoints
        }
        return history?.stressPoints ?? []
    }

    private var chartSampleBadgeText: String {
        guard !activeStressPoints.isEmpty else { return String(localized: "等待样本") }
        guard selectedPeriod == .day else {
            return String(localized: "\(activeStressPoints.count) 个时间点")
        }
        return String(localized: "\(activeStressPoints.count) 个样本 · \(chartEstimatedTimestamps.count) 个估算")
    }

    private var modalAssessmentSubtitle: String {
        if selectedPeriod != .day {
            return selectedPeriod.insightSubtitle
        }
        if let average = recentAvgHrv {
            return String(localized: "近 30 天平均 HRV \(Int(average.rounded())) ms")
        }
        return activeAssessment.adviceTitle
    }

    private var hrvSummaryValueText: String {
        if selectedPeriod != .day {
            guard let value = rangeAverageHrv else { return "暂无" }
            return String(localized: "\(Int(value.rounded())) 毫秒")
        }
        let value = avgHrvToday ?? currentHrv
        return value.map { "\(Int($0.rounded())) 毫秒" } ?? "暂无"
    }

    private var hrvComparisonText: String {
        if selectedPeriod != .day {
            guard let rangeAverage = rangeAverageHrv else {
                return String(localized: "等待 \(selectedPeriod.shortTitle) 内 HRV 同步")
            }
            guard let baseline = recentAvgHrv, baseline > 0 else {
                return String(localized: "近 30 天平均暂不可用")
            }
            let delta = Int((rangeAverage - baseline).rounded())
            let prefix = delta > 0 ? "+" : ""
            if delta == 0 {
                return String(localized: "30 天平均: \(Int(baseline.rounded())) 毫秒")
            }
            return String(localized: "\(prefix)\(delta) vs 30 天平均 \(Int(baseline.rounded())) 毫秒")
        }
        guard let today = avgHrvToday ?? currentHrv else {
            return String(localized: "等待今日 HRV 同步")
        }
        guard let baseline = recentAvgHrv, baseline > 0 else {
            return String(localized: "近 30 天平均暂不可用")
        }
        let delta = Int((today - baseline).rounded())
        if delta == 0 {
            return String(localized: "30 天平均: \(Int(baseline.rounded())) 毫秒")
        }
        let prefix = delta > 0 ? "+" : ""
        return String(localized: "\(prefix)\(delta) vs 30 天平均 \(Int(baseline.rounded())) 毫秒")
    }

    private var latestHrvNoteText: String {
        if selectedPeriod != .day {
            guard let latest = filteredHrvAverages.last?.value else { return "最近记录等待同步" }
            return String(localized: "最近记录 \(Int(latest.rounded())) 毫秒")
        }
        guard let latest = todayHrvSamples.last?.value ?? (avgHrvToday ?? currentHrv) else {
            return String(localized: "最新记录等待同步")
        }
        return String(localized: "最新记录 \(Int(latest.rounded())) 毫秒")
    }

    private var peakStressPoint: TimeSeriesPoint? {
        activeStressPoints.max { lhs, rhs in lhs.value < rhs.value }
    }

    private var lowStressPoint: TimeSeriesPoint? {
        activeStressPoints.min { lhs, rhs in lhs.value < rhs.value }
    }

    private var referenceDisplayPoints: [TimeSeriesPoint] {
        chartDisplayPoints.sorted { $0.date < $1.date }
    }

    private var recentWeekStressSummaries: [PressureDailySummary] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        let filtered = effectiveStressPoints.filter { point in
            let day = calendar.startOfDay(for: point.date)
            return day >= start && day <= end
        }

        let grouped = Dictionary(grouping: filtered) { point in
            calendar.startOfDay(for: point.date)
        }

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let items = grouped[date] ?? []
            let average = items.isEmpty ? nil : Int((Double(items.map(\.value).reduce(0, +)) / Double(items.count)).rounded())
            return PressureDailySummary(date: date, averageValue: average, isToday: calendar.isDateInToday(date))
        }
    }

    private var activeAssessment: StressPresentationAssessment {
        guard selectedPeriod != .day else { return localAssessment }
        let score = activeAverageStress
        guard score > 0 else {
            return StressPresentationAssessment(
                score: nil,
                band: .waiting,
                title: "等待数据",
                adviceTitle: "当前时间范围内还没有足够样本。",
                adviceDetail: "继续同步 HRV、心率和静息心率后，就能看到这个时间窗口的压力趋势。",
                tint: .tertiary,
                updatedAtSeconds: nil
            )
        }
        return StressPresentation.assessmentFromScore(score, now: referenceDate, updatedAtSeconds: Int64(referenceDate.timeIntervalSince1970))
    }

    private var activeStressPoints: [TimeSeriesPoint] {
        if selectedPeriod == .day {
            return dayMeasuredStressPoints
        }

        let source = (history?.stressPoints ?? []).sorted { $0.date < $1.date }
        let historyPoints: [TimeSeriesPoint]
        switch selectedPeriod {
        case .day:
            historyPoints = chartData
        case .week:
            historyPoints = aggregateStressPoints(source, bucket: .day, range: periodRange)
        case .month:
            historyPoints = aggregateStressPoints(source, bucket: .day, range: periodRange)
        case .year:
            historyPoints = aggregateStressPoints(source, bucket: .month, range: periodRange)
        }
        return mergeStressPoints(primary: historyPoints, fallback: estimatedStressPoints)
    }

    private var activeAverageStress: Int {
        guard !activeStressPoints.isEmpty else { return localAssessment.score ?? 0 }
        let total = activeStressPoints.map(\.value).reduce(0, +)
        return Int((Double(total) / Double(activeStressPoints.count)).rounded())
    }

    private var periodRange: ClosedRange<Date> {
        let interval = selectedPeriod.rollingRange.interval(anchorDate: referenceDate)
        return interval.start...interval.end.addingTimeInterval(-1)
    }

    /// 使用与今日页压力图一致的 20 分钟实测分桶。
    /// 估算点单独叠加，绝不计入汇总统计。
    private var dayMeasuredStressPoints: [TimeSeriesPoint] {
        let start = Calendar.current.startOfDay(for: referenceDate)
        let startTimestamp = Int64(start.timeIntervalSince1970)
        var valuesByBucket: [Int64: [Int]] = [:]

        for point in chartData where point.value > 0 && chartDomain.contains(point.date) {
            let bucketTimestamp = startTimestamp
                + (point.timestamp - startTimestamp) / dayStressBucketSeconds * dayStressBucketSeconds
            valuesByBucket[bucketTimestamp, default: []].append(point.value)
        }

        return valuesByBucket.compactMap { timestamp, values in
            guard !values.isEmpty else { return nil }
            let average = Double(values.reduce(0, +)) / Double(values.count)
            return TimeSeriesPoint(timestamp: timestamp, value: Int(average.rounded()))
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    private var dayStressTimelineSeries: StressChartInterpolationResult {
        guard selectedPeriod == .day else {
            return StressChartInterpolationResult(points: activeStressPoints, estimatedTimestamps: [])
        }
        return StressChartGapInterpolator.interpolate(
            points: dayMeasuredStressPoints,
            bucketSeconds: dayStressInterpolationBucketSeconds,
            maximumGapSeconds: dayStressInterpolationMaximumGapSeconds,
            domain: chartDomain,
            now: Date()
        )
    }

    private var chartDisplayPoints: [TimeSeriesPoint] {
        selectedPeriod == .day ? dayStressTimelineSeries.points : activeStressPoints
    }

    private var chartEstimatedTimestamps: Set<Int64> {
        selectedPeriod == .day ? dayStressTimelineSeries.estimatedTimestamps : []
    }

    private var chartBucketDuration: TimeInterval? {
        selectedPeriod == .day ? TimeInterval(dayStressInterpolationBucketSeconds) : nil
    }

    private var filteredHrvAverages: [TimeSeriesPointDouble] {
        monthlyHrvAverages
            .filter { periodRange.contains($0.date) }
            .sorted { $0.date < $1.date }
    }

    private var filteredRestingHeartRateAverages: [TimeSeriesPointDouble] {
        restingHeartRateAverages
            .filter { periodRange.contains($0.date) }
            .sorted { $0.date < $1.date }
    }

    private var filteredRangeHrvAverages: [TimeSeriesPointDouble] {
        rangeHrvAverages
            .filter { periodRange.contains($0.date) }
            .sorted { $0.date < $1.date }
    }

    private var filteredRangeHeartRateAverages: [TimeSeriesPointDouble] {
        rangeHeartRateAverages
            .filter { periodRange.contains($0.date) }
            .sorted { $0.date < $1.date }
    }

    private var filteredRangeRestingHeartRateAverages: [TimeSeriesPointDouble] {
        rangeRestingHeartRateAverages
            .filter { periodRange.contains($0.date) }
            .sorted { $0.date < $1.date }
    }

    private var estimatedDailyStressPoints: [TimeSeriesPoint] {
        guard selectedPeriod != .day else { return [] }

        return HealthStressEstimator.estimateDailyStress(
            hrv: filteredRangeHrvAverages,
            heartRate: filteredRangeHeartRateAverages,
            restingHeartRate: filteredRangeRestingHeartRateAverages,
            restingHeartRateBaseline: stressEstimationRestingHeartRateBaseline
        ).map {
            TimeSeriesPoint(timestamp: $0.timestamp, value: Int($0.value.rounded()))
        }
    }

    private var estimatedStressPoints: [TimeSeriesPoint] {
        let derivedDailyStress = estimatedDailyStressPoints

        guard !derivedDailyStress.isEmpty else { return [] }

        switch selectedPeriod {
        case .day:
            return []
        case .week, .month:
            return aggregateStressPoints(derivedDailyStress, bucket: .day, range: periodRange)
        case .year:
            return aggregateStressPoints(derivedDailyStress, bucket: .month, range: periodRange)
        }
    }

    private var activeHrvPoints: [TimeSeriesPointDouble] {
        selectedPeriod == .day ? todayHrvSamples : filteredHrvAverages
    }

    private var activeHeartRatePoints: [TimeSeriesPointDouble] {
        if selectedPeriod == .day {
            return todayHeartRateSamples.map {
                TimeSeriesPointDouble(timestamp: $0.timestamp, value: Double($0.value))
            }
        }
        return filteredRestingHeartRateAverages
    }

    private var rangeAverageHrv: Double? {
        averagePositive(filteredHrvAverages.map(\.value))
    }

    private var selectedDateTitle: String {
        switch selectedPeriod {
        case .day:
            return Calendar.current.isDateInToday(referenceDate) ? "今天" : dayHeaderFormatter.string(from: referenceDate)
        case .week, .month, .year:
            return "\(ChineseDateText.compactMonthDay(periodRange.lowerBound)) - \(ChineseDateText.compactMonthDay(periodRange.upperBound))"
        }
    }

    var body: some View {
        ZStack {
            pressureDetailBackground

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if isModalPresentation {
                            referenceCompactHeroCard
                            referenceHeroSection
                            referenceSummarySection
                            referenceAdviceSection
                        } else {
                            heroCard
                            signalSection
                            trendSection
                            bodySignalChartsSection
                        }

                        if !isModalPresentation {
                            moduleActions
                        }
                        pressureDisclaimerCard
                    }
                    .padding(.horizontal, Theme.Layout.padding)
                    .padding(.top, isModalPresentation ? 0 : 10)
                    .padding(.bottom, 88)
                }
            }
        }
        .navigationTitle(isModalPresentation ? "" : "压力详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isModalPresentation ? .hidden : .visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await loadStressDetails()
        }
        .onChange(of: selectedPeriod) { _, _ in
            Task { await loadStressDetails() }
        }
        .onChange(of: referenceDate) { _, _ in
            Task { await loadStressDetails() }
        }
    }

    private var pressureDetailBackground: some View {
        HealthDetailPageBackground(
            topGlow: Color(hex: "DCE9E3"),
            lowerGlow: Color(hex: "F6F8F7")
        )
    }

    private var moduleActions: some View {
        VStack(spacing: 10) {
            NavigationLink("查看压力事件") {
                StressEventTimelineView()
            }
            .buttonStyle(BBSecondaryButtonStyle(isFullWidth: true))

            NavigationLink("开始 3 分钟呼吸放松") {
                BalancedBreathingView()
            }
            .buttonStyle(BBPrimaryButtonStyle(isFullWidth: true))
        }
    }

    private var pressureDisclaimerCard: some View {
        HealthDisclaimerCard(
            message: "综合压力详情基于 HRV、心率、静息心率等已授权健康数据进行估算，仅供日常自我管理参考，不构成医疗诊断或治疗建议。若身体不适或需要做出重要健康决定，请咨询专业医生。"
        )
    }

    private var modalHeader: some View {
        ZStack {
            Text("综合压力")
                .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.appSystem(size: 16, weight: .bold))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Spacer()

                ShareLink(item: pressureShareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.appSystem(size: 16, weight: .bold))
                        .foregroundColor(style.accentColor)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Layout.padding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [style.accentColor.opacity(0.08), Color.white.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var referenceHeroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModernReportSegmentedPicker(
                selection: $selectedPeriod,
                options: PressureDetailPeriod.allCases.map {
                    ModernReportPickerOption(value: $0, title: $0.title)
                }
            )

            modalDateRow

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("压力分布")
                    .font(.appSystem(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Image(systemName: "info.circle")
                    .font(.appSystem(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Colors.textTertiary)

                Spacer()

                Text(chartSampleBadgeText)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(referenceAccent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(referenceAccent.opacity(0.10), in: Capsule())
            }

            referenceTrendChart
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(referenceAccent.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: referenceAccent.opacity(0.07), radius: 14, x: 0, y: 7)
    }

    private var referenceAccent: Color { Color(hex: "628B78") }

    private var referenceCompactHeroCard: some View {
        ModernSignalSheetHero(
            eyebrow: "身体信号",
            title: "综合压力",
            value: localAssessment.valueText,
            unit: "/ 100",
            state: localAssessment.title,
            description: localAssessment.adviceDetail,
            progress: Double(max(0, min(100, localAssessment.score ?? activeAverageStress))) / 100,
            tint: referenceAccent,
            symbol: "waveform.path.ecg",
            pills: [
                ModernSignalHeroPill(symbol: "waveform.path.ecg", text: "HRV \(hrvText)"),
                ModernSignalHeroPill(symbol: "heart.fill", text: "心率 \(bpmText)"),
                ModernSignalHeroPill(symbol: "bed.double.fill", text: "静息 \(restingText)")
            ],
            onClose: { dismiss() }
        )
    }

    private var referenceSummarySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("摘要")
                    .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                Spacer()
                Text("关键状态")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            HStack(spacing: 8) {
                referenceSummaryItem(value: "HRV \(hrvText)", detail: hrvHintText)
                referenceSummaryItem(value: "心率 \(bpmText)", detail: bpmHintText)
                referenceSummaryItem(value: localAssessment.title, detail: chartSampleBadgeText)
            }
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(referenceAccent.opacity(0.10), lineWidth: 1))
    }

    private func referenceSummaryItem(value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.appSystem(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(2)
            Text(detail)
                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .padding(10)
        .background(referenceAccent.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var referenceAdviceSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.appSystem(size: 16, weight: .black))
                .foregroundColor(referenceAccent)
                .frame(width: 38, height: 38)
                .background(referenceAccent.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(localAssessment.adviceTitle)
                    .font(.appSystem(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(localAssessment.adviceDetail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(referenceAccent.opacity(0.075), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var modalDateRow: some View {
        HStack {
            Button {
                shiftReferenceDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.appSystem(size: 17, weight: .bold))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 7) {
                Text(currentRangeBadgeText)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(style.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(style.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(selectedDateTitle)
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            Spacer()

            Button {
                shiftReferenceDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 17, weight: .bold))
                    .foregroundColor(canMoveForward ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveForward)
        }
        .padding(.horizontal, 6)
    }

    private var currentRangeBadgeText: String {
        guard periodRange.contains(Date()) else { return "所选时段" }
        return selectedPeriod.shortTitle
    }

    private var pressureShareText: String {
        guard !activeStressPoints.isEmpty else {
            return String(localized: "\(selectedDateTitle)暂无足够的综合压力样本。")
        }
        return String(localized: "\(selectedDateTitle)综合压力均值 \(activeAverageStress)，\(activeAssessment.title)。\(activeAssessment.adviceTitle)")
    }

    private var referenceTrendChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                StressTimelineStyledChart(
                    points: referenceDisplayPoints,
                    domain: chartDomain,
                    axisDates: stressAxisDates,
                    axisLabel: stressAxisLabel(for:),
                    accent: style.accentColor,
                    emptyText: "",
                    sleepIntervals: selectedPeriod == .day ? sleepIntervals : [],
                    height: 218,
                    metricName: "综合压力",
                    presentation: .showcase,
                    bucketDuration: chartBucketDuration,
                    estimatedTimestamps: chartEstimatedTimestamps,
                    selectedTimestamp: $selectedReferenceStressTimestamp
                )
                .opacity(activeStressPoints.isEmpty ? 0 : 1)

                if isLoading && activeStressPoints.isEmpty {
                    ModernReportChartLoadingState(
                        title: "正在读取健康数据",
                        tint: referenceAccent
                    )
                } else if activeStressPoints.isEmpty {
                    ModernReportChartEmptyState(
                        symbol: "waveform.path.ecg",
                        title: "等待压力趋势",
                        message: "持续佩戴并同步 HRV、心率和静息心率后，这里会显示当天的压力变化。",
                        tint: referenceAccent
                    )
                }
            }

            HStack(spacing: 14) {
                modalLegendItem(color: Color(hex: "34C759"), label: "放松平稳")
                modalLegendItem(color: Color(hex: "FF9F0A"), label: "轻度压力")
                modalLegendItem(color: Color(hex: "D70015"), label: "注意压力")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var referenceCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("趋势解读")
                .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: activeAssessment.band == .high ? "exclamationmark.heart.fill" : "sparkles")
                        .font(.appSystem(size: 18, weight: .bold))
                        .foregroundColor(style.accentColor)
                        .frame(width: 40, height: 40)
                        .background(style.accentColor.opacity(0.11), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeAssessment.adviceTitle)
                            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(modalAssessmentSubtitle)
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                Text(activeAssessment.adviceDetail)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                        showingDeepAnalysis.toggle()
                    }
                } label: {
                    Label(showingDeepAnalysis ? "收起详细分析" : "查看详细分析", systemImage: showingDeepAnalysis ? "chevron.up" : "chart.xyaxis.line")
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "176B52"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(hex: "E2F6EE"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: "DDEDE6"), lineWidth: 1)
            )
        }
    }

    private var canMoveForward: Bool {
        switch selectedPeriod {
        case .day:
            return !Calendar.current.isDate(referenceDate, inSameDayAs: Date())
        case .week:
            return !Calendar.current.isDate(periodRange.lowerBound, equalTo: Date(), toGranularity: .weekOfYear)
        case .month:
            return !Calendar.current.isDate(periodRange.lowerBound, equalTo: Date(), toGranularity: .month)
        case .year:
            return !Calendar.current.isDate(periodRange.lowerBound, equalTo: Date(), toGranularity: .year)
        }
    }

    private func shiftReferenceDate(by value: Int) {
        let calendar = Calendar.current
        let component: Calendar.Component
        switch selectedPeriod {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }

        guard let shifted = calendar.date(byAdding: component, value: value, to: referenceDate) else { return }
        if value > 0 && shifted > Date() {
            referenceDate = Date()
        } else {
            referenceDate = shifted
        }
    }

    private func aggregateStressPoints(
        _ source: [TimeSeriesPoint],
        bucket: PressureAggregationBucket,
        range: ClosedRange<Date>
    ) -> [TimeSeriesPoint] {
        let calendar = Calendar.current
        let filtered = source.filter { range.contains($0.date) }
        guard !filtered.isEmpty else { return [] }

        let grouped = Dictionary(grouping: filtered) { point in
            switch bucket {
            case .day:
                return calendar.startOfDay(for: point.date)
            case .month:
                let components = calendar.dateComponents([.year, .month], from: point.date)
                return calendar.date(from: components) ?? calendar.startOfDay(for: point.date)
            }
        }

        return grouped.keys.sorted().compactMap { date in
            guard let items = grouped[date], !items.isEmpty else { return nil }
            let average = Int((Double(items.map(\.value).reduce(0, +)) / Double(items.count)).rounded())
            return TimeSeriesPoint(timestamp: Int64(date.timeIntervalSince1970), value: average)
        }
    }

    private func mergeStressPoints(primary: [TimeSeriesPoint], fallback: [TimeSeriesPoint]) -> [TimeSeriesPoint] {
        guard !fallback.isEmpty else { return primary }
        guard !primary.isEmpty else { return fallback }

        var merged = Dictionary(uniqueKeysWithValues: fallback.map { ($0.timestamp, $0) })
        for point in primary where point.value > 0 {
            merged[point.timestamp] = point
        }
        return merged.values.sorted { $0.date < $1.date }
    }

    private var heroCard: some View {
        VStack(spacing: 14) {
            ModernReportHero(
                eyebrow: String(localized: "压力与恢复"),
                title: String(localized: "综合压力"),
                value: localAssessment.valueText,
                unit: "/100",
                ghostUnit: "SCORE",
                captions: [
                    ModernReportCaption(symbol: "calendar", text: selectedDateTitle),
                    ModernReportCaption(symbol: "heart.text.square.fill", text: String(localized: "健康 App")),
                    ModernReportCaption(symbol: "info.circle.fill", text: localAssessment.adviceTitle)
                ],
                badge: ModernReportBadge(
                    symbol: style.metricSymbol,
                    text: localAssessment.title,
                    tint: style.accentColor
                ),
                accent: style.accentColor,
                symbol: "leaf.fill"
            )

            ModernReportSegmentedPicker(
                selection: $selectedPeriod,
                options: PressureDetailPeriod.allCases.map {
                    ModernReportPickerOption(value: $0, title: $0.title)
                }
            )

            ModernReportMetricsPanel(
                title: String(localized: "关键指标"),
                metrics: [
                    ModernReportMetric(
                        title: String(localized: "压力指数"),
                        value: localAssessment.valueText,
                        tint: style.accentColor,
                        symbol: "leaf.fill"
                    ),
                    ModernReportMetric(
                        title: String(localized: "恢复状态"),
                        value: localAssessment.title,
                        tint: Color(hex: "F0A32E"),
                        symbol: "bolt.fill"
                    ),
                    ModernReportMetric(
                        title: String(localized: "当前心率"),
                        value: bpmText,
                        tint: Color(hex: "FF7A59"),
                        symbol: "heart.fill"
                    ),
                    ModernReportMetric(
                        title: String(localized: "当前 HRV"),
                        value: hrvText,
                        tint: Theme.Colors.mintGreen,
                        symbol: "waveform.path.ecg"
                    )
                ]
            )

            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(verbatim: localAssessment.adviceDetail)
                } icon: {
                    Image(systemName: "lightbulb.fill")
                }
                .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .modernReportPanelSurface()
        }
    }

    private var signalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("压力信号概览")
                .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                detailCard(title: "当前心率", value: bpmText, subtitle: bpmHintText, tint: Color(hex: "FF7A59"), symbol: "heart.fill")
                detailCard(title: "当前 HRV", value: hrvText, subtitle: hrvHintText, tint: Theme.Colors.mintGreen, symbol: "waveform.path.ecg")
                detailCard(title: "静息心率", value: restingText, subtitle: restingHintText, tint: Color(hex: "5E8CFF"), symbol: "bed.double.fill")
                detailCard(title: "近期基线", value: baselineText, subtitle: baselineHintText, tint: Color(hex: "FFB340"), symbol: "chart.line.uptrend.xyaxis")
            }
        }
    }

    private func summaryMetricBlock(
        title: String,
        value: String,
        subtitle: String,
        symbol: String? = nil,
        tint: Color = Theme.Colors.textSecondary
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.appSystem(size: 12, weight: .bold))
                        .foregroundColor(tint)
                        .frame(width: 24, height: 24)
                        .background(tint.opacity(0.12), in: Circle())
                }

                Text(title)
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Text(value)
                .font(.appSystem(size: 32, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            Text(subtitle)
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modalLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private func dayStressCell(_ item: PressureDailySummary) -> some View {
        VStack(spacing: 10) {
            Text(weekdayFormatter.string(from: item.date))
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(item.isToday ? style.accentColor : Theme.Colors.textTertiary)

            Text(dayFormatter.string(from: item.date))
                .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            Text(item.averageValue.map { "\($0)" } ?? "--")
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(item.averageValue.map(segmentColor(for:)) ?? Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(item.isToday ? style.accentColor.opacity(0.20) : Theme.Colors.surfaceBorder, lineWidth: 1)
        )
        .shadow(color: style.accentColor.opacity(item.isToday ? 0.08 : 0.04), radius: 8, x: 0, y: 4)
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                eyebrow: "今日趋势",
                title: "综合压力趋势",
                subtitle: "优先用 HealthKit 的 HRV 样本估算综合压力；没有样本时，再回退到今天已有的压力历史。"
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 6) {
                        Text("实时压力")
                        Image(systemName: "info.circle")
                            .font(.appSystem(size: 13, weight: .semibold))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    Text(chartSampleBadgeText)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(style.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .bbTintedChip(tint: style.accentColor, in: Capsule(), tintOpacity: 0.12)
                }

                HStack(spacing: 10) {
                    trendMetricChip(title: "当前", value: "\(latestStress)")
                    trendMetricChip(title: "均值", value: "\(averageStress)")
                    trendMetricChip(title: "峰值", value: "\(peakStress)")
                }

                ZStack {
                    StressTimelineStyledChart(
                        points: referenceDisplayPoints,
                        domain: chartDomain,
                        axisDates: stressAxisDates,
                        axisLabel: stressAxisLabel(for:),
                        accent: style.accentColor,
                        emptyText: "",
                        sleepIntervals: selectedPeriod == .day ? sleepIntervals : [],
                        height: 216,
                        metricName: "综合压力",
                        presentation: .showcase,
                        bucketDuration: chartBucketDuration,
                        estimatedTimestamps: chartEstimatedTimestamps,
                        selectedTimestamp: $selectedReferenceStressTimestamp
                    )

                    if isLoading && activeStressPoints.isEmpty {
                        ProgressView("正在读取健康数据")
                            .padding(14)
                            .background(Theme.Colors.surface.opacity(0.90), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                HStack(spacing: 14) {
                    modalLegendItem(color: Color(hex: "34C759"), label: "放松平稳")
                    modalLegendItem(color: Color(hex: "FF9F0A"), label: "轻度压力")
                    modalLegendItem(color: Color(hex: "D70015"), label: "注意压力")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .pressureDetailCard(tint: style.accentColor, cornerRadius: Theme.Layout.cornerRadius, padding: 16)
        }
    }

    private var bodySignalChartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                eyebrow: "身体信号",
                title: "HRV 与心率的今日变化",
                subtitle: "把今天的 HRV 与心率序列放到同一页，方便对照近期基线判断综合压力来源。"
            )

            VStack(alignment: .leading, spacing: 22) {
                hrvTrendChart
                heartRateTrendChart
                monthlyHrvBaselineChart
                restingHeartRateBaselineChart
            }
            .pressureDetailCard(tint: style.accentColor, cornerRadius: Theme.Layout.cornerRadius, padding: 16)
        }
    }

    private var hrvTrendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hrvTrendTitle)
                .font(.appSystem(size: 21, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            if activeHrvPoints.isEmpty {
                chartEmptyCard(text: hrvEmptyText)
            } else {
                Chart {
                    if let baseline = averagePositive(monthlyHrvAverages.map(\.value)) {
                        RuleMark(y: .value("近30日平均HRV", baseline))
                            .foregroundStyle(Color(hex: "A8B1E8"))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    }

                    ForEach(activeHrvPoints) { item in
                        LineMark(
                            x: .value("时间", item.date),
                            y: .value("HRV", item.value)
                        )
                        .foregroundStyle(Color.black.opacity(0.14))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("时间", item.date),
                            y: .value("HRV", item.value)
                        )
                        .foregroundStyle(hrvPointColor(for: item.value))
                        .symbolSize(88)
                    }
                }
                .frame(height: 212)
                .chartXScale(domain: selectedPeriod == .day ? chartDomain : hrvRangeDomain)
                .chartXAxis {
                    AxisMarks(values: selectedPeriod == .day ? axisDates : hrvRangeAxisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.10))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(selectedPeriod == .day ? axisTimeLabel(for: date) : referenceAxisLabel(for: date))
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.10))
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text("\(Int(doubleValue.rounded()))")
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }

                HStack(spacing: 18) {
                    chartLegendItem(color: Color(hex: "C7CEF2"), label: selectedPeriod == .day ? "今日 HRV" : "\(selectedPeriod.shortTitle) HRV")
                    chartLegendItem(color: Color(hex: "A8B1E8"), label: "近30日平均HRV")
                }
            }
        }
    }

    private var heartRateTrendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(restingTrendTitle)
                .font(.appSystem(size: 21, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            if activeHeartRatePoints.isEmpty {
                chartEmptyCard(text: restingEmptyText)
            } else {
                Chart {
                    if let baseline = averagePositive(restingHeartRateAverages.map(\.value)) {
                        RuleMark(y: .value("近60日平均静息心率", baseline))
                            .foregroundStyle(Color(hex: "FF9DB1"))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    }

                    ForEach(activeHeartRatePoints) { item in
                        AreaMark(
                            x: .value("时间", item.date),
                            yStart: .value("最低", Double(heartRateChartDomain.lowerBound)),
                            yEnd: .value("心率", Double(item.value))
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "FF7C93").opacity(0.28), Color(hex: "FF7C93").opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("时间", item.date),
                            y: .value("心率", item.value)
                        )
                        .foregroundStyle(Color(hex: "F45C78"))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(height: 228)
                .chartPlotStyle { plotArea in
                    plotArea.clipped()
                }
                .chartXScale(domain: selectedPeriod == .day ? chartDomain : restingRangeDomain)
                .chartYScale(domain: heartRateChartDomain)
                .chartXAxis {
                    AxisMarks(values: selectedPeriod == .day ? axisDates : restingRangeAxisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.10))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(selectedPeriod == .day ? axisTimeLabel(for: date) : referenceAxisLabel(for: date))
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [heartRateChartDomain.lowerBound, heartRateChartDomain.upperBound]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.10))
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue)")
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }

                HStack(spacing: 18) {
                    chartLegendItem(color: Color(hex: "FFB6C4"), label: selectedPeriod == .day ? "今日心率" : "\(selectedPeriod.shortTitle)静息心率")
                    chartLegendItem(color: Color(hex: "FF9DB1"), label: "近60日平均静息心率")
                }
            }
        }
    }

    private var monthlyHrvBaselineChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近30日 HRV 基线")
                .font(.appSystem(size: 21, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            if monthlyHrvAverages.isEmpty {
                chartEmptyCard(text: "最近还没有足够的 HRV 日均值。")
            } else {
                Chart(monthlyHrvAverages) { item in
                    AreaMark(
                        x: .value("日期", item.date),
                        y: .value("HRV", item.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "8078FF").opacity(0.20), Color(hex: "8078FF").opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("日期", item.date),
                        y: .value("HRV", item.value)
                    )
                    .foregroundStyle(Color(hex: "6C63FF"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("日期", item.date),
                        y: .value("HRV", item.value)
                    )
                    .foregroundStyle(Color(hex: "6C63FF"))
                    .symbolSize(48)
                }
                .frame(height: 212)
                .chartPlotStyle { plotArea in
                    plotArea.clipped()
                }
                .chartXScale(domain: recentHrvDomain)
                .chartXAxis {
                    AxisMarks(values: recentHrvAxisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.10))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(shortDateFormatter.string(from: date))
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.10))
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text("\(Int(doubleValue.rounded()))")
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var restingHeartRateBaselineChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近60日 静息心率基线")
                .font(.appSystem(size: 21, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            if restingHeartRateAverages.isEmpty {
                chartEmptyCard(text: "最近还没有足够的静息心率日均值。")
            } else {
                Chart(restingHeartRateAverages) { item in
                    LineMark(
                        x: .value("日期", item.date),
                        y: .value("静息心率", item.value)
                    )
                    .foregroundStyle(Color(hex: "FF7A59"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("日期", item.date),
                        y: .value("静息心率", item.value)
                    )
                    .foregroundStyle(Color(hex: "FF7A59"))
                    .symbolSize(42)
                }
                .frame(height: 212)
                .chartXScale(domain: recentRestingDomain)
                .chartXAxis {
                    AxisMarks(values: recentRestingAxisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.10))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(shortDateFormatter.string(from: date))
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.10))
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text("\(Int(doubleValue.rounded()))")
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadStressDetails() async {
        let requestedDate = Calendar.current.startOfDay(for: referenceDate)
        let requestedPeriod = selectedPeriod
        let isViewingToday = Calendar.current.isDateInToday(requestedDate)
        // 370 天区间聚合仅用于周/月/年视图；日视图打开时跳过，避免拖慢首屏。
        let needsRangeAggregates = requestedPeriod != .day
        let requestedRange = requestedPeriod.rollingRange
        let requestedInterval = requestedRange.interval(anchorDate: requestedDate)
        let requestedDayEnd = requestedRange.queryEnd(anchorDate: requestedDate)
        Self.logger.info(
            "[PressureDetail] operation=dataLoadStart technicalID=stress.assessment period=\(periodLogLabel, privacy: .public) expectedDays=\(requestedRange.dayCount, privacy: .public)"
        )
        isLoading = true

        async let points = stressPointsForReferenceDate(requestedDate)
        async let latestHeartRate: Double? = isViewingToday ? (try? HealthKitManager.shared.fetchLatestHeartRate()) : nil
        async let latestHrv: Double? = isViewingToday ? (try? HealthKitManager.shared.fetchLatestHRV()) : nil
        async let averageHrvToday = try? HealthKitManager.shared.fetchAverageHRV(on: requestedDate)
        async let hrvSamples = try? HealthKitManager.shared.fetchHRVSamples(on: requestedDate)
        async let heartRateSeries = try? HealthKitManager.shared.fetchHeartRateSeries(
            start: requestedDate,
            end: requestedDayEnd,
            maxPoints: 180
        )
        // 与 TodayChartsCard 保持一致：展示请求日期内所有重叠的睡眠时段，
        // 包括主睡眠、再次入睡和午睡；不使用只保留最长主睡眠的夜间摘要。
        async let requestedSleepSessions = try? HealthKitManager.shared.fetchSleepIntervals(on: requestedDate)
        async let resting = try? HealthKitManager.shared.fetchRestingHeartRate(on: requestedDate)
        async let recentHrvPoints = try? HealthKitManager.shared.fetchDailyHRVAverages(days: 30, endDate: requestedDayEnd)
        async let recentRestingPoints = try? HealthKitManager.shared.fetchDailyRestingHeartRateAverages(days: 60, endDate: requestedDayEnd)
        async let rangeHrvPoints: [TimeSeriesPointDouble]? = needsRangeAggregates ? (try? HealthKitManager.shared.fetchDailyHRVAverages(days: requestedRange.dayCount, endDate: requestedDayEnd)) : nil
        async let rangeHeartRatePoints: [TimeSeriesPointDouble]? = needsRangeAggregates ? (try? HealthKitManager.shared.fetchDailyHeartRateAverages(days: requestedRange.dayCount, endDate: requestedDayEnd)) : nil
        async let rangeRestingPoints: [TimeSeriesPointDouble]? = needsRangeAggregates ? (try? HealthKitManager.shared.fetchDailyRestingHeartRateAverages(days: requestedRange.dayCount, endDate: requestedDayEnd)) : nil

        let localPoints = await points
        let realBpm = await latestHeartRate
        let realHrv = await latestHrv
        let avgToday = await averageHrvToday
        let todayHrv = await hrvSamples ?? []
        let todayHeartRate = await heartRateSeries ?? []
        let requestedSleepIntervals = (await requestedSleepSessions ?? [])
            .map { DateInterval(start: $0.start, end: $0.end) }
        let restingValue = await resting
        let recentHrvSeries = await recentHrvPoints ?? []
        let recentRestingSeries = await recentRestingPoints ?? []
        let stressRangeHrvSeries = await rangeHrvPoints ?? []
        let stressRangeHeartRateSeries = await rangeHeartRatePoints ?? []
        let stressRangeRestingSeries = await rangeRestingPoints ?? []

        guard selectedPeriod == requestedPeriod,
              Calendar.current.isDate(referenceDate, inSameDayAs: requestedDate) else { return }

        let resolvedHrvBaseline = HealthBaselineStrategy.usableValue(
            for: recentHrvSeries.map(\.value),
            metric: .hrvSDNN
        )
        let resolvedHistoricalRestingHeartRateBaseline = HealthBaselineStrategy.usableValue(
            for: recentRestingSeries.map(\.value),
            metric: .restingHeartRate
        )
        let effectiveRestingHeartRateBaseline = StressDailyEngine.resolvedRestingHeartRateBaseline(
            measured: restingValue,
            historical: resolvedHistoricalRestingHeartRateBaseline,
            heartRate: todayHeartRate
        )
        let reconstructedPoints = StressDailyEngine.sevenMinuteStressPoints(
            hrv: todayHrv,
            heartRate: todayHeartRate,
            restingHeartRate: restingValue,
            restingHeartRateBaseline: resolvedHistoricalRestingHeartRateBaseline,
            hrvBaseline: resolvedHrvBaseline,
            in: DateInterval(start: requestedInterval.start, end: requestedDayEnd)
        )
        if isViewingToday && !preferredSevenMinuteStressPoints.isEmpty {
            // 今日页卡片已经确定首选的七分钟数据源，此处直接复用，
            // 避免次级图表混入额外重建点后与主图产生偏差。
            healthKitPoints = localPoints
        } else {
            healthKitPoints = mergeStressPoints(
                primary: localPoints,
                fallback: reconstructedPoints
            )
        }
        todayHrvSamples = todayHrv
        todayHeartRateSamples = todayHeartRate
        sleepIntervals = requestedSleepIntervals
        monthlyHrvAverages = requestedPeriod == .day ? recentHrvSeries : stressRangeHrvSeries
        restingHeartRateAverages = requestedPeriod == .day ? recentRestingSeries : stressRangeRestingSeries
        rangeHrvAverages = stressRangeHrvSeries
        rangeHeartRateAverages = stressRangeHeartRateSeries
        rangeRestingHeartRateAverages = stressRangeRestingSeries
        currentBpm = realBpm.flatMap { $0 > 0 ? $0 : nil }
        currentHrv = realHrv.flatMap { $0 > 0 ? $0 : nil }
        avgHrvToday = avgToday.flatMap { $0 > 0 ? $0 : nil }
        restingHeartRate = restingValue.flatMap { $0 > 0 ? $0 : nil }
        recentAvgHrv = resolvedHrvBaseline
        recentAvgRestingHeartRate = resolvedHistoricalRestingHeartRateBaseline
        stressEstimationRestingHeartRateBaseline = effectiveRestingHeartRateBaseline

        let resolvedPoints = activeStressPoints
        let historyAverageStress = resolvedPoints.isEmpty ? nil : Double(resolvedPoints.map(\.value).reduce(0, +)) / Double(resolvedPoints.count)
        let resolved: StressPresentationAssessment
        if selectedPeriod == .day,
           let current = StressPresentation.assessment(from: isViewingToday ? preferredRealtimeHealth : nil, now: requestedDate) {
            resolved = current
        } else if let historyAverageStress {
            resolved = StressPresentation.assessmentFromScore(
                Int(historyAverageStress.rounded()),
                now: requestedDate,
                updatedAtSeconds: resolvedPoints.last?.timestamp
            )
        } else {
            resolved = StressPresentation.unavailableAssessment(reason: .noDailySamples)
        }
        localAssessment = resolved
        isLoading = false
        let renderStatus = resolved.hasData ? "available" : "unavailable"
        Self.logger.info(
            "[PressureDetail] operation=render technicalID=stress.assessment period=\(periodLogLabel, privacy: .public) status=\(renderStatus, privacy: .public) stressPointCount=\(resolvedPoints.count, privacy: .public) hrvDayCount=\(stressRangeHrvSeries.count, privacy: .public) heartRateDayCount=\(stressRangeHeartRateSeries.count, privacy: .public) restingDayCount=\(stressRangeRestingSeries.count, privacy: .public) algorithm=\(StressResult.currentAlgorithmVersion, privacy: .public)"
        )
        printPressureDebugData(
            referenceDate: requestedDate,
            queryInterval: requestedInterval,
            queryEnd: requestedDayEnd,
            assessment: resolved,
            stressPoints: resolvedPoints,
            hrvSamples: todayHrv,
            heartRateSamples: todayHeartRate,
            rangeHrvAverages: stressRangeHrvSeries,
            rangeHeartRateAverages: stressRangeHeartRateSeries,
            rangeRestingHeartRateAverages: stressRangeRestingSeries,
            sleepIntervals: requestedSleepIntervals,
            currentHeartRate: realBpm,
            currentHrv: realHrv,
            averageHrv: avgToday,
            restingHeartRate: restingValue,
            hrvBaseline: resolvedHrvBaseline,
            restingHeartRateBaseline: resolvedHistoricalRestingHeartRateBaseline,
            effectiveRestingHeartRateBaseline: effectiveRestingHeartRateBaseline
        )
    }

    private func printPressureDebugData(
        referenceDate: Date,
        queryInterval: DateInterval,
        queryEnd: Date,
        assessment: StressPresentationAssessment,
        stressPoints: [TimeSeriesPoint],
        hrvSamples: [TimeSeriesPointDouble],
        heartRateSamples: [TimeSeriesPoint],
        rangeHrvAverages: [TimeSeriesPointDouble],
        rangeHeartRateAverages: [TimeSeriesPointDouble],
        rangeRestingHeartRateAverages: [TimeSeriesPointDouble],
        sleepIntervals: [DateInterval],
        currentHeartRate: Double?,
        currentHrv: Double?,
        averageHrv: Double?,
        restingHeartRate: Double?,
        hrvBaseline: Double?,
        restingHeartRateBaseline: Double?,
        effectiveRestingHeartRateBaseline: Double?
    ) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        func dateText(_ date: Date) -> String {
            formatter.string(from: date)
        }
        func doubleText(_ value: Double?) -> String {
            value.map { String(format: "%.2f", $0) } ?? "nil"
        }

        var lines: [String] = []
        lines.append("=== [PressureDebug] 综合压力页面数据 ===")
        lines.append("metric=stress period=\(periodLogLabel) referenceDate=\(dateText(referenceDate))")
        lines.append("queryWindow=\(dateText(queryInterval.start)) ~ \(dateText(queryInterval.end)) queryEnd=\(dateText(queryEnd)) expectedDays=\(selectedPeriod.rollingRange.dayCount)")
        lines.append("assessment=\(String(reflecting: assessment))")
        lines.append("currentHeartRate=\(doubleText(currentHeartRate)) currentHrv=\(doubleText(currentHrv)) averageHrv=\(doubleText(averageHrv)) restingHeartRate=\(doubleText(restingHeartRate))")
        lines.append("hrvBaseline=\(doubleText(hrvBaseline)) restingHeartRateBaseline=\(doubleText(restingHeartRateBaseline)) effectiveRestingHeartRateBaseline=\(doubleText(effectiveRestingHeartRateBaseline))")
        if selectedPeriod == .day {
            lines.append("intraday.hrvSamples: \(hrvSamples.count) 条")
            for (index, point) in hrvSamples.enumerated() {
                lines.append("  [\(index)] \(dateText(point.date)) HRV=\(String(format: "%.2f", point.value)) ms")
            }
            lines.append("intraday.heartRateSamples: \(heartRateSamples.count) 条")
            for (index, point) in heartRateSamples.enumerated() {
                lines.append("  [\(index)] \(dateText(point.date)) heartRate=\(point.value) bpm")
            }
        } else {
            lines.append("rollingRange.hrvDailyAverages: \(rangeHrvAverages.count) 条")
            for (index, point) in rangeHrvAverages.enumerated() {
                lines.append("  [\(index)] \(dateText(point.date)) HRV=\(String(format: "%.2f", point.value)) ms")
            }
            lines.append("rollingRange.heartRateDailyAverages: \(rangeHeartRateAverages.count) 条")
            for (index, point) in rangeHeartRateAverages.enumerated() {
                lines.append("  [\(index)] \(dateText(point.date)) heartRate=\(String(format: "%.2f", point.value)) bpm")
            }
            lines.append("rollingRange.restingHeartRateDailyAverages: \(rangeRestingHeartRateAverages.count) 条")
            for (index, point) in rangeRestingHeartRateAverages.enumerated() {
                lines.append("  [\(index)] \(dateText(point.date)) restingHeartRate=\(String(format: "%.2f", point.value)) bpm")
            }
        }
        lines.append("sleepIntervals: \(sleepIntervals.count) 条")
        for (index, interval) in sleepIntervals.enumerated() {
            lines.append("  [\(index)] \(dateText(interval.start)) ~ \(dateText(interval.end)) duration=\(Int(interval.duration / 60)) min")
        }
        lines.append("chart.stressPoints: \(stressPoints.count) 条")
        for (index, point) in stressPoints.enumerated() {
            lines.append("  [\(index)] \(dateText(point.date)) stress=\(point.value)")
        }
        print(lines.joined(separator: "\n"))
    }

    private func stressPointsForReferenceDate(_ date: Date) async -> [TimeSeriesPoint] {
        guard Calendar.current.isDateInToday(date) else { return [] }
        let calendar = Calendar.current
        let preferredPoints = preferredSevenMinuteStressPoints.filter {
            $0.value > 0 && calendar.isDate($0.date, inSameDayAs: date)
        }
        var points = preferredPoints.isEmpty
            ? (history?.stressPoints ?? []).filter {
                $0.value > 0 && calendar.isDate($0.date, inSameDayAs: date)
            }
            : preferredPoints
        if let realtime = preferredRealtimeHealth,
           realtime.stress_value > 0,
           calendar.isDate(
               Date(timeIntervalSince1970: TimeInterval(realtime.timestamp)),
               inSameDayAs: date
           ) {
            points.append(TimeSeriesPoint(timestamp: realtime.timestamp, value: realtime.stress_value))
        }
        return Dictionary(grouping: points, by: { $0.timestamp / 300 })
            .compactMap { _, bucket in bucket.max { $0.timestamp < $1.timestamp } }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var periodLogLabel: String {
        switch selectedPeriod {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        }
    }

    private func heroMetric(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 12, weight: .bold))
                Text(title)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(Theme.Colors.textSecondary)

            Text(value)
                .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private func statusPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(value)
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private func sectionHeader(eyebrow: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.mintGreen)
                .tracking(1.2)
            Text(title)
                .font(.appSystem(size: 21, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var heroArtwork: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 108, height: 108)
                .bbTintedSurface(tint: Color.white, in: Circle(), tintStrength: 0.04)
            Circle()
                .fill(Color(hex: "F7F8F4"))
                .frame(width: 94, height: 94)
            Image(style.heroImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 98, height: 98)
                .scaleEffect(animateHero ? 1.03 : 0.98)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: animateHero)

            VStack {
                Spacer()
                Text(localAssessment.hasData ? "\(localAssessment.valueText) / 100" : "等待数据")
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(localAssessment.hasData ? Color(hex: "255CCB") : Theme.Colors.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .bbTintedChip(tint: Color.white, in: Capsule(), tintOpacity: 0.04)
                    .padding(.bottom, -2)
            }
        }
        .frame(width: 112, height: 112)
    }

    private func overviewMetricCard(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 12, weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: 28, height: 28)
                    .bbTintedChip(tint: tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous), tintOpacity: 0.14)

                Text(title)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Text(value)
                .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private func detailCard(title: String, value: String, subtitle: String, tint: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: 30, height: 30)
                    .bbTintedChip(tint: tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous), tintOpacity: 0.14)
                Spacer(minLength: 8)
                Text(title)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Text(value)
                .font(.appSystem(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.07), radius: 10, x: 0, y: 5)
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func trendMetricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private func chartEmptyCard(text: String) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white)
            .frame(height: 180)
            .overlay {
                Text(text)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
            )
    }

    private func chartLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 28, height: 3)
            Text(label)
                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private func segmentColor(for value: Int) -> Color {
        // 与 StressBand 色调体系对齐
        switch value {
        case ..<30:
            return Color(hex: "34C759")
        case 30..<50:
            return Color(hex: "007F79")
        case 50..<70:
            return Color(hex: "FF9F0A")
        case 70..<85:
            return Color(hex: "FF7A00")
        default:
            return Color(hex: "D70015")
        }
    }

    private func hrvPointColor(for value: Double) -> Color {
        if let baseline = averagePositive(monthlyHrvAverages.map(\.value)) {
            if value >= baseline + 6 { return Color(hex: "64C79A") }
            if value <= baseline - 6 { return Color(hex: "E55D78") }
        }
        return Color(hex: "8B9BDA")
    }

    private var recentHrvDomain: ClosedRange<Date> {
        let dates = monthlyHrvAverages.map(\.date).sorted()
        guard let first = dates.first, let last = dates.last else {
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -29, to: end) ?? end
            return start...end
        }
        return first...max(last, first.addingTimeInterval(24 * 60 * 60))
    }

    private var recentRestingDomain: ClosedRange<Date> {
        let dates = restingHeartRateAverages.map(\.date).sorted()
        guard let first = dates.first, let last = dates.last else {
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -59, to: end) ?? end
            return start...end
        }
        return first...max(last, first.addingTimeInterval(24 * 60 * 60))
    }

    private var recentHrvAxisDates: [Date] {
        axisDates(for: recentHrvDomain, count: 4)
    }

    private var recentRestingAxisDates: [Date] {
        axisDates(for: recentRestingDomain, count: 4)
    }

    private func domain(for dates: [Date], fallbackRange: ClosedRange<Date>) -> ClosedRange<Date> {
        let sorted = dates.sorted()
        guard let first = sorted.first, let last = sorted.last else {
            return fallbackRange
        }

        if first == last {
            switch selectedPeriod {
            case .day:
                return first...first.addingTimeInterval(24 * 60 * 60)
            case .week:
                return first...first.addingTimeInterval(7 * 24 * 60 * 60)
            case .month:
                return first...first.addingTimeInterval(30 * 24 * 60 * 60)
            case .year:
                return first...first.addingTimeInterval(31 * 24 * 60 * 60)
            }
        }

        return first...last
    }

    private var heartRateChartDomain: ClosedRange<Int> {
        let values = activeHeartRatePoints.map(\.value)
        guard !values.isEmpty else { return 40...120 }
        let minimum = max(40, Int((values.min() ?? 40).rounded()) - 8)
        let maximum = min(120, Int((values.max() ?? 120).rounded()) + 8)
        return minimum...max(maximum, minimum + 20)
    }

    private var hrvTrendTitle: String {
        if selectedPeriod == .day {
            return String(localized: "今日平均 HRV \(hrvText)")
        }
        let value = rangeAverageHrv.map { "\(Int($0.rounded())) ms" } ?? "--"
        return String(localized: "\(selectedPeriod.shortTitle)平均 HRV \(value)")
    }

    private var restingTrendTitle: String {
        if selectedPeriod == .day {
            return String(localized: "今日静息心率 \(restingText)")
        }
        let value = averagePositive(filteredRestingHeartRateAverages.map(\.value)).map { "\(Int($0.rounded())) 次/分" } ?? "--"
        return String(localized: "\(selectedPeriod.shortTitle)静息心率 \(value)")
    }

    private var hrvEmptyText: String {
        selectedPeriod == .day ? "今天还没有足够的 HRV 样本。" : "\(selectedPeriod.shortTitle)还没有足够的 HRV 日均值。"
    }

    private var restingEmptyText: String {
        selectedPeriod == .day ? "今天还没有足够的心率样本。" : "\(selectedPeriod.shortTitle)还没有足够的静息心率日均值。"
    }

    private var hrvRangeDomain: ClosedRange<Date> {
        domain(for: activeHrvPoints.map(\.date), fallbackRange: periodRange)
    }

    private var restingRangeDomain: ClosedRange<Date> {
        domain(for: activeHeartRatePoints.map(\.date), fallbackRange: periodRange)
    }

    private var hrvRangeAxisDates: [Date] {
        axisDates(for: hrvRangeDomain, count: selectedPeriod == .year ? 6 : 5)
    }

    private var restingRangeAxisDates: [Date] {
        axisDates(for: restingRangeDomain, count: selectedPeriod == .year ? 6 : 5)
    }

    private func averagePositive(_ values: [Double]) -> Double? {
        let valid = values.filter { $0 > 0 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    private var bpmText: String {
        currentBpm.map { "\(Int($0.rounded())) 次/分" } ?? "--"
    }

    private var hrvText: String {
        let value = avgHrvToday ?? currentHrv
        return value.map { "\(Int($0.rounded())) ms" } ?? "--"
    }

    private var restingText: String {
        restingHeartRate.map { "\(Int($0.rounded())) 次/分" } ?? "--"
    }

    private var baselineText: String {
        if let hrv = recentAvgHrv, let resting = recentAvgRestingHeartRate {
            return String(localized: "\(Int(hrv.rounded()))ms / \(Int(resting.rounded()))次")
        }
        if let hrv = recentAvgHrv {
            return "\(Int(hrv.rounded())) ms"
        }
        if let resting = recentAvgRestingHeartRate {
            return String(localized: "\(Int(resting.rounded())) 次/分")
        }
        return "--"
    }

    private var bpmHintText: String {
        guard let bpm = currentBpm else { return "当前没有可用心率样本。" }
        if let resting = restingHeartRate, bpm - resting >= 18 {
            return String(localized: "明显高于静息心率，身体负荷在抬升。")
        }
        return String(localized: "心率没有明显高出静息区间。")
    }

    private var hrvHintText: String {
        guard let current = avgHrvToday ?? currentHrv else { return "当前没有可用 HRV 样本。" }
        guard let baseline = recentAvgHrv, baseline > 0 else { return "已用当前 HRV 直接参与估算。" }
        let delta = current - baseline
        if delta < -8 {
            return String(localized: "低于近期均值，恢复状态偏弱。")
        }
        if delta > 8 {
            return String(localized: "高于近期均值，恢复状态较好。")
        }
        return String(localized: "与近期均值接近，恢复信号相对平稳。")
    }

    private var restingHintText: String {
        guard let current = restingHeartRate else { return "当前没有静息心率基线。" }
        guard let baseline = recentAvgRestingHeartRate, baseline > 0 else { return "已用当前静息心率参与估算。" }
        if current - baseline >= 4 {
            return String(localized: "高于近期均值，可能恢复不足。")
        }
        return String(localized: "与近期均值接近，没有明显抬升。")
    }

    private var baselineHintText: String {
        if recentAvgHrv != nil || recentAvgRestingHeartRate != nil {
            return String(localized: "用最近 14 天健康样本做参考基线。")
        }
        return String(localized: "基线不足时，会退回到当前样本和今日历史。")
    }

    private var stressTimestampText: String {
        guard let latest = activeStressPoints.last?.date else { return "刚刚" }
        switch selectedPeriod {
        case .day:
            return detailTimeFormatter.string(from: latest)
        case .week, .month:
            return shortDateFormatter.string(from: latest)
        case .year:
            return monthAxisFormatter.string(from: latest)
        }
    }

    private func referenceAxisLabel(for date: Date) -> String {
        switch selectedPeriod {
        case .day:
            return axisTimeLabel(for: date)
        case .week:
            return weekdayShortFormatter.string(from: date)
        case .month:
            return monthDayAxisFormatter.string(from: date)
        case .year:
            return monthAxisFormatter.string(from: date)
        }
    }

    private func stressAxisLabel(for date: Date) -> String {
        guard selectedPeriod == .day else { return referenceAxisLabel(for: date) }
        if abs(date.timeIntervalSince(chartDomain.upperBound)) < 1 { return "24" }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard components.minute == 0,
              let hour = components.hour,
              hour.isMultiple(of: 3) else { return "" }
        return String(format: "%02d", hour)
    }

    private var axisTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private func axisTimeLabel(for date: Date) -> String {
        if abs(date.timeIntervalSince(chartDayEnd)) < 1 {
            return "24:00"
        }
        return axisTimeFormatter.string(from: date)
    }

    private var detailTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "M/d"
        return formatter
    }

    private var weekdayShortFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "EEE"
        return formatter
    }

    private var monthDayAxisFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "M/d"
        return formatter
    }

    private var monthAxisFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }

    private var dayHeaderFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("yyyyMM")
        return formatter
    }

    private var yearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "yyyy年"
        return formatter
    }

    private func weekRangeTitle(for date: Date) -> String {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return String(localized: "本周")
        }
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\(monthDayFormatter.string(from: interval.start)) - \(monthDayFormatter.string(from: end))"
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "d"
        return formatter
    }

    private var weekdayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "EEE"
        return formatter
    }

    private var weekRangeText: String {
        guard let first = recentWeekStressSummaries.first?.date, let last = recentWeekStressSummaries.last?.date else {
            return String(localized: "最近 7 天")
        }
        return "\(monthDayFormatter.string(from: first)) - \(monthDayFormatter.string(from: last))"
    }

    private var monthDayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }

    private func axisDates(for domain: ClosedRange<Date>, count: Int) -> [Date] {
        guard count > 1 else { return [domain.lowerBound] }
        let total = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard total > 0 else { return [domain.lowerBound] }
        return (0..<count).map { index in
            let progress = Double(index) / Double(count - 1)
            return domain.lowerBound.addingTimeInterval(total * progress)
        }
    }
}

private struct PressureDailySummary: Identifiable {
    let date: Date
    let averageValue: Int?
    let isToday: Bool

    var id: Date { date }
}

private enum PressureDetailPeriod: CaseIterable {
    case day
    case week
    case month
    case year

    var title: String {
        switch self {
        case .day: return "日"
        case .week: return "周"
        case .month: return "月"
        case .year: return "年"
        }
    }

    var rollingRange: BodySignalRollingRange {
        switch self {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        }
    }

    var shortTitle: String {
        switch self {
        case .day: return "今日"
        case .week: return "本周"
        case .month: return "本月"
        case .year: return "今年"
        }
    }

    var insightSubtitle: String {
        switch self {
        case .day: return "今日综合压力变化"
        case .week: return "这一周的综合压力走势"
        case .month: return "这个月的综合压力波动"
        case .year: return "这一年的综合压力节律"
        }
    }
}

private enum PressureAggregationBucket {
    case day
    case month
}

private extension View {
    func pressureDetailCard(
        tint: Color,
        cornerRadius: CGFloat,
        padding: CGFloat,
        shadow: Bool = false
    ) -> some View {
        self
            .padding(padding)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
            )
            .shadow(
                color: tint.opacity(shadow ? 0.14 : 0.07),
                radius: shadow ? 20 : 10,
                x: 0,
                y: shadow ? 10 : 5
            )
    }
}
