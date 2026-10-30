import WidgetKit
import SwiftUI
import AppIntents

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            configuration: ConfigurationAppIntent(),
            snapshot: .previewRecovery()
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: configuration, snapshot: WidgetSharedStore.loadSnapshot())
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let now = Date()
        let snapshot = WidgetSharedStore.loadSnapshot(now: now)
        let refresh = nextRefreshDate(for: snapshot, now: now)
        // 多 entry 让相对时间文案与新鲜度状态在两次刷新之间也能持续推进
        var entries: [SimpleEntry] = []
        var entryDate = now
        while entryDate < refresh {
            entries.append(SimpleEntry(date: entryDate, configuration: configuration, snapshot: snapshot))
            entryDate = entryDate.addingTimeInterval(15 * 60)
        }
        return Timeline(entries: entries, policy: .after(refresh))
    }

    private func nextRefreshDate(for snapshot: WidgetHealthSnapshot, now: Date) -> Date {
        let minutes: Int
        switch widgetDataState(for: snapshot.lastSyncTime, now: now) {
        case .fresh:
            minutes = 30
        case .stale:
            minutes = 15
        case .missing:
            minutes = 45
        }
        return Calendar.current.date(byAdding: .minute, value: minutes, to: now) ?? now.addingTimeInterval(TimeInterval(minutes * 60))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let snapshot: WidgetHealthSnapshot
}

private enum OverallStatusSource: String {
    case plan
    case recovery
    case stress
    case activity
    case hydration
    case empty
    case stale
}

private struct OverallStatusDescriptor {
    let source: OverallStatusSource
    let title: String
    let summary: String
    let detail: String
    let primaryMetricTitle: String
    let primaryMetricValue: String
    let secondaryMetricTitle: String
    let secondaryMetricValue: String
    let tertiaryMetricTitle: String
    let tertiaryMetricValue: String
    let tone: WidgetVisualTone
    let symbolName: String
    let progress: Double
}

private extension OverallStatusSource {
    init(_ source: SharedWidgetDescriptorSource) {
        switch source {
        case .recovery:
            self = .recovery
        case .stress:
            self = .stress
        case .activity:
            self = .activity
        case .hydration:
            self = .hydration
        case .empty:
            self = .empty
        case .stale:
            self = .stale
        }
    }
}

private extension WidgetVisualTone {
    init(_ tone: SharedWidgetDescriptorTone) {
        switch tone {
        case .relaxed:
            self = .relaxed
        case .steady:
            self = .steady
        case .mild:
            self = .mild
        case .caution:
            self = .caution
        case .high:
            self = .high
        case .waiting:
            self = .waiting
        }
    }
}

private extension SharedOverallWidgetSnapshot {
    init(_ snapshot: WidgetHealthSnapshot) {
        self.init(
            heartRate: snapshot.heartRate,
            hrv: snapshot.hrv,
            stress: snapshot.stress,
            stressState: snapshot.stressState,
            stressExplanationCode: nil,
            stressConfidence: nil,
            stressTrend: snapshot.stressTrend,
            lastSyncTime: snapshot.lastSyncTime,
            waterIntakeMl: snapshot.waterIntakeMl,
            waterTargetMl: snapshot.waterTargetMl,
            waterCompletionRate: snapshot.waterCompletionRate,
            caffeineRemainedMg: snapshot.caffeineRemainedMg,
            steps: snapshot.steps,
            activeEnergy: snapshot.activeEnergy,
            activityCompletionRate: snapshot.activityCompletionRate,
            sleepDurationMinutes: snapshot.sleepDurationMinutes,
            sleepScore: snapshot.sleepScore,
            sleepDurationCompletionRate: snapshot.sleepDurationCompletionRate,
            lateNightRecoveryPrompt: snapshot.sleep.lateNightRecoveryPrompt,
            lateNightRecoverySeverity: snapshot.sleep.lateNightRecoverySeverity,
            sleepEnvironmentCompletionRate: snapshot.sleep.environmentCompletionRate,
            sleepEnvironmentPrompt: snapshot.sleep.environmentPrompt
        )
    }
}

struct MianyuWidgetEntryView: View {
    let entry: SimpleEntry

    var body: some View {
        let viewDescriptor = descriptor(for: entry.snapshot, focus: entry.configuration.focus, now: entry.date)

        WidgetRenderContextReader { renderContext in
            Group {
                switch renderContext.family {
                case .systemSmall:
                    MianyuSmallCard(snapshot: entry.snapshot, descriptor: viewDescriptor, now: entry.date)
                case .systemMedium:
                    MianyuMediumCard(snapshot: entry.snapshot, descriptor: viewDescriptor, now: entry.date)
                case .systemLarge:
                    MianyuLargeCard(snapshot: entry.snapshot, descriptor: viewDescriptor, now: entry.date)
                case .accessoryRectangular:
                    MianyuAccessoryRectangularCard(snapshot: entry.snapshot, descriptor: viewDescriptor, now: entry.date)
                case .accessoryCircular:
                    MianyuAccessoryCircularCard(snapshot: entry.snapshot, descriptor: viewDescriptor)
                case .accessoryInline:
                    MianyuAccessoryInlineCard(snapshot: entry.snapshot, descriptor: viewDescriptor)
                default:
                    MianyuMediumCard(snapshot: entry.snapshot, descriptor: viewDescriptor, now: entry.date)
                }
            }
        }
        .widgetURL(deepLinkURL(for: viewDescriptor, focus: entry.configuration.focus))
    }
}

/// 深链跟随用户的聚焦配置：聚焦睡眠时点击直接进睡眠页，而不是回综合页
private func deepLinkURL(for descriptor: OverallStatusDescriptor, focus: WidgetFocusMode) -> URL? {
    // 今日计划展示时仍跳综合页，计划详情在那里
    if descriptor.source == .plan { return MianyuWidgetDeepLink.overall }
    switch focus {
    case .automatic, .hydration:
        return MianyuWidgetDeepLink.overall
    case .recovery:
        return MianyuWidgetDeepLink.vitals
    case .sleep:
        return MianyuWidgetDeepLink.sleep
    case .stress:
        return MianyuWidgetDeepLink.stress
    case .activity:
        return MianyuWidgetDeepLink.activity
    }
}

/// 取当前有效计划里下一项待处理行动，供卡片上的完成按钮使用
private func pendingPlanAction(in snapshot: WidgetHealthSnapshot, now: Date) -> (planID: String, action: SharedWidgetRecoveryAction)? {
    guard let plan = snapshot.recoveryPlan,
          plan.isValid(at: now),
          let action = plan.nextAction else {
        return nil
    }
    return (plan.planID, action)
}

struct MianyuWidget: Widget {
    let kind: String = "BioBalanceWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            MianyuWidgetEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("综合状态")
        .description("查看同源今日计划，以及恢复、压力、睡眠、活动与补水重点。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

#if ENABLE_WIDGET_PREVIEWS
#Preview(as: .systemMedium) {
    MianyuWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        configuration: ConfigurationAppIntent(),
        snapshot: .previewRecovery()
    )
    SimpleEntry(
        date: .now,
        configuration: ConfigurationAppIntent(),
        snapshot: .previewEmpty()
    )
}

#Preview(as: .accessoryRectangular) {
    MianyuWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        configuration: ConfigurationAppIntent(),
        snapshot: .previewRecovery()
    )
    SimpleEntry(
        date: .now,
        configuration: ConfigurationAppIntent(),
        snapshot: .previewStaleStress()
    )
}
#endif

private extension WidgetHealthSnapshot {
    static func previewRecovery(now: Date = .now) -> WidgetHealthSnapshot {
        WidgetHealthSnapshot(
            generatedAt: now,
            vitals: .init(
                heartRate: 68,
                hrv: 61,
                stress: 24,
                stressTrend: "下降",
                freshness: .init(updatedAt: now, staleAfter: 2 * 60 * 60),
                recoveryScore: 82,
                recoveryStatus: "可推进",
                recoveryTrend: "回升"
            ),
            hydration: .init(
                waterIntakeMl: 1400,
                waterTargetMl: 2000,
                waterCompletionRate: 0.7,
                caffeineRemainedMg: 60,
                freshness: .init(updatedAt: now, staleAfter: 6 * 60 * 60)
            ),
            activity: .init(
                steps: 6380,
                stepsGoal: 8000,
                activeEnergy: 420,
                activeEnergyGoal: 500,
                exerciseMinutes: 21,
                exerciseMinutesGoal: 30,
                standHours: 8,
                standHoursGoal: 12,
                stepsCompletionRate: 0.8,
                activeEnergyCompletionRate: 0.84,
                exerciseMinutesCompletionRate: 0.7,
                standHoursCompletionRate: 0.67,
                activityCompletionRate: 0.75,
                freshness: .init(updatedAt: now, staleAfter: 4 * 60 * 60)
            ),
            sleep: .init(
                durationMinutes: 456,
                score: 84,
                goalMinutes: 480,
                completionRate: 0.95,
                freshness: .init(updatedAt: now, staleAfter: 18 * 60 * 60)
            ),
            summary: .init(
                healthSummary: "恢复在线，适合正常推进今天计划。",
                bodyAgeValueYears: 27.4,
                bodyAgeStatusText: "年轻于实际年龄",
                vo2MaxValue: 43.8,
                vo2MaxConfidence: 82,
                vo2MaxTrend: "improving",
                vo2MaxFitnessLevel: "Good",
                vo2MaxSource: "engineEstimated",
                vo2MaxDriverSummary: "最近跑步配速与心率配合更高效",
                freshness: .init(updatedAt: now, staleAfter: 12 * 60 * 60)
            ),
            recoveryPlan: .init(
                planID: "recovery-plan-preview",
                dayStart: Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970),
                updatedAt: now,
                actions: [
                    .init(actionID: "main", title: "稳住今天的恢复节律", role: .main, state: .pending),
                    .init(actionID: "supporting-water", title: "先补一杯水", role: .supporting, state: .completed),
                    .init(actionID: "supporting-walk", title: "起身走动 3 分钟", role: .supporting, state: .pending)
                ]
            )
        )
    }

    static func previewStaleStress(now: Date = .now) -> WidgetHealthSnapshot {
        let staleDate = now.addingTimeInterval(-(3 * 60 * 60))
        return WidgetHealthSnapshot(
            generatedAt: now,
            vitals: .init(
                heartRate: 92,
                hrv: 28,
                stress: 72,
                stressTrend: "上升",
                freshness: .init(updatedAt: staleDate, staleAfter: 2 * 60 * 60),
                recoveryScore: 42,
                recoveryStatus: "先恢复",
                recoveryTrend: "走低"
            ),
            hydration: .init(
                waterIntakeMl: 700,
                waterTargetMl: 2000,
                waterCompletionRate: 0.35,
                caffeineRemainedMg: 20,
                freshness: .init(updatedAt: staleDate, staleAfter: 6 * 60 * 60)
            ),
            activity: .init(
                steps: 3020,
                stepsGoal: 8000,
                activeEnergy: 180,
                activeEnergyGoal: 500,
                exerciseMinutes: 9,
                exerciseMinutesGoal: 30,
                standHours: 4,
                standHoursGoal: 12,
                stepsCompletionRate: 0.38,
                activeEnergyCompletionRate: 0.36,
                exerciseMinutesCompletionRate: 0.3,
                standHoursCompletionRate: 0.33,
                activityCompletionRate: 0.34,
                freshness: .init(updatedAt: staleDate, staleAfter: 4 * 60 * 60)
            ),
            sleep: .init(
                durationMinutes: 332,
                score: 61,
                goalMinutes: 480,
                completionRate: 0.69,
                freshness: .init(updatedAt: staleDate, staleAfter: 18 * 60 * 60)
            ),
            summary: .init(
                healthSummary: "压力偏高，建议先放慢节奏再继续。",
                bodyAgeValueYears: nil,
                bodyAgeStatusText: nil,
                vo2MaxValue: 39.6,
                vo2MaxConfidence: 61,
                vo2MaxTrend: "stable",
                vo2MaxFitnessLevel: "Average",
                vo2MaxSource: "engineEstimated",
                vo2MaxDriverSummary: "近几天恢复偏弱，系统对上行保持保守",
                freshness: .init(updatedAt: staleDate, staleAfter: 12 * 60 * 60)
            )
        )
    }

    static func previewEmpty(now: Date = .now) -> WidgetHealthSnapshot {
        WidgetHealthSnapshot(generatedAt: now)
    }
}

#if ENABLE_WIDGET_PREVIEWS
#Preview("Small", as: .systemSmall) {
    MianyuWidget()
} timeline: {
        SimpleEntry(
            date: .now,
            configuration: ConfigurationAppIntent(),
            snapshot: .previewRecovery()
        )
    }

#Preview("Large Stale", as: .systemLarge) {
    MianyuWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        configuration: ConfigurationAppIntent(),
        snapshot: .previewStaleStress()
    )
}

#Preview("Accessory Rectangular", as: .accessoryRectangular) {
    MianyuWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        configuration: ConfigurationAppIntent(),
        snapshot: .previewEmpty()
    )
}
#endif

private struct MianyuSmallCard: View {
    let snapshot: WidgetHealthSnapshot
    let descriptor: OverallStatusDescriptor
    let now: Date

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetGlassMetrics.outerRadiusSmall, style: .continuous)
        ZStack {
            WidgetReferenceCardBackground(tint: descriptor.tone.accent, cornerRadius: WidgetGlassMetrics.outerRadiusSmall)
            VStack(alignment: .leading, spacing: 5) {
                WidgetReferenceHeader(
                    icon: descriptor.symbolName,
                    title: descriptor.source == .plan ? String(localized: "今日计划") : String(localized: "综合"),
                    status: descriptor.title,
                    tint: descriptor.tone.accent
                )

                WidgetReferenceMetric(
                    value: descriptor.primaryMetricValue,
                    unit: descriptor.primaryMetricTitle
                )

                WidgetReferenceBars(
                    values: chartValues,
                    tint: descriptor.tone.accent,
                    secondaryTint: descriptor.tone.secondaryAccent
                )
                .frame(height: 34)

                WidgetReferenceFooter(stats: [
                    WidgetReferenceStat(value: descriptor.secondaryMetricValue, label: descriptor.secondaryMetricTitle, tint: descriptor.tone.accent),
                    WidgetReferenceStat(value: descriptor.tertiaryMetricValue, label: descriptor.tertiaryMetricTitle, tint: descriptor.tone.secondaryAccent),
                    WidgetReferenceStat(value: widgetClockText(for: snapshot.lastSyncTime, now: now), label: String(localized: "同步"), tint: Color.white.opacity(0.72))
                ])
            }
            .padding(12)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var chartValues: [Double] {
        WidgetMetricSeries.normalized([
            (snapshot.waterCompletionRate ?? 0) * 100,
            (snapshot.sleepDurationCompletionRate ?? 0) * 100,
            (snapshot.activityCompletionRate ?? 0) * 100,
            descriptor.progress * 100
        ])
    }
}

private struct MianyuMediumCard: View {
    let snapshot: WidgetHealthSnapshot
    let descriptor: OverallStatusDescriptor
    let now: Date
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetGlassMetrics.outerRadiusMedium, style: .continuous)
        ZStack(alignment: .trailing) {
            WidgetCardBackground(tone: descriptor.tone, cornerRadius: WidgetGlassMetrics.outerRadiusMedium)
            WidgetRingView(progress: descriptor.progress, tint: descriptor.tone.accent, lineWidth: 16)
                .frame(width: WidgetGlassMetrics.mediumOrbSize, height: WidgetGlassMetrics.mediumOrbSize)
                .overlay {
                    VStack(spacing: 3) {
                        Text(descriptor.primaryMetricValue)
                            .font(.widgetAppSystem(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(descriptor.tone.accent)
                        Text(descriptor.primaryMetricTitle)
                            .font(.widgetAppSystem(size: 11, weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? WidgetPalette.textTertiaryDark : WidgetPalette.textTertiary)
                    }
                }
                .padding(.trailing, WidgetGlassMetrics.mediumOrbTrailingInset)
        }
        .overlay(alignment: .leading) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    WidgetAccentChip(icon: descriptor.symbolName, text: descriptor.source == .plan ? String(localized: "今日计划") : String(localized: "综合状态"), tint: descriptor.tone.accent)
                    Spacer(minLength: 0)
                    WidgetAccentChip(icon: "clock", text: widgetRelativeSyncText(for: snapshot.lastSyncTime, now: now), tint: descriptor.tone.accent)
                }

                Text(descriptor.title)
                    .font(.widgetAppSystem(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(descriptor.tone.accent)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    WidgetMetricCard(title: descriptor.secondaryMetricTitle, value: descriptor.secondaryMetricValue, tint: descriptor.tone.accent)
                    WidgetMetricCard(title: descriptor.tertiaryMetricTitle, value: descriptor.tertiaryMetricValue, tint: descriptor.tone.secondaryAccent)
                    if let pending = pendingPlanAction(in: snapshot, now: now), descriptor.source == .plan {
                        // 今日计划展示时，提供一键完成下一项行动的入口
                        Button(intent: CompleteRecoveryActionIntent(planID: pending.planID, actionID: pending.action.actionID)) {
                            Image(systemName: "checkmark")
                                .font(.widgetAppSystem(size: 15, weight: .bold))
                                .foregroundStyle(descriptor.tone.accent)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.62))
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(descriptor.tone.accent.opacity(0.28), lineWidth: 1)
                                )
                                .invalidatableContent()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "完成：\(pending.action.title)"))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(WidgetGlassMetrics.outerPadding)
            .padding(.trailing, WidgetGlassMetrics.mediumContentTrailingReserve)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }
}

private struct MianyuLargeCard: View {
    let snapshot: WidgetHealthSnapshot
    let descriptor: OverallStatusDescriptor
    let now: Date
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderContext) private var renderContext

    /// AI 一句话总结，去空后为空则不展示
    private var trimmedHealthSummary: String? {
        guard let text = snapshot.healthSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetGlassMetrics.outerRadiusLarge, style: .continuous)

        ZStack {
            WidgetCardBackground(tone: descriptor.tone, cornerRadius: WidgetGlassMetrics.outerRadiusLarge)
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    WidgetAccentChip(icon: descriptor.symbolName, text: descriptor.source == .plan ? String(localized: "今日计划") : String(localized: "综合状态"), tint: descriptor.tone.accent)
                    Spacer(minLength: 0)
                    WidgetAccentChip(icon: "clock", text: widgetRelativeSyncText(for: snapshot.lastSyncTime, now: now), tint: descriptor.tone.accent)
                }

                Text(descriptor.title)
                    .font(.widgetAppSystem(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(descriptor.tone.accent)
                    .lineLimit(2)

                HStack(alignment: .top, spacing: 12) {
                    WidgetRingView(progress: descriptor.progress, tint: descriptor.tone.accent, lineWidth: 17)
                        .frame(width: 110, height: 110)
                        .overlay {
                            VStack(spacing: 3) {
                                Text(descriptor.primaryMetricValue)
                                    .font(.widgetAppSystem(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(descriptor.tone.accent)
                                Text(descriptor.primaryMetricTitle)
                                    .font(.widgetAppSystem(size: 11, weight: .semibold))
                                    .foregroundStyle(colorScheme == .dark ? WidgetPalette.textTertiaryDark : WidgetPalette.textTertiary)
                            }
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        WidgetMetricCard(title: descriptor.secondaryMetricTitle, value: descriptor.secondaryMetricValue, tint: descriptor.tone.accent)
                        WidgetMetricCard(title: descriptor.tertiaryMetricTitle, value: descriptor.tertiaryMetricValue, tint: descriptor.tone.secondaryAccent)

                        // 把 resolver 的解释与 AI 一句话总结利用起来，避免大卡只重复展示指标
                        if !renderContext.prefersSimplifiedContent {
                            Text(descriptor.summary)
                                .font(.widgetAppSystem(size: 13, weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? WidgetPalette.textSecondaryDark : WidgetPalette.textSecondary)
                                .lineLimit(2)

                            if let healthSummary = trimmedHealthSummary, healthSummary != descriptor.summary {
                                Text(healthSummary)
                                    .font(.widgetAppSystem(size: 12, weight: .medium))
                                    .foregroundStyle(colorScheme == .dark ? WidgetPalette.textTertiaryDark : WidgetPalette.textTertiary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    if let pending = pendingPlanAction(in: snapshot, now: now) {
                        Button(intent: CompleteRecoveryActionIntent(planID: pending.planID, actionID: pending.action.actionID)) {
                            WidgetActionCapsule(title: String(localized: "完成行动"), icon: "checkmark.circle.fill", tint: descriptor.tone.accent)
                                .invalidatableContent()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "完成：\(pending.action.title)"))
                    }
                    Button(intent: AddWaterIntent(amountMl: 250)) {
                        WidgetActionCapsule(title: String(localized: "补水 250ml"), icon: "drop.fill", tint: descriptor.tone.secondaryAccent)
                            .invalidatableContent()
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }
}

private struct MianyuAccessoryRectangularCard: View {
    let snapshot: WidgetHealthSnapshot
    let descriptor: OverallStatusDescriptor
    let now: Date

    var body: some View {
        WidgetAccessorySummaryView(
            label: descriptor.source == .plan ? String(localized: "今日计划") : String(localized: "综合"),
            title: descriptor.title,
            detail: "\(descriptor.primaryMetricTitle) \(descriptor.primaryMetricValue) · \(widgetRelativeSyncText(for: snapshot.lastSyncTime, now: now))",
            tint: descriptor.tone.accent
        )
    }
}

private struct MianyuAccessoryCircularCard: View {
    let snapshot: WidgetHealthSnapshot
    let descriptor: OverallStatusDescriptor

    var body: some View {
        Gauge(value: descriptor.progress, in: 0...1) {
            Image(systemName: descriptor.symbolName)
        } currentValueLabel: {
            Text(descriptor.primaryMetricValue)
        }
        .tint(descriptor.tone.accent)
        .gaugeStyle(.accessoryCircular)
        // 锁屏着色模式下让系统统一渲染重点内容
        .widgetAccentable()
    }
}

private struct MianyuAccessoryInlineCard: View {
    let snapshot: WidgetHealthSnapshot
    let descriptor: OverallStatusDescriptor

    var body: some View {
        Text("\(descriptor.title) \(descriptor.primaryMetricTitle) \(descriptor.primaryMetricValue)")
    }
}

private func descriptor(for snapshot: WidgetHealthSnapshot, focus: WidgetFocusMode = .automatic, now: Date = .now) -> OverallStatusDescriptor {
    if (focus == .automatic || focus == .recovery),
       let plan = snapshot.recoveryPlan,
       plan.isValid(at: now) {
        return recoveryPlanDescriptor(plan)
    }

    let resolved = WidgetOverallResolver.resolve(snapshot: SharedOverallWidgetSnapshot(snapshot), focus: focus.sharedMode, now: now)
    return OverallStatusDescriptor(
        source: .init(resolved.source),
        title: resolved.title,
        summary: resolved.summary,
        detail: resolved.detail,
        primaryMetricTitle: resolved.primaryMetricTitle,
        primaryMetricValue: resolved.primaryMetricValue,
        secondaryMetricTitle: resolved.secondaryMetricTitle,
        secondaryMetricValue: resolved.secondaryMetricValue,
        tertiaryMetricTitle: resolved.tertiaryMetricTitle,
        tertiaryMetricValue: resolved.tertiaryMetricValue,
        tone: .init(resolved.tone),
        symbolName: resolved.symbolName,
        progress: resolved.progress
    )
}

private func recoveryPlanDescriptor(_ plan: SharedWidgetRecoveryPlan) -> OverallStatusDescriptor {
    let action = plan.nextAction
    let total = max(plan.actions.count, 1)
    let progress = Double(plan.processedActionCount) / Double(total)
    let isFinished = action == nil
    let roleText = action?.role == .main ? String(localized: "主目标") : String(localized: "辅助行动")
    let stateText: String
    if action?.state == .snoozed {
        stateText = String(localized: "稍后")
    } else if action?.state == .pending {
        stateText = String(localized: "待完成")
    } else {
        stateText = String(localized: "已处理")
    }

    return OverallStatusDescriptor(
        source: .plan,
        title: action?.title ?? String(localized: "今日计划已处理"),
        summary: isFinished ? String(localized: "今日行动已收尾") : String(localized: "下一项最值得执行的行动"),
        detail: isFinished ? String(localized: "继续保持当前节律") : roleText,
        primaryMetricTitle: String(localized: "已处理"),
        primaryMetricValue: "\(plan.processedActionCount)/\(plan.actions.count)",
        secondaryMetricTitle: String(localized: "行动"),
        secondaryMetricValue: isFinished ? String(localized: "已收尾") : roleText,
        tertiaryMetricTitle: String(localized: "状态"),
        tertiaryMetricValue: stateText,
        tone: isFinished ? .relaxed : .steady,
        symbolName: isFinished ? "checkmark.circle.fill" : "scope",
        progress: isFinished ? 1 : max(0.08, progress)
    )
}
