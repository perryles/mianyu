import SwiftUI

private enum WidgetAppFontScaleLevel: Int {
    case one = 1
    case two = 2
    case three = 3
    case four = 4

    static var current: WidgetAppFontScaleLevel {
        WidgetAppFontScaleLevel(rawValue: AppGroupManager.shared.getAppFontScaleLevelRawValue() ?? 2) ?? .two
    }

    var multiplier: CGFloat {
        switch self {
        case .one: return 0.92
        case .two: return 1.0
        case .three: return 1.08
        case .four: return 1.16
        }
    }
}

extension Font {
    private static func widgetScaledSize(_ size: CGFloat) -> CGFloat {
        size * WidgetAppFontScaleLevel.current.multiplier
    }

    private static func widgetBaseSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .subheadline: return 15
        case .body: return 17
        case .callout: return 16
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }

    static func widgetAppSystem(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: widgetScaledSize(size), weight: weight, design: design)
    }

    static func widgetAppSystem(
        _ style: Font.TextStyle,
        design: Font.Design = .default
    ) -> Font {
        .system(size: widgetScaledSize(widgetBaseSize(for: style)), weight: .regular, design: design)
    }
}
