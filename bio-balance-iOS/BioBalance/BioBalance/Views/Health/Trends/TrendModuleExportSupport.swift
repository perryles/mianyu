/// TrendExportModuleDescriptor 作为共享界面层的支撑类型，负责定义趋势模块导出描述符。
/// 负责描述分类、标题、范围、状态、摘要、配色与导出文件前缀。

import SwiftUI
import UIKit

/// 趋势Export模块Descriptor结构体 作为共享界面层里的辅助类型。
/// 负责共享布局与通用界面能力。
struct TrendExportModuleDescriptor: Identifiable, Hashable {
    let id = UUID()
    let category: TrendCategoryID
    let moduleTitle: String
    let rangeTitle: String
    let statusTitle: String
    let summary: String
    let accentColor: Color
    let exportFilePrefix: String
}

/// 趋势模块Export错误枚举 作为共享界面层里的错误状态定义。
/// 负责描述共享布局与通用界面能力过程中会用到的状态、分类或分支。
enum TrendModuleExportError: LocalizedError {
    case noContent
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .noContent:
            return String(localized: "当前模块暂无可导出的内容。")
        case .renderFailed:
            return String(localized: "PDF 生成失败，请稍后重试。")
        }
    }
}

/// 趋势模块PDFExporter枚举 作为共享界面层里的能力或分类定义。
/// 负责描述共享布局与通用界面能力过程中会用到的状态、分类或分支。
@MainActor
enum TrendModulePDFExporter {
    static func export<Content: View>(
        descriptor: TrendExportModuleDescriptor,
        displayScale: CGFloat,
        content: Content
    ) throws -> URL {
        let renderer = ImageRenderer(content: TrendModulePDFPage(descriptor: descriptor) { content })
        renderer.scale = displayScale

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let image = renderer.uiImage else {
            throw TrendModuleExportError.noContent
        }

        let safePrefix = descriptor.exportFilePrefix.replacingOccurrences(of: " ", with: "-")
        let filename = "\(safePrefix)-\(timestampString()).pdf"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let format = UIGraphicsPDFRendererFormat()
        let rendererPDF = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        do {
            try rendererPDF.writePDF(to: outputURL) { context in
                context.beginPage()
                image.draw(in: pageRect)
            }
        } catch {
            throw TrendModuleExportError.renderFailed
        }

        return outputURL
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

/// 趋势Exportable区块组件 作为共享界面层里的布局区块组件。
/// 负责共享布局与通用界面能力。
struct TrendExportableSection<Content: View, ExportContent: View>: View {
    @Environment(\.displayScale) private var displayScale
    let descriptor: TrendExportModuleDescriptor
    let content: Content
    let exportContent: ExportContent

    @State private var isExporting = false
    @State private var exportItem: ShareSheetItem?
    @State private var exportErrorMessage: String?

    init(
        descriptor: TrendExportModuleDescriptor,
        @ViewBuilder content: () -> Content,
        @ViewBuilder exportContent: () -> ExportContent
    ) {
        self.descriptor = descriptor
        self.content = content()
        self.exportContent = exportContent()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.moduleTitle)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(descriptor.summary)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    exportPDF()
                } label: {
                    HStack(spacing: 6) {
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Theme.Colors.onAccent)
                                .scaleEffect(0.78)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .bold))
                        }

                        Text(isExporting ? "导出中" : "导出 PDF")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [descriptor.accentColor, descriptor.accentColor.opacity(0.72)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(isExporting)
            }

            content
        }
        .sheet(item: $exportItem) { item in
            ActivityViewController(items: [item.url])
        }
        .alert("导出失败", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    private func exportPDF() {
        guard !isExporting else { return }
        isExporting = true

        Task { @MainActor in
            defer { isExporting = false }
            do {
                exportItem = ShareSheetItem(url: try TrendModulePDFExporter.export(
                    descriptor: descriptor,
                    displayScale: displayScale,
                    content: exportContent
                ))
            } catch {
                exportErrorMessage = (error as? LocalizedError)?.errorDescription ?? TrendModuleExportError.renderFailed.localizedDescription
            }
        }
    }
}

private struct ShareSheetItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct TrendModulePDFPage<Content: View>: View {
    let descriptor: TrendExportModuleDescriptor
    let content: Content

    init(descriptor: TrendExportModuleDescriptor, @ViewBuilder content: () -> Content) {
        self.descriptor = descriptor
        self.content = content()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white, descriptor.accentColor.opacity(0.05), Color(hex: "F7FAFF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(descriptor.category.title)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(descriptor.accentColor)
                            Text(descriptor.moduleTitle)
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: descriptor.category.icon)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(descriptor.accentColor)
                            .frame(width: 52, height: 52)
                            .background(descriptor.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    HStack(spacing: 8) {
                        pdfMetaPill(text: descriptor.rangeTitle)
                        pdfMetaPill(text: descriptor.statusTitle)
                    }

                    Text(descriptor.summary)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content

                HealthDisclaimerCard(
                    message: "本页趋势、AI 洞察与健康解读仅供日常自我管理参考，不构成医疗诊断或治疗建议。",
                    style: .compact,
                    strokeColor: Color.white.opacity(0.88),
                    backgroundColor: Color.white.opacity(0.88),
                    showsIcon: false
                )
            }
            .padding(26)
        }
        .frame(width: 595, height: 842, alignment: .topLeading)
    }

    private func pdfMetaPill(text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(descriptor.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(descriptor.accentColor.opacity(0.10), in: Capsule())
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
