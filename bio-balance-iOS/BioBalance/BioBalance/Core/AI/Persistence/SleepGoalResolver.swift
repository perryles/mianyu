import Foundation

/// 读取统一后的睡眠目标键，为确定性引擎提供明确输入。
nonisolated enum SleepGoalResolver {
    private static let validGoalMinutes = 60...960

    static func configuredGoalMinutes(defaults: UserDefaults = .standard) -> Int? {
        let modern = defaults.double(forKey: "daily_sleep_goal_hours")
        return validMinutes(fromHours: modern)
    }

    static func goalMinutes(
        defaultValue: Int = 480,
        defaults: UserDefaults = .standard
    ) -> Int {
        if let configured = configuredGoalMinutes(defaults: defaults) { return configured }
        return validGoalMinutes.contains(defaultValue) ? defaultValue : 480
    }

    /// 拒绝非有限值和不合理目标，避免损坏的 UserDefaults 在 Double 转 Int 时触发崩溃。
    private static func validMinutes(fromHours hours: Double) -> Int? {
        guard hours.isFinite,
              let minutes = Int(exactly: (hours * 60).rounded()),
              validGoalMinutes.contains(minutes) else { return nil }
        return minutes
    }
}
