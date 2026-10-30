import SwiftUI
import Charts

/// Presentation and hit testing are isolated from activity summaries and data preparation.
struct ActivityTrendPlot: View {
    let displayedPoints: [ActivityTrendReading]
    let selectedMetric: ActivityTrendMetric
    let selectedRange: Int
    let plotDateDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    @Binding var selectedDate: Date?

    private var selectedPoint: ActivityTrendReading? {
        guard let selectedDate else { return displayedPoints.last }
        return ActivityTrendData.selected(on: selectedDate, in: displayedPoints)
    }

    var body: some View {
        Chart {
            if !selectedMetric.usesBars {
                ForEach(Array(ActivityTrendData.segments(displayedPoints).enumerated()), id: \.offset) { segmentIndex, segment in
                    ForEach(segment) { item in
                        LineMark(
                            x: .value("日期", item.date),
                            y: .value(selectedMetric.rawValue, item.value),
                            series: .value("连续记录", segmentIndex)
                        )
                        .foregroundStyle(selectedMetric.tint)
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            ForEach(displayedPoints) { item in
                if selectedMetric.usesBars {
                    activityBarMark(for: item)
                } else {
                    activityPointMark(for: item)
                }
            }

            if let selectedPoint {
                selectedRuleMark(for: selectedPoint)
                selectedHighlightPointMark(for: selectedPoint)
            }
        }
        .chartXScale(domain: plotDateDomain)
        .chartYScale(domain: yDomain)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                updateSelection(at: location, frame: frame, proxy: proxy)
                            case .ended:
                                selectedDate = nil
                            }
                        }
                        .gesture(
                            LongPressGesture(minimumDuration: 0.25)
                                .sequenced(before: DragGesture(minimumDistance: 0))
                                .onChanged { value in
                                    switch value {
                                    case .first:
                                        break
                                    case .second(true, let drag):
                                        guard let drag else { return }
                                        updateSelection(at: drag.location, frame: frame, proxy: proxy)
                                    default:
                                        break
                                    }
                                }
                                .onEnded { value in
                                    switch value {
                                    case .second(true, let drag):
                                        if let drag {
                                            updateSelection(at: drag.location, frame: frame, proxy: proxy)
                                        }
                                    default:
                                        break
                                    }
                                }
                        )
                } else {
                    Color.clear
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: selectedRange == 7 ? 4 : 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.16))
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day(.defaultDigits))
                    .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7, dash: [4, 4]))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.18))
                AxisValueLabel()
                    .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.leading, 4)
                .padding(.trailing, 8)
        }
        .frame(height: 230)
    }

    @ChartContentBuilder
    private func activityBarMark(for item: ActivityTrendReading) -> some ChartContent {
        BarMark(
            x: .value("日期", item.date, unit: .day),
            y: .value(selectedMetric.rawValue, item.value)
        )
        .foregroundStyle(barGradient(for: item))
        .cornerRadius(6)
    }



    @ChartContentBuilder
    private func activityPointMark(for item: ActivityTrendReading) -> some ChartContent {
        PointMark(
            x: .value("日期", item.date),
            y: .value(selectedMetric.rawValue, item.value)
        )
        .foregroundStyle(selectedMetric.tint)
        .symbolSize(pointSize(for: item))
        .opacity(pointOpacity(for: item))
    }

    @ChartContentBuilder
    private func selectedRuleMark(for point: ActivityTrendReading) -> some ChartContent {
        RuleMark(x: .value("选中", ActivityTrendData.plotDate(for: point, metric: selectedMetric)))
            .foregroundStyle(selectedMetric.tint.opacity(0.24))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    @ChartContentBuilder
    private func selectedHighlightPointMark(for point: ActivityTrendReading) -> some ChartContent {
        PointMark(
            x: .value("日期", ActivityTrendData.plotDate(for: point, metric: selectedMetric)),
            y: .value(selectedMetric.rawValue, point.value)
        )
        .symbolSize(88)
        .foregroundStyle(Theme.Colors.onAccent)
        .annotation(position: .overlay, alignment: .center) {
            Circle()
                .fill(selectedMetric.tint)
                .frame(width: 13, height: 13)
        }
    }

    private func updateSelection(at location: CGPoint, frame: CGRect, proxy: ChartProxy) {
        guard frame.contains(location) else { return }
        let relativeX = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: relativeX) else { return }
        selectedDate = Calendar.current.startOfDay(for: date)
    }

    private func isSelected(_ item: ActivityTrendReading) -> Bool {
        selectedPoint?.timestamp == item.timestamp
    }

    private func hasSelection() -> Bool {
        selectedPoint != nil
    }

    private func primaryBarOpacity(for item: ActivityTrendReading) -> Double {
        !hasSelection() || isSelected(item) ? 0.96 : 0.42
    }

    private func secondaryBarOpacity(for item: ActivityTrendReading) -> Double {
        !hasSelection() || isSelected(item) ? 0.42 : 0.18
    }



    private func pointOpacity(for item: ActivityTrendReading) -> Double {
        !hasSelection() || isSelected(item) ? 1 : 0.32
    }

    private func pointSize(for item: ActivityTrendReading) -> Double {
        isSelected(item) ? 56 : 28
    }

    private func barGradient(for item: ActivityTrendReading) -> LinearGradient {
        LinearGradient(
            colors: [
                selectedMetric.tint.opacity(primaryBarOpacity(for: item)),
                selectedMetric.tint.opacity(secondaryBarOpacity(for: item))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
