/// Complication Guide View 定义 Apple Watch 端的界面或同步逻辑，负责在手表上展示核心健康信息并与 iPhone 侧保持数据联动。
import SwiftUI

private enum WatchComplicationTemplateOption: String, CaseIterable, Identifiable {
    case overview
    case recovery
    case sleep
    case activity
    case hydration
    case bodyAge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return String(localized: "综合状态")
        case .recovery: return String(localized: "恢复")
        case .sleep: return String(localized: "睡眠")
        case .activity: return String(localized: "活动")
        case .hydration: return String(localized: "补水")
        case .bodyAge: return String(localized: "体龄")
        }
    }

    var detail: String {
        switch self {
        case .overview: return String(localized: "优先看今日整体状态")
        case .recovery: return String(localized: "优先看 HRV 与恢复分数")
        case .sleep: return String(localized: "优先看睡眠时长与得分")
        case .activity: return String(localized: "优先看步数与活动完成度")
        case .hydration: return String(localized: "优先看饮水和咖啡因")
        case .bodyAge: return String(localized: "优先看体龄与建议")
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "waveform.path.ecg"
        case .recovery: return "leaf.fill"
        case .sleep: return "bed.double.fill"
        case .activity: return "figure.walk"
        case .hydration: return "drop.fill"
        case .bodyAge: return "person.text.rectangle"
        }
    }

    var tint: Color {
        switch self {
        case .overview: return .cyan
        case .recovery: return .green
        case .sleep: return .blue
        case .activity: return .orange
        case .hydration: return .teal
        case .bodyAge: return .purple
        }
    }
}

/// 复杂功能引导视图 由上级页面或路由调用，作为设置模块里的界面或内容组件。
/// 负责Apple Watch 端展示与同步。
struct ComplicationGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var receiver: WatchConnectivityReceiver
    var showsCloseButton = false

    private var selectedOption: WatchComplicationTemplateOption {
        WatchComplicationTemplateOption(rawValue: receiver.defaultComplicationTemplate) ?? .overview
    }

    private var syncTitle: String {
        receiver.isReachable ? String(localized: "iPhone 已连接") : String(localized: "等待 iPhone 连接")
    }

    private var syncDetail: String {
        receiver.isReachable
            ? String(localized: "点一下就能刷新默认模板。")
            : String(localized: "当前模板会先保存在手表端，等 iPhone 恢复连接后继续同步。")
    }

    private var latestSyncText: String {
        if let last = receiver.lastSyncDate ?? AppGroupManager.shared.getLastSyncTime() {
            return last.formatted(date: .omitted, time: .shortened)
        }
        return String(localized: "还没有同步记录")
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.16),
                    Color(red: 0.06, green: 0.08, blue: 0.14),
                    Color(red: 0.02, green: 0.03, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.55, green: 0.50, blue: 1.0).opacity(0.12))
                .frame(width: 140, height: 140)
                .blur(radius: 44)
                .offset(x: 56, y: -112)

            Circle()
                .fill(Color(red: 0.34, green: 0.81, blue: 0.63).opacity(0.10))
                .frame(width: 154, height: 154)
                .blur(radius: 48)
                .offset(x: -50, y: 30)

            ScrollView {
                VStack(spacing: 10) {
                    templateGridCard
                    syncCard
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("表盘设置")
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var templateGridCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                    Text("默认模块")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("点一下就能切换，改完会同步到 iPhone。")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.68))
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(WatchComplicationTemplateOption.allCases) { option in
                    Button {
                        receiver.updateComplicationTemplate(option.rawValue)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(receiver.defaultComplicationTemplate == option.rawValue ? option.tint : Color.gray.opacity(0.28))
                                .frame(width: 9, height: 9)
                                .padding(.top, 4)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(option.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: option.symbolName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(option.tint)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color.white.opacity(receiver.defaultComplicationTemplate == option.rawValue ? 0.16 : 0.08),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(receiver.defaultComplicationTemplate == option.rawValue ? 0.10 : 0.05), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
        )
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("同步")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(syncTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(receiver.isReachable ? .mint : .secondary)
                }
                Spacer()
                Button("刷新") {
                    receiver.requestLatestFromiPhone()
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
            }

            Text(syncDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("最近同步：\(latestSyncText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
        )
    }

    private func previewChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}