import Foundation

/// 将模型的五段式 Markdown 回答解析成 UI 可直接消费的结构。
struct HealthAIAnswerParser {
    private let titles = ["结论", "依据", "建议", "留意", "下一步可问"]

    func parse(_ text: String) -> HealthAIAnswerPayload {
        // 解析失败时保留原文，不补造模型没有返回的结构化内容。
        let sections = markdownSections(text)
        guard !sections.isEmpty else { return .plain(text) }
        let summary = sections["结论"]?.nilIfBlank
        let basis = bullets("依据", sections)
        let actions = bullets("建议", sections)
        let risks = bullets("留意", sections)
        let followUps = bullets("下一步可问", sections)
        guard summary != nil || !basis.isEmpty || !actions.isEmpty || !risks.isEmpty || !followUps.isEmpty else {
            return .plain(text)
        }
        return HealthAIAnswerPayload(
            summary: summary,
            basis: basis,
            actions: actions,
            risks: risks,
            followUps: followUps,
            rawMarkdown: text
        )
    }

    private func markdownSections(_ text: String) -> [String: String] {
        var sections: [String: [String]] = [:]
        var current: String?
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                let title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if titles.contains(title) {
                    current = title
                    sections[title, default: []] = []
                    continue
                }
            }
            guard let current else { continue }
            sections[current, default: []].append(line)
        }
        return sections.mapValues { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func bullets(_ title: String, _ sections: [String: String]) -> [String] {
        let body = sections[title] ?? ""
        let items = body.components(separatedBy: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { return nil }
            return String(trimmed.dropFirst(2)).nilIfBlank
        }
        return items.isEmpty ? body.nilIfBlank.map { [$0] } ?? [] : items
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
