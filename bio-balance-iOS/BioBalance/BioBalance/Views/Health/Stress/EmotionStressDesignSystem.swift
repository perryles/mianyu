import SwiftUI

enum EmotionStressStyle {
    static let page = Theme.Colors.pageBackground
    static let card = Theme.Colors.surface
    static let border = Theme.Colors.surfaceBorder
    static let mint = Color(hex: "25B27B")
    static let mintFill = Color(hex: "EFF8F4")
    static let mintMuted = Color(hex: "8DD9BC")
    static let grayGreen = Color(hex: "C8D7D0")
    static let coral = Color(hex: "C65B70")
    static let coralFill = Color(hex: "FFF1F4")
    static let ink = Theme.Colors.textPrimary
    static let secondary = Theme.Colors.textSecondary
    static let tertiary = Theme.Colors.textTertiary
    static let track = Color(hex: "E6ECE9")
    static let corner: CGFloat = Theme.Radius.card
    static let pagePadding: CGFloat = Theme.Layout.pagePadding
}

enum EmotionKind: String, CaseIterable, Identifiable, Sendable {
    case happy, calm, neutral, anxious, low, tired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .happy: return String(localized: "开心")
        case .calm: return String(localized: "平静")
        case .neutral: return String(localized: "一般")
        case .anxious: return String(localized: "焦虑")
        case .low: return String(localized: "低落")
        case .tired: return String(localized: "疲惫")
        }
    }

    var assetName: String {
        switch self {
        case .happy: return "EmotionHappy"
        case .calm: return "EmotionCalm"
        case .neutral: return "EmotionNeutral"
        case .anxious: return "EmotionAnxious"
        case .low: return "EmotionLow"
        case .tired: return "EmotionTired"
        }
    }

    var backendCode: String {
        switch self {
        case .happy: return "happy"
        case .calm, .neutral: return "neutral"
        case .anxious: return "anxious"
        case .low: return "sad"
        case .tired: return "tired"
        }
    }

    var moodID: String { rawValue }

    var tint: Color {
        switch self {
        case .happy: return Color(hex: "D9A92F")
        case .calm: return EmotionStressStyle.mint
        case .neutral: return Color(hex: "799488")
        case .anxious, .low: return EmotionStressStyle.coral
        case .tired: return Color(hex: "7390A6")
        }
    }

    static func resolve(moodID: String, backendCode: String) -> EmotionKind {
        if let exact = EmotionKind(rawValue: moodID) { return exact }
        switch backendCode {
        case "happy": return .happy
        case "anxious": return .anxious
        case "sad": return .low
        case "tired": return .tired
        default: return .calm
        }
    }
}

struct EmotionIconView: View {
    let emotion: EmotionKind
    var size: CGFloat = 28

    var body: some View {
        Image(emotion.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

nonisolated struct AIInsightSpark: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: center.y),
            control1: CGPoint(x: center.x, y: center.y * 0.72),
            control2: CGPoint(x: center.x * 1.28, y: center.y)
        )
        path.addCurve(
            to: CGPoint(x: center.x, y: rect.maxY),
            control1: CGPoint(x: center.x * 1.28, y: center.y),
            control2: CGPoint(x: center.x, y: center.y * 1.28)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: center.y),
            control1: CGPoint(x: center.x, y: center.y * 1.28),
            control2: CGPoint(x: center.x * 0.72, y: center.y)
        )
        path.addCurve(
            to: CGPoint(x: center.x, y: rect.minY),
            control1: CGPoint(x: center.x * 0.72, y: center.y),
            control2: CGPoint(x: center.x, y: center.y * 0.72)
        )
        return path
    }
}

struct AIInsightIcon: View {
    var size: CGFloat = 20

    var body: some View {
        AIInsightSpark()
            .fill(EmotionStressStyle.mint)
            .overlay(AIInsightSpark().stroke(EmotionStressStyle.ink, lineWidth: max(0.75, size / 22)))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct EmotionStressCard<Content: View>: View {
    var fill: Color = EmotionStressStyle.card
    var cornerRadius: CGFloat = EmotionStressStyle.corner
    var padding: CGFloat = Theme.Spacing.medium
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(fill == EmotionStressStyle.card ? EmotionStressStyle.border : .clear, lineWidth: 1)
            }
    }
}

struct EmotionStressEmptyState: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        EmotionStressCard {
            VStack(spacing: Theme.Spacing.small) {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(EmotionStressStyle.grayGreen)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(EmotionStressStyle.ink)
                Text(message)
                    .font(Theme.Typography.supporting)
                    .foregroundStyle(EmotionStressStyle.secondary)
                    .multilineTextAlignment(.center)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(BBTintedButtonStyle(tint: EmotionStressStyle.mint))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.small)
        }
    }
}

struct EmotionStressPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
            Text(title)
                .font(Theme.Typography.pageTitle)
                .foregroundStyle(EmotionStressStyle.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(Theme.Typography.supporting)
                .foregroundStyle(EmotionStressStyle.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
