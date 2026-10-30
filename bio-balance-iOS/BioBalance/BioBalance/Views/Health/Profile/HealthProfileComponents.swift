/// HealthProfileComponents 作为 HealthProfileView 的共享扩展，负责提供画片级 UI 组件。
/// 负责提供分区标题、可展开维度行等健康画像页专用视图。

import SwiftUI

extension HealthProfileView {

    func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 19, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(subtitle)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    func expandableDimensionRow(_ dimension: HealthProfileDimension) -> some View {
        let tint = trendTint(dimension.trend)
        let isExpanded = expandedDimensionIDs.contains(dimension.id)

        VStack(spacing: 0) {
            Button {
                if isExpanded {
                    expandedDimensionIDs.remove(dimension.id)
                } else {
                    expandedDimensionIDs.insert(dimension.id)
                }
            } label: {
                HStack(spacing: 12) {
                    iconBubble(symbol: dimension.kind.symbol, tint: tint, size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dimension.title)
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(dimension.statusText)
                            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(tint)
                    }
                    Spacer(minLength: 8)
                    Text(dimension.score.map { String($0) } ?? "--")
                        .font(.appSystem(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(tint)
                    Image(systemName: "chevron.down")
                        .font(.appSystem(size: 12, weight: .black))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(dimension.title)，\(dimension.statusText)，分数 \(dimension.score.map(String.init) ?? "未知")")
            .accessibilityAddTraits(isExpanded ? [.isSelected] : [])

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let score = dimension.score {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.Colors.secondaryBackground)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: trendGradient(dimension.trend),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(10, proxy.size.width * CGFloat(min(max(Double(score) / 100, 0), 1))))
                            }
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                    }

                    Text(dimension.detail)
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 14)
            }
        }
    }

    func profileRow(symbol: String, title: String, detail: String, badge: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            iconBubble(symbol: symbol, tint: tint, size: 38)
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        BBStatusBadge(title: badge, tint: tint)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        BBStatusBadge(title: badge, tint: tint)
                    }
                }
                Text(detail)
                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }

    func actionRecommendationRow(
        _ action: HealthProfileActionRecommendation,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            iconBubble(symbol: symbol, tint: tint, size: 42)

            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(action.title)
                            .font(.appSystem(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        BBStatusBadge(title: action.priority.title, tint: tint)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(action.title)
                            .font(.appSystem(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        BBStatusBadge(title: action.priority.title, tint: tint)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("建议行动")
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(tint)
                    Text(action.detail)
                        .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "344254"))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("判断依据")
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "758092"))
                    Text(action.reason)
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }

    func inlineEmptyState(_ text: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "circle.dotted")
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
        .foregroundColor(Theme.Colors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    func evidenceRow(_ item: HealthProfileDataCompleteness) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(completenessTint(item.state).opacity(0.14))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: completenessSymbol(item.state))
                        .font(.appSystem(size: 12, weight: .black))
                        .foregroundColor(completenessTint(item.state))
                }

            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.appSystem(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer(minLength: 0)
                        BBStatusBadge(
                            title: item.state.title,
                            systemImage: completenessSymbol(item.state),
                            tint: completenessTint(item.state)
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.appSystem(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        BBStatusBadge(
                            title: item.state.title,
                            systemImage: completenessSymbol(item.state),
                            tint: completenessTint(item.state)
                        )
                    }
                }

                Text(item.detail)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 13)
    }
}


struct ProfileSectionCard: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(18)
            .bbTintedSurface(
                tint: tint,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                tintStrength: 0.025
            )
    }
}
