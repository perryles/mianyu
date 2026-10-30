import SwiftUI
import UIKit

enum AppNavigationAppearance {
    @MainActor
    static func configure() {
        guard #available(iOS 26.0, *) else { return }

        let transparentAppearance = UINavigationBarAppearance()
        transparentAppearance.configureWithTransparentBackground()
        transparentAppearance.backgroundColor = .clear
        transparentAppearance.shadowColor = .clear

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = transparentAppearance
        navigationBar.scrollEdgeAppearance = transparentAppearance
        navigationBar.compactAppearance = transparentAppearance
        navigationBar.compactScrollEdgeAppearance = transparentAppearance
    }
}

private struct AppSecondaryNavigationModifier: ViewModifier {
    let title: LocalizedStringKey

    @ViewBuilder
    func body(content: Content) -> some View {
        let navigationContent = content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            // 二级页统一隐藏主 TabBar，返回根页面时自动恢复。
            .toolbar(.hidden, for: .tabBar)

        if #available(iOS 26.0, *) {
            navigationContent
                .toolbarBackground(.hidden, for: .navigationBar)
        } else {
            navigationContent
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color(light: "FFFFFF", dark: "1C1C1E").opacity(0.94), for: .navigationBar)
        }
    }
}

extension View {
    func appSecondaryNavigation(title: LocalizedStringKey) -> some View {
        modifier(AppSecondaryNavigationModifier(title: title))
    }
}
