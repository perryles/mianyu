/// Ring Progress 定义可复用界面组件，负责沉淀通用样式、交互结构或设计系统能力。
import SwiftUI

// MARK: - 圆环尺寸预设

/// 环形进度尺寸预设
enum RingProgressSize: Equatable {
    case small
    case medium
    case large
    case custom(diameter: CGFloat, lineWidth: CGFloat)

    var diameter: CGFloat {
        switch self {
        case .small: return 52
        case .medium: return 80
        case .large: return 120
        case .custom(let diameter, _): return diameter
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .small: return 6
        case .medium: return 10
        case .large: return 14
        case .custom(_, let lineWidth): return lineWidth
        }
    }

    var valueFont: Font {
        switch self {
        case .small: return .appSystem(size: 13, weight: .bold, design: .rounded)
        case .medium: return .appSystem(.title2, design: .default).bold()
        case .large: return .appSystem(size: 32, weight: .heavy, design: .rounded)
        case .custom(let diameter, _):
            return .appSystem(size: max(11, diameter * 0.2), weight: .bold, design: .rounded)
        }
    }
}

// MARK: - 圆环进度视图

/// 环形进度视图 由上级页面或路由调用，作为通用组件层里的界面或内容组件。
/// 负责通用组件与设计系统能力。
///
/// 使用示例：
/// ```swift
/// RingProgressView(value: 7500, total: 10000, color: .green, label: "步数")
/// RingProgressView(value: 45, total: 60, color: .blue, label: "锻炼", size: .large, showsPercentage: true)
/// RingProgressView(value: 8, total: 12, color: .orange, label: "站立", size: .small, useGradient: true)
/// ```
struct RingProgressView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var value: Double
    var total: Double
    var color: Color
    var label: String
    var size: RingProgressSize = .medium
    var trackColor: Color = Color.gray.opacity(0.2)
    var showsPercentage: Bool = false
    var useGradient: Bool = false

    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(min(value / total, 1.0))
    }

    private var displayText: String {
        if showsPercentage {
            return "\(Int(progress * 100))%"
        }
        return "\(Int(value))"
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: size.lineWidth, lineCap: .round)
    }

    private var gradientColors: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [color, color.opacity(0.6), color]),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }

    var body: some View {
        VStack(spacing: size == .small ? 4 : 8) {
            ZStack {
                // 背景轨道圆环
                Circle()
                    .stroke(trackColor, lineWidth: size.lineWidth)

                // 进度圆环
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        useGradient ? AnyShapeStyle(gradientColors) : AnyShapeStyle(color),
                        style: strokeStyle
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? MotionTokens.ringDrawAnimationReduced : MotionTokens.ringDrawAnimation, value: value)

                // 中央数值
                Text(displayText)
                    .font(size.valueFont)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? MotionTokens.numberTransitionReduced : MotionTokens.numberTransition)
                    .animation(reduceMotion ? MotionTokens.numberAnimationReduced : MotionTokens.numberAnimation, value: value)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(width: size.diameter, height: size.diameter)

            if !label.isEmpty {
                Text(label)
                    .font(.appSystem(size: size == .small ? 10 : 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)")
        .accessibilityValue("\(Int(value)) / \(Int(total))")
    }
}

// MARK: - 多圆环进度视图

/// 多环进度视图，用于同时展示多个指标（类似 Apple 健身环）
struct MultiRingProgressView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Ring: Identifiable {
        let id = UUID()
        let value: Double
        let total: Double
        let color: Color
        let label: String
    }

    let rings: [Ring]
    var diameter: CGFloat = 100
    var lineWidth: CGFloat = 8
    var spacing: CGFloat = 3

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let ringDiameter = diameter - CGFloat(index) * (lineWidth + spacing) * 2
                let progress = ring.total > 0 ? min(ring.value / ring.total, 1.0) : 0

                Circle()
                    .stroke(ring.color.opacity(0.15), lineWidth: lineWidth)
                    .frame(width: ringDiameter, height: ringDiameter)

                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(ring.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: ringDiameter, height: ringDiameter)
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? MotionTokens.ringDrawAnimationReduced : MotionTokens.ringDrawAnimation, value: ring.value)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rings.map { "\($0.label) \(Int($0.value))/\(Int($0.total))" }.joined(separator: ", "))
    }
}

// MARK: - 预览

#Preview("Ring Sizes") {
    HStack(spacing: 24) {
        RingProgressView(value: 7500, total: 10000, color: Theme.Colors.mintGreen, label: "步数", size: .small)
        RingProgressView(value: 7500, total: 10000, color: Theme.Colors.mintGreen, label: "步数", size: .medium)
        RingProgressView(value: 7500, total: 10000, color: Theme.Colors.mintGreen, label: "步数", size: .large, showsPercentage: true, useGradient: true)
    }
    .padding()
}

#Preview("Multi Ring") {
    MultiRingProgressView(rings: [
        .init(value: 450, total: 600, color: .red, label: "活动"),
        .init(value: 28, total: 30, color: .green, label: "锻炼"),
        .init(value: 10, total: 12, color: .cyan, label: "站立")
    ])
    .padding()
}
