import Foundation

nonisolated public struct WatchStressHistoryPoint: Codable, Equatable, Identifiable, Sendable {
    let timestamp: Int
    let value: Int

    public var id: Int { timestamp }
}
