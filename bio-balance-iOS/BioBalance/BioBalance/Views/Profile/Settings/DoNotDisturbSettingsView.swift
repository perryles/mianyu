/// DoNotDisturbSettingsView 由设置页调用，作为「免打扰」设置入口。
/// 负责管理通知静默时间段（QuietTimeField）的起止时间配置。

import SwiftUI

struct DoNotDisturbSettingsView: View {
    @Binding var preferences: NotificationManagementPreferences

    @State private var activeTimeField: QuietTimeField?
    @State private var draftHour = 0
    @State private var draftMinute = 0

    var body: some View {
        ZStack {
            ReportsSoftBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    settingsCard
                    explanationText
                    advancedCard

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, Theme.Layout.padding)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("免打扰设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: timeSheetBinding) {
            timePickerSheet
                .presentationDetents([.height(310)])
                .presentationDragIndicator(.hidden)
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            SettingsToggleDetailRow(
                icon: "moon.zzz.fill",
                tint: Color(hex: "5E5CE6"),
                title: "开启免打扰",
                subtitle: preferences.quietHoursEnabled ? "已在 \(preferences.quietHoursTimeRangeText) 暂停普通提醒" : "开启后按下方时间段暂停普通提醒",
                isOn: quietHoursEnabledBinding
            )

            Divider().padding(.leading, 86)

            quietSummaryRow

            Divider().padding(.leading, 86)

            quietTimeRow(
                title: "开始时间",
                value: preferences.quietStartTimeText,
                field: .start
            )
            .disabled(!preferences.quietHoursEnabled)
            .opacity(preferences.quietHoursEnabled ? 1 : 0.42)

            Divider().padding(.leading, 86)

            quietTimeRow(
                title: "结束时间",
                value: preferences.quietEndTimeText,
                field: .end
            )
            .disabled(!preferences.quietHoursEnabled)
            .opacity(preferences.quietHoursEnabled ? 1 : 0.42)
        }
        .settingsCardSurface(paddingTop: 0, paddingBottom: 0)
    }

    private var quietSummaryRow: some View {
        HStack(spacing: 16) {
            Text("自定义时间")
                .font(Theme.Typography.scaled(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)

            Spacer()

            Text(preferences.quietHoursTimeRangeText)
                .font(Theme.Typography.scaled(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(preferences.quietHoursEnabled ? Color(hex: "101F38") : Theme.Colors.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var explanationText: some View {
        Text("免打扰时段里，眠屿会暂停普通健康提醒、习惯提醒和报告摘要。喝水、久坐等高频提醒也会遵守夜间保护时段，避免在休息时间打断你。如果需要接收高风险健康异常，可以在下方开启穿透提醒。")
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Colors.textSecondary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
    }

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("例外")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                SettingsToggleDetailRow(
                    icon: "shield.lefthalf.filled",
                    tint: Theme.Colors.accentRed,
                    title: "高风险健康异常穿透",
                    subtitle: "开启后，严重异常提醒可在免打扰时段送达",
                    isOn: criticalBypassBinding
                )
            }
            .settingsCardSurface(paddingTop: 0, paddingBottom: 0)
            .disabled(!preferences.quietHoursEnabled)
            .opacity(preferences.quietHoursEnabled ? 1 : 0.42)
        }
    }

    private func quietTimeRow(title: String, value: String, field: QuietTimeField) -> some View {
        Button {
            presentPicker(for: field)
        } label: {
            HStack(spacing: 16) {
                Text(title)
                    .font(Theme.Typography.scaled(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Text(value)
                    .font(Theme.Typography.scaled(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .monospacedDigit()

                Image(systemName: Theme.Icons.chevronRight)
                    .font(.appSystem(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var timePickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") {
                    activeTimeField = nil
                }
                .font(Theme.Typography.scaled(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "6B5FA8"))

                Spacer()

                Button("确定") {
                    applyDraftTime()
                }
                .font(Theme.Typography.scaled(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.accentBlue)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 6)

            HStack(spacing: 0) {
                Picker("小时", selection: $draftHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d", hour)).tag(hour)
                    }
                }
                .pickerStyle(.wheel)

                Text("小时")
                    .font(Theme.Typography.scaled(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(width: 56, alignment: .leading)

                Picker("分钟", selection: $draftMinute) {
                    ForEach(0..<60, id: \.self) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .pickerStyle(.wheel)

                Text("分钟")
                    .font(Theme.Typography.scaled(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(width: 56, alignment: .leading)
            }
            .frame(height: 236)
            .padding(.horizontal, 24)
        }
        .background(Theme.Colors.pageBackground.ignoresSafeArea())
    }

    private var quietHoursEnabledBinding: Binding<Bool> {
        Binding(
            get: { preferences.quietHoursEnabled },
            set: { preferences.quietHoursEnabled = $0 }
        )
    }

    private var criticalBypassBinding: Binding<Bool> {
        Binding(
            get: { preferences.criticalAlertsBypassQuietHours },
            set: { preferences.criticalAlertsBypassQuietHours = $0 }
        )
    }

    private var timeSheetBinding: Binding<Bool> {
        Binding(
            get: { activeTimeField != nil },
            set: { isPresented in
                if !isPresented {
                    activeTimeField = nil
                }
            }
        )
    }

    private func presentPicker(for field: QuietTimeField) {
        let totalMinutes = field == .start ? preferences.quietStartTotalMinutes : preferences.quietEndTotalMinutes
        draftHour = totalMinutes / 60
        draftMinute = totalMinutes % 60
        activeTimeField = field
    }

    private func applyDraftTime() {
        guard let activeTimeField else { return }
        let totalMinutes = draftHour * 60 + draftMinute
        switch activeTimeField {
        case .start:
            preferences.setQuietStart(totalMinutes: totalMinutes)
        case .end:
            preferences.setQuietEnd(totalMinutes: totalMinutes)
        }
        self.activeTimeField = nil
    }
}

private enum QuietTimeField {
    case start
    case end
}

#Preview {
    NavigationStack {
        DoNotDisturbSettingsView(preferences: .constant(NotificationManagementPreferences()))
    }
}
