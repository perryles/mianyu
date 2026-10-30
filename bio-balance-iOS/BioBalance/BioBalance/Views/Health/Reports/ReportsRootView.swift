import SwiftUI

/// 报告模块根页面，承载日报、周报、月报、最近报告与分享工具。
struct ReportsRootView: View {
    var body: some View {
        ZStack {
            reportBackground

            AdaptivePageScrollView(style: .reading, topPadding: 14, bottomPadding: 88) {
                ReportsContentView()
            }
        }
    }

    private var reportBackground: some View {
        HealthDetailPageBackground(
            topGlow: Color(hex: "C9D7FA"),
            lowerGlow: Color(hex: "DFE9FF")
        )
    }
}

#Preview("报告") {
    NavigationStack {
        ReportsRootView()
    }
}
