/// ProfileInlineContent 由 ProfileView 调用，承载「我的」页面全部子页面的内联展示内容。
/// 将原来需要 NavigationLink 跳转的 12+ 个子页面内容，全部以 section 卡片形式直接渲染在同一个可滚动页面中。
/// 对于子页面内部存在 workspace 切换（如 MyDeviceView、HelpFeedbackView）或三级页面跳转（如 SettingsView）的情况，
/// 直接全部展开为平铺内容，不做任何切换。

import SwiftUI
import UIKit
import UserNotifications
import CloudKit

// MARK: - 我的信息（ProfileDetailView 内联）

/// ProfileDetailInlineSection 由 ProfileView 直接调用，以 section 形式展示「我的信息」全部内容。
struct ProfileDetailInlineSection: View {
    @AppStorage("userNickname") private var storedNickname: String = ""
    @AppStorage("watchThemeId") private var watchThemeId: String = "joey"

    @State private var healthSexText = String(localized: "读取中")
    @State private var healthAgeText = ""

    private let ink = Color(hex: "2E3135")
    private let cardBorder = Theme.Colors.surfaceBorder
    private let accessoryColumns = [
        GridItem(.adaptive(minimum: 50, maximum: 58), spacing: 18)
    ]

    var body: some View {
        VStack(spacing: 16) {
            // 头像
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Theme.Colors.mintGreen.opacity(0.16))
                    .frame(width: 110, height: 110)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))

                InlineAccessoryPortrait(accessory: selectedAccessory)
                    .frame(width: 98, height: 98)
                    .clipShape(Circle())

                ZStack {
                    Circle().fill(Color.white).frame(width: 40, height: 40)
                    Circle().fill(Color(hex: "6B6E73")).frame(width: 29, height: 29)
                    Image(systemName: "camera.fill")
                        .font(.appSystem(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .offset(x: 2, y: -5)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            // 昵称
            VStack(alignment: .leading, spacing: 14) {
                Text("昵称")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                HStack(spacing: 12) {
                    TextField("你的昵称", text: $storedNickname)
                        .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(ink)
                        .autocorrectionDisabled(true)

                    Spacer(minLength: 0)

                    Image(systemName: "pencil")
                        .font(.appSystem(size: 17, weight: .bold))
                        .foregroundColor(ink)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(inlineCardBg)

            // 头像配饰
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("头像配饰")
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Spacer()
                    Text("仅在手表端显示")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "9B9EA2"))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(InlineProfileAccessory.allCases) { accessory in
                            Button {
                                selectAccessory(accessory)
                            } label: {
                                accessoryOption(accessory)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(inlineCardBg)

            // 我的数据
            VStack(alignment: .leading, spacing: 14) {
                Text("我的数据")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                VStack(spacing: 12) {
                    healthDataRow(title: "年龄", value: healthAgeText)
                    Divider().padding(.leading, 0)
                    healthDataRow(title: "性别", value: healthSexText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(inlineCardBg)

            // 脚注
            HStack(spacing: 6) {
                Text("年龄性别数据来自")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "9AA1A8"))
                Text("苹果健康")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "5579D7"))
                    .underline()
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onAppear { loadHealthProfile() }
    }

    private var inlineCardBg: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(cardBorder, lineWidth: 1))
    }

    private func healthDataRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "6B6F75"))
            Spacer()
            Text(value)
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .foregroundColor(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func accessoryOption(_ accessory: InlineProfileAccessory) -> some View {
        let isSelected = accessory.id == selectedAccessory.id
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color(hex: "E7F8FF"))
                    .frame(width: 48, height: 48)
                InlineAccessoryPortrait(accessory: accessory)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                if isSelected {
                    Circle()
                        .fill(Color(hex: "20C27A"))
                        .frame(width: 20, height: 20)
                        .overlay(Image(systemName: "checkmark").font(.appSystem(size: 11, weight: .black)).foregroundColor(.white))
                        .offset(x: -15, y: 26)
                }
            }
            .frame(width: 48, height: 60)
        }
        .accessibilityLabel(accessory.name)
    }

    private var selectedAccessory: InlineProfileAccessory {
        InlineProfileAccessory.allCases.first { $0.id == watchThemeId } ?? .joey
    }

    private func selectAccessory(_ accessory: InlineProfileAccessory) {
        watchThemeId = accessory.id
        AppGroupManager.shared.saveWatchThemeId(accessory.id)
        HealthDataManager.shared.syncWatchThemeSelection(accessory.id)
    }

    private func loadHealthProfile() {
        Task {
            let manager = HealthKitManager.shared
            let age = await manager.fetchChronologicalAge()
            let sex = await manager.fetchBiologicalSexDisplayText()
            await MainActor.run {
                healthAgeText = age.map { "\($0) 岁" } ?? ""
                healthSexText = sex ?? String(localized: "未设定")
            }
        }
    }
}

// MARK: - 我的信息配饰（内联精简版）

private enum InlineProfileAccessory: String, CaseIterable, Identifiable {
    case joey, bubble, flowercat, bearjoy, tiger, piggy

    var id: String { rawValue }

    var name: String {
        switch self {
        case .joey: return "周伊 Joey"
        case .bubble: return "压力泡泡"
        case .flowercat: return "焦绿猫"
        case .bearjoy: return "小熊 joy"
        case .tiger: return "虎虎"
        case .piggy: return "猪傻傻"
        }
    }
}

private struct InlineAccessoryPortrait: View {
    let accessory: InlineProfileAccessory

    var body: some View {
        ZStack {
            Circle().fill(fill)
            switch accessory {
            case .joey:
                Image("ProfileHeaderMascot").resizable().scaledToFit().padding(3)
            case .bubble:
                InlineBubbleAvatar().padding(6)
            case .flowercat:
                InlineFlowerCatAvatar().padding(5)
            case .bearjoy:
                InlineBearAvatar().padding(6)
            case .tiger:
                InlineTigerAvatar().padding(5)
            case .piggy:
                InlinePigAvatar().padding(6)
            }
        }
    }

    private var fill: Color {
        switch accessory {
        case .joey: return Color(hex: "DDF2F9")
        case .bubble: return Color(hex: "E7F8FF")
        case .flowercat: return Color(hex: "FFF2F7")
        case .bearjoy: return Color(hex: "FFF5E7")
        case .tiger: return Color(hex: "F5F6FF")
        case .piggy: return Color(hex: "FFF4F5")
        }
    }
}

private struct InlineBubbleAvatar: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: "70D5A6"))
            Circle().fill(Color.white.opacity(0.26)).frame(width: 14, height: 14).offset(x: 13, y: -11)
            HStack(spacing: 7) {
                Capsule().fill(Color(hex: "6B8190")).frame(width: 5, height: 12)
                InlineArcEye().stroke(Color(hex: "6B8190"), lineWidth: 2).frame(width: 11, height: 8).scaleEffect(x: -1)
            }.offset(y: -3)
            InlineSmile().stroke(Color(hex: "6B8190"), lineWidth: 2).frame(width: 15, height: 8).offset(y: 9)
        }
    }
}

private struct InlineFlowerCatAvatar: View {
    var body: some View {
        ZStack {
            InlineCatHead().fill(Color.white)
            InlineCatHead().stroke(Color(hex: "42464D").opacity(0.8), lineWidth: 2)
            HStack(spacing: 20) {
                InlineFlower().fill(Color(hex: "FF8FB8")).frame(width: 13, height: 13)
                InlineFlower().fill(Color(hex: "FF8FB8")).frame(width: 13, height: 13)
            }.offset(y: -13)
            InlineFaceMarks()
        }
    }
}

private struct InlineBearAvatar: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: "E8BD82"))
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: "5C4A3A").opacity(0.72), lineWidth: 2)
            Circle().fill(Color(hex: "F8D7A8")).frame(width: 14, height: 14).offset(x: -15, y: -14)
            Circle().fill(Color(hex: "F8D7A8")).frame(width: 14, height: 14).offset(x: 15, y: -14)
            InlineFaceMarks()
            Capsule().fill(Color(hex: "F28C6F")).frame(width: 16, height: 10).offset(y: 11)
        }
    }
}

private struct InlineTigerAvatar: View {
    var body: some View {
        ZStack {
            InlineCatHead().fill(Color.white)
            InlineCatHead().stroke(Color(hex: "343840").opacity(0.82), lineWidth: 2)
            HStack(spacing: 14) {
                Rectangle().fill(Color(hex: "FFB457")).frame(width: 4, height: 18).rotationEffect(.degrees(-18))
                Rectangle().fill(Color(hex: "FFB457")).frame(width: 4, height: 20)
                Rectangle().fill(Color(hex: "FFB457")).frame(width: 4, height: 18).rotationEffect(.degrees(18))
            }.offset(y: -17)
            InlineFaceMarks()
        }
    }
}

private struct InlinePigAvatar: View {
    var body: some View {
        ZStack {
            Ellipse().fill(Color(hex: "FFD6DC")).frame(width: 50, height: 42)
            Ellipse().stroke(Color(hex: "5C4A50").opacity(0.72), lineWidth: 2).frame(width: 50, height: 42)
            Ellipse().fill(Color(hex: "FFA9B5")).frame(width: 22, height: 14).offset(y: 5)
            HStack(spacing: 4) {
                Circle().fill(Color(hex: "5C4A50")).frame(width: 3, height: 3)
                Circle().fill(Color(hex: "5C4A50")).frame(width: 3, height: 3)
            }.offset(y: 5)
            InlineFaceMarks().offset(y: -4)
        }
    }
}

private struct InlineFaceMarks: View {
    var body: some View {
        ZStack {
            HStack(spacing: 14) {
                Circle().fill(Color(hex: "4C6070")).frame(width: 4, height: 7)
                InlineArcEye().stroke(Color(hex: "4C6070"), lineWidth: 2).frame(width: 10, height: 7).scaleEffect(x: -1)
            }.offset(y: -3)
            InlineSmile().stroke(Color(hex: "4C6070"), lineWidth: 2).frame(width: 12, height: 7).offset(y: 8)
        }
    }
}

nonisolated private struct InlineCatHead: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.09))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.04))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.34), control: CGPoint(x: rect.minX + rect.width * 0.13, y: rect.minY + rect.height * 0.13))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.maxY - rect.height * 0.18), control: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.maxY - rect.height * 0.02))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.20, y: rect.maxY - rect.height * 0.18), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.06))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY + rect.height * 0.34), control: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.maxY - rect.height * 0.02))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.27, y: rect.minY + rect.height * 0.04), control: CGPoint(x: rect.maxX - rect.width * 0.13, y: rect.minY + rect.height * 0.13))
        path.closeSubpath()
        return path
    }
}

nonisolated private struct InlineFlower: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<5 {
            let angle = Double(index) * .pi * 2 / 5
            let center = CGPoint(x: rect.midX + cos(angle) * rect.width * 0.22, y: rect.midY + sin(angle) * rect.height * 0.22)
            path.addEllipse(in: CGRect(x: center.x - rect.width * 0.16, y: center.y - rect.height * 0.16, width: rect.width * 0.32, height: rect.height * 0.32))
        }
        path.addEllipse(in: CGRect(x: rect.midX - rect.width * 0.10, y: rect.midY - rect.height * 0.10, width: rect.width * 0.20, height: rect.height * 0.20))
        return path
    }
}

nonisolated private struct InlineArcEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

nonisolated private struct InlineSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

// MARK: - 应用设置内联（通用 + 通知 + 图标 + 小组件 + 缓存）

/// SettingsInlineSection 以 section 形式直接展示应用设置的全部内容，不跳转到三级页面。
struct SettingsInlineSection: View {
    // 通用设置
    @AppStorage("app_time_format_preference") private var timeFormatPreference: String = "24h"
    @AppStorage("app_week_start_monday") private var weekStartsOnMonday: Bool = true
    @AppStorage("app_reduce_motion_preference") private var reduceMotionPreference: Bool = false
    @AppStorage(CloudKitDataPolicy.PreferenceKey.drinkExperienceSyncEnabled) private var drinkExperienceSyncEnabled: Bool = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.sleepSummarySyncEnabled) private var sleepSummarySyncEnabled: Bool = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled) private var medicationHealthSyncEnabled: Bool = true
    @Environment(AppFontScaleStore.self) private var appFontScaleStore

    // 通知设置
    @AppStorage("abnormalHealthAlertsEnabled") private var abnormalHealthAlertsEnabled: Bool = true
    @AppStorage("goalRemindersEnabled") private var goalRemindersEnabled: Bool = true
    @AppStorage("weeklySummaryEnabled") private var weeklySummaryEnabled: Bool = true
    @AppStorage("sleepLackReminderEnabled") private var sleepLackReminderEnabled: Bool = true
    @AppStorage("stressAlertsEnabled") private var stressAlertsEnabled: Bool = true
    @AppStorage("stressDailyCheckInEnabled") private var stressDailyCheckInEnabled: Bool = true
    @State private var managementPreferences = NotificationManagementPreferencesStore.shared.load()
    @State private var notificationsEnabled = true

    // 缓存
    @State private var isClearingCache = false
    @State private var cacheFeedbackMessage = ""
    @State private var cacheSnapshot = AppDataCacheManager.shared.snapshot()
    @State private var showCacheClearConfirm = false

    // 图标
    @State private var selectedIconName: String?

    // 小组件
    @State private var showHowToAdd = false
    @State private var widgetPreview = WidgetSettingsPreview.load()

    private var appFontScaleLevel: AppFontScaleLevel { appFontScaleStore.level }

    var body: some View {
        VStack(spacing: 16) {
            generalSettingsContent
            appIconContent
            widgetContent
            notificationContent
            cacheContent
        }
    }

    // MARK: 通用设置
    private var generalSettingsContent: some View {
        SettingsSectionCard(title: "通用") {
            VStack(spacing: 0) {
                SettingsSegmentedControlRow(
                    icon: "textformat.size", tint: Theme.Colors.accentBlue,
                    title: "字体大小", subtitle: "支持四档显示",
                    control: fontScaleControl
                )
                Divider().padding(.leading, 86)
                SettingsSegmentedControlRow(
                    icon: "clock", tint: Color(hex: "7D8BFF"),
                    title: "时间格式", subtitle: "调整应用内时间显示",
                    control: Picker("时间格式", selection: $timeFormatPreference) {
                        Text("24 小时").tag("24h"); Text("12 小时").tag("12h")
                    }.pickerStyle(.segmented)
                )
                Divider().padding(.leading, 86)
                SettingsSegmentedControlRow(
                    icon: "calendar", tint: Color(hex: "FFB340"),
                    title: "一周起始日", subtitle: "按习惯组织周视图",
                    control: Picker("一周起始日", selection: $weekStartsOnMonday) {
                        Text("周一").tag(true); Text("周日").tag(false)
                    }.pickerStyle(.segmented)
                )
                Divider().padding(.leading, 86)
                SettingsToggleDetailRow(
                    icon: "sparkles.rectangle.stack", tint: Theme.Colors.textSecondary,
                    title: "减少装饰动效", subtitle: "弱化渐变和装饰动画", isOn: $reduceMotionPreference
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
                Text(appFontScaleLevel.previewText)
                    .font(Theme.Typography.scaled(size: 13, weight: .semibold, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.Colors.secondarySurface, in: Capsule())
                Spacer(minLength: 0)
                Text(appFontScaleLevel.displayTitle)
                    .font(Theme.Typography.scaled(size: 12, weight: .bold, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.accentBlue)
            }
        }
    }

    private var fontScaleBinding: Binding<Int> {
        Binding(get: { appFontScaleLevel.rawValue }, set: { newValue in
            guard let level = AppFontScaleLevel(rawValue: newValue) else { return }
            appFontScaleStore.update(level: level)
        })
    }

    private var currentLanguageDisplayName: String {
        switch Bundle.main.preferredLocalizations.first {
        case "zh-Hant": return String(localized: "繁體中文（前往系统设置切换）")
        case "en": return String(localized: "English（前往系统设置切换）")
        default: return String(localized: "简体中文（前往系统设置切换）")
        }
    }

    // MARK: 应用图标
    private var appIconContent: some View {
        SettingsSectionCard(title: "应用图标") {
            HStack(spacing: 16) {
                ForEach(appIcons, id: \.title) { icon in
                    Button { changeIcon(to: icon.name) } label: {
                        VStack(spacing: 8) {
                            Image(icon.previewAssetName)
                                .resizable().scaledToFit()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
                            Text(icon.title)
                                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(selectedIconName == icon.name ? Theme.Colors.mintGreen : Color(hex: "303238"))
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private struct AppIconChoice {
        let name: String?
        let title: String
        let previewAssetName: String
    }
    private var appIcons: [AppIconChoice] {
        [
            .init(name: nil, title: "经典", previewAssetName: "ClassicAppIconPreview"),
            .init(name: "AppIconBalance", title: "活力", previewAssetName: "BalanceAppIconPreview")
        ]
    }
    private func changeIcon(to name: String?) {
        guard UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name)
        selectedIconName = name
    }

    // MARK: 手机小组件
    private var widgetContent: some View {
        SettingsSectionCard(title: "手机小组件") {
            VStack(alignment: .leading, spacing: 12) {
                Text("推荐优先添加综合状态组件。它会自动在睡眠、恢复、压力、活动和补水之间挑出今天最值得先看的重点。")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    widgetPill(title: "推荐", value: "综合状态", tint: Theme.Colors.mintGreen)
                    widgetPill(title: "尺寸", value: "小 / 中 / 大", tint: Theme.Colors.accentBlue)
                }

                Button { showHowToAdd = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.square.on.square").font(.appSystem(size: 13, weight: .bold))
                        Text("查看添加方式").font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Theme.Colors.accentBlue, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .sheet(isPresented: $showHowToAdd) {
            NavigationStack { HowToAddWidgetsView() }
        }
    }

    private func widgetPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.appSystem(size: 10, weight: .bold, design: .rounded)).foregroundColor(Theme.Colors.textTertiary)
            Text(value).font(.appSystem(size: 12, weight: .black, design: .rounded)).foregroundColor(tint)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: 通知管理
    private var notificationContent: some View {
        SettingsSectionCard(title: "通知管理") {
            VStack(spacing: 0) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Task { await UIApplication.shared.open(url) }
                    }
                } label: {
                    SettingsIconRow(
                        title: notificationsEnabled ? "系统通知可用" : "系统通知需要授权",
                        symbol: notificationsEnabled ? "bell.badge.fill" : "bell.slash.fill",
                        tint: notificationsEnabled ? Theme.Colors.mintGreen : Theme.Colors.accentRed,
                        subtitle: managementPreferences.contentSummary
                    )
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 70)

                SettingsToggleDetailRow(icon: "heart.text.square.fill", tint: Theme.Colors.accentRed, title: "健康警报", subtitle: "心率与压力异常时提醒", isOn: $abnormalHealthAlertsEnabled)
                Divider().padding(.leading, 70)
                SettingsToggleDetailRow(icon: "checkmark.seal.fill", tint: Theme.Colors.mintGreen, title: "目标提醒", subtitle: "习惯完成与进度提醒", isOn: $goalRemindersEnabled)
                Divider().padding(.leading, 70)
                SettingsToggleDetailRow(icon: "chart.bar.doc.horizontal.fill", tint: Color(hex: "7D8BFF"), title: "周报摘要", subtitle: "每周生成恢复摘要", isOn: $weeklySummaryEnabled)
                Divider().padding(.leading, 70)
                SettingsToggleDetailRow(icon: "bed.double.fill", tint: Color(hex: "536FE8"), title: "睡眠不足提醒", subtitle: "睡眠不足时温柔提示", isOn: $sleepLackReminderEnabled)
                Divider().padding(.leading, 70)
                SettingsToggleDetailRow(icon: "brain.head.profile.fill", tint: Color(hex: "FF6B6B"), title: "压力警报", subtitle: "压力持续偏高时提醒", isOn: $stressAlertsEnabled)
                Divider().padding(.leading, 70)
                SettingsToggleDetailRow(icon: "checkmark.circle.fill", tint: Color(hex: "B78CFF"), title: "每日签到", subtitle: "每天一次状态打卡", isOn: $stressDailyCheckInEnabled)
            }
        }
        .onAppear {
            checkNotificationStatus()
            managementPreferences = NotificationManagementPreferencesStore.shared.load()
        }
        .onChange(of: abnormalHealthAlertsEnabled) { _, newValue in
            if stressAlertsEnabled != newValue { stressAlertsEnabled = newValue }
        }
        .onChange(of: stressAlertsEnabled) { _, newValue in
            if abnormalHealthAlertsEnabled != newValue { abnormalHealthAlertsEnabled = newValue }
        }
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let isEnabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                notificationsEnabled = isEnabled
            }
        }
    }

    // MARK: 页面缓存
    private var cacheContent: some View {
        SettingsSectionCard(title: "页面缓存") {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("已用缓存")
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text(SettingsView.cacheSizeText(cacheSnapshot.totalBytes))
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    Spacer()
                    Text("\(cacheSnapshot.totalItemCount) 项")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.accentBlue)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.Colors.accentBlue.opacity(0.10), in: Capsule())
                }

                if !cacheFeedbackMessage.isEmpty {
                    Text(cacheFeedbackMessage)
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    showCacheClearConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: cacheSnapshot.totalItemCount == 0 ? "checkmark.circle.fill" : "trash")
                            .font(.appSystem(size: 13, weight: .bold))
                        Text(isClearingCache ? "正在清理" : "清理页面缓存")
                            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Theme.Colors.accentRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.Colors.accentRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isClearingCache)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .alert("清理页面缓存？", isPresented: $showCacheClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("立即清理", role: .destructive) { clearPageCaches() }
        } message: {
            Text("会清空页面派生快照、Widget 展示快照和 Watch 传输缓存，不会删除账号、偏好、目标、Health 原始数据或用户记录。")
        }
    }

    private func clearPageCaches() {
        guard !isClearingCache else { return }
        withAnimation { isClearingCache = true; cacheFeedbackMessage = "" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            let result = AppDataCacheManager.shared.clear()
            withAnimation { cacheSnapshot = result.remainingSnapshot }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                withAnimation {
                    isClearingCache = false
                    cacheFeedbackMessage = result.removedItemCount == 0
                        ? String(localized: "当前没有可清理的页面缓存。")
                        : String(localized: "已清理 \(result.removedItemCount) 项缓存。")
                }
            }
        }
    }
}

// MARK: - 设备管理内联（MyDeviceView 全部 workspace 平铺）

/// DeviceInlineSection 以 section 形式直接展示「我的设备」全部内容，包括 Apple Watch 状态和帮助排障。
struct DeviceInlineSection: View {
    @Bindable private var healthDataManager = HealthDataManager.shared
    @State private var isSyncingAppleWatch = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            // Apple Watch 状态
            SettingsSectionCard(title: "Apple Watch") {
                VStack(spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        deviceMetric(title: "系统配对", value: healthDataManager.isWatchPaired ? "已完成" : "未配对", symbol: healthDataManager.isWatchPaired ? "checkmark.circle.fill" : "link.badge.plus", tint: healthDataManager.isWatchPaired ? Color(hex: "2BA77A") : Color(hex: "E49A36"))
                        deviceMetric(title: "Watch App", value: healthDataManager.isWatchAppInstalled ? "已安装" : "待安装", symbol: healthDataManager.isWatchAppInstalled ? "app.badge.checkmark.fill" : "square.and.arrow.down.fill", tint: healthDataManager.isWatchAppInstalled ? Color(hex: "316DF4") : Color(hex: "E49A36"))
                        deviceMetric(title: "当前连接", value: connectivityText, symbol: watchConnectionMetricSymbol, tint: watchConnectionMetricColor)
                        deviceMetric(title: "最近同步", value: lastWatchSyncText, symbol: "arrow.triangle.2.circlepath.circle.fill", tint: Color(hex: "7D71DC"))
                    }

                    Button {
                        performSync()
                    } label: {
                        HStack(spacing: 8) {
                            if isSyncingAppleWatch {
                                ProgressView().tint(Theme.Colors.onAccent)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.appSystem(size: 15, weight: .bold))
                            }
                            Text(isSyncingAppleWatch ? "同步中…" : "同步最新数据")
                                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color(hex: "316DF4"), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSyncingAppleWatch || !healthDataManager.isWatchPaired)
                    .opacity(healthDataManager.isWatchPaired ? 1 : 0.5)
                }
                .padding(16)
            }

            // 帮助排障
            SettingsSectionCard(title: "连接排障") {
                VStack(spacing: 0) {
                    SettingsIconRow(title: "重新检查连接", symbol: "arrow.clockwise", tint: Color(hex: "2BA77A"), subtitle: "刷新配对、安装与在线状态")
                    Divider().padding(.leading, 70)
                    Button {
                        openSystemSettings()
                    } label: {
                        SettingsIconRow(title: "打开系统设置", symbol: "gearshape.fill", tint: Color(hex: "316DF4"), subtitle: "检查 眠屿 的系统权限")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 70)
                    Button {
                        openSystemSettings()
                    } label: {
                        SettingsIconRow(title: "检查通知、蓝牙与健康权限", symbol: "checkmark.shield.fill", tint: Color(hex: "D78745"), subtitle: "逐项排查连接问题")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { healthDataManager.refreshWatchSessionState() }
    }

    private func deviceMetric(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: symbol).font(.appSystem(size: 15, weight: .bold)).foregroundColor(tint); Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.appSystem(size: 14, weight: .black, design: .rounded)).foregroundColor(Color(hex: "202938")).lineLimit(1).minimumScaleFactor(0.78)
                Text(title).font(.appSystem(size: 10, weight: .bold, design: .rounded)).foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func performSync() {
        guard healthDataManager.isWatchPaired && healthDataManager.isWatchAppInstalled else { return }
        isSyncingAppleWatch = true
        Task {
            await HealthDataManager.shared.syncAllData()
            healthDataManager.refreshWatchSessionState()
            isSyncingAppleWatch = false
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private var connectivityText: String {
        if !healthDataManager.isWatchPaired { return String(localized: "未配对") }
        if !healthDataManager.isWatchAppInstalled { return String(localized: "待安装") }
        if healthDataManager.isWatchReachable { return String(localized: "已连接") }
        if healthDataManager.watchActivationState == .activated { return String(localized: "等待连接") }
        return String(localized: "未激活")
    }
    private var watchConnectionMetricSymbol: String {
        if !healthDataManager.isWatchPaired { return "link.badge.plus" }
        if !healthDataManager.isWatchAppInstalled { return "arrow.down.circle.fill" }
        if healthDataManager.isWatchReachable { return "dot.radiowaves.left.and.right" }
        return "clock.arrow.circlepath"
    }
    private var watchConnectionMetricColor: Color {
        if healthDataManager.isWatchReachable { return Color(hex: "2BA77A") }
        if healthDataManager.isWatchPaired { return Color(hex: "D98B2B") }
        return Color(hex: "7D8797")
    }
    private var lastWatchSyncText: String {
        guard let date = healthDataManager.lastWatchSyncDate else { return String(localized: "暂无记录") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 帮助与反馈内联（HelpFeedbackView 全部 workspace 平铺）

/// HelpFeedbackInlineSection 以 section 形式直接展示「帮助与反馈」全部内容。
struct HelpFeedbackInlineSection: View {
    @Environment(\.openURL) private var openURL
    @State private var feedbackText = ""
    @State private var selectedTopic: FeedbackType = .issue
    @FocusState private var isFeedbackFieldFocused: Bool

    var body: some View {
        SettingsSectionCard(title: "帮助与反馈") {
            VStack(spacing: 14) {
                // 联系渠道
                VStack(spacing: 0) {
                    Button { openURL(ProfileExternalLinks.supportEmail) } label: {
                        SettingsIconRow(title: "邮箱支持", symbol: "envelope.fill", tint: Theme.Colors.accentBlue, subtitle: ProfileExternalLinks.emailAddress)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 70)
                    Button { openURL(ProfileExternalLinks.xiaohongshu) } label: {
                        SettingsIconRow(title: "小红书", symbol: "heart.fill", tint: Color(hex: "FF2E6F"), subtitle: "关注更新、留言交流")
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                // 反馈输入
                VStack(alignment: .leading, spacing: 10) {
                    Text("提交反馈")
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FeedbackType.allCases, id: \.self) { topic in
                                Button { selectedTopic = topic } label: {
                                    Text(topic.title)
                                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(selectedTopic == topic ? .white : Color(hex: "53605B"))
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(
                                            selectedTopic == topic ? Theme.Colors.mintGreen : Color(hex: "EEF0EE"),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    TextField("描述你遇到的问题或建议…", text: $feedbackText, axis: .vertical)
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .textFieldStyle(.plain)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .focused($isFeedbackFieldFocused)

                    Button {
                        sendFeedbackEmail()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane.fill").font(.appSystem(size: 13, weight: .bold))
                            Text("通过邮件发送").font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Theme.Colors.mintGreen, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .onChange(of: feedbackText) { _, newValue in
            if newValue.count > 1000 { feedbackText = String(newValue.prefix(1000)) }
        }
    }

    private func sendFeedbackEmail() {
        let subject = "眠屿 反馈 · \(selectedTopic.title)"
        let body = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ProfileExternalLinks.emailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url { openURL(url) }
    }
}

// MARK: - 品牌故事内联

/// BrandStoryInlineSection 以 section 形式直接展示品牌故事和理念。
struct BrandStoryInlineSection: View {
    var body: some View {
        SettingsSectionCard(title: "我们的故事") {
            VStack(spacing: 14) {
                storyRow(title: "先看见身体信号", detail: "把睡眠、压力、活动和日常记录放回同一段生活里，让零散数字第一次彼此照应。", icon: "waveform.path.ecg", tint: Color(hex: "397CE8"))
                Divider().padding(.leading, 60)
                storyRow(title: "再理解一段变化", detail: "少盯一次高低，多看趋势、节律和前后关系。一次波动不定义你，一段变化才更接近真实。", icon: "chart.line.uptrend.xyaxis", tint: Color(hex: "E18A2D"))
                Divider().padding(.leading, 60)
                storyRow(title: "最后轻轻行动", detail: "把复杂数据收成一件今天真正做得到的小事。补水、早一点休息，或只是给自己留出一点缓冲。", icon: "leaf.fill", tint: Color(hex: "2FA570"))
                Divider().padding(.leading, 60)
                storyRow(title: "数据属于你", detail: "我们会尽量采用本地优先、最少必要的方式处理健康信息，并把权限选择留给你。", icon: "lock.shield.fill", tint: Color(hex: "397CE8"))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private func storyRow(title: String, detail: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(tint.opacity(0.13))
                Image(systemName: icon).font(.appSystem(size: 15, weight: .bold)).foregroundColor(tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.appSystem(size: 14, weight: .black, design: .rounded)).foregroundColor(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 健康目标内联（GoalsSettingsView 内联）

/// GoalsInlineSection 以 section 形式直接展示目标设置，滚轮选择器通过 sheet 弹出。
struct GoalsInlineSection: View {
    @AppStorage("daily_steps_goal") private var dailyStepsGoal: Int = 8000
    @AppStorage("daily_active_minutes_goal") private var dailyActiveMinutesGoal: Int = 30
    @AppStorage("daily_sleep_goal_hours") private var sleepHoursGoal: Double = 8
    @State private var activePicker: InlineGoalPickerKind?
    @State private var showingResetConfirmation = false

    var body: some View {
        SettingsSectionCard(title: "健康目标") {
            VStack(spacing: 0) {
                ProfileWheelSelectorRow(
                    title: "每日步数", subtitle: "点按用滚轮选择",
                    icon: "shoeprints.fill", tint: Theme.Colors.mintGreen,
                    valueText: "\(dailyStepsGoal) 步"
                ) { activePicker = .steps }
                Divider().padding(.leading, 74)
                ProfileWheelSelectorRow(
                    title: "活动时间", subtitle: "点按用滚轮选择",
                    icon: "figure.walk", tint: Theme.Colors.accentBlue,
                    valueText: "\(dailyActiveMinutesGoal) 分钟"
                ) { activePicker = .activeMinutes }
                Divider().padding(.leading, 74)
                ProfileWheelSelectorRow(
                    title: "睡眠目标", subtitle: "点按用滚轮选择",
                    icon: "bed.double.fill", tint: Color(hex: "7D8BFF"),
                    valueText: String(format: String(localized: "%.1f 小时"), sleepHoursGoal)
                ) { activePicker = .sleep }
            }
        }
        .sheet(item: $activePicker) { picker in
            switch picker {
            case .steps:
                ProfileWheelPickerSheet(
                    title: "每日步数", subtitle: "滚动选择一个稳定完成的档位。",
                    valueSummary: "\(dailyStepsGoal) 步", tint: Theme.Colors.mintGreen,
                    options: stepGoalOptions, selection: $dailyStepsGoal
                )
            case .activeMinutes:
                ProfileWheelPickerSheet(
                    title: "活动时间", subtitle: "滚动选择计划留给活动的分钟数。",
                    valueSummary: "\(dailyActiveMinutesGoal) 分钟", tint: Theme.Colors.accentBlue,
                    options: activeMinuteOptions, selection: $dailyActiveMinutesGoal
                )
            case .sleep:
                ProfileWheelPickerSheet(
                    title: "睡眠目标", subtitle: "滚动选择希望维持的睡眠时长。",
                    valueSummary: String(format: String(localized: "%.1f 小时"), sleepHoursGoal),
                    tint: Color(hex: "7D8BFF"), options: sleepGoalOptions, selection: $sleepHoursGoal
                )
            }
        }
        .onAppear(perform: syncGoalPreferences)
        .onChange(of: dailyStepsGoal) { _, _ in syncGoalPreferences() }
        .onChange(of: dailyActiveMinutesGoal) { _, _ in syncGoalPreferences() }
        .onChange(of: sleepHoursGoal) { _, _ in syncGoalPreferences() }
    }

    private enum InlineGoalPickerKind: String, Identifiable {
        case steps, activeMinutes, sleep
        var id: String { rawValue }
    }

    private var stepGoalOptions: [ProfileWheelPickerOption<Int>] {
        Array(stride(from: 1000, through: 30000, by: 500)).map { .init(value: $0, label: "\($0) 步") }
    }
    private var activeMinuteOptions: [ProfileWheelPickerOption<Int>] {
        Array(stride(from: 5, through: 180, by: 5)).map { .init(value: $0, label: "\($0) 分钟") }
    }
    private var sleepGoalOptions: [ProfileWheelPickerOption<Double>] {
        Array(stride(from: 4.0, through: 10.0, by: 0.5)).map { .init(value: $0, label: String(format: String(localized: "%.1f 小时"), $0)) }
    }

    private func syncGoalPreferences() {
        AppGroupManager.shared.save(value: dailyStepsGoal, forKey: AppGroupManager.Keys.stepsGoal)
        AppGroupManager.shared.save(value: dailyActiveMinutesGoal, forKey: AppGroupManager.Keys.exerciseMinutesGoal)
        AppGroupManager.shared.save(value: Int(sleepHoursGoal * 60.0), forKey: AppGroupManager.Keys.sleepGoalMinutes)
    }
}

// MARK: - 阈值内联（ThresholdSettingsView 内联）

/// ThresholdInlineSection 以 section 形式直接展示阈值设置，滚轮选择器通过 sheet 弹出。
struct ThresholdInlineSection: View {
    @AppStorage("high_heart_rate_alert_bpm") private var highHeartRateBpm: Double = 120
    @AppStorage("low_heart_rate_alert_bpm") private var lowHeartRateBpm: Double = 45
    @AppStorage("stress_alert_threshold") private var stressAlertThreshold: Double = 75
    @State private var activePicker: InlineThresholdPickerKind?

    var body: some View {
        SettingsSectionCard(title: "提醒阈值") {
            VStack(spacing: 0) {
                ProfileWheelSelectorRow(
                    title: "高心率提醒", subtitle: "点按用滚轮调整",
                    icon: "heart.fill", tint: Theme.Colors.accentRed,
                    valueText: "\(Int(highHeartRateBpm)) 次/分"
                ) { activePicker = .highHeartRate }
                Divider().padding(.leading, 74)
                ProfileWheelSelectorRow(
                    title: "低心率提醒", subtitle: "点按用滚轮调整",
                    icon: "heart.text.square.fill", tint: Theme.Colors.accentBlue,
                    valueText: "\(Int(lowHeartRateBpm)) 次/分"
                ) { activePicker = .lowHeartRate }
                Divider().padding(.leading, 74)
                ProfileWheelSelectorRow(
                    title: "压力警报阈值", subtitle: "点按用滚轮调整",
                    icon: "brain.head.profile", tint: Color(hex: "FFB340"),
                    valueText: "\(Int(stressAlertThreshold))%"
                ) { activePicker = .stress }
            }
        }
        .sheet(item: $activePicker) { picker in
            switch picker {
            case .highHeartRate:
                ProfileWheelPickerSheet(
                    title: "高心率提醒", subtitle: "滚动选择提醒心率上限。",
                    valueSummary: "\(Int(highHeartRateBpm)) 次/分", tint: Theme.Colors.accentRed,
                    options: highHeartRateOptions, selection: $highHeartRateBpm
                )
            case .lowHeartRate:
                ProfileWheelPickerSheet(
                    title: "低心率提醒", subtitle: "滚动选择提醒心率下限。",
                    valueSummary: "\(Int(lowHeartRateBpm)) 次/分", tint: Theme.Colors.accentBlue,
                    options: lowHeartRateOptions, selection: $lowHeartRateBpm
                )
            case .stress:
                ProfileWheelPickerSheet(
                    title: "压力警报阈值", subtitle: "滚动选择压力提醒阈值。",
                    valueSummary: "\(Int(stressAlertThreshold))%", tint: Color(hex: "FFB340"),
                    options: stressThresholdOptions, selection: $stressAlertThreshold
                )
            }
        }
        .onAppear {
            normalizeHeartRateRange()
        }
        .onChange(of: highHeartRateBpm) { _, _ in normalizeHeartRateRange(changedHighValue: true) }
        .onChange(of: lowHeartRateBpm) { _, _ in normalizeHeartRateRange(changedHighValue: false) }
    }

    private enum InlineThresholdPickerKind: String, Identifiable {
        case highHeartRate, lowHeartRate, stress
        var id: String { rawValue }
    }

    private var highHeartRateOptions: [ProfileWheelPickerOption<Double>] {
        Array(stride(from: 80, through: 200, by: 5)).map { .init(value: $0, label: "\(Int($0))") }
    }
    private var lowHeartRateOptions: [ProfileWheelPickerOption<Double>] {
        Array(stride(from: 30, through: 100, by: 5)).map { .init(value: $0, label: "\(Int($0))") }
    }
    private var stressThresholdOptions: [ProfileWheelPickerOption<Double>] {
        Array(stride(from: 40, through: 95, by: 5)).map { .init(value: $0, label: "\(Int($0))%") }
    }

    private func normalizeHeartRateRange(changedHighValue: Bool = false) {
        if lowHeartRateBpm >= highHeartRateBpm {
            if changedHighValue {
                lowHeartRateBpm = max(30, highHeartRateBpm - 5)
            } else {
                highHeartRateBpm = min(200, lowHeartRateBpm + 5)
            }
        }
    }
}

// MARK: - iCloud 管理内联

/// ICloudManagementInlineSection 以 section 形式直接展示 iCloud 同步管理全部开关，不跳转。
struct ICloudManagementInlineSection: View {
    @AppStorage(CloudKitDataPolicy.PreferenceKey.drinkExperienceSyncEnabled) private var drinkExperienceSyncEnabled = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.sleepSummarySyncEnabled) private var sleepSummarySyncEnabled = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled) private var medicationHealthSyncEnabled = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.pregnancySyncEnabled) private var pregnancySyncEnabled = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.goalMascotSyncEnabled) private var goalMascotSyncEnabled = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.onboardingPreferenceSyncEnabled) private var onboardingPreferenceSyncEnabled = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.socialSharingEnabled) private var socialSharingEnabled = true

    @State private var accountStatus: CKAccountStatus?
    @State private var isRefreshing = false

    private var enabledCount: Int {
        [drinkExperienceSyncEnabled, sleepSummarySyncEnabled, medicationHealthSyncEnabled,
         pregnancySyncEnabled, onboardingPreferenceSyncEnabled, goalMascotSyncEnabled, socialSharingEnabled]
            .filter { $0 }.count
    }

    var body: some View {
        VStack(spacing: 16) {
            // 账户状态摘要
            SettingsSectionCard(title: "iCloud 管理") {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Theme.Colors.surfaceBorder, lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: CGFloat(enabledCount) / 7)
                            .stroke(Theme.Colors.accentBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(enabledCount)")
                            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(accountTitle)
                            .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("已开启 \(enabledCount) 项 · 共 7 项")
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Text(enabledCount == 7 ? "全部开启" : "自定义")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(enabledCount == 7 ? Theme.Colors.mintGreen : Theme.Colors.accentBlue)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background((enabledCount == 7 ? Theme.Colors.mintGreen : Theme.Colors.accentBlue).opacity(0.10), in: Capsule())
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }

            // 健康与生活数据
            SettingsSectionCard(title: "健康与生活数据") {
                VStack(spacing: 0) {
                    SettingsToggleDetailRow(icon: "fork.knife", tint: Color(hex: "FF9F43"), title: "餐饮数据同步", subtitle: "不包含原始图片和精确位置", isOn: $drinkExperienceSyncEnabled)
                    Divider().padding(.leading, 70)
                    SettingsToggleDetailRow(icon: "bed.double.fill", tint: Color(hex: "7D8BFF"), title: "睡眠数据同步", subtitle: "仅同步摘要，不上传录音", isOn: $sleepSummarySyncEnabled)
                    Divider().padding(.leading, 70)
                    SettingsToggleDetailRow(icon: "cross.case.fill", tint: Color(hex: "536FE8"), title: "药物与处方同步", subtitle: "同步确认后的结构化资料", isOn: $medicationHealthSyncEnabled)
                    Divider().padding(.leading, 70)
                    SettingsToggleDetailRow(icon: "figure.and.child.holdinghands", tint: Color(hex: "E98AB3"), title: "孕期资料同步", subtitle: "同步孕期档案和胎动记录", isOn: $pregnancySyncEnabled)
                }
            }

            // 功能与共享
            SettingsSectionCard(title: "功能与共享") {
                VStack(spacing: 0) {
                    SettingsToggleDetailRow(icon: "person.text.rectangle.fill", tint: Color(hex: "4E8EF7"), title: "引导偏好同步", subtitle: "同步健康目标和基础资料", isOn: $onboardingPreferenceSyncEnabled)
                    Divider().padding(.leading, 70)
                    SettingsToggleDetailRow(icon: "pawprint.fill", tint: Color(hex: "B78CFF"), title: "吉祥物数据同步", subtitle: "同步档案、成长进度和 XP", isOn: $goalMascotSyncEnabled)
                    Divider().padding(.leading, 70)
                    SettingsToggleDetailRow(icon: "person.2.fill", tint: Theme.Colors.mintGreen, title: "社交共享", subtitle: "好友发现和协作待办", isOn: $socialSharingEnabled)
                }
            }

            // 同步按钮
            Button {
                Task { await synchronize() }
            } label: {
                HStack(spacing: 8) {
                    if isRefreshing {
                        ProgressView().tint(Theme.Colors.onAccent)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                    }
                    Text(isRefreshing ? "正在同步" : "立即同步已开启项目")
                        .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(
                    LinearGradient(colors: [Theme.Colors.accentBlue, Color(hex: "625DEB")], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing || accountStatus != .available)
            .opacity(accountStatus == .available ? 1 : 0.5)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield.fill").foregroundColor(Theme.Colors.accentBlue).padding(.top, 1)
                Text("数据保存在当前 Apple ID 的 iCloud 中。关闭同步不会删除已保存的数据。")
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, 4)
        }
        .task { await refreshAccountStatus() }
    }

    private var accountTitle: String {
        switch accountStatus {
        case .available: return String(localized: "iCloud 已连接")
        case .noAccount: return String(localized: "未登录 iCloud")
        case .restricted: return String(localized: "iCloud 访问受限")
        case .couldNotDetermine: return String(localized: "无法确认 iCloud 状态")
        case .temporarilyUnavailable: return String(localized: "iCloud 暂时不可用")
        case nil: return String(localized: "正在检查 iCloud")
        @unknown default: return String(localized: "iCloud 状态未知")
        }
    }

    private func refreshAccountStatus() async {
        accountStatus = await ICloudSyncCoordinator.shared.accountStatus()
    }

    @MainActor
    private func synchronize() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        _ = await ICloudSyncCoordinator.shared.synchronizeEnabledDomains(includePregnancy: true)
        accountStatus = await ICloudSyncCoordinator.shared.accountStatus()
    }
}

// MARK: - Watch 表盘组件内联

/// WatchPromoInlineSection 以 section 形式直接展示 Watch 表盘组件信息。
struct WatchPromoInlineSection: View {
    var body: some View {
        SettingsSectionCard(title: "Watch 表盘组件") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("综合恢复表盘")
                            .font(.appSystem(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("把恢复、睡眠、步数和习惯入口放到最顺手的位置。")
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    featureChip("表情", "face.smiling")
                    featureChip("睡眠", "bed.double.fill")
                    featureChip("步数", "figure.walk")
                    featureChip("晒太阳", "sun.max.fill")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private func featureChip(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.appSystem(size: 13, weight: .bold)).foregroundColor(Theme.Colors.mintGreen)
            Text(title).font(.appSystem(size: 9, weight: .bold, design: .rounded)).foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.Colors.mintGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Watch 吉祥物内联

/// WatchThemeInlineSection 以 section 形式直接展示 Watch 吉祥物选择。
struct WatchThemeInlineSection: View {
    @AppStorage("watchThemeId") private var watchThemeId: String = "joey"

    private let themes: [WatchTheme] = [
        WatchTheme(id: "bubble", name: "压力泡泡", accent: Color(hex: "68D4A2"), background: Color(hex: "EDFFF5"), style: .bubble),
        WatchTheme(id: "bosscat", name: "醒神仔", accent: Color(hex: "FFD85E"), background: Color(hex: "FFF9E8"), style: .bossCat),
        WatchTheme(id: "bearjoy", name: "小熊joy", accent: Color(hex: "F0C27B"), background: Color(hex: "FFF5E7"), style: .bear),
        WatchTheme(id: "flowercat", name: "焦绿猫", accent: Color(hex: "FF9BC3"), background: Color(hex: "FFF2F7"), style: .flowerCat),
        WatchTheme(id: "bunny", name: "汪啊", accent: Color(hex: "F3A6D2"), background: Color(hex: "FFF4FA"), style: .bunny),
        WatchTheme(id: "tiger", name: "虎虎", accent: Color(hex: "8F94FF"), background: Color(hex: "F5F6FF"), style: .tiger),
        WatchTheme(id: "piggy", name: "猪傻傻", accent: Color(hex: "FF9FA8"), background: Color(hex: "FFF4F5"), style: .pig),
        WatchTheme(id: "joey", name: "周伊 Joey", accent: Color(hex: "63D6A0"), background: Color(hex: "F0FFF7"), style: .joey)
    ]

    private let columns = [
        GridItem(.adaptive(minimum: 68, maximum: 82), spacing: 10)
    ]

    var body: some View {
        SettingsSectionCard(title: "Watch 吉祥物") {
            VStack(spacing: 14) {
                Text("选择 Apple Watch 端展示的吉祥物主题")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(themes) { theme in
                        Button {
                            selectTheme(theme)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(theme.background)
                                        .frame(width: 52, height: 52)
                                    Circle()
                                        .stroke(theme.accent.opacity(watchThemeId == theme.id ? 0.9 : 0.3), lineWidth: 2)
                                        .frame(width: 52, height: 52)
                                    Image(systemName: themeSymbol(style: theme.style))
                                        .font(.appSystem(size: 20, weight: .black))
                                        .foregroundColor(theme.accent)
                                    if watchThemeId == theme.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.appSystem(size: 16, weight: .bold))
                                            .foregroundColor(Theme.Colors.mintGreen)
                                            .background(Circle().fill(Color.white).frame(width: 18, height: 18))
                                            .offset(x: 18, y: -18)
                                    }
                                }
                                .frame(width: 52, height: 52)

                                Text(theme.name)
                                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(watchThemeId == theme.id ? theme.accent : Color(hex: "686C69"))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private func themeSymbol(style: WatchMascotStyle) -> String {
        switch style {
        case .bubble: return "circle.fill"
        case .bossCat: return "face.smiling.fill"
        case .bear: return "pawprint.fill"
        case .flowerCat: return "leaf.fill"
        case .bunny: return "tortoise.fill"
        case .tiger: return "moon.stars.fill"
        case .pig: return "music.note"
        case .joey: return "sparkles"
        }
    }

    private func selectTheme(_ theme: WatchTheme) {
        watchThemeId = theme.id
        AppGroupManager.shared.saveWatchThemeId(theme.id)
        HealthDataManager.shared.syncWatchThemeSelection(theme.id)
    }
}
