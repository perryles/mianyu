/// AppLaunchView 由应用冷启动流程调用，作为「品牌闪屏」启动页。
/// 负责固定展示 1.5 秒品牌吉祥物动画，并在期间后台恢复私有偏好。

import SwiftUI

/// 每次冷启动时展示的静态品牌页；从后台回前台不再重播。
/// 页面固定停留 1.5 秒；私有偏好恢复只在这段时间内尝试，不延长展示时间。
struct AppLaunchView: View {
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color(light: "F4F4F2", dark: "17181A")
                .ignoresSafeArea()

            staticBackdrop

            // 吉祥物作为 ZStack 直接子视图，保持屏幕正中。
            LoginMascot()
                .frame(width: 240, height: 260)
                .accessibilityHidden(true)

            // 品牌名单独钉在底部，不影响吉祥物居中。
            VStack(spacing: 0) {
                Spacer()

                Text("眠屿")
                    .font(.appSystem(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(light: "5B6571", dark: "B7C0CA"), Color(light: "343A42", dark: "7E8892")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.bottom, 72)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await holdAndContinue() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("眠屿，每天更了解自己的状态")
    }

    private var staticBackdrop: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.48))
                    .frame(width: proxy.size.width * 0.86)
                    .offset(x: -proxy.size.width * 0.36, y: -proxy.size.height * 0.34)

                Circle()
                    .fill(Color(light: "E6ECE8", dark: "2A2D2C").opacity(0.65))
                    .frame(width: proxy.size.width * 0.68)
                    .offset(x: proxy.size.width * 0.42, y: proxy.size.height * 0.34)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @MainActor
    private func holdAndContinue() async {
        let cloudTask = Task {
            await OnboardingPreferenceCloudStore.shared.synchronize()
        }

        // 固定停留 1.5 秒后必定放行；云端请求不能延长展示，取消后由后续全局同步补偿。
        // 不再用 Task.isCancelled 拦截 onComplete，避免任何取消场景把用户永久困在启动页。
        try? await Task.sleep(for: .milliseconds(1_500))
        cloudTask.cancel()
        onComplete()
    }
}

#Preview {
    AppLaunchView {}
}
