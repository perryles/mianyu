import Foundation

/// 某一天的一组行为输入和健康结果，用于散点、相关性和回归趋势计算。
struct BehaviorImpactPoint: Identifiable, Hashable {
    var id: String { date }

    let date: String
    let x: Double
    let y: Double
}

struct BehaviorImpactRegressionPoint: Identifiable, Equatable {
    var id: Double { x }

    let x: Double
    let y: Double
}

/// 图表一次渲染所需的统计结果。`nil` 表示当前样本不足以支持可靠计算，
/// 视图应展示“样本不足”，而不是把它误写成相关系数为 0。
struct BehaviorImpactSummary: Equatable {
    let sampleCount: Int
    let correlation: Double?
    let meanX: Double?
    let meanY: Double?
    let regressionLine: [BehaviorImpactRegressionPoint]
}

/// 行为影响图的纯计算入口，避免视图渲染过程中重复实现统计口径。
enum BehaviorImpactAnalyzer {
    /// 计算 Pearson 相关系数及一元线性回归线。
    ///
    /// 口径约定：
    /// - 先剔除 NaN 和无穷值，确保 Chart 与统计结果使用同一批有效样本；
    /// - 至少 3 组样本才展示相关关系，避免两点天然形成“完美直线”的误导；
    /// - 任一维度没有变化时，相关系数没有定义，因此返回 `nil`；
    /// - 回归线只输出 X 最小值和最大值两个端点，交给 Charts 绘制直线。
    static func summary(for points: [BehaviorImpactPoint]) -> BehaviorImpactSummary {
        let finitePoints = points.filter { $0.x.isFinite && $0.y.isFinite }
        guard !finitePoints.isEmpty else {
            return BehaviorImpactSummary(
                sampleCount: 0,
                correlation: nil,
                meanX: nil,
                meanY: nil,
                regressionLine: []
            )
        }

        let meanX = finitePoints.map(\.x).reduce(0, +) / Double(finitePoints.count)
        let meanY = finitePoints.map(\.y).reduce(0, +) / Double(finitePoints.count)
        guard finitePoints.count >= 3 else {
            return BehaviorImpactSummary(
                sampleCount: finitePoints.count,
                correlation: nil,
                meanX: meanX,
                meanY: meanY,
                regressionLine: []
            )
        }

        // 中心化后直接使用离差平方和计算，避免先生成标准差造成额外舍入误差。
        let centered = finitePoints.map { ($0.x - meanX, $0.y - meanY) }
        let sumXX = centered.reduce(0) { $0 + $1.0 * $1.0 }
        let sumYY = centered.reduce(0) { $0 + $1.1 * $1.1 }
        let sumXY = centered.reduce(0) { $0 + $1.0 * $1.1 }
        guard sumXX > .ulpOfOne, sumYY > .ulpOfOne else {
            return BehaviorImpactSummary(
                sampleCount: finitePoints.count,
                correlation: nil,
                meanX: meanX,
                meanY: meanY,
                regressionLine: []
            )
        }

        let correlation = max(-1, min(1, sumXY / sqrt(sumXX * sumYY)))
        let slope = sumXY / sumXX
        let intercept = meanY - slope * meanX
        let minimumX = finitePoints.map(\.x).min() ?? meanX
        let maximumX = finitePoints.map(\.x).max() ?? meanX

        return BehaviorImpactSummary(
            sampleCount: finitePoints.count,
            correlation: correlation,
            meanX: meanX,
            meanY: meanY,
            regressionLine: [
                BehaviorImpactRegressionPoint(x: minimumX, y: slope * minimumX + intercept),
                BehaviorImpactRegressionPoint(x: maximumX, y: slope * maximumX + intercept)
            ]
        )
    }
}
