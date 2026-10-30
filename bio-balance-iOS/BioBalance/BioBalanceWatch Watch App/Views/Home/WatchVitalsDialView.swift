import SwiftUI

/// Watch 首页使用的紧凑型健康仪表盘。
/// 动效由时间线日期驱动，无需维持长期运行的计时器。
struct WatchVitalsDialView: View {
    let snapshot: WatchRealtimeHealth

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stateColor: Color {
        if snapshot.hrv >= 48 {
            return Color(red: 0.48, green: 0.92, blue: 0.62)
        }
        if snapshot.hrv >= 25 {
            return Color(red: 0.42, green: 0.82, blue: 0.96)
        }
        if snapshot.hrv > 0 {
            return Color(red: 1.0, green: 0.68, blue: 0.38)
        }
        if snapshot.stressState.map({ ["highStress", "overloaded"].contains($0) }) == true {
            return Color(red: 1.0, green: 0.38, blue: 0.42)
        }
        return Color(red: 0.55, green: 0.70, blue: 0.96)
    }

    private var pulseStrength: CGFloat {
        guard snapshot.bpm > 0 else { return 1 }
        return min(max(CGFloat(snapshot.bpm) / 100, 0.72), 1.18)
    }

    private var recoveryProgress: CGFloat {
        if snapshot.hrv > 0 {
            return min(max(CGFloat((snapshot.hrv - 10) / 50), 0.08), 0.92)
        }
        guard snapshot.stress_value > 0 else { return 0.12 }
        let inverseStress = 1 - (CGFloat(min(max(snapshot.stress_value, 0), 100)) / 100)
        return min(max(inverseStress, 0.08), 0.92)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { proxy in
                let diameter = min(proxy.size.width, proxy.size.height)
                let radius = diameter / 2
                let seconds = context.date.timeIntervalSinceReferenceDate
                let rotation = reduceMotion ? 0 : (seconds.truncatingRemainder(dividingBy: 60) / 60) * 360
                let pulse: CGFloat = reduceMotion || snapshot.bpm <= 0
                    ? 1
                    : 1 + (0.035 * CGFloat(sin(seconds * .pi * 2 / 2.8)))

                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.22))
                    Circle()
                        .stroke(stateColor.opacity(0.18), lineWidth: diameter * 0.08)
                    Circle()
                        .trim(from: 0.02, to: recoveryProgress)
                        .stroke(stateColor.opacity(0.95), style: StrokeStyle(lineWidth: diameter * 0.055, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .padding(diameter * 0.17)

                    ForEach(0..<24, id: \.self) { index in
                        Capsule()
                            .fill(Color.white.opacity(index.isMultiple(of: 3) ? 0.72 : 0.28))
                            .frame(width: index.isMultiple(of: 3) ? 2 : 1, height: index.isMultiple(of: 3) ? 7 : 4)
                            .offset(y: -radius * 0.40)
                            .rotationEffect(.degrees(Double(index) * 15))
                    }

                    Capsule()
                        .fill(stateColor)
                        .frame(width: 2, height: radius * 0.34)
                        .offset(y: -radius * 0.22)
                        .rotationEffect(.degrees(rotation))
                        .shadow(color: stateColor.opacity(0.8), radius: 3)

                    Circle()
                        .fill(stateColor.opacity(0.16))
                        .frame(width: diameter * 0.48, height: diameter * 0.48)
                        .scaleEffect(pulse * pulseStrength)

                    VStack(spacing: 1) {
                        Text(snapshot.bpm > 0 ? String(snapshot.bpm) : "--")
                            .font(.watchAppSystem(size: diameter * 0.22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.7)
                        Text("BPM")
                            .font(.watchAppSystem(size: diameter * 0.085, weight: .bold, design: .rounded))
                            .foregroundStyle(stateColor.opacity(0.9))
                            .tracking(0.6)
                    }
                }
                .frame(width: diameter, height: diameter)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("实时心率")
                .accessibilityValue(snapshot.bpm > 0 ? "\(snapshot.bpm) 次每分钟" : "等待心率数据")
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
