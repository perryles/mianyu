import SwiftUI
import WidgetKit

/// 所有小组件卡片统一使用的渲染输入，避免直接依赖具体设备类型。
struct WidgetRenderContext {
    let family: WidgetFamily
    let renderingMode: WidgetRenderingMode
    let contentMargins: EdgeInsets
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let systemRequestsSimplifiedContent: Bool

    var isAccented: Bool {
        renderingMode == .accented
    }

    var prefersSimplifiedContent: Bool {
        switch family {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular:
            return true
        default:
            return systemRequestsSimplifiedContent || dynamicTypeSize.isAccessibilitySize
        }
    }
}

private struct WidgetRenderContextKey: EnvironmentKey {
    static var defaultValue: WidgetRenderContext {
        WidgetRenderContext(
            family: .systemMedium,
            renderingMode: .fullColor,
            contentMargins: EdgeInsets(),
            colorScheme: .light,
            dynamicTypeSize: .medium,
            systemRequestsSimplifiedContent: false
        )
    }
}

extension EnvironmentValues {
    var widgetRenderContext: WidgetRenderContext {
        get { self[WidgetRenderContextKey.self] }
        set { self[WidgetRenderContextKey.self] = newValue }
    }
}

struct WidgetRenderContextReader<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetContentMargins) private var contentMargins
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(visionOS)
    @Environment(\.levelOfDetail) private var levelOfDetail
    #endif

    @ViewBuilder let content: (WidgetRenderContext) -> Content

    var body: some View {
        let context = WidgetRenderContext(
            family: family,
            renderingMode: renderingMode,
            contentMargins: contentMargins,
            colorScheme: colorScheme,
            dynamicTypeSize: dynamicTypeSize,
            systemRequestsSimplifiedContent: systemRequestsSimplifiedContent
        )
        content(context)
            .environment(\.widgetRenderContext, context)
    }

    private var systemRequestsSimplifiedContent: Bool {
        #if os(visionOS)
        levelOfDetail == .simplified
        #else
        false
        #endif
    }
}
