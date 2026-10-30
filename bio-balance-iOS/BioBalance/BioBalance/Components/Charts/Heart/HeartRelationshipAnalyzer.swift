import Foundation

/// 两项心血管指标在同一时间窗口内的一组配对读数。
/// `date` 使用 X 轴指标的采样时间；周/月视图则使用聚合后的自然日开始时间。
struct HeartRelationshipPoint: Identifiable, Hashable {
    var id: Int64 { timestamp }

    let timestamp: Int64
    let xValue: Double
    let yValue: Double

    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
}

/// 回归线只需要首尾两个点，单独建模能避免把趋势线误认为真实采样点。
struct HeartRelationshipRegressionPoint: Identifiable, Hashable {
    var id: Double { xValue }

    let xValue: Double
    let yValue: Double
}

/// 三项心血管指标在同一时间窗口内的一组配对读数，供 iOS 26 的 Chart3D 探索视图使用。
struct HeartRelationship3DPoint: Identifiable, Hashable {
    var id: Int64 { timestamp }

    let timestamp: Int64
    let xValue: Double
    let yValue: Double
    let zValue: Double

    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
}

struct HeartRelationshipSummary: Equatable {
    let sampleCount: Int
    let correlation: Double?
    let meanX: Double?
    let meanY: Double?
    let regressionLine: [HeartRelationshipRegressionPoint]
}

/// 心血管联合图表的纯计算入口。
/// 计算与 SwiftUI 视图分离，便于验证时间配对、标准化和相关系数口径。
enum HeartRelationshipAnalyzer {
    /// 将三项指标配成同一批样本。日视图沿用 90 分钟容差；周/月视图按自然日均值求交集。
    static func triplePoints(
        xPoints: [TimeSeriesPointDouble],
        yPoints: [TimeSeriesPointDouble],
        zPoints: [TimeSeriesPointDouble],
        range: TrendsRange,
        calendar: Calendar = .current
    ) -> [HeartRelationship3DPoint] {
        let finiteZ = zPoints.filter { $0.value.isFinite }.sorted { $0.timestamp < $1.timestamp }

        guard range == .day else {
            // 周/月视图不应把不同采样时刻强行匹配：先汇总为日均值，再只保留三项都有数据的日期。
            let xByDay = dailyAverages(xPoints.filter { $0.value.isFinite }, calendar: calendar)
            let yByDay = dailyAverages(yPoints.filter { $0.value.isFinite }, calendar: calendar)
            let zByDay = dailyAverages(finiteZ, calendar: calendar)
            return Set(xByDay.keys)
                .intersection(yByDay.keys)
                .intersection(zByDay.keys)
                .sorted()
                .compactMap { timestamp in
                    guard let xValue = xByDay[timestamp],
                          let yValue = yByDay[timestamp],
                          let zValue = zByDay[timestamp] else { return nil }
                    return HeartRelationship3DPoint(
                        timestamp: timestamp,
                        xValue: xValue,
                        yValue: yValue,
                        zValue: zValue
                    )
                }
        }

        // 日视图先复用二维图的 X/Y 配对口径，再为每一对寻找同一时间窗口内的 Z 样本。
        let pairs = pairedPoints(xPoints: xPoints, yPoints: yPoints, range: range, calendar: calendar)
        let tolerance: Int64 = 90 * 60
        var zIndex = 0
        var result: [HeartRelationship3DPoint] = []

        for pair in pairs {
            while zIndex < finiteZ.count, finiteZ[zIndex].timestamp < pair.timestamp - tolerance {
                zIndex += 1
            }
            guard zIndex < finiteZ.count else { break }

            let zPoint = finiteZ[zIndex]
            guard abs(zPoint.timestamp - pair.timestamp) <= tolerance else { continue }

            result.append(
                HeartRelationship3DPoint(
                    timestamp: pair.timestamp,
                    xValue: pair.xValue,
                    yValue: pair.yValue,
                    zValue: zPoint.value
                )
            )
            // 每个 Z 读数最多使用一次，防止稀疏数据被复制成多组三维证据。
            zIndex += 1
        }

        return result
    }

    /// 日视图保留日内变化，以 90 分钟为容差做按时间顺序的一对一配对；周/月视图先按自然日求均值。
    /// 顺序配对不会重复使用样本，并优先保留最多有效配对，避免稀疏读数被放大成多组证据。
    static func pairedPoints(
        xPoints: [TimeSeriesPointDouble],
        yPoints: [TimeSeriesPointDouble],
        range: TrendsRange,
        calendar: Calendar = .current
    ) -> [HeartRelationshipPoint] {
        let finiteX = xPoints.filter { $0.value.isFinite }.sorted { $0.timestamp < $1.timestamp }
        let finiteY = yPoints.filter { $0.value.isFinite }.sorted { $0.timestamp < $1.timestamp }

        guard range == .day else {
            let xByDay = dailyAverages(finiteX, calendar: calendar)
            let yByDay = dailyAverages(finiteY, calendar: calendar)
            return Set(xByDay.keys)
                .intersection(yByDay.keys)
                .sorted()
                .compactMap { timestamp in
                    guard let xValue = xByDay[timestamp], let yValue = yByDay[timestamp] else { return nil }
                    return HeartRelationshipPoint(timestamp: timestamp, xValue: xValue, yValue: yValue)
                }
        }

        let tolerance: Int64 = 90 * 60
        var result: [HeartRelationshipPoint] = []
        var xIndex = 0
        var yIndex = 0

        while xIndex < finiteX.count, yIndex < finiteY.count {
            let xPoint = finiteX[xIndex]
            let yPoint = finiteY[yIndex]
            let difference = yPoint.timestamp - xPoint.timestamp

            if difference < -tolerance {
                yIndex += 1
                continue
            }
            if difference > tolerance {
                xIndex += 1
                continue
            }

            result.append(
                HeartRelationshipPoint(
                    timestamp: xPoint.timestamp,
                    xValue: xPoint.value,
                    yValue: yPoint.value
                )
            )
            xIndex += 1
            yIndex += 1
        }

        return result
    }

    static func summary(for points: [HeartRelationshipPoint]) -> HeartRelationshipSummary {
        let finitePoints = points.filter { $0.xValue.isFinite && $0.yValue.isFinite }
        guard !finitePoints.isEmpty else {
            return HeartRelationshipSummary(
                sampleCount: 0,
                correlation: nil,
                meanX: nil,
                meanY: nil,
                regressionLine: []
            )
        }

        let meanX = finitePoints.map(\.xValue).reduce(0, +) / Double(finitePoints.count)
        let meanY = finitePoints.map(\.yValue).reduce(0, +) / Double(finitePoints.count)

        // 少于三组的相关系数非常容易被偶然值主导，因此只展示配对点，不给出方向结论。
        guard finitePoints.count >= 3 else {
            return HeartRelationshipSummary(
                sampleCount: finitePoints.count,
                correlation: nil,
                meanX: meanX,
                meanY: meanY,
                regressionLine: []
            )
        }

        let centered = finitePoints.map { point in
            (x: point.xValue - meanX, y: point.yValue - meanY)
        }
        let sumXX = centered.reduce(0) { $0 + $1.x * $1.x }
        let sumYY = centered.reduce(0) { $0 + $1.y * $1.y }
        let sumXY = centered.reduce(0) { $0 + $1.x * $1.y }
        guard sumXX > .ulpOfOne, sumYY > .ulpOfOne else {
            return HeartRelationshipSummary(
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
        let minimumX = finitePoints.map(\.xValue).min() ?? meanX
        let maximumX = finitePoints.map(\.xValue).max() ?? meanX

        return HeartRelationshipSummary(
            sampleCount: finitePoints.count,
            correlation: correlation,
            meanX: meanX,
            meanY: meanY,
            regressionLine: [
                HeartRelationshipRegressionPoint(xValue: minimumX, yValue: slope * minimumX + intercept),
                HeartRelationshipRegressionPoint(xValue: maximumX, yValue: slope * maximumX + intercept)
            ]
        )
    }

    /// 将不同单位的指标换算成“相对各自区间均值的百分比偏离”，以便叠加比较形状。
    /// 这里不反转 HRV 方向，也不合成健康分数，正负值只表达高于或低于自身均值。
    static func baselineDeviations(for points: [TimeSeriesPointDouble]) -> [Double] {
        let finiteValues = points.map(\.value).filter(\.isFinite)
        guard !finiteValues.isEmpty else { return [] }
        let mean = finiteValues.reduce(0, +) / Double(finiteValues.count)
        guard abs(mean) > .ulpOfOne else { return Array(repeating: 0, count: finiteValues.count) }
        return finiteValues.map { (($0 - mean) / abs(mean)) * 100 }
    }

    private static func dailyAverages(
        _ points: [TimeSeriesPointDouble],
        calendar: Calendar
    ) -> [Int64: Double] {
        let grouped = Dictionary(grouping: points) { point in
            Int64(calendar.startOfDay(for: point.date).timeIntervalSince1970)
        }
        return grouped.mapValues { dayPoints in
            dayPoints.map(\.value).reduce(0, +) / Double(dayPoints.count)
        }
    }
}
