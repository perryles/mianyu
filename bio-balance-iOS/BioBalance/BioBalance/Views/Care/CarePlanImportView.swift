/// CarePlanImportView 负责从 JSON 文件导入医生照护计划。
///
/// 支持两种导入方式：
/// 1. JSON 文件选择（通过 UIDocumentPickerViewController）
/// 2. 文本粘贴
///
/// 导入流程：
/// 1. 读取 JSON → 解析为 CarePlanImportDocument
/// 2. 预览页面：逐条展示任务详情，用户可取消勾选
/// 3. 确认导入：批量创建 CareTask
/// 4. 重复导入检测：同一 source 标记不重复创建

import SwiftUI
import UniformTypeIdentifiers

struct CarePlanImportView: View {
    @State private var jsonText: String = ""
    @State private var parsedDocument: CarePlanImportDocument?
    @State private var confirmedTasks: Set<String> = []  // task IDs to import
    @State private var draftTasks: [CareTask] = []
    @State private var errorMessage: String?
    @State private var showFilePicker: Bool = false
    @State private var showSample: Bool = false
    @State private var importResult: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if parsedDocument == nil {
                    inputSection
                } else {
                    previewSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "导入照护计划"))
        .navigationBarTitleDisplayMode(.large)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleFileResult(result)
        }
    }

    // MARK: - 输入区

    @ViewBuilder
    private var inputSection: some View {
        VStack(spacing: 16) {
            BBTitledCard(
                title: String(localized: "从医生或照护团队获取计划"),
                subtitle: String(localized: "支持标准 JSON 格式的照护计划文件"),
                systemImage: "square.and.arrow.down",
                tint: Theme.Colors.mintGreen
            ) {
                VStack(spacing: 12) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label(String(localized: "选择 JSON 文件"), systemImage: "doc")
                            .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.Colors.mintGreen)
                            )
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Text(String(localized: "或粘贴 JSON 内容"))
                        .font(.appSystem(size: 13, weight: .medium))
                        .foregroundColor(Theme.Colors.textTertiary)

                    TextEditor(text: $jsonText)
                        .font(.appSystem(size: 13, design: .monospaced))
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
                        )

                    if !jsonText.isEmpty {
                        Button {
                            parseText()
                        } label: {
                            Label(String(localized: "解析 JSON"), systemImage: "doc.text.magnifyingglass")
                                .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.Colors.mintGreen)
                        }
                    }

                    Button {
                        showSample.toggle()
                    } label: {
                        Label(String(localized: "查看示例格式"), systemImage: "questionmark.circle")
                            .font(.appSystem(size: 13, weight: .medium))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }

            if showSample {
                sampleCard
            }

            if let errorMessage {
                BBCard(style: .standard, tint: .red) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.appSystem(size: 13, weight: .medium))
                            .foregroundColor(.red)
                    }
                }
            }

            if let importResult {
                BBCard(style: .standard, tint: .green) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(importResult)
                            .font(.appSystem(size: 13, weight: .medium))
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sampleCard: some View {
        BBTitledCard(
            title: String(localized: "示例 JSON"),
            systemImage: "doc.text",
            tint: Theme.Colors.mintGreen
        ) {
            Text(CarePlanImporter.sampleJSON)
                .font(.appSystem(size: 11, design: .monospaced))
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }

    // MARK: - 预览区

    @ViewBuilder
    private var previewSection: some View {
        VStack(spacing: 16) {
            if let document = parsedDocument {
                BBTitledCard(
                    title: document.source,
                    subtitle: "\(document.tasks.count) \(String(localized: "项任务待确认"))",
                    systemImage: "doc.text.magnifyingglass",
                    tint: Theme.Colors.mintGreen
                ) {
                    HStack(spacing: 12) {
                        Button(String(localized: "全部选中")) {
                            confirmedTasks = Set(document.tasks.map(\.id))
                        }
                        .font(.appSystem(size: 13, weight: .semibold))
                        .foregroundColor(Theme.Colors.mintGreen)

                        Button(String(localized: "取消全部")) {
                            confirmedTasks.removeAll()
                        }
                        .font(.appSystem(size: 13, weight: .medium))
                        .foregroundColor(Theme.Colors.textTertiary)

                        Spacer()

                        Button {
                            confirmImport()
                        } label: {
                            Text(String(localized: "确认导入 (\(confirmedTasks.count))"))
                                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(confirmedTasks.isEmpty ? Color.gray : Theme.Colors.mintGreen)
                                )
                        }
                        .disabled(confirmedTasks.isEmpty)
                    }
                }

                ForEach(document.tasks) { task in
                    importTaskRow(task)
                }

                Button(String(localized: "重新选择")) {
                    parsedDocument = nil
                    draftTasks = []
                    confirmedTasks = []
                    jsonText = ""
                    errorMessage = nil
                }
                .font(.appSystem(size: 13, weight: .medium))
                .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func importTaskRow(_ task: CarePlanImportTask) -> some View {
        let isSelected = confirmedTasks.contains(task.id)
        let category = CareTaskCategory(rawValue: task.category) ?? .habit
        let color = categoryColor(category)

        BBCard(style: .standard, tint: isSelected ? color : nil) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.appSystem(size: 18))
                        .foregroundColor(isSelected ? color : Theme.Colors.textTertiary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)

                        HStack(spacing: 6) {
                            categoryBadge(category, color: color)
                            if let target = task.targetValue, let unit = task.unit {
                                Text("\(formattedNumber(target)) \(unit)")
                                    .font(.appSystem(size: 12, weight: .medium))
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                    }

                    Spacer()
                }

                if let instructions = task.instructions {
                    Text(instructions)
                        .font(.appSystem(size: 12))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(2)
                        .padding(.leading, 28)
                }

                schedulePreview(task.schedule)
                    .padding(.leading, 28)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                confirmedTasks.remove(task.id)
            } else {
                confirmedTasks.insert(task.id)
            }
        }
    }

    @ViewBuilder
    private func categoryBadge(_ category: CareTaskCategory, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: category.symbol)
                .font(.appSystem(size: 10, weight: .bold))
            Text(category.shortTitle)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    @ViewBuilder
    private func schedulePreview(_ schedule: CarePlanImportSchedule) -> some View {
        let times = schedule.slots.map { String(format: "%02d:%02d", $0.hour, $0.minute) }.joined(separator: " ")
        Text(times)
            .font(.appSystem(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(Theme.Colors.textTertiary)
    }

    // MARK: - 操作

    private func parseText() {
        errorMessage = nil
        do {
            let document = try CarePlanImporter.parse(json: jsonText)
            if CarePlanImporter.isAlreadyImported(source: document.source) {
                errorMessage = String(localized: "来源「\(document.source)」已经导入过，确认后会合并")
            }
            parsedDocument = document
            draftTasks = CarePlanImporter.toDraftTasks(document)
            confirmedTasks = Set(document.tasks.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmImport() {
        guard let document = parsedDocument else { return }
        let tasksToImport = draftTasks.enumerated().compactMap { index, task -> CareTask? in
            guard index < document.tasks.count else { return nil }
            let importTask = document.tasks[index]
            return confirmedTasks.contains(importTask.id) ? task : nil
        }

        let count = CarePlanImporter.importConfirmed(tasksToImport)
        importResult = String(localized: "成功导入 \(count) 项任务")
        parsedDocument = nil
        draftTasks = []
        confirmedTasks = []
        jsonText = ""
    }

    private func handleFileResult(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            let document = try CarePlanImporter.parse(data: data)
            parsedDocument = document
            draftTasks = CarePlanImporter.toDraftTasks(document)
            confirmedTasks = Set(document.tasks.map(\.id))
            errorMessage = nil
        } catch let error as CarePlanImporter.ImportError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 辅助方法

    private func categoryColor(_ category: CareTaskCategory) -> Color {
        switch category {
        case .medication: return .orange
        case .rehabilitation: return .blue
        case .habit: return .green
        case .symptom: return .purple
        }
    }

    private func formattedNumber(_ value: Double) -> String {
        if floor(value) == value { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }
}
