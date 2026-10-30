/// GeneralSettingsView 由 SettingsView 调用，作为「通用」三级设置页。
/// 负责管理字体大小、时间格式、一周起始日、减少动效与各业务域同步开关。

import SwiftUI

/// General Settings View 由 [SettingsView] 调用，作为设置页里的“通用”三级页面入口。
/// 负责承载字体大小、时间格式、一周起始日和减少装饰动效等基础显示偏好设置。
struct GeneralSettingsView: View {
    @AppStorage("app_time_format_preference") private var timeFormatPreference: String = "24h"
    @AppStorage("app_week_start_monday") private var weekStartsOnMonday: Bool = true
    @AppStorage("app_reduce_motion_preference") private var reduceMotionPreference: Bool = false
    @AppStorage(CloudKitDataPolicy.PreferenceKey.drinkExperienceSyncEnabled) private var drinkExperienceSyncEnabled: Bool = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.sleepSummarySyncEnabled) private var sleepSummarySyncEnabled: Bool = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled) private var medicationHealthSyncEnabled: Bool = true
    @Environment(AppFontScaleStore.self) private var appFontScaleStore

    private var appFontScaleLevel: AppFontScaleLevel {
        appFontScaleStore.level
    }

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground
                .ignoresSafeArea()

            AdaptivePageScrollView(topPadding: 12, bottomPadding: 88) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionCard(title: "显示与偏好") {
                        VStack(spacing: 0) {
                            SettingsSegmentedControlRow(
                                icon: "textformat.size",
                                tint: Theme.Colors.accentBlue,
                                title: "字体大小",
                                subtitle: "支持四档显示",
                                control: fontScaleControl
                            )

                            Divider().padding(.leading, 86)

                            SettingsSegmentedControlRow(
                                icon: "clock",
                                tint: Color(hex: "7D8BFF"),
                                title: "时间格式",
                                subtitle: "调整应用内时间显示",
                                control:
                                    Picker("时间格式", selection: $timeFormatPreference) {
                                        Text("24 小时").tag("24h")
                                        Text("12 小时").tag("12h")
                                    }
                                    .pickerStyle(.segmented)
                            )

                            Divider().padding(.leading, 86)

                            SettingsSegmentedControlRow(
                                icon: "calendar",
                                tint: Color(hex: "FFB340"),
                                title: "一周起始日",
                                subtitle: "按习惯组织周视图",
                                control:
                                    Picker("一周起始日", selection: $weekStartsOnMonday) {
                                        Text("周一").tag(true)
                                        Text("周日").tag(false)
                                    }
                                    .pickerStyle(.segmented)
                            )

                            Divider().padding(.leading, 86)

                            SettingsToggleDetailRow(
                                icon: "sparkles.rectangle.stack",
                                tint: Theme.Colors.textSecondary,
                                title: "减少装饰动效",
                                subtitle: "弱化渐变和装饰动画",
                                isOn: $reduceMotionPreference
                            )

                            Divider().padding(.leading, 86)

                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    Task { await UIApplication.shared.open(url) }
                                }
                            } label: {
                                SettingsIconRow(title: "语言", symbol: "globe", tint: Color(hex: "7D8BFF"), subtitle: currentLanguageDisplayName)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SettingsSectionCard(title: "数据与权限") {
                        VStack(spacing: 0) {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    Task { await UIApplication.shared.open(url) }
                                }
                            } label: {
                                SettingsIconRow(title: "健康数据授权", symbol: "checkmark.shield", tint: Theme.Colors.mintGreen, subtitle: "允许读取心率、睡眠、活动等健康数据")
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 86)

                            SettingsToggleDetailRow(
                                icon: "icloud.fill",
                                tint: Theme.Colors.accentBlue,
                                title: "iCloud 餐饮记录",
                                subtitle: "同步结构化记录，不上传图片、精确位置或 AI 元数据",
                                isOn: $drinkExperienceSyncEnabled
                            )

                            Divider().padding(.leading, 86)

                            SettingsToggleDetailRow(
                                icon: "bed.double.fill",
                                tint: Color(hex: "7D8BFF"),
                                title: "iCloud 睡眠摘要",
                                subtitle: "仅同步评分、时段和规则码，不上传音频或片段",
                                isOn: $sleepSummarySyncEnabled
                            )

                            Divider().padding(.leading, 86)

                            SettingsToggleDetailRow(
                                icon: "cross.case.fill",
                                tint: Color(hex: "536FE8"),
                                title: "iCloud 药症资料",
                                subtitle: "同步确认后的处方、药物和病症，不上传原图或识别全文",
                                isOn: $medicationHealthSyncEnabled
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("通用")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: drinkExperienceSyncEnabled) { _, isEnabled in
            guard isEnabled else { return }
            Task { await DrinkExperienceStore.shared.synchronizePrivateCloud() }
        }
        .onChange(of: sleepSummarySyncEnabled) { _, isEnabled in
            guard isEnabled else { return }
            Task { await SleepMonitoringOrchestrator.shared.restoreState() }
        }
        .onChange(of: medicationHealthSyncEnabled) { _, isEnabled in
            guard isEnabled else { return }
            Task { await MedicationHealthCloudSyncCoordinator.shared.synchronize() }
        }
    }

    private var fontScaleControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("字体大小", selection: fontScaleBinding) {
                ForEach(AppFontScaleLevel.allCases) { level in
                    Text(level.displayTitle).tag(level.rawValue)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Text(fontPreviewText)
                    .font(Theme.Typography.scaled(size: 13, weight: .semibold, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.Colors.secondarySurface, in: Capsule())

                Spacer(minLength: 0)

                Text(appFontScaleLevel.displayTitle)
                    .font(Theme.Typography.scaled(size: 12, weight: .bold, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.accentBlue)
            }
        }
    }

    private var fontScaleBinding: Binding<Int> {
        Binding(
            get: { appFontScaleLevel.rawValue },
            set: { newValue in
                guard let level = AppFontScaleLevel(rawValue: newValue) else { return }
                appFontScaleStore.update(level: level)
            }
        )
    }

    private var fontPreviewText: String { appFontScaleLevel.previewText }

    /// 当前生效的应用语言名称，跟随系统的按 App 语言设置。
    private var currentLanguageDisplayName: String {
        switch Bundle.main.preferredLocalizations.first {
        case "zh-Hant":
            return String(localized: "繁體中文（前往系统设置切换）")
        case "en":
            return String(localized: "English（前往系统设置切换）")
        default:
            return String(localized: "简体中文（前往系统设置切换）")
        }
    }
}
