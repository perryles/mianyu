/// ReportShareView 由报告页调用，作为「报告分享」面板。
/// 负责定义分享详情级别枚举（详细/摘要）并驱动分享与保存流程。

import SwiftUI
import UIKit
import Photos

private enum ReportShareDetailLevel: String, CaseIterable, Identifiable {
    case detailed = "详细"
    case summary = "摘要"

    var id: String { rawValue }

    /// 本地化标题：rawValue 仅作标识，UI 展示走 String Catalog。
    var displayName: String {
        switch self {
        case .detailed: return String(localized: "详细")
        case .summary: return String(localized: "摘要")
        }
    }
}

/// 报告分享视图 由上级页面或路由调用，作为报告模块里的界面或内容组件。
/// 负责组织日报、周报、月报或报告详情的展示与分享。
struct ReportShareView: View {
    let reportDate: Date
    let score: Int

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ReportSummaryViewModel()
    @State private var shareItems: [Any] = []
    @State private var showingSystemShare = false
    @State private var feedback: ReportShareFeedback?
    @State private var isSaving = false
    @State private var detailLevel: ReportShareDetailLevel = .detailed

    private var summary: ReportDaySummary? {
        viewModel.summary(for: reportDate)
    }

    private var resolvedScore: Int {
        summary?.score ?? score
    }

    private var shareText: String {
        [
            "眠屿 每日健康报告",
            reportDate.reportsFullDateString(),
            resolvedScore > 0 ? "综合评分 \(resolvedScore)" : "综合评分 暂无",
            posterHighlightText,
            trendText
        ].joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.pageBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    shareContextBar

                    ScrollView(showsIndicators: false) {
                        ReportSharePosterCard(
                            reportDate: reportDate,
                            score: resolvedScore,
                            summary: summary,
                            highlightText: posterHighlightText,
                            trendText: trendText,
                            detailLevel: detailLevel
                        )
                        .frame(maxWidth: 430)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                shareBottomBar
            }
            .appSecondaryNavigation(title: "分享报告")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .task {
                viewModel.load(days: 30)
            }
            .sheet(isPresented: $showingSystemShare) {
                ReportActivityShareSheet(items: shareItems)
            }
            .alert(item: $feedback) { item in
                Alert(title: Text(item.message))
            }
        }
    }

    private var shareContextBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.appSystem(size: 15, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color(hex: "DCA91F"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("眠屿")
                        .font(.appSystem(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "565A57"))

                    Text(reportDate.shareHeaderDateString())
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            Picker("报告内容", selection: $detailLevel) {
                ForEach(ReportShareDetailLevel.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("报告内容")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var shareBottomBar: some View {
        HStack(spacing: 18) {
            Button {
                savePoster()
            } label: {
                shareActionButton(
                    title: isSaving ? "保存中" : "保存图片",
                    systemImage: "square.and.arrow.down",
                    isPrimary: false
                )
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            Button {
                sharePoster()
            } label: {
                shareActionButton(title: "分享", systemImage: "square.and.arrow.up", isPrimary: true)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private func shareActionButton(title: String, systemImage: String, isPrimary: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.appSystem(size: 18, weight: .bold))
            Text(title)
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
        }
        .foregroundColor(isPrimary ? Color(hex: "E6B42F") : Color(hex: "343735"))
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(
            isPrimary ? Color(hex: "303331") : Color.white,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isPrimary ? Color.clear : Color(hex: "D8D8D4"), lineWidth: 1)
        }
    }

    private func sharePoster() {
        guard let image = renderPoster() else {
            feedback = ReportShareFeedback(message: "图片生成失败，请稍后再试")
            return
        }
        shareItems = [image, shareText]
        showingSystemShare = true
    }

    @MainActor
    private func savePoster() {
        guard !isSaving else { return }
        guard let image = renderPoster() else {
            feedback = ReportShareFeedback(message: "图片生成失败，请稍后再试")
            return
        }

        isSaving = true
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                isSaving = false
                feedback = ReportShareFeedback(message: "未获得相册添加权限")
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                isSaving = false
                feedback = ReportShareFeedback(message: "已保存到相册")
            } catch {
                isSaving = false
                feedback = ReportShareFeedback(message: "保存失败，请稍后再试")
            }
        }
    }

    private func renderPoster() -> UIImage? {
        let renderer = ImageRenderer(
            content: ReportSharePosterCard(
                reportDate: reportDate,
                score: resolvedScore,
                summary: summary,
                highlightText: posterHighlightText,
                trendText: trendText,
                detailLevel: detailLevel
            )
            .frame(width: 390)
        )
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private var posterHighlightText: String {
        guard detailLevel == .detailed else {
            return resolvedScore > 0 ? "今日综合评分 \(resolvedScore) · \(scoreStatusText)" : "今日综合状态等待更多数据"
        }
        return highlightText
    }

    private var scoreStatusText: String {
        switch resolvedScore {
        case 85...: return "状态稳定"
        case 70..<85: return "整体平稳"
        case 50..<70: return "存在波动"
        case 1..<50: return "恢复承压"
        default: return "等待记录"
        }
    }

    private var highlightText: String {
        guard let summary, summary.hasData else {
            return String(localized: "摘要：健康 App 暂无足够数据")
        }
        let sleep = summary.sleepHours.map { String(format: String(localized: "睡眠 %.1fh"), $0) } ?? "睡眠 暂无"
        let stress = summary.stress.map { "压力 \(Int($0.rounded()))" } ?? "压力 暂无"
        let hrv = summary.hrv.map { "HRV \(Int($0.rounded()))" } ?? "HRV 暂无"
        return "\(sleep) · \(stress) · \(hrv)"
    }

    private var trendText: String {
        let nearby = recentSummaries
        guard nearby.count >= 2,
              let first = nearby.first?.score,
              let last = nearby.last?.score else {
            return String(localized: "趋势：等待更多健康数据")
        }
        let delta = last - first
        if abs(delta) <= 3 {
            return String(localized: "趋势：近 7 天整体稳定")
        }
        return delta > 0 ? "趋势：近 7 天综合状态改善 \(delta) 分" : "趋势：近 7 天综合状态下降 \(abs(delta)) 分"
    }

    private var recentSummaries: [ReportDaySummary] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: reportDate)),
              let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reportDate)) else {
            return []
        }
        return viewModel.summaries(for: DateInterval(start: start, end: end)).filter { $0.score != nil }
    }
}

private struct ReportSharePosterCard: View {
    let reportDate: Date
    let score: Int
    let summary: ReportDaySummary?
    let highlightText: String
    let trendText: String
    let detailLevel: ReportShareDetailLevel

    private var includesHealthDetails: Bool {
        detailLevel == .detailed
    }

    private var progress: CGFloat {
        min(max(CGFloat(score) / 100, 0), 1)
    }

    private var scoreText: String {
        score > 0 ? "\(score)" : "--"
    }

    private var scorePercentText: String {
        score > 0 ? "\(score)%" : "--%"
    }

    private var sleepText: String {
        guard includesHealthDetails else { return "--" }
        return summary?.sleepHours.map { String(format: "%.1fh", $0) } ?? "--h"
    }

    private var stressText: String {
        guard includesHealthDetails else { return "--" }
        return summary?.stress.map { "\(Int($0.rounded()))" } ?? "--"
    }

    private var hrvText: String {
        guard includesHealthDetails else { return "--" }
        return summary?.hrv.map { "\(Int($0.rounded()))ms" } ?? "--ms"
    }

    private var stepsText: String {
        guard includesHealthDetails else { return "--" }
        guard let steps = summary?.steps else { return "--步" }
        return String(localized: "\(Int(steps.rounded()))步")
    }

    private var energyText: String {
        guard includesHealthDetails else { return "--" }
        guard let energy = summary?.activeEnergy else { return "--kcal" }
        return "\(Int(energy.rounded()))kcal"
    }

    private var moodText: String {
        switch score {
        case 85...: return "稳定"
        case 70..<85: return "平稳"
        case 50..<70: return "波动"
        case 1..<50: return "承压"
        default: return "待记录"
        }
    }

    private var adviceItems: [String] {
        let items = summary?.adviceSummary?.actionItems ?? []
        if items.isEmpty {
            return ["保持补水", "早点休息", "轻活动 10min"]
        }
        return Array(items.prefix(3))
    }

    var body: some View {
        VStack(spacing: 0) {
            notebook
        }
        .padding(20)
        .background(Theme.Colors.secondarySurface)
    }

    private var notebook: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "doc.text.fill")
                    .font(.appSystem(size: 18, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color(hex: "DCA91F"), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("眠屿")
                        .font(.appSystem(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.black)

                    Text("每日健康报告 · \(reportDate.reportsFullDateString())")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "686B67"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.top, 30)
            .padding(.bottom, 18)

            Rectangle()
                .fill(Color(hex: "D9D5CF"))
                .frame(height: 1)
                .padding(.horizontal, 10)

            posterNarrativeSummary

            HStack(alignment: .top, spacing: 0) {
                leftColumn
                    .frame(maxWidth: .infinity, alignment: .top)

                Rectangle()
                    .fill(Color(hex: "D9D5CF"))
                    .frame(width: 1)

                rightColumn
                    .frame(maxWidth: .infinity, alignment: .top)
            }

            Rectangle()
                .fill(Color(hex: "D9D5CF"))
                .frame(height: 1)
                .padding(.horizontal, 10)

            brandFooter
        }
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var posterNarrativeSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日结论")
                .font(.appSystem(size: 11, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "7868A7"))

            Text(highlightText)
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)

            Text(trendText)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "5F625F"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color(hex: "F1EEFA"))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: "D9D5CF"))
                .frame(height: 1)
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHealthDetails {
                posterSection(title: "心情", icon: "sparkle", tint: Color(hex: "F5C53D")) {
                    posterRow(title: "心情", value: moodText, icon: "face.smiling.fill", tint: Color(hex: "FFC84A"))
                    posterRow(title: "睡眠", value: sleepText, icon: "moon.zzz.fill", tint: Color(hex: "8ECDF5"))
                    posterRow(title: "压力", value: stressText, icon: "brain.head.profile", tint: Color(hex: "D8A08F"))
                    posterRow(title: "HRV", value: hrvText, icon: "waveform.path.ecg", tint: Color(hex: "B7D0C8"))
                }
            }

            posterSection(title: "恢复", icon: "drop.fill", tint: Color(hex: "78A8F5")) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(scoreText)
                            .font(.appSystem(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(.black)
                        Text("综合评分")
                            .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "4C4C4C"))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "heart.circle.fill")
                        .font(.appSystem(size: 34, weight: .black))
                        .foregroundColor(Color(hex: "8ECDF5"))
                }
            }

            if includesHealthDetails {
                posterSection(title: "运动", icon: "figure.walk.circle.fill", tint: Color(hex: "7DA9A0")) {
                    posterValueLine(title: "步数", value: stepsText)
                    posterDashedDivider()
                    posterValueLine(title: "活动能量", value: energyText)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 24)
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHealthDetails {
                posterSection(title: "体征", icon: "flame.fill", tint: Color(hex: "FF5F52")) {
                    posterValueLine(title: "压力指数", value: stressText)
                    posterValueLine(title: "心率变异", value: hrvText)
                }
            }

            posterSection(title: "进度", icon: "flame.fill", tint: Color(hex: "FF5F52")) {
                HStack {
                    Text("目标评分 85")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    Spacer(minLength: 0)
                    Text(scorePercentText)
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(.black)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: "DEDEDE"))
                        Capsule()
                            .fill(Color(hex: "FFB24C"))
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 10)
                .padding(.top, 10)
            }

            posterSection(title: "建议", icon: "takeoutbag.and.cup.and.straw.fill", tint: Color(hex: "E7D9B6")) {
                ForEach(Array(adviceItems.enumerated()), id: \.offset) { index, item in
                    posterValueLine(title: index == 0 ? "优先" : index == 1 ? "其次" : "其他", value: item)
                    if index < adviceItems.count - 1 {
                        posterDashedDivider()
                            .padding(.vertical, 20)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 24)
    }

    private var brandFooter: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "DCA91F"))

                Image(systemName: "doc.text.fill")
                    .font(.appSystem(size: 20, weight: .black))
                    .foregroundColor(.white)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text("眠屿")
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "54575D"))
                Text("每日健康报告")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.black)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func posterSection<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.appSystem(size: 15, weight: .black))
                    .foregroundColor(tint)
                    .frame(width: 20)
                Text(title)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.black)
            }

            content()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: "D9D5CF"))
                .frame(height: 1)
        }
    }

    private func posterRow(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.black)

                Spacer(minLength: 0)

                Text(value)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "4B4B4B"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Image(systemName: icon)
                    .font(.appSystem(size: 18, weight: .black))
                    .foregroundColor(tint.opacity(0.9))
                    .frame(width: 22)
            }

            posterDashedDivider()
        }
    }

    private func posterValueLine(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.black)

            Spacer(minLength: 0)

            Text(value)
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
    }

    private func posterDashedDivider() -> some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [7, 5]))
            .foregroundColor(Color(hex: "D9D5CF"))
            .frame(height: 1)
    }
}

private struct ReportActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ReportShareFeedback: Identifiable {
    let id = UUID()
    let message: String
}

private extension Date {
    func shareHeaderDateString(locale: Locale = Locale.autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "M月d日 EEE"
        return formatter.string(from: self)
    }
}

#Preview {
    ReportShareView(reportDate: Date(), score: 82)
}
