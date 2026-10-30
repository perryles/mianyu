/// 特别关注页：设计稿「特别关注」（6:124）。
/// 展示重点关注的好友状态与提醒规则；提醒规则是纯本地偏好（App Storage），
/// 不进入任何共享载荷；状态数据只来自对方已共享的最近 7 天摘要。

import SwiftUI

struct SocialSpecialFocusView: View {
    let friends: [FriendHealthProfile]

    @Environment(\.dismiss) private var dismiss

    @AppStorage(SocialSharingPreferenceKeys.specialFocusFriendIDs)
    private var encodedFocusFriendIDs = ""
    @AppStorage(SocialSharingPreferenceKeys.specialFocusNewStatus)
    private var isNewStatusReminderOn = true
    @AppStorage(SocialSharingPreferenceKeys.specialFocusWorkoutCompleted)
    private var isWorkoutCompletedReminderOn = true
    @AppStorage(SocialSharingPreferenceKeys.specialFocusSharingChanged)
    private var isSharingChangedReminderOn = true
    @AppStorage(SocialSharingPreferenceKeys.specialFocusPinnedActivity)
    private var isPinnedActivityOn = true

    private let ink = Color(hex: "12141A")
    private let secondaryInk = Color(hex: "6E7887")
    private let canvas = Color(hex: "F6F9FB")
    private let mintSoft = Color(hex: "F0FCF7")
    private let liveTint = Color(hex: "29AD73")
    private let amber = Theme.Colors.accentOrange
    private let sleepTint = Color(hex: "6C7CE0")

    private var focusFriendIDs: Set<String> {
        Set(encodedFocusFriendIDs.split(separator: "\n").map(String.init))
    }

    private var focusedFriends: [FriendHealthProfile] {
        friends.filter { focusFriendIDs.contains($0.id) }
    }

    var body: some View {
        AdaptivePageScrollView(topPadding: 8, bottomPadding: 40) {
            VStack(alignment: .leading, spacing: 20) {
                header
                introBanner
                focusList
                reminderRulesCard
            }
        }
        .background(canvas)
        .navigationTitle("特别关注")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("特别关注")
                .font(.appSystem(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(ink)
            Text("重要状态，优先看见")
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryInk)
        }
        .padding(.horizontal, 4)
    }

    private var introBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(focusedFriends.isEmpty ? String(localized: "还没有关注的好友") : String(localized: "你关注了 \(focusedFriends.count) 位好友"))
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
            Text("特别关注用于优先展示好友的新状态，不作为医疗监控或异常告警。")
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mintSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var focusList: some View {
        VStack(spacing: 10) {
            if friends.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "star")
                        .font(.appSystem(size: 18, weight: .semibold))
                        .foregroundStyle(secondaryInk)
                        .frame(width: 40, height: 40)
                        .background(canvas, in: Circle())
                    Text("成为好友后，可在这里选择希望优先看见状态的人。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryInk)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(friends) { friend in
                    focusRow(friend)
                }
            }
        }
    }

    private func focusRow(_ friend: FriendHealthProfile) -> some View {
        Button {
            toggleFocus(friend.id)
        } label: {
        HStack(spacing: 12) {
            Text(String(friend.name.prefix(1)))
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(friend.relationshipState.storyTint)
                .frame(width: 44, height: 44)
                .background(friend.relationshipState.storyTint.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text(focusSummary(friend))
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: focusFriendIDs.contains(friend.id) ? "star.fill" : "star")
                .font(.appSystem(size: 13, weight: .semibold))
                .foregroundStyle(focusFriendIDs.contains(friend.id) ? Color(hex: "FFC94D") : secondaryInk)
                .frame(width: 44, height: 44)
                .accessibilityLabel(focusFriendIDs.contains(friend.id) ? "取消特别关注" : "设为特别关注")
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func toggleFocus(_ friendID: String) {
        var ids = focusFriendIDs
        if ids.contains(friendID) { ids.remove(friendID) } else { ids.insert(friendID) }
        encodedFocusFriendIDs = ids.sorted().joined(separator: "\n")
    }

    private func focusSummary(_ friend: FriendHealthProfile) -> String {
        if friend.snapshot.highlights.validSleepDays > 0 {
            return String(localized: "昨晚睡眠 \(friend.sleepText)")
        }
        return String(localized: "近 7 天步速 \(friend.walkingText)")
    }

    private func focusBadge(_ friend: FriendHealthProfile) -> String {
        if friend.isStale { return String(localized: "缓存中") }
        if let minutes = friend.snapshot.highlights.averageSleepMinutes {
            if minutes < 360 { return String(localized: "睡眠偏少") }
        }
        if friend.snapshot.highlights.validWalkingSpeedDays > 0 {
            return String(localized: "状态良好")
        }
        return String(localized: "观察中")
    }

    private func focusBadgeTint(_ friend: FriendHealthProfile) -> Color {
        if friend.isStale { return amber }
        if let minutes = friend.snapshot.highlights.averageSleepMinutes, minutes < 360 {
            return amber
        }
        return liveTint
    }

    // MARK: - 提醒规则

    private var reminderRulesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("提醒规则")
                .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .padding(.bottom, 8)

            reminderRule("好友状态更新", detail: "特别关注的好友发布新状态", isOn: $isNewStatusReminderOn)
            Divider().padding(.leading, 16)
            reminderRule("完成运动", detail: "好友主动共享的运动已完成", isOn: $isWorkoutCompletedReminderOn)
            Divider().padding(.leading, 16)
            reminderRule("共享状态变化", detail: "好友开始或停止共享", isOn: $isSharingChangedReminderOn)
            Divider().padding(.leading, 16)
            reminderRule("重要动态置顶", detail: "优先显示在好友页顶部", isOn: $isPinnedActivityOn)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func reminderRule(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                Text(detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryInk)
            }
        }
        .tint(liveTint)
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        SocialSpecialFocusView(friends: [])
    }
}
