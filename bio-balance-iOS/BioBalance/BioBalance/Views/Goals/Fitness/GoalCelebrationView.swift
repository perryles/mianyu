/// GoalCelebrationView 由目标达成检测逻辑调用，作为「目标达成庆祝」弹层。
/// 负责以全屏/半屏形式展示庆祝动画与文案，并通过回调关闭。

import SwiftUI

/// 目标达成视图 由上级页面或路由调用，作为辅助界面里的界面或内容组件。
/// 负责承载弹层、空状态、引导态或局部补充信息，帮助主流程表达更完整。
struct GoalCelebrationView: View {
    /// Presentation 枚举，作为内部辅助类型，用于细分外层辅助弹层与状态视图中的状态或分支。
    enum Presentation {
        case fullScreen
        case halfSheet
    }
    
    let presentation: Presentation
    let title: String
    let subtitle: String
    let closeTitle: String
    let onClose: () -> Void
    
    @State private var pulse: Bool = false
    @State private var floatUp: Bool = false
    
    var body: some View {
        ZStack {
            backgroundLayer
            
            content
                .padding(presentation == .fullScreen ? 26 : 20)
                .frame(maxWidth: 520)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                floatUp = true
            }
        }
    }
    
    private var backgroundLayer: some View {
        Group {
            if presentation == .fullScreen {
                Theme.Colors.background
                    .ignoresSafeArea()
            } else {
                Theme.Colors.background
                    .ignoresSafeArea()
            }
        }
    }
    
    private var content: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
                    .frame(width: 190, height: 190)
                    .scaleEffect(pulse ? 1.06 : 0.98)
                    .opacity(pulse ? 0.6 : 0.9)
                
                Circle()
                    .stroke(Color.black.opacity(0.10), lineWidth: 10)
                    .frame(width: 135, height: 135)
                    .scaleEffect(pulse ? 0.95 : 1.03)
                    .opacity(pulse ? 0.8 : 0.55)
                
                Image(systemName: "checkmark")
                    .font(.appSystem(size: 48, weight: .bold))
                    .foregroundColor(Color.black)
                    .offset(y: floatUp ? -4 : 6)
            }
            .padding(.top, presentation == .fullScreen ? 28 : 8)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.appSystem(.title2, design: .default).bold())
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text(subtitle)
                    .font(.appSystem(.subheadline, design: .default))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                onClose()
            } label: {
                Text(closeTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(Theme.Colors.onAccent)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: presentation == .fullScreen ? 26 : 22, style: .continuous)
                .fill(Theme.Colors.background)
                .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 10)
        )
        .padding(presentation == .fullScreen ? 0 : 6)
    }
}
