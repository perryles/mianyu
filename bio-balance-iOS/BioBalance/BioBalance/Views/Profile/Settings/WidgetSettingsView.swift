/// WidgetSettingsView 由「应用设置 → 手机小组件」入口调用。
/// 负责读取 Widget 共享快照，展示真实预览、内容说明与添加教程。

import SwiftUI
import HealthKit

struct WidgetSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHowToAdd = false
    @State private var preview = WidgetSettingsPreview.load()

    var body: some View {
        ZStack {
            ReportsSoftBackground()
            widgetPageBackground

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    heroCard
                    previewCard
                    contentCard
                    tutorialCard
                }
                .padding(Theme.Layout.padding)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("手机小组件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showHowToAdd) {
            NavigationStack {
                HowToAddWidgetsView()
            }
        }
        .onAppear(perform: refreshPreview)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshPreview()
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("综合状态")
                .font(.appSystem(size: 32, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            Text("推荐优先添加综合状态组件。它会自动在睡眠、恢复、压力、活动和补水之间挑出今天最值得先看的重点；没有数据或数据过旧时，不会给出误导性的强结论。")
                .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                heroPill(title: "推荐", value: "综合状态", tint: Theme.Colors.mintGreen)
                heroPill(title: "尺寸", value: "小 / 中 / 大", tint: Theme.Colors.accentBlue)
                heroPill(title: "聚焦", value: "自动 / 睡眠等", tint: Theme.Colors.accentBlue)
            }

            Button {
                showHowToAdd = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.square.on.square")
                        .font(.appSystem(size: 15, weight: .bold))
                    Text("查看添加方式")
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.Colors.accentBlue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("真实预览")
                        .font(.appSystem(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("这里直接读取共享快照，并复用综合 Widget 的同一套状态解析逻辑。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                statusPill(text: preview.syncStatusText, tint: preview.syncStatusTint)
            }

            WidgetSettingsMediumPreviewCard(model: preview.card)
        }
        .padding(20)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("显示哪些内容")
                .font(.appSystem(size: 22, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            contentRow(
                title: "顶部",
                detail: "组件标题和同步状态，让你先知道这张卡的数据能不能直接信。"
            )
            contentRow(
                title: "主结论",
                detail: "默认自动在睡眠、恢复、压力、活动、补水之间选出今天最重要的结论。"
            )
            contentRow(
                title: "指标区",
                detail: "最多显示 3 个关键值，避免把中号卡塞成信息拼贴。"
            )
            contentRow(
                title: "空状态 / 过期状态",
                detail: "没有数据时显示等待同步；同步超过约 6 小时时，统一降级为“数据较旧”。"
            )
            contentRow(
                title: "聚焦模式",
                detail: "你可以在添加组件时手动聚焦睡眠、恢复、压力、活动或补水，也可以保持自动模式。"
            )
        }
        .padding(20)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private var tutorialCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("如何添加到桌面")
                        .font(.appSystem(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("系统里会优先看到综合状态，也会保留几个专题组件用于补充场景。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                Button("查看步骤") {
                    showHowToAdd = true
                }
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.accentBlue)
            }

            StepRow(number: "1", text: "在 iPhone 主屏幕长按空白处，直到图标开始抖动。")
            StepRow(number: "2", text: "点击左上角“+”，搜索眠屿。")
            StepRow(number: "3", text: "优先选择“综合状态”组件，并按需要选择小号、中号或大号。")
            StepRow(number: "4", text: "如果需要，也可以在添加时把组件聚焦到睡眠、恢复、压力、活动或补水。")
            StepRow(number: "5", text: "放到桌面后点击组件，会直接进入 App 的今日总览页。")
        }
        .padding(20)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private var widgetPageBackground: some View {
        Color.clear
    }

    private func heroPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(value)
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.1), in: Capsule())
    }

    private func contentRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(detail)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func refreshPreview() {
        preview = WidgetSettingsPreview.load()
    }
}

private struct WidgetSettingsMediumPreviewCard: View {
    let model: WidgetSettingsPreviewCard

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    previewBadge(model.badge, tint: model.accent)
                    Image(systemName: model.symbol)
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(model.accent)
                }

                Text(model.title)
                    .font(.appSystem(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(model.accent)
                    .lineLimit(2)

                Text(model.summary)
                    .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    previewMetric(title: model.secondaryMetricTitle, value: model.secondaryMetricValue, tint: model.accent)
                    previewMetric(title: model.tertiaryMetricTitle, value: model.tertiaryMetricValue, tint: model.secondary)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                previewScoreRing(
                    valueText: model.primaryMetricValue,
                    subtitle: model.primaryMetricTitle,
                    progress: model.progress,
                    accent: model.accent,
                    secondary: model.secondary
                )

                previewMetric(title: "摘要", value: model.detail, tint: model.secondary)
                    .frame(width: 108)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .frame(height: 196)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.98), model.accent.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.88), lineWidth: 1)
        )
    }
}

private func previewBadge(_ text: String, tint: Color) -> some View {
    Text(text)
        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
        .foregroundColor(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
}

private func previewMetric(title: String, value: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.Colors.textTertiary)
        Text(value)
            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(Theme.Colors.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .background(Theme.Colors.surface.opacity(0.84), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(tint.opacity(0.12), lineWidth: 1)
    )
}

private func previewScoreRing(
    valueText: String,
    subtitle: String,
    progress: Double,
    accent: Color,
    secondary: Color
) -> some View {
    ZStack {
        Circle()
            .stroke(accent.opacity(0.14), lineWidth: 14)
        Circle()
            .trim(from: 0, to: max(0.08, min(1, progress)))
            .stroke(
                AngularGradient(colors: [secondary.opacity(0.65), accent, secondary], center: .center),
                style: StrokeStyle(lineWidth: 14, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))

        VStack(spacing: 2) {
            Text(valueText)
                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                .foregroundColor(accent)
            Text(subtitle)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }
    .frame(width: 96, height: 96)
}

private struct StepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.appSystem(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Theme.Colors.mintGreen)
                .clipShape(Circle())

            Text(text)
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(4)
        }
        .padding(.vertical, 4)
    }
}

struct HowToAddWidgetsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("如何在主屏幕添加小组件")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                VStack(alignment: .leading, spacing: 12) {
                    StepRow(number: "1", text: "在主屏幕长按任意空白处，直到应用图标开始抖动。")
                    StepRow(number: "2", text: "点击左上角的“+”按钮。")
                    StepRow(number: "3", text: "在搜索栏输入“眠屿”或向下滚动找到应用。")
                    StepRow(number: "4", text: "优先选择“综合状态”组件，并按需要选择小号、中号或大号。")
                    StepRow(number: "5", text: "如需更明确的视角，可在添加时选择睡眠、恢复、压力、活动或补水聚焦。")
                    StepRow(number: "6", text: "拖动到合适位置，点击“完成”即可。")
                }
            }
            .padding(Theme.Layout.padding)
        }
        .background {
            ReportsSoftBackground()
        }
        .navigationTitle("添加小组件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
    }
}

struct WidgetSettingsPreviewCard {
    let badge: String
    let symbol: String
    let title: String
    let summary: String
    let detail: String
    let primaryMetricTitle: String
    let primaryMetricValue: String
    let secondaryMetricTitle: String
    let secondaryMetricValue: String
    let tertiaryMetricTitle: String
    let tertiaryMetricValue: String
    let accent: Color
    let secondary: Color
    let progress: Double
}

struct WidgetSettingsPreview {
    let card: WidgetSettingsPreviewCard
    let syncStatusText: String
    let syncStatusTint: Color

    static func load() -> WidgetSettingsPreview {
        let shared = AppGroupManager.shared
        let snapshot = WidgetSettingsSnapshot(
            heartRate: shared.getLatestHeartRate(),
            hrv: shared.getLatestHRV(),
            stress: shared.getLatestStress(),
            stressTrend: shared.getStressTrend(),
            lastSyncTime: shared.getLastSyncTime(),
            waterIntakeMl: shared.getWaterIntakeMl(),
            waterTargetMl: shared.getWaterTargetMl(),
            waterCompletionRate: shared.getWaterCompletionRate(),
            steps: shared.getSteps(),
            activeEnergy: shared.getActiveEnergy(),
            activityCompletionRate: shared.getActivityCompletionRate(),
            sleepDurationMinutes: shared.getSleepDurationMinutes(),
            sleepScore: shared.getSleepScore(),
            sleepDurationCompletionRate: shared.getSleepDurationCompletionRate()
        )

        let descriptor = widgetSettingsDescriptor(for: snapshot)
        return WidgetSettingsPreview(
            card: descriptor,
            syncStatusText: widgetSettingsSyncStatusText(for: snapshot.lastSyncTime),
            syncStatusTint: widgetSettingsSyncStatusTint(for: snapshot.lastSyncTime)
        )
    }
}

private struct WidgetSettingsSnapshot {
    let heartRate: Double?
    let hrv: Double?
    let stress: Double?
    let stressTrend: String?
    let lastSyncTime: Date?
    let waterIntakeMl: Double?
    let waterTargetMl: Int?
    let waterCompletionRate: Double?
    let steps: Int?
    let activeEnergy: Int?
    let activityCompletionRate: Double?
    let sleepDurationMinutes: Int?
    let sleepScore: Int?
    let sleepDurationCompletionRate: Double?
}

private enum WidgetSettingsDataState {
    case missing
    case stale
    case fresh
}

private func widgetSettingsDescriptor(for snapshot: WidgetSettingsSnapshot) -> WidgetSettingsPreviewCard {
    let resolved = WidgetOverallResolver.resolve(
        snapshot: SharedOverallWidgetSnapshot(
            heartRate: snapshot.heartRate,
            hrv: snapshot.hrv,
            stress: snapshot.stress,
            stressState: nil,
            stressExplanationCode: nil,
            stressConfidence: nil,
            stressTrend: snapshot.stressTrend,
            lastSyncTime: snapshot.lastSyncTime,
            waterIntakeMl: snapshot.waterIntakeMl,
            waterTargetMl: snapshot.waterTargetMl,
            waterCompletionRate: snapshot.waterCompletionRate,
            caffeineRemainedMg: nil,
            steps: snapshot.steps,
            activeEnergy: snapshot.activeEnergy,
            activityCompletionRate: snapshot.activityCompletionRate,
            sleepDurationMinutes: snapshot.sleepDurationMinutes,
            sleepScore: snapshot.sleepScore,
            sleepDurationCompletionRate: snapshot.sleepDurationCompletionRate
        )
    )

    let accent: Color
    let secondary: Color
    switch resolved.tone {
    case .relaxed:
        accent = Theme.Colors.mintGreen
        secondary = Theme.Colors.accentBlue
    case .steady:
        accent = Theme.Colors.accentBlue
        secondary = Theme.Colors.mintGreen
    case .mild:
        accent = Theme.Colors.accentOrange
        secondary = Theme.Colors.mintGreen
    case .caution, .high:
        accent = Theme.Colors.accentOrange
        secondary = Theme.Colors.accentBlue
    case .waiting:
        accent = Theme.Colors.textTertiary
        secondary = Theme.Colors.accentBlue
    }

    return WidgetSettingsPreviewCard(
        badge: "综合状态预览",
        symbol: resolved.symbolName,
        title: resolved.title,
        summary: resolved.summary,
        detail: resolved.detail,
        primaryMetricTitle: resolved.primaryMetricTitle,
        primaryMetricValue: resolved.primaryMetricValue,
        secondaryMetricTitle: resolved.secondaryMetricTitle,
        secondaryMetricValue: resolved.secondaryMetricValue,
        tertiaryMetricTitle: resolved.tertiaryMetricTitle,
        tertiaryMetricValue: resolved.tertiaryMetricValue,
        accent: accent,
        secondary: secondary,
        progress: resolved.progress
    )
}

private func widgetSettingsDataState(for lastSyncTime: Date?) -> WidgetSettingsDataState {
    switch WidgetOverallResolver.dataState(for: lastSyncTime) {
    case .fresh:
        return .fresh
    case .stale:
        return .stale
    case .missing:
        return .missing
    }
}

private func widgetSettingsSyncStatusText(for lastSyncTime: Date?) -> String {
    switch widgetSettingsDataState(for: lastSyncTime) {
    case .fresh:
        return "已同步"
    case .stale:
        return String(localized: "数据较旧")
    case .missing:
        return String(localized: "待同步")
    }
}

private func widgetSettingsSyncStatusTint(for lastSyncTime: Date?) -> Color {
    switch widgetSettingsDataState(for: lastSyncTime) {
    case .fresh:
        return Theme.Colors.mintGreen
    case .stale:
        return Theme.Colors.accentOrange
    case .missing:
        return Theme.Colors.textTertiary
    }
}

/// WidgetSettingsView_Previews 用于本地预览 WidgetSettingsView 的界面效果。
struct WidgetSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            WidgetSettingsView()
        }
    }
}
