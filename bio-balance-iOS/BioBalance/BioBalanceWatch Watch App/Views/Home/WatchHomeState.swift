import SwiftUI

struct WatchHomeHeroState: Equatable {
    let statusText: String
    let valueColor: Color
}

enum WatchHomeStateMapper {
    static func makeHeroState(snapshot: WatchRealtimeHealth) -> WatchHomeHeroState {
        let hrv = snapshot.hrv
        let statusText: String
        let valueColor: Color

        if hrv >= 48 {
            statusText = String(localized: "恢复良好")
            valueColor = Color(red: 0.54, green: 0.88, blue: 0.62)
        } else if hrv >= 25 {
            statusText = String(localized: "状态正常")
            valueColor = Color(red: 0.75, green: 0.72, blue: 1.0)
        } else if hrv > 0 {
            statusText = String(localized: "需要恢复")
            valueColor = Color(red: 0.99, green: 0.72, blue: 0.47)
        } else if snapshot.stress_value > 0 {
            statusText = pressureLevelText(for: snapshot.stress_value)
            valueColor = pressureColor(for: snapshot.stress_value)
        } else {
            statusText = String(localized: "等待同步")
            valueColor = .white.opacity(0.86)
        }

        return WatchHomeHeroState(
            statusText: statusText,
            valueColor: valueColor
        )
    }
}
