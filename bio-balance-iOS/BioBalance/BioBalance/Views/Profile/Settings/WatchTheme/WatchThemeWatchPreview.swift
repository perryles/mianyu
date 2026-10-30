/// WatchThemeWatchPreview 复刻手表主页的预览卡片：状态文案 + 素材（自定义）或官方吉祥物 + 状态条。
/// iOS 端主题页/创建页/预览页共用。
import SwiftUI

/// WatchThemeWatchPreviewStyle 区分官方主题与自定义主题的预览内容。
enum WatchThemeWatchPreviewContent {
    /// 官方吉祥物主题。
    case official(WatchTheme)
    /// 自定义主题素材（按槽位取图）。
    case custom(CustomWatchTheme, slot: WatchThemeSlot)

    var slot: WatchThemeSlot? {
        if case .custom(_, let slot) = self { return slot }
        return nil
    }
}

/// WatchThemeStatusBands 渲染四段彩色状态条（与截图手表效果一致）。
struct WatchThemeStatusBands: View {
    let accent: Color

    private let bandColors: [Color] = [
        Color(hex: "F5D75E"),
        Color(hex: "9FE06E"),
        Color(hex: "B9A8F5"),
        Color(hex: "F5A8C0")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index == 1 ? accent : bandColors[index])
                    .frame(width: index == 1 ? 26 : 14, height: 5)
            }
        }
    }
}

/// WatchThemeWatchPreview 在手机端模拟手表圆角矩形屏幕。
struct WatchThemeWatchPreview: View {
    let content: WatchThemeWatchPreviewContent
    /// 屏幕宽度。
    var width: CGFloat = 148
    var showSideButton: Bool = true

    private var screenHeight: CGFloat { width * 1.12 }

    var body: some View {
        ZStack(alignment: .trailing) {
            screenBody
                .frame(width: width, height: screenHeight)

            if showSideButton {
                Capsule()
                    .fill(Color(hex: "C9CDD2"))
                    .frame(width: 7, height: screenHeight * 0.22)
                    .offset(x: 4)
            }
        }
        .padding(.trailing, showSideButton ? 4 : 0)
    }

    private var screenBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.30, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

            screenContent
                .frame(width: width - 10, height: screenHeight - 10)
                .clipShape(RoundedRectangle(cornerRadius: width * 0.26, style: .continuous))
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch content {
        case .official(let theme):
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "3A4A1F"), Color(hex: "1E260F")],
                    startPoint: .top, endPoint: .bottom
                )

                VStack(spacing: 6) {
                    WatchMascotSymbolFallback(style: theme.style)
                        .frame(width: width * 0.34, height: width * 0.34)
                        .padding(.top, width * 0.14)

                    Spacer()

                    Text("状态正常")
                        .font(.appSystem(size: width * 0.1, weight: .bold, design: .rounded))
                        .foregroundColor(theme.accent)
                    WatchThemeStatusBands(accent: theme.accent)
                        .padding(.bottom, width * 0.16)
                }
            }
        case .custom(let theme, let slot):
            WatchThemeCustomScreenPreview(theme: theme, slot: slot, sideLength: width - 10)
        }
    }
}

/// WatchThemeCustomScreenPreview 渲染自定义素材屏幕内容（含槽位回退）。
struct WatchThemeCustomScreenPreview: View {
    let theme: CustomWatchTheme
    let slot: WatchThemeSlot
    let sideLength: CGFloat

    /// 槽位素材缺失时按回退链解析实际槽位。
    private var resolvedSlot: WatchThemeSlot? {
        WatchThemeSlotResolver
            .fallbackChain(for: slot)
            .first { theme.slots[$0] != nil }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "3A4A1F"), Color(hex: "1E260F")],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 6) {
                Spacer()
                if let resolvedSlot, let media = theme.slots[resolvedSlot],
                   let image = UIImage(contentsOfFile: WatchCustomThemeFileStore.slotFileURL(
                        themeId: theme.id,
                        slot: resolvedSlot,
                        fileExtension: media.fileExtension
                   ).path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: sideLength * 0.5, height: sideLength * 0.5)
                } else {
                    Image(systemName: "photo")
                        .font(.appSystem(size: sideLength * 0.16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()

                Text(slot.displayTitle)
                    .font(.appSystem(size: sideLength * 0.1, weight: .bold, design: .rounded))
                    .foregroundColor(slotAccent)
                WatchThemeStatusBands(accent: slotAccent)
                    .padding(.bottom, sideLength * 0.13)
            }
        }
    }

    private var slotAccent: Color {
        switch slot {
        case .excellent: return Color(hex: "9FE06E")
        case .normal: return Color(hex: "F5D75E")
        case .mild: return Color(hex: "B9A8F5")
        case .overloaded: return Color(hex: "F5A8C0")
        }
    }
}

/// WatchMascotSymbolFallback 在 iOS 端为官方吉祥物提供静态示意（与 WatchThemeView 内嵌绘制一致）。
struct WatchMascotSymbolFallback: View {
    let style: WatchMascotStyle

    var body: some View {
        switch style {
        case .joey:
            Image("SettingsHeaderMascot")
                .resizable()
                .scaledToFit()
        default:
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.9))
                Circle()
                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
                HStack(spacing: 8) {
                    Circle().fill(Color.black.opacity(0.7)).frame(width: 5, height: 5)
                    Circle().fill(Color.black.opacity(0.7)).frame(width: 5, height: 5)
                }
                .offset(y: -4)
                Capsule()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: 12, height: 3)
                    .offset(y: 8)
            }
        }
    }
}
