/// HealthProfileSupport 作为 HealthProfileView 的共享扩展，负责提供辅助方法。
/// 负责提供标签证据文案格式化、图标气泡等健康画像页辅助逻辑。

import SwiftUI

extension HealthProfileView {

    func tagEvidenceText(_ tag: HealthProfileTag) -> String {
        var lines = [tag.detail]
        let evidence = tag.evidence.prefix(2).joined(separator: "；")
        if !evidence.isEmpty {
            lines.append("依据：\(evidence)")
        }
        if let firstDetectedAt = tag.firstDetectedAt {
            lines.append("首次形成于 \(shortDateText(firstDetectedAt))")
        }
        return lines.joined(separator: "\n")
    }

    func iconBubble(symbol: String, tint: Color, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.appSystem(size: size * 0.42, weight: .black))
                    .foregroundColor(tint)
            }
    }

    func scoreTint(_ score: Int) -> Color {
        if score >= 80 { return Theme.Colors.mintGreen }
        if score >= 65 { return Color(hex: "6B83E8") }
        if score >= 45 { return Color(hex: "F3A53B") }
        return Color(hex: "FF8A5B")
    }

    func trendTint(_ trend: HealthProfileTrend) -> Color {
        switch trend {
        case .improving: return Theme.Colors.mintGreen
        case .stable: return Color(hex: "6B83E8")
        case .declining: return Color(hex: "FF8A5B")
        case .observing: return Color(hex: "94A3C3")
        case .missing: return Theme.Colors.textTertiary
        }
    }

    func trendGradient(_ trend: HealthProfileTrend) -> [Color] {
        switch trend {
        case .improving: return [Theme.Colors.mintGreen, Color(hex: "3ACE92")]
        case .stable: return [Color(hex: "6B83E8"), Color(hex: "7C9CFB")]
        case .declining: return [Color(hex: "FF8A5B"), Color(hex: "FF9A78")]
        case .observing: return [Color(hex: "94A3C3"), Color(hex: "B0C0D5")]
        case .missing: return [Theme.Colors.textTertiary, Theme.Colors.textTertiary]
        }
    }

    func dimensionPriority(_ trend: HealthProfileTrend) -> Int {
        switch trend {
        case .declining: return 0
        case .observing: return 1
        case .stable: return 2
        case .improving: return 3
        case .missing: return 4
        }
    }

    func tint(for kind: HealthProfileChangeKind) -> Color {
        switch kind {
        case .positive: return Theme.Colors.mintGreen
        case .risk: return Color(hex: "FF8A5B")
        case .stable: return Color(hex: "6B83E8")
        case .observing: return Color(hex: "94A3C3")
        }
    }

    func symbol(for kind: HealthProfileChangeKind) -> String {
        switch kind {
        case .positive: return "arrow.up.right.circle.fill"
        case .risk: return "exclamationmark.circle.fill"
        case .stable: return "equal.circle.fill"
        case .observing: return "eye.fill"
        }
    }

    func actionTint(_ priority: HealthProfileActionPriority) -> Color {
        switch priority {
        case .high: return Color(hex: "FF8A5B")
        case .medium: return Color(hex: "4CA6A8")
        case .low: return Theme.Colors.mintGreen
        }
    }

    func actionSymbol(for module: HealthProfileModule) -> String {
        switch module {
        case .sleep: return "moon.zzz.fill"
        case .stress: return "wind"
        case .activity: return "figure.walk"
        case .sedentary: return "figure.stand"
        case .habits: return "checkmark.seal.fill"
        case .reproductive: return "circle.hexagongrid.fill"
        case .symptoms: return "person.text.rectangle.fill"
        case .healthKit: return "heart.fill"
        }
    }

    func completenessTint(_ state: HealthProfileDataCompletenessState) -> Color {
        switch state {
        case .synced, .generated: return Theme.Colors.mintGreen
        case .insufficient: return Color(hex: "F3A53B")
        case .unauthorized: return Color(hex: "FF8A5B")
        case .notEnabled, .notApplicable: return Color(hex: "94A3C3")
        }
    }

    func completenessSymbol(_ state: HealthProfileDataCompletenessState) -> String {
        switch state {
        case .synced, .generated: return "checkmark"
        case .insufficient: return "hourglass"
        case .unauthorized: return "lock.fill"
        case .notEnabled, .notApplicable: return "minus"
        }
    }

    func shortDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    func dateTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
