import SwiftUI

struct HRVPenPlot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let samples: [TimeSeriesPointDouble]
    let xDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    let tint: Color
    let lineGradient: LinearGradient

    @State private var progress = 0.0
    @State private var finishedDrawing = false
    @State private var inspection = HRVPenInspection()
    @GestureState private var pressing = false
    @AccessibilityFocusState private var accessibilityFocused: Bool

    private var inspecting: Bool { inspection.index != nil }

    var body: some View {
        GeometryReader { geometry in
            let positions = positions(in: geometry.size)
            let index = inspection.index ?? samples.indices.last
            ZStack(alignment: .topLeading) {
                HRVPenStroke(points: positions, progress: progress, fillsArea: true)
                    .fill(LinearGradient(colors: [tint.opacity(0.23), tint.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                HRVPenStroke(points: positions, progress: progress, fillsArea: false)
                    .stroke(tint.opacity(0.13), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                HRVPenStroke(points: positions, progress: progress, fillsArea: false)
                    .stroke(lineGradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                if let index, positions.indices.contains(index) {
                    if inspecting {
                        Path { path in
                            path.move(to: CGPoint(x: positions[index].x, y: 0))
                            path.addLine(to: CGPoint(x: positions[index].x, y: geometry.size.height))
                        }
                        .stroke(tint.opacity(0.45), lineWidth: 0.75)
                    }
                    HRVPenEndpoint(tint: tint, breathes: finishedDrawing && !inspecting && !reduceMotion && scenePhase == .active)
                        .position(positions[index])
                        .opacity(finishedDrawing || inspecting ? 1 : 0)
                }

                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(pressGesture(positions: positions))
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard !pressing, !accessibilityFocused else { return }
                            select(location.x, positions: positions, input: .pointer)
                        case .ended:
                            inspection.end(.pointer)
                        }
                    }

                if !samples.isEmpty {
                    let safeIndex = min(inspection.lastIndex, samples.count - 1)
                    let bubbleWidth = min(CGFloat(170), geometry.size.width)
                    HRVPenTooltip(sample: samples[safeIndex], tint: tint, reduceMotion: reduceMotion)
                        .frame(width: bubbleWidth, height: 42)
                        .position(
                            x: min(max(positions[safeIndex].x, bubbleWidth / 2), geometry.size.width - bubbleWidth / 2),
                            y: -24
                        )
                        .opacity(inspecting ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: inspecting)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("今日HRV趋势"))
            .accessibilityValue(accessibilityReadout)
            .accessibilityFocused($accessibilityFocused)
            .accessibilityAdjustableAction(adjustSelection)
        }
        .task {
            await reveal()
        }
        .onChange(of: samples) { _, _ in
            // Live health updates must not replay the entrance or retain a stale index.
            inspection.reset()
            finishReveal()
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { finishReveal() }
        }
        .onChange(of: pressing) { _, pressed in
            if !pressed { inspection.end(.touch) }
        }
        .onChange(of: accessibilityFocused) { _, focused in
            if !focused { inspection.end(.accessibility) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                inspection.reset()
                finishReveal()
            }
        }
        .onDisappear(perform: resetPresentation)
    }

    private var accessibilityReadout: Text {
        let index = inspection.index ?? (samples.count - 1)
        guard samples.indices.contains(index) else { return Text("暂无今日数据") }
        let sample = samples[index]
        return Text("\(Date(timeIntervalSince1970: TimeInterval(sample.timestamp)).formatted(date: .abbreviated, time: .shortened))，\(Int(sample.value.rounded())) ms")
    }

    private func positions(in size: CGSize) -> [CGPoint] {
        let start = xDomain.lowerBound.timeIntervalSince1970
        let duration = max(1, xDomain.upperBound.timeIntervalSince1970 - start)
        let span = max(1, yDomain.upperBound - yDomain.lowerBound)
        return samples.map {
            CGPoint(
                x: min(max((Double($0.timestamp) - start) / duration, 0), 1) * size.width,
                y: (1 - min(max(($0.value - yDomain.lowerBound) / span, 0), 1)) * size.height
            )
        }
    }

    private func pressGesture(positions: [CGPoint]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.16, maximumDistance: 16)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($pressing) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                if case .second(true, let drag) = value, let drag {
                    select(drag.location.x, positions: positions, input: .touch)
                }
            }
            .onEnded { _ in inspection.end(.touch) }
    }

    private func select(_ x: CGFloat, positions: [CGPoint], input: HRVPenInspection.Input) {
        finishReveal()
        inspection.select(HRVPenGeometry.nearestIndex(x: x, positions: positions), input: input)
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: inspection.adjust(by: 1, count: samples.count)
        case .decrement: inspection.adjust(by: -1, count: samples.count)
        @unknown default: return
        }
        finishReveal()
    }

    private func resetPresentation() {
        finishedDrawing = false
        inspection.reset()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { progress = 0 }
    }

    private func finishReveal() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { progress = 1 }
        finishedDrawing = true
    }

    private func reveal() async {
        guard samples.count > 1 else {
            finishReveal()
            return
        }
        progress = reduceMotion ? 1 : 0
        finishedDrawing = reduceMotion
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 1.2)) { progress = 1 }
        do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
        guard !Task.isCancelled else { return }
        finishedDrawing = true
    }
}
