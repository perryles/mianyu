/// BB Metric Row 定义可复用界面组件，负责沉淀通用样式、交互结构或设计系统能力。
import SwiftUI

// MARK: - Trend Direction

/// 指标趋势方向
enum BBMetricTrend: Equatable {
    case up
    case down
    case stable
    case none

    var systemImage: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        case .none: return ""
        }
    }

    var color: Color {
        switch self {
        case .up: return Color(hex: "34C759")
        case .down: return Color(hex: "D70015")
        case .stable: return Theme.Colors.textTertiary
        case .none: return .clear
        }
    }
}

// MARK: - BB Metric Row

/// BB指标行组件 作为设计系统里的列表行组件。
/// 负责通用组件与设计系统能力。
///
/// 使用示例：
/// ```swift
/// BBMetricRow(title: "静息心率", value: "62", unit: "bpm")
/// BBMetricRow(title: "步数", value: "8,320", unit: "步", systemImage: "figure.walk", trend: .up)
/// BBMetricRow(title: "睡眠时长", value: "7.5", unit: "小时", tint: .purple, showsDivider: true)
/// ```
struct BBMetricRow: View {
    let title: String
    let value: String
    var unit: String? = nil
    var valueFont: Font = .system(.headline, design: .monospaced).bold()
    var showsDivider: Bool = false
    var systemImage: String? = nil
    var tint: Color? = nil
    var trend: BBMetricTrend = .none
    var secondaryValue: String? = nil
    var onTap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.compact) {
                // 前置图标
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.appSystem(size: 14, weight: .semibold))
                        .foregroundColor(tint ?? Theme.Colors.mintGreen)
                        .frame(width: 28, height: 28)
                        .background((tint ?? Theme.Colors.mintGreen).opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }

                // 标题与辅助值
                VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
                    Text(title)
                        .font(Theme.Typography.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)

                    if let secondaryValue {
                        Text(secondaryValue)
                            .font(Theme.Typography.supporting)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }

                Spacer()

                // 数值、单位与趋势
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.hairline) {
                    Text(value)
                        .font(valueFont)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .monospacedDigit()

                    if let unit {
                        Text(unit)
                            .font(Theme.Typography.label)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }

                    if trend != .none {
                        Image(systemName: trend.systemImage)
                            .font(.appSystem(size: 11, weight: .bold))
                            .foregroundColor(trend.color)
                    }
                }

                // 跳转指示
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 12, weight: .semibold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            .padding(.vertical, onTap != nil ? Theme.Spacing.small : 0)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap?()
            }

            if showsDivider {
                Divider()
                    .padding(.top, Theme.Spacing.small)
                    .padding(.leading, systemImage != nil ? 38 : 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)\(unit.map { " \($0)" } ?? "")")
    }
}

/// 指标组的数据项
struct BBMetricGroupItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var unit: String? = nil
    var systemImage: String? = nil
    var tint: Color? = nil
    var trend: BBMetricTrend = .none
}

// MARK: - 预览

#Preview("Metric Rows") {
    VStack(spacing: 20) {
        BBMetricRow(title: "静息心率", value: "62", unit: "bpm", showsDivider: true, systemImage: "heart.fill", tint: .red, trend: .down)
        BBMetricRow(title: "步数", value: "8,320", unit: "步", showsDivider: true, systemImage: "figure.walk", trend: .up)
        BBMetricRow(title: "睡眠时长", value: "7.5", unit: "小时", systemImage: "bed.double.fill", tint: .purple, secondaryValue: "比昨天多 30 分钟")
        BBMetricRow(title: "HRV", value: "45", unit: "ms", onTap: {})
    }
    .padding()
}
