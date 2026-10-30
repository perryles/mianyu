import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Foundation Models @Generable 结构化健康回答。
/// constrained decoding 保证输出严格匹配该结构，无需 Markdown 解析。
@available(iOS 26.0, *)
@Generable
struct HealthAIGenerableAnswer {
    @Guide(description: "直接回答用户问题的一句话结论")
    var summary: String

    @Guide(description: "支持结论的依据，2到4条", .count(2...4))
    var basis: [String]

    @Guide(description: "具体可执行的生活建议，2到4条", .count(2...4))
    var actions: [String]

    @Guide(description: "需要留意的风险或注意事项，0到3条", .count(0...3))
    var risks: [String]

    @Guide(description: "用户可以继续追问的问题，2到3条", .count(2...3))
    var followUps: [String]
}

@available(iOS 26.0, *)
extension HealthAIGenerableAnswer {
    /// 将完整的 @Generable 结果转为 HealthAIAnswerPayload，绕过 Markdown 解析。
    func toAnswerPayload() -> HealthAIAnswerPayload {
        HealthAIAnswerPayload(
            summary: summary,
            basis: basis,
            actions: actions,
            risks: risks,
            followUps: followUps,
            rawMarkdown: toMarkdown()
        )
    }

    /// 将结构化回答转为 5 段 Markdown（供 displayText 和日志使用）。
    func toMarkdown() -> String {
        var lines = ["## 结论", summary, "", "## 依据"]
        lines.append(contentsOf: basis.map { "- \($0)" })
        lines.append(contentsOf: ["", "## 建议"])
        lines.append(contentsOf: actions.map { "- \($0)" })
        lines.append(contentsOf: ["", "## 留意"])
        if risks.isEmpty {
            lines.append("- 当前没有明显风险信号，仍需结合体感持续观察。")
        } else {
            lines.append(contentsOf: risks.map { "- \($0)" })
        }
        lines.append(contentsOf: ["", "## 下一步可问"])
        lines.append(contentsOf: followUps.map { "- \($0)" })
        return lines.joined(separator: "\n")
    }
}

@available(iOS 26.0, *)
extension HealthAIGenerableAnswer.PartiallyGenerated {
    /// 将 PartiallyGenerated 快照转为可实时显示的 Markdown 文本。
    func toMarkdownSnapshot() -> String {
        var lines: [String] = []
        if let summary {
            lines.append(contentsOf: ["## 结论", summary])
        }
        if let basis, !basis.isEmpty {
            lines.append(contentsOf: ["", "## 依据"])
            lines.append(contentsOf: basis.map { "- \($0)" })
        }
        if let actions, !actions.isEmpty {
            lines.append(contentsOf: ["", "## 建议"])
            lines.append(contentsOf: actions.map { "- \($0)" })
        }
        if let risks, !risks.isEmpty {
            lines.append(contentsOf: ["", "## 留意"])
            lines.append(contentsOf: risks.map { "- \($0)" })
        }
        if let followUps, !followUps.isEmpty {
            lines.append(contentsOf: ["", "## 下一步可问"])
            lines.append(contentsOf: followUps.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}
#endif
