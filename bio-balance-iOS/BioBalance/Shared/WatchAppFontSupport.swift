import SwiftUI

enum CompanionWatchFontScaleLevel: Int {
    case one = 1
    case two = 2
    case three = 3
    case four = 4

    static var current: CompanionWatchFontScaleLevel {
        let sharedDefaults = AppGroupManager.userDefaults()
        return CompanionWatchFontScaleLevel(rawValue: sharedDefaults?.integer(forKey: AppGroupSchema.Keys.appFontScaleLevel) ?? 2) ?? .two
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
    static func watchAppSystem(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: size * CompanionWatchFontScaleLevel.current.multiplier, weight: weight, design: design)
    }

    static func watchAppSystem(
        _ style: Font.TextStyle,
        design: Font.Design = .default
    ) -> Font {
        let baseSize: CGFloat
        switch style {
        case .largeTitle: baseSize = 34
        case .title: baseSize = 28
        case .title2: baseSize = 22
        case .title3: baseSize = 20
        case .headline: baseSize = 17
        case .subheadline: baseSize = 15
        case .body: baseSize = 17
        case .callout: baseSize = 16
        case .footnote: baseSize = 13
        case .caption: baseSize = 12
        case .caption2: baseSize = 11
        @unknown default:
            baseSize = 17
        }
        return .system(size: baseSize * CompanionWatchFontScaleLevel.current.multiplier, weight: .regular, design: design)
    }
}
