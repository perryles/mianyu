/// SleepRecordCard 由睡眠详情页调用，作为「睡眠记录」内容卡片。
/// 负责展示今日睡眠时长、评分、深睡/REM 占比、平均心率与呼吸率。

import SwiftUI

/// 睡眠记录卡片组件 作为睡眠模块里的内容展示卡片。
/// 负责展示睡眠记录、恢复分析以及睡眠与其他指标的关联。
struct SleepRecordCard: View {
    let deepSleepPercentage: Double
    let remSleepPercentage: Double
    let avgHeartRate: Int?
    let avgRespirationRate: Double?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("夜间恢复信号")
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("阶段比例与睡眠窗口内的身体信号")
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                MetricItem(
                    title: "深度睡眠",
                    value: String(format: "%.0f%%", deepSleepPercentage * 100),
                    icon: "moon.fill",
                    color: .indigo
                )
                MetricItem(
                    title: "REM睡眠",
                    value: String(format: "%.0f%%", remSleepPercentage * 100),
                    icon: "eye.fill",
                    color: .purple
                )
                if let hr = avgHeartRate {
                    MetricItem(
                        title: "平均心率",
                        value: "\(hr) bpm",
                        icon: "heart.fill",
                        color: .red
                    )
                }
                if let resp = avgRespirationRate {
                    MetricItem(
                        title: "平均呼吸",
                        value: String(format: String(localized: "%.1f 次/分"), resp),
                        icon: "wind",
                        color: .blue
                    )
                }
            }
        }
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        }
    }
}

private struct MetricItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.appSystem(size: 20))
                .foregroundColor(color)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appSystem(.caption, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                Text(value)
                    .font(.appSystem(.subheadline, design: .rounded).bold())
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            Spacer()
        }
    }
}
