/// InviteFriendIntroSheet 由社交共享页调用，作为「邀请好友」介绍弹层。
/// 负责展示共享权限状态和大致位置共享开关。

import SwiftUI

struct InviteFriendIntroSheet: View {
    @AppStorage(SocialSharingDataPolicy.approximateLocationSharingEnabledKey)
    private var isApproximateLocationSharingEnabled = false

    let permissionState: SharedHealthPermissionState
    let isAuthorizing: Bool
    let authorizationMessage: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("与好友共享健康摘要")
                    .font(.appSystem(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("你将通过 iCloud 共享最近 7 天的睡眠、步速摘要。粗略位置默认不共享，健康摘要和共享待办对受邀好友均为只读。")
                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)

                if let authorizationMessage {
                    Label(authorizationMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "D65A42"))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    introRow(
                        title: "共享内容",
                        subtitle: "仅包含睡眠分钟、步速摘要、有效样本天数、最近更新时间，以及你主动共享的列表内容。",
                        tint: Color(hex: "5E5CE6"),
                        systemImage: "bed.double.fill"
                    )
                    introRow(
                        title: "位置边界",
                        subtitle: "开启后，粗略位置会随摘要刷新；不会保存轨迹、精确地址或持续实时定位。",
                        tint: Color(hex: "B25000"),
                        systemImage: "location.circle.fill"
                    )
                    introRow(
                        title: "共享权限",
                        subtitle: "通过系统分享发送邀请，只有被邀请且接受的人才能查看；健康摘要和共享待办均为只读。",
                        tint: Theme.Colors.mintGreen,
                        systemImage: "person.2.fill"
                    )
                    introRow(
                        title: "停止共享",
                        subtitle: "你可以随时停止未来同步，但无法撤回对方此前已看到或截图保存的内容。",
                        tint: Color(hex: "FF7A59"),
                        systemImage: "hand.raised.fill"
                    )
                }

                Toggle(isOn: $isApproximateLocationSharingEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("共享粗略位置")
                            .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                        Text("独立授权，默认关闭，可随时再次关闭。")
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
                .tint(Theme.Colors.mintGreen)
                .onChange(of: isApproximateLocationSharingEnabled) { _, isEnabled in
                    Task { @MainActor in
                        if isEnabled {
                            _ = await LocationSharingService.shared.requestAuthorizationIfNeeded()
                        }
                        // 关闭位置共享会先清理本地缓存中的旧粗略位置；已存在 CKShare 时
                        // 立即上传移除位置字段的新快照，没有 CKShare 时只更新本地预览。
                        await SharedHealthDataStore.shared.updateApproximateLocationSharing(isEnabled)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    print("[社交共享] 点击授权并继续邀请 permission=\(permissionState)")
                    onConfirm()
                } label: {
                    HStack(spacing: 9) {
                        if isAuthorizing {
                            ProgressView()
                                .tint(Theme.Colors.onAccent)
                        }
                        Text(isAuthorizing ? "正在连接健康数据" : (permissionState == .needsPermission ? "授权并继续" : "继续邀请"))
                            .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.Colors.mintGreen, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isAuthorizing)
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "chevron.down")
                            .font(.appSystem(size: 15, weight: .bold))
                    }
                }
            }
        }
    }

    private func introRow(title: String, subtitle: String, tint: Color, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.appSystem(size: 17, weight: .semibold))
                        .foregroundColor(tint)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
    }
}
