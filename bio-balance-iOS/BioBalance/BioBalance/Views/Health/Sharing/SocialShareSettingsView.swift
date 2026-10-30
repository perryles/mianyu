/// 好友分享设置页：设计稿「好友分享设置」（4:52）。
/// 分享给谁（胶囊组）+ 共享的数据（开关行）+ 实时状态开关 + 隐私保护（停止全部分享）。
/// 可实际生效的开关严格对应 ICLOUD_DATA_ARCHITECTURE 的白名单合同
/// （睡眠、步速、粗略位置）；设计稿中的心率/压力/体重在合同扩展前
/// 展示为「暂不支持」，不可开启。

import SwiftUI

/// 设计稿「共享的数据」的类别；仅白名单合同内的类别可实际开启。
nonisolated enum ShareDataCategory: String, CaseIterable, Identifiable {
    case sleep
    case walking
    case heartRate
    case stress
    case weight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return String(localized: "睡眠")
        case .walking: return String(localized: "运动")
        case .heartRate: return String(localized: "心率")
        case .stress: return String(localized: "压力")
        case .weight: return String(localized: "体重")
        }
    }

    var detail: String {
        switch self {
        case .sleep: return String(localized: "睡眠时长、阶段、入睡/醒来时间")
        case .walking: return String(localized: "步数、距离、活动消耗")
        case .heartRate: return String(localized: "静息心率与趋势")
        case .stress: return String(localized: "综合压力评分与趋势")
        case .weight: return String(localized: "体重与身体成分")
        }
    }

    /// 设计稿默认开：睡眠/运动/心率开，压力/体重关；其中心率/压力/体重不可改。
    var defaultOn: Bool {
        switch self {
        case .sleep, .walking, .heartRate: return true
        case .stress, .weight: return false
        }
    }

    var isSupported: Bool {
        switch self {
        case .sleep, .walking: return true
        case .heartRate, .stress, .weight: return false
        }
    }
}

struct SocialShareSettingsView: View {
    let friendName: String?
    var onSave: (FriendSharePermission) -> Void = { _ in }
    var onStopAllSharing: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SocialSharingDataPolicy.approximateLocationSharingEnabledKey)
    private var isLocationSharingEnabled = false
    @AppStorage(SocialSharingPreferenceKeys.profileSearchable)
    private var isProfileSearchable = false
    @State private var selectedAudience: ShareAudience = .allFriends
    @State private var enabledCategories: Set<ShareDataCategory> = []
    @State private var isRealtimeStatusEnabled = false
    @State private var isLastUpdatedVisible = true
    @State private var confirmingStopAll = false

    enum ShareAudience: String, CaseIterable, Identifiable {
        case allFriends
        case specialFocus
        case privateOnly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .allFriends: return String(localized: "所有好友")
            case .specialFocus: return String(localized: "特别关注")
            case .privateOnly: return String(localized: "不公开")
            }
        }
    }

    private let ink = Color(hex: "12141A")
    private let secondaryInk = Color(hex: "6E7887")
    private let canvas = Color(hex: "F6F9FB")
    private let trackOff = Color(hex: "D6DBE3")
    private let toggleOn = Color(hex: "29AD73")
    private let danger = Color(hex: "F04D59")

    var body: some View {
        AdaptivePageScrollView(topPadding: 8, bottomPadding: 40) {
            VStack(alignment: .leading, spacing: 16) {
                audienceCard
                discoverabilityCard
                sharedDataCard
                realtimeCard
                privacyCard
            }
        }
        .background(canvas)
        .navigationTitle("分享设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .onAppear {
            let permission = HealthKitSharingService.shared.sharePermission()
            var restoredCategories = Set<ShareDataCategory>()
            if permission.sleep { restoredCategories.insert(.sleep) }
            if permission.activity { restoredCategories.insert(.walking) }
            enabledCategories = restoredCategories
            isRealtimeStatusEnabled = permission.liveStatus
            isLastUpdatedVisible = permission.showsLastUpdated
        }
        .alert("停止全部分享？", isPresented: $confirmingStopAll) {
            Button("取消", role: .cancel) { }
            Button("停止共享", role: .destructive) {
                isRealtimeStatusEnabled = false
                isLastUpdatedVisible = false
                isLocationSharingEnabled = false
                selectedAudience = .privateOnly
                saveAndApply()
                onStopAllSharing()
            }
        } message: {
            Text("停止后，\(friendName ?? "好友")将无法继续看到你的健康摘要更新。")
        }
        .onDisappear { saveAndApply() }
    }

    private var discoverabilityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle("好友发现")
            Toggle(isOn: $isProfileSearchable) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("允许通过用户 ID 找到我")
                        .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                    Text("关闭后仍可使用你主动分享的邀请链接")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryInk)
                }
            }
            .tint(toggleOn)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func saveAndApply() {
        let permission = FriendSharePermission(
            sleep: enabledCategories.contains(.sleep),
            activity: enabledCategories.contains(.walking),
            liveStatus: isRealtimeStatusEnabled,
            showsLastUpdated: isLastUpdatedVisible
        )
        HealthKitSharingService.shared.saveSharePermission(permission)
        onSave(permission)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("分享设置")
                .font(.appSystem(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(ink)
            Text("你可以随时调整好友能看到什么")
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryInk)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 分享给谁

    private var audienceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle("分享给谁")
            HStack(spacing: 8) {
                ForEach(ShareAudience.allCases) { audience in
                    let isSelected = selectedAudience == audience
                    Button {
                        if audience == .privateOnly {
                            confirmingStopAll = true
                        } else {
                            selectedAudience = audience
                        }
                    } label: {
                        VStack(spacing: 1) {
                            Text(audience.title)
                            if audience == .specialFocus { Text("暂不支持").font(.system(size: 8)) }
                        }
                            .font(.appSystem(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                            .foregroundStyle(isSelected ? Color.white : secondaryInk)
                            .padding(.horizontal, 14)
                            .frame(minWidth: 72, minHeight: 30)
                            .background(Capsule().fill(isSelected ? ink : Color(hex: "F2F5F7")))
                    }
                    .buttonStyle(.plain)
                    .disabled(audience == .specialFocus)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - 共享的数据

    private var sharedDataCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            cardTitle("共享的数据")
                .padding(.bottom, 8)

            ForEach(ShareDataCategory.allCases) { category in
                categoryRow(category)
                if category != ShareDataCategory.allCases.last {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func categoryRow(_ category: ShareDataCategory) -> some View {
        let isOn = enabledCategories.contains(category)
        return Button {
            guard category.isSupported else { return }
            if isOn {
                enabledCategories.remove(category)
            } else {
                enabledCategories.insert(category)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(category.title)
                            .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(ink)
                        if !category.isSupported {
                            Text("暂不支持")
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(secondaryInk.opacity(0.75))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(canvas, in: Capsule())
                        }
                    }
                    Text(category.detail)
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                // 设计稿的自绘开关：48x28 胶囊 + 22 白色圆钮。
                Capsule()
                    .fill(category.isSupported ? (isOn ? toggleOn : trackOff) : trackOff.opacity(0.7))
                    .frame(width: 48, height: 28)
                    .overlay {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .offset(x: isOn ? 11 : -11)
                    }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!category.isSupported)
        .accessibilityLabel("\(category.title)，\(category.detail)")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // MARK: - 实时状态

    private var realtimeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            cardTitle("实时状态")
                .padding(.bottom, 8)

            Toggle(isOn: $isRealtimeStatusEnabled) {
                Text("允许显示「正在睡觉 / 运动中」")
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
            }
            .tint(toggleOn)
            .padding(.vertical, 6)

            Divider().padding(.leading, 16)

            Toggle(isOn: $isLastUpdatedVisible) {
                Text("显示最后更新时间")
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
            }
            .tint(toggleOn)
            .padding(.vertical, 6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - 隐私保护

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle("隐私保护")

            Text("好友只能查看你主动共享的数据，不会看到原始 Health 数据。")
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                confirmingStopAll = true
            } label: {
                Text("停止全部分享")
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(danger)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(danger.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("停止向所有好友共享健康摘要")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func cardTitle(_ title: String) -> some View {
        Text(title)
            .font(.appSystem(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(ink)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    NavigationStack {
        SocialShareSettingsView(friendName: "小鱼")
    }
}
