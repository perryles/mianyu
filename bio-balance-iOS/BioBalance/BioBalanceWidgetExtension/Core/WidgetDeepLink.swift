/// Widget Deep Link 定义 WidgetKit 小组件入口或配置，负责把应用中的关键数据以系统小组件的形式展示出来。
import Foundation

/// 应用小组件深度链接枚举 作为核心能力层里的能力或分类定义。
/// 负责描述Widget 展示与配置过程中会用到的状态、分类或分支。
enum MianyuWidgetDeepLink {
    static let overall = URL(string: "biobalance://widget/overall")
    static let sunlight = URL(string: "biobalance://widget/sunlight")
    static let vitals = URL(string: "biobalance://widget/vitals")
    static let stress = URL(string: "biobalance://widget/stress")
    static let activity = URL(string: "biobalance://widget/activity")
    static let sleep = URL(string: "biobalance://widget/sleep")
}