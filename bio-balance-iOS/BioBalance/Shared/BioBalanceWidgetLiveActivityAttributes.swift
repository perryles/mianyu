#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

nonisolated struct MianyuWidgetAttributes: ActivityAttributes {
    public nonisolated struct ContentState: Codable, Hashable, Sendable {
        var title: String
        var primaryValue: String
        var detail: String
        var tone: String
        var symbolName: String
        /// iOS 26+: 用于 CarPlay/macOS 菜单栏的紧凑副标题
        var supplementalSubtitle: String?
        /// 提醒触发时间，用于锁屏与灵动岛的实时倒计时展示
        var fireDate: Date?
        /// 发布时间，作为倒计时进度条的固定起点
        var startDate: Date?
    }

    var name: String
    /// 提醒标识符，用于多活动并发追踪与精确 Deep Link；旧版活动解码后为 nil
    var reminderIdentifier: String?
}
#endif
