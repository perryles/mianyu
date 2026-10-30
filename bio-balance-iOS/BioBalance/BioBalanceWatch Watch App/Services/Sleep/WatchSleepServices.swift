import Foundation
import Observation

struct WatchSleepSignalSnapshot: Equatable, Sendable {
    let likelihood: Double
    let sleepStartHint: Date?
    let source: String
}

final class WatchSleepSignalService {
    func evaluate(snapshot: WatchRealtimeHealth, now: Date = Date()) -> WatchSleepSignalSnapshot {
        let heartFactor = snapshot.bpm > 0 ? max(0, 1.0 - (Double(snapshot.bpm - 48) / 42.0)) : 0.32
        let movementFactor = snapshot.steps == 0 ? 0.88 : max(0.12, 1.0 - Double(min(snapshot.steps, 1200)) / 1200.0)
        let sleepFactor = snapshot.sleepDurationMinutes > 0 ? 0.76 : 0.22
        let likelihood = min(0.98, max(0, heartFactor * 0.44 + movementFactor * 0.34 + sleepFactor * 0.22))
        let hintedStart = likelihood > 0.62 ? Calendar.current.date(byAdding: .minute, value: -25, to: now) : nil
        return WatchSleepSignalSnapshot(
            likelihood: likelihood,
            sleepStartHint: hintedStart,
            source: likelihood > 0.62 ? "heart+activity" : "watch_idle"
        )
    }
}

@Observable
@MainActor
final class WatchSleepStatusViewModel {
    var payload: WatchSleepStatePayload = .idle

    var statusTitle: String {
        switch payload.phase {
        case .idle: return String(localized: "等待今晚监测")
        case .armed: return String(localized: "已准备联动")
        case .monitoring: return String(localized: "iPhone 正在分析")
        case .finalizing: return String(localized: "整理昨夜结果")
        case .synced: return String(localized: "已同步")
        case .surfaced: return String(localized: "昨夜结果已生成")
        }
    }

    var statusSummary: String {
        if let summary = payload.summary {
            return String(localized: "睡眠 \(summary.sleepDurationMinutes / 60)h \(summary.sleepDurationMinutes % 60)m · 鼾声 \(summary.snoreSummary.intensity.title)")
        }
        if payload.watchConnected {
            return String(localized: "Watch 置信度 \(Int((payload.watchConfidence * 100).rounded()))%")
        }
        return String(localized: "等待 iPhone 建立今晚会话")
    }

    func apply(_ payload: WatchSleepStatePayload) {
        self.payload = payload
    }
}