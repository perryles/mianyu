/// NotificationPreferencesView 由 SettingsView 调用，作为「通知管理」页面。
/// 负责在单页内承载系统权限、接收类型、通知内容、送达节奏与具体提醒开关。

import SwiftUI

/// NotificationPreferencesView 由 [SettingsView] 调用，作为设置页里的“通知管理”页面入口。
/// 负责在单页内承载系统权限、接收类型、通知内容、送达节奏和具体提醒开关。
struct NotificationPreferencesView: View {
    @Bindable private var dashboardViewModel = DashboardViewModel.shared
    let notificationsEnabled: Bool
    @Binding var abnormalHealthAlertsEnabled: Bool
    @Binding var goalRemindersEnabled: Bool
    @Binding var weeklySummaryEnabled: Bool
    @Binding var sleepLackReminderEnabled: Bool
    let setNotificationsEnabled: (Bool) -> Void

    @AppStorage("stressAlertsEnabled") private var stressAlertsEnabled: Bool = true
    @AppStorage("stressDailyCheckInEnabled") private var stressDailyCheckInEnabled: Bool = true
    @State private var managementPreferences = NotificationManagementPreferencesStore.shared.load()
    @State private var reminderSettings: HabitReminderSettings = HabitReminderManager.shared.load()
    @State private var showNotificationDeniedAlert = false

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground
                .ignoresSafeArea()

            AdaptivePageScrollView(topPadding: 12, bottomPadding: 88) {
                VStack(alignment: .leading, spacing: 12) {
                    notificationStatusSection
                    receiveTypeSection
                    contentSection
                    deliverySection
                    singleReminderSection
                }
            }
        }
        .navigationTitle("通知管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert("通知未开启", isPresented: $showNotificationDeniedAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("请先在系统设置中开启通知权限，提醒才会真正送达。")
        }
        .onAppear {
            managementPreferences = NotificationManagementPreferencesStore.shared.load()
            reminderSettings = HabitReminderManager.shared.load()
            syncNotificationPreferencesFromSettings()
            syncManagementPreferencesFromCurrentSwitches()
            Task {
                await LocalNotificationScheduler.reconcilePendingRequestsForQuietHours()
            }
        }
        .onChange(of: managementPreferences) { _, newValue in
            NotificationManagementPreferencesStore.shared.save(newValue)
            applyManagementPreferences(newValue)
        }
        .onChange(of: abnormalHealthAlertsEnabled) { _, newValue in
            if stressAlertsEnabled != newValue {
                stressAlertsEnabled = newValue
            }
            syncManagementPreferencesFromCurrentSwitches()
        }
        .onChange(of: stressAlertsEnabled) { _, newValue in
            if abnormalHealthAlertsEnabled != newValue {
                abnormalHealthAlertsEnabled = newValue
            }
            syncManagementPreferencesFromCurrentSwitches()
        }
        .onChange(of: stressDailyCheckInEnabled) { _, _ in
            syncNotificationPreferencesFromSettings()
            syncManagementPreferencesFromCurrentSwitches()
        }
        .onChange(of: goalRemindersEnabled) { _, newValue in
            applyGoalReminderPreference(newValue)
            syncManagementPreferencesFromCurrentSwitches()
        }
        .onChange(of: weeklySummaryEnabled) { _, _ in
            syncManagementPreferencesFromCurrentSwitches()
        }
        .onChange(of: sleepLackReminderEnabled) { _, _ in
            syncManagementPreferencesFromCurrentSwitches()
        }
        .onChange(of: reminderSettings) { _, newValue in
            HabitReminderManager.shared.save(newValue)
            applyHabitReminderSettings(newValue)
            syncNotificationPreferencesFromSettings()
            syncManagementPreferencesFromCurrentSwitches()
        }
    }

    private var notificationStatusSection: some View {
        SettingsSectionCard(title: "通知状态") {
            SettingsStatusSummaryRow(
                icon: notificationsEnabled ? "bell.badge.fill" : "bell.slash.fill",
                tint: notificationsEnabled ? Theme.Colors.mintGreen : Theme.Colors.accentRed,
                title: notificationsEnabled ? "系统通知可用" : "系统通知需要授权",
                subtitle: "\(managementPreferences.contentSummary) · \(managementPreferences.quietHoursSummary)",
                status: "\(managementPreferences.enabledReceiveTypeCount) 类"
            )
        }
    }

    private var receiveTypeSection: some View {
        settingsSection(title: "接收类型") {
            SettingsToggleDetailRow(
                icon: "bell.badge.fill",
                tint: notificationsEnabled ? Theme.Colors.mintGreen : Theme.Colors.accentRed,
                title: "系统通知",
                subtitle: notificationsEnabled ? "通知权限已开启" : "进入系统设置开启后，提醒才能送达",
                isOn: Binding(
                    get: { notificationsEnabled },
                    set: { setNotificationsEnabled($0) }
                )
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "exclamationmark.triangle.fill",
                tint: Theme.Colors.accentRed,
                title: "健康异常与安全",
                subtitle: "压力异常、心率风险和需要立刻留意的提醒",
                isOn: managementBinding(\.healthAlertsEnabled)
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "sparkles",
                tint: Color(hex: "F28C28"),
                title: "恢复建议",
                subtitle: "睡眠不足、低恢复、睡前收尾和午后重置",
                isOn: managementBinding(\.recoveryAdviceEnabled)
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "checklist",
                tint: Theme.Colors.accentBlue,
                title: "习惯与目标",
                subtitle: "喝水、情绪记录、压力打卡和目标进度",
                isOn: managementBinding(\.habitNudgesEnabled)
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "calendar.badge.clock",
                tint: Color(hex: "7D8BFF"),
                title: "报告摘要",
                subtitle: "周报、趋势回顾和阶段性健康摘要",
                isOn: managementBinding(\.summaryReportsEnabled)
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "person.2.wave.2.fill",
                tint: Color(hex: "38C793"),
                title: "陪伴与共享",
                subtitle: "好友关心、共享状态和协作提醒",
                isOn: managementBinding(\.socialCareEnabled)
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "megaphone.fill",
                tint: Color(hex: "9B7CFF"),
                title: "产品与活动",
                subtitle: "版本更新、会员权益和重要运营信息",
                isOn: managementBinding(\.productUpdatesEnabled)
            )
        }
    }

    private var contentSection: some View {
        settingsSection(title: "通知内容") {
            SettingsSegmentedControlRow(
                icon: "text.bubble.fill",
                tint: Theme.Colors.accentBlue,
                title: "内容详细程度",
                subtitle: managementPreferences.contentDetailLevel.subtitle,
                control:
                    Picker("内容详细程度", selection: managementBinding(\.contentDetailLevel)) {
                        ForEach(NotificationContentDetailLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "number.circle.fill",
                tint: Theme.Colors.accentBlue,
                title: "包含关键数值",
                subtitle: "例如睡眠时长、压力分数、喝水进度",
                isOn: managementBinding(\.includeHealthValues)
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "figure.walk.motion",
                tint: Theme.Colors.mintGreen,
                title: "包含行动建议",
                subtitle: "告诉你下一步适合做什么",
                isOn: managementBinding(\.includeActionSuggestion)
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "quote.bubble.fill",
                tint: Color(hex: "F28C28"),
                title: "包含触发原因",
                subtitle: "说明为什么现在发这条提醒",
                isOn: managementBinding(\.includeReasonExplanation)
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "chart.line.uptrend.xyaxis",
                tint: Color(hex: "7D8BFF"),
                title: "包含趋势摘要",
                subtitle: "把今天和最近状态放在一起看",
                isOn: managementBinding(\.includeTrendSummary)
            )
        }
    }

    private var deliverySection: some View {
        settingsSection(title: "送达节奏") {
            SettingsSegmentedControlRow(
                icon: "speaker.wave.2.fill",
                tint: Theme.Colors.mintGreen,
                title: "提醒方式",
                subtitle: managementPreferences.deliveryStyle.subtitle,
                control:
                    Picker("提醒方式", selection: managementBinding(\.deliveryStyle)) {
                        ForEach(NotificationDeliveryStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
            )

            Divider().padding(.leading, 86)
            NavigationLink {
                DoNotDisturbSettingsView(preferences: $managementPreferences)
            } label: {
                SettingsIconRow(
                    title: "免打扰设置",
                    symbol: "moon.zzz.fill",
                    tint: Color(hex: "5E5CE6"),
                    subtitle: managementPreferences.quietHoursSummary
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var singleReminderSection: some View {
        settingsSection(title: "具体提醒") {
            NavigationLink {
                SedentaryView(viewModel: dashboardViewModel)
            } label: {
                SettingsIconRow(
                    title: "久坐提醒",
                    symbol: "figure.seated.side.right",
                    tint: Color(hex: "2E9B68"),
                    subtitle: dashboardViewModel.sedentaryReminderEnabled
                        ? "每 \(dashboardViewModel.sedentaryReminderIntervalMinutes) 分钟提醒一次"
                        : "已关闭"
                )
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "brain.head.profile",
                tint: Color(hex: "FFB340"),
                title: "压力提醒",
                subtitle: "压力明显升高时提醒",
                isOn: $stressAlertsEnabled
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "checklist",
                tint: Theme.Colors.accentBlue,
                title: "压力每日打卡",
                subtitle: "提醒记录主观压力和备注",
                isOn: $stressDailyCheckInEnabled
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "target",
                tint: Theme.Colors.accentBlue,
                title: "目标提醒",
                subtitle: goalReminderSubtitle,
                isOn: $goalRemindersEnabled
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "moon.zzz.fill",
                tint: Color(hex: "5E5CE6"),
                title: "睡眠不足提醒",
                subtitle: "睡眠明显不足时提醒恢复",
                isOn: $sleepLackReminderEnabled
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "calendar.badge.clock",
                tint: Color(hex: "7D8BFF"),
                title: "每周摘要",
                subtitle: "每周生成健康摘要提醒",
                isOn: $weeklySummaryEnabled
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "drop.fill",
                tint: Color(hex: "32ADE6"),
                title: "每日喝水提醒",
                subtitle: reminderTimeSummary(hour: reminderSettings.waterDailyHour, minute: reminderSettings.waterDailyMinute, kind: .hydration),
                isOn: waterDailyBinding
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "timer",
                tint: Color(hex: "5DADE2"),
                title: "间隔补水提醒",
                subtitle: reminderSettings.waterNudgeEnabled ? "每 \(reminderSettings.waterNudgeIntervalMinutes) 分钟提醒一次" : "记录喝水后按间隔继续提醒",
                isOn: waterNudgeBinding
            )

            Divider().padding(.leading, 86)

            SettingsToggleDetailRow(
                icon: "heart.text.square.fill",
                tint: Theme.Colors.mintGreen,
                title: "情绪记录提醒",
                subtitle: reminderTimeSummary(hour: reminderSettings.moodDailyHour, minute: reminderSettings.moodDailyMinute, kind: .mood),
                isOn: moodDailyBinding
            )
        }
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        SettingsSectionCard(title: title) {
            content()
        }
    }

    private var waterDailyBinding: Binding<Bool> {
        Binding(
            get: { reminderSettings.waterDailyEnabled },
            set: { reminderSettings.waterDailyEnabled = $0 }
        )
    }

    private var waterNudgeBinding: Binding<Bool> {
        Binding(
            get: { reminderSettings.waterNudgeEnabled },
            set: { reminderSettings.waterNudgeEnabled = $0 }
        )
    }

    private var moodDailyBinding: Binding<Bool> {
        Binding(
            get: { reminderSettings.moodDailyEnabled },
            set: { reminderSettings.moodDailyEnabled = $0 }
        )
    }

    private func managementBinding<Value>(_ keyPath: WritableKeyPath<NotificationManagementPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { managementPreferences[keyPath: keyPath] },
            set: { managementPreferences[keyPath: keyPath] = $0 }
        )
    }

    private func syncNotificationPreferencesFromSettings() {
        let hasGoalRemindersEnabled =
            stressDailyCheckInEnabled ||
            reminderSettings.waterDailyEnabled ||
            reminderSettings.waterNudgeEnabled ||
            reminderSettings.moodDailyEnabled

        if goalRemindersEnabled != hasGoalRemindersEnabled {
            goalRemindersEnabled = hasGoalRemindersEnabled
        }
    }

    private func syncManagementPreferencesFromCurrentSwitches() {
        var next = managementPreferences
        next.healthAlertsEnabled = abnormalHealthAlertsEnabled || stressAlertsEnabled
        next.recoveryAdviceEnabled = sleepLackReminderEnabled || PersonalizedReminderCenter.shared.loadPreferences().values.contains { $0.isEnabled }
        next.habitNudgesEnabled = goalRemindersEnabled || stressDailyCheckInEnabled || hasAnyHabitReminderEnabled
        next.summaryReportsEnabled = weeklySummaryEnabled

        if next != managementPreferences {
            managementPreferences = next
        }
        NotificationManagementPreferencesStore.shared.save(next)
    }

    private func applyManagementPreferences(_ next: NotificationManagementPreferences) {
        if abnormalHealthAlertsEnabled != next.healthAlertsEnabled {
            abnormalHealthAlertsEnabled = next.healthAlertsEnabled
        }
        if stressAlertsEnabled != next.healthAlertsEnabled {
            stressAlertsEnabled = next.healthAlertsEnabled
        }
        if sleepLackReminderEnabled != next.recoveryAdviceEnabled {
            sleepLackReminderEnabled = next.recoveryAdviceEnabled
        }
        if weeklySummaryEnabled != next.summaryReportsEnabled {
            weeklySummaryEnabled = next.summaryReportsEnabled
        }

        applyHabitNudgePreference(next.habitNudgesEnabled)

        if !next.recoveryAdviceEnabled {
            PersonalizedReminderCenter.shared.cancelAllPersonalized()
        } else {
            Task {
                await PersonalizedReminderCenter.shared.evaluateAndReschedule()
            }
        }

        HabitReminderManager.shared.apply(reminderSettings)
        Task {
            await LocalNotificationScheduler.reconcilePendingRequestsForQuietHours()
        }
    }

    private func applyGoalReminderPreference(_ isEnabled: Bool) {
        let hasAnyGoalReminderEnabled =
            stressDailyCheckInEnabled ||
            reminderSettings.waterDailyEnabled ||
            reminderSettings.waterNudgeEnabled ||
            reminderSettings.moodDailyEnabled

        if isEnabled {
            guard !hasAnyGoalReminderEnabled else { return }
            stressDailyCheckInEnabled = true
            reminderSettings.waterDailyEnabled = true
            reminderSettings.moodDailyEnabled = true
            return
        }

        guard hasAnyGoalReminderEnabled else { return }
        stressDailyCheckInEnabled = false
        reminderSettings.waterDailyEnabled = false
        reminderSettings.waterNudgeEnabled = false
        reminderSettings.moodDailyEnabled = false
    }

    private var hasAnyHabitReminderEnabled: Bool {
        reminderSettings.waterDailyEnabled || reminderSettings.waterNudgeEnabled || reminderSettings.moodDailyEnabled
    }

    private func applyHabitNudgePreference(_ isEnabled: Bool) {
        if goalRemindersEnabled != isEnabled {
            goalRemindersEnabled = isEnabled
        }

        if isEnabled {
            if !stressDailyCheckInEnabled {
                stressDailyCheckInEnabled = true
            }
            guard !hasAnyHabitReminderEnabled else { return }
            reminderSettings.waterDailyEnabled = true
            reminderSettings.moodDailyEnabled = true
        } else {
            if stressDailyCheckInEnabled {
                stressDailyCheckInEnabled = false
            }
            guard hasAnyHabitReminderEnabled else { return }
            reminderSettings.waterDailyEnabled = false
            reminderSettings.waterNudgeEnabled = false
            reminderSettings.moodDailyEnabled = false
            HabitReminderManager.shared.cancelWaterNudge()
        }

        HabitReminderManager.shared.save(reminderSettings)
        HabitReminderManager.shared.apply(reminderSettings)
    }

    private func applyHabitReminderSettings(_ settings: HabitReminderSettings) {
        Task {
            let enabled = settings.waterDailyEnabled || settings.waterNudgeEnabled || settings.moodDailyEnabled
            if enabled {
                let granted = await LocalNotificationScheduler.requestAuthorizationIfNeeded()
                guard granted else {
                    await MainActor.run {
                        showNotificationDeniedAlert = true
                        reminderSettings = HabitReminderManager.shared.load()
                        syncNotificationPreferencesFromSettings()
                    }
                    return
                }
            }

            HabitReminderManager.shared.apply(settings)
            if !settings.waterNudgeEnabled {
                HabitReminderManager.shared.cancelWaterNudge()
            }
        }
    }

    private enum DailyReminderKind {
        case hydration
        case mood
    }

    private func reminderTimeSummary(hour: Int, minute: Int, kind: DailyReminderKind) -> String {
        let time = String(format: "%02d:%02d", hour, minute)
        switch kind {
        case .hydration:
            return reminderSettings.waterDailyEnabled
                ? String(localized: "每天 \(time) 提醒补水")
                : String(localized: "固定时间补水提醒")
        case .mood:
            return reminderSettings.moodDailyEnabled
                ? String(localized: "每天 \(time) 提醒记录")
                : String(localized: "每天留一点时间记录感受")
        }
    }

    private var goalReminderSubtitle: String {
        let enabledItems = [
            stressDailyCheckInEnabled ? String(localized: "压力打卡") : nil,
            reminderSettings.waterDailyEnabled ? String(localized: "每日喝水") : nil,
            reminderSettings.waterNudgeEnabled ? String(localized: "间隔补水") : nil,
            reminderSettings.moodDailyEnabled ? String(localized: "情绪记录") : nil
        ].compactMap { $0 }

        if enabledItems.isEmpty {
            return String(localized: "管理喝水和记录提醒；打开后会启用默认提醒")
        }

        return String(localized: "当前联动：\(ListFormatter.localizedString(byJoining: enabledItems))")
    }
}
