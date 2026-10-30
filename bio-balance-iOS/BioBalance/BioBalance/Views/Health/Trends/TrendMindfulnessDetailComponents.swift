/// MindfulnessDetailContent 作为趋势模块的支撑类型，负责渲染「心理正念」详情页。
/// 负责将正念指标、状态与时间范围分发到专用趋势仪表盘。

import SwiftUI


/// 正念详情内容结构体 作为趋势模块里的辅助类型。
/// 负责趋势分析展示。用于趋势页面的“心理正念”详情页。
struct MindfulnessDetailContent: View {
    let detail: TrendCategoryDetailModel
    let range: TrendsRange
    var isStaticForExport: Bool = false

    var body: some View {
        MindfulnessSpecializedTrendDashboard(
            metrics: detail.metrics,
            status: detail.status,
            range: range,
            isStaticForExport: isStaticForExport
        )
    }
}
