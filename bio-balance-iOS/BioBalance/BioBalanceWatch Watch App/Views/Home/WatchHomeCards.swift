import SwiftUI

enum WatchHomeSheet: String, Identifiable {
    case settings
    case hrvInfo
    case pressure
    case sleep
    case motivation
    case ai
    case more

    var id: String { rawValue }
}

struct WatchHomeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.16),
                    Color(red: 0.08, green: 0.07, blue: 0.19),
                    Color(red: 0.01, green: 0.02, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.72, green: 0.73, blue: 1.0).opacity(0.16))
                .frame(width: 140, height: 140)
                .blur(radius: 44)
                .offset(x: 56, y: -112)

            Circle()
                .fill(Color(red: 0.52, green: 0.41, blue: 0.96).opacity(0.18))
                .frame(width: 168, height: 168)
                .blur(radius: 48)
                .offset(x: -46, y: -30)
        }
    }
}

struct WatchRecoveryInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    let snapshot: WatchRealtimeHealth

    private var statusText: String {
        if snapshot.hrv >= 48 { return String(localized: "恢复良好") }
        if snapshot.hrv >= 25 { return String(localized: "状态正常") }
        if snapshot.hrv > 0 { return String(localized: "需要恢复") }
        return String(localized: "等待数据")
    }

    private var sampleTimeText: String {
        guard snapshot.timestamp > 0 else { return String(localized: "暂无采样时间") }
        return Date(timeIntervalSince1970: TimeInterval(snapshot.timestamp))
            .formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        infoChip(title: String(localized: "当前"), value: snapshot.hrv > 0 ? "\(formatWhole(snapshot.hrv))ms" : "--")
                        infoChip(title: String(localized: "状态"), value: statusText)
                    }

                    Text("HRV 越高通常代表恢复越好，偏低更常见于疲劳、压力或睡眠不足。")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("最近采样：\(sampleTimeText)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.64))
                }
                .padding(14)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.18, blue: 0.34),
                            Color(red: 0.09, green: 0.09, blue: 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )

                NavigationLink {
                    StressDetailView(snapshot: snapshot, liveBpm: snapshot.bpm)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("查看完整解读")
                                .font(.caption.weight(.semibold))
                            Text("继续看趋势、建议和关联状态")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .navigationTitle("HRV 说明")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") {
                    dismiss()
                }
            }
        }
    }

    private func infoChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
            Text(value)
                .font(.watchAppSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
