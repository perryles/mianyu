/// SettingsView 由 ProfileView 应用设置入口调用，作为「应用设置」首页容器。
/// 负责承载设置首页的分组入口、全局弹窗状态与三级页面跳转。

import SwiftUI
import UserNotifications

/// SettingsView 由应用主导航入口调用，作为“应用设置”首页容器使用。
/// 负责承载应用设置首页的分组入口、全局弹窗状态和各类三级页面跳转，
/// 包括通用设置、通知管理、页面缓存、帮助与协议等入口。
struct SettingsView: View {
    @AppStorage("abnormalHealthAlertsEnabled") private var abnormalHealthAlertsEnabled: Bool = true
    @AppStorage("goalRemindersEnabled") private var goalRemindersEnabled: Bool = true
    @AppStorage("weeklySummaryEnabled") private var weeklySummaryEnabled: Bool = true
    @AppStorage("sleepLackReminderEnabled") private var sleepLackReminderEnabled: Bool = true
    @AppStorage("stressAlertsEnabled") private var stressAlertsEnabled: Bool = true
    @AppStorage("stressDailyCheckInEnabled") private var stressDailyCheckInEnabled: Bool = true
    
    @State private var notificationsEnabled = true
    @State private var selectedFAQ: FAQSheetItem?
    @State private var showingFAQList = false
    @State private var showingAbout = false
    @State private var cacheStats = CacheManagementStats()
    
    @Environment(AppFontScaleStore.self) private var appFontScaleStore
    private let cardSpacing: CGFloat = 12

    private var adaptiveSectionSpacing: CGFloat {
        cardSpacing
    }

    private var appFontScaleLevel: AppFontScaleLevel {
        appFontScaleStore.level
    }

    var body: some View {
        ZStack {
            settingsAmbientBackground
            
            AdaptivePageScrollView(topPadding: 12, bottomPadding: 88) {
                VStack(alignment: .leading, spacing: adaptiveSectionSpacing) {
                    settingsSectionBlock(title: "应用偏好") {
                        generalEntryCard
                        appIconEntryCard
                        widgetEntryCard
                        notificationEntryCard
                        cacheManagementEntryCard
                        #if DEBUG || INTERNAL_AI
                        internalAIEntryCard
                        #endif
                    }

                    settingsSectionBlock(title: "数据与隐私") {
                        NavigationLink(destination: DataPrivacyManagementView()) {
                            PromoCard(
                                title: "导出我的数据",
                                icon: "square.and.arrow.up.fill",
                                tint: Theme.Colors.accentBlue
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: DataPrivacyManagementView()) {
                            PromoCard(
                                title: "删除我的数据",
                                icon: "trash.fill",
                                tint: Theme.Colors.accentRed
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    supportLinksCard
                    legalCard

                    Spacer(minLength: 80)
                }
            }
        }
        .navigationTitle("应用设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showingFAQList) {
            NavigationStack {
                FAQListView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") { showingFAQList = false }
                        }
                    }
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingAbout) {
            NavigationStack {
                AboutView()
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .sheet(item: $selectedFAQ) { item in
            NavigationStack {
                FAQDetailView(question: item.question)
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .onAppear {
            checkNotificationStatus()
            syncNotificationManagementPreferences()
            Task { await cacheStats.refresh() }
        }
    }

    private var settingsAmbientBackground: some View {
        Theme.Colors.pageBackground
            .ignoresSafeArea()
    }
    
    private var generalEntryCard: some View {
        NavigationLink(destination: GeneralSettingsView()) {
            PromoCard(
                title: "通用",
                icon: "slider.horizontal.3",
                tint: Theme.Colors.mintGreen
            )
        }
        .buttonStyle(.plain)
    }

    private var notificationEntryCard: some View {
        NavigationLink(
            destination: NotificationPreferencesView(
                notificationsEnabled: notificationsEnabled,
                abnormalHealthAlertsEnabled: $abnormalHealthAlertsEnabled,
                goalRemindersEnabled: $goalRemindersEnabled,
                weeklySummaryEnabled: $weeklySummaryEnabled,
                sleepLackReminderEnabled: $sleepLackReminderEnabled,
                setNotificationsEnabled: setNotificationsEnabled
            )
        ) {
            PromoCard(
                title: "通知管理",
                icon: "bell.badge.fill",
                tint: Color(hex: "FFB340")
            )
        }
        .buttonStyle(.plain)
    }

    private var appIconEntryCard: some View {
        NavigationLink(destination: AppIconSettingsView()) {
            PromoCard(
                title: "应用图标",
                icon: "app.badge.fill",
                tint: Color(hex: "55BFF4")
            )
        }
        .buttonStyle(.plain)
    }

    /// Widget 页会读取实际共享快照并提供系统添加教程，因此属于真实的应用偏好入口。
    private var widgetEntryCard: some View {
        NavigationLink(destination: WidgetSettingsView()) {
            PromoCard(
                title: "手机小组件",
                icon: "square.grid.2x2.fill",
                tint: Color(hex: "6D7EF7")
            )
        }
        .buttonStyle(.plain)
    }

    private var supportLinksCard: some View {
        settingsSectionBlock(title: "帮助与支持") {
            NavigationLink(destination: SleepAudioInferenceView()) {
                PromoCard(
                    title: "睡眠音频诊断",
                    icon: "waveform.and.mic",
                    tint: Color(hex: "5BB7C5")
                )
            }
            .buttonStyle(.plain)

            Button {
                showingAbout = true
            } label: {
                PromoCard(
                    title: "帮助与关于",
                    icon: "questionmark.circle.fill",
                    tint: Color(hex: "87D6F7")
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedFAQ = FAQSheetItem(question: "压力与HRV基础科普")
            } label: {
                PromoCard(
                    title: "心率科普",
                    icon: "heart.text.square.fill",
                    tint: Theme.Colors.accentBlue
                )
            }
            .buttonStyle(.plain)

            Button {
                showingFAQList = true
            } label: {
                PromoCard(
                    title: "常见问题",
                    icon: "list.bullet.rectangle.fill",
                    tint: Color(hex: "B78CFF")
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var cacheManagementEntryCard: some View {
        NavigationLink(
            destination: CacheManagementView(stats: cacheStats)
        ) {
            ViewThatFits(in: .horizontal) {
                cacheEntryRow(showsPreview: true)
                cacheEntryRow(showsPreview: false)
            }
        }
        .buttonStyle(.plain)
    }

    private func cacheEntryRow(showsPreview: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(hex: "7D8BFF").opacity(0.12))
                    .frame(width: 38, height: 38)

                Image(systemName: "externaldrive.fill")
                    .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "7D8BFF"))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("页面缓存")
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(cacheStats.previewDetailText)
                    .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: showsPreview ? 4 : 0)

            if showsPreview {
                CacheManagementPreview(
                    summaryText: cacheStats.previewSummaryText,
                    detailText: cacheStats.previewDetailText,
                    isClearing: cacheStats.isClearing
                )
            }

            Image(systemName: "chevron.right")
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "D7D9D7"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    #if DEBUG || INTERNAL_AI
    /// 内部入口和目标页面使用同一编译条件，避免 Release 包出现不可达配置 UI。
    private var internalAIEntryCard: some View {
        NavigationLink(destination: InternalAISettingsView()) {
            PromoCard(
                title: "内部 AI 配置",
                icon: "cpu.fill",
                tint: Color(hex: "4E8F83")
            )
        }
        .buttonStyle(.plain)
    }
    #endif

    private var legalCard: some View {
        settingsSectionBlock(title: "协议与版本") {
            NavigationLink(destination: PrivacyPolicyView()) {
                PromoCard(
                    title: "隐私政策",
                    icon: "lock.shield.fill",
                    tint: Color(hex: "B7BA92")
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: TermsOfServiceView()) {
                PromoCard(
                    title: "服务条款",
                    icon: "doc.text.fill",
                    tint: Color(hex: "B98BEA")
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - 方法
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let isEnabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                self.notificationsEnabled = isEnabled
            }
        }
    }

    private func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled != notificationsEnabled else { return }
        
        if enabled {
            notificationsEnabled = true
            Task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                if settings.authorizationStatus == .notDetermined {
                    let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                    notificationsEnabled = granted
                } else {
                    notificationsEnabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
                    if settings.authorizationStatus == .denied {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            await UIApplication.shared.open(url)
                        }
                    }
                }
            }
        } else {
            // 系统不允许应用直接关闭通知，因此引导用户前往系统设置。
            notificationsEnabled = true
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Task { await UIApplication.shared.open(url) }
            }
        }
    }

    private func syncNotificationManagementPreferences() {
        var managementPreferences = NotificationManagementPreferencesStore.shared.load()
        managementPreferences.healthAlertsEnabled = abnormalHealthAlertsEnabled || stressAlertsEnabled
        managementPreferences.recoveryAdviceEnabled = sleepLackReminderEnabled || PersonalizedReminderCenter.shared.loadPreferences().values.contains { $0.isEnabled }
        managementPreferences.summaryReportsEnabled = weeklySummaryEnabled

        if stressAlertsEnabled != abnormalHealthAlertsEnabled {
            stressAlertsEnabled = abnormalHealthAlertsEnabled
        }

        let reminderSettings = HabitReminderManager.shared.load()
        let hasGoalRemindersEnabled =
            stressDailyCheckInEnabled ||
            reminderSettings.waterDailyEnabled ||
            reminderSettings.waterNudgeEnabled ||
            reminderSettings.moodDailyEnabled

        if goalRemindersEnabled != hasGoalRemindersEnabled {
            goalRemindersEnabled = hasGoalRemindersEnabled
        }

        managementPreferences.habitNudgesEnabled = hasGoalRemindersEnabled
        NotificationManagementPreferencesStore.shared.save(managementPreferences)
    }

    static func cacheSizeText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytes)), countStyle: .file)
    }
}

private extension SettingsView {
    @ViewBuilder
    func settingsSectionBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        SettingsSectionCard(title: title) {
            content()
        }
    }

    func overviewPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.Typography.scaled(size: 11, weight: .bold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.scaled(size: 14, weight: .black, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    var settingsFocusText: String {
        if !notificationsEnabled {
            return String(localized: "通知权限还没完全开启")
        }
        if appFontScaleLevel == .one {
            return String(localized: "当前界面更紧凑")
        }
        if appFontScaleLevel != .two {
            return String(localized: "字体大小已经调整")
        }
        return String(localized: "基础配置已就绪")
    }

    var fontPreviewText: String {
        switch appFontScaleLevel {
        case .one: return String(localized: "预览文字更紧凑")
        case .two: return String(localized: "预览文字标准")
        case .three: return String(localized: "预览文字偏大")
        case .four: return String(localized: "预览文字更大")
        }
    }

    var notificationSummaryText: String {
        notificationEnabledCount > 0 ? "已开启 \(notificationEnabledCount) 项提醒" : "当前没有提醒"
    }

    var notificationEnabledCount: Int {
        let reminderSettings = HabitReminderManager.shared.load()
        return [
            abnormalHealthAlertsEnabled,
            weeklySummaryEnabled,
            sleepLackReminderEnabled,
            stressAlertsEnabled,
            stressDailyCheckInEnabled,
            reminderSettings.waterDailyEnabled,
            reminderSettings.waterNudgeEnabled,
            reminderSettings.moodDailyEnabled
        ].filter { $0 }.count
    }
}

private struct FAQSheetItem: Identifiable {
    let id = UUID()
    let question: String
}

/// SettingsSectionCard 统一应用设置首页及子页面的分组标题与卡片表面。
struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.appSystem(size: 17, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                content
            }
            .padding(.vertical, 3)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.Colors.surfaceBorder.opacity(0.8), lineWidth: 1)
            )
        }
    }
}

/// SettingsStatusSummaryRow 用紧凑状态行呈现设置页面的当前配置摘要。
struct SettingsStatusSummaryRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: icon)
                    .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(status)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(tint.opacity(0.12), in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// SettingsTextRow 由 SettingsView 及设置相关子页面调用，用来展示纯文本跳转行。
private struct SettingsTextRow: View {
    let title: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
            Image(systemName: Theme.Icons.chevronRight)
                .font(.appSystem(size: 14, weight: .semibold))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .contentShape(Rectangle())
    }
}

/// SettingsIconRow 由 SettingsView 及其三级页面调用，用来展示带图标和可选副标题的设置行。
struct SettingsIconRow: View {
    let title: String
    let symbol: String
    let tint: Color
    var useMulticolorSymbol: Bool = true
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: symbol)
                    .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
                    .symbolRenderingMode(useMulticolorSymbol ? .monochrome : .monochrome)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Image(systemName: Theme.Icons.chevronRight)
                .font(.appSystem(size: 14, weight: .semibold))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

/// SettingsToggleDetailRow 由通知管理、通用设置等页面调用，用来展示带说明文案的开关行。
struct SettingsToggleDetailRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: icon)
                    .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.Colors.mintGreen)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

/// SettingsSegmentedControlRow 由通用设置页调用，用来展示带分段选择器的设置行。
struct SettingsSegmentedControlRow<Control: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(tint.opacity(0.12))
                    Image(systemName: icon)
                        .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(tint)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

/// PromoCard 由 SettingsView 调用，作为首页各设置入口卡的统一承载视图。
struct PromoCard: View {
    let title: String
    var icon: String = "gearshape.fill"
    var tint: Color = Theme.Colors.mintGreen
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 38, height: 38)

                Image(systemName: icon)
                    .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
            }

            Text(title)
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "D7D9D7"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

/// WatchGlyphBadge 由设置首页内的设备或表盘相关入口预览调用，用来展示简化版 Watch 标识。
private struct WatchGlyphBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
            Circle().fill(Color(hex: "27D8D0")).frame(width: 7, height: 7).offset(x: -7, y: -7)
            Circle().fill(Color(hex: "27D8D0")).frame(width: 7, height: 7).offset(x: 7, y: -7)
            Circle().fill(Color(hex: "27D8D0")).frame(width: 7, height: 7).offset(x: -7, y: 7)
            Circle().fill(Color(hex: "27D8D0")).frame(width: 7, height: 7).offset(x: 7, y: 7)
            Circle().fill(Color(hex: "27D8D0")).frame(width: 7, height: 7)
        }
        .frame(width: 36, height: 36)
    }
}


/// WatchPreviewStrip 由设置首页预览调用，用来展示双 Watch 缩略效果。
private struct WatchPreviewStrip: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .frame(width: 108, height: 56)
            
            HStack(spacing: 8) {
                WatchMiniPreview(tint: Theme.Colors.mintGreen)
                WatchMiniPreview(tint: Theme.Colors.accentBlue)
            }
        }
        .frame(width: 114, height: 60)
    }
}

/// WatchMiniPreview 由 WatchPreviewStrip 调用，作为单个手表缩略块。
private struct WatchMiniPreview: View {
    let tint: Color
    
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black)
            .frame(width: 40, height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .overlay(
                Circle()
                    .fill(tint.opacity(0.7))
                    .frame(width: 16, height: 16)
                    .offset(x: 8, y: -10)
            )
    }
}

/// PhoneWidgetPreview 由设置首页预览调用，用来展示手机小组件缩略效果。
private struct PhoneWidgetPreview: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .frame(width: 114, height: 58)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "heart.fill")
                            .font(.appSystem(size: 14, weight: .semibold))
                            .foregroundColor(Theme.Colors.mintGreen)
                    )
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white)
                    .frame(width: 54, height: 40)
                    .overlay(
                        HStack(spacing: 5) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.appSystem(size: 12, weight: .semibold))
                                .foregroundColor(Theme.Colors.accentBlue)
                            Circle()
                                .fill(Theme.Colors.mintGreen.opacity(0.6))
                                .frame(width: 10, height: 10)
                        }
                    )
            }
        }
        .frame(width: 120, height: 60)
    }
}

/// WallpaperPreview 由设置首页预览调用，用来展示主题壁纸缩略效果。
private struct WallpaperPreview: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .frame(width: 114, height: 58)
            
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.Colors.mintGreen.opacity(0.55), Theme.Colors.accentBlue.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.appSystem(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    )
                
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.Colors.accentBlue.opacity(0.55), Theme.Colors.mintGreen.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 40)
                    .overlay(
                        Image(systemName: "applewatch")
                            .font(.appSystem(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    )
            }
        }
        .frame(width: 120, height: 60)
    }
}

/// GeneralSettingsPreview 由 SettingsView 调用，作为“通用”入口卡右侧缩略预览。
private struct GeneralSettingsPreview: View {
    let level: AppFontScaleLevel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .frame(width: 118, height: 60)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.Colors.accentBlue.opacity(0.7))
                        .frame(width: 8, height: 8)
                    Text("字号 \(level.displayTitle)")
                        .font(Theme.Typography.scaled(size: 10, weight: .black, design: .rounded, level: level))
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                Text(previewText)
                    .font(Theme.Typography.scaled(size: 11, weight: .semibold, design: .rounded, level: level))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 106, height: 48, alignment: .leading)
            .background(Theme.Colors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(width: 120, height: 60)
    }

    private var previewText: String { level.previewText }
}

/// NotificationSettingsPreview 由 SettingsView 调用，作为“通知管理”入口卡右侧缩略预览。
private struct NotificationSettingsPreview: View {
    let isEnabled: Bool
    let enabledCount: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .frame(width: 118, height: 60)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill((isEnabled ? Theme.Colors.mintGreen : Theme.Colors.accentRed).opacity(0.8))
                        .frame(width: 8, height: 8)
                    Text(isEnabled ? "通知可用" : "需授权")
                        .font(Theme.Typography.scaled(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                Text(enabledCount > 0 ? "已开 \(enabledCount) 项提醒" : "当前没有提醒")
                    .font(Theme.Typography.scaled(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 106, height: 48, alignment: .leading)
            .background(Theme.Colors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(width: 120, height: 60)
    }
}

/// ChipTone 用于描述设置页状态胶囊的语气颜色。
private enum ChipTone {
    case positive
    case neutral
    case negative
}

/// StatusChip 由设置相关页面调用，用来展示简单状态胶囊。
private struct StatusChip: View {
    let text: String
    let tone: ChipTone
    
    private var background: Color {
        switch tone {
        case .positive:
            return Theme.Colors.mintGreen.opacity(0.18)
        case .neutral:
            return Theme.Colors.secondaryBackground
        case .negative:
            return Theme.Colors.accentRed.opacity(0.14)
        }
    }
    
    private var foreground: Color {
        switch tone {
        case .positive:
            return Theme.Colors.mintGreen
        case .neutral:
            return Theme.Colors.textSecondary
        case .negative:
            return Theme.Colors.accentRed
        }
    }
    
    var body: some View {
        Text(text)
            .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(foreground)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(background, in: Capsule())
    }
}

/// ThemeAvatarRow 由主题相关设置页调用，用来展示一组主题头像/色彩预览。
private struct ThemeAvatarRow: View {
    private let colors: [Color] = [
        Color(hex: "D8F3ED"),
        Color(hex: "FFE8D6"),
        Color(hex: "FDE2E4"),
        Color(hex: "E2F0CB"),
        Color(hex: "E7ECFF"),
        Color(hex: "F1E5FF"),
        Color(hex: "D9F99D")
    ]
    
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(colors.enumerated()), id: \.offset) { entry in
                Circle()
                    .fill(entry.element)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                    )
            }
            Spacer(minLength: 0)
        }
    }
}

extension View {
    func settingsCardSurface(paddingTop: CGFloat = 8, paddingBottom: CGFloat = 8) -> some View {
        self
            .padding(.top, paddingTop)
            .padding(.bottom, paddingBottom)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
            )
    }
}

#Preview {
    SettingsView()
}
