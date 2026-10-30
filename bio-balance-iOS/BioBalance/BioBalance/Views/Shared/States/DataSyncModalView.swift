/// DataSyncModalView 由数据同步入口调用，作为「数据同步」模态弹层。
/// 负责以进度条展示同步阶段（准备/上传/下载/校验/完成）并反馈结果。

import SwiftUI

/// 数据同步Modal视图 由上级页面或路由调用，作为辅助界面里的界面或内容组件。
/// 负责承载弹层、空状态、引导态或局部补充信息，帮助主流程表达更完整。
struct DataSyncModalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var progress: Double = 0
    @State private var phase: SyncPhase = .preparing
    @State private var isCompleted: Bool = false
    
    /// Sync Phase 枚举，作为内部辅助类型，用于细分外层辅助弹层与状态视图中的状态或分支。
    enum SyncPhase: String {
        case preparing = "准备中"
        case uploading = "上传中"
        case downloading = "下载中"
        case verifying = "校验中"
        case done = "完成"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.pageBackground.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath.circle")
                            .font(.appSystem(size: 38, weight: .semibold))
                            .foregroundColor(Color.black)
                        
                        Text("数据同步")
                            .font(.appSystem(.title3, design: .default).bold())
                            .foregroundColor(Theme.Colors.textPrimary)
                        
                        Text(phase.rawValue)
                            .font(.appSystem(.subheadline, design: .default))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .padding(.top, 6)
                    
                    VStack(spacing: 10) {
                        ProgressView(value: progress)
                            .tint(Color.black)
                        HStack {
                            Text(localizedPercentRatio(progress))
                                .font(.appSystem(.footnote, design: .monospaced))
                                .foregroundColor(Theme.Colors.textSecondary)
                            Spacer()
                            Text(isCompleted ? "已同步到最新" : "请保持网络连接")
                                .font(.appSystem(.footnote, design: .default))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                    .padding()
                    .background(Theme.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 10) {
                        syncRow(title: "本地缓存整理", done: progress >= 0.2)
                        syncRow(title: "上传新增记录", done: progress >= 0.5)
                        syncRow(title: "下载远端变更", done: progress >= 0.8)
                        syncRow(title: "索引与校验", done: progress >= 0.95)
                    }
                    .padding()
                    .background(Theme.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Text(isCompleted ? "关闭" : "取消")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(Theme.Colors.onAccent)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            await runSyncSimulation()
        }
    }
    
    private func syncRow(title: String, done: Bool) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(done ? Color.black : Theme.Colors.textSecondary)
            Text(title)
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
        }
        .font(.appSystem(.subheadline, design: .default))
    }
    
    @MainActor
    private func runSyncSimulation() async {
        guard progress == 0 else { return }
        for idx in 0...100 {
            do {
                try await Task.sleep(for: .milliseconds(35))
            } catch {
                return
            }
            progress = Double(idx) / 100
            phase = phaseForProgress(progress)
        }
        isCompleted = true
        phase = .done
    }
    
    private func phaseForProgress(_ value: Double) -> SyncPhase {
        switch value {
        case 0..<0.25:
            return .preparing
        case 0.25..<0.6:
            return .uploading
        case 0.6..<0.9:
            return .downloading
        case 0.9..<0.99:
            return .verifying
        default:
            return .done
        }
    }
}
