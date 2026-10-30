/// ProfileHeatmapCardView 由 ProfileView 调用，作为「活力热力图」卡片。
/// 展示近 16 周 (7×16 网格) 的健康活跃度，采用 GitHub 贡献图风格。

import SwiftUI

/// 活力热力图卡片，展示近 16 周的健康活跃度网格。
struct ProfileHeatmapCardView: View {
    @Bindable var viewModel: ProfileHeatmapViewModel
    let reportDays: [ReportDaySummary]
    let isLoading: Bool
    @Binding var showingVitalityInfo: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 入场动画触发
    @State private var hasAppeared = false

    /// 图表配色统一引用应用主题色（Theme.Colors / BBChartStyle），跟随应用设置。
    private let vitalityFill = Theme.Colors.mintGreen
    private let vitalityLabel = Theme.Colors.mintGreen

    private var displayDays: [ProfileHeatmapDay] {
        viewModel.computeDisplayDays(count: 112, reportDays: reportDays)
    }

    /// 计算连续活跃天数（从今天往回数）
    private var currentStreak: Int {
        let days = displayDays
        var streak = 0
        for day in days.reversed() {
            if day.hasActivity {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    var body: some View {
        let days = displayDays
        let selectedDay = viewModel.selectedDayID.flatMap { selectedID in
            days.first(where: { $0.id == selectedID })
        }

        VStack(alignment: .leading, spacing: 14) {
            headerRow
            gridView(days, selectedDayID: selectedDay?.id)
            legendBar
            if let selectedDay {
                selectionRow(selectedDay)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder.opacity(0.8), lineWidth: 1)
        )
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    hasAppeared = true
                }
            }
        }
    }

    // MARK: - 标题区

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("活力热力图")
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Button {
                        showingVitalityInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("活力指数说明")
                }

                Text("最近 16 周的健康活跃度")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer(minLength: 0)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                streakBadge
            }
        }
    }

    private var streakBadge: some View {
        let streak = currentStreak
        return HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(vitalityLabel)
            Text("连续 \(streak) 天")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(vitalityLabel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            vitalityFill.opacity(0.10),
            in: Capsule()
        )
        .accessibilityLabel("连续活跃 \(streak) 天")
    }

    // MARK: - 网格（16 列 × 7 行）

    private func gridView(
        _ days: [ProfileHeatmapDay],
        selectedDayID: TimeInterval?
    ) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 16)

        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                cellView(day, index: index, isSelected: selectedDayID == day.id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("活力热力图，连续活跃 \(currentStreak) 天")
    }

    private func cellView(
        _ day: ProfileHeatmapDay,
        index: Int,
        isSelected: Bool
    ) -> some View {
        let isToday = Calendar.current.isDateInToday(day.date)
        let isFuture = day.date > Date()
        let column = index / 7 // 0-15, 用于波浪动画延迟

        return Button {
            viewModel.selectedDayID = day.id
        } label: {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(cellColor(for: day))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(
                            isToday ? vitalityLabel : Color.clear,
                            lineWidth: isToday ? 2 : 0
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(
                            isSelected ? BBChartStyle.selection : Color.clear,
                            lineWidth: isSelected ? 1.5 : 0
                        )
                )
                .opacity(isFuture ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        // 逐列波浪入场动画
        .opacity(hasAppeared || reduceMotion ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 8)
        .animation(
            reduceMotion
                ? .none
                : .easeOut(duration: 0.35).delay(Double(column) * 0.035),
            value: hasAppeared
        )
        .accessibilityLabel("\(accessibilityDate(day.date))，\(accessibilityValue(day))")
    }

    // MARK: - 图例栏

    private var legendBar: some View {
        HStack(spacing: 0) {
            Text("4 个月前")
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            Spacer()

            HStack(spacing: 4) {
                Text("少")
                    .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)

                ForEach([0.05, 0.1, 0.35, 0.6, 0.9], id: \.self) { opacity in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(vitalityFill.opacity(opacity * 0.8))
                        .frame(width: 10, height: 10)
                }

                Text("多")
                    .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer()

            Text("今天")
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.top, 2)
    }

    // MARK: - 选中项

    private func selectionRow(_ day: ProfileHeatmapDay) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(cellColor(for: day))
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(
                            Calendar.current.isDateInToday(day.date)
                                ? vitalityLabel
                                : Color.clear,
                            lineWidth: 1.5
                        )
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(accessibilityDate(day.date))
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(statusText(day))
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor(for: day))
                }

                Text(day.source.detailText(
                    healthMetricCount: day.healthMetricCount,
                    behaviorSignalCount: day.behaviorSignalCount
                ))
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Text(valueText(day))
                .font(.appSystem(size: 18, weight: .black, design: .rounded))
                .foregroundColor(accentColor(for: day))
                .monospacedDigit()
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BBChartStyle.grid)
                .frame(height: 1)
        }
    }

    // MARK: - 颜色映射（仅薄荷绿色板）

    private func cellColor(for day: ProfileHeatmapDay) -> Color {
        if let score = day.score {
            switch score {
            case 85...: return vitalityFill.opacity(0.72)
            case 70..<85: return vitalityFill.opacity(0.48)
            case 50..<70: return vitalityFill.opacity(0.26)
            default: return vitalityFill.opacity(0.08)
            }
        }
        if day.behaviorSignalCount > 0 {
            let opacity = 0.1 + Double(min(5, day.behaviorSignalCount)) * 0.05
            return vitalityFill.opacity(opacity * 0.8)
        }
        return vitalityFill.opacity(0.04)
    }

    private func accentColor(for day: ProfileHeatmapDay) -> Color {
        if day.score != nil || day.behaviorSignalCount > 0 {
            return vitalityLabel
        }
        return Theme.Colors.textTertiary
    }

    private func valueText(_ day: ProfileHeatmapDay) -> String {
        if let score = day.score { return "\(score)分" }
        if day.behaviorSignalCount > 0 { return "\(day.behaviorSignalCount)类" }
        return "--"
    }

    private func statusText(_ day: ProfileHeatmapDay) -> String {
        if day.source == .records {
            switch day.behaviorSignalCount {
            case 4...: return String(localized: "记录充足")
            case 2..<4: return String(localized: "持续记录")
            default: return String(localized: "已有记录")
            }
        }
        guard let score = day.score else { return String(localized: "暂无数据") }
        switch score {
        case 85...: return String(localized: "良好")
        case 70..<85: return String(localized: "稳定")
        case 50..<70: return String(localized: "波动")
        default: return String(localized: "承压")
        }
    }

    private func accessibilityValue(_ day: ProfileHeatmapDay) -> String {
        if let score = day.score {
            return String(localized: "健康活力 \(score) 分，\(statusText(day))，\(day.source.title)")
        }
        if day.behaviorSignalCount > 0 {
            return String(localized: "行为记录信号 \(day.behaviorSignalCount) 类，无健康综合评分")
        }
        return String(localized: "暂无活力数据")
    }

    private func accessibilityDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }
}
