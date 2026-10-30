/// Add Water Intent 定义 Widget 相关的共享能力或辅助逻辑，负责支撑小组件的数据读取、样式组织与交互行为。
import AppIntents
import WidgetKit

/// Add饮水Intent结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "记录喝水"

    @Parameter(title: "增加量（ml）")
    var amountMl: Double

    init() {}

    init(amountMl: Double) {
        self.amountMl = amountMl
    }

    static var parameterSummary: some ParameterSummary {
        Summary("增加 \(\.$amountMl) ml 喝水量")
    }

    func perform() async throws -> some IntentResult {
        guard amountMl.isFinite, amountMl > 0 else {
            return .result()
        }

        let manager = AppGroupManager.shared
        let snapshot = AppGroupSnapshotStore.load()
        let increment = min(amountMl, 2_000)
        let storedCurrent = manager.getWaterIntakeMl() ?? snapshot?.hydration.waterIntakeMl ?? 0
        let current = storedCurrent.isFinite ? max(0, storedCurrent) : 0
        let storedTarget = manager.getWaterTargetMl() ?? snapshot?.hydration.waterTargetMl ?? 2_000
        let target = min(20_000, max(1, storedTarget))
        let newValue = min(10_000, current + increment)
        let completionRate = min(1.0, newValue / Double(target))
        let storedCaffeine = manager.getCaffeineRemainedMg() ?? snapshot?.hydration.caffeineRemainedMg ?? 0
        let caffeine = storedCaffeine.isFinite ? max(0, storedCaffeine) : 0
        let updatedAt = Date()

        manager.saveHabitSummary(
            waterIntakeMl: newValue,
            waterTargetMl: target,
            waterCompletionRate: completionRate,
            caffeineRemainedMg: caffeine
        )

        let updatedSnapshot = (snapshot ?? .empty(generatedAt: updatedAt)).replacingHydration(
            waterIntakeMl: newValue,
            waterTargetMl: target,
            waterCompletionRate: completionRate,
            caffeineRemainedMg: caffeine,
            updatedAt: updatedAt
        )
        AppGroupSnapshotStore.save(updatedSnapshot)

        WidgetCenter.shared.reloadTimelines(ofKind: AppGroupSchema.Kind.overall)
        for kind in AppGroupSchema.Kind.allComplicationKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        return .result()
    }
}
