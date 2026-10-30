/// 好友健康报告分享卡片页：设计稿「健康报告分享卡片」（6:188）。
/// 周报评分预览 + 分享内容开关 + 可见范围 + 生成卡片 / 导出 PDF。
/// 合同外的类别（心率/压力）不可开启，评分是从共享摘要派生的本机展示值，
/// 生成动作当前导出快照 PDF，不新增云端数据。

import SwiftUI
import UIKit

struct SocialShareReportCardView: View {
    let myStatus: MySharedHealthStatus

    @Environment(\.dismiss) private var dismiss
    @State private var includedCategories: Set<ReportCategory> = [.score, .sleep, .walking]
    @State private var visibility: ReportVisibility = .onceOnly
    @State private var renderingPDF = false
    @State private var renderedPDFURL: URL?
    @State private var exportError: String?

    enum ReportCategory: String, CaseIterable, Identifiable, Hashable {
        case score
        case sleep
        case walking
        case heartRate
        case stress

        var id: String { rawValue }

        var title: String {
            switch self {
            case .score: return String(localized: "综合评分")
            case .sleep: return String(localized: "睡眠数据")
            case .walking: return String(localized: "运动数据")
            case .heartRate: return String(localized: "心率数据")
            case .stress: return String(localized: "压力数据")
            }
        }

        /// 合同内可分享的类别；心率/压力未进入共享载荷前不可开启。
        var isSupported: Bool {
            switch self {
            case .score, .sleep, .walking: return true
            case .heartRate, .stress: return false
            }
        }
    }

    enum ReportVisibility: String, CaseIterable, Identifiable, Hashable {
        case onceOnly
        case specialFocus
        case allFriends

        var id: String { rawValue }

        var title: String {
            switch self {
            case .onceOnly: return String(localized: "仅这一次")
            case .specialFocus: return String(localized: "特别关注")
            case .allFriends: return String(localized: "所有好友")
            }
        }
    }

    private let ink = Color(hex: "12141A")
    private let secondaryInk = Color(hex: "6E7887")
    private let canvas = Color(hex: "F6F9FB")
    private let trackOff = Color(hex: "DBE0E8")
    private let toggleOn = Color(hex: "29AD73")
    private let mintBanner = Color(hex: "EBFAF5")
    private let liveTint = Color(hex: "29AD73")

    var body: some View {
        AdaptivePageScrollView(topPadding: 8, bottomPadding: 40) {
            VStack(alignment: .leading, spacing: 20) {
                header
                weeklyReportCard
                shareContentCard
                visibilityCard
                actionButtons
            }
        }
        .background(canvas)
        .navigationTitle("好友健康报告")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { renderedPDFURL.map(ShareDocument.init) },
            set: { if $0 == nil { renderedPDFURL = nil } }
        )) { document in
            ShareSheet(items: [document.url])
        }
        .alert("生成失败", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("好友健康报告")
                .font(.appSystem(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(ink)
            Text("选择你愿意分享的内容")
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryInk)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 周报预览卡

    private var weeklyReportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("好友的健康周报")
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(liveTint)
            Text(weekRangeText)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryInk)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(reportScore)")
                    .font(.appSystem(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(ink)
                    .accessibilityLabel("综合健康评分 \(reportScore)")
            }
            Text(scoreCaption)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(liveTint)

            HStack(spacing: 8) {
                if includedCategories.contains(.sleep) {
                    summaryChip("睡眠", value: sleepChipText)
                }
                if includedCategories.contains(.walking) {
                    summaryChip("运动", value: walkingChipText)
                }
            }

            Text("“这一周，\(weeklyMotto)”")
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryInk)
                .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mintBanner, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func summaryChip(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(secondaryInk)
            Text(value)
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 分享内容

    private var shareContentCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("分享内容")
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .padding(.bottom, 6)

            ForEach(ReportCategory.allCases) { category in
                categoryToggleRow(category)
                if category != ReportCategory.allCases.last {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func categoryToggleRow(_ category: ReportCategory) -> some View {
        let isOn = includedCategories.contains(category)
        return Button {
            guard category.isSupported else { return }
            if isOn {
                if category != .score { // 综合评分是报告主体，保持常开
                    includedCategories.remove(category)
                }
            } else {
                includedCategories.insert(category)
            }
        } label: {
            HStack(spacing: 12) {
                Text(category.title)
                    .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(category.isSupported ? ink : secondaryInk.opacity(0.7))
                if !category.isSupported {
                    Text("暂不支持")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(secondaryInk.opacity(0.7))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(canvas, in: Capsule())
                }
                Spacer(minLength: 8)
                Capsule()
                    .fill(category.isSupported ? (isOn ? toggleOn : trackOff) : trackOff.opacity(0.6))
                    .frame(width: 48, height: 28)
                    .overlay {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .offset(x: isOn ? 11 : -11)
                    }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!category.isSupported)
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // MARK: - 可见范围

    private var visibilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("可见范围")
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
            HStack(spacing: 8) {
                ForEach(ReportVisibility.allCases) { option in
                    Button {
                        visibility = option
                    } label: {
                        Text(option.title)
                            .font(.appSystem(size: 13, weight: visibility == option ? .bold : .medium, design: .rounded))
                            .foregroundStyle(visibility == option ? Color.white : secondaryInk)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(visibility == option ? ink : Color(hex: "F0F5FA")))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(visibility == option ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - 操作按钮

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                generatePDF()
            } label: {
                Group {
                    if renderingPDF {
                        ProgressView().tint(Theme.Colors.onAccent)
                    } else {
                        Text("生成分享卡片")
                    }
                }
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(renderingPDF)

            Button {
                generatePDF()
            } label: {
                Text("导出 PDF")
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(renderingPDF)
        }
    }

    // MARK: - 派生数据

    private var snapshot: SharedHealthSnapshot? { myStatus.snapshot }

    /// 从共享摘要派生的展示评分（0-100），仅本机计算，不回写云。
    private var reportScore: Int {
        guard let snapshot else { return 0 }
        let sleepScore = Double(snapshot.highlights.averageSleepMinutes ?? 0) / 480.0
        let walkScore = (snapshot.highlights.averageWalkingSpeedMps ?? 0) / 1.4
        let validRate = Double(
            snapshot.highlights.validSleepDays + snapshot.highlights.validWalkingSpeedDays
        ) / 14.0
        let score = (min(sleepScore, 1) * 0.4 + min(walkScore, 1) * 0.3 + validRate * 0.3) * 100
        return Int(score.rounded())
    }

    private var scoreCaption: String {
        reportScore >= 80
            ? String(localized: "综合健康评分 · 状态良好")
            : reportScore >= 60
                ? String(localized: "综合健康评分 · 节奏稳定")
                : String(localized: "综合健康评分 · 继续加油")
    }

    private var sleepChipText: String {
        guard let minutes = snapshot?.highlights.averageSleepMinutes else { return "—" }
        return String(localized: "\(minutes / 60)h\(minutes % 60)m")
    }

    private var walkingChipText: String {
        guard let speed = snapshot?.highlights.averageWalkingSpeedMps else { return "—" }
        return String(format: "%.1fkm", speed * 60 * 60 / 1000)
    }

    private var weeklyMotto: String {
        let highlights = snapshot?.highlights
        if (highlights?.averageSleepMinutes ?? 0) >= 420 {
            return String(localized: "我睡得更规律，也动得更多。”")
        }
        return String(localized: "我在慢慢调整节奏，状态在变好。”")
    }

    private var weekRangeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -6, to: end) ?? end
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    /// 用 UIKit 把周报预览渲染成单页 PDF 并交给分享面板。
    private func generatePDF() {
        renderingPDF = true
        let score = reportScore
        let range = weekRangeText
        let sleep = includedCategories.contains(.sleep) ? sleepChipText : nil
        let walking = includedCategories.contains(.walking) ? walkingChipText : nil
        Task { @MainActor in
            defer { renderingPDF = false }
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 390, height: 320))
            let data = renderer.pdfData { context in
                context.beginPage()
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                    .foregroundColor: UIColor(Color(hex: "29AD73"))
                ]
                (String(localized: "好友的健康周报") as NSString).draw(
                    at: CGPoint(x: 24, y: 28),
                    withAttributes: titleAttributes
                )
                (range as NSString).draw(
                    at: CGPoint(x: 24, y: 52),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor(Color(hex: "6E7887"))]
                )
                (String(score) as NSString).draw(
                    at: CGPoint(x: 24, y: 78),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 44, weight: .black), .foregroundColor: UIColor(Color(hex: "12141A"))]
                )
                (scoreCaption as NSString).draw(
                    at: CGPoint(x: 24, y: 136),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor(Color(hex: "29AD73"))]
                )
                var y = 176
                if let sleep {
                    (String(localized: "睡眠：\(sleep)") as NSString).draw(
                        at: CGPoint(x: 24, y: y),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor(Color(hex: "12141A"))]
                    )
                    y += 26
                }
                if let walking {
                    (String(localized: "运动：\(walking)") as NSString).draw(
                        at: CGPoint(x: 24, y: y),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor(Color(hex: "12141A"))]
                    )
                    y += 26
                }
                (String(localized: "仅包含我主动选择共享的摘要数据") as NSString).draw(
                    at: CGPoint(x: 24, y: y + 8),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor(Color(hex: "6E7887"))]
                )
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("weekly-report-\(Int(Date().timeIntervalSince1970)).pdf")
            do {
                try data.write(to: url)
                renderedPDFURL = url
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}

private struct ShareDocument: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        SocialShareReportCardView(myStatus: SocialSharingState.empty.myStatus)
    }
}
