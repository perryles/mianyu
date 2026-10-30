import SwiftUI
import Charts

struct TodayHRVPenChart: View {
    let samples: [TimeSeriesPointDouble]
    let xDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    let axisDates: [Date]
    let axisValues: [Double]
    let reference: Double?
    let referenceLabel: String
    let average: Double?
    let tint: Color
    let lineGradient: LinearGradient

    var body: some View {
        Chart {
            if let reference {
                RuleMark(y: .value(referenceLabel, reference))
                    .foregroundStyle(tint.opacity(0.34))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(referenceLabel)
                            .font(.appSystem(size: 10, weight: .bold))
                            .foregroundStyle(tint)
                    }
            }
            if let average {
                RuleMark(y: .value("日内均值", average))
                    .foregroundStyle(tint.opacity(0.26))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 5]))
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text("日内均值 \(Int(average.rounded())) ms")
                            .font(.appSystem(size: 10, weight: .bold))
                            .foregroundStyle(tint)
                    }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisGridLine().foregroundStyle(Theme.Colors.textTertiary.opacity(0.12))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date == xDomain.upperBound ? "24" : date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                            .font(.appSystem(size: 9))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: axisValues) { _ in
                AxisGridLine().foregroundStyle(Theme.Colors.textTertiary.opacity(0.12))
                AxisValueLabel().font(.appSystem(size: 10))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    HRVPenPlot(
                        samples: samples, xDomain: xDomain, yDomain: yDomain,
                        tint: tint, lineGradient: lineGradient
                    )
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .frame(height: 150)
        // A dedicated tooltip lane keeps the bubble out of the line and headings.
        .padding(.top, 46)
    }
}
