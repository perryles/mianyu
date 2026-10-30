/// CareAdherenceView 展示照护任务的完成率统计图表。
///
/// 基于 CareTaskEngine 的 adherence 数据，以图表展示：
/// - 连续数周的任务完成趋势
/// - 支持按模块筛选（服药/康复/习惯/全部）
/// - 各任务完成率排行
///
/// 使用 SwiftUI Charts 框架，与现有 Trends 模块风格一致。

import SwiftUI
import Charts

struct CareAdherenceView: View {
    @State private var selectedCategory: CareTaskCategory?
    @State private var weeks: Int = 4
    @State private var referenceDate: Date = Date()
    @State private var refreshToken = UUID()

    private var weeklyData: [CareWeeklyAdherence] {
        CareTaskEngine.shared.weeklyAdherence(weeks: weeks, category: selectedCategory, referenceDate: referenceDate)
    }

    private var overallSummary: CareAdherenceSummary {
        CareTaskEngine.shared.adherenceSummary(days: weeks * 7, category: selectedCategory, referenceDate: referenceDate)
    }

    private var taskBreakdown: [CareAdherenceBreakdown] {
        CareAdherenceCalculator.breakdownByTask(days: weeks * 7, category: selectedCategory, referenceDate: referenceDate)
    }

    private var categoryBreakdown: [CareAdherenceBreakdown] {
        CareAdherenceCalculator.breakdownByCategory(days: weeks * 7, referenceDate: referenceDate)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                overallCard
                categoryFilter
                weeklyChartCard
                categoryBreakdownCard
                taskBreakdownCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "完成率统计"))
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            referenceDate = Date()
            refreshToken = UUID()
        }
        .id(refreshToken)
    }

    // MARK: - 总览

    @ViewBuilder
    private var overallCard: some View {
        BBCard(style: .hero, tint: overallTint) {
            VStack(spacing: 12) {
                Text(String(localized: "总完成率"))
                    .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.15), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.02, overallSummary.adherenceRate)))
                        .stroke(overallTint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(overallSummary.formattedAdherence)
                            .font(.appSystem(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("\(overallSummary.completedEvents)/\(overallSummary.totalEvents)")
                            .font(.appSystem(size: 13, weight: .medium))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                .frame(width: 120, height: 120)

                HStack(spacing: 16) {
                    statItem(String(localized: "已完成"), value: "\(overallSummary.completedEvents)", color: .green)
                    statItem(String(localized: "待补记"), value: "\(overallSummary.overdueEvents)", color: .red)
                    statItem(String(localized: "已跳过"), value: "\(overallSummary.skippedEvents)", color: .gray)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var overallTint: Color {
        if overallSummary.adherenceRate >= 0.8 { return .green }
        if overallSummary.adherenceRate >= 0.5 { return .orange }
        return .red
    }

    @ViewBuilder
    private func statItem(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.appSystem(size: 11, weight: .medium))
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    // MARK: - 分类筛选

    @ViewBuilder
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: String(localized: "全部"), category: nil)
                ForEach(CareTaskCategory.allCases, id: \.self) { category in
                    filterChip(label: category.title, category: category)
                }
            }
        }
    }

    @ViewBuilder
    private func filterChip(label: String, category: CareTaskCategory?) -> some View {
        let isSelected = selectedCategory == category
        let chipColor = category?.accentColorName == "orange" ? Color.orange :
                        category?.accentColorName == "blue" ? Color.blue :
                        category?.accentColorName == "green" ? Color.green :
                        category?.accentColorName == "purple" ? Color.purple : Theme.Colors.mintGreen

        Text(label)
            .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? chipColor : Color.gray.opacity(0.12))
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedCategory = category
                }
            }
    }

    // MARK: - 周趋势图

    @ViewBuilder
    private var weeklyChartCard: some View {
        BBTitledCard(
            title: String(localized: "周度趋势"),
            subtitle: String(localized: "最近 \(weeks) 周完成率"),
            systemImage: "chart.bar.fill",
            tint: Theme.Colors.mintGreen
        ) {
            if weeklyData.isEmpty {
                Text(String(localized: "暂无数据"))
                    .font(.appSystem(size: 14))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else {
                Chart(weeklyData) { item in
                    BarMark(
                        x: .value(String(localized: "周"), item.weekLabel),
                        y: .value(String(localized: "完成率"), item.adherenceRate * 100)
                    )
                    .foregroundStyle(barColor(rate: item.adherenceRate))
                    .cornerRadius(4)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let num = value.as(Double.self) {
                                Text("\(Int(num))%")
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .font(.appSystem(size: 10, weight: .medium))
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - 分类明细

    @ViewBuilder
    private var categoryBreakdownCard: some View {
        if selectedCategory == nil {
            BBTitledCard(
                title: String(localized: "模块完成率"),
                systemImage: "square.grid.2x2.fill",
                tint: Theme.Colors.mintGreen
            ) {
                VStack(spacing: 10) {
                    ForEach(categoryBreakdown) { item in
                        categoryBreakdownRow(item)
                    }
                    if categoryBreakdown.isEmpty {
                        Text(String(localized: "暂无数据"))
                            .font(.appSystem(size: 14))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .padding(.vertical, 20)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func categoryBreakdownRow(_ item: CareAdherenceBreakdown) -> some View {
        let color = categoryColor(item.category)
        HStack(spacing: 10) {
            Image(systemName: item.category.symbol)
                .font(.appSystem(size: 16))
                .foregroundColor(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                ProgressView(value: item.adherenceRate)
                    .tint(color)
                    .frame(height: 6)
            }

            Text(item.formattedAdherence)
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .frame(width: 48, alignment: .trailing)
        }
    }

    // MARK: - 任务明细

    @ViewBuilder
    private var taskBreakdownCard: some View {
        BBTitledCard(
            title: String(localized: "任务明细"),
            subtitle: String(localized: "按任务查看完成情况"),
            systemImage: "list.bullet.rectangle.portrait.fill",
            tint: Theme.Colors.mintGreen
        ) {
            if taskBreakdown.isEmpty {
                Text(String(localized: "暂无任务记录"))
                    .font(.appSystem(size: 14))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(taskBreakdown) { item in
                        taskBreakdownRow(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func taskBreakdownRow(_ item: CareAdherenceBreakdown) -> some View {
        let color = categoryColor(item.category)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                HStack(spacing: 8) {
                    Text("\(item.completedEvents)/\(item.totalEvents)")
                        .font(.appSystem(size: 11, weight: .medium))
                        .foregroundColor(Theme.Colors.textTertiary)

                    if item.currentStreak > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.appSystem(size: 9))
                            Text("\(item.currentStreak)\(String(localized: "天"))")
                                .font(.appSystem(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.orange)
                    }
                }
            }

            Spacer(minLength: 0)

            Text(item.formattedAdherence)
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 辅助方法

    private func barColor(rate: Double) -> Color {
        if rate >= 0.8 { return .green }
        if rate >= 0.5 { return .orange }
        return .red
    }

    private func categoryColor(_ category: CareTaskCategory) -> Color {
        switch category {
        case .medication: return .orange
        case .rehabilitation: return .blue
        case .habit: return .green
        case .symptom: return .purple
        }
    }
}
