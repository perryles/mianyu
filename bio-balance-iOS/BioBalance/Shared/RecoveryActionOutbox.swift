import Foundation

/// 小组件端行动状态变更的出站条目，等待主 App 消费后写回本地行动状态库
struct RecoveryActionOutboxEntry: Codable, Sendable, Hashable {
    let planID: String
    let actionID: String
    let stateRawValue: String
    let updatedAt: Date
}

/// App Group 出站队列：小组件把"完成行动"先写入队列并乐观更新快照，
/// 主 App 在前台同步今日计划时消费队列，落库到 DailyRecoveryOrchestrationStore。
enum RecoveryActionOutbox {
    static let key = "recoveryActionOutbox.v1"
    private static let maxEntries = 12

    static func append(_ entry: RecoveryActionOutboxEntry) {
        guard let defaults = AppGroupManager.userDefaults() else { return }
        var entries = load(defaults: defaults)
        // 同一行动只保留最新一条，避免重复落库
        entries.removeAll { $0.planID == entry.planID && $0.actionID == entry.actionID }
        entries.append(entry)
        guard let data = try? JSONEncoder().encode(Array(entries.suffix(maxEntries))) else { return }
        defaults.set(data, forKey: key)
    }

    /// 读取并清空队列（主 App 消费用）
    static func drain() -> [RecoveryActionOutboxEntry] {
        guard let defaults = AppGroupManager.userDefaults() else { return [] }
        let entries = load(defaults: defaults)
        if !entries.isEmpty {
            defaults.removeObject(forKey: key)
        }
        return entries
    }

    private static func load(defaults: UserDefaults) -> [RecoveryActionOutboxEntry] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([RecoveryActionOutboxEntry].self, from: data) else {
            return []
        }
        return entries
    }
}
