/// Bio Balance Widget Control 定义 WidgetKit 小组件入口或配置，负责把应用中的关键数据以系统小组件的形式展示出来。
import AppIntents
import SwiftUI
import WidgetKit

/// 应用小组件Control结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct MianyuWidgetControl: ControlWidget {
    static let kind: String = "com.boundesu.BioBalance.BioBalanceHydrationControl"

    var body: some ControlWidgetConfiguration {
        let waterIntake = Int(AppGroupSnapshotStore.load()?.hydration.waterIntakeMl ?? 0)
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: QuickHydrationIntent(amountMl: 250)) {
                Label("今日 \(waterIntake)ml · 记录 250ml", systemImage: "drop.fill")
            }
        }
        .displayName("快速补水")
        .description("一键记录 250ml 饮水，保持今天的补水节奏。")
    }
}

/// 快捷HydrationIntent结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct QuickHydrationIntent: AppIntent {
    static let title: LocalizedStringResource = "快速记录补水"
    static let description = IntentDescription("在不打开 App 的情况下快速记录一杯水。")

    @Parameter(title: "补水量")
    var amountMl: Double

    init() {}

    init(amountMl: Double) {
        self.amountMl = amountMl
    }

    func perform() async throws -> some IntentResult {
        let intent = AddWaterIntent(amountMl: amountMl)
        _ = try await intent.perform()
        return .result()
    }
}
