/// ReportChartExtensions 作为报告模块的图表样式扩展。
/// 负责为 LineMark 等图表元素提供报告评分曲线的统一视觉样式。

import SwiftUI
import Charts

// MARK: - Chart 标记扩展

/// LineMark 报告评分曲线样式
extension LineMark {
    /// 应用报告评分曲线的视觉样式（颜色、平滑插值、圆头线端）
    func reportsScoreLine(tint: Color = ReportsChartStyle.score) -> some ChartContent {
        foregroundStyle(tint)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }
}

/// AreaMark 报告评分面积样式
extension AreaMark {
    /// 应用报告评分区域的渐变填充和平滑插值
    func reportsScoreArea(tint: Color = ReportsChartStyle.score) -> some ChartContent {
        foregroundStyle(
            LinearGradient(
                colors: [tint.opacity(0.20), tint.opacity(0.015)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
            .interpolationMethod(.catmullRom)
    }
}

/// PointMark 报告评分数据点样式
extension PointMark {
    /// 应用报告评分数据点的圆形标记样式
    func reportsScorePoint(tint: Color = ReportsChartStyle.score) -> some ChartContent {
        foregroundStyle(tint)
            .symbol(.circle)
            .symbolSize(46)
    }
}

/// BarMark 报告评分柱状图样式
extension BarMark {
    /// 应用报告评分柱状图的渐变填充和圆角
    func reportsScoreBar(tint: Color = ReportsChartStyle.score) -> some ChartContent {
        foregroundStyle(
            LinearGradient(
                colors: [tint.opacity(0.96), tint.opacity(0.58)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(5)
    }
}

/// RuleMark 报告参考线样式
extension RuleMark {
    /// 均值虚线样式
    func reportsAverageRule() -> some ChartContent {
        foregroundStyle(ReportsChartStyle.averageLine)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    /// 稳定基线虚线样式
    func reportsStabilityRule() -> some ChartContent {
        foregroundStyle(ReportsChartStyle.stabilityLine)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 5]))
    }

    /// 选区指示线样式
    func reportsSelectionRule(tint: Color = ReportsChartStyle.selectionLine) -> some ChartContent {
        foregroundStyle(tint.opacity(0.46))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
    }
}

// MARK: - 评分区间色带

/// 生成评分区间的背景色带（用于图表背景分层着色）
@ChartContentBuilder
func reportsScoreZoneBands() -> some ChartContent {
    RectangleMark(yStart: .value("承压下限", 0), yEnd: .value("承压上限", 50))
        .foregroundStyle(ReportsScorePalette.tint(for: 40).opacity(0.055))
    RectangleMark(yStart: .value("波动下限", 50), yEnd: .value("波动上限", 70))
        .foregroundStyle(ReportsScorePalette.tint(for: 60).opacity(0.05))
    RectangleMark(yStart: .value("稳定下限", 70), yEnd: .value("稳定上限", 85))
        .foregroundStyle(ReportsScorePalette.tint(for: 75).opacity(0.045))
    RectangleMark(yStart: .value("优秀下限", 85), yEnd: .value("优秀上限", 100))
        .foregroundStyle(ReportsScorePalette.tint(for: 90).opacity(0.05))
}

// MARK: - 图表框架修饰器

/// 报告评分图表的统一框架修饰器
/// 固定 Y 轴范围、刻度标记和绘图区样式，保证所有评分图表视觉一致。
extension View {
    func reportsScoreChartFrame(height: CGFloat = 160) -> some View {
        self
            .frame(height: height)
            .chartPlotStyle { plotArea in
                plotArea
                    .bbChartPlotSurface(tint: ReportsChartStyle.score, cornerRadius: 10)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 70, 85, 100]) { _ in
                    AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                    AxisValueLabel()
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(ReportsChartStyle.axisLabel)
                }
            }
    }
}

// MARK: - 日期格式化扩展

/// 报告页面专用的日期格式化扩展
extension Date {
    /// 短日期格式（如"3月15日 周六"），用于卡片标签和历史列表
    func reportsShortDateString(locale: Locale = Locale.autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "M月d日 E"
        return formatter.string(from: self)
    }
    
    /// 完整日期格式（如"2025年3月15日 星期六"），用于页面标题
    func reportsFullDateString(locale: Locale = Locale.autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter.string(from: self)
    }
}
