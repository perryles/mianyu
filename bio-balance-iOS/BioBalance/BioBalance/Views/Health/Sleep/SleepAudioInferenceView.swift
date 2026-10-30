/// SleepAudioInferenceView 由睡眠详情页调用，作为「睡眠音频监测」页面。
/// 负责通过 SleepAudioInferenceService 提供音频监测与推理展示。

import SwiftUI

struct SleepAudioInferenceView: View {
    @State private var service = SleepAudioInferenceService()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("睡眠音频监测", systemImage: "waveform.and.mic")
                        .font(.headline)
                    Text("查看本机睡眠音频分类结果。原始音频只在内存中处理，不保存、不上传。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(
                        service.isFluidAudioPackageAvailable ? "FluidAudio SDK 已接入，模型将优先使用" : "当前使用本机基线算法",
                        systemImage: service.isFluidAudioPackageAvailable ? "checkmark.seal.fill" : "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(service.isFluidAudioPackageAvailable ? .green : .orange)
                }
                .padding(.vertical, 4)
            }

            Section("实时指标") {
                LabeledContent("状态", value: service.isRunning ? "采集中" : "已停止")
                LabeledContent("运行时长", value: "\(Int(service.elapsed)) 秒")
                LabeledContent("窗口数量", value: "\(service.results.count)")
                if let last = service.results.last {
                    LabeledContent("最近活动", value: last.activity.displayName)
                    LabeledContent("最近音量", value: String(format: "%.1f dBFS", last.decibelsFullScale))
                    LabeledContent("推理提供方", value: last.providerName)
                }
            }

            Section("窗口结果") {
                if service.results.isEmpty {
                    Text("点击开始，采集 10 秒本地音频窗口。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.results.reversed()) { result in
                        HStack {
                            Circle()
                                .fill(color(for: result.activity))
                                .frame(width: 9, height: 9)
                            VStack(alignment: .leading) {
                                Text(result.activity.displayName)
                                Text(result.startDate, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.1f dBFS", result.decibelsFullScale))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("睡眠音频诊断")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(service.isRunning ? "停止" : "开始 10 秒") {
                    if service.isRunning {
                        service.stop()
                    } else {
                        Task { await service.start() }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .alert("采集失败", isPresented: .constant(service.errorMessage != nil)) {
            Button("知道了") { service.clearError() }
        } message: {
            Text(service.errorMessage ?? "未知错误")
        }
    }

    private func color(for activity: SleepAudioActivity) -> Color {
        switch activity {
        case .quiet: return .gray
        case .speechLike: return .blue
        case .steadyNoise: return .orange
        case .active: return .purple
        }
    }
}

#Preview {
    NavigationStack { SleepAudioInferenceView() }
}
