import Foundation

/// Normalizes compact widget chart inputs into the closed 0...1 range.
/// Non-finite values are treated as unavailable so a malformed metric cannot
/// produce an invalid SwiftUI frame or path.
enum WidgetMetricSeries {
    static func normalized(_ values: [Double]) -> [Double] {
        values.map { value in
            guard value.isFinite else { return 0 }
            return min(1, max(0, value / 100))
        }
    }

    static func recentNormalized(
        _ values: [Double],
        limit: Int,
        fallback: [Double] = []
    ) -> [Double] {
        guard !values.isEmpty, limit > 0 else { return fallback }
        return normalized(Array(values.suffix(limit)))
    }
}
