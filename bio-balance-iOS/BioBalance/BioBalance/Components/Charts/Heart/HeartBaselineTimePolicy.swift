import Foundation

nonisolated enum HeartBaselineTimePolicy {
    static let intradayTolerance: TimeInterval = 90 * 60

    static func matchingIndex(on date: Date, dates: [Date], intraday: Bool, calendar: Calendar = .current) -> Int? {
        let sameDay = dates.indices.filter { calendar.isDate(dates[$0], inSameDayAs: date) }
        guard let index = sameDay.min(by: { abs(dates[$0].timeIntervalSince(date)) < abs(dates[$1].timeIntervalSince(date)) }) else { return nil }
        if intraday, abs(dates[index].timeIntervalSince(date)) > intradayTolerance { return nil }
        return index
    }

    static func segments(dates: [Date], intraday: Bool, calendar: Calendar = .current) -> [[Int]] {
        var result: [[Int]] = []
        for index in dates.indices.sorted(by: { dates[$0] < dates[$1] }) {
            if let previous = result.last?.last {
                let connected: Bool
                if intraday {
                    connected = calendar.isDate(dates[previous], inSameDayAs: dates[index])
                        && dates[index].timeIntervalSince(dates[previous]) <= intradayTolerance
                } else {
                    let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dates[previous]))
                    connected = next.map { calendar.startOfDay(for: dates[index]) <= $0 } ?? false
                }
                if connected {
                    result[result.count - 1].append(index)
                    continue
                }
            }
            result.append([index])
        }
        return result
    }
}
