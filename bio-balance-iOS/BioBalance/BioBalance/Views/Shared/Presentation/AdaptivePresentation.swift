/// AdaptivePresentation 作为 View 的共享扩展，负责提供弹层适配修饰器。
/// 负责提供 adaptiveSheetChrome 方法以统一弹层的 detents、拖拽指示器与宽度适配。

import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveSheetChrome(
        style: AdaptiveLayoutContext.ContentStyle = .form,
        detents: Set<PresentationDetent> = [.large],
        dragIndicator: Visibility = .visible
    ) -> some View {
        self
            .presentationDetents(detents)
            .presentationDragIndicator(dragIndicator)
            .presentationCornerRadius(Theme.Radius.hero)
            .presentationBackground(Theme.Colors.surface)
            .modifier(AdaptiveSheetWidthModifier(style: style))
    }
}

private struct AdaptiveSheetWidthModifier: ViewModifier {
    let style: AdaptiveLayoutContext.ContentStyle

    func body(content: Content) -> some View {
        AdaptiveLayoutReader { layout in
            content
                .frame(maxWidth: layout.usesExpandedLayout ? layout.contentMaxWidth(for: style) : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, layout.usesExpandedLayout ? layout.outerPadding : 0)
                .padding(.bottom, Theme.Spacing.extraLarge)
        }
    }
}
