import SwiftUI

/// Accepts only the selected friend. Local health data cannot be substituted.
struct SocialStressDetailView: View {
    let friend: FriendHealthProfile

    var body: some View {
        AdaptivePageScrollView(topPadding: 16, bottomPadding: 40) {
            VStack(spacing: 20) {
                Text(friend.name)
                    .font(.appSystem(size: 22, weight: .bold, design: .rounded))
                Image(systemName: "lock.shield")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Colors.mintGreen)
                    .accessibilityHidden(true)
                Text("暂无好友压力数据")
                    .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                Text("当前好友共享内容不包含压力数据，暂时无法查看对方的压力评分与趋势。")
                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24))
        }
        .background(Theme.Colors.secondarySurface)
        .navigationTitle("好友压力详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}
