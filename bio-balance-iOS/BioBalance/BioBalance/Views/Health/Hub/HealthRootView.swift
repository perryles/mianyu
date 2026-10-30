/// HealthRootView 作为健康模块的支撑类型，负责定义健康因子枚举。
/// 负责描述睡眠、训练、步数、最大摄氧量、心率、体脂等因子的属性与数据加载。

import SwiftUI
import UIKit
import Charts
import HealthKit


/// 健康因子枚举 作为健康模块里的状态与分类定义。
/// 负责描述健康指标详情展示过程中会用到的状态、分类或分支。
enum HealthFactorKey: CaseIterable, Identifiable {
    case sleepDuration
    case sleepConsistency
    case aerobicTraining
    case strengthTraining
    case steps
    case vo2Max
    case restingHeartRate
    case bodyFat

    var id: String { title }

    var title: String {
        switch self {
        case .sleepDuration: return "睡眠时长"
        case .sleepConsistency: return "睡眠一致性"
        case .aerobicTraining: return "Z1-Z3训练"
        case .strengthTraining: return "力量训练"
        case .steps: return "步数"
        case .vo2Max: return "最大摄氧量"
        case .restingHeartRate: return "静息心率"
        case .bodyFat: return "体脂率"
        }
    }

    var unit: String {
        switch self {
        case .sleepDuration: return "小时"
        case .sleepConsistency: return "%"
        case .aerobicTraining, .strengthTraining: return "分钟"
        case .steps: return "步"
        case .vo2Max: return "ml/kg/min"
        case .restingHeartRate: return "次/分"
        case .bodyFat: return "%"
        }
    }

    var icon: String {
        switch self {
        case .sleepDuration: return "moon.zzz.fill"
        case .sleepConsistency: return "clock.fill"
        case .aerobicTraining: return "figure.run"
        case .strengthTraining: return "figure.strengthtraining.traditional"
        case .steps: return "shoeprints.fill"
        case .vo2Max: return "lungs.fill"
        case .restingHeartRate: return "heart.fill"
        case .bodyFat: return "figure.mixed.cardio"
        }
    }

    var iconColor: Color {
        switch self {
        case .sleepDuration: return .purple
        case .sleepConsistency: return .indigo
        case .aerobicTraining: return .blue
        case .strengthTraining: return .orange
        case .steps: return Theme.Colors.mintGreen
        case .vo2Max: return .red
        case .restingHeartRate: return Theme.Colors.accentRed
        case .bodyFat: return .teal
        }
    }

    func loadSeries(days: Int) async -> [TimeSeriesPointDouble] {
        let hk = HealthKitManager.shared
        switch self {
        case .sleepDuration:
            return (try? await hk.fetchSleepDurationSeries(days: days)) ?? []
        case .sleepConsistency:
            return (try? await hk.fetchSleepConsistencySeries(days: days)) ?? []
        case .aerobicTraining:
            return (try? await hk.fetchDailyExerciseTimeSums(days: days)) ?? []
        case .strengthTraining:
            return (try? await hk.fetchDailyStrengthTrainingMinutes(days: days)) ?? []
        case .steps:
            return (try? await hk.fetchDailyStepSums(days: days)) ?? []
        case .vo2Max:
            return (try? await hk.fetchDailyVo2MaxAverages(days: days)) ?? []
        case .restingHeartRate:
            return (try? await hk.fetchDailyRestingHeartRateAverages(days: days)) ?? []
        case .bodyFat:
            return (try? await hk.fetchDailyBodyFatPercentageAverages(days: days)) ?? []
        }
    }

    func displayValue(_ rawValue: Double?) -> String {
        guard let rawValue, rawValue > 0 else { return "--" }
        switch self {
        case .sleepDuration:
            return String(format: String(localized: "%.1f小时"), rawValue / 60.0)
        case .sleepConsistency:
            return "\(Int(rawValue.rounded()))%"
        case .aerobicTraining, .strengthTraining:
            return String(localized: "\(Int(rawValue.rounded()))分钟")
        case .steps:
            return String(localized: "\(Int(rawValue.rounded()))步")
        case .vo2Max:
            return String(format: "%.1f", rawValue)
        case .restingHeartRate:
            return String(localized: "\(Int(rawValue.rounded()))次/分")
        case .bodyFat:
            return String(format: "%.1f%%", rawValue * 100.0)
        }
    }

    func chartValue(_ rawValue: Double) -> Double {
        switch self {
        case .sleepDuration:
            return rawValue / 60.0
        case .bodyFat:
            return rawValue * 100.0
        default:
            return rawValue
        }
    }

    var prefersBarChart: Bool {
        switch self {
        case .sleepDuration, .aerobicTraining, .strengthTraining, .steps:
            return true
        case .sleepConsistency, .vo2Max, .restingHeartRate, .bodyFat:
            return false
        }
    }
}

/// 健康因子数据模型 作为健康模块里的数据载体。
/// 负责健康指标详情展示。
struct HealthFactorSnapshot {
    let valueText: String
    let subtitle: String
}

/// 健康因子趋势解读结构体 作为健康模块里的辅助类型。
/// 负责健康指标详情展示。
struct HealthFactorTrendInsight {
    let badgeText: String
    let detailText: String
    let averageText: String
}


/// 健康因子s视图模型 作为健康模块里的界面状态管理入口。
/// 负责健康指标详情展示。
@MainActor
@Observable
final class HealthFactorsViewModel {
    var snapshots: [HealthFactorKey: HealthFactorSnapshot] = [:]
    var trendSeries: [HealthFactorKey: [TimeSeriesPointDouble]] = [:]
    var trendInsights: [HealthFactorKey: HealthFactorTrendInsight] = [:]

    func load() {
        Task {
            var next: [HealthFactorKey: HealthFactorSnapshot] = [:]
            var nextSeries: [HealthFactorKey: [TimeSeriesPointDouble]] = [:]
            var nextInsights: [HealthFactorKey: HealthFactorTrendInsight] = [:]
            for key in HealthFactorKey.allCases {
                let series = await key.loadSeries(days: 14)
                nextSeries[key] = series
                let latest = series.last(where: { $0.value > 0 })?.value
                let values = series.map(\.value).filter { $0 > 0 }
                let avg = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
                next[key] = HealthFactorSnapshot(
                    valueText: key.displayValue(latest),
                    subtitle: avg == nil ? "健康 App 暂无数据" : "14天均值 \(key.displayValue(avg))"
                )
                nextInsights[key] = trendInsight(for: key, series: series, average: avg)
            }
            snapshots = next
            trendSeries = nextSeries
            trendInsights = nextInsights
        }
    }

    private func trendInsight(
        for key: HealthFactorKey,
        series: [TimeSeriesPointDouble],
        average: Double?
    ) -> HealthFactorTrendInsight {
        let points = series.filter { $0.value > 0 }
        guard points.count >= 2 else {
            return HealthFactorTrendInsight(
                badgeText: points.isEmpty ? "暂无数据" : "样本较少",
                detailText: points.isEmpty ? "健康 App 暂无可用趋势" : "再积累几天记录，会更容易看清方向。",
                averageText: average.map { "14天均值 \(key.displayValue($0))" } ?? "健康 App 暂无数据"
            )
        }

        let values = points.map(\.value)
        let current: Double
        let previous: Double
        if values.count >= 6 {
            let split = values.count / 2
            let firstHalf = Array(values.prefix(split))
            let secondHalf = Array(values.suffix(values.count - split))
            previous = firstHalf.reduce(0, +) / Double(firstHalf.count)
            current = secondHalf.reduce(0, +) / Double(secondHalf.count)
        } else {
            previous = values.first ?? 0
            current = values.last ?? 0
        }

        let delta = current - previous
        let threshold = max(abs(previous) * relativeThreshold(for: key), absoluteThreshold(for: key))
        let averageText = average.map { "14天均值 \(key.displayValue($0))" } ?? "健康 App 暂无数据"

        if abs(delta) < threshold {
            return HealthFactorTrendInsight(
                badgeText: "持平",
                detailText: "当前约 \(key.displayValue(current))，和前一阶段基本持平。",
                averageText: averageText
            )
        }

        let direction = delta > 0 ? directionText(for: key, rising: true) : directionText(for: key, rising: false)
        let deltaText = key.displayValue(abs(delta))
        return HealthFactorTrendInsight(
            badgeText: delta > 0 ? "上升" : "回落",
            detailText: "\(direction)\(deltaText)，当前约 \(key.displayValue(current))。",
            averageText: averageText
        )
    }

    private func absoluteThreshold(for key: HealthFactorKey) -> Double {
        switch key {
        case .sleepDuration:
            return 25
        case .sleepConsistency:
            return 3
        case .aerobicTraining, .strengthTraining:
            return 12
        case .steps:
            return 600
        case .vo2Max:
            return 0.8
        case .restingHeartRate:
            return 2
        case .bodyFat:
            return 0.015
        }
    }

    private func relativeThreshold(for key: HealthFactorKey) -> Double {
        switch key {
        case .bodyFat:
            return 0.04
        default:
            return 0.06
        }
    }

    private func directionText(for key: HealthFactorKey, rising: Bool) -> String {
        switch key {
        case .sleepDuration:
            return rising ? "睡眠时长增加 " : "睡眠时长回落 "
        case .sleepConsistency:
            return rising ? "作息稳定度提高 " : "作息稳定度下降 "
        case .aerobicTraining:
            return rising ? "Z1-Z3 训练增加 " : "Z1-Z3 训练回落 "
        case .strengthTraining:
            return rising ? "力量刺激增加 " : "力量刺激回落 "
        case .steps:
            return rising ? "日常活动量增加 " : "日常活动量回落 "
        case .vo2Max:
            return rising ? "心肺能力走高 " : "心肺能力回落 "
        case .restingHeartRate:
            return rising ? "静息心率升高 " : "静息心率回落 "
        case .bodyFat:
            return rising ? "体脂率上升 " : "体脂率回落 "
        }
    }
}

struct HealthLockedModuleContainer<Content: View>: View {
    let isUnlocked: Bool
    @ViewBuilder let content: () -> Content

    @State private var showingPaywall = false

    var body: some View {
        ZStack {
            content()
                .blur(radius: isUnlocked ? 0 : 4)
                .allowsHitTesting(isUnlocked)

            if !isUnlocked {
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.appSystem(size: 28))
                        .foregroundColor(Theme.Colors.textTertiary)

                    Text("会员可查看该内容")
                        .font(Theme.Typography.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)

                    Button(action: { showingPaywall = true }) {
                        Text("免费试用")
                            .font(Theme.Typography.bodyMedium.weight(.bold))
                            .foregroundColor(Theme.Colors.onAccent)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Theme.Colors.mintGreen)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isUnlocked else { return }
            showingPaywall = true
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }
}

/// FactorsList卡片组件 作为健康模块里的内容展示卡片。
/// 负责健康指标详情展示。
struct FactorsListCard: View {
    /// Factor Item 结构体，作为内部辅助类型，用于配合外层健康指标详情展示。
    struct FactorItem: Identifiable {
        let key: HealthFactorKey
        var id: String { key.id }
        var title: String { key.title }
        var icon: String { key.icon }
        var iconColor: Color { key.iconColor }
    }

    @State private var selectedFactor: FactorItem?
    @State private var viewModel = HealthFactorsViewModel()
    
    let factors = HealthFactorKey.allCases.map { FactorItem(key: $0) }

    private var spotlightFactor: FactorItem {
        if let available = factors.first(where: { (viewModel.snapshots[$0.key]?.valueText ?? "--") != "--" }) {
            return available
        }
        return factors.first ?? FactorItem(key: .sleepDuration)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(factors) { item in
                factorRowCard(item)
            }
        }
        .padding(.top, 2)
        .sheet(item: $selectedFactor) { factor in
            FactorDetailSheetView(factor: factor)
        }
        .onAppear {
            viewModel.load()
        }
    }

    private func factorRowCard(_ item: FactorItem) -> some View {
        let snapshot = viewModel.snapshots[item.key]
        let insight = viewModel.trendInsights[item.key]
        let series = viewModel.trendSeries[item.key] ?? []

        return Button {
            selectedFactor = item
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.appSystem(size: 16, weight: .bold))
                            .foregroundColor(item.iconColor)
                            .frame(width: 38, height: 38)
                            .background(item.iconColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.appSystem(size: 18, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(insight?.badgeText ?? "等待同步")
                                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(item.iconColor)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: Theme.Icons.chevronRight)
                            .font(.appSystem(size: 12, weight: .heavy))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(snapshot?.valueText ?? "--")
                            .font(.appSystem(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Text(insight?.detailText ?? snapshot?.subtitle ?? "健康 App 暂无数据")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        factorMetricPill(title: "均值", value: insight?.averageText ?? (snapshot?.subtitle ?? "等待同步"), tint: item.iconColor)
                        factorMetricPill(title: "趋势", value: insight?.badgeText ?? "暂无数据", tint: item.iconColor)
                        factorMetricPill(title: "覆盖", value: "\(series.filter { $0.value > 0 }.count)天", tint: item.iconColor)
                    }
                }

                Spacer(minLength: 0)

                factorSideVisual(item: item, series: series)
            }
            .padding(16)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func factorMetricPill(title: String, value: String, tint: Color) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Theme.Colors.surface.opacity(0.26), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
        )
    }

    private func factorSideVisual(item: FactorItem, series: [TimeSeriesPointDouble]) -> some View {
        let positiveSeries = series.map(\.value).filter { $0 > 0 }
        let maxValue = max(positiveSeries.max() ?? 1, 1)

        return VStack(spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 92, height: 92)
                .overlay {
                    Circle()
                        .stroke(item.iconColor.opacity(0.12), lineWidth: 10)
                        .frame(width: 84, height: 84)

                    if positiveSeries.isEmpty {
                        Image(systemName: item.icon)
                            .font(.appSystem(size: 26, weight: .bold))
                            .foregroundColor(item.iconColor)
                    } else {
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(Array(positiveSeries.suffix(5).enumerated()), id: \.offset) { index, value in
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(index == positiveSeries.suffix(5).count - 1 ? item.iconColor : item.iconColor.opacity(0.26))
                                    .frame(width: 8, height: max(10, CGFloat(value / maxValue) * 38))
                            }
                        }
                    }
                }
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.82), lineWidth: 1)
                        .frame(width: 92, height: 92)
                )

            Text("点击查看")
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(item.iconColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(item.iconColor.opacity(0.10), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
                )
        }
        .frame(width: 98)
    }
}

/// 因子详情视图模型 作为健康模块里的界面状态管理入口。
/// 负责健康指标详情展示。
@MainActor
@Observable
final class FactorDetailViewModel {
    var points: [TimeSeriesPointDouble] = []
    var isLoading = false
    /// 加载代际：快速切换天数时只允许最新一次加载写入结果。
    private var loadGeneration = 0

    func load(key: HealthFactorKey, days: Int) {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let loaded = await key.loadSeries(days: days)
            guard !Task.isCancelled, generation == self.loadGeneration else { return }
            self.points = loaded
            self.isLoading = false
        }
    }
}

/// 因子视图 由上级页面或路由调用，作为健康模块里的界面或内容组件。
/// 负责健康指标详情展示。
struct FactorDetailSheetView: View {
    let factor: FactorsListCard.FactorItem
    @State private var days: Int = 14
    @State private var selectedChartTimestamp: Int64?
    @State private var viewModel = FactorDetailViewModel()

    private var hasPositiveData: Bool {
        viewModel.points.contains { $0.value > 0 }
    }

    private var chartPoints: [TimeSeriesPointDouble] {
        guard hasPositiveData else { return [] }
        if factor.key.prefersBarChart {
            return viewModel.points
        }
        return viewModel.points.filter { $0.value > 0 }
    }

    private var reversedPoints: [TimeSeriesPointDouble] {
        guard hasPositiveData else { return [] }
        if factor.key.prefersBarChart {
            return Array(viewModel.points.reversed())
        }
        return Array(chartPoints.reversed())
    }

    private var avg: Double {
        let vals = viewModel.points.map(\.value).filter { $0 > 0 }
        return vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
    }

    private var chartYDomain: ClosedRange<Double> {
        let values = chartPoints.map { factor.key.chartValue($0.value) }
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        if factor.key.prefersBarChart {
            return 0...(maxValue + max(maxValue * 0.15, 1))
        }

        if abs(maxValue - minValue) < 0.0001 {
            let padding = max(1, abs(maxValue) * 0.15)
            return max(0, minValue - padding)...(maxValue + padding)
        }

        let padding = max((maxValue - minValue) * 0.18, maxValue * 0.06)
        return max(0, minValue - padding)...(maxValue + padding)
    }

    private var averageLabel: String {
        chartPoints.isEmpty ? "健康 App 暂无数据" : "均值 \(factor.key.displayValue(avg))"
    }

    private var positivePoints: [TimeSeriesPointDouble] {
        viewModel.points.filter { $0.value > 0 }
    }

    private var latestPositivePoint: TimeSeriesPointDouble? {
        positivePoints.last
    }

    private var highestPoint: TimeSeriesPointDouble? {
        positivePoints.max(by: { $0.value < $1.value })
    }

    private var lowestPoint: TimeSeriesPointDouble? {
        positivePoints.min(by: { $0.value < $1.value })
    }

    private var dataCoverageText: String {
        guard !viewModel.points.isEmpty else { return "暂无数据" }
        let count = positivePoints.count
        let ratio = Double(count) / Double(max(days, 1))
        return String(localized: "\(count)/\(days) 天有记录 · 覆盖率 \(localizedPercentRatio(ratio))")
    }

    private var chartRangeText: String {
        let first = chartXDomain.lowerBound
        guard let last = Calendar.current.date(byAdding: .day, value: -1, to: chartXDomain.upperBound) else {
            return String(localized: "最近 \(days) 天")
        }
        return "\(detailDateText(for: first)) - \(detailDateText(for: last))"
    }

    private var trendInsightText: String {
        guard positivePoints.count >= 2 else {
            return hasPositiveData ? "数据量还比较少，继续记录几天后会出现更稳定的趋势判断。" : "授权并同步健康 App 数据后，这里会显示近期变化解读。"
        }

        let latest = positivePoints.suffix(max(1, min(3, positivePoints.count)))
        let previousCount = min(latest.count, max(0, positivePoints.count - latest.count))
        guard previousCount > 0 else {
            return String(localized: "已读取到近期数据，继续累积后可以对比前后变化。")
        }

        let previous = positivePoints.dropLast(latest.count).suffix(previousCount)
        let latestAvg = latest.map(\.value).reduce(0, +) / Double(latest.count)
        let previousAvg = previous.map(\.value).reduce(0, +) / Double(previous.count)
        let delta = latestAvg - previousAvg

        if abs(delta) < max(previousAvg * 0.05, 1) {
            return String(localized: "最近几天与前段时间基本持平，整体比较稳定。")
        }

        let direction = delta > 0 ? "上升" : "下降"
        let formatted = detailValue(for: abs(delta))
        return String(localized: "最近几天相比前段时间平均\(direction)约 \(formatted)。")
    }

    private var chartXDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let visibleEnd = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: end) ?? end
        return start...visibleEnd
    }

    private var chartAxisDates: [Date] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: end) ?? end
        let step = max(1, days / 4)
        var dates: [Date] = []
        var offset = 0

        while offset < days {
            if let date = calendar.date(byAdding: .day, value: offset, to: start) {
                dates.append(date)
            }
            offset += step
        }

        if !dates.contains(where: { calendar.isDate($0, inSameDayAs: end) }) {
            dates.append(end)
        }
        return dates
    }

    private var focusHeadline: String {
        guard hasPositiveData else { return "等待健康数据同步" }
        if positivePoints.count < 3 {
            return String(localized: "先继续积累样本")
        }
        return trendInsightText
    }

    private var selectedChartPoint: TimeSeriesPointDouble? {
        guard let selectedChartTimestamp else { return nil }
        return chartPoints.first(where: { $0.timestamp == selectedChartTimestamp })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ReportsSoftBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        detailHeroHeader

                        detailOverviewPanel

                        detailSummaryCard

                        VStack(spacing: 14) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("趋势图")
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    Text(chartRangeText)
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                Text(dataCoverageText)
                                    .font(.appSystem(size: 10, weight: .semibold))
                                    .foregroundColor(factor.iconColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(factor.iconColor.opacity(0.10))
                                    .clipShape(Capsule())
                            }

                            Picker("天数", selection: $days) {
                                Text("7天").tag(7)
                                Text("14天").tag(14)
                                Text("30天").tag(30)
                            }
                            .pickerStyle(.segmented)
                            .tint(Theme.Colors.textPrimary)

                            if viewModel.isLoading {
                                ProgressView("正在读取健康 App 数据")
                                    .font(Theme.Typography.bodyMedium)
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 180)
                            } else if chartPoints.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "waveform.path.ecg")
                                        .font(.appSystem(size: 22, weight: .semibold))
                                        .foregroundColor(Theme.Colors.textTertiary)
                                    Text("健康 App 暂无可展示数据")
                                        .font(Theme.Typography.bodyMedium)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                            } else {
                                trendChart

                                if let selectedChartPoint {
                                    selectedChartDetailCard(for: selectedChartPoint)
                                }
                            }
                        }
                        .padding(Theme.Layout.padding)
                        .background(
                            LinearGradient(
                                colors: [Color.white, factor.iconColor.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                                .stroke(factor.iconColor.opacity(0.10), lineWidth: 1)
                        )

                        insightCard

                        VStack(alignment: .leading, spacing: 10) {
                            Text("明细")
                                .font(Theme.Typography.headline)
                                .foregroundColor(Theme.Colors.textPrimary)

                            if reversedPoints.isEmpty {
                                Text("最近 \(days) 天暂无明细记录。")
                                    .font(Theme.Typography.bodyMedium)
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(reversedPoints.enumerated()), id: \.element.id) { index, item in
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(detailDateText(for: item.date))
                                                    .font(Theme.Typography.bodyMedium)
                                                    .foregroundColor(Theme.Colors.textPrimary)
                                                Text(detailDayText(for: item.date))
                                                    .font(Theme.Typography.caption)
                                                    .foregroundColor(Theme.Colors.textTertiary)
                                            }

                                            Spacer()

                                            Text(detailValue(for: item.value))
                                                .font(Theme.Typography.bodyBold)
                                                .foregroundColor(Theme.Colors.textPrimary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(factor.iconColor.opacity(0.10))
                                                .clipShape(Capsule())
                                        }
                                        .padding(.vertical, 10)

                                        if index != reversedPoints.count - 1 {
                                            Divider().opacity(0.35)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(Theme.Layout.padding)
                        .background(Theme.Colors.surface)
                        .cornerRadius(Theme.Layout.cornerRadius)
                    }
                    .padding(.horizontal, Theme.Layout.padding)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("影响因素")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            viewModel.load(key: factor.key, days: days)
            selectedChartTimestamp = chartPoints.last?.timestamp
        }
        .onChange(of: days) { _, newValue in
            viewModel.load(key: factor.key, days: newValue)
            selectedChartTimestamp = nil
        }
        .onChange(of: chartPoints.map(\.timestamp)) { _, timestamps in
            guard !timestamps.isEmpty else {
                selectedChartTimestamp = nil
                return
            }
            if let selectedChartTimestamp, timestamps.contains(selectedChartTimestamp) {
                return
            }
            selectedChartTimestamp = timestamps.last
        }
    }

    private var selectedChartPoints: [TimeSeriesPointDouble] {
        selectedChartPoint.map { [$0] } ?? []
    }

    private var trendChart: some View {
        Group {
            if factor.key.prefersBarChart {
                barTrendChart
            } else {
                lineAreaTrendChart
            }
        }
        .chartXScale(domain: chartXDomain)
        .chartYScale(domain: chartYDomain)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            SpatialTapGesture().onEnded { value in
                                updateChartSelection(at: value.location, frame: frame, proxy: proxy)
                            }
                        )
                        .gesture(
                            LongPressGesture(minimumDuration: 0.12)
                                .sequenced(before: DragGesture(minimumDistance: 0))
                                .onChanged { value in
                                    switch value {
                                    case .first:
                                        break
                                    case .second(true, let drag):
                                        guard let drag else { return }
                                        updateChartSelection(at: drag.location, frame: frame, proxy: proxy)
                                    default:
                                        break
                                    }
                                }
                                .onEnded { value in
                                    switch value {
                                    case .second(true, let drag):
                                        if let drag {
                                            updateChartSelection(at: drag.location, frame: frame, proxy: proxy)
                                        }
                                    default:
                                        break
                                    }
                                }
                        )
                } else {
                    Color.clear
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: chartAxisDates) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Color.black.opacity(0.08))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.black.opacity(0.15))
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(detailDateText(for: date))
                            .font(.appSystem(size: 10, weight: .medium))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Color.black.opacity(0.08))
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(axisLabel(for: doubleValue))
                            .font(.appSystem(size: 10, weight: .medium))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .clipped()
        }
        .frame(height: 236)
        .padding(.bottom, 8)
    }

    private var barTrendChart: some View {
        Chart {
            ForEach(chartPoints) { item in
                BarMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Value", factor.key.chartValue(item.value))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            factor.iconColor.opacity(selectedChartPoint == nil || selectedChartPoint?.timestamp == item.timestamp ? 0.95 : 0.40),
                            factor.iconColor.opacity(selectedChartPoint == nil || selectedChartPoint?.timestamp == item.timestamp ? 0.62 : 0.24)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(6)
            }

            ForEach(selectedChartPoints) { selectedPoint in
                selectedChartOverlay(for: selectedPoint)
            }
        }
    }

    private var lineAreaTrendChart: some View {
        Chart {
            ForEach(chartPoints) { item in
                AreaMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Value", factor.key.chartValue(item.value))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [factor.iconColor.opacity(0.22), factor.iconColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Value", factor.key.chartValue(item.value))
                )
                .foregroundStyle(factor.iconColor.opacity(0.24))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))

                LineMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Value", factor.key.chartValue(item.value))
                )
                .foregroundStyle(factor.iconColor)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Value", factor.key.chartValue(item.value))
                )
                .foregroundStyle(factor.iconColor)
                .opacity(selectedChartPoint == nil || selectedChartPoint?.timestamp == item.timestamp ? 1 : 0.35)
            }

            ForEach(selectedChartPoints) { selectedPoint in
                selectedChartOverlay(for: selectedPoint)
            }
        }
    }

    @ChartContentBuilder
    private func selectedChartOverlay(for selectedPoint: TimeSeriesPointDouble) -> some ChartContent {
        RuleMark(x: .value("选中", selectedPoint.date, unit: .day))
            .foregroundStyle(factor.iconColor.opacity(0.24))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

        PointMark(
            x: .value("Date", selectedPoint.date, unit: .day),
            y: .value("Value", factor.key.chartValue(selectedPoint.value))
        )
        .symbolSize(90)
        .foregroundStyle(Theme.Colors.onAccent)
        .annotation(position: .overlay, alignment: .center) {
            Circle()
                .fill(factor.iconColor)
                .frame(width: 13, height: 13)
        }
    }

    private var detailHeroHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(factor.iconColor.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: factor.icon)
                            .foregroundColor(factor.iconColor)
                            .font(.appSystem(size: 20, weight: .bold))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(factor.title)
                            .font(.appSystem(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(averageLabel)
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                Text(focusHeadline)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text("\(days)天")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(factor.iconColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(factor.iconColor.opacity(0.10), in: Capsule())
        }
        .padding(Theme.Layout.padding)
        .background(
            LinearGradient(
                colors: [Color.white, factor.iconColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                .stroke(factor.iconColor.opacity(0.12), lineWidth: 1)
        )
    }

    private var detailOverviewPanel: some View {
        HStack(spacing: 12) {
            summaryStatCard(
                title: "覆盖率",
                value: dataCoverageText,
                subtitle: "最近 \(days) 天"
            )
            summaryStatCard(
                title: "趋势判断",
                value: hasPositiveData ? (positivePoints.count < 3 ? "样本偏少" : "已有方向") : "暂无",
                subtitle: hasPositiveData ? "已同步健康 App" : "等待同步"
            )
        }
    }

    private func axisLabel(for value: Double) -> String {
        switch factor.key {
        case .steps:
            if value >= 10000 {
                return String(format: String(localized: "%.1f万"), value / 10000.0)
            }
            return "\(Int(value.rounded()))"
        case .sleepDuration:
            return String(format: String(localized: "%.1f时"), value)
        case .aerobicTraining, .strengthTraining:
            return String(localized: "\(Int(value.rounded()))分")
        case .sleepConsistency, .bodyFat:
            return "\(Int(value.rounded()))"
        case .vo2Max:
            return String(format: "%.1f", value)
        case .restingHeartRate:
            return "\(Int(value.rounded()))"
        }
    }

    private func detailValue(for value: Double) -> String {
        if value > 0 {
            return factor.key.displayValue(value)
        }

        switch factor.key {
        case .sleepDuration:
            return String(localized: "0.0小时")
        case .aerobicTraining, .strengthTraining:
            return "0分钟"
        case .steps:
            return String(localized: "0步")
        default:
            return "--"
        }
    }

    private func updateChartSelection(at location: CGPoint, frame: CGRect, proxy: ChartProxy) {
        guard frame.contains(location) else { return }
        let relativeX = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: relativeX) else { return }
        selectedChartTimestamp = nearestChartPoint(to: date)?.timestamp
    }

    private func nearestChartPoint(to date: Date) -> TimeSeriesPointDouble? {
        chartPoints.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    private func selectedChartDetailCard(for point: TimeSeriesPointDouble) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(detailDateText(for: point.date))
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detailDayText(for: point.date))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer()
                Text(detailValue(for: point.value))
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(factor.iconColor)
            }

            Text(selectedChartDescription(for: point))
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [factor.iconColor.opacity(0.12), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func selectedChartDescription(for point: TimeSeriesPointDouble) -> String {
        let valueText = detailValue(for: point.value)
        switch factor.key {
        case .aerobicTraining:
            return String(localized: "\(detailDateText(for: point.date)) 共记录 \(valueText)，更适合和睡眠恢复一起看有氧负荷是否稳定。")
        case .strengthTraining:
            return String(localized: "\(detailDateText(for: point.date)) 共记录 \(valueText)，力量训练天更适合留意第二天恢复是否跟上。")
        case .steps:
            return String(localized: "\(detailDateText(for: point.date)) 共走了 \(valueText)，步数更适合结合连续几天的节奏判断活跃度。")
        case .sleepDuration:
            return String(localized: "\(detailDateText(for: point.date)) 睡了 \(valueText)，先看它是否连续偏短，再判断恢复负荷。")
        case .sleepConsistency:
            return String(localized: "\(detailDateText(for: point.date)) 的作息一致性为 \(valueText)，连续稳定通常比单天更有参考意义。")
        case .vo2Max:
            return String(localized: "\(detailDateText(for: point.date)) 的心肺耐力估算为 \(valueText)，这类指标更适合按周看趋势。")
        case .restingHeartRate:
            return String(localized: "\(detailDateText(for: point.date)) 的静息状态约为 \(valueText)，若连续走高通常更值得结合疲劳一起看。")
        case .bodyFat:
            return String(localized: "\(detailDateText(for: point.date)) 的身体组成记录为 \(valueText)，这类变化更适合长期观察。")
        }
    }

    private var detailSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("数据摘要")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            if hasPositiveData {
                HStack(spacing: 12) {
                    summaryStatCard(
                        title: "最近一次",
                        value: detailValue(for: latestPositivePoint?.value ?? 0),
                        subtitle: latestPositivePoint.map { detailDateText(for: $0.date) } ?? "暂无"
                    )
                    summaryStatCard(
                        title: "最高",
                        value: detailValue(for: highestPoint?.value ?? 0),
                        subtitle: highestPoint.map { detailDateText(for: $0.date) } ?? "暂无"
                    )
                    summaryStatCard(
                        title: "最低",
                        value: detailValue(for: lowestPoint?.value ?? 0),
                        subtitle: lowestPoint.map { detailDateText(for: $0.date) } ?? "暂无"
                    )
                }
            } else {
                Text("最近 \(days) 天还没有可用于展示的健康数据。")
                    .font(Theme.Typography.bodyMedium)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Layout.padding)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.Layout.cornerRadius)
    }

    private var insightCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(factor.iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.appSystem(size: 15, weight: .bold))
                    .foregroundColor(factor.iconColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("趋势解读")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(trendInsightText)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("数据来源：健康 App")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Layout.padding)
        .background(
            LinearGradient(
                colors: [factor.iconColor.opacity(0.12), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(Theme.Layout.cornerRadius)
    }

    private func summaryStatCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.appSystem(size: 11, weight: .medium))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(factor.iconColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func detailDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    private func detailDayText(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return String(localized: "今天")
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "昨天")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

/// Locked趋势卡片组件 作为健康模块里的内容展示卡片。
/// 负责健康指标详情展示。
struct LockedTrendCard: View {
    let title: String
    let points: [HealthAgeTrendPoint]
    let unit: String
    let tint: Color
    var usesTintedSurface: Bool = false
    var tintedSurfaceTint: Color = .white
    private var subscriptionManager = SubscriptionManager.shared
    @State private var showingPaywall = false

    /// 创建可复用的锁定趋势卡片，不向其他文件的调用方暴露内部订阅和付费墙状态。
    init(
        title: String,
        points: [HealthAgeTrendPoint],
        unit: String,
        tint: Color,
        usesTintedSurface: Bool = false,
        tintedSurfaceTint: Color = .white
    ) {
        self.title = title
        self.points = points
        self.unit = unit
        self.tint = tint
        self.usesTintedSurface = usesTintedSurface
        self.tintedSurfaceTint = tintedSurfaceTint
    }

    private var chartDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        let visibleEnd = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        return start...visibleEnd
    }

    private var axisDates: [Date] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -(6 - offset), to: end)
        }
    }

    private var chartYDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        if abs(maxValue - minValue) < 0.01 {
            let padding = max(1, abs(maxValue) * 0.08)
            return (minValue - padding)...(maxValue + padding)
        }

        let padding = max((maxValue - minValue) * 0.18, 0.6)
        return (minValue - padding)...(maxValue + padding)
    }

    private var yAxisValues: [Double] {
        let domain = chartYDomain
        let step = (domain.upperBound - domain.lowerBound) / 3
        guard step.isFinite, step > 0 else { return [domain.lowerBound] }
        return (0...3).map { domain.lowerBound + (Double($0) * step) }
    }

    private var latestValueText: String {
        guard let latest = points.last?.value else { return "--" }
        return formattedValue(latest)
    }

    private var averageValueText: String {
        guard !points.isEmpty else { return "--" }
        let total = points.reduce(0) { $0 + $1.value }
        return formattedValue(total / Double(points.count))
    }

    private var rangeValueText: String {
        let values = points.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else { return "--" }
        return "\(formattedValue(minValue)) - \(formattedValue(maxValue))"
    }

    private var weeklyDirectionText: String {
        guard points.count >= 2 else { return "继续记录" }
        let latest = points.suffix(min(3, points.count))
        let previous = points.dropLast(latest.count).suffix(latest.count)
        guard !previous.isEmpty else { return "继续记录" }
        let latestAverage = latest.reduce(0) { $0 + $1.value } / Double(latest.count)
        let previousAverage = previous.reduce(0) { $0 + $1.value } / Double(previous.count)
        let delta = latestAverage - previousAverage
        if abs(delta) < 0.25 { return "本周持平" }
        return delta < 0 ? "本周更年轻" : "本周偏高"
    }

    private var weeklyDirectionTint: Color {
        switch weeklyDirectionText {
        case "本周更年轻":
            return Theme.Colors.mintGreen
        case "本周偏高":
            return Color(hex: "FF8A5B")
        default:
            return tint
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            
            ZStack {
                trendChart
                    .blur(radius: subscriptionManager.isPro ? 0 : 4)

                if !subscriptionManager.isPro {
                    lockedTrendOverlay
                }
            }
            .modifier(
                TrendContainerStyle(
                    tint: tint,
                    surfaceTint: tintedSurfaceTint,
                    usesTintedSurface: usesTintedSurface
                )
            )
        }
        .padding(.top, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !subscriptionManager.isPro else { return }
            showingPaywall = true
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }

    private var trendChart: some View {
        VStack(spacing: 12) {
            if points.isEmpty {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<7, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.24), tint.opacity(0.08)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 30, height: CGFloat([58, 78, 52, 94, 70, 84, 64][index]))
                    }
                }
            } else {
                HStack(spacing: 12) {
                    trendMetric(title: "最新", value: latestValueText)
                    trendMetric(title: "均值", value: averageValueText)
                    trendMetric(title: "范围", value: rangeValueText)
                }

                HStack(spacing: 8) {
                    Text(weeklyDirectionText)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(weeklyDirectionTint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(weeklyDirectionTint.opacity(0.12), in: Capsule())

                    Text("按周看身体年龄变化，比看单天更有参考意义。")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                Chart(points) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(tint.opacity(0.22))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))

                    LineMark(
                        x: .value("日期", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(tint)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.22), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    PointMark(
                        x: .value("日期", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(tint)

                    if !points.isEmpty {
                        RuleMark(y: .value("均值", points.reduce(0) { $0 + $1.value } / Double(points.count)))
                            .foregroundStyle(tint.opacity(0.24))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("均值 \(averageValueText)")
                                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(tint)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .modifier(
                                        TrendAnnotationStyle(
                                            tint: tint,
                                            surfaceTint: tintedSurfaceTint,
                                            usesTintedSurface: usesTintedSurface
                                        )
                                    )
                            }
                    }
                }
                .chartXScale(domain: chartDomain)
                .chartYScale(domain: chartYDomain)
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Color.black.opacity(0.06))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.black.opacity(0.12))
                        AxisValueLabel(centered: true) {
                            if let date = value.as(Date.self) {
                                Text(shortAxisDateText(for: date))
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: yAxisValues) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Color.black.opacity(0.08))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.black.opacity(0.12))
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(formattedValue(doubleValue))
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .clipped()
                }
                .frame(height: 162)
                .padding(.bottom, 8)
            }
        }
    }

    private var lockedTrendOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.appSystem(size: 28))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("会员可查看该内容")
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)

            Button(action: {
                showingPaywall = true
            }) {
                Text("免费试用")
                    .font(Theme.Typography.bodyMedium.weight(.bold))
                    .foregroundColor(Theme.Colors.onAccent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Theme.Colors.mintGreen)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)

            Text("解锁后可查看每周身体年龄变化与长期恢复方向")
                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    private func shortAxisDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func formattedValue(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return "\(Int(value.rounded()))\(unit)"
        }
        return String(format: "%.1f%@", value, unit)
    }

    private func trendMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .modifier(
            TrendMetricStyle(
                tint: tint,
                surfaceTint: tintedSurfaceTint,
                usesTintedSurface: usesTintedSurface
            )
        )
    }
}

private struct TrendContainerStyle: ViewModifier {
    let tint: Color
    let surfaceTint: Color
    let usesTintedSurface: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesTintedSurface {
            content
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 20)
                .background(Color.clear)
                .bbTintedSurface(
                    tint: surfaceTint,
                    in: RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous),
                    tintStrength: 0.08
                )
        } else {
            content
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 20)
                .background(Theme.Colors.secondaryBackground.opacity(0.5))
                .cornerRadius(Theme.Layout.cornerRadius)
        }
    }
}

private struct TrendAnnotationStyle: ViewModifier {
    let tint: Color
    let surfaceTint: Color
    let usesTintedSurface: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesTintedSurface {
            content
                .bbTintedChip(tint: surfaceTint, in: Capsule(), tintOpacity: 0.10)
        } else {
            content
                .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
        }
    }
}

private struct TrendMetricStyle: ViewModifier {
    let tint: Color
    let surfaceTint: Color
    let usesTintedSurface: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesTintedSurface {
            content
                .background(Color.clear)
                .bbTintedSurface(
                    tint: surfaceTint,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    tintStrength: 0.07,
                    shadow: false
                )
        } else {
            content
                .background(Theme.Colors.secondaryBackground.opacity(0.32), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.65), lineWidth: 1)
                )
        }
    }
}


#Preview {
    BodyAgeView()
}
