/// REMAnalysisView 由睡眠详情的「快速眼动」阶段卡调用。
/// 负责展示 REM 时长、深睡占比、睡眠阶段分布与趋势序列。

import SwiftUI
import Charts

/// 负责展示睡眠记录、恢复分析以及睡眠与其他指标的关联。
struct REMAnalysisView: View {
    @State private var stages: [SleepStage] = []
    @State private var sleepInterval: SleepInterval?
    @State private var sleepDurationSeries: [TimeSeriesPointDouble] = []
    @State private var isLoading = false

    private var remMinutes: Int {
        minutes(for: "REM")
    }

    private var deepMinutes: Int {
        minutes(for: "Deep")
    }

    private var awakeMinutes: Int {
        minutes(for: "Awake")
    }

    private var totalMinutes: Int {
        stages.map(\.duration).reduce(0, +)
    }

    private var remRatio: Double {
        guard totalMinutes > 0 else { return 0 }
        return Double(remMinutes) / Double(totalMinutes)
    }

    private var hasTimeline: Bool {
        SleepStageTimelineChart.hasRenderableData(stages)
    }

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: HealthDetailDesignSystem.sectionSpacing) {
                    heroCard
                    timelineCard
                    insightCard
                    trendCard
                    disclaimerCard
                }
                .padding(.horizontal, HealthDetailDesignSystem.pageHorizontalPadding)
                .padding(.top, HealthDetailDesignSystem.pageTopPadding)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("REM")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(alignment: .top, spacing: Theme.Spacing.small) {
                VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                    Text("REM 睡眠")
                        .font(Theme.Typography.pageTitle)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("快速眼动阶段和记忆整理、情绪恢复关系更紧。")
                        .font(Theme.Typography.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "5E5CE6"))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: "5E5CE6").opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }

            HStack(spacing: Theme.Spacing.small) {
                metric(title: "REM 时长", value: durationText(remMinutes), tint: Color(hex: "5E5CE6"))
                metric(title: "占比", value: remMinutes > 0 ? "\(Int((remRatio * 100).rounded()))%" : "--", tint: Color(hex: "007F79"))
                metric(title: "深睡配合", value: deepMinutes > 0 ? "\(deepMinutes)分" : "--", tint: Color(hex: "3240D3"))
            }
        }
        .healthDetailSurface()
    }

    private var ambientBackground: some View {
        VStack {
            HStack {
                Circle()
                    .fill(Color(hex: "5E5CE6").opacity(0.16))
                    .frame(width: 180, height: 180)
                    .blur(radius: 28)
                    .offset(x: -38, y: -38)
                Spacer()
                Circle()
                    .fill(Color(hex: "007F79").opacity(0.16))
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)
                    .offset(x: 30, y: -26)
            }
            Spacer()
        }
        .ignoresSafeArea()
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("昨夜阶段时间轴")
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(hasTimeline ? "和新睡眠详情页保持同一口径，统一使用四阶段专业时间轴与 0:00、06:00、12:00、18:00 x 轴。" : "当前还没有拿到带时间区间的睡眠阶段样本，先显示阶段汇总。")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                badge(hasTimeline ? "REM 节律" : "等待样本", tint: Color(hex: "5E5CE6"))
            }

            HStack(spacing: Theme.Spacing.small) {
                stageStat(title: "REM", minutes: remMinutes, color: Color(hex: "78E2DF"))
                stageStat(title: "深睡", minutes: deepMinutes, color: Color(hex: "3240D3"))
                stageStat(title: "清醒", minutes: awakeMinutes, color: Color(hex: "CFC7F7"))
            }

            if hasTimeline {
                SleepStageTimelineChart(
                    stages: stages,
                    sleepInterval: sleepInterval,
                    mode: .detailed
                )
                .frame(height: 260)

                SleepStageTimelineLegend()
            } else if isLoading {
                ProgressView("正在读取健康 App 数据")
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
            } else {
                emptyState(text: "健康 App 暂无 REM 睡眠阶段时间轴")
                    .frame(height: 220)
            }
        }
        .healthDetailSurface()
    }

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("解读")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(insightText)
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.small) {
                metric(title: "后半夜恢复", value: remRatio >= 0.18 ? "较完整" : "可提升", tint: Color(hex: "ECF3FF"))
                metric(title: "完整睡眠", value: totalMinutes > 0 ? durationText(totalMinutes) : "--", tint: Color(hex: "E8FBFB"))
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                suggestion(icon: "moon.zzz.fill", title: "固定入睡窗口", detail: "REM 多集中在后半夜，稳定作息比临时补觉更有效。")
                suggestion(icon: "cup.and.saucer.fill", title: "减少睡前刺激", detail: "晚间咖啡因、酒精和强光会压缩 REM 的连续性。")
            }
        }
        .healthDetailSurface()
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("近 7 天总睡眠时长")
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("REM 恢复通常依赖完整睡眠时长，先看整体睡眠是否被压缩。")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
            }

            if isLoading {
                ProgressView("正在读取健康 App 数据")
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
            } else if sleepDurationSeries.isEmpty {
                emptyState(text: "健康 App 暂无近 7 天睡眠记录")
                    .frame(height: 220)
            } else {
                Chart(sleepDurationSeries) { item in
                    BarMark(
                        x: .value("日期", item.date, unit: .day),
                        y: .value("小时", item.value / 60.0)
                    )
                    .foregroundStyle(Color(hex: "5E5CE6").gradient)
                    .cornerRadius(6)

                    RuleMark(y: .value("目标", 7.0))
                        .foregroundStyle(Color(hex: "5E5CE6").opacity(0.28))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .frame(height: 220)
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day(.defaultDigits))
                            .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Theme.Colors.textTertiary.opacity(0.16))
                        AxisValueLabel()
                            .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .healthDetailSurface()
    }

    private var disclaimerCard: some View {
        HealthDisclaimerCard(
            message: "本页 REM 睡眠数据、阶段时间轴和解读仅供日常自我管理参考，不构成医疗诊断或治疗建议。若长期噩梦频繁、白天困倦明显或需要做出重要健康决定，请咨询专业医生。"
        )
    }

    private var insightText: String {
        guard totalMinutes > 0 else {
            return String(localized: "授权健康 App 并佩戴 Apple Watch 睡眠后，这里会显示 REM 占比，以及 Awake、REM、Core、Deep 的完整阶段结构。")
        }
        if remRatio >= 0.18 && remRatio <= 0.28 {
            return String(localized: "昨晚 REM 占比处于常见健康区间，后半夜记忆整理和情绪恢复节奏较平稳。")
        }
        if remRatio < 0.18 {
            return String(localized: "昨晚 REM 占比偏低。优先保证完整睡眠时长，避免过早醒来压缩后半夜 REM，并留意时间轴里是否存在临近清晨的频繁觉醒。")
        }
        return String(localized: "昨晚 REM 占比较高。如果同时觉得疲惫，可继续结合深睡和夜间觉醒一起看，判断是否只是睡眠结构后移。")
    }

    private func load() async {
        isLoading = true
        async let stageTask = try? HealthKitManager.shared.fetchDetailedSleepStages()
        async let intervalTask = try? HealthKitManager.shared.fetchLatestSleepInterval()
        async let durationTask = try? HealthKitManager.shared.fetchSleepDurationSeries(days: 7)
        stages = (await stageTask) ?? []
        sleepInterval = await intervalTask
        sleepDurationSeries = (await durationTask) ?? []
        isLoading = false
    }

    private func metric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    private func suggestion(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundColor(Color(hex: "5E5CE6"))
                .frame(width: 28, height: 28)
                .background(Color(hex: "5E5CE6").opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    private func emptyState(text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .font(.appSystem(size: 28, weight: .semibold))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(text)
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stageStat(title: String, minutes: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(minutes > 0 ? "\(minutes) 分" : "--")
                .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.appSystem(size: 10, weight: .heavy, design: .rounded))
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func durationText(_ minutes: Int) -> String {
        guard minutes > 0 else { return "--" }
        return String(localized: "\(minutes / 60)小时\(minutes % 60)分")
    }

    private func minutes(for stage: String) -> Int {
        stages
            .filter { normalizedStage($0.stage) == stage }
            .map(\.duration)
            .reduce(0, +)
    }

    private func normalizedStage(_ stage: String) -> String {
        if stage.contains("深") || stage.caseInsensitiveCompare("Deep") == .orderedSame {
            return "Deep"
        }
        if stage.contains("快速") || stage.caseInsensitiveCompare("REM") == .orderedSame {
            return "REM"
        }
        if stage.contains("清醒") || stage.caseInsensitiveCompare("Awake") == .orderedSame {
            return "Awake"
        }
        if stage.contains("浅") || stage.contains("核心") || stage.caseInsensitiveCompare("Core") == .orderedSame {
            return "Core"
        }
        return stage
    }
}
