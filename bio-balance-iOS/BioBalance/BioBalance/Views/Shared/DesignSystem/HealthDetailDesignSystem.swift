/// HealthDetailDesignSystem 是跨 Today、Health、Goals 和 Profile 使用的健康详情视觉规范。
/// 负责定义页面边距、间距、圆角、边框色、次级表面色与页面命名常量。

import SwiftUI

/// 健康二级页面的统一视觉规范。
enum HealthDetailDesignSystem {
    static let pageHorizontalPadding: CGFloat = Theme.Layout.pagePadding
    static let pageTopPadding: CGFloat = Theme.Spacing.small
    static let pageBottomPadding: CGFloat = 96
    static let sectionSpacing: CGFloat = Theme.Layout.sectionSpacing
    static let surfaceRadius: CGFloat = 22
    static let navigationControlSize: CGFloat = 44

    static let surfaceBorder = Color.white.opacity(0.88)
    static let secondarySurface = Theme.Colors.secondarySurface
    static let secondaryText = Theme.Colors.textSecondary
}

/// 二级页标题以健康首页的入口文案为唯一来源。
/// PEN-2 P0-4：改用 LocalizedStringKey，经 navigationTitle 输出时走 String Catalog 本地化。
enum HealthPageName {
    static let report: LocalizedStringKey = "报告"
    static let fitness: LocalizedStringKey = "健身"
    static let dailyGoal: LocalizedStringKey = "每日行动"
    static let mentalRecovery: LocalizedStringKey = "心理恢复"
    static let bodyProfile: LocalizedStringKey = "身高体重"
    static let hydration: LocalizedStringKey = "补水饮品"
    static let environmentNoise: LocalizedStringKey = "环境噪音"
    static let sedentaryReminder: LocalizedStringKey = "久坐提醒"
    static let healthProfile: LocalizedStringKey = "健康档案"
    static let symptomObservation: LocalizedStringKey = "症状观察"
    static let restingHeartRate: LocalizedStringKey = "静息心率"
    static let hrv: LocalizedStringKey = "HRV"
    static let bodyAge: LocalizedStringKey = "身体年龄"
    static let medication: LocalizedStringKey = "用药补剂"
    static let femaleHealth: LocalizedStringKey = "周期健康"
    static let friends: LocalizedStringKey = "好友"
    static let pregnancy: LocalizedStringKey = "孕期记录"
    static let basalEnergy: LocalizedStringKey = "基础代谢"
    static let activeEnergy: LocalizedStringKey = "活动消耗"
    static let behaviorImpact: LocalizedStringKey = "行为影响"
    static let cardiopulmonaryFitness: LocalizedStringKey = "心肺耐力"
    static let walkingAsymmetry: LocalizedStringKey = "步态不对称"
}

struct HealthDetailPageBackground: View {
    private let topGlow: Color
    private let lowerGlow: Color
    private let topGlowOpacity: Double
    private let lowerGlowOpacity: Double

    init(
        topGlow: Color = Color(hex: "DCEFE8"),
        lowerGlow: Color = Color(hex: "E6EAF5"),
        topGlowOpacity: Double = 0.22,
        lowerGlowOpacity: Double = 0.16
    ) {
        self.topGlow = topGlow
        self.lowerGlow = lowerGlow
        self.topGlowOpacity = topGlowOpacity
        self.lowerGlowOpacity = lowerGlowOpacity
    }

    var body: some View {
        // 睡眠详情使用的晨雾底色，主题色只作为稀薄光晕出现在卡片后方。
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "F5F8F7"),
                    Color(hex: "F1F5F6"),
                    Color(hex: "F7F8F8")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [topGlow.opacity(topGlowOpacity), .clear],
                center: UnitPoint(x: 0.98, y: 0.08),
                startRadius: 0,
                endRadius: 390
            )

            RadialGradient(
                colors: [lowerGlow.opacity(lowerGlowOpacity), .clear],
                center: UnitPoint(x: 0.02, y: 0.54),
                startRadius: 0,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 与健康档案首屏一致的环形摘要，供高频健康功能页复用。
struct HealthReferenceScoreRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let valueText: String
    let title: LocalizedStringKey
    let progress: Double
    let accent: Color
    var animates = false

    @State private var renderedProgress = 0.0
    @State private var isCelebrating = false
    @State private var celebrationTrigger = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.14), lineWidth: 9)
            Circle()
                .trim(from: 0, to: renderedProgress)
                .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(
                    animates && !reduceMotion ? MotionTokens.ringDrawAnimation : nil,
                    value: renderedProgress
                )
            Circle()
                .stroke(accent.opacity(isCelebrating ? 0 : 0.32), lineWidth: 2)
                .scaleEffect(
                    isCelebrating
                        ? HealthFeatureMotionPolicy(reduceMotion: reduceMotion).celebrationScale
                        : 1
                )
                .opacity(isCelebrating && !reduceMotion ? 0 : 1)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.36),
                    value: isCelebrating
                )
                .allowsHitTesting(false)
            VStack(spacing: 1) {
                Text(valueText)
                    .font(Theme.Typography.pageTitle)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .font(Theme.Typography.label)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(animates ? .isButton : [])
        .accessibilityHint(animates ? String(localized: "轻点感受进度反馈") : "")
        .accessibilityAction {
            guard animates else { return }
            celebrate()
        }
        .contentShape(Circle())
        .onTapGesture {
            guard animates else { return }
            celebrate()
        }
        .sensoryFeedback(.selection, trigger: celebrationTrigger)
        .onAppear { updateRenderedProgress() }
        .onChange(of: progress) { _, _ in updateRenderedProgress() }
        .onChange(of: reduceMotion) { _, _ in updateRenderedProgress() }
    }

    private func updateRenderedProgress() {
        let target = min(max(progress, 0), 1)
        if animates && !reduceMotion {
            renderedProgress = target
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { renderedProgress = target }
        }
    }

    private func celebrate() {
        celebrationTrigger += 1
        guard !reduceMotion else { return }
        isCelebrating = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { isCelebrating = false }
        }
    }
}

/// 健康档案式 Hero 中的单行事实摘要。
struct HealthReferenceHeroFact: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String
    let accent: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: symbol)
                .font(.appSystem(size: 14, weight: .black))
                .foregroundColor(accent)
                .frame(width: 32, height: 32)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            Text(title)
                .font(Theme.Typography.captionBold)
                .foregroundColor(Color(hex: "5E6A7B"))
            Spacer(minLength: Theme.Spacing.compact)
            Text(value)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 三个高频记录页在首屏后展示的单一下一步，避免用户先阅读完整统计再决定行动。
struct HealthFeatureNextStep: Equatable {
    let eyebrow: String
    let title: String
    let detail: String
    let actionTitle: String
    let progress: Double
}

struct HealthFeatureMotionPolicy: Equatable {
    let reduceMotion: Bool

    var floatingOffset: CGFloat { reduceMotion ? 0 : 4 }
    var pressedScale: CGFloat { reduceMotion ? 1 : MotionTokens.cardPressScale }
    var animatesProgress: Bool { !reduceMotion }
    var celebrationScale: CGFloat { reduceMotion ? 1 : 1.22 }
}

enum HealthFeatureContentPlanner {
    static func dailyAction(completed: Int, total: Int, nextActionTitle: String?) -> HealthFeatureNextStep {
        let safeTotal = max(total, 1)
        let progress = min(max(Double(completed) / Double(safeTotal), 0), 1)
        if completed >= total, total > 0 {
            return HealthFeatureNextStep(
                eyebrow: String(localized: "今日已完成"),
                title: String(localized: "今天的基础行动已完成"),
                detail: String(localized: "保持当前节奏即可，也可以回看行动发生的时间，了解哪种安排最容易坚持。"),
                actionTitle: String(localized: "回看今日节奏"),
                progress: 1
            )
        }
        let next = nextActionTitle ?? String(localized: "一项轻行动")
        return HealthFeatureNextStep(
            eyebrow: String(localized: "今日优先"),
            title: String(localized: "先完成“\(next)”"),
            detail: String(localized: "先做一项低负担行动，不需要一次补齐全部目标。完成后会同步更新今日进度。"),
            actionTitle: String(localized: "开始记录"),
            progress: progress
        )
    }

    static func meal(recorded: Int, total: Int, nextMealTitle: String?) -> HealthFeatureNextStep {
        let safeTotal = max(total, 1)
        let progress = min(max(Double(recorded) / Double(safeTotal), 0), 1)
        if recorded >= total, total > 0 {
            return HealthFeatureNextStep(
                eyebrow: String(localized: "今日已完成"),
                title: String(localized: "今天的餐食已经记齐"),
                detail: String(localized: "可以继续核对识别结果或回看各餐构成，不需要为了完整而重复记录。"),
                actionTitle: String(localized: "继续记录餐食"),
                progress: 1
            )
        }
        let meal = nextMealTitle ?? String(localized: "下一餐")
        return HealthFeatureNextStep(
            eyebrow: String(localized: "下一餐待记录"),
            title: String(localized: "补记\(meal)"),
            detail: String(localized: "拍照后先核对食物与热量，再确认保存；也可以选择手动录入。"),
            actionTitle: String(localized: "拍照识别"),
            progress: progress
        )
    }

    static func medication(completed: Int, total: Int, overdue: Int, todaySymptomCount: Int) -> HealthFeatureNextStep {
        let safeTotal = max(total, 1)
        let progress = total > 0 ? min(max(Double(completed) / Double(safeTotal), 0), 1) : 0
        if overdue > 0 {
            return HealthFeatureNextStep(
                eyebrow: String(localized: "需要补记"),
                title: String(localized: "先补记 \(overdue) 项用药"),
                detail: String(localized: "按真实发生时间补记服用结果，后续药症回看才不会把计划误当作实际用药。"),
                actionTitle: String(localized: "补记用药"),
                progress: progress
            )
        }
        if total > 0, completed < total {
            return HealthFeatureNextStep(
                eyebrow: String(localized: "下一项计划"),
                title: String(localized: "继续完成今日用药计划"),
                detail: String(localized: "服用后记录实际时间与体感；未服用时不要提前标记完成。"),
                actionTitle: String(localized: "记录用药"),
                progress: progress
            )
        }
        return HealthFeatureNextStep(
            eyebrow: String(localized: "今日回看"),
            title: todaySymptomCount > 0 ? String(localized: "今天已有症状记录") : String(localized: "补充今天的用药或体感"),
            detail: String(localized: "只记录真实发生的用药与症状；时间重叠用于整理，不代表药物导致症状。"),
            actionTitle: String(localized: "新增记录"),
            progress: progress
        )
    }
}

struct HealthFeatureNextStepCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let focus: HealthFeatureNextStep
    let symbol: String
    let accent: Color
    let action: () -> Void

    @State private var isFloating = false
    @State private var renderedProgress = 0.0
    @State private var feedbackTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(alignment: .top, spacing: Theme.Spacing.small) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 18, weight: .black))
                    .foregroundColor(accent)
                    .frame(width: 44, height: 44)
                    .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .scaleEffect(reduceMotion ? 1 : (isFloating ? 1.04 : 0.97))
                    .offset(y: reduceMotion ? 0 : (isFloating ? -4 : 4))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.9).repeatForever(autoreverses: true),
                        value: isFloating
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
                    Text(focus.eyebrow)
                        .font(Theme.Typography.label)
                        .foregroundColor(accent)
                    Text(focus.title)
                        .font(Theme.Typography.sectionTitle)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(focus.detail)
                        .font(Theme.Typography.supporting)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ProgressView(value: renderedProgress)
                .tint(accent)
                .animation(
                    reduceMotion ? nil : MotionTokens.ringDrawAnimation,
                    value: renderedProgress
                )

            Button {
                feedbackTrigger += 1
                action()
            } label: {
                HStack {
                    Text(focus.actionTitle)
                    Spacer(minLength: Theme.Spacing.compact)
                    Image(systemName: "arrow.right")
                        .scaleEffect(
                            reduceMotion || feedbackTrigger.isMultiple(of: 2)
                                ? 1
                                : HealthFeatureMotionPolicy(reduceMotion: false).pressedScale
                        )
                        .offset(
                            x: reduceMotion || feedbackTrigger.isMultiple(of: 2) ? 0 : 3
                        )
                        .animation(
                            reduceMotion ? nil : MotionTokens.cardPressAnimation,
                            value: feedbackTrigger
                        )
                }
                .font(Theme.Typography.bodyBold)
                .foregroundColor(accent)
                .padding(.horizontal, Theme.Spacing.medium)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: feedbackTrigger)
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: Theme.Stroke.standardWidth)
        )
        .shadow(color: Theme.Shadow.raised.color, radius: Theme.Shadow.raised.radius, y: Theme.Shadow.raised.y)
        .onAppear {
            isFloating = !reduceMotion
            updateRenderedProgress()
        }
        .onChange(of: focus.progress) { _, _ in updateRenderedProgress() }
        .onChange(of: reduceMotion) { _, newValue in
            isFloating = !newValue
            updateRenderedProgress()
        }
    }

    private func updateRenderedProgress() {
        let target = min(max(focus.progress, 0), 1)
        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { renderedProgress = target }
        } else {
            renderedProgress = target
        }
    }
}

/// 健康模块以模态方式展示时使用的统一返回控件。
/// 推入 NavigationStack 的页面继续使用系统返回按钮，避免同一页面出现两个返回入口。
struct HealthNavigationDismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.appSystem(size: 16, weight: .bold))
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(
                    width: HealthDetailDesignSystem.navigationControlSize,
                    height: HealthDetailDesignSystem.navigationControlSize
                )
                .background(Theme.Colors.surface.opacity(0.82), in: Circle())
                .overlay(Circle().stroke(Theme.Colors.surface.opacity(0.92), lineWidth: Theme.Stroke.standardWidth))
                .shadow(color: Theme.Shadow.raised.color, radius: Theme.Shadow.raised.radius, y: Theme.Shadow.raised.y)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回")
        .accessibilityHint("返回上一页")
    }
}

private struct HealthDetailSurfaceModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: HealthDetailDesignSystem.surfaceRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .padding(padding)
                .bbLiquidGlassSurface(
                    tint: .white,
                    in: shape,
                    tintStrength: 0.02,
                    shadow: false
                )
                .shadow(
                    color: Color(hex: "283857").opacity(0.07),
                    radius: 14,
                    x: 0,
                    y: 6
                )
        } else {
            content
                .padding(padding)
                .background(Color.white.opacity(0.86), in: shape)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.88), lineWidth: 1)
                }
                .shadow(
                    color: Color(hex: "283857").opacity(0.07),
                    radius: 14,
                    x: 0,
                    y: 6
                )
        }
    }
}

extension View {
    func healthDetailSurface(padding: CGFloat = Theme.Spacing.medium) -> some View {
        modifier(HealthDetailSurfaceModifier(padding: padding))
    }

    func healthDetailNavigation(title: LocalizedStringKey) -> some View {
        appSecondaryNavigation(title: title)
    }
}
