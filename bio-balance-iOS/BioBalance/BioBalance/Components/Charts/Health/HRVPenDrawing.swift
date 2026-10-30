import SwiftUI

nonisolated struct HRVPenStroke: Shape {
    let points: [CGPoint]
    var progress: Double
    let fillsArea: Bool
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let visible = HRVPenGeometry.revealedPoints(points, progress: progress)
        guard let first = visible.first, let last = visible.last else { return Path() }
        var path = Path()
        path.move(to: first)
        for point in visible.dropFirst() { path.addLine(to: point) }
        if fillsArea {
            path.addLine(to: CGPoint(x: last.x, y: rect.height))
            path.addLine(to: CGPoint(x: first.x, y: rect.height))
            path.closeSubpath()
        }
        return path
    }
}

struct HRVPenEndpoint: View {
    let tint: Color
    let breathes: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !breathes)) { context in
            let wave = breathes ? (sin(context.date.timeIntervalSinceReferenceDate * .pi / 1.4) + 1) / 2 : 0
            ZStack {
                Circle().fill(tint.opacity(0.10 + wave * 0.09))
                    .frame(width: 16 + wave * 7, height: 16 + wave * 7)
                Circle().fill(Theme.Colors.surface).frame(width: 10, height: 10)
                Circle().fill(tint).frame(width: 6, height: 6)
            }
            .frame(width: 24, height: 24)
        }
        .allowsHitTesting(false)
    }
}

struct HRVPenTooltip: View {
    let sample: TimeSeriesPointDouble
    let tint: Color
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(Date(timeIntervalSince1970: TimeInterval(sample.timestamp)), format: .dateTime.month().day().hour().minute())
                .font(.appSystem(size: 9, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .transaction { $0.animation = nil }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(sample.value.rounded()))")
                    .contentTransition(reduceMotion ? .identity : .numericText(value: sample.value))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: sample.value)
                    .monospacedDigit()
                Text("ms")
            }
            .font(.appSystem(size: 13, weight: .bold))
            .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.18), lineWidth: 0.5))
        .shadow(color: tint.opacity(0.10), radius: 5, y: 2)
    }
}
