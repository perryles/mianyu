/// CarePlanImporter 负责把外部 JSON 照护计划导入为 CareTask。
///
/// 支持两种导入来源：
/// 1. 本地 JSON 文件（通过 .json importing 扩展）
/// 2. App 内文本粘贴
///
/// 导入流程：
/// 1. parse(json:) → CarePlanImportDocument
/// 2. previewAndConfirm → 用户在 CarePlanImportView 逐条确认
/// 3. importConfirmed → 批量创建 CareTask（带 sourceImportID）
/// 4. 重复导入同一 source 时合并而非重复创建

import Foundation

// MARK: - 导入文档

nonisolated struct CarePlanImportDocument: Codable, Sendable {
    var schemaVersion: Int
    var source: String
    var issuedAt: Date?
    var tasks: [CarePlanImportTask]
}

nonisolated struct CarePlanImportTask: Codable, Sendable, Identifiable, Hashable {
    var id: String { UUID().uuidString }  // 临时 ID，仅供列表展示
    var category: String         // "rehabilitation", "habit", "symptom"
    var title: String
    var subtitle: String?
    var icon: String?
    var schedule: CarePlanImportSchedule
    var targetValue: Double?
    var unit: String?
    var instructions: String?
    var linkedModule: String?
}

nonisolated struct CarePlanImportSchedule: Codable, Sendable, Hashable {
    struct Slot: Codable, Sendable, Hashable {
        var hour: Int
        var minute: Int
        var durationMinutes: Int?
    }

    var isEnabled: Bool?
    var slots: [Slot]
    var weekdays: [Int]?
    var frequency: String?       // "daily", "weekly", "customInterval"
    var customIntervalDays: Int?
    var startDate: Date?
    var endDate: Date?
}

// MARK: - 导入器

nonisolated enum CarePlanImporter {

    nonisolated enum ImportError: LocalizedError, Sendable {
        case invalidJSON(String)
        case unsupportedSchema(Int)
        case emptyTasks
        case invalidCategory(String)
        case parseFailure(String)

        var errorDescription: String? {
            switch self {
            case .invalidJSON(let detail):
                return String(localized: "JSON 格式有误：\(detail)")
            case .unsupportedSchema(let version):
                return String(localized: "不支持的 schema 版本：\(version)，当前仅支持版本 1")
            case .emptyTasks:
                return String(localized: "文件中没有可导入的照护任务")
            case .invalidCategory(let raw):
                return String(localized: "未知的任务类别：\(raw)")
            case .parseFailure(let detail):
                return String(localized: "解析失败：\(detail)")
            }
        }
    }

    /// 解析 JSON 文本
    static func parse(json text: String) throws -> CarePlanImportDocument {
        guard let data = text.data(using: .utf8) else {
            throw ImportError.invalidJSON(String(localized: "无法读取文本内容"))
        }
        return try parse(data: data)
    }

    /// 解析 JSON Data
    static func parse(data: Data) throws -> CarePlanImportDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let doc = try decoder.decode(CarePlanImportDocument.self, from: data)
            guard doc.schemaVersion == 1 else {
                throw ImportError.unsupportedSchema(doc.schemaVersion)
            }
            guard !doc.tasks.isEmpty else {
                throw ImportError.emptyTasks
            }
            // 验证 category
            for task in doc.tasks {
                guard CareTaskCategory(rawValue: task.category) != nil else {
                    throw ImportError.invalidCategory(task.category)
                }
            }
            return doc
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.parseFailure(error.localizedDescription)
        }
    }

    /// 把导入文档中的任务转换为引擎可用的 CareTask（待确认草稿）
    static func toDraftTasks(_ document: CarePlanImportDocument) -> [CareTask] {
        let now = Date()
        return document.tasks.compactMap { importTask in
            guard let category = CareTaskCategory(rawValue: importTask.category) else { return nil }

            let schedule = CareSchedule(
                isEnabled: importTask.schedule.isEnabled ?? true,
                slots: importTask.schedule.slots.map { slot in
                    CareSchedule.TimeSlot(
                        hour: slot.hour,
                        minute: slot.minute,
                        durationMinutes: slot.durationMinutes ?? 0
                    )
                },
                weekdays: Set(importTask.schedule.weekdays ?? []),
                frequency: CareScheduleFrequency(rawValue: importTask.schedule.frequency ?? "daily") ?? .daily,
                customIntervalDays: importTask.schedule.customIntervalDays ?? 1,
                startDate: importTask.schedule.startDate ?? now,
                endDate: importTask.schedule.endDate
            )

            return CareTask(
                category: category,
                title: importTask.title,
                subtitle: importTask.subtitle,
                icon: importTask.icon,
                schedule: schedule,
                targetValue: importTask.targetValue,
                unit: importTask.unit,
                instructions: importTask.instructions,
                linkedModule: importTask.linkedModule,
                sourceImportID: document.source
            )
        }
    }

    /// 确认导入：批量保存已确认的任务
    @MainActor
    @discardableResult
    static func importConfirmed(_ tasks: [CareTask]) -> Int {
        let engine = CareTaskEngine.shared
        var savedCount = 0
        for task in tasks {
            engine.saveTask(task)
            savedCount += 1
        }
        return savedCount
    }

    /// 检查同一来源是否已经导入过
    @MainActor
    static func isAlreadyImported(source: String) -> Bool {
        !CareTaskEngine.shared.allTaskVersions().filter { $0.sourceImportID == source }.isEmpty
    }

    /// 示例 JSON 模板，供 UI 层展示
    static let sampleJSON = """
    {
      "schemaVersion": 1,
      "source": "Dr.Zhang_2026-08-01",
      "issuedAt": "2026-08-01T10:00:00Z",
      "tasks": [
        {
          "category": "rehabilitation",
          "title": "颈椎康复训练",
          "icon": "figure.cooldown",
          "schedule": {
            "isEnabled": true,
            "slots": [{"hour": 9, "minute": 0, "durationMinutes": 15}],
            "weekdays": [2,4,6],
            "frequency": "weekly"
          },
          "targetValue": 15,
          "unit": "分钟",
          "instructions": "缓慢颈部旋转，每个方向5次"
        },
        {
          "category": "habit",
          "title": "晒太阳",
          "icon": "sun.max.fill",
          "schedule": {
            "isEnabled": true,
            "slots": [{"hour": 10, "minute": 0, "durationMinutes": 20}],
            "frequency": "daily"
          },
          "targetValue": 20,
          "unit": "分钟",
          "linkedModule": "sunlight"
        }
      ]
    }
    """
}
