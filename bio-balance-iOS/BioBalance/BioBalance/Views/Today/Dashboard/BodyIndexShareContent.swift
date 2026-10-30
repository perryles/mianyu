import Foundation

/// 身体指数分享时使用的最小化快照。只包含用户主动分享所需的数据，
/// 不带定位、设备标识或原始 HealthKit 样本时间戳。
struct BodyIndexShareContent: Equatable, Sendable {
    let title: String
    let periodText: String
    let valueText: String
    let unitText: String
    let statusText: String
    let headline: String
    let detail: String
    let facts: [BodyIndexPersonalizedFact]
    let sampleCaption: String

    var formattedValue: String {
        let trimmedValue = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnit = unitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return String(localized: "暂无") }
        guard trimmedValue != "—", trimmedValue != "--", trimmedValue != "暂无" else {
            return trimmedValue
        }
        guard !trimmedUnit.isEmpty, !trimmedValue.hasSuffix(trimmedUnit) else {
            return trimmedValue
        }
        return "\(trimmedValue) \(trimmedUnit)"
    }

    var plainText: String {
        var lines = [
            String(localized: "眠屿 · \(title)"),
            "\(periodText)｜\(formattedValue)｜\(statusText)",
            headline,
            detail
        ]
        lines.append(contentsOf: facts.prefix(4).map { "\($0.title)：\($0.value)" })
        if !sampleCaption.isEmpty {
            lines.append(sampleCaption)
        }
        lines.append(String(localized: "仅供日常健康管理参考"))
        return lines.joined(separator: "\n")
    }
}
