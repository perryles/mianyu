import SwiftUI
import WebKit

nonisolated enum TodayMianyuMascotEmotion: String, Equatable {
    case sleeping = "00"
    case idle = "02"
    case booting = "05"
    case happy = "10"
    case tired = "15"
    case focused = "16"
}

nonisolated enum TodayMianyuMascotState {
    static func emotion(hasData: Bool, band: StressBand) -> TodayMianyuMascotEmotion {
        guard hasData else { return .booting }

        return switch band {
        case .waiting: .booting
        case .relaxed: .happy
        case .steady: .idle
        case .mild: .focused
        case .caution: .tired
        case .high: .sleeping
        }
    }
}

nonisolated enum TodayMianyuMascotUpdateAction: Equatable {
    case reload
    case setEmotion(TodayMianyuMascotEmotion)
    case none

    static func resolve(
        loadedEmotion: TodayMianyuMascotEmotion?,
        loadedReduceMotion: Bool?,
        requestedEmotion: TodayMianyuMascotEmotion,
        requestedReduceMotion: Bool
    ) -> Self {
        guard let loadedEmotion, let loadedReduceMotion else { return .reload }
        guard loadedReduceMotion == requestedReduceMotion else { return .reload }
        guard loadedEmotion != requestedEmotion else { return .none }
        return .setEmotion(requestedEmotion)
    }
}

nonisolated enum TodayMianyuMascotLoadPolicy {
    static let initialDelayNanoseconds: UInt64 = 150_000_000

    static func shouldMountWebView(hasFinishedInitialDelay: Bool) -> Bool {
        hasFinishedInitialDelay
    }
}

/// 今日页的眠屿品牌吉祥物。视觉、表情和交互由自研 SVG/JavaScript 引擎完成，
/// 首帧先保留稳定布局，随后再挂载 WebKit，避免页面打开时同步启动 Web 内容进程。
struct TodayMascotView: View {
    @State private var hasFinishedInitialDelay = false

    let assessment: StressPresentationAssessment

    var body: some View {
        Group {
            if TodayMianyuMascotLoadPolicy.shouldMountWebView(
                hasFinishedInitialDelay: hasFinishedInitialDelay
            ) {
                TodayMascotWebView(assessment: assessment)
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .task {
            guard !hasFinishedInitialDelay else { return }
            try? await Task.sleep(
                nanoseconds: TodayMianyuMascotLoadPolicy.initialDelayNanoseconds
            )
            guard !Task.isCancelled else { return }
            hasFinishedInitialDelay = true
        }
    }
}

/// SwiftUI 只传递健康状态与辅助功能偏好。
private struct TodayMascotWebView: UIViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let assessment: StressPresentationAssessment

    private var emotion: TodayMianyuMascotEmotion {
        TodayMianyuMascotState.emotion(hasData: assessment.hasData, band: assessment.band)
    }

    private var accessibilityValue: String {
        switch emotion {
        case .booting: String(localized: "等待健康数据")
        case .happy: String(localized: "恢复良好")
        case .idle: String(localized: "状态平稳")
        case .focused: String(localized: "轻度压力")
        case .tired: String(localized: "建议留意")
        case .sleeping: String(localized: "需要恢复")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isAccessibilityElement = true
        webView.accessibilityLabel = String(localized: "眠屿 健康伙伴")
        webView.accessibilityValue = accessibilityValue
        webView.accessibilityHint = reduceMotion
            ? nil
            : String(localized: "轻点互动，拖动跟随")

        context.coordinator.requestedEmotion = emotion
        context.coordinator.loadedEmotion = emotion
        context.coordinator.loadedReduceMotion = reduceMotion
        loadContent(in: webView, emotion: emotion, reduceMotion: reduceMotion)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.accessibilityValue = accessibilityValue
        webView.accessibilityHint = reduceMotion
            ? nil
            : String(localized: "轻点互动，拖动跟随")
        context.coordinator.requestedEmotion = emotion

        let action = TodayMianyuMascotUpdateAction.resolve(
            loadedEmotion: context.coordinator.loadedEmotion,
            loadedReduceMotion: context.coordinator.loadedReduceMotion,
            requestedEmotion: emotion,
            requestedReduceMotion: reduceMotion
        )

        switch action {
        case .reload:
            context.coordinator.isReady = false
            context.coordinator.loadedEmotion = emotion
            context.coordinator.loadedReduceMotion = reduceMotion
            loadContent(in: webView, emotion: emotion, reduceMotion: reduceMotion)
        case let .setEmotion(emotion):
            guard context.coordinator.isReady else { return }
            setEmotion(emotion, in: webView)
            context.coordinator.loadedEmotion = emotion
        case .none:
            break
        }
    }

    private func loadContent(
        in webView: WKWebView,
        emotion: TodayMianyuMascotEmotion,
        reduceMotion: Bool
    ) {
        guard let fileURL = Bundle.main.url(
            forResource: "mianyu-mascot",
            withExtension: "html",
            subdirectory: "MianyuMascot"
        ) ?? Bundle.main.url(forResource: "mianyu-mascot", withExtension: "html") else {
            assertionFailure("Missing bundled Mianyu mascot HTML")
            return
        }

        var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "emotion", value: emotion.rawValue),
            URLQueryItem(name: "reduceMotion", value: reduceMotion ? "1" : "0")
        ]
        webView.loadFileURL(
            components?.url ?? fileURL,
            allowingReadAccessTo: fileURL.deletingLastPathComponent()
        )
    }

    private func setEmotion(_ emotion: TodayMianyuMascotEmotion, in webView: WKWebView) {
        webView.evaluateJavaScript(
            "window.MianyuMascot && window.MianyuMascot.setEmotion('\(emotion.rawValue)');"
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var isReady = false
        var loadedEmotion: TodayMianyuMascotEmotion?
        var loadedReduceMotion: Bool?
        var requestedEmotion: TodayMianyuMascotEmotion = .idle

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            isReady = true
            loadedEmotion = requestedEmotion
            webView.evaluateJavaScript(
                "window.MianyuMascot && window.MianyuMascot.setEmotion('\(requestedEmotion.rawValue)');"
            )
        }
    }
}
