/// NewbieGuideOverlay 由今日页首次进入时调用，作为「新手引导」遮罩层。
/// 负责分步高亮今日概览、趋势、压力、个人页核心功能，引导用户熟悉操作。

import SwiftUI

/// 新手引导视图 由上级页面或路由调用，作为辅助界面里的界面或内容组件。
/// 负责承载弹层、空状态、引导态或局部补充信息，帮助主流程表达更完整。
struct NewbieGuideOverlay: View {
    @Binding var isPresented: Bool
    @State private var stepIndex: Int = 0
    
    private let steps: [String] = [
        "这里是今日概览。点开卡片可查看更详细的数据。",
        "在趋势页可以查看周/月报告与指标变化。",
        "压力页提供记录与呼吸引导，帮助快速恢复平静。",
        "个人页可以管理目标、阈值、设备与数据导出。"
    ]
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 14) {
                HStack {
                    Text("新手引导")
                        .font(.appSystem(.headline, design: .default))
                        .foregroundColor(Theme.Colors.textPrimary)
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            isPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.appSystem(size: 13, weight: .semibold))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(8)
                            .background(Theme.Colors.background)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("第 \(stepIndex + 1) / \(steps.count) 步")
                        .font(.appSystem(.subheadline, design: .monospaced))
                        .foregroundColor(Theme.Colors.textSecondary)
                    
                    Text(steps[stepIndex])
                        .font(.appSystem(.body, design: .default))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Theme.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            stepIndex = max(0, stepIndex - 1)
                        }
                    } label: {
                        Text("上一步")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .background(Theme.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(stepIndex == 0)
                    .opacity(stepIndex == 0 ? 0.5 : 1)
                    
                    Button {
                        if stepIndex >= steps.count - 1 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                isPresented = false
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                stepIndex = min(steps.count - 1, stepIndex + 1)
                            }
                        }
                    } label: {
                        Text(stepIndex >= steps.count - 1 ? "完成" : "下一步")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundColor(Theme.Colors.onAccent)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 520)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}
