/// Bio Balance Complication Widget Bundle 定义并发症组件，负责把关键状态以更轻量的形式展示在 Apple Watch 表盘上。
import WidgetKit
import SwiftUI

/// 应用复杂功能小组件集合结构体 作为表盘组件扩展里的辅助类型。
/// 负责表盘并发症展示。
@main
struct MianyuComplicationWidgetBundle: WidgetBundle {
    var body: some Widget {
        MianyuComplicationWidget()
        overviewAndRecoveryWidgets
        sleepAndActivityWidgets
        hydrationAndBodyAgeWidgets
        #if os(watchOS) && compiler(>=6.2)
        if #available(watchOS 26.0, *) {
            MianyuRelevanceWidget()
        }
        #endif
    }

    @WidgetBundleBuilder
    private var overviewAndRecoveryWidgets: some Widget {
        MianyuComplicationOverviewRectangularWidget()
        MianyuComplicationOverviewCircularWidget()
        #if os(watchOS)
        MianyuComplicationOverviewCornerWidget()
        #endif
        MianyuComplicationRecoveryRectangularWidget()
        MianyuComplicationRecoveryCircularWidget()
        #if os(watchOS)
        MianyuComplicationRecoveryCornerWidget()
        #endif
    }

    @WidgetBundleBuilder
    private var sleepAndActivityWidgets: some Widget {
        MianyuComplicationSleepRectangularWidget()
        MianyuComplicationSleepCircularWidget()
        #if os(watchOS)
        MianyuComplicationSleepCornerWidget()
        #endif
        MianyuComplicationActivityRectangularWidget()
        MianyuComplicationActivityCircularWidget()
        #if os(watchOS)
        MianyuComplicationActivityCornerWidget()
        #endif
    }

    @WidgetBundleBuilder
    private var hydrationAndBodyAgeWidgets: some Widget {
        MianyuComplicationHydrationRectangularWidget()
        MianyuComplicationHydrationCircularWidget()
        #if os(watchOS)
        MianyuComplicationHydrationCornerWidget()
        #endif
        MianyuComplicationBodyAgeRectangularWidget()
        MianyuComplicationBodyAgeCircularWidget()
        #if os(watchOS)
        MianyuComplicationBodyAgeCornerWidget()
        #endif
    }
}
