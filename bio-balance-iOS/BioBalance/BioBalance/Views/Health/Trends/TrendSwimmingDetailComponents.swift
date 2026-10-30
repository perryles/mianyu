/// SwimmingDetailContent 作为趋势模块的支撑类型，负责渲染「游泳趋势」详情页。
/// 负责将游泳指标、状态与时间范围分发到运动专用趋势仪表盘。

import SwiftUI


/// 游泳详情内容结构体 作为趋势模块里的辅助类型。
/// 负责趋势分析展示。用于趋势页面的“游泳趋势”详情页。
struct SwimmingDetailContent: View {
    let detail: TrendCategoryDetailModel
    let range: TrendsRange
    var isStaticForExport: Bool = false

    var body: some View {
        SportSpecializedTrendDashboard(
            kind: .swimming,
            metrics: detail.metrics,
            status: detail.status,
            range: range,
            accent: detail.category.accentColor,
            isStaticForExport: isStaticForExport
        )
    }
}
