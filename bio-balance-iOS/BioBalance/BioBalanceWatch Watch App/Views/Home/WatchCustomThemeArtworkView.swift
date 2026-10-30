/// WatchCustomThemeArtworkView 在手表端渲染自定义主题素材：
/// 静态 PNG 直接显示，GIF 通过 ImageIO 帧回调驱动；槽位缺失时由调用方回退官方吉祥物。
import SwiftUI
import ImageIO

/// WatchCustomThemeArtworkView 按槽位渲染素材，负责帧动画与文件加载。
struct WatchCustomThemeArtworkView: View {
    let themeId: String
    let slot: WatchThemeSlot

    @State private var frames: [CGImage] = []
    @State private var frameDurations: [Double] = []
    @State private var frameIndex = 0
    @State private var animationTimer: Timer?

    var body: some View {
        ZStack {
            if frames.isEmpty {
                // 素材尚未到达：占位图形，避免布局跳动。
                Circle()
                    .fill(Color.white.opacity(0.12))
            } else {
                Image(decorative: frames[frameIndex], scale: 2.0)
                    .resizable()
                    .scaledToFit()
            }
        }
        .task(id: "\(themeId)-\(slot.rawValue)-\(frames.isEmpty)") {
            loadFrames()
            startAnimation()
        }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func loadFrames() {
        animationTimer?.invalidate()
        animationTimer = nil
        frames = []
        frameDurations = []
        frameIndex = 0

        guard let (data, media) = WatchCustomThemeFileStore.slotData(themeId: themeId, slot: slot) else {
            return
        }
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        guard let source, CGImageSourceGetCount(source) > 0 else { return }

        if media.isAnimated && CGImageSourceGetCount(source) > 1 {
            var loadedFrames: [CGImage] = []
            var loadedDurations: [Double] = []
            for index in 0..<CGImageSourceGetCount(source) {
                if let frame = CGImageSourceCreateImageAtIndex(source, index, nil) {
                    loadedFrames.append(frame)
                    loadedDurations.append(gifFrameDelay(source: source, index: index))
                }
            }
            frames = loadedFrames
            frameDurations = loadedDurations
        } else if let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            frames = [frame]
            frameDurations = [0]
        }
    }

    private func gifFrameDelay(source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
        let delay = unclamped ?? clamped ?? 0
        return delay > 0 ? delay : 0.1
    }

    private func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        guard frames.count > 1 else { return }
        scheduleNextFrame(index: 0)
    }

    private func scheduleNextFrame(index: Int) {
        guard frames.count > 1, index < frameDurations.count else { return }
        animationTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: frameDurations[index], repeats: false) { _ in
            Task { @MainActor in
                guard frames.count > 1 else { return }
                let next = (index + 1) % frames.count
                frameIndex = next
                scheduleNextFrame(index: next)
            }
        }
        animationTimer = timer
    }
}
