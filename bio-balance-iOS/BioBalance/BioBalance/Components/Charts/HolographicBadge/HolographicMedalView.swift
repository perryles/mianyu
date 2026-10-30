/// 全息奖章绘制：用 Shape/Canvas 复刻「珐琅 + 金属边 + 视角联动光泽」的立体勋章质感。
/// 纯 SwiftUI 绘制，无图片资源。

import SwiftUI

// MARK: - 徽章页面配色

/// 全息徽章各页面统一走浅色画布，与「今日」页共用同一套底色与文字层级。
/// 不再使用任何深色/黑色铺底。
enum HolographicBadgePalette {
    /// 页面画布：与今日页 `TodayVisualTokens.canvas` 同源。
    static let canvas = Theme.Colors.pageBackground
    /// 画布顶部（略亮），用于详情页的极浅渐变。
    static let canvasTop = Color(hex: "F8FAFA")
    /// 卡片/胶囊底衬与描边。
    static let surface = Theme.Colors.surface
    static let surfaceStroke = Theme.Colors.surfaceBorder
    /// 金色强调文字：浅底上可读的深金（替代原先的低对比浅金）。
    static let goldText = Color(hex: "9A7420")
    /// 进度条底槽。
    static let track = Theme.Colors.secondaryBackground
}

// MARK: - 六边形

nonisolated struct HexagonShape: Shape {
    /// 顶点 FlatTop = true 时上下为平边（参考图中勋章形态）；false 为尖顶。
    var isFlatTop: Bool = true

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let angleOffset: CGFloat = isFlatTop ? .pi / 6 : 0
        var path = Path()
        for index in 0..<6 {
            let angle = angleOffset + CGFloat(index) * .pi / 3
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - 全息奖章视图

/// 立体珐琅勋章：六边形金属外框 + 珐琅内部 + 顶部年月标签 + 视角联动全息光泽。
/// `tilt` 由外部拖拽/滚动驱动（-1...1 归一化），reduceMotion 时光泽退化为静态。
struct HolographicMedalView: View {
    let theme: HolographicBadgeTheme
    let symbol: String
    /// 顶部标签文字（如「9月」）；nil 则不显示标签。
    var headerText: String? = nil
    var bodySize: CGSize = .zero
    var isLocked: Bool = false
    /// 视角参数（-1...1）。
    var tiltX: CGFloat = 0
    var tiltY: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack {
                medalBody(side: side)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func medalBody(side: CGFloat) -> some View {
        let metalLight = Color(hex: theme.metal.light)
        let metalDark = Color(hex: theme.metal.dark)
        let enamelColors = theme.enamel.map { Color(hex: $0) }
        let highlight = Color(hex: theme.highlight)
        let tilt = reduceMotion ? CGSize.zero : CGSize(width: tiltX, height: tiltY)

        ZStack {
            // 投影
            HexagonShape()
                .fill(Color.black.opacity(isLocked ? 0.08 : 0.22))
                .blur(radius: side * 0.06)
                .offset(y: side * 0.05)

            // 金属外框（厚边）
            HexagonShape()
                .fill(
                    LinearGradient(
                        colors: [metalLight, metalDark, metalLight],
                        startPoint: UnitPoint(x: 0.2 - tilt.width * 0.15, y: 0),
                        endPoint: UnitPoint(x: 0.8 - tilt.width * 0.15, y: 1)
                    )
                )
                .shadow(color: metalDark.opacity(0.55), radius: side * 0.015, x: 0, y: side * 0.012)

            // 内侧细环（亮线）
            HexagonShape()
                .stroke(metalLight.opacity(0.9), lineWidth: side * 0.018)
                .padding(side * 0.045)

            // 珐琅内部
            HexagonShape()
                .fill(
                    LinearGradient(
                        colors: enamelColors,
                        startPoint: UnitPoint(x: 0.3, y: 0),
                        endPoint: UnitPoint(x: 0.7, y: 1)
                    )
                )
                .padding(side * 0.085)

            // 珐琅格线（参考图中的分区感）
            HexagonShape()
                .stroke(Color.white.opacity(0.16), lineWidth: side * 0.012)
                .padding(side * 0.085)

            // 中央符号（带轻微视差）
            Image(systemName: symbol)
                .font(.appSystem(size: side * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.onAccent.opacity(isLocked ? 0.5 : 0.96))
                .shadow(color: .black.opacity(0.28), radius: side * 0.02, x: 0, y: side * 0.015)
                .offset(x: tilt.width * side * 0.03, y: tilt.height * side * 0.03)

            // 顶部年月标签
            if let headerText {
                headerCapsule(text: headerText, side: side, highlight: highlight, metalDark: metalDark)
            }

            // 全息光泽：对角高光随视角移动
            sheen(side: side, tilt: tilt)

            // 锁定态：整体淡化蒙版（浅色画布上用磨砂白，而非深色压暗）
            if isLocked {
                HexagonShape()
                    .fill(Color(white: 0.94).opacity(0.62))
                    .padding(-side * 0.005)
            }
        }
    }

    private func headerCapsule(text: String, side: CGFloat, highlight: Color, metalDark: Color) -> some View {
        let capsuleWidth = side * 0.5
        let capsuleHeight = side * 0.19
        return ZStack {
            // 标签底（弧形舱位）
            RoundedRectangle(cornerRadius: capsuleHeight / 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [highlight, metalDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: capsuleWidth, height: capsuleHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: capsuleHeight / 2, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: side * 0.008)
                )
                .shadow(color: .black.opacity(0.25), radius: side * 0.02, y: side * 0.012)

            Text(text)
                .font(.appSystem(size: side * 0.115, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: "2B3A66"))
                .frame(width: capsuleWidth, height: capsuleHeight)
        }
        .offset(y: -side * 0.315)
    }

    /// 视角联动全息光泽层。
    @ViewBuilder
    private func sheen(side: CGFloat, tilt: CGSize) -> some View {
        let center = UnitPoint(
            x: 0.5 + tilt.width * 0.35,
            y: 0.5 + tilt.height * 0.35
        )
        HexagonShape()
            .fill(
                AngularGradient(
                    colors: [
                        .white.opacity(0.0),
                        .cyan.opacity(0.22),
                        .white.opacity(0.0),
                        .pink.opacity(0.18),
                        .yellow.opacity(0.2),
                        .white.opacity(0.0)
                    ],
                    center: center,
                    angle: .degrees(Double(tilt.width) * 60)
                )
            )
            .padding(side * 0.02)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}

// MARK: - 舞台（详情页聚光 + 底座阴影）

/// 详情页的聚光舞台：浅色画布 + 顶部柔光锥 + 奖章悬浮投影。
struct HolographicStageView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            // 柔光锥：在浅色画布上以纯白叠加出「略亮一档」的光带，避免深色铺底
            ConeShape()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 420)
                .offset(y: -60)
                .allowsHitTesting(false)

            VStack {
                content
                // 底座投影（浅底上减弱，避免发黑）
                Ellipse()
                    .fill(Color.black.opacity(0.14))
                    .blur(radius: 14)
                    .frame(width: 170, height: 26)
                    .offset(y: 22)
            }
        }
    }
}

nonisolated struct ConeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 彩带粒子（庆祝/详情页飘落）

/// 彩带粒子模型与下落动画；reduceMotion 时静态展示少量粒子。
struct ConfettiPiece: Identifiable {
    let id: Int
    let x: CGFloat
    let delay: Double
    let size: CGFloat
    let color: Color
    let isStar: Bool
}

struct ConfettiOverlay: View {
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    private static let palette: [Color] = [
        Color(hex: "F6D488"), Color(hex: "9FD8B7"), Color(hex: "7FA8F5"),
        Color(hex: "E8A0A0"), Color(hex: "C9B6F2"), Color(hex: "FCE9B0")
    ]

    private var pieces: [ConfettiPiece] {
        let count = reduceMotion ? 10 : Int(26 * intensity)
        return (0..<count).map { index in
            ConfettiPiece(
                id: index,
                x: CGFloat((index * 137) % 100) / 100,
                delay: Double((index * 53) % 40) / 10,
                size: CGFloat(6 + (index * 7) % 8),
                color: Self.palette[index % Self.palette.count],
                isStar: index % 3 == 0
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ForEach(pieces) { piece in
                    Group {
                        if piece.isStar {
                            Image(systemName: "star.fill")
                                .font(.appSystem(size: piece.size, weight: .bold))
                                .foregroundStyle(piece.color)
                        } else {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(piece.color)
                                .frame(width: piece.size * 0.55, height: piece.size * 1.15)
                        }
                    }
                    .position(
                        x: piece.x * proxy.size.width + (animate ? 14 : -10),
                        y: animate ? proxy.size.height + 40 : -40
                    )
                    .opacity(animate ? 0.9 : 0)
                    .rotationEffect(.degrees(animate ? 240 : 40))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else {
                animate = true
                return
            }
            withAnimation(.easeIn(duration: 3.2).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}
