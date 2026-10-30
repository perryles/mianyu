/// CacheManagementPreview 由 SettingsView 调用，作为「页面缓存」入口卡右侧的缩略预览。
/// 负责用小尺寸信息块提示当前缓存可清理状态。

import SwiftUI

/// CacheManagementPreview 由 SettingsView 调用，作为“页面缓存”入口卡右侧的缩略预览。
/// 负责用小尺寸信息块提示当前缓存可清理状态。
struct CacheManagementPreview: View {
    let summaryText: String
    let detailText: String
    var isClearing: Bool = false
    @State private var rotation = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .frame(width: 104, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .stroke(Theme.Colors.surfaceBorder, lineWidth: 2)
                            .frame(width: 10, height: 10)
                        Circle()
                            .trim(from: 0, to: isClearing ? 0.72 : 1)
                            .stroke(
                                isClearing ? Theme.Colors.accentRed : Theme.Colors.accentBlue.opacity(0.82),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                            .frame(width: 10, height: 10)
                            .rotationEffect(.degrees(isClearing && rotation ? 360 : -90))
                            .animation(
                                isClearing
                                    ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                    : .spring(response: 0.32, dampingFraction: 0.72),
                                value: rotation
                            )
                    }
                    Text(summaryText)
                        .font(.appSystem(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                }

                Text(detailText)
                    .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(width: 94, height: 44, alignment: .leading)
            .background(Theme.Colors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .scaleEffect(isClearing ? 0.985 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.76), value: isClearing)
        }
        .frame(width: 104, height: 54)
        .onAppear {
            if isClearing {
                startRotation()
            }
        }
        .onChange(of: isClearing) { _, newValue in
            if newValue {
                startRotation()
            } else {
                rotation = false
            }
        }
    }

    private func startRotation() {
        rotation = false
        DispatchQueue.main.async {
            rotation = true
        }
    }
}
