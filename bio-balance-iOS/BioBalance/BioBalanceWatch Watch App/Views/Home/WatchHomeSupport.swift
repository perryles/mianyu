import SwiftUI

/// 手表同步状态卡片组件 作为Apple Watch 应用里的内容展示卡片。
/// 负责Apple Watch 端展示与同步。
struct WatchSyncStatusCard: View {
    var receiver: WatchConnectivityReceiver

    private var statusText: String {
        if receiver.isSyncing { return String(localized: "正在拉取 iPhone 数据") }
        return receiver.isReachable ? String(localized: "iPhone 已连接") : String(localized: "等待 iPhone 连接")
    }

    private var syncDetailText: String {
        if receiver.isSyncing { return String(localized: "正在请求最新健康快照，请稍候。") }
        if let error = receiver.syncErrorMessage, !error.isEmpty { return error }
        if let last = receiver.lastSyncDate {
            return String(localized: "最近同步：\(last.formatted(date: .omitted, time: .shortened))")
        }
        return String(localized: "连接后会显示 HRV、压力和恢复状态。")
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 46, height: 46)
                ProgressView()
                    .tint(.white)
            }

            Text(statusText)
                .font(.watchAppSystem(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))

            Text(syncDetailText)
                .font(.watchAppSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.70))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("立即同步") {
                receiver.syncNow()
            }
            .font(.watchAppSystem(size: 11, weight: .bold, design: .rounded))
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.58, green: 0.63, blue: 0.96))
            .disabled(!receiver.isReachable || receiver.isSyncing)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 185)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.30, green: 0.32, blue: 0.43),
                    Color(red: 0.13, green: 0.14, blue: 0.20),
                    Color.black.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 0.8)
        }
        .overlay(alignment: .topTrailing) {
            if receiver.isSyncing {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 14)
                    .padding(.trailing, 14)
            }
        }
    }

}

/// 身体年龄Estimate结构体 作为Apple Watch 应用里的辅助类型。
/// 负责Apple Watch 端展示与同步。
struct BodyAgeEstimate {
    let valueText: String
    let subtitle: String
    let badge: String
    let guidance: String
    let coverageText: String?
    let directionText: String?
    let isSynced: Bool
}

func makeBodyAgeEstimate(snapshot: WatchRealtimeHealth) -> BodyAgeEstimate {
    if let bodyAgeValueYears = snapshot.bodyAgeValueYears {
        return BodyAgeEstimate(
            valueText: String(localized: "\(Int(bodyAgeValueYears.rounded())) 岁"),
            subtitle: snapshot.bodyAgeComparisonText ?? String(localized: "已从 iPhone 同步身体年龄结果"),
            badge: snapshot.bodyAgeStatusText ?? String(localized: "已同步"),
            guidance: snapshot.bodyAgeSuggestionText ?? String(localized: "继续累积健康数据"),
            coverageText: snapshot.bodyAgeCoverageText,
            directionText: snapshot.bodyAgeDirectionText,
            isSynced: true
        )
    }

    let statusText = snapshot.bodyAgeStatusText ?? String(localized: "等待数据")
    let comparisonText = snapshot.bodyAgeComparisonText ?? String(localized: "补齐样本后再和实际年龄比较")
    let suggestionText = snapshot.bodyAgeSuggestionText ?? String(localized: "打开 iPhone 端同步后会显示正式结果")

    if snapshot.bodyAgeCoverageText != nil || snapshot.bodyAgeStatusText != nil {
        return BodyAgeEstimate(
            valueText: "--",
            subtitle: comparisonText,
            badge: statusText,
            guidance: suggestionText,
            coverageText: snapshot.bodyAgeCoverageText,
            directionText: snapshot.bodyAgeDirectionText,
            isSynced: true
        )
    }

    return BodyAgeEstimate(
        valueText: "--",
        subtitle: String(localized: "等待 iPhone 同步身体年龄结果"),
        badge: String(localized: "待同步"),
        guidance: String(localized: "保持 iPhone 打开并完成健康数据授权后，这里会显示正式身体年龄。"),
        coverageText: nil,
        directionText: nil,
        isSynced: false
    )
}

func pressureColor(for value: Int) -> Color {
    switch value {
    case 0..<35: return .green
    case 35..<70: return .orange
    default: return .red
    }
}

func pressureHeadline(for value: Int) -> String {
    switch value {
    case 0..<35: return String(localized: "今天状态还不错")
    case 35..<70: return String(localized: "今天节奏有点满")
    default: return String(localized: "今天先把恢复放前面")
    }
}

func pressureLevelText(for value: Int) -> String {
    switch value {
    case 0..<35: return String(localized: "比较放松")
    case 35..<70: return String(localized: "有些紧绷")
    default: return String(localized: "压力偏高")
    }
}

func pressureAdvice(for value: Int) -> String {
    switch value {
    case 0..<35: return String(localized: "继续保持现在的节奏就好。")
    case 35..<70: return String(localized: "适合停一下，做一次短呼吸或散步。")
    default: return String(localized: "建议先慢下来，做 2 分钟呼吸放松。")
    }
}

func formatWhole(_ value: Double) -> String {
    String(Int(value.rounded()))
}
