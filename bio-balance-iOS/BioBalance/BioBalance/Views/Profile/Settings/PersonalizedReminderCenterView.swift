/// PersonalizedReminderCenterView 由设置页调用，作为「个性化提醒中心」入口。
/// 负责展示个性化提醒偏好设置、推荐列表和通知权限状态。

import SwiftUI

struct PersonalizedReminderCenterView: View {
    @AppStorage("app_font_scale_level") private var appFontScaleLevelRaw: Int = 2
    @State private var preferences: [PersonalizedReminderKind: PersonalizedReminderPreference] = PersonalizedReminderCenter.shared.loadPreferences()
    @State private var recommendations: [PersonalizedReminderRecommendation] = []
    @State private var isLoading = true
    @State private var showNotificationDeniedAlert = false
    @State private var notificationAuthorized = false

    private var appFontScaleLevel: AppFontScaleLevel {
        AppFontScaleLevel(rawValue: appFontScaleLevelRaw) ?? .two
    }

    private var recommendationCount: Int {
        recommendations.filter(\.isRecommended).count
    }

    private var readinessText: String {
        recommendations.first(where: { $0.kind == .lowRecovery })?.contextSummary ?? "等待更多恢复线索"
    }

    var body: some View {
        ProfileSettingsPage(title: "个性化提醒编排中心", subtitle: "先看推荐，再手动决定哪些提醒真正参与调度。") {
            heroCard

            ProfileSection(title: "恢复核心四件套") {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                } else {
                    ForEach(PersonalizedReminderKind.allCases) { kind in
                        PersonalizedReminderCard(
                            kind: kind,
                            preference: binding(for: kind),
                            recommendation: recommendation(for: kind),
                            onToggle: { isEnabled in
                                handleToggle(kind: kind, isEnabled: isEnabled)
                            },
                            onTimeChanged: { hour, minute in
                                handleTimeChange(kind: kind, hour: hour, minute: minute)
                            }
                        )

                        if kind != PersonalizedReminderKind.allCases.last {
                            Divider().padding(.leading, 72)
                        }
                    }
                }
            }

            ProfileSection(title: "说明") {
                Text("系统会先根据你的睡眠、恢复、久坐、自然光和咖啡因上下文，帮你判断今天更适合推进、重置、保护还是收尾。只有你明确开启后，这些提醒才会真正参与本地通知编排。")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(4)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)

                Divider().padding(.leading, 18)

                ProfileInfoRow(title: "推荐数量", value: "\(recommendationCount) 项")
                ProfileInfoRow(title: "当前通知权限", value: notificationAuthorized ? "已开启" : "未开启")
            }

            ProfileSection(title: "周期修饰") {
                Text("周期阶段只会影响提醒理由和文案强度，不会额外凭空生成新的提醒种类。经期和黄体期会更偏向“保节律、降刺激、留恢复余量”，把工作密度和收尾节奏再收一点。")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(4)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
        }
        .alert("通知未开启", isPresented: $showNotificationDeniedAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请先在系统设置中开启通知权限，个性化提醒才能真正送达。")
        }
        .task {
            await reload()
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前恢复倾向")
                        .font(Theme.Typography.scaled(size: 12, weight: .bold, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textTertiary)

                    Text(readinessText)
                        .font(Theme.Typography.scaled(size: 24, weight: .black, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(notificationAuthorized ? "通知权限已就绪，开启后会按本地上下文重排提醒。" : "当前还没拿到通知权限，建议先授权再开启策略。")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 10) {
                    heroPill(title: "推荐", value: "\(recommendationCount)")
                    heroPill(title: "已启用", value: "\(preferences.values.filter(\.isEnabled).count)")
                }
            }
        }
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private func heroPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.Typography.scaled(size: 11, weight: .bold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.scaled(size: 18, weight: .black, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func recommendation(for kind: PersonalizedReminderKind) -> PersonalizedReminderRecommendation? {
        recommendations.first(where: { $0.kind == kind })
    }

    private func binding(for kind: PersonalizedReminderKind) -> Binding<PersonalizedReminderPreference> {
        Binding(
            get: {
                preferences[kind] ?? PersonalizedReminderPreference(kind: kind)
            },
            set: { newValue in
                preferences[kind] = newValue
            }
        )
    }

    @MainActor
    private func reload() async {
        preferences = PersonalizedReminderCenter.shared.loadPreferences()
        recommendations = await PersonalizedReminderCenter.shared.buildRecommendations()
        let status = await LocalNotificationScheduler.authorizationStatus()
        notificationAuthorized = status == .authorized || status == .provisional
        isLoading = false
    }

    private func persist() {
        PersonalizedReminderCenter.shared.savePreferences(preferences)
        Task {
            await PersonalizedReminderCenter.shared.evaluateAndReschedule()
        }
    }

    private func handleTimeChange(kind: PersonalizedReminderKind, hour: Int, minute: Int) {
        var current = preferences[kind] ?? PersonalizedReminderPreference(kind: kind)
        current.hour = hour
        current.minute = minute
        preferences[kind] = current
        persist()
    }

    private func handleToggle(kind: PersonalizedReminderKind, isEnabled: Bool) {
        Task {
            if isEnabled {
                let granted = await LocalNotificationScheduler.requestAuthorizationIfNeeded()
                guard granted else {
                    await MainActor.run {
                        var current = preferences[kind] ?? PersonalizedReminderPreference(kind: kind)
                        current.isEnabled = false
                        preferences[kind] = current
                        notificationAuthorized = false
                        showNotificationDeniedAlert = true
                    }
                    return
                }
            }

            await MainActor.run {
                if isEnabled, let recommendation = recommendation(for: kind) {
                    var current = preferences[kind] ?? PersonalizedReminderPreference(kind: kind)
                    current.lastAdoptedRecommendationAt = Date()
                    current.lastAdoptedRecommendationVersion = recommendation.recommendationVersion
                    preferences[kind] = current
                }
                if isEnabled {
                    notificationAuthorized = true
                }
                persist()
            }
        }
    }
}

private struct PersonalizedReminderCard: View {
    let kind: PersonalizedReminderKind
    @Binding var preference: PersonalizedReminderPreference
    let recommendation: PersonalizedReminderRecommendation?
    let onToggle: (Bool) -> Void
    let onTimeChanged: (Int, Int) -> Void

    @State private var pickedTime: Date

    init(
        kind: PersonalizedReminderKind,
        preference: Binding<PersonalizedReminderPreference>,
        recommendation: PersonalizedReminderRecommendation?,
        onToggle: @escaping (Bool) -> Void,
        onTimeChanged: @escaping (Int, Int) -> Void
    ) {
        self.kind = kind
        self._preference = preference
        self.recommendation = recommendation
        self.onToggle = onToggle
        self.onTimeChanged = onTimeChanged

        var components = DateComponents()
        components.hour = preference.wrappedValue.hour
        components.minute = preference.wrappedValue.minute
        _pickedTime = State(initialValue: Calendar.current.date(from: components) ?? Date())
    }

    private var accent: Color { Color(hex: kind.accentHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent.opacity(0.14))
                    Image(systemName: kind.symbol)
                        .font(.appSystem(size: 18, weight: .bold))
                        .foregroundColor(accent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(kind.title)
                            .font(Theme.Typography.bodyMedium)
                            .foregroundColor(Theme.Colors.textPrimary)

                        if recommendation?.isRecommended == true {
                            Text("推荐")
                                .font(Theme.Typography.scaled(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(accent.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(recommendation?.reason ?? "继续累积健康上下文后，这里会给出更贴近当日状态的建议。")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: Binding(
                    get: { preference.isEnabled },
                    set: { newValue in
                        preference.isEnabled = newValue
                        onToggle(newValue)
                    }
                ))
                .labelsHidden()
                .tint(Theme.Colors.mintGreen)
            }

            HStack {
                Text("默认时间")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textTertiary)

                Spacer()

                DatePicker(
                    "",
                    selection: $pickedTime,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .onChange(of: pickedTime) { _, newValue in
                    let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    preference.hour = components.hour ?? preference.hour
                    preference.minute = components.minute ?? preference.minute
                    onTimeChanged(preference.hour, preference.minute)
                }
            }

            if let recommendation {
                Text(recommendation.body)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .onAppear {
            var components = DateComponents()
            components.hour = preference.hour
            components.minute = preference.minute
            pickedTime = Calendar.current.date(from: components) ?? pickedTime
        }
    }
}
