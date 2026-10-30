/// AdaptiveLayoutContext 作为共享界面层的支撑类型，负责提供自适应布局参数。
/// 负责根据容器尺寸与大小类，提供页面/阅读/表单/Hero 四种内容样式及布局参数。

import SwiftUI

/// AdaptiveLayoutContext结构体 作为共享界面层里的辅助类型。
/// 负责共享布局与通用界面能力。
struct AdaptiveLayoutContext: Equatable {
    /// Content Style 枚举，作为内部辅助类型，用于细分外层共享布局与通用界面能力中的状态或分支。
    enum ContentStyle {
        case page
        case reading
        case form
        case hero
    }

    let containerWidth: CGFloat
    let containerHeight: CGFloat
    let horizontalSizeClass: UserInterfaceSizeClass?

    var isRegularWidth: Bool {
        horizontalSizeClass == .regular || containerWidth >= 820
    }

    /// 是否使用扩展布局取决于当前窗口尺寸，而不是物理设备类型。
    var usesExpandedLayout: Bool {
        isRegularWidth
    }

    var prefersTwoPaneLayout: Bool {
        containerWidth >= 820
    }

    var supportsThreeColumns: Bool {
        containerWidth >= 1100
    }

    var isLandscape: Bool {
        containerWidth > containerHeight
    }

    var outerPadding: CGFloat {
        if usesExpandedLayout {
            return isLandscape ? 32 : 24
        }
        return Theme.Layout.padding
    }

    var sectionSpacing: CGFloat {
        usesExpandedLayout ? 20 : 16
    }

    var cardPadding: CGFloat {
        usesExpandedLayout ? 20 : 16
    }

    var chartMinHeight: CGFloat {
        usesExpandedLayout ? 260 : 220
    }

    var rootGridColumnCount: Int {
        guard usesExpandedLayout else { return 2 }
        if supportsThreeColumns {
            return 3
        }
        return prefersTwoPaneLayout ? 2 : 1
    }

    var compactGridColumnCount: Int {
        guard usesExpandedLayout else { return 2 }
        if supportsThreeColumns {
            return 3
        }
        return prefersTwoPaneLayout ? 2 : 2
    }

    var secondaryGridColumnCount: Int {
        if supportsThreeColumns {
            return 2
        }
        return prefersTwoPaneLayout ? 2 : 1
    }

    var primarySecondaryColumns: [GridItem] {
        if supportsThreeColumns {
            return [
                GridItem(.flexible(minimum: 280, maximum: 420), spacing: 18, alignment: .top),
                GridItem(.flexible(minimum: 420, maximum: .infinity), spacing: 18, alignment: .top)
            ]
        }
        return [
            GridItem(.flexible(minimum: 280, maximum: .infinity), spacing: 16, alignment: .top),
            GridItem(.flexible(minimum: 280, maximum: .infinity), spacing: 16, alignment: .top)
        ]
    }

    var floatingTabBarMaxWidth: CGFloat {
        guard usesExpandedLayout else { return .infinity }
        return min(safeAvailableWidth, 760)
    }

    func contentMaxWidth(for style: ContentStyle) -> CGFloat {
        guard usesExpandedLayout else { return .infinity }
        let availableWidth = safeAvailableWidth
        switch style {
        case .page:
            return min(availableWidth, supportsThreeColumns ? 1220 : (isLandscape ? 1040 : 860))
        case .reading:
            return min(availableWidth, isLandscape ? 820 : 720)
        case .form:
            return min(availableWidth, isLandscape ? 760 : 680)
        case .hero:
            return min(availableWidth, supportsThreeColumns ? 1280 : (isLandscape ? 1120 : 920))
        }
    }

    func gridItems(minWidth: CGFloat = 280, maxColumns: Int? = nil) -> [GridItem] {
        let resolvedColumns = max(1, maxColumns ?? rootGridColumnCount)
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: resolvedColumns)
    }

    func formGridItems(maxColumns: Int = 2) -> [GridItem] {
        let columnCount = prefersTwoPaneLayout ? min(maxColumns, 2) : 1
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: max(1, columnCount))
    }

    private var safeAvailableWidth: CGFloat {
        guard containerWidth.isFinite, outerPadding.isFinite else { return 0 }
        return max(0, containerWidth - outerPadding * 2)
    }
}

private struct AdaptiveLayoutKey: EnvironmentKey {
    static let defaultValue = AdaptiveLayoutContext(
        containerWidth: 390,
        containerHeight: 844,
        horizontalSizeClass: .compact
    )
}

extension EnvironmentValues {
    var adaptiveLayout: AdaptiveLayoutContext {
        get { self[AdaptiveLayoutKey.self] }
        set { self[AdaptiveLayoutKey.self] = newValue }
    }
}

/// AdaptiveLayoutReader结构体 作为共享界面层里的辅助类型。
/// 负责共享布局与通用界面能力。
struct AdaptiveLayoutReader<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder let content: (AdaptiveLayoutContext) -> Content

    var body: some View {
        GeometryReader { proxy in
            let layout = AdaptiveLayoutContext(
                containerWidth: proxy.size.width,
                containerHeight: proxy.size.height,
                horizontalSizeClass: horizontalSizeClass
            )

            content(layout)
                .environment(\.adaptiveLayout, layout)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// AdaptivePageScroll视图 由上级页面或路由调用，作为共享界面层里的界面或内容组件。
/// 负责共享布局与通用界面能力。
struct AdaptivePageScrollView<Content: View>: View {
    let style: AdaptiveLayoutContext.ContentStyle
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let showsIndicators: Bool
    @ViewBuilder let content: Content

    init(
        style: AdaptiveLayoutContext.ContentStyle = .page,
        topPadding: CGFloat = 18,
        bottomPadding: CGFloat = 112,
        showsIndicators: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    var body: some View {
        AdaptiveLayoutReader { layout in
            ScrollView(showsIndicators: showsIndicators) {
                content
                    .frame(maxWidth: layout.contentMaxWidth(for: style), alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, layout.outerPadding)
                    .padding(.top, topPadding)
                    .padding(.bottom, bottomPadding)
            }
        }
    }
}

extension View {
    /// Enables the system reading-page navigation bar minimization on iOS 27 and later.
    /// Earlier systems keep the existing navigation behavior unchanged.
    @ViewBuilder
    func readingNavigationBarMinimization() -> some View {
        if #available(iOS 27.0, *) {
            self
                .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
                .toolbarMinimizationRestoration(.atScrollEdge, for: .navigationBar)
                .toolbarMinimizationSafeAreaAdjustment(.enabled, for: .navigationBar)
        } else {
            self
        }
    }
}

/// Adaptive内容容器组件 作为共享界面层里的外层容器组件。
/// 负责共享布局与通用界面能力。

/// Adaptive区块Grid结构体 作为共享界面层里的辅助类型。
/// 负责共享布局与通用界面能力。

/// AdaptiveTwoPane区块组件 作为共享界面层里的布局区块组件。
/// 负责共享布局与通用界面能力。
struct AdaptiveTwoPaneSection<Primary: View, Secondary: View>: View {
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    let spacing: CGFloat
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    init(
        spacing: CGFloat = 16,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.spacing = spacing
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        if adaptiveLayout.prefersTwoPaneLayout {
            LazyVGrid(columns: adaptiveLayout.primarySecondaryColumns, spacing: spacing) {
                primary
                secondary
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                primary
                secondary
            }
        }
    }
}

/// AdaptiveHeroLayout结构体 作为共享界面层里的辅助类型。
/// 负责共享布局与通用界面能力。
struct AdaptiveHeroLayout<Leading: View, Trailing: View>: View {
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    let spacing: CGFloat
    let verticalAlignment: VerticalAlignment
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    init(
        spacing: CGFloat = 16,
        verticalAlignment: VerticalAlignment = .top,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.spacing = spacing
        self.verticalAlignment = verticalAlignment
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        if adaptiveLayout.prefersTwoPaneLayout {
            HStack(alignment: verticalAlignment, spacing: spacing) {
                leading
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
                    .frame(width: adaptiveLayout.supportsThreeColumns ? 320 : 260, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                leading
                trailing
            }
        }
    }
}

/// AdaptiveForm容器组件 作为共享界面层里的外层容器组件。
/// 负责共享布局与通用界面能力。
