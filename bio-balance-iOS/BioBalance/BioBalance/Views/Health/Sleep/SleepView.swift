/// SleepView 由健康首页与今日页调用，作为「睡眠」模块主页。
/// 负责展示睡眠概览、阶段分析、环境检测与节律训练入口。

import SwiftUI
import Charts

/// 睡眠视图 由上级页面或路由调用，作为睡眠模块里的界面或内容组件。
/// 负责展示睡眠记录、恢复分析以及睡眠与其他指标的关联。
struct SleepView: View {
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    let showsDismissButton: Bool
    @State private var viewModel = SleepViewModel()
    @Environment(\.dismiss) private var dismiss
    @GestureState private var horizontalDragOffset: CGFloat = 0

    init(showsDismissButton: Bool = false) {
        self.showsDismissButton = showsDismissButton
    }
    
    var body: some View {
        ZStack {
            sleepPageBackground

            AdaptivePageScrollView(style: .reading, topPadding: Theme.Layout.padding, bottomPadding: Theme.Layout.padding) {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: adaptiveLayout.usesExpandedLayout ? 24 : 20) {
                        sleepHeroCard
                        sleepFocusCard

                        if viewModel.lateNightRecoverySummary.isActive {
                            sleepSectionTitle("恢复计划", subtitle: "根据昨夜作息生成，先完成最容易的一项")
                            LateNightRecoveryCard(
                                summary: viewModel.lateNightRecoverySummary,
                                onStartRecovery: {
                                    viewModel.startRhythmProtectionPlan(mode: .lateNightRecovery)
                                }
                            )
                        }

                        if let data = viewModel.sleepData {
                            if data.duration_minutes > 0 {
                                if !viewModel.sleepIntervals.isEmpty {
                                    sleepSessionsCard
                                }

                                sleepStructureSection(data)
                            } else {
                                emptyStateCard
                            }
                        } else {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .tint(Theme.Colors.textPrimary)
                                Text("正在同步睡眠数据")
                                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }

                        sleepSectionTitle("睡眠环境", subtitle: "用连续记录判断环境因素是否真的影响恢复")

                        if let trendSummary = viewModel.sleepEnvironmentTrendSummary {
                            SleepEnvironmentTrendCard(
                                summary: trendSummary,
                                onOpenChecklist: {
                                    withAnimation(.easeInOut(duration: 0.4)) {
                                        proxy.scrollTo("environmentChecklist", anchor: .center)
                                    }
                                }
                            )
                        }

                        SleepEnvironmentChecklistCard(viewModel: viewModel)
                            .id("environmentChecklist")
                    }
                }
            }
        }
        .healthDetailNavigation(title: "睡眠")
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    HealthNavigationDismissButton {
                        dismiss()
                    }
                }
            }
        }
        .offset(x: showsDismissButton ? max(0, horizontalDragOffset) : 0)
        .gesture(showsDismissButton ? swipeToDismissGesture : nil)
        .onAppear {
            viewModel.loadData()
        }
    }

    private var swipeToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($horizontalDragOffset) { value, state, _ in
                guard value.startLocation.x <= 36 else { return }
                guard value.translation.width > 0 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard value.startLocation.x <= 36 else { return }
                guard value.translation.width > 90 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dismiss()
            }
    }

    private var sleepPageBackground: some View {
        Theme.Colors.pageBackground
            .ignoresSafeArea()
    }

    private var sleepHeroCard: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 190, height: 190)
                .offset(x: 58, y: -72)

            Image(systemName: "moon.stars.fill")
                .font(.appSystem(size: 48, weight: .regular))
                .foregroundColor(Color(hex: "DAD9FF").opacity(0.82))
                .padding(.top, 22)
                .padding(.trailing, 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("昨夜睡眠")
                        .font(.appSystem(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.onAccent)
                    Text(heroSubtitle)
                        .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.onAccent.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 62)
                }

                Spacer(minLength: 12)
            }

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.appSystem(size: 11, weight: .bold))
                    Text(heroBadgeText)
                        .font(.appSystem(size: 11, weight: .black, design: .rounded))
                }
                .foregroundColor(Color(hex: "F4F1FF"))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Theme.Colors.surface.opacity(0.13), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))

                HStack(spacing: 10) {
                heroMetric(
                    title: "时长",
                    value: heroDurationValue,
                    tint: Color(hex: "5E5CE6")
                )
                heroMetric(
                    title: "评分",
                    value: heroScoreValue,
                    tint: Color(hex: "FF9F0A")
                )
                heroMetric(
                    title: "目标完成",
                    value: heroGoalValue,
                    tint: Theme.Colors.mintGreen
                )
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "25245A"), Color(hex: "48458E"), Color(hex: "6D68B5")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: Color(hex: "302D71").opacity(0.22), radius: 22, y: 12)
    }

    private var sleepFocusCard: some View {
        let focus = viewModel.pageFocus
        let tint = focusTint(focus.tone)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label("昨夜重点", systemImage: "scope")
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(tint)
                Spacer(minLength: 8)
                Text(focus.badgeText)
                    .font(.appSystem(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.12), in: Capsule())
            }

            Text(focus.title)
                .font(.appSystem(size: 22, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            sleepFocusLine(label: "判断依据", text: focus.reason, symbol: "text.magnifyingglass", tint: tint)
            sleepFocusLine(label: "连续趋势", text: focus.context, symbol: "chart.line.uptrend.xyaxis", tint: tint)
            sleepFocusLine(label: "今晚行动", text: focus.action, symbol: "moon.stars.fill", tint: tint)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.13), Color.white.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func sleepFocusLine(
        label: String,
        text: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.appSystem(size: 12, weight: .black))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.appSystem(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(tint)
                Text(text)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func focusTint(_ tone: SleepPageFocusTone) -> Color {
        switch tone {
        case .building: return Color(hex: "8C7A62")
        case .attention: return Color(hex: "C18124")
        case .recovery: return Color(hex: "D35F53")
        case .stable: return Color(hex: "318B68")
        }
    }

    private func sleepSectionTitle(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 21, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(subtitle)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "moon.zzz")
                .font(.appSystem(size: 56, weight: .regular))
                .foregroundColor(Color(hex: "5E5CE6"))
            Text("暂无睡眠数据")
                .font(.appSystem(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text("请佩戴 Apple Watch 睡觉或手动录入数据")
                .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 24)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        }
    }

    private var sleepSessionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("今日睡眠时段")
                    .font(.appSystem(.title3, design: .rounded).bold())
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Text("\(viewModel.sleepIntervals.count) 段")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "5E5CE6"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: "5E5CE6").opacity(0.1), in: Capsule())
            }

            ForEach(Array(viewModel.sleepIntervals.enumerated()), id: \.offset) { index, interval in
                if index > 0 {
                    Divider().overlay(Theme.Colors.surfaceBorder)
                }

                HStack(spacing: 12) {
                    Image(systemName: isDaytimeSleep(interval) ? "sun.max.fill" : "moon.stars.fill")
                        .font(.appSystem(size: 16, weight: .semibold))
                        .foregroundColor(isDaytimeSleep(interval) ? Color(hex: "FF9F0A") : Color(hex: "5E5CE6"))
                        .frame(width: 36, height: 36)
                        .background(
                            (isDaytimeSleep(interval) ? Color(hex: "FF9F0A") : Color(hex: "5E5CE6"))
                                .opacity(0.1),
                            in: Circle()
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isDaytimeSleep(interval) ? String(localized: "午睡") : String(localized: "夜间睡眠"))
                            .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("\(sleepTimeText(interval.start)) – \(sleepTimeText(interval.end))")
                            .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Spacer()

                    Text(sleepDurationText(interval))
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                }
            }
        }
        .padding(20)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private func isDaytimeSleep(_ interval: SleepInterval) -> Bool {
        let midpoint = interval.start.addingTimeInterval(interval.end.timeIntervalSince(interval.start) / 2)
        let hour = Calendar.current.component(.hour, from: midpoint)
        return (9..<19).contains(hour)
    }

    private func sleepTimeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func sleepDurationText(_ interval: SleepInterval) -> String {
        let minutes = max(0, Int(interval.end.timeIntervalSince(interval.start) / 60))
        if minutes < 60 { return String(localized: "\(minutes) 分钟") }
        let remainder = minutes % 60
        return remainder == 0
            ? String(localized: "\(minutes / 60) 小时")
            : String(localized: "\(minutes / 60) 小时 \(remainder) 分钟")
    }

    private func sleepStructureSection(_ data: SleepData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sleepSectionTitle("结构与恢复", subtitle: "先看总时长，再用阶段和夜间信号补充解释")

            SleepRecordCard(
                deepSleepPercentage: calculatePercentage(
                    for: ["Deep", "深睡"],
                    stages: data.stages,
                    total: data.duration_minutes
                ),
                remSleepPercentage: calculatePercentage(
                    for: ["REM", "快速眼动"],
                    stages: data.stages,
                    total: data.duration_minutes
                ),
                avgHeartRate: data.avg_heart_rate
                    ?? viewModel.overnightAverageHeartRate.map { Int($0.rounded()) },
                avgRespirationRate: data.avg_respiration_rate
                    ?? viewModel.nightlyRespirationRate
            )

            let stages = normalizedStages(from: data.stages)
            if !stages.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("各阶段时长")
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("单晚结构只用于观察，连续趋势比一次比例更有参考价值")
                            .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Chart(stages, id: \.id) { stage in
                        BarMark(
                            x: .value("阶段", stage.name),
                            y: .value("时长", stage.duration)
                        )
                        .foregroundStyle(stage.color.gradient)
                        .cornerRadius(7)
                        .annotation(position: .top) {
                            Text("\(stage.duration)分")
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                    .frame(height: 190)
                    .chartLegend(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .automatic) {
                            AxisValueLabel()
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) {
                            AxisGridLine()
                                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.16))
                            AxisValueLabel()
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
                .padding(18)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                        .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
                }
            }
        }
    }

    private var heroSubtitle: String {
        guard let data = viewModel.sleepData else { return String(localized: "正在整理昨夜恢复状态和睡眠节奏。") }
        guard data.duration_minutes > 0 else { return String(localized: "昨夜暂无记录，等你下一次完整入睡后再来看看。") }
        if data.sleep_score >= 85 { return String(localized: "恢复状态不错，继续保持当前节奏。") }
        if data.sleep_score >= 70 { return String(localized: "整体睡得还可以，今天注意补足恢复。") }
        return String(localized: "恢复还不够，今晚适合早点收尾、减少刺激。")
    }

    private var heroBadgeText: String {
        guard let data = viewModel.sleepData, data.duration_minutes > 0 else { return String(localized: "等待记录") }
        return data.sleep_score >= 80 ? String(localized: "恢复良好") : String(localized: "继续调整")
    }

    private var heroDurationValue: String {
        guard let data = viewModel.sleepData, data.duration_minutes > 0 else { return "--" }
        return "\(data.duration_minutes / 60)h \(data.duration_minutes % 60)m"
    }

    private var heroScoreValue: String {
        guard let data = viewModel.sleepData, data.sleep_score > 0 else { return "--" }
        return "\(data.sleep_score)"
    }

    private var heroGoalValue: String {
        guard let data = viewModel.sleepData, data.duration_minutes > 0 else { return "--" }
        let progress = min(1, Double(data.duration_minutes) / Double(max(viewModel.sleepGoalMinutes, 1)))
        return "\(Int((progress * 100).rounded()))%"
    }

    private func heroMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.onAccent.opacity(0.66))
            ZStack(alignment: .leading) {
                Text("--")
                    .font(.appSystem(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.onAccent)
                    .opacity(value == "--" ? 1 : 0)
                Text(value == "--" ? "" : value)
                    .font(.appSystem(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.onAccent)
                    .opacity(value == "--" ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.Colors.surface.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.45), lineWidth: 1)
        }
    }

    private func calculatePercentage(for stageNames: [String], stages: [SleepStage], total: Int) -> Double {
        guard total > 0 else { return 0.0 }
        let stageDuration = stages
            .filter { stageNames.contains($0.stage) }
            .reduce(0) { $0 + max($1.duration, 0) }
        return Double(stageDuration) / Double(total)
    }

    private func normalizedStages(from stages: [SleepStage]) -> [SleepStageChartItem] {
        let grouped = Dictionary(grouping: stages) { normalizeStageName($0.stage) }
        let order = ["清醒", "浅睡", "深睡", "快速眼动"]

        return grouped.map { key, values in
            SleepStageChartItem(
                name: key,
                duration: values.reduce(0) { $0 + max($1.duration, 0) },
                color: stageDotColor(key)
            )
        }
        .filter { $0.duration > 0 }
        .sorted { lhs, rhs in
            (order.firstIndex(of: lhs.name) ?? .max) < (order.firstIndex(of: rhs.name) ?? .max)
        }
    }

    private func normalizeStageName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "awake", "清醒":
            return "清醒"
        case "core", "light", "浅睡":
            return "浅睡"
        case "deep", "深睡":
            return "深睡"
        case "rem", "快速眼动":
            return "快速眼动"
        default:
            return raw
        }
    }

    private func stageDotColor(_ stage: String) -> Color {
        switch stage {
        case "清醒": return Theme.Colors.textTertiary.opacity(0.45)
        case "快速眼动": return Color(hex: "007F79")
        case "深睡": return Theme.Colors.mintGreen
        default: return Color(hex: "5E5CE6")
        }
    }

}

private struct SleepStageChartItem: Identifiable {
    let name: String
    let duration: Int
    let color: Color

    var id: String { name }
}
