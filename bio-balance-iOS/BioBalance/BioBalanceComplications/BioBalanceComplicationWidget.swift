/// Bio Balance Complication Widget 定义并发症组件，负责把关键状态以更轻量的形式展示在 Apple Watch 表盘上。
import SwiftUI
import WidgetKit
import AppIntents

/// 复杂功能Template枚举 作为表盘组件扩展里的状态与分类定义。
/// 负责描述表盘并发症展示过程中会用到的状态、分类或分支。
enum ComplicationTemplateStyle: String, AppEnum, CaseIterable {
    case followDefault
    case overview
    case recovery
    case sleep
    case activity
    case hydration
    case bodyAge

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "组件模板")
    }

    static var caseDisplayRepresentations: [ComplicationTemplateStyle: DisplayRepresentation] {
        [
            .followDefault: DisplayRepresentation(title: "跟随默认"),
            .overview: DisplayRepresentation(title: "综合状态"),
            .recovery: DisplayRepresentation(title: "恢复分"),
            .sleep: DisplayRepresentation(title: "睡眠"),
            .activity: DisplayRepresentation(title: "活动"),
            .hydration: DisplayRepresentation(title: "补水"),
            .bodyAge: DisplayRepresentation(title: "体龄")
        ]
    }

    var fallbackTitle: String {
        switch self {
        case .followDefault: return String(localized: "跟随默认")
        case .overview: return String(localized: "综合状态")
        case .recovery: return String(localized: "恢复分")
        case .sleep: return String(localized: "睡眠")
        case .activity: return String(localized: "活动")
        case .hydration: return String(localized: "补水")
        case .bodyAge: return String(localized: "体龄")
        }
    }

    var sharedTemplate: SharedComplicationTemplate {
        SharedComplicationTemplate(rawValue: rawValue) ?? .overview
    }
}

/// 复杂功能ConfigurationIntent结构体 作为表盘组件扩展里的辅助类型。
/// 负责表盘并发症展示。
struct ComplicationConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "眠屿 表盘组件"
    static let description = IntentDescription("选择你希望在表盘上优先查看的健康模板。")

    @Parameter(title: "模板", default: .followDefault)
    var template: ComplicationTemplateStyle

    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// 应用复杂功能数据模型 作为表盘组件扩展里的数据载体。
/// 负责表盘并发症展示。
struct MianyuComplicationEntry: TimelineEntry {
    let date: Date
    let template: ComplicationTemplateStyle
    let heartRate: Double?
    let hrv: Double?
    let stress: Double?
    let stressTrend: String?
    let sleepDurationMinutes: Int?
    let sleepScore: Int?
    let sleepCompletionRate: Double?
    let sleepSnoreIntensity: String?
    let sleepSnoreDurationMinutes: Double?
    let steps: Int?
    let activeEnergy: Int?
    let exerciseMinutes: Int?
    let standHours: Int?
    let activityCompletionRate: Double?
    let waterIntakeMl: Double?
    let waterTargetMl: Int?
    let waterCompletionRate: Double?
    let caffeineRemainedMg: Double?
    let bodyAgeValueYears: Double?
    let bodyAgeStatusText: String?
    let healthSummary: String?
    let lastSyncTime: Date?
    let isStale: Bool
}

/// 应用复杂功能结构体 作为表盘组件扩展里的辅助类型。
/// 负责表盘并发症展示。
struct MianyuComplicationProvider: AppIntentTimelineProvider {
    typealias Intent = ComplicationConfigurationIntent
    typealias Entry = MianyuComplicationEntry

    func placeholder(in context: Context) -> MianyuComplicationEntry {
        .overviewSample
    }

    func snapshot(for configuration: ComplicationConfigurationIntent, in context: Context) async -> MianyuComplicationEntry {
        let entry = makeComplicationEntry(date: Date(), template: configuration.template)
        if context.isPreview, entry.hasDisplayContent == false {
            return .sample(for: entry.template)
        }
        return entry
    }

    func timeline(for configuration: ComplicationConfigurationIntent, in context: Context) async -> Timeline<MianyuComplicationEntry> {
        let now = Date()
        let entry = makeComplicationEntry(date: now, template: configuration.template)
        let nextUpdate = nextRefreshDate(now: now, entry: entry)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    func recommendations() -> [AppIntentRecommendation<ComplicationConfigurationIntent>] {
        [
            recommendation(.followDefault, description: String(localized: "跟随默认模板")),
            recommendation(.overview, description: String(localized: "综合状态")),
            recommendation(.recovery, description: String(localized: "恢复")),
            recommendation(.sleep, description: String(localized: "睡眠")),
            recommendation(.activity, description: String(localized: "活动")),
            recommendation(.hydration, description: String(localized: "补水")),
            recommendation(.bodyAge, description: String(localized: "体龄"))
        ]
    }

    private func nextRefreshDate(now: Date, entry: MianyuComplicationEntry) -> Date {
        if let refreshAt = AppGroupSnapshotStore.load()?.freshness(for: entry.template.sharedTemplate).nextRefreshDate(from: now),
           refreshAt > now {
            return refreshAt
        }

        let fallbackMinutes = entry.isStale ? 15 : 30
        return Calendar.current.date(byAdding: .minute, value: fallbackMinutes, to: now) ?? now.addingTimeInterval(TimeInterval(fallbackMinutes * 60))
    }

    private func recommendation(_ template: ComplicationTemplateStyle, description: String) -> AppIntentRecommendation<ComplicationConfigurationIntent> {
        let intent = ComplicationConfigurationIntent()
        intent.template = template
        return AppIntentRecommendation(intent: intent, description: description)
    }

    private func completionRate(value: Int?, goal: Int) -> Double? {
        guard let value, goal > 0 else { return nil }
        return min(1.0, Double(value) / Double(goal))
    }

    private func activityCompletionRate(
        steps: Int?,
        stepsGoal: Int?,
        activeEnergy: Int?,
        activeEnergyGoal: Int?
    ) -> Double? {
        let stepRate = completionRate(value: steps, goal: stepsGoal ?? 8000)
        let energyRate = completionRate(value: activeEnergy, goal: activeEnergyGoal ?? 500)
        let parts = [stepRate, energyRate].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return min(1.0, parts.reduce(0.0, +) / Double(parts.count))
    }
}

private func makeComplicationEntry(date: Date, template requestedTemplate: ComplicationTemplateStyle) -> MianyuComplicationEntry {
    let fallback = AppGroupManager.shared
        .getDefaultComplicationTemplate()
        .flatMap(ComplicationTemplateStyle.init(rawValue:))
        .flatMap { $0 == .followDefault ? nil : $0 }
        ?? .overview

    let resolvedTemplate = requestedTemplate == .followDefault ? fallback : requestedTemplate
    let sharedTemplate = resolvedTemplate.sharedTemplate
    let sharedSnapshot = AppGroupSnapshotStore.load()
    let appGroup = AppGroupManager.shared
    let heartRate = sharedSnapshot?.vitals.heartRate ?? appGroup.getLatestHeartRate()
    let hrv = sharedSnapshot?.vitals.hrv ?? appGroup.getLatestHRV()
    let stress = sharedSnapshot?.vitals.stress ?? appGroup.getLatestStress()
    let stressTrend = sharedSnapshot?.vitals.stressTrend ?? appGroup.getStressTrend()
    let lastSyncTime = sharedSnapshot?.freshness(for: sharedTemplate).updatedAt ?? fallbackSyncTime(for: sharedTemplate, appGroup: appGroup)
    let sleepDuration = sharedSnapshot?.sleep.durationMinutes ?? appGroup.getSleepDurationMinutes()
    let sleepScore = sharedSnapshot?.sleep.score ?? appGroup.getSleepScore()
    let sleepSnoreIntensity = sharedSnapshot?.sleep.snoreIntensity
        ?? SharedStorageReader.string(forKey: AppGroupSchema.Keys.sleepSnoreIntensity)
    let sleepSnoreDurationMinutes = sharedSnapshot?.sleep.snoreDurationMinutes
        ?? SharedStorageReader.double(forKey: AppGroupSchema.Keys.sleepSnoreDurationMinutes)
    let steps = sharedSnapshot?.activity.steps ?? appGroup.getSteps()
    let activeEnergy = sharedSnapshot?.activity.activeEnergy ?? appGroup.getActiveEnergy()
    let exerciseMinutes = sharedSnapshot?.activity.exerciseMinutes ?? appGroup.getExerciseMinutes()
    let standHours = sharedSnapshot?.activity.standHours ?? appGroup.getStandHours()
    let waterIntakeMl = sharedSnapshot?.hydration.waterIntakeMl ?? appGroup.getWaterIntakeMl()
    let waterTargetMl = sharedSnapshot?.hydration.waterTargetMl ?? appGroup.getWaterTargetMl()
    let waterCompletionRate = sharedSnapshot?.hydration.waterCompletionRate ?? appGroup.getWaterCompletionRate()
    let caffeineRemainedMg = sharedSnapshot?.hydration.caffeineRemainedMg ?? appGroup.getCaffeineRemainedMg()
    let bodyAgeValueYears = sharedSnapshot?.summary.bodyAgeValueYears ?? appGroup.getBodyAgeValueYears()
    let bodyAgeStatusText = sharedSnapshot?.summary.bodyAgeStatusText ?? appGroup.getBodyAgeStatusText()
    let healthSummary = sharedSnapshot?.summary.healthSummary ?? appGroup.getHealthSummary()
    let resolvedSleepCompletionRate = sharedSnapshot.map { _ in
        completionRate(value: sleepDuration, goal: 480)
    } ?? appGroup.getSleepDurationCompletionRate() ?? completionRate(value: sleepDuration, goal: 480)
    let resolvedActivityCompletionRate = sharedSnapshot.map { snapshot in
        activityCompletionRate(
            steps: steps,
            stepsGoal: snapshot.activity.stepsGoal,
            activeEnergy: activeEnergy,
            activeEnergyGoal: snapshot.activity.activeEnergyGoal
        )
    } ?? appGroup.getActivityCompletionRate() ?? activityCompletionRate(
        steps: steps,
        stepsGoal: appGroup.getStepsGoal(),
        activeEnergy: activeEnergy,
        activeEnergyGoal: appGroup.getActiveEnergyGoal()
    )
    let resolvedFreshness = sharedSnapshot?.freshness(for: sharedTemplate)
    let isStale = resolvedFreshness?.isStale(at: date)
        ?? fallbackIsStale(for: sharedTemplate, at: date, appGroup: appGroup)

    return MianyuComplicationEntry(
        date: date,
        template: resolvedTemplate,
        heartRate: heartRate,
        hrv: hrv,
        stress: stress,
        stressTrend: stressTrend,
        sleepDurationMinutes: sleepDuration,
        sleepScore: sleepScore,
        sleepCompletionRate: resolvedSleepCompletionRate,
        sleepSnoreIntensity: sleepSnoreIntensity,
        sleepSnoreDurationMinutes: sleepSnoreDurationMinutes,
        steps: steps,
        activeEnergy: activeEnergy,
        exerciseMinutes: exerciseMinutes,
        standHours: standHours,
        activityCompletionRate: resolvedActivityCompletionRate,
        waterIntakeMl: waterIntakeMl,
        waterTargetMl: waterTargetMl,
        waterCompletionRate: waterCompletionRate,
        caffeineRemainedMg: caffeineRemainedMg,
        bodyAgeValueYears: bodyAgeValueYears,
        bodyAgeStatusText: bodyAgeStatusText,
        healthSummary: healthSummary,
        lastSyncTime: lastSyncTime,
        isStale: isStale
    )
}

private func fallbackSyncTime(for template: SharedComplicationTemplate, appGroup: AppGroupManager) -> Date? {
    appGroup.getLastSyncTime()
}

private func fallbackIsStale(for template: SharedComplicationTemplate, at date: Date, appGroup: AppGroupManager) -> Bool {
    guard let lastSyncTime = fallbackSyncTime(for: template, appGroup: appGroup) else {
        return true
    }

    let staleAfter: TimeInterval
    switch template {
    case .overview, .recovery:
        staleAfter = AppGroupSchema.Freshness.vitalsStaleAfter
    case .sleep:
        staleAfter = AppGroupSchema.Freshness.sleepStaleAfter
    case .activity:
        staleAfter = AppGroupSchema.Freshness.activityStaleAfter
    case .hydration:
        staleAfter = AppGroupSchema.Freshness.hydrationStaleAfter
    case .bodyAge:
        staleAfter = AppGroupSchema.Freshness.summaryStaleAfter
    }
    return date.timeIntervalSince(lastSyncTime) > staleAfter
}

private func completionRate(value: Int?, goal: Int) -> Double? {
    guard let value, goal > 0 else { return nil }
    return min(1.0, Double(value) / Double(goal))
}

private func activityCompletionRate(
    steps: Int?,
    stepsGoal: Int?,
    activeEnergy: Int?,
    activeEnergyGoal: Int?
) -> Double? {
    let stepRate = completionRate(value: steps, goal: stepsGoal ?? 8000)
    let energyRate = completionRate(value: activeEnergy, goal: activeEnergyGoal ?? 500)
    let parts = [stepRate, energyRate].compactMap { $0 }
    guard !parts.isEmpty else { return nil }
    return min(1.0, parts.reduce(0.0, +) / Double(parts.count))
}

/// 应用复杂功能视图 由上级页面或路由调用，作为表盘组件扩展里的界面或内容组件。
/// 负责表盘并发症展示。
struct MianyuComplicationView: View {
    let entry: MianyuComplicationEntry
    @Environment(\.widgetFamily) private var family
#if os(watchOS)
    @Environment(\.showsWidgetLabel) private var showsWidgetLabel
#endif

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
#if os(watchOS)
        case .accessoryCorner:
            cornerView
#endif
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            rectangularView
        }
    }

    private enum SyncState {
        case empty
        case fresh
        case stale
    }

    private var hasMetricData: Bool {
        presentation.hasVitals
    }

    private var summaryText: String? {
        shortSummaryText(entry.healthSummary ?? AppGroupManager.shared.getHealthSummary())
    }

    private var hasSummaryData: Bool {
        summaryText != nil
            || sanitizedText(entry.bodyAgeStatusText ?? AppGroupManager.shared.getBodyAgeStatusText()) != nil
    }

    private var hasDisplayContent: Bool {
        hasMetricData || hasSummaryData
    }

    private var syncState: SyncState {
        guard hasDisplayContent else { return .empty }
        guard entry.lastSyncTime != nil else { return .stale }
        return entry.isStale ? .stale : .fresh
    }

    private var isStale: Bool { entry.isStale }

    private var presentation: SharedComplicationPresentation {
        SharedComplicationPresentation.resolve(
            template: entry.template.sharedTemplate,
            vitals: SharedComplicationVitals(
                heartRate: entry.heartRate,
                hrv: entry.hrv,
                stress: entry.stress,
                stressState: nil,
                stressExplanationCode: nil,
                stressConfidence: nil,
                stressTrend: entry.stressTrend,
                recoveryScore: nil,
                recoveryStatus: nil,
                recoveryTrend: nil,
                sleepDurationMinutes: entry.sleepDurationMinutes,
                sleepScore: entry.sleepScore,
                sleepCompletionRate: entry.sleepCompletionRate,
                sleepSnoreIntensity: entry.sleepSnoreIntensity,
                sleepSnoreDurationMinutes: entry.sleepSnoreDurationMinutes,
                steps: entry.steps,
                activeEnergy: entry.activeEnergy,
                exerciseMinutes: entry.exerciseMinutes,
                standHours: entry.standHours,
                activityCompletionRate: entry.activityCompletionRate,
                waterIntakeMl: entry.waterIntakeMl,
                waterTargetMl: entry.waterTargetMl,
                waterCompletionRate: entry.waterCompletionRate,
                caffeineRemainedMg: entry.caffeineRemainedMg,
                bodyAgeValueYears: entry.bodyAgeValueYears,
                bodyAgeStatusText: entry.bodyAgeStatusText,
                vo2MaxValue: nil,
                vo2MaxConfidence: nil,
                vo2MaxTrend: nil,
                vo2MaxFitnessLevel: nil,
                vo2MaxSource: nil,
                vo2MaxDriverSummary: nil,
                healthSummary: entry.healthSummary,
                lastSyncTime: entry.lastSyncTime
            ),
            now: entry.date,
            isStaleOverride: entry.isStale
        )
    }

    private var templateTitle: String {
        presentation.template.shortTitle
    }

    private var freshnessText: String {
        switch syncState {
        case .empty:
            return String(localized: "待同步")
        case .stale:
            return presentation.freshnessText
        case .fresh:
            break
        }
        return presentation.freshnessText
    }

    private var stressColor: Color {
        guard let value = entry.stress, value > 0 else {
            return Color.gray
        }
        switch value {
        case 0..<35:
            return WatchBrandPalette.brandGreen
        case 35..<70:
            return Color(red: 1.0, green: 0.74, blue: 0.36)
        default:
            return Color(red: 1.0, green: 0.38, blue: 0.42)
        }
    }

    private var primaryColor: Color {
        switch entry.template {
        case .followDefault: return stressColor
        case .overview: return stressColor
        case .recovery: return WatchBrandPalette.brandGreen
        case .sleep: return .blue
        case .activity: return .orange
        case .hydration: return .cyan
        case .bodyAge: return .purple
        }
    }

    private var secondaryColor: Color {
        switch entry.template {
        case .followDefault, .overview:
            return WatchBrandPalette.brandBlue
        case .recovery:
            return WatchBrandPalette.brandBlue
        case .sleep:
            return WatchBrandPalette.brandCyan
        case .activity:
            return WatchBrandPalette.brandGreen
        case .hydration:
            return Color(red: 0.41, green: 0.74, blue: 0.98)
        case .bodyAge:
            return Color(red: 0.72, green: 0.54, blue: 0.98)
        }
    }

    private var stateTitle: String {
        if hasMetricData { return presentation.statusTitle }
        if let bodyAgeStatus = sanitizedText(entry.bodyAgeStatusText ?? AppGroupManager.shared.getBodyAgeStatusText()),
           entry.template == .bodyAge {
            return bodyAgeStatus
        }
        if entry.template == .overview, summaryText != nil {
            return String(localized: "今日摘要")
        }
        if hasSummaryData {
            return String(localized: "已同步")
        }
        return String(localized: "待同步")
    }

    private var trendText: String {
        guard let trend = entry.stressTrend, !trend.isEmpty else { return String(localized: "趋势 --") }
        return String(localized: "趋势 \(trend)")
    }

    private var circularRange: ClosedRange<Double> {
        presentation.gaugeRangeLower...presentation.gaugeRangeUpper
    }

    private var circularValue: Double? {
        presentation.gaugeValue
    }

    private var circularSymbol: String {
        switch entry.template {
        case .followDefault: return "waveform.path.ecg"
        case .overview: return "waveform.path.ecg"
        case .recovery: return "leaf.fill"
        case .sleep: return "bed.double.fill"
        case .activity: return "figure.walk"
        case .hydration: return "drop.fill"
        case .bodyAge: return "person.text.rectangle"
        }
    }

    private var cornerSymbolName: String {
        switch entry.template {
        case .followDefault, .overview:
            return "waveform.path.ecg"
        case .recovery:
            return "leaf.fill"
        case .sleep:
            return "bed.double.fill"
        case .activity:
            return "figure.walk"
        case .hydration:
            return "drop.fill"
        case .bodyAge:
            return "person.text.rectangle"
        }
    }

    private var cornerValueText: String {
        if entry.template == .activity, let steps = entry.steps {
            return compactCount(steps)
        }
        if entry.template == .hydration, let rate = entry.waterCompletionRate {
            return "\(Int((rate * 100).rounded()))%"
        }
        if entry.template == .bodyAge, let age = entry.bodyAgeValueYears {
            return "\(Int(age.rounded()))"
        }
        return circularValue.map { "\(Int($0.rounded()))" } ?? "--"
    }

    private var cornerCurvedText: String {
        ViewText.trimmed("\(templateTitle) \(cornerValueText)", maxLength: 8)
    }

    private var cornerLabelText: String {
        if syncState == .empty {
            return String(localized: "等待同步")
        }
        return "\(presentation.primaryMetricTitle) \(presentation.primaryMetricValue) · \(freshnessText)"
    }

    private var cornerCaptionText: String {
        if syncState == .empty { return "SYNC" }
        return presentation.template.cornerLabel
    }

    private var inlineText: String {
        if !hasMetricData, let summaryText {
            return "\(templateTitle) \(summaryText)"
        }
        if !hasMetricData, isStale {
            return String(localized: "\(templateTitle) 数据较旧")
        }
        return presentation.inlineText
    }

    private var deepLink: URL? {
        URL(string: "biobalance://watch/dashboard")
    }

    private var emptyStateText: String {
        if let summaryText {
            return summaryText
        }
        if let bodyAgeStatus = sanitizedText(entry.bodyAgeStatusText ?? AppGroupManager.shared.getBodyAgeStatusText()) {
            return bodyAgeStatus
        }
        if isStale {
            return String(localized: "数据较旧，等待刷新")
        }
        return String(localized: "等待同步健康数据")
    }

    private var circularView: some View {
        let gaugeTint = isStale
            ? AnyShapeStyle(Color.gray)
            : AnyShapeStyle(
                LinearGradient(
                    colors: [primaryColor, secondaryColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        return ZStack {
            if let value = circularValue {
                Gauge(value: value, in: circularRange) {
                    Image(systemName: circularSymbol)
                } currentValueLabel: {
                    if isStale {
                        VStack(spacing: 0) {
                            Text("\(Int(value))")
                                .monospacedDigit()
                            Text("旧")
                                .font(.system(size: 7, weight: .bold))
                        }
                    } else {
                        Text("\(Int(value))")
                            .monospacedDigit()
                    }
                }
                .tint(gaugeTint)
                .gaugeStyle(.accessoryCircular)
            } else {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.28), lineWidth: 5)
                    VStack(spacing: 1) {
                        Image(systemName: circularSymbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text("--")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .widgetAccentable()
        .widgetURL(deepLink)
    }

#if os(watchOS)
    private var cornerView: some View {
        Group {
            if showsWidgetLabel {
                cornerCurvedContent
            } else {
                cornerCompactContent
            }
        }
            .widgetLabel {
                Text(cornerLabelText)
                    .monospacedDigit()
            }
            .widgetAccentable()
            .accessibilityLabel(cornerAccessibilityText)
        .widgetURL(deepLink)
    }

    private var cornerCurvedContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                Image(systemName: cornerSymbolName)
                    .font(.system(size: 8.5, weight: .bold))
                Text(cornerCurvedText)
                    .monospacedDigit()
            }
            Text(cornerValueText)
                .monospacedDigit()
            Text(templateTitle)
        }
        .font(.system(size: 9, weight: .black, design: .rounded))
        .foregroundStyle(cornerForegroundStyle)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .widgetCurvesContent()
    }

    private var cornerCompactContent: some View {
        VStack(spacing: 1) {
            Image(systemName: cornerSymbolName)
                .font(.system(size: 8.5, weight: .bold))
            Text(cornerValueText)
                .font(.system(size: entry.template == .activity ? 13 : 15, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(cornerCaptionText)
                .font(.system(size: 5.8, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(cornerForegroundStyle)
    }

    private var cornerForegroundStyle: Color {
        if syncState == .empty || isStale {
            return .secondary
        }
        return primaryColor
    }

    private var cornerAccessibilityText: String {
        "\(templateTitle)，\(presentation.primaryMetricTitle) \(presentation.primaryMetricValue)，\(freshnessText)"
    }
#endif

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(hasDisplayContent ? (isStale ? Color.gray : primaryColor) : Color.gray.opacity(0.8))
                    .frame(width: 6, height: 6)
                Text("眠屿 · \(templateTitle)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(freshnessText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isStale ? .secondary : primaryColor)
                    .monospacedDigit()
            }

            if hasMetricData {
                HStack(alignment: .top, spacing: 4) {
                    rectangularMetric(title: presentation.primaryMetricTitle, value: presentation.primaryMetricValue)
                    rectangularMetric(title: presentation.secondaryMetricTitle, value: presentation.secondaryMetricValue)
                    rectangularMetric(title: presentation.tertiaryMetricTitle, value: presentation.tertiaryMetricValue)
                }

                Text(isStale ? String(localized: "\(stateTitle) · 数据较旧") : stateTitle)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isStale ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(emptyStateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .widgetAccentable()
        .widgetURL(deepLink)
    }

    private var inlineView: some View {
        Text(inlineText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .widgetAccentable()
            .widgetURL(deepLink)
    }

    private func rectangularMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
        }
        .frame(minHeight: 22, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortSummaryText(_ text: String?) -> String? {
        guard let cleaned = sanitizedText(text) else { return nil }
        guard !cleaned.isEmpty else { return nil }
        if cleaned.count <= 22 {
            return cleaned
        }
        return String(cleaned.prefix(22)) + "…"
    }

    private func sanitizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private var shortCornerLabel: String {
        presentation.template.cornerLabel
    }

    private func compactCount(_ value: Int) -> String {
        if value >= 10_000 {
            return "\(Int((Double(value) / 1000.0).rounded()))k"
        }
        if value >= 1_000 {
            let compact = Double(value) / 1000.0
            return String(format: compact >= 10 ? "%.0fk" : "%.1fk", compact)
        }
        return "\(value)"
    }
}

private enum ViewText {
    static func trimmed(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength))
    }
}

private enum WatchBrandPalette {
    static let brandBlue = Color(red: 0.12, green: 0.52, blue: 1.0)
    static let brandCyan = Color(red: 0.11, green: 0.80, blue: 0.89)
    static let brandGreen = Color(red: 0.17, green: 0.90, blue: 0.42)
}

/// 应用复杂功能小组件结构体 作为表盘组件扩展里的辅助类型。
/// 负责表盘并发症展示。
struct MianyuComplicationWidget: Widget {
    let kind = AppGroupSchema.Kind.complication

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ComplicationConfigurationIntent.self,
            provider: MianyuComplicationProvider()
        ) { entry in
            MianyuComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("眠屿 表盘组件")
        .description("在表盘上快速查看眠屿的综合、睡眠、活动、补水与体龄状态。")
        .supportedFamilies(supportedFamilies)
    }
}

struct MianyuComplicationOverviewRectangularWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationOverviewRectangular

    var body: some WidgetConfiguration {
        complicationConfiguration(
            kind: kind,
            template: .overview,
            displayName: "眠屿 综合概览",
            description: "适合矩形槽位的综合概览。"
        )
        .supportedFamilies([.accessoryRectangular])
    }
}

struct MianyuComplicationOverviewCircularWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationOverviewCircular

    var body: some WidgetConfiguration {
        complicationConfiguration(kind: kind, template: .overview, displayName: "眠屿 综合", description: "适合圆形槽位的综合状态。")
            .supportedFamilies([.accessoryCircular])
    }
}

#if os(watchOS)
struct MianyuComplicationOverviewCornerWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationOverviewCorner

    var body: some WidgetConfiguration {
        complicationConfiguration(kind: kind, template: .overview, displayName: "眠屿 综合角标", description: "适合角落槽位的综合状态。")
            .supportedFamilies([.accessoryCorner])
    }
}
#endif

struct MianyuComplicationRecoveryRectangularWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationRecoveryRectangular

    var body: some WidgetConfiguration {
        complicationConfiguration(
            kind: kind,
            template: .recovery,
            displayName: "眠屿 恢复概览",
            description: "在矩形槽位显示 HRV、压力和睡眠三项恢复信号。"
        )
        .supportedFamilies([.accessoryRectangular])
    }
}

#if os(watchOS)
struct MianyuComplicationRecoveryCornerWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationRecoveryCorner

    var body: some WidgetConfiguration {
        complicationConfiguration(kind: kind, template: .recovery, displayName: "眠屿 恢复角标", description: "适合角落槽位的恢复分。")
            .supportedFamilies([.accessoryCorner])
    }
}
#endif

struct MianyuComplicationSleepRectangularWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationSleepRectangular

    var body: some WidgetConfiguration {
        complicationConfiguration(
            kind: kind,
            template: .sleep,
            displayName: "眠屿 睡眠概览",
            description: "在矩形槽位显示睡眠时长、得分和目标完成度。"
        )
        .supportedFamilies([.accessoryRectangular])
    }
}

#if os(watchOS)
struct MianyuComplicationSleepCornerWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationSleepCorner

    var body: some WidgetConfiguration {
        complicationConfiguration(kind: kind, template: .sleep, displayName: "眠屿 睡眠角标", description: "适合角落槽位的睡眠状态。")
            .supportedFamilies([.accessoryCorner])
    }
}
#endif

struct MianyuComplicationActivityRectangularWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationActivityRectangular

    var body: some WidgetConfiguration {
        complicationConfiguration(
            kind: kind,
            template: .activity,
            displayName: "眠屿 活动概览",
            description: "在矩形槽位显示步数、能量和运动分钟。"
        )
        .supportedFamilies([.accessoryRectangular])
    }
}

struct MianyuComplicationHydrationRectangularWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationHydrationRectangular

    var body: some WidgetConfiguration {
        complicationConfiguration(
            kind: kind,
            template: .hydration,
            displayName: "眠屿 补水概览",
            description: "在矩形槽位显示饮水完成度和咖啡因余量。"
        )
        .supportedFamilies([.accessoryRectangular])
    }
}

struct MianyuComplicationBodyAgeRectangularWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationBodyAgeRectangular

    var body: some WidgetConfiguration {
        complicationConfiguration(
            kind: kind,
            template: .bodyAge,
            displayName: "眠屿 体龄概览",
            description: "在矩形槽位显示体龄状态与摘要。"
        )
        .supportedFamilies([.accessoryRectangular])
    }
}

struct MianyuComplicationSleepCircularWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationSleepCircular

    var body: some WidgetConfiguration {
        complicationConfiguration(kind: kind, template: .sleep, displayName: "眠屿 睡眠", description: "适合圆形槽位的睡眠概览。")
            .supportedFamilies([.accessoryCircular])
    }
}

struct MianyuComplicationActivityCircularWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationActivityCircular

    var body: some WidgetConfiguration {
        complicationConfiguration(kind: kind, template: .activity, displayName: "眠屿 活动", description: "适合圆形槽位的活动概览。")
            .supportedFamilies([.accessoryCircular])
    }
}

struct MianyuComplicationRecoveryCircularWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationRecoveryCircular

    var body: some WidgetConfiguration {
        complicationConfiguration(kind: kind, template: .recovery, displayName: "眠屿 恢复分", description: "适合圆形槽位的恢复分概览。")
            .supportedFamilies([.accessoryCircular])
    }
}

struct MianyuComplicationHydrationCircularWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationHydrationCircular

    var body: some WidgetConfiguration {
        complicationConfiguration(kind: kind, template: .hydration, displayName: "眠屿 补水", description: "适合圆形槽位的补水完成度。")
            .supportedFamilies([.accessoryCircular])
    }
}

struct MianyuComplicationBodyAgeCircularWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationBodyAgeCircular

    var body: some WidgetConfiguration {
        complicationConfiguration(kind: kind, template: .bodyAge, displayName: "眠屿 体龄", description: "适合圆形槽位的体龄状态。")
            .supportedFamilies([.accessoryCircular])
    }
}

#if os(watchOS)
struct MianyuComplicationHydrationCornerWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationHydrationCorner

    var body: some WidgetConfiguration {
        complicationConfiguration(kind: kind, template: .hydration, displayName: "眠屿 补水角标", description: "适合角落槽位的补水完成度。")
            .supportedFamilies([.accessoryCorner])
    }
}
#endif

#if os(watchOS)
struct MianyuComplicationBodyAgeCornerWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationBodyAgeCorner

    var body: some WidgetConfiguration {
        complicationConfiguration(kind: kind, template: .bodyAge, displayName: "眠屿 体龄角标", description: "适合角落槽位的体龄状态。")
            .supportedFamilies([.accessoryCorner])
    }
}
#endif

#if os(watchOS)
struct MianyuComplicationActivityCornerWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationActivityCorner

    var body: some WidgetConfiguration {
        complicationConfiguration(kind: kind, template: .activity, displayName: "眠屿 健身记录", description: "适合 corner 槽位的活动指标。")
            .supportedFamilies([.accessoryCorner])
    }
}
#endif

private func complicationConfiguration(
    kind: String,
    template: ComplicationTemplateStyle,
    displayName: LocalizedStringResource,
    description: LocalizedStringResource
) -> some WidgetConfiguration {
    StaticConfiguration(
        kind: kind,
        provider: FixedTemplateComplicationProvider(template: template)
    ) { entry in
        MianyuComplicationView(entry: entry)
            .containerBackground(.clear, for: .widget)
    }
    .configurationDisplayName(displayName)
    .description(description)
}

private struct FixedTemplateComplicationProvider: TimelineProvider {
    typealias Entry = MianyuComplicationEntry

    let template: ComplicationTemplateStyle

    func placeholder(in context: Context) -> MianyuComplicationEntry {
        .sample(for: template)
    }

    func getSnapshot(in context: Context, completion: @escaping (MianyuComplicationEntry) -> Void) {
        let entry = forceTemplate(makeBaseEntry(date: Date()))
        if context.isPreview, entry.hasDisplayContent == false {
            completion(.sample(for: template))
        } else {
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MianyuComplicationEntry>) -> Void) {
        let now = Date()
        let entry = forceTemplate(makeBaseEntry(date: now))
        let nextUpdate = nextRefreshDate(now: now, entry: entry)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func forceTemplate(_ entry: MianyuComplicationEntry) -> MianyuComplicationEntry {
        MianyuComplicationEntry(
            date: entry.date,
            template: template,
            heartRate: entry.heartRate,
            hrv: entry.hrv,
            stress: entry.stress,
            stressTrend: entry.stressTrend,
            sleepDurationMinutes: entry.sleepDurationMinutes,
            sleepScore: entry.sleepScore,
            sleepCompletionRate: entry.sleepCompletionRate,
            sleepSnoreIntensity: entry.sleepSnoreIntensity,
            sleepSnoreDurationMinutes: entry.sleepSnoreDurationMinutes,
            steps: entry.steps,
            activeEnergy: entry.activeEnergy,
            exerciseMinutes: entry.exerciseMinutes,
            standHours: entry.standHours,
            activityCompletionRate: entry.activityCompletionRate,
            waterIntakeMl: entry.waterIntakeMl,
            waterTargetMl: entry.waterTargetMl,
            waterCompletionRate: entry.waterCompletionRate,
            caffeineRemainedMg: entry.caffeineRemainedMg,
            bodyAgeValueYears: entry.bodyAgeValueYears,
            bodyAgeStatusText: entry.bodyAgeStatusText,
            healthSummary: entry.healthSummary,
            lastSyncTime: entry.lastSyncTime,
            isStale: entry.isStale
        )
    }

    private func makeBaseEntry(date: Date) -> MianyuComplicationEntry {
        makeComplicationEntry(date: date, template: template)
    }

    private func nextRefreshDate(now: Date, entry: MianyuComplicationEntry) -> Date {
        if let refreshAt = AppGroupSnapshotStore.load()?.freshness(for: entry.template.sharedTemplate).nextRefreshDate(from: now),
           refreshAt > now {
            return refreshAt
        }

        let fallbackMinutes = entry.isStale ? 15 : 30
        return Calendar.current.date(byAdding: .minute, value: fallbackMinutes, to: now) ?? now.addingTimeInterval(TimeInterval(fallbackMinutes * 60))
    }
}

private let supportedFamilies: [WidgetFamily] = {
    var families: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular, .accessoryInline]
#if os(watchOS)
    families.append(.accessoryCorner)
#endif
    return families
}()

private extension MianyuComplicationEntry {
    var hasDisplayContent: Bool {
        heartRate != nil
            || hrv != nil
            || stress != nil
            || sleepDurationMinutes != nil
            || steps != nil
            || waterIntakeMl != nil
            || bodyAgeValueYears != nil
            || bodyAgeStatusText?.isEmpty == false
            || healthSummary?.isEmpty == false
    }

    static func sample(for template: ComplicationTemplateStyle) -> MianyuComplicationEntry {
        switch template {
        case .followDefault, .overview: return .overviewSample
        case .recovery: return .recoverySample
        case .sleep: return .sleepSample
        case .activity: return .activitySample
        case .hydration: return .hydrationSample
        case .bodyAge: return .bodyAgeSample
        }
    }

    static var overviewSample: MianyuComplicationEntry {
        MianyuComplicationEntry(
            date: .now,
            template: .overview,
            heartRate: 72,
            hrv: 55,
            stress: 42,
            stressTrend: String(localized: "稳定"),
            sleepDurationMinutes: 456,
            sleepScore: 84,
            sleepCompletionRate: 0.95,
            sleepSnoreIntensity: "low",
            sleepSnoreDurationMinutes: 6,
            steps: 6380,
            activeEnergy: 420,
            exerciseMinutes: 34,
            standHours: 8,
            activityCompletionRate: 0.75,
            waterIntakeMl: 1400,
            waterTargetMl: 2000,
            waterCompletionRate: 0.7,
            caffeineRemainedMg: 60,
            bodyAgeValueYears: 27.4,
            bodyAgeStatusText: String(localized: "年轻于实际年龄"),
            healthSummary: String(localized: "恢复在线，适合正常推进今天计划。"),
            lastSyncTime: .now,
            isStale: false
        )
    }

    static var recoverySample: MianyuComplicationEntry {
        MianyuComplicationEntry(
            date: .now,
            template: .recovery,
            heartRate: 78,
            hrv: 62,
            stress: 24,
            stressTrend: String(localized: "回落"),
            sleepDurationMinutes: 430,
            sleepScore: 88,
            sleepCompletionRate: 0.9,
            sleepSnoreIntensity: "none",
            sleepSnoreDurationMinutes: 0,
            steps: 5200,
            activeEnergy: 360,
            exerciseMinutes: 26,
            standHours: 7,
            activityCompletionRate: 0.68,
            waterIntakeMl: 1500,
            waterTargetMl: 2000,
            waterCompletionRate: 0.75,
            caffeineRemainedMg: 48,
            bodyAgeValueYears: 26.9,
            bodyAgeStatusText: String(localized: "年轻于实际年龄"),
            healthSummary: String(localized: "恢复不错，适合继续推进今天计划。"),
            lastSyncTime: .now,
            isStale: false
        )
    }

    static var sleepSample: MianyuComplicationEntry {
        MianyuComplicationEntry(
            date: .now,
            template: .sleep,
            heartRate: 66,
            hrv: 58,
            stress: 33,
            stressTrend: String(localized: "稳定"),
            sleepDurationMinutes: 472,
            sleepScore: 91,
            sleepCompletionRate: 0.98,
            sleepSnoreIntensity: "low",
            sleepSnoreDurationMinutes: 4,
            steps: 4300,
            activeEnergy: 280,
            exerciseMinutes: 18,
            standHours: 6,
            activityCompletionRate: 0.52,
            waterIntakeMl: 1200,
            waterTargetMl: 2000,
            waterCompletionRate: 0.6,
            caffeineRemainedMg: 80,
            bodyAgeValueYears: 27.2,
            bodyAgeStatusText: String(localized: "年轻于实际年龄"),
            healthSummary: String(localized: "睡眠良好，白天保持节奏即可。"),
            lastSyncTime: .now,
            isStale: false
        )
    }

    static var activitySample: MianyuComplicationEntry {
        MianyuComplicationEntry(
            date: .now,
            template: .activity,
            heartRate: 74,
            hrv: 46,
            stress: 41,
            stressTrend: String(localized: "平稳"),
            sleepDurationMinutes: 440,
            sleepScore: 82,
            sleepCompletionRate: 0.92,
            sleepSnoreIntensity: "medium",
            sleepSnoreDurationMinutes: 12,
            steps: 8120,
            activeEnergy: 520,
            exerciseMinutes: 42,
            standHours: 9,
            activityCompletionRate: 0.86,
            waterIntakeMl: 1100,
            waterTargetMl: 2000,
            waterCompletionRate: 0.55,
            caffeineRemainedMg: 90,
            bodyAgeValueYears: 27.5,
            bodyAgeStatusText: String(localized: "年轻于实际年龄"),
            healthSummary: String(localized: "活动完成度不错，保持当前步调。"),
            lastSyncTime: .now,
            isStale: false
        )
    }

    static var hydrationSample: MianyuComplicationEntry {
        MianyuComplicationEntry(
            date: .now,
            template: .hydration,
            heartRate: 70,
            hrv: 50,
            stress: 36,
            stressTrend: String(localized: "稳定"),
            sleepDurationMinutes: 418,
            sleepScore: 79,
            sleepCompletionRate: 0.87,
            sleepSnoreIntensity: "low",
            sleepSnoreDurationMinutes: 7,
            steps: 5900,
            activeEnergy: 390,
            exerciseMinutes: 29,
            standHours: 8,
            activityCompletionRate: 0.66,
            waterIntakeMl: 1650,
            waterTargetMl: 2000,
            waterCompletionRate: 0.82,
            caffeineRemainedMg: 32,
            bodyAgeValueYears: 27.0,
            bodyAgeStatusText: String(localized: "年轻于实际年龄"),
            healthSummary: String(localized: "补水接近目标，继续维持即可。"),
            lastSyncTime: .now,
            isStale: false
        )
    }

    static var bodyAgeSample: MianyuComplicationEntry {
        MianyuComplicationEntry(
            date: .now,
            template: .bodyAge,
            heartRate: 69,
            hrv: 53,
            stress: 29,
            stressTrend: String(localized: "下降"),
            sleepDurationMinutes: 450,
            sleepScore: 86,
            sleepCompletionRate: 0.94,
            sleepSnoreIntensity: "none",
            sleepSnoreDurationMinutes: 0,
            steps: 7200,
            activeEnergy: 470,
            exerciseMinutes: 38,
            standHours: 9,
            activityCompletionRate: 0.8,
            waterIntakeMl: 1380,
            waterTargetMl: 2000,
            waterCompletionRate: 0.69,
            caffeineRemainedMg: 58,
            bodyAgeValueYears: 26.8,
            bodyAgeStatusText: String(localized: "年轻于实际年龄"),
            healthSummary: String(localized: "体龄状态良好，继续保持睡眠与活动节奏。"),
            lastSyncTime: .now,
            isStale: false
        )
    }

    static var emptySample: MianyuComplicationEntry {
        MianyuComplicationEntry(
            date: .now,
            template: .overview,
            heartRate: nil,
            hrv: nil,
            stress: nil,
            stressTrend: nil,
            sleepDurationMinutes: nil,
            sleepScore: nil,
            sleepCompletionRate: nil,
            sleepSnoreIntensity: nil,
            sleepSnoreDurationMinutes: nil,
            steps: nil,
            activeEnergy: nil,
            exerciseMinutes: nil,
            standHours: nil,
            activityCompletionRate: nil,
            waterIntakeMl: nil,
            waterTargetMl: nil,
            waterCompletionRate: nil,
            caffeineRemainedMg: nil,
            bodyAgeValueYears: nil,
            bodyAgeStatusText: nil,
            healthSummary: nil,
            lastSyncTime: nil,
            isStale: false
        )
    }
}
