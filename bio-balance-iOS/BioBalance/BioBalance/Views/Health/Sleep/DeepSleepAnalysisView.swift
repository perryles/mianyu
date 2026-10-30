/// DeepSleepAnalysisView 由睡眠详情的「深度睡眠」阶段卡调用。
/// 负责展示深睡时长、REM 占比、睡眠阶段分布及趋势序列。

import SwiftUI
import Charts

/// 负责展示睡眠记录、恢复分析以及睡眠与其他指标的关联。
struct DeepSleepAnalysisView: View {
    @State private var stages: [SleepStage] = []
    @State private var sleepInterval: SleepInterval?
    @State private var sleepDurationSeries: [TimeSeriesPointDouble] = []
    @State private var isLoading = false

    private var deepMinutes: Int {
        minutes(for: "Deep")
    }

    private var remMinutes: Int {
        minutes(for: "REM")
    }

    private var awakeMinutes: Int {
        minutes(for: "Awake")
    }

    private var totalStageMinutes: Int {
        stages.map(\.duration).reduce(0, +)
    }

    private var deepRatio: Double {
        guard totalStageMinutes > 0 else { return 0 }
        return Double(deepMinutes) / Double(totalStageMinutes)
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
                    recoveryCard
                    weeklySleepCard
                    suggestionsCard
                    disclaimerCard
                }
                .padding(.horizontal, HealthDetailDesignSystem.pageHorizontalPadding)
                .padding(.top, HealthDetailDesignSystem.pageTopPadding)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("深度睡眠")
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
                    Text("深度睡眠")
                        .font(Theme.Typography.pageTitle)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("身体修复、免疫恢复和生长激素分泌更依赖这一阶段。")
                        .font(Theme.Typography.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "moon.stars.fill")
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "2B2DFF"))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: "2B2DFF").opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }

            HStack(spacing: Theme.Spacing.small) {
                metric(title: "深睡时长", value: durationText(deepMinutes), tint: Color(hex: "2B2DFF"))
                metric(title: "占比", value: deepMinutes > 0 ? "\(Int((deepRatio * 100).rounded()))%" : "--", tint: Theme.Colors.mintGreen)
                metric(title: "夜醒", value: awakeMinutes > 0 ? "\(awakeMinutes)分" : "--", tint: Color(hex: "CFC7F7"))
            }
        }
        .healthDetailSurface()
    }

    private var ambientBackground: some View {
        VStack {
            HStack {
                Circle()
                    .fill(Color(hex: "2B2DFF").opacity(0.16))
                    .frame(width: 180, height: 180)
                    .blur(radius: 28)
                    .offset(x: -36, y: -42)
                Spacer()
                Circle()
                    .fill(Theme.Colors.mintGreen.opacity(0.14))
                    .frame(width: 150, height: 150)
                    .blur(radius: 30)
                    .offset(x: 26, y: -24)
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
                    Text(hasTimeline ? "复用睡眠详情页同一套 Awake / REM / Core / Deep 专业时间轴，统一按 0:00、06:00、12:00、18:00 展示。" : "当前还没有拿到带时间区间的睡眠阶段样本，先显示阶段汇总。")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                badge(hasTimeline ? "专业时间轴" : "等待样本", tint: Color(hex: "2B2DFF"))
            }

            HStack(spacing: Theme.Spacing.small) {
                stageStat(title: "深睡", minutes: deepMinutes, color: Color(hex: "3240D3"))
                stageStat(title: "REM", minutes: remMinutes, color: Color(hex: "78E2DF"))
                stageStat(title: "总时长", minutes: totalStageMinutes, color: Theme.Colors.mintGreen)
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
                ProgressView("正在读取睡眠阶段")
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
            } else {
                emptyState(text: "健康 App 暂无可绘制的睡眠阶段时间轴")
                    .frame(height: 220)
            }
        }
        .healthDetailSurface()
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text("恢复解读")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(insightText)
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.small) {
                metric(title: "深睡目标", value: deepMinutes >= 90 ? "已达标" : "继续补足", tint: Color(hex: "E7EBFF"))
                metric(title: "REM 配合", value: remMinutes > 0 ? durationText(remMinutes) : "--", tint: Color(hex: "E8FBFB"))
            }
        }
        .healthDetailSurface()
    }

    private var weeklySleepCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("近 7 天睡眠时长")
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("深睡数据按昨晚阶段展示，时长趋势来自健康 App。")
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
                    .foregroundStyle(Theme.Colors.mintGreen.gradient)
                    .cornerRadius(6)

                    RuleMark(y: .value("目标", 7.0))
                        .foregroundStyle(Theme.Colors.mintGreen.opacity(0.35))
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

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text("改善建议")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            suggestion(icon: "thermometer.snowflake", title: "保持凉爽环境", detail: "卧室略低温、少光线，更容易进入稳定深睡。", color: Color(hex: "5E8CFF"))
            suggestion(icon: "figure.walk", title: "白天规律活动", detail: "白天中低强度运动有助于提升夜间恢复质量。", color: Theme.Colors.mintGreen)
            suggestion(icon: "iphone.slash", title: "睡前减少刺激", detail: "减少强光、短视频和酒精，避免压缩前半夜深睡。", color: Color(hex: "FF9F0A"))
        }
        .healthDetailSurface()
    }

    private var disclaimerCard: some View {
        HealthDisclaimerCard(
            message: "本页深度睡眠数据、阶段时间轴和解读仅供日常自我管理参考，不构成医疗诊断或治疗建议。若长期睡眠不佳、白天嗜睡或需要做出重要健康决定，请咨询专业医生。"
        )
    }

    private var insightText: String {
        guard totalStageMinutes > 0 else {
            return String(localized: "佩戴 Apple Watch 完成睡眠监测后，这里会展示深睡占比以及 Awake、REM、Core、Deep 的完整阶段切换。")
        }
        if deepMinutes >= 90 {
            return String(localized: "昨晚深睡达到常见目标区间，前半夜修复节奏比较完整，身体恢复基础不错。")
        }
        if deepMinutes >= 60 {
            return String(localized: "昨晚深睡接近目标。结合时间轴看，如果前半夜频繁切到清醒或核心睡眠，优先优化睡前放松和卧室环境。")
        }
        return String(localized: "昨晚深睡偏少。深睡通常更集中在前半夜，建议优先保证睡眠连续性，并减少晚间酒精、强光和过晚进食。")
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

    private func suggestion(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
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
            Image(systemName: "bed.double.fill")
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
