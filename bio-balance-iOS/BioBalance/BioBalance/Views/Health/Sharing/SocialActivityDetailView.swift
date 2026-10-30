/// 好友动态详情页：设计稿「好友动态详情」（6:4）。
/// 展示单条好友动态的完整摘要（运动大卡 / 指标宫格）与互动区（点赞、鼓励）；
/// 数据边界遵循 ICLOUD_DATA_ARCHITECTURE：只呈现对方主动共享的最近 7 天只读摘要。
/// 点赞与鼓励是本机 UI 状态（表情回应暂无跨设备通道），不写入共享载荷。

import SwiftUI

struct SocialActivityDetailView: View {
    let friend: FriendHealthProfile
    /// 打开完整好友档案（共享详情/待办等）；由容器决定呈现方式。
    var onOpenProfile: ((FriendHealthProfile) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var cheeredKinds: Set<CheerKind> = []
    @State private var showingCheerComposer = false
    @State private var cheerDraft = ""

    private let ink = Color(hex: "12141A")
    private let secondaryInk = Color(hex: "6E7887")
    private let canvas = Color(hex: "F6F9FB")
    private let liveTint = Color(hex: "29AD73")
    private let liveSoft = Color(hex: "E5F7F0")
    private let trackInk = Color(hex: "EDF0F5")
    private let walkTint = Color(hex: "3FBF9F")
    private let heartTint = Color(hex: "D1C9FF")
    private let paceTint = Color(hex: "B8DEFF")
    private let climbTint = Color(hex: "FFE58C")

    enum CheerKind: String, CaseIterable, Identifiable, Hashable {
        case heart
        case clap
        case muscle

        var id: String { rawValue }

        var emoji: String {
            switch self {
            case .heart: return "❤️"
            case .clap: return "👏"
            case .muscle: return "💪"
            }
        }
    }

    var body: some View {
        AdaptivePageScrollView(topPadding: 8, bottomPadding: 40) {
            VStack(alignment: .leading, spacing: 20) {
                header
                highlightCard
                metricGrid
                interactionCard
            }
        }
        .background(canvas)
        .navigationTitle("好友动态")
        .navigationBarTitleDisplayMode(.inline)
        .alert("说点什么", isPresented: $showingCheerComposer) {
            TextField("说点什么…", text: $cheerDraft)
            Button("发送", role: .none) {
                if !cheerDraft.isEmpty {
                    cheeredKinds.insert(.clap)
                    cheerDraft = ""
                }
            }
            Button("取消", role: .cancel) { cheerDraft = "" }
        } message: {
            Text("鼓励语仅保存在本机，跨设备互动通道将在后续版本开放。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(String(friend.name.prefix(1)))
                .font(.appSystem(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(friend.relationshipState.storyTint)
                .frame(width: 46, height: 46)
                .background(friend.relationshipState.storyTint.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                Text(headerSubtitle)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryInk)
            }
            Spacer(minLength: 8)
            if let onOpenProfile {
                Button {
                    onOpenProfile(friend)
                } label: {
                    Text("完整档案")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(trackInk, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private var headerSubtitle: String {
        String(localized: "\(friend.name) · \(relativeUpdatedText)")
    }

    // MARK: - 摘要大卡

    /// 设计稿的运动大卡：大号距离 + 配速行 + 浅绿结论条；无运动样本时展示睡眠。
    private var highlightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(activityTitle)
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
            Text(primaryValue)
                .font(.appSystem(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(secondaryLine)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryInk)

            Label(conclusionText, systemImage: "checkmark.circle.fill")
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(liveTint)
                .padding(.horizontal, 12)
                .frame(minHeight: 40, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(liveSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - 指标宫格

    /// 设计稿的 2×2 指标宫格（平均心率/步频/配速/爬升），
    /// 摘要合同只携带睡眠与步速，宫格用合同内指标填充。
    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            metricCard(symbol: "moon.fill", tint: heartTint, title: "平均睡眠", value: sleepValue)
            metricCard(symbol: "figure.walk", tint: walkTint, title: "平均步速", value: walkingValue)
            metricCard(symbol: "bed.double.fill", tint: paceTint, title: "有效睡眠", value: String(localized: "\(friend.snapshot.highlights.validSleepDays)/7 晚"))
            metricCard(symbol: "checkmark.seal.fill", tint: climbTint, title: "有效步速", value: String(localized: "\(friend.snapshot.highlights.validWalkingSpeedDays)/7 天"))
        }
    }

    private func metricCard(symbol: String, tint: Color, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title)
                    .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryInk)
            }
            Text(value)
                .font(.appSystem(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 互动区

    /// 设计稿的「3 人点赞 · 2 条鼓励」+ 表情回应行 + 评论输入占位。
    private var interactionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(interactionSummary)
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(secondaryInk)

            HStack(spacing: 10) {
                ForEach(CheerKind.allCases) { kind in
                    let isOn = cheeredKinds.contains(kind)
                    Button {
                        if isOn {
                            cheeredKinds.remove(kind)
                        } else {
                            cheeredKinds.insert(kind)
                        }
                    } label: {
                        Text(kind.emoji)
                            .font(.appSystem(size: 16, weight: .semibold))
                            .frame(width: 46, height: 38)
                            .background(isOn ? liveSoft : trackInk, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind == .heart ? "点赞" : kind == .clap ? "鼓掌" : "加油")
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }

            Button {
                showingCheerComposer = true
            } label: {
                Text("说点什么…")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(trackInk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var interactionSummary: String {
        let count = cheeredKinds.count
        return count == 0
            ? String(localized: "做第一个鼓励 TA 的人")
            : String(localized: "你送出了 \(count) 个鼓励")
    }

    // MARK: - 派生数据

    private var activityTitle: String {
        if let action = friend.snapshot.sharedActionRecords.first {
            return action.summaryText
        }
        return friend.snapshot.highlights.validSleepDays > 0 ? String(localized: "最近睡眠") : String(localized: "最近步速")
    }

    private var primaryValue: String {
        if friend.snapshot.highlights.validSleepDays > 0 {
            return friend.sleepText
        }
        return friend.walkingText
    }

    private var secondaryLine: String {
        let highlights = friend.snapshot.highlights
        if highlights.averageSleepMinutes != nil {
            return String(localized: "近 7 天平均 · \(highlights.validSleepDays)/7 晚有效")
        }
        return String(localized: "近 7 天 · \(highlights.validWalkingSpeedDays)/7 天有效")
    }

    private var conclusionText: String {
        if let minutes = friend.snapshot.highlights.averageSleepMinutes, minutes >= 420 {
            return String(localized: "睡得很充足，继续保持呀 🌙")
        }
        if friend.snapshot.highlights.validWalkingSpeedDays >= 5 {
            return String(localized: "这周节奏很稳，为你点赞 👏")
        }
        return String(localized: "状态平稳，记得多休息 ✨")
    }

    private var sleepValue: String {
        guard let minutes = friend.snapshot.highlights.averageSleepMinutes else {
            return friend.sleepText
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? String(localized: "\(hours) 小时") : String(localized: "\(hours) 小时 \(rest) 分")
    }

    private var walkingValue: String {
        guard let speed = friend.snapshot.highlights.averageWalkingSpeedMps else {
            return friend.walkingText
        }
        return String(format: "%.2f m/s", speed)
    }

    private var relativeUpdatedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter.localizedString(for: friend.lastUpdated, relativeTo: Date())
    }
}

#Preview {
    NavigationStack {
        SocialActivityDetailView(
            friend: FriendHealthProfile(
                id: "preview",
                ownerUserRecordName: nil,
                name: "阿杰",
                relationshipState: .mutualShared,
                permissionRole: .readOnly,
                statusText: "正在运动",
                sleepText: "7 小时 45 分",
                walkingText: "1.2 m/s",
                lastUpdated: Date(),
                isStale: false,
                publicProfile: nil,
                availableContentSummary: "",
                snapshot: SharedHealthSnapshot(
                    ownerUserID: nil,
                    ownerDisplayName: "阿杰",
                    generatedAt: Date(),
                    days: [],
                    highlights: SharedHealthHighlights(
                        averageSleepMinutes: 465,
                        averageWalkingSpeedMps: 1.2,
                        validSleepDays: 6,
                        validWalkingSpeedDays: 5
                    ),
                    payloadVersion: 1
                )
            )
        )
    }
}
