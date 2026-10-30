/// ModernReportLayout 定义新版健康报告的沉浸式首屏与轻量数据面板。
/// 统一“小标签 → 标题 → 巨型核心值 → 上下文 → 状态徽章”的阅读顺序，
/// 并让后续指标继续使用大留白、低描边和高圆角的分组结构。

import SwiftUI

struct ModernReportCaption: Identifiable, Hashable {
    let id: String
    let symbol: String
    let text: String

    init(id: String? = nil, symbol: String, text: String) {
        self.id = id ?? symbol + text
        self.symbol = symbol
        self.text = text
    }
}

struct ModernReportBadge: Hashable {
    let symbol: String
    let text: String
    let tint: Color

    init(symbol: String, text: String, tint: Color) {
        self.symbol = symbol
        self.text = text
        self.tint = tint
    }
}

struct ModernSignalHeroPill: Identifiable, Hashable {
    let symbol: String
    let text: String
    var id: String { symbol + text }
}

/// 四个身体信号 Bottom Sheet 共用的沉浸式首屏，布局对应 V23 参考稿。
struct ModernSignalSheetHero: View {
    let eyebrow: String
    let title: String
    let value: String
    let unit: String
    let state: String
    let description: String
    let progress: Double
    let tint: Color
    let symbol: String
    let pills: [ModernSignalHeroPill]
    let contentTopPadding: CGFloat
    let onClose: () -> Void

    init(
        eyebrow: String,
        title: String,
        value: String,
        unit: String,
        state: String,
        description: String,
        progress: Double,
        tint: Color,
        symbol: String,
        pills: [ModernSignalHeroPill],
        contentTopPadding: CGFloat = 18,
        onClose: @escaping () -> Void
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.value = value
        self.unit = unit
        self.state = state
        self.description = description
        self.progress = progress
        self.tint = tint
        self.symbol = symbol
        self.pills = pills
        self.contentTopPadding = contentTopPadding
        self.onClose = onClose
    }

    @Environment(\.colorScheme) private var colorScheme

    private var foreground: Color {
        colorScheme == .dark ? .white : Theme.Colors.textPrimary
    }

    private var secondaryForeground: Color {
        colorScheme == .dark ? .white.opacity(0.74) : Theme.Colors.textSecondary
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            heroBackground

            VStack(alignment: .leading, spacing: 16) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: 17, weight: .black))
                        .foregroundStyle(foreground)
                        .frame(width: 44, height: 44)
                        .background(controlFill, in: Circle())
                        .overlay { Circle().strokeBorder(controlBorder, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: eyebrow)
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(secondaryForeground)
                    Text(verbatim: title)
                        .font(.appSystem(size: 29, weight: .black, design: .rounded))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(verbatim: value)
                            .font(.appSystem(size: 76, weight: .black, design: .rounded))
                            .foregroundStyle(foreground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .allowsTightening(true)

                        if !unit.isEmpty {
                            Text(verbatim: unit)
                                .font(.appSystem(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(secondaryForeground)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }

                    Label(state, systemImage: "circle.fill")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(foreground)
                        .labelStyle(CompactSignalStateLabelStyle())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(controlFill, in: Capsule())
                }

                Text(verbatim: description)
                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryForeground)
                    .lineSpacing(4)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 0) {
                    ForEach(pills.prefix(3)) { pill in
                        VStack(alignment: .leading, spacing: 7) {
                            Image(systemName: pill.symbol)
                                .font(.appSystem(size: 14, weight: .bold))
                                .foregroundStyle(tint)

                            Text(verbatim: pill.text)
                                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(foreground)
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                        }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 13)

                        if pill.id != pills.prefix(3).last?.id {
                            Rectangle()
                                .fill(summaryDivider)
                                .frame(width: 1, height: 38)
                        }
                    }
                }
                .background(summaryFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .padding(.horizontal, Theme.Layout.padding)
            .padding(.top, contentTopPadding)
            .padding(.bottom, 24)

            Image(systemName: symbol)
                .font(.appSystem(size: 116, weight: .black))
                .foregroundStyle(foreground.opacity(colorScheme == .dark ? 0.07 : 0.06))
                .offset(x: 18, y: 82)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 34,
                bottomTrailingRadius: 34,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .padding(.horizontal, -Theme.Layout.padding)
        .accessibilityElement(children: .contain)
    }

    private var controlFill: Color {
        colorScheme == .dark ? .white.opacity(0.11) : .white.opacity(0.58)
    }

    private var controlBorder: Color {
        colorScheme == .dark ? .white.opacity(0.13) : .white.opacity(0.72)
    }

    private var summaryFill: Color {
        colorScheme == .dark ? .black.opacity(0.16) : .white.opacity(0.54)
    }

    private var summaryDivider: Color {
        colorScheme == .dark ? .white.opacity(0.12) : foreground.opacity(0.10)
    }

    private var heroBackground: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [tint.opacity(0.58), tint.opacity(0.34), Color.black.opacity(0.92)]
                    : [tint.opacity(0.30), tint.opacity(0.17), tint.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(colorScheme == .dark ? 0.06 : 0.32))
                .frame(width: 260, height: 260)
                .blur(radius: 3)
                .offset(x: 112, y: -108)
        }
    }
}

private struct CompactSignalStateLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.appSystem(size: 6, weight: .bold))
            configuration.title
        }
    }
}

/// Hero 有全页报告与 Today 摘要卡两种量级，避免首页直接复用详情页的巨大字号。
enum ModernReportHeroScale {
    case full
    case compact

    var contentSpacing: CGFloat { self == .full ? 14 : 10 }
    var padding: CGFloat { self == .full ? 24 : 16 }
    var cornerRadius: CGFloat { self == .full ? 34 : 24 }
    var eyebrowSize: CGFloat { self == .full ? 12 : 10 }
    var titleSize: CGFloat { self == .full ? 26 : 18 }
    var valueSize: CGFloat { self == .full ? 78 : 42 }
    var unitSize: CGFloat { self == .full ? 24 : 13 }
    var ghostSize: CGFloat { self == .full ? 88 : 52 }
    var captionSize: CGFloat { self == .full ? 12 : 10 }
    var badgeSize: CGFloat { self == .full ? 12 : 11 }
    var iconSize: CGFloat { self == .full ? 24 : 16 }
    var iconFrame: CGFloat { self == .full ? 48 : 36 }
}

struct ModernReportHero: View {
    let eyebrow: String
    let title: String
    let value: String
    let unit: String
    var ghostUnit: String = ""
    let captions: [ModernReportCaption]
    let badge: ModernReportBadge?
    let accent: Color
    let symbol: String
    var scale: ModernReportHeroScale = .full

    @Environment(\.colorScheme) private var colorScheme

    private var foreground: Color {
        colorScheme == .dark ? .white : Theme.Colors.textPrimary
    }

    private var mutedForeground: Color {
        colorScheme == .dark ? .white.opacity(0.72) : Theme.Colors.textSecondary
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            background

            VStack(alignment: .leading, spacing: scale.contentSpacing) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: eyebrow)
                        .font(.appSystem(size: scale.eyebrowSize, weight: .semibold, design: .rounded))
                        .foregroundColor(mutedForeground)

                    Text(verbatim: title)
                        .font(.appSystem(size: scale.titleSize, weight: .heavy, design: .rounded))
                        .foregroundColor(foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ZStack(alignment: .leading) {
                    Text(verbatim: ghostUnit.isEmpty ? unit : ghostUnit)
                        .font(.appSystem(size: scale.ghostSize, weight: .black, design: .rounded))
                        .foregroundColor(foreground.opacity(colorScheme == .dark ? 0.13 : 0.08))
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.22)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(x: scale == .full ? 82 : 46, y: scale == .full ? 6 : 3)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)

                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text(verbatim: value)
                            .font(.appSystem(size: scale.valueSize, weight: .black, design: .rounded))
                            .foregroundColor(foreground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.38)
                            .allowsTightening(true)

                        if !unit.isEmpty {
                            Text(verbatim: unit)
                                .font(.appSystem(size: scale.unitSize, weight: .black, design: .rounded))
                                .foregroundColor(foreground.opacity(0.24))
                                .textCase(.uppercase)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(captions) { caption in
                        Label {
                            Text(verbatim: caption.text)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: caption.symbol)
                                .font(.appSystem(size: scale.captionSize + 1, weight: .bold))
                        }
                        .font(.appSystem(size: scale.captionSize, weight: .semibold, design: .rounded))
                        .foregroundColor(mutedForeground)
                    }
                }

                if let badge {
                    HStack(spacing: 10) {
                        Image(systemName: badge.symbol)
                            .font(.appSystem(size: scale.badgeSize, weight: .black))
                            .foregroundColor(badge.tint)

                        Text(verbatim: badge.text)
                            .font(.appSystem(size: scale.badgeSize, weight: .bold, design: .rounded))
                            .foregroundColor(foreground)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                    }
                    .padding(.horizontal, scale == .full ? 14 : 12)
                    .padding(.vertical, scale == .full ? 11 : 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: scale == .full ? 20 : 16, style: .continuous)
                            .fill(colorScheme == .dark ? .white.opacity(0.10) : Theme.Colors.surface.opacity(0.74))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: scale == .full ? 20 : 16, style: .continuous)
                            .strokeBorder(
                                colorScheme == .dark ? .white.opacity(0.12) : Theme.Colors.surfaceBorder.opacity(0.6),
                                lineWidth: 1
                            )
                    }
                }
            }
            .padding(scale.padding)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: symbol)
                .font(.appSystem(size: scale.iconSize, weight: .black))
                .foregroundColor(foreground)
                .frame(width: scale.iconFrame, height: scale.iconFrame)
                .background(
                    Circle().fill(colorScheme == .dark ? .white.opacity(0.12) : Theme.Colors.surface.opacity(0.68))
                )
                .overlay {
                    Circle().strokeBorder(
                        colorScheme == .dark ? .white.opacity(0.12) : Theme.Colors.surfaceBorder.opacity(0.6),
                        lineWidth: 1
                    )
                }
                .padding(scale == .full ? 18 : 12)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: scale.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var background: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [accent.opacity(0.38), Color.black.opacity(0.94), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [.white.opacity(0.98), accent.opacity(0.15), accent.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            Circle()
                .fill((colorScheme == .dark ? Color.white : accent).opacity(colorScheme == .dark ? 0.05 : 0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 8)
                .offset(x: 120, y: -84)

            Circle()
                .stroke((colorScheme == .dark ? Color.white : accent).opacity(0.10), lineWidth: 18)
                .frame(width: 158, height: 158)
                .rotationEffect(.degrees(18))
                .offset(x: 84, y: 92)
        }
    }
}

struct ModernReportMetric: Identifiable, Hashable {
    let title: String
    let value: String
    let tint: Color
    var symbol: String? = nil
    var id: String { title }
}

struct ModernReportPickerOption<Value: Hashable> {
    let value: Value
    let title: String
}

struct ModernReportSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [ModernReportPickerOption<Value>]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(verbatim: option.title)
                        .font(.appSystem(size: 13, weight: selection == option.value ? .black : .semibold, design: .rounded))
                        .foregroundColor(selection == option.value ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Group {
                                if selection == option.value {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Theme.Colors.surface)
                                        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.Colors.secondarySurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.Colors.surfaceBorder.opacity(0.7), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

struct ModernReportDateStepper: View {
    let title: String
    let canMoveForward: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            stepperButton(symbol: "chevron.left", enabled: true, action: onPrevious)

            Text(verbatim: title)
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            stepperButton(symbol: "chevron.right", enabled: canMoveForward, action: onNext)
        }
        .accessibilityElement(children: .contain)
    }

    private func stepperButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.appSystem(size: 13, weight: .black))
                .foregroundColor(enabled ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                .frame(width: 36, height: 36)
                .background(Theme.Colors.surface.opacity(0.84), in: Circle())
                .overlay {
                    Circle().strokeBorder(Theme.Colors.surfaceBorder.opacity(0.7), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct ModernReportMetricsPanel: View {
    let title: String
    let metrics: [ModernReportMetric]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: "chart.bar.doc.horizontal.fill")
                .font(.appSystem(size: 17, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            if let symbol = metric.symbol {
                                Image(systemName: symbol)
                                    .font(.appSystem(size: 11, weight: .black))
                                    .foregroundColor(metric.tint)
                                    .frame(width: 24, height: 24)
                                    .background(metric.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else {
                                Circle()
                                    .fill(metric.tint)
                                    .frame(width: 7, height: 7)
                            }

                            Text(verbatim: metric.title)
                                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.74)
                        }

                        Text(verbatim: metric.value)
                            .font(.appSystem(size: 19, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.Colors.secondarySurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(18)
        .modernReportPanelSurface()
    }
}

/// 趋势图统一空态。内容直接落在绘图区，不再叠加第二张卡片或伪造柱状数据。
struct ModernReportChartEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.appSystem(size: 20, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.10), in: Circle())

            Text(verbatim: title)
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(verbatim: message)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}

struct ModernReportChartLoadingState: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(tint)
            Text(verbatim: title)
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
        .overlay {
            Capsule().strokeBorder(tint.opacity(0.14), lineWidth: 1)
        }
    }
}

extension View {
    /// 新版报告面板在 iOS 26+ 复用系统 Liquid Glass；旧系统退化为白卡与细描边。
    @ViewBuilder
    func modernReportPanelSurface() -> some View {
        if #available(iOS 26.0, *) {
            self.bbLiquidGlassSurface(
                tint: Theme.Colors.mintGreen,
                in: RoundedRectangle(cornerRadius: 26, style: .continuous),
                tintStrength: 0.06,
                shadow: false
            )
        } else {
            self
                .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Theme.Colors.surfaceBorder.opacity(0.8), lineWidth: 1)
                }
        }
    }

    /// 详情页趋势图的轻量绘图区。保留坐标可读性，同时用指标色提供很弱的空间层次。
    func modernReportChartPlotSurface(tint: Color, cornerRadius: CGFloat = 20) -> some View {
        self
            .background(
                LinearGradient(
                    colors: [
                        tint.opacity(0.075),
                        Theme.Colors.surface.opacity(0.96),
                        Theme.Colors.surface
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.12), lineWidth: 1)
            }
    }
}
