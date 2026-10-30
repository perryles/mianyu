/// SplashLoadingView 由主流程在数据加载或切换场景调用，作为「加载过渡」弹层。
/// 负责以呼吸动画展示标题/副标题，并在完成后通过回调关闭。

import SwiftUI

/// 启动加载视图 由上级页面或路由调用，作为辅助界面里的界面或内容组件。
/// 负责承载弹层、空状态、引导态或局部补充信息，帮助主流程表达更完整。
struct SplashLoadingView: View {
    let title: String
    let subtitle: String
    let onClose: () -> Void
    
    @State private var breathing: Bool = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 14) {
                Spacer()
                
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Theme.Colors.background)
                        .frame(width: 120, height: 120)
                        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
                        .scaleEffect(breathing ? 1.02 : 0.98)
                    
                    Image(systemName: "waveform.path.ecg")
                        .font(.appSystem(size: 46, weight: .bold))
                        .foregroundColor(Color.black)
                        .opacity(breathing ? 0.85 : 1)
                }
                
                Text(title)
                    .font(.appSystem(.title2, design: .default).bold())
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text(subtitle)
                    .font(.appSystem(.subheadline, design: .default))
                    .foregroundColor(Theme.Colors.textSecondary)
                
                ProgressView()
                    .tint(Color.black)
                    .padding(.top, 4)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.appSystem(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(12)
                    .background(Theme.Colors.background)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .padding(18)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}
