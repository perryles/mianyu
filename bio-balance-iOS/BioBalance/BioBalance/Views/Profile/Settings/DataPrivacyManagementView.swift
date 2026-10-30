import SwiftUI
import UIKit

/// DataPrivacyManagementView 是「设置 → 数据管理」页面。
///
/// 承载两类隐私能力（均为破坏性/导出操作，文案明确说明）：
/// - 导出我的数据：按域白名单生成 JSON / CSV，通过系统分享面板存到 Files 或分享；
/// - 删除我的数据：二次确认后删除本地 SwiftData 与当前 Apple ID 私有 CloudKit 记录。
///
/// 隐私约束：文字全部静态展示，不加任何动效；导出只含白名单聚合字段；
/// 删除过程只报告 zone/domain 与数量，不展示任何健康明细。
struct DataPrivacyManagementView: View {
    @State private var audit: UserDataAuditReport?
    @State private var selectedFormat: UserDataExportFormat = .json
    @State private var isGeneratingExport = false
    @State private var exportItem: DataPrivacyShareItem?
    @State private var exportErrorMessage: String?

    @State private var deletionFlow = DataPrivacyDeletionFlow(
        deletion: { await UserDataDeletionService.shared.deleteAllData() }
    )
    @State private var showFirstDeleteConfirmation = false
    @State private var showFinalDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deletionReport: UserDataDeletionReport?
    @State private var deleteErrorMessage: String?

    var body: some View {
        ProfileSettingsPage(title: "数据管理", subtitle: "查看、导出或删除你在本机与 iCloud 中的数据。") {
            VStack(spacing: 16) {
                dataOverviewCard
                exportCard
                deleteCard
            }
        }
        .task { await refreshAudit() }
        .sheet(item: $exportItem) { item in
            DataPrivacyActivityView(items: [item.url])
        }
        .alert("删除我的数据", isPresented: $showFirstDeleteConfirmation) {
            Button("取消", role: .cancel) {
                deletionFlow.cancelDeletion()
            }
            Button("继续", role: .destructive) {
                deletionFlow.proceedToFinalConfirmation()
                showFinalDeleteConfirmation = true
            }
        } message: {
            Text("将删除本机 SwiftData 记录，以及当前 Apple ID 私有 iCloud 中对应的记录（含好友共享与公开资料）。此操作不可撤销，请谨慎操作。")
        }
        .alert("最后确认", isPresented: $showFinalDeleteConfirmation) {
            Button("取消", role: .cancel) {
                deletionFlow.cancelDeletion()
            }
            Button("彻底删除", role: .destructive) {
                Task { await performDeletion() }
            }
        } message: {
            Text("这是最后一次确认：所有个人数据（不含健康原始明细，健康 App 数据需在系统设置中单独管理）将被永久删除。")
        }
    }

    // MARK: - 数据概览

    private var dataOverviewCard: some View {
        SettingsSectionCard(title: "数据概览") {
            VStack(alignment: .leading, spacing: 6) {
                if let audit {
                    Text("共 \(audit.totalRecordCount) 条本机记录，分布于 \(audit.domainSummaries.count) 个数据域")
                        .font(Theme.Typography.bodyMedium)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    if audit.domainSummaries.isEmpty {
                        Text("暂无本地业务数据")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    } else {
                        ForEach(audit.domainSummaries, id: \.domain) { summary in
                            DataPrivacyDomainRow(summary: summary)
                            if summary.domain != audit.domainSummaries.last?.domain {
                                Divider().padding(.leading, 16)
                            }
                        }
                        .padding(.bottom, 6)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 18)
                }
            }
        }
    }

    // MARK: - 导出

    private var exportCard: some View {
        SettingsSectionCard(title: "导出我的数据") {
            VStack(alignment: .leading, spacing: 10) {
                Text("导出的 JSON/CSV 仅包含你自己的白名单聚合字段（情绪、咖啡因、打卡、评估分数、餐饮、用药等结构化记录），不含健康原始明细、图片、精确位置与自由文本备注。")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                Picker("导出格式", selection: $selectedFormat) {
                    Text("JSON").tag(UserDataExportFormat.json)
                    Text("CSV").tag(UserDataExportFormat.csv)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                Button {
                    generateExport()
                } label: {
                    HStack(spacing: 8) {
                        if isGeneratingExport {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up.fill")
                        }
                        Text(isGeneratingExport ? "正在生成…" : "生成导出文件")
                            .font(Theme.Typography.bodyMedium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.Colors.mintGreen, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingExport)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

                if let exportErrorMessage {
                    DataPrivacyFeedbackRow(message: exportErrorMessage, isError: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    // MARK: - 删除

    private var deleteCard: some View {
        SettingsSectionCard(title: "删除我的数据") {
            VStack(alignment: .leading, spacing: 10) {
                Text("删除本机 SwiftData 记录与当前 Apple ID 私有 iCloud 中的对应记录（含好友共享 zone 与公开资料，公开资料为尽力清理）。删除前需二次确认；iCloud 不可用时云端数据会保留并提示重试。此操作不可撤销。")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                Button {
                    deletionFlow.requestDeletion()
                    showFirstDeleteConfirmation = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                        Text("删除我的数据")
                            .font(Theme.Typography.bodyMedium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.Colors.accentRed.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundColor(Theme.Colors.accentRed)
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

                if isDeleting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在删除本地与 iCloud 数据…")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }

                if let deleteErrorMessage {
                    DataPrivacyFeedbackRow(message: deleteErrorMessage, isError: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                if let deletionReport {
                    DataPrivacyDeletionResultView(report: deletionReport)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
            }
        }
    }

    // MARK: - 动作

    private func refreshAudit() async {
        audit = UserDataAuditService.shared.audit()
    }

    private func generateExport() {
        guard !isGeneratingExport else { return }
        isGeneratingExport = true
        exportErrorMessage = nil
        Task {
            defer { isGeneratingExport = false }
            do {
                let url = try UserDataExportService.shared.generateExport(format: selectedFormat)
                exportItem = DataPrivacyShareItem(url: url)
            } catch {
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    private func performDeletion() async {
        guard !isDeleting else { return }
        isDeleting = true
        deleteErrorMessage = nil
        deletionReport = nil
        defer { isDeleting = false }

        await deletionFlow.confirmFinalDeletion()
        guard let report = deletionFlow.lastReport else { return }
        deletionReport = report
        if report.cloudFailureCount > 0 {
            deleteErrorMessage = "部分 iCloud 数据删除失败，可稍后重试（删除是幂等的）。"
        } else if report.cloudUnavailable {
            deleteErrorMessage = "iCloud 当前不可用，已删除本机数据；请登录 iCloud 后重试以清理云端数据。"
        }
        await refreshAudit()
    }
}

/// 数据域一行概览。
private struct DataPrivacyDomainRow: View {
    let summary: UserDataDomainSummary

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.displayName)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(rangeText)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            Spacer(minLength: 8)
            Text("\(summary.recordCount) 条")
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var rangeText: String {
        guard let earliest = summary.earliestAt, let latest = summary.latestAt else {
            return "无时间范围"
        }
        return "\(Self.dayText(earliest)) 至 \(Self.dayText(latest))"
    }

    private static func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("yyyyMd")
        return formatter.string(from: date)
    }
}

/// 删除结果逐 zone 展示。
private struct DataPrivacyDeletionResultView: View {
    let report: UserDataDeletionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("删除结果")
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            HStack(spacing: 8) {
                Image(systemName: report.isFullyCleared ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(report.isFullyCleared ? Theme.Colors.mintGreen : Color(hex: "E3A045"))
                Text(report.localSwiftDataCleared
                     ? "本机数据已清除（\(report.localRecordCount) 条）"
                     : "本机数据清除失败，请重试")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            ForEach(report.cloudResults, id: \.zoneName) { result in
                HStack(spacing: 8) {
                    Image(systemName: Self.icon(for: result.state))
                        .foregroundColor(Self.color(for: result.state))
                    Text(Self.text(for: result))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(12)
        .background(Theme.Colors.secondaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static func icon(for state: CloudZoneDeletionResult.State) -> String {
        switch state {
        case .deleted, .completed: "checkmark.circle.fill"
        case .unavailable: "icloud.slash.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private static func color(for state: CloudZoneDeletionResult.State) -> Color {
        switch state {
        case .deleted, .completed: Theme.Colors.mintGreen
        case .unavailable: Color(hex: "8A96AA")
        case .failed: Color(hex: "E3A045")
        }
    }

    private static func text(for result: CloudZoneDeletionResult) -> String {
        let zoneLabel = result.zoneName
        switch result.state {
        case .deleted:
            return "\(zoneLabel)：已清除 \(result.recordCount) 条"
        case .completed:
            return "\(zoneLabel)：\(result.message ?? "已完成")"
        case .unavailable:
            return "\(zoneLabel)：iCloud 不可用，跳过"
        case .failed:
            return "\(zoneLabel)：删除失败，请重试"
        }
    }
}

/// 导出/删除的提示行。
private struct DataPrivacyFeedbackRow: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? Color(hex: "E3A045") : Theme.Colors.mintGreen)
            Text(message)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 分享面板承载的导出文件。
private struct DataPrivacyShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIActivityViewController 包装：支持「存储到文件」与系统分享。
private struct DataPrivacyActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        DataPrivacyManagementView()
    }
    .environment(AppFontScaleStore.shared)
}
