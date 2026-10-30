/// AbnormalAlertOverlay 由健康监测逻辑调用，作为「异常提醒」遮罩层。
/// 负责在检测到异常健康数据时弹出全屏提示并支持展开详情。

import SwiftUI

/// 异常提醒视图 由上级页面或路由调用，作为辅助界面里的界面或内容组件。
/// 负责承载弹层、空状态、引导态或局部补充信息，帮助主流程表达更完整。
struct AbnormalAlertOverlay: View {
    @Binding var isPresented: Bool
    @State private var showDetails: Bool = false
    
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
                    Text("异常提醒")
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
                
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.Colors.accentRed.opacity(0.12))
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.appSystem(size: 22, weight: .bold))
                            .foregroundColor(Theme.Colors.accentRed)
                    }
                    .frame(width: 44, height: 44)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("检测到偏离阈值的读数")
                            .font(.appSystem(.subheadline, design: .default).weight(.semibold))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("你的心率、压力或恢复指标出现明显波动。先停下来观察身体感受，必要时联系专业人士。")
                            .font(.appSystem(.footnote, design: .default))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Theme.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                
                HStack(spacing: 10) {
                    Button {
                        showDetails = true
                    } label: {
                        Text("查看详情")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundColor(Theme.Colors.onAccent)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            isPresented = false
                        }
                    } label: {
                        Text("稍后")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .background(Theme.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                
                Divider()
                    .overlay(Theme.Colors.textSecondary.opacity(0.2))
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("建议处理")
                        .font(.appSystem(.subheadline, design: .default).weight(.semibold))
                        .foregroundColor(Theme.Colors.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        AlertSuggestionRow(text: "坐下休息 3-5 分钟，避免继续高强度活动")
                        AlertSuggestionRow(text: "进行一次缓慢呼吸，观察心率和压力是否回落")
                        AlertSuggestionRow(text: "若伴随胸闷、头晕或持续不适，请及时就医")
                    }
                }
                .padding()
                .background(Theme.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(20)
            .frame(maxWidth: 520)
        }
        .alert("异常详情", isPresented: $showDetails) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("本提醒基于当前健康指标的波动生成，不替代医疗诊断。请结合身体感受判断。")
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

private struct AlertSuggestionRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.appSystem(size: 14, weight: .semibold))
                .foregroundColor(Theme.Colors.mintGreen)
                .padding(.top, 2)
            Text(text)
                            .font(.appSystem(.footnote, design: .default))
                            .foregroundColor(Theme.Colors.textSecondary)
        }
    }
}
