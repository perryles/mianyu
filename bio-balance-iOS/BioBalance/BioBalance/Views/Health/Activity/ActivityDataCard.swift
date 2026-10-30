/// ActivityDataCard 由活动概览页调用，作为「活动数据」内容卡片。
/// 负责展示步数、活动能量、锻炼时长与站立小时四项核心指标。

import SwiftUI

/// Activity数据卡片组件 作为活动模块里的内容展示卡片。
/// 负责展示运动概览、活动详情与趋势变化。
struct ActivityDataCard: View {
    let steps: Int
    let activeEnergy: Int
    let exerciseTime: Int
    let standHours: Int
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                MetricItem(title: "步数", value: "\(steps)", unit: "步", icon: "figure.walk", color: .green)
                MetricItem(title: "活动能量", value: "\(activeEnergy)", unit: "千卡", icon: "flame.fill", color: .orange)
            }
            HStack(spacing: 16) {
                MetricItem(title: "锻炼时长", value: "\(exerciseTime)", unit: "分钟", icon: "figure.run", color: .blue)
                MetricItem(title: "站立", value: "\(standHours)", unit: "小时", icon: "figure.stand", color: .purple)
            }
        }
        .padding()
        .background(Theme.Colors.background)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

private struct MetricItem: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.appSystem(size: 14))
                Text(title)
                    .font(.appSystem(size: 14, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.appSystem(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .contentTransition(reduceMotion ? MotionTokens.numberTransitionReduced : MotionTokens.numberTransition)
                    .animation(reduceMotion ? MotionTokens.numberAnimationReduced : MotionTokens.numberAnimation, value: value)
                Text(unit)
                    .font(.appSystem(size: 12, weight: .medium))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    ActivityDataCard(steps: 6542, activeEnergy: 450, exerciseTime: 32, standHours: 8)
        .padding()
}