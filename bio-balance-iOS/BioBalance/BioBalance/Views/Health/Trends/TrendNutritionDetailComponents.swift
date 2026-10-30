/// NutritionDetailContent 作为趋势模块的支撑类型，负责渲染「营养摄入」详情页。
/// 负责展示饮食记录列表、图表与餐次关联。

import Charts
import SwiftUI


/// 营养详情内容结构体 作为趋势模块里的辅助类型。
/// 负责趋势分析展示。用于趋势页面的“营养摄入”详情页。
struct NutritionDetailContent: View {
    let detail: TrendCategoryDetailModel
    let range: TrendsRange
    var isStaticForExport: Bool = false

    @State private var mealRecords: [MealRecognitionRecord]
    @State private var selectedChartDate: Date?

    private let mealStore = DrinkExperienceStore.shared
    private let mealAccent = Color(hex: "E57B3C")

    init(
        detail: TrendCategoryDetailModel,
        range: TrendsRange,
        isStaticForExport: Bool = false
    ) {
        self.detail = detail
        self.range = range
        self.isStaticForExport = isStaticForExport
        self.mealRecords = DrinkExperienceStore.shared.allMealRecords()
    }

    private var hydrationMetrics: [TrendCategoryMetricModel] {
        ["饮水量", "饮水达标率"].compactMap { title in
            detail.metrics.first(where: { $0.title == title })
        }
    }

    private var stimulationMetrics: [TrendCategoryMetricModel] {
        ["咖啡因残留"].compactMap { title in
            detail.metrics.first(where: { $0.title == title })
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            mealIntakeSection

            nutritionSection(
                title: "补水节奏",
                subtitle: "把饮水量和达标率放在一起看，更容易判断最近补水节奏有没有连续形成。",
                metrics: hydrationMetrics
            )

            nutritionSection(
                title: "刺激输入",
                subtitle: "把咖啡因残留单独看，更适合判断刺激输入是不是还在持续影响恢复与清醒节律。",
                metrics: stimulationMetrics
            )
        }
        .onAppear(perform: reloadMealRecords)
        .onChange(of: range) { _, _ in
            selectedChartDate = nil
            reloadMealRecords()
        }
        .task {
            if await mealStore.synchronizePrivateCloud() {
                reloadMealRecords()
            }
        }
    }

    private var mealIntakeSection: some View {
        VStack(spacing: 14) {
            mealTrendCard
            mealCompositionCard
            mealMaintenanceEntry
        }
    }

    private var mealTrendCard: some View {
        BBChartCard(
            title: range == .day ? "今日餐食时间线" : "餐食摄入趋势",
            subtitle: mealWindowSummary,
            isEmpty: windowMealRecords.isEmpty,
            emptyTitle: "当前窗口还没有餐食记录",
            emptySystemImage: "fork.knife.circle",
            systemImage: "fork.knife",
            tint: mealAccent
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    BBChartMetricPill(
                        title: "已记录",
                        value: "\(windowMealRecords.count) 餐",
                        tint: mealAccent
                    )
                    BBChartMetricPill(
                        title: range == .day ? "今日热量" : "记录日均",
                        value: "\(range == .day ? totalCalories : averageDailyCalories) kcal",
                        tint: Color(hex: "287A58")
                    )
                    BBChartMetricPill(
                        title: "记录天数",
                        value: "\(mealDayCount) 天",
                        tint: Color(hex: "5DADE2")
                    )
                }

                interactiveMealChart

                if let selectedMealSummary {
                    BBChartSelectionReadout(
                        title: selectedMealSummary.title,
                        value: "\(selectedMealSummary.calories) kcal",
                        detail: "\(selectedMealSummary.count) 餐 · \(selectedMealSummary.foods)",
                        tint: mealAccent,
                        systemImage: "fork.knife"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var interactiveMealChart: some View {
        if isStaticForExport {
            mealChart
        } else {
            mealChart
                .chartXSelection(value: $selectedChartDate)
        }
    }

    private var mealChart: some View {
        Chart(mealTrendPoints) { point in
            BarMark(
                x: .value("时间", point.date, unit: range == .day ? .hour : .day),
                y: .value("热量", point.calories)
            )
            .foregroundStyle((range == .day ? mealSlotTint(point.slot) : mealAccent).gradient)
            .cornerRadius(5)
        }
        .chartLegend(.hidden)
        .chartXAxis {
            if range == .day {
                AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                    AxisGridLine().foregroundStyle(BBChartStyle.grid.opacity(0.55))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                        }
                    }
                    .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 5)) { value in
                    AxisGridLine().foregroundStyle(BBChartStyle.grid.opacity(0.55))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.month(.defaultDigits).day()))
                        }
                    }
                    .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(BBChartStyle.grid.opacity(0.62))
                AxisValueLabel {
                    if let calories = value.as(Double.self) {
                        Text("\(Int(calories.rounded()))")
                    }
                }
                .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartXScale(domain: range.dateDomain)
        .chartPlotStyle { plotArea in
            plotArea
                .background(BBChartStyle.plotGradient(tint: mealAccent))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(height: range == .day ? 190 : 210)
        .accessibilityLabel(range == .day ? "今日餐食热量时间线" : "餐食热量趋势")
    }

    private var mealCompositionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            BBChartHeader(
                title: "餐次构成",
                subtitle: compositionSummary,
                systemImage: "chart.pie.fill",
                tint: Color(hex: "287A58")
            )

            if windowMealRecords.isEmpty {
                Text("完成一次餐食识别或手动录入后，这里会按早餐、午餐和晚餐显示真实构成。")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                    .padding(14)
                    .bbChartPlotSurface(tint: Color(hex: "287A58"), cornerRadius: 16)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) {
                        mealCompositionChart
                        mealCompositionLegend
                    }
                    VStack(spacing: 14) {
                        mealCompositionChart
                        mealCompositionLegend
                    }
                }

                if !frequentFoods.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前窗口常见食物")
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)

                        FlexibleTagLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                            ForEach(frequentFoods, id: \.name) { item in
                                Text("\(item.name) · \(item.count)")
                                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "4D5B56"))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Color(hex: "E5F5EA"), in: Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .bbChartSurface(tint: Color(hex: "287A58"), cornerRadius: 26)
    }

    private var mealCompositionChart: some View {
        Chart(mealSlotBreakdown) { item in
            SectorMark(
                angle: .value("热量", max(item.calories, 1)),
                innerRadius: .ratio(0.58),
                angularInset: 2
            )
            .cornerRadius(4)
            .foregroundStyle(mealSlotTint(item.slot))
        }
        .chartLegend(.hidden)
        .frame(width: 146, height: 146)
        .overlay {
            VStack(spacing: 2) {
                Text("\(totalCalories)")
                    .font(.appSystem(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("kcal")
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .accessibilityLabel("餐次热量构成")
    }

    private var mealCompositionLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(mealSlotBreakdown) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(mealSlotTint(item.slot))
                        .frame(width: 8, height: 8)
                    Text(item.slot.title)
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Spacer(minLength: 12)
                    Text("\(item.count) 餐 · \(item.calories) kcal")
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var mealMaintenanceEntry: some View {
        if isStaticForExport {
            mealMaintenanceLabel
        } else {
            NavigationLink {
                MealRecognitionHubView()
            } label: {
                mealMaintenanceLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var mealMaintenanceLabel: some View {
        HStack(spacing: 13) {
            Image(systemName: "camera.viewfinder")
                .font(.appSystem(size: 18, weight: .black))
                .foregroundColor(mealAccent)
                .frame(width: 38, height: 38)
                .background(mealAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("餐食识别与记录")
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(windowMealRecords.isEmpty ? "添加第一餐" : "查看或补充餐食资料")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 8)

            if !isStaticForExport {
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .black))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(15)
        .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(mealAccent.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func nutritionSection(
        title: String,
        subtitle: String,
        metrics: [TrendCategoryMetricModel]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !metrics.isEmpty {
                VStack(spacing: 14) {
                    ForEach(metrics) { metric in
                        TrendCategoryMetricCard(
                            metric: metric,
                            range: range,
                            category: detail.category,
                            isStaticForExport: isStaticForExport
                        )
                    }
                }
            } else {
                TrendMetricEmptyStateView(
                    status: detail.status,
                    title: title,
                    message: "当前区间里这组摄入指标还没有形成稳定记录，继续记录补水和咖啡因后这里会自动补成连续趋势。",
                    accent: detail.category.accentColor
                )
            }
        }
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var windowMealRecords: [MealRecognitionRecord] {
        mealRecords
            .filter { $0.capturedAt >= range.startDate && $0.capturedAt <= Date() }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private var totalCalories: Int {
        windowMealRecords.reduce(0) { $0 + max(0, $1.estimatedCalories) }
    }

    private var mealDayCount: Int {
        Set(windowMealRecords.map { Calendar.current.startOfDay(for: $0.capturedAt) }).count
    }

    private var averageDailyCalories: Int {
        guard mealDayCount > 0 else { return 0 }
        return Int((Double(totalCalories) / Double(mealDayCount)).rounded())
    }

    private var mealTrendPoints: [MealNutritionTrendPoint] {
        if range == .day {
            return windowMealRecords.map {
                MealNutritionTrendPoint(
                    date: $0.capturedAt,
                    slot: $0.mealSlot,
                    calories: max(0, $0.estimatedCalories)
                )
            }
        }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: windowMealRecords) {
            calendar.startOfDay(for: $0.capturedAt)
        }
        return grouped.map { day, records in
            MealNutritionTrendPoint(
                date: day,
                slot: records.first?.mealSlot ?? .breakfast,
                calories: records.reduce(0) { $0 + max(0, $1.estimatedCalories) }
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var mealSlotBreakdown: [MealNutritionSlotBreakdown] {
        MealSlot.allCases.compactMap { slot in
            let records = windowMealRecords.filter { $0.mealSlot == slot }
            guard !records.isEmpty else { return nil }
            return MealNutritionSlotBreakdown(
                slot: slot,
                calories: records.reduce(0) { $0 + max(0, $1.estimatedCalories) },
                count: records.count
            )
        }
    }

    private var frequentFoods: [(name: String, count: Int)] {
        Dictionary(grouping: windowMealRecords.flatMap(\.recognizedFoods), by: { $0.name })
            .map { (name: $0.key, count: $0.value.count) }
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                if $0.count == $1.count { return $0.name < $1.name }
                return $0.count > $1.count
            }
            .prefix(5)
            .map { $0 }
    }

    private var mealWindowSummary: String {
        guard !windowMealRecords.isEmpty else {
            return String(localized: "餐食识别记录会在这里按当前趋势窗口自动汇总。")
        }
        if range == .day {
            let slots = Set(windowMealRecords.map(\.mealSlot)).count
            return String(localized: "今天已记录 \(windowMealRecords.count) 餐、覆盖 \(slots) 个餐次，共 \(totalCalories) kcal。")
        }
        return String(localized: "当前窗口记录 \(windowMealRecords.count) 餐、覆盖 \(mealDayCount) 天，记录日平均 \(averageDailyCalories) kcal。")
    }

    private var compositionSummary: String {
        guard !windowMealRecords.isEmpty else { return "等待餐食识别记录" }
        let leading = mealSlotBreakdown.max { $0.calories < $1.calories }
        return leading.map { "\($0.slot.title)占当前窗口热量最多，\($0.calories) kcal。" } ?? mealWindowSummary
    }

    private var selectedMealSummary: MealNutritionSelectionSummary? {
        guard !windowMealRecords.isEmpty else { return nil }
        let targetDate = selectedChartDate ?? windowMealRecords.last?.capturedAt ?? Date()
        let calendar = Calendar.current

        let records: [MealRecognitionRecord]
        if range == .day {
            records = windowMealRecords
                .sorted { abs($0.capturedAt.timeIntervalSince(targetDate)) < abs($1.capturedAt.timeIntervalSince(targetDate)) }
                .prefix(1)
                .map { $0 }
        } else {
            records = windowMealRecords.filter { calendar.isDate($0.capturedAt, inSameDayAs: targetDate) }
        }
        guard !records.isEmpty else { return nil }

        let foods = records
            .flatMap(\.recognizedFoods)
            .map(\.name)
            .filter { !$0.isEmpty }
            .prefix(3)
            .joined(separator: "、")
        let title = range == .day
            ? "\(records[0].mealSlot.title) · \(records[0].capturedAt.formatted(.dateTime.hour().minute()))"
            : targetDate.formatted(.dateTime.month().day())
        return MealNutritionSelectionSummary(
            title: title,
            calories: records.reduce(0) { $0 + max(0, $1.estimatedCalories) },
            count: records.count,
            foods: foods.isEmpty ? "未填写食物明细" : foods
        )
    }

    private func mealSlotTint(_ slot: MealSlot) -> Color {
        switch slot {
        case .breakfast: return Color(hex: "F3A53B")
        case .lunch: return Color(hex: "287A58")
        case .dinner: return Color(hex: "6B83E8")
        case .snack: return Color(hex: "8B9D73")
        }
    }

    private func reloadMealRecords() {
        mealRecords = mealStore.allMealRecords()
    }
}

private struct MealNutritionTrendPoint: Identifiable {
    let date: Date
    let slot: MealSlot
    let calories: Int

    var id: String { "\(date.timeIntervalSince1970)-\(slot.rawValue)" }
}

private struct MealNutritionSlotBreakdown: Identifiable {
    let slot: MealSlot
    let calories: Int
    let count: Int

    var id: String { slot.rawValue }
}

private struct MealNutritionSelectionSummary {
    let title: String
    let calories: Int
    let count: Int
    let foods: String
}
