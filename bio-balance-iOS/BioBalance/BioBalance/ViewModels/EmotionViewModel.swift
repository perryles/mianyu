import SwiftUI

/// 情绪视图模型 作为视图模型层里的界面状态管理入口。
/// 负责连接界面与底层数据源，处理状态管理、业务计算和用户操作响应。
@MainActor
@Observable
final class EmotionViewModel {
    var records: [EmotionRecord] = []

    func load(days: Int = 7) {
        Task {
            // 本地优先：无自建后端，情绪历史取自本机 MoodStore。
            let now = Date()
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
            let list: [EmotionRecord] = MoodStore.shared.allEntries()
                .filter { $0.loggedAt >= start }
                .map { entry in
                    EmotionRecord(
                        emotion: entry.backendEmotionCode,
                        intensity: entry.intensity,
                        source: "mood",
                        timestamp: Int(entry.loggedAt.timeIntervalSince1970)
                    )
                }
            records = list.sorted { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
        }
    }
}
