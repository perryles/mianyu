import Foundation
import HealthKit

/// 压力TimeSlot数据模型 作为视图模型层里的数据载体。
/// 负责界面状态管理与业务编排。
struct PressureTimeSlotCell: Identifiable, Hashable {
    /// Source 枚举，作为内部辅助类型，用于细分外层界面状态管理与业务编排中的状态或分支。
    enum Source: Hashable {
        case measured
        case estimated
        case inferred
        case empty
    }

    let date: Date
    let slotStartHour: Int
    let slotDurationHours: Int
    let value: Double?
    let source: Source

    var id: String {
        "\(date.timeIntervalSince1970)-\(slotStartHour)-\(slotDurationHours)"
    }

    var kind: PressureBucket.Kind? {
        guard let value else { return nil }
        return PressureBucket.Kind(value: value)
    }

    var isInferred: Bool {
        source == .inferred
    }
}

/// 压力TimeSlot行组件 作为视图模型层里的列表行组件。
/// 负责界面状态管理与业务编排。
struct PressureTimeSlotRow: Identifiable, Hashable {
    let date: Date
    let cells: [PressureTimeSlotCell]

    var id: TimeInterval { date.timeIntervalSince1970 }
}

/// 压力Sample数据模型 作为视图模型层里的数据载体。
/// 负责界面状态管理与业务编排。
struct PressureSamplePoint: Identifiable, Hashable {
    let timestamp: Int64
    let value: Double
    let source: PressureTimeSlotCell.Source

    var id: Int64 { timestamp }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
    var kind: PressureBucket.Kind { PressureBucket.Kind(value: value) }
    var isInferred: Bool { source == .inferred }
}

private struct PressureDayHourKey: Hashable {
    let day: Date
    let hour: Int
}

/// Trends视图模型 作为视图模型层里的界面状态管理入口。
/// 负责界面状态管理与业务编排。
@MainActor
@Observable
final class TrendsViewModel {
    var isLoading: Bool = false

    var pressureTimeSlotRows: [PressureTimeSlotRow] = []
    var pressureTimeSlotSamples: [PressureSamplePoint] = []

    var categoryCards: [TrendCategoryCardModel] = []
    var featuredCategoryCards: [FeaturedTrendCategoryModel] = []
    var selectedCategoryDetail: TrendCategoryDetailModel?

    private var categoryDetails: [TrendCategoryID: TrendCategoryDetailModel] = [:]
    private var categoryDetailsRange: TrendsRange?
    private var selectedRange: TrendsRange = .day
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    /// 分类详情加载代际：连续点击多张卡片时只允许最近一次写入 selectedCategoryDetail，
    /// 且不再改写 selectedRange（避免打断在途的 load() 导致 isLoading 永不复位）。
    private var detailGeneration = 0

    func load(range: TrendsRange = .day) {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        selectedRange = range

        loadTask = Task {
            let hk = HealthKitManager.shared
            async let history = fetchHistory(days: range.windowDays)
            async let hourlyStressInputs = fetchHourlyStressInputs(for: range, healthKit: hk)

            let historyData = await history
            let hourlyInputs = await hourlyStressInputs
            let historyEvents = historyData?.stressPoints.map {
                TimeSeriesPointDouble(timestamp: $0.timestamp, value: Double($0.value))
            } ?? []
            let slotMatrix = PressureMatrixMath.buildPressureSlotMatrix(
                range: range,
                historyEvents: historyEvents,
                estimatedHourly: hourlyInputs
            )

            guard !Task.isCancelled,
                  generation == self.loadGeneration,
                  range == self.selectedRange else { return }

            self.pressureTimeSlotRows = slotMatrix.rows
            self.pressureTimeSlotSamples = slotMatrix.samples

            await self.loadCategoryCards(range: range)
            guard !Task.isCancelled,
                  generation == self.loadGeneration,
                  range == self.selectedRange else { return }
            self.isLoading = false
        }
    }

    func loadCategoryCards(range: TrendsRange) async {
        let builder = TrendCategoryBuilder(healthKitManager: .shared)
        let result = await builder.build(range: range)
        guard selectedRange == range else { return }
        categoryCards = result.cards
        categoryDetails = result.details
        categoryDetailsRange = range
        featuredCategoryCards = Self.buildFeaturedCategoryCards(from: result.details)
        await enrichSleepInsightIfNeeded(expectedRange: range)
    }

    func loadCategoryDetail(_ category: TrendCategoryID, range: TrendsRange) async {
        // 不改写共享 selectedRange：用户点击的卡片范围总是等于当前 dashboard 所选范围，
        // 改写反而会让在途 load() 的 `range == selectedRange` 守卫失败并卡住 isLoading。
        detailGeneration += 1
        let generation = detailGeneration
        if categoryDetailsRange == range, let cached = categoryDetails[category] {
            selectedCategoryDetail = cached
            if category == .sleepRecovery {
                await enrichSleepInsightIfNeeded(expectedRange: range)
            }
            return
        }

        let builder = TrendCategoryBuilder(healthKitManager: .shared)
        let result = await builder.build(range: range)
        guard !Task.isCancelled, generation == detailGeneration else { return }
        categoryCards = result.cards
        categoryDetails = result.details
        categoryDetailsRange = range
        featuredCategoryCards = Self.buildFeaturedCategoryCards(from: result.details)
        selectedCategoryDetail = result.details[category]
        await enrichSleepInsightIfNeeded(expectedRange: range)
    }

    private func enrichSleepInsightIfNeeded(expectedRange: TrendsRange) async {
        guard selectedRange == expectedRange,
              categoryDetailsRange == expectedRange,
              var sleepDetail = categoryDetails[.sleepRecovery] else { return }
        let remoteInsight = await fetchInsightData()
        guard selectedRange == expectedRange,
              categoryDetailsRange == expectedRange else { return }
        guard let merged = mergeSleepInsight(detail: sleepDetail, remote: remoteInsight) else { return }
        sleepDetail = merged
        categoryDetails[.sleepRecovery] = sleepDetail
        categoryCards = categoryCards.map { card in
            guard card.category == .sleepRecovery else { return card }
            return TrendCategoryCardModel(
                category: card.category,
                status: card.status,
                primaryValueText: sleepDetail.metrics.first?.summary ?? card.status.title,
                summary: sleepDetail.headerSummary,
                highlights: sleepDetail.metrics.prefix(3).map { metric in
                    "\(metric.title) · \(metric.summary)"
                }
            )
        }
        featuredCategoryCards = Self.buildFeaturedCategoryCards(from: categoryDetails)
        if selectedCategoryDetail?.category == .sleepRecovery {
            selectedCategoryDetail = sleepDetail
        }
    }

    private func fetchHistory(days: Int) async -> HealthHistory? {
        // 本地优先：无自建后端，不再拉取远端历史；压力矩阵以 HealthKit 实时估算为主。
        nil
    }

    private func fetchHourlyStressInputs(for range: TrendsRange, healthKit hk: HealthKitManager) async -> [TimeSeriesPointDouble] {
        let hrvPoints: [TimeSeriesPointDouble]
        let hrPoints: [TimeSeriesPointDouble]
        let rhrPoints: [TimeSeriesPointDouble]

        if range.isIntraday {
            hrvPoints = (try? await hk.fetchHourlyStatisticsForToday(
                quantityIdentifier: .heartRateVariabilitySDNN,
                unit: HKUnit.secondUnit(with: .milli),
                options: .discreteAverage
            )) ?? []
            hrPoints = (try? await hk.fetchHourlyStatisticsForToday(
                quantityIdentifier: .heartRate,
                unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
                options: .discreteAverage
            )) ?? []
            rhrPoints = (try? await hk.fetchHourlyStatisticsForToday(
                quantityIdentifier: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
                options: .discreteAverage
            )) ?? []
        } else {
            let start = range.startDate
            let end = Date()
            hrvPoints = (try? await hk.fetchHourlyStatistics(
                quantityIdentifier: .heartRateVariabilitySDNN,
                unit: HKUnit.secondUnit(with: .milli),
                options: .discreteAverage,
                startDate: start,
                endDate: end
            )) ?? []
            hrPoints = (try? await hk.fetchHourlyStatistics(
                quantityIdentifier: .heartRate,
                unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
                options: .discreteAverage,
                startDate: start,
                endDate: end
            )) ?? []
            rhrPoints = (try? await hk.fetchHourlyStatistics(
                quantityIdentifier: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
                options: .discreteAverage,
                startDate: start,
                endDate: end
            )) ?? []
        }

        return PressureMatrixMath.estimateStressSeriesByTimestamp(
            hrv: hrvPoints,
            heartRate: hrPoints,
            restingHeartRate: rhrPoints
        )
    }

    private func fetchInsightData() async -> InsightData? {
        // 本地优先：无自建后端，睡眠洞察由本机分析生成。
        nil
    }

    private func mergeSleepInsight(detail: TrendCategoryDetailModel, remote: InsightData?) -> TrendCategoryDetailModel? {
        guard detail.category == .sleepRecovery, let local = detail.sleepAIInsight else { return nil }
        guard let remote, isSleepRelevant(remote) else { return detail }

        let merged = SleepTrendAIInsightModel(
            summary: local.summary,
            observations: Array((local.observations + [remote.reason]).filter { !$0.isEmpty }.prefix(3)),
            guidance: trimmedInsightSentence(remote.analysis) ?? local.guidance
        )

        return TrendCategoryDetailModel(
            category: detail.category,
            headerSummary: detail.headerSummary,
            metrics: detail.metrics,
            status: detail.status,
            sleepStages: detail.sleepStages,
            sleepClinicalSummary: detail.sleepClinicalSummary,
            sleepAIInsight: merged,
            sleepCompositeScores: detail.sleepCompositeScores,
            sleepNightSummaries: detail.sleepNightSummaries,
            sleepCoreMetrics: detail.sleepCoreMetrics,
            sleepRecoveryMetrics: detail.sleepRecoveryMetrics,
            genericAIInsight: detail.genericAIInsight,
            mobilityAIInsight: detail.mobilityAIInsight,
            reproductiveDetail: detail.reproductiveDetail,
            heartECGSummary: detail.heartECGSummary,
            heartECGRecords: detail.heartECGRecords,
            heartClinicalMonitorSummary: detail.heartClinicalMonitorSummary
        )
    }

    private func isSleepRelevant(_ insight: InsightData) -> Bool {
        let text = "\(insight.analysis) \(insight.reason)"
        let keywords = ["睡眠", "睡眠恢复", "恢复", "睡眠评分", "睡眠 HRV", "夜间心率", "呼吸频率", "节律"]
        return keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func trimmedInsightSentence(_ text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.count <= 42 { return cleaned }
        return String(cleaned.prefix(42)) + "…"
    }
}
