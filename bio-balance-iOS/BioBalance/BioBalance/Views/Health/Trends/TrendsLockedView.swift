/// TrendsLockedView 由 TrendsRootView 在无 Pro 权限时调用，作为「趋势锁定」引导页。
/// 负责展示 Pro 专属趋势功能列表与解锁转化入口。

import SwiftUI

/// TrendsLocked视图 由上级页面或路由调用，作为趋势模块里的界面或内容组件。
/// 负责从不同维度汇总长期数据变化并帮助用户理解趋势。
struct TrendsLockedView: View {
    let onUnlock: () -> Void
    @State private var didAppear = false
    
    private let features: [LockedFeature] = [
        LockedFeature(icon: "chart.bar.xaxis", title: "综合压力趋势", subtitle: "查看每日、每周、每月的压力变化趋势", color: Theme.Colors.mintGreen),
        LockedFeature(icon: "clock.arrow.circlepath", title: "压力时段统计", subtitle: "发现您最容易产生压力的特定时间段", color: Color(hex: "5E5CE6")),
        LockedFeature(icon: "square.grid.2x2", title: "压力水平分布", subtitle: "洞察低/中/高压力的比例与变化", color: Color(hex: "FF9F0A")),
        LockedFeature(icon: "heart.text.square", title: "HRV 与静息心率趋势", subtitle: "用关键生理指标理解压力变化", color: Color(hex: "FF2D55")),
        LockedFeature(icon: "infinity", title: "无限制历史数据回看", subtitle: "随时查看更长周期的趋势记录", color: Theme.Colors.accentBlue)
    ]
    
    var body: some View {
        ZStack {
            background
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                        .modifier(StaggeredAppear(isActive: didAppear, index: 0))
                    hero
                        .modifier(StaggeredAppear(isActive: didAppear, index: 1))
                    preview
                        .modifier(StaggeredAppear(isActive: didAppear, index: 2))
                    comparisonSection
                        .modifier(StaggeredAppear(isActive: didAppear, index: 3))
                    socialProof
                        .modifier(StaggeredAppear(isActive: didAppear, index: 4))
                    detailSection
                        .modifier(StaggeredAppear(isActive: didAppear, index: 5))
                    featureList
                        .modifier(StaggeredAppear(isActive: didAppear, index: 6))
                    faqSection
                        .modifier(StaggeredAppear(isActive: didAppear, index: 7))
                    guaranteeSection
                        .modifier(StaggeredAppear(isActive: didAppear, index: 8))
                }
                .padding(.horizontal, Theme.Layout.padding)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            if didAppear { return }
            didAppear = true
        }
    }
    
    private var background: some View {
        ZStack {
            Theme.Colors.secondaryBackground
            
            VStack {
                HStack {
                    Circle()
                        .fill(Theme.Colors.mintGreen.opacity(0.15))
                        .frame(width: 180, height: 180)
                        .blur(radius: 28)
                        .offset(x: -58, y: -52)
                    Spacer()
                    Circle()
                        .fill(Color(hex: "FFF4D6").opacity(0.85))
                        .frame(width: 150, height: 150)
                        .blur(radius: 32)
                        .offset(x: 42, y: -24)
                }
                Spacer()
            }
        }
        .ignoresSafeArea()
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            Text("趋势")
                .font(.appSystem(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
    
    private var hero: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [
                    Theme.Colors.mintGreen.opacity(0.16),
                    Color(hex: "EAF8F1"),
                    Color.white.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ProTrendMascot()
                .frame(width: 146, height: 112)
                .offset(x: 12, y: 16)

            VStack(alignment: .leading, spacing: 12) {
                Text("解锁专业版\n看懂长期趋势")
                    .font(.appSystem(size: 30, weight: .bold, design: .serif))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(2)

                Text("压力、HRV、静息心率和声音暴露都会整理成可回看的趋势卡片。")
                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onUnlock) {
                    Text("免费试用")
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Theme.Colors.mintGreen.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.plain)

            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 110)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.75), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 18, x: 0, y: 10)
    }
    
    private var preview: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.035), radius: 14, x: 0, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.Colors.mintGreen.opacity(0.10),
                                    Theme.Colors.background.opacity(0.0),
                                    Theme.Colors.background.opacity(0.0),
                                    Theme.Colors.background
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.Colors.mintGreen)
                        .frame(width: 8, height: 8)
                    Text("本月压力负荷")
                        .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                chartPreview
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 24)
                
                Divider()
                    .padding(.horizontal, 24)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("趋势概览")
                            .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        
                        Text("解锁后可查看完整的交互式图表与多维数据分析。")
                            .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
        )
    }
    
    private var chartPreview: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(0..<7, id: \.self) { idx in
                let heights: [CGFloat] = [40, 70, 50, 90, 65, 45, 80]
                let isPeak = idx == 3
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isPeak ? Theme.Colors.mintGreen : Theme.Colors.mintGreen.opacity(0.25))
                        .frame(height: heights[idx])
                    
                    Text(["一", "二", "三", "四", "五", "六", "日"][idx])
                        .font(.appSystem(size: 12, weight: .medium))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .overlay(
            Rectangle()
                .fill(LinearGradient(colors: [Theme.Colors.background.opacity(0.1), Theme.Colors.background.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                .padding(.top, -20)
        )
    }
    
    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("免费版 vs 专业版")
                .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            
            HStack(alignment: .top, spacing: 12) {
                ComparisonCard(
                    title: "免费版",
                    badge: nil,
                    items: [
                        ComparisonItem(text: "仅查看当日概览", isIncluded: true),
                        ComparisonItem(text: "有限历史回顾", isIncluded: false),
                        ComparisonItem(text: "趋势维度较少", isIncluded: false),
                        ComparisonItem(text: "无深度洞察与建议", isIncluded: false)
                    ],
                    accent: Theme.Colors.textTertiary
                )
                
                ComparisonCard(
                    title: "专业版",
                    badge: "推荐",
                    items: [
                        ComparisonItem(text: "每日/每周/每月趋势", isIncluded: true),
                        ComparisonItem(text: "压力分布与时段统计", isIncluded: true),
                        ComparisonItem(text: "HRV 与静息心率对比", isIncluded: true),
                        ComparisonItem(text: "无限历史回顾", isIncluded: true)
                    ],
                    accent: Theme.Colors.mintGreen
                )
            }
        }
    }
    
    private var socialProof: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .padding(.bottom, 8)
            
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.appSystem(size: 16))
                            .foregroundColor(Color(hex: "FF9F0A"))
                    }
                }
                Text("4.9/5 评分")
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            
            Text("“终于看清了周末的睡眠不规律是如何影响周一的压力水平的。它帮助我重新找回了生活的掌控感。”")
                .font(.appSystem(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineSpacing(6)
            
            Text("— 超过 50,000 名用户正在通过趋势分析改善生活质量")
                .font(.appSystem(size: 14, weight: .regular))
                .foregroundColor(Theme.Colors.textSecondary)
            
            Divider()
                .padding(.top, 16)
        }
    }
    
    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("更深度的健康视角")
                .font(.appSystem(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            
            VStack(alignment: .leading, spacing: 36) {
                DetailRow(number: "01", title: "AI 智能洞察", description: "不仅仅是数据堆砌。我们的引擎会交叉分析您的睡眠、运动和压力，发现潜藏的规律。")
                DetailRow(number: "02", title: "无限历史回顾", description: "打破时间限制。随时回顾上个月甚至去年的数据，见证您的长期改变。")
                DetailRow(number: "03", title: "专属周报与建议", description: "每周为您生成健康总结，并提供切实可行的调节方案，让改变自然发生。")
            }
        }
    }
    
    private var featureList: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("核心特权一览")
                .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            
            VStack(spacing: 12) {
                ForEach(features) { feature in
                    Button {
                        onUnlock()
                    } label: {
                        LockedFeatureRow(feature: feature)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("常见问题")
                .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            
            VStack(spacing: 12) {
                FAQRow(
                    title: "试用期间会收费吗？",
                    detail: "不会。试用期结束前不会收取任何费用，您也可以在系统订阅设置中随时取消。"
                )
                
                FAQRow(
                    title: "数据安全吗？",
                    detail: "趋势分析仅用于为您提供洞察与可视化展示。我们尽量减少不必要的数据展示与暴露，确保页面对比度与可读性。"
                )
                
                FAQRow(
                    title: "为什么趋势对我有帮助？",
                    detail: "短期波动往往看不出问题，但长期趋势可以帮助您发现：哪类睡眠/运动习惯，会在几天后影响压力与恢复。"
                )
            }
        }
    }
    
    private var guaranteeSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.appSystem(size: 28))
                .foregroundColor(Theme.Colors.mintGreen)
            Text("随时取消，无隐性消费")
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text("试用期结束前不会收取任何费用")
                .font(.appSystem(size: 14, weight: .medium))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.Colors.background.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
}

private struct StaggeredAppear: ViewModifier {
    let isActive: Bool
    let index: Int
    
    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 18)
            .animation(.spring(response: 0.62, dampingFraction: 0.86).delay(0.06 * Double(index)), value: isActive)
    }
}

private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.86), value: configuration.isPressed)
    }
}

private struct ComparisonItem: Identifiable {
    let id = UUID()
    let text: String
    let isIncluded: Bool
}

private struct ComparisonCard: View {
    let title: String
    let badge: String?
    let items: [ComparisonItem]
    let accent: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                
                if let badge = badge {
                    Text(badge)
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accent)
                        .clipShape(Capsule())
                }
                
                Spacer(minLength: 0)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.appSystem(size: 15, weight: .semibold))
                            .foregroundColor(item.isIncluded ? accent : Theme.Colors.textTertiary)
                            .padding(.top, 1)
                        
                        Text(item.text)
                            .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(item.isIncluded ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.Colors.background.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

private struct FAQRow: View {
    let title: String
    let detail: String
    
    var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detail)
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
    
    var header: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var body: some View {
        DisclosureGroup {
            content
        } label: {
            header
        }
        .tint(Theme.Colors.textSecondary)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.Colors.background.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

private struct DetailRow: View {
    let number: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Text(number)
                .font(.appSystem(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.Colors.mintGreen)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text(description)
                    .font(.appSystem(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LockedFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
}

private struct ProTrendMascot: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: "BFDCC9").opacity(0.5))
                .frame(width: 120, height: 76)
                .rotationEffect(.degrees(-8))
                .offset(x: 8, y: 18)

            Circle()
                .fill(Theme.Colors.mintGreen.opacity(0.58))
                .frame(width: 104, height: 104)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.white.opacity(0.24))
                        .frame(width: 30, height: 30)
                        .offset(x: -12, y: 16)
                }

            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.black.opacity(0.78))
                    .frame(width: 22, height: 10)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.black.opacity(0.78))
                    .frame(width: 22, height: 10)
            }
            .rotationEffect(.degrees(-8))
            .offset(x: -10, y: -14)

            Circle()
                .stroke(Theme.Colors.mintGreen.opacity(0.55), lineWidth: 4)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.appSystem(size: 13, weight: .bold))
                        .foregroundColor(Theme.Colors.mintGreen)
                )
                .background(Theme.Colors.surface.opacity(0.62), in: Circle())
                .offset(x: 34, y: 20)
        }
    }
}

private struct LockedFeatureRow: View {
    let feature: LockedFeature
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: feature.icon)
                .font(.appSystem(size: 18, weight: .semibold))
                .foregroundColor(feature.color)
                .frame(width: 40, height: 40)
                .background(feature.color.opacity(0.12))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.appSystem(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text(feature.subtitle)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            
            Spacer(minLength: 0)
            
            Image(systemName: Theme.Icons.chevronRight)
                .font(.appSystem(size: 14, weight: .semibold))
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.top, 13)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(Theme.Colors.background.opacity(0.8))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    TrendsLockedView(onUnlock: {})
}
