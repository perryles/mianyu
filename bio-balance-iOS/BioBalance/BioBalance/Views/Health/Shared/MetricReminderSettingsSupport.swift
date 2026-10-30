/// MetricReminderSettingsSupport 作为指标提醒设置的共享数据结构。
/// 负责定义 MetricReminderSettings（开关、提前天数、时分）供多个指标详情页复用。

import SwiftUI

struct MetricReminderSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var leadDays: Int
    var hour: Int
    var minute: Int

    init(isEnabled: Bool = false, leadDays: Int = 0, hour: Int = 20, minute: Int = 0) {
        self.isEnabled = isEnabled
        self.leadDays = leadDays
        self.hour = hour
        self.minute = minute
    }

    var notificationDate: Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    var timeSummary: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

final class MetricReminderStore {
    static let shared = MetricReminderStore()

    private let defaults = UserDefaults.standard
    private let keyPrefix = "metric.reminder.settings."
    private let identifierPrefix = "metric.reminder.notification."

    func load(for metricKey: String) -> MetricReminderSettings {
        guard let data = defaults.data(forKey: keyPrefix + metricKey),
              let value = try? JSONDecoder().decode(MetricReminderSettings.self, from: data) else {
            return MetricReminderSettings()
        }
        return value
    }

    func save(_ settings: MetricReminderSettings, for metricKey: String) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: keyPrefix + metricKey)
    }

    func apply(_ settings: MetricReminderSettings, for metricKey: String, title: String) {
        let identifier = identifierPrefix + metricKey
        guard settings.isEnabled else {
            LocalNotificationScheduler.cancel(identifiers: [identifier])
            return
        }

        LocalNotificationScheduler.scheduleDaily(
            identifier: identifier,
            hour: settings.hour,
            minute: settings.minute,
            title: String(localized: "🔍 \(title)小巡查"),
            body: settings.leadDays == 0
                ? String(localized: "打卡时间到～来瞄一眼\(title)有没有新动静。")
                : String(localized: "提前 \(settings.leadDays) 天开始盯一盯\(title)，心里更有底。")
        )
    }
}

struct MetricReminderSettingsView: View {
    let metricKey: String
    let metricTitle: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_font_scale_level") private var appFontScaleLevelRaw: Int = 2
    @State private var settings: MetricReminderSettings
    @State private var notificationTime: Date
    @State private var showNotificationDeniedAlert = false

    init(metricKey: String, metricTitle: String) {
        self.metricKey = metricKey
        self.metricTitle = metricTitle
        let initialSettings = MetricReminderStore.shared.load(for: metricKey)
        _settings = State(initialValue: initialSettings)
        _notificationTime = State(initialValue: initialSettings.notificationDate)
    }

    private var appFontScaleLevel: AppFontScaleLevel {
        AppFontScaleLevel(rawValue: appFontScaleLevelRaw) ?? .two
    }

    private var accentColor: Color {
        switch metricKey {
        case "hrv":
            return Color(hex: "69A89C")
        case "resting_heart_rate":
            return Color(hex: "EF5350")
        case "vo2max":
            return Color(hex: "F06449")
        case "sunlight":
            return Color(hex: "F4A259")
        case "walking_asymmetry":
            return Color(hex: "33A6DA")
        case "wrist_temperature":
            return Color(hex: "8266C6")
        default:
            return Theme.Colors.mintGreen
        }
    }

    private var secondaryAccent: Color {
        accentColor.opacity(0.18)
    }

    private var statusTitle: String {
        settings.isEnabled ? "提醒已开启" : "暂未开启"
    }

    private var statusSummary: String {
        if settings.isEnabled {
            return settings.leadDays == 0
                ? "每天 \(settings.timeSummary) 提醒查看\(metricTitle)。"
                : "从提前 \(settings.leadDays) 天开始，每天 \(settings.timeSummary) 提醒留意\(metricTitle)。"
        }
        return String(localized: "开启后可在固定时间收到\(metricTitle)提醒。")
    }

    private var cadenceSummary: String {
        settings.leadDays == 0 ? "当天提醒" : "提前 \(settings.leadDays) 天"
    }

    var body: some View {
        ProfileSettingsPage(title: "设置提醒", subtitle: "为\(metricTitle)设置固定提醒时间和提前关注节奏。") {
            MetricReminderHeroCard(
                metricTitle: metricTitle,
                title: statusTitle,
                summary: statusSummary,
                accentColor: accentColor,
                secondaryAccent: secondaryAccent,
                isEnabled: settings.isEnabled
            )

            HStack(spacing: 10) {
                MetricReminderOverviewPill(
                    title: "状态",
                    value: settings.isEnabled ? "开启" : "关闭",
                    tint: accentColor
                )
                MetricReminderOverviewPill(
                    title: "提前",
                    value: cadenceSummary,
                    tint: Color(hex: "7D8BFF")
                )
                MetricReminderOverviewPill(
                    title: "时间",
                    value: settings.timeSummary,
                    tint: Color(hex: "FFB340")
                )
            }

            ProfileSection(title: "提醒内容") {
                MetricReminderToggleRow(
                    title: "是否开启",
                    subtitle: settings.isEnabled ? "已为\(metricTitle)安排提醒" : "关闭后不会发送这项提醒",
                    icon: "bell.badge.fill",
                    tint: accentColor,
                    isOn: Binding(
                        get: { settings.isEnabled },
                        set: { newValue in
                            settings.isEnabled = newValue
                            persist()
                        }
                    )
                )

                Divider().padding(.leading, 86)

                MetricReminderLeadDaysRow(
                    value: Binding(
                        get: { settings.leadDays },
                        set: { newValue in
                            settings.leadDays = newValue
                            persist()
                        }
                    ),
                    accentColor: accentColor
                )

                Divider().padding(.leading, 86)

                MetricReminderTimeRow(
                    time: $notificationTime,
                    accentColor: accentColor
                )
            }

            ProfileSection(title: "提醒说明") {
                ProfileInfoRow(title: "提醒对象", value: metricTitle)
                ProfileInfoRow(title: "触达频率", value: settings.isEnabled ? "每天一次" : "未开启")
                ProfileInfoRow(title: "提前策略", value: cadenceSummary)
                ProfileInfoRow(title: "通知时间", value: settings.timeSummary)
            }
        }
        .navigationTitle("设置提醒")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
        .alert("通知未开启", isPresented: $showNotificationDeniedAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("请先在系统设置中开启通知权限，提醒才会真正送达。")
        }
        .onChange(of: notificationTime) { _, newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            settings.hour = components.hour ?? settings.hour
            settings.minute = components.minute ?? settings.minute
            persist()
        }
    }

    private func persist() {
        let snapshot = settings
        Task {
            if snapshot.isEnabled {
                let granted = await LocalNotificationScheduler.requestAuthorizationIfNeeded()
                guard granted else {
                    await MainActor.run {
                        settings.isEnabled = false
                        MetricReminderStore.shared.save(settings, for: metricKey)
                        MetricReminderStore.shared.apply(settings, for: metricKey, title: metricTitle)
                        showNotificationDeniedAlert = true
                    }
                    return
                }
            }

            MetricReminderStore.shared.save(snapshot, for: metricKey)
            MetricReminderStore.shared.apply(snapshot, for: metricKey, title: metricTitle)
        }
    }
}

private struct MetricReminderHeroCard: View {
    let metricTitle: String
    let title: String
    let summary: String
    let accentColor: Color
    let secondaryAccent: Color
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.14))
                    Image(systemName: isEnabled ? "bell.badge.fill" : "bell.slash.fill")
                        .font(.appSystem(size: 24, weight: .bold))
                        .foregroundColor(accentColor)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 6) {
                    Text(metricTitle)
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(summary)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(isEnabled ? "已启用" : "未启用")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(accentColor.opacity(0.10), in: Capsule())
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.96), secondaryAccent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: accentColor.opacity(0.10), radius: 18, x: 0, y: 10)
    }
}

private struct MetricReminderOverviewPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.Typography.scaled(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.scaled(size: 14, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MetricReminderToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(tint.opacity(0.14))
                Image(systemName: icon)
                    .font(Theme.Typography.scaled(size: 17, weight: .bold))
                    .foregroundColor(tint)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(tint)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct MetricReminderLeadDaysRow: View {
    @Binding var value: Int
    let accentColor: Color

    private let quickOptions = [0, 1, 3, 7]

    var body: some View {
        VStack(spacing: 10) {
            MetricReminderRowShell(
                title: "提前几天",
                subtitle: value == 0 ? "当天提醒" : "提前 \(value) 天开始提醒",
                icon: "calendar.badge.clock"
            ) {
                Text(value == 0 ? "当天" : "\(value) 天")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(accentColor.opacity(0.10), in: Capsule())
            }

            HStack(spacing: 8) {
                ForEach(quickOptions, id: \.self) { option in
                    Button {
                        value = option
                    } label: {
                        Text(option == 0 ? "当天" : "\(option) 天")
                            .font(Theme.Typography.scaled(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(value == option ? .white : Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(value == option ? accentColor : Color(hex: "F5F8FF"))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)

            Stepper("", value: $value, in: 0...7)
                .labelsHidden()
                .tint(accentColor)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
        }
    }
}

private struct MetricReminderTimeRow: View {
    @Binding var time: Date
    let accentColor: Color

    var body: some View {
        VStack(spacing: 10) {
            MetricReminderRowShell(
                title: "通知时间",
                subtitle: time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)),
                icon: "clock.fill"
            ) {
                EmptyView()
            }

            DatePicker("", selection: $time, displayedComponents: [.hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(accentColor.opacity(0.08))
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }
}

private struct MetricReminderRowShell<Trailing: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Theme.Colors.mintGreen.opacity(0.14))
                Image(systemName: icon)
                    .font(Theme.Typography.scaled(size: 17, weight: .bold))
                    .foregroundColor(Theme.Colors.mintGreen)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            trailing
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
