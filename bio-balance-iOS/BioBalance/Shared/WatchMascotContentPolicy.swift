import Foundation

/// Keeps user-authored Watch content short enough for the smallest supported display.
nonisolated public enum WatchMascotContentPolicy {
    public static let maximumLength = 24

    public static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maximumLength))
    }
}

nonisolated public enum WatchMascotMessageUpdatePolicy {
    public static func resolve(current: String?, incoming: String?, isConfigured: Bool?) -> String? {
        guard isConfigured == true else { return current }
        return WatchMascotContentPolicy.normalize(incoming)
    }
}
