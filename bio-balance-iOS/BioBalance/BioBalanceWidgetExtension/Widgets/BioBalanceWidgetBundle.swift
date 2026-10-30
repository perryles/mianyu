/// Bio Balance Widget Bundle 定义 WidgetKit 小组件入口或配置，负责把应用中的关键数据以系统小组件的形式展示出来。
//
//  BioBalanceWidgetBundle.swift
//  BioBalanceWidget
//
//  Created by lihaha on 2026/4/15.
//

import WidgetKit
import SwiftUI

/// 应用小组件集合结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
@main
struct MianyuWidgetBundle: WidgetBundle {
    var body: some Widget {
        MianyuWidget()
        SunlightWidget()
        StressWidget()
        ActivityWidget()
        ActivityConfigurableWidget()
        SleepWidget()
        VitalsWidget()
        MianyuWidgetLiveActivity()
        MianyuWidgetControl()
    }
}
