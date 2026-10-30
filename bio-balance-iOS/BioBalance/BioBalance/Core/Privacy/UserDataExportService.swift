import Foundation
import os

/// 单个导出记录的字段投影值（白名单过滤后的 JSON 安全值）。
nonisolated enum UserDataExportValue: Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([UserDataExportValue])
    case object([String: UserDataExportValue])
}

/// 导出服务：把本机 SwiftData 业务记录按「域白名单」投影为 JSON / CSV 文件。
///
/// ## 隐私边界
/// - 只导出 `UserDataPrivacyRegistry.exportWhitelist(for:)` 白名单内且实际存在的字段；
/// - 内部基础设施域（`local-sync-outbox` / `app-data-cache`）不导出；
/// - 不含健康原始明细：自由文本、图片/文件引用、精确位置、HealthKit 样本引用、
///   AI 元数据均不在白名单内，天然被过滤；
/// - 导出过程日志只记录域名与记录数，不记录任何内容。
@MainActor
final class UserDataExportService {
    static let shared = UserDataExportService()

    private let recordStore: SwiftDataRecordStore

    init(recordStore: SwiftDataRecordStore? = nil) {
        self.recordStore = recordStore ?? SwiftDataRecordStore()
    }

    /// 生成本机全量业务数据的导出文件，返回临时目录中的文件 URL（供分享/存储）。
    func generateExport(
        format: UserDataExportFormat,
        now: Date = Date()
    ) throws -> URL {
        let snapshots = recordStore.allRecords()
            .filter { !UserDataPrivacyRegistry.internalDomains.contains($0.domain) }

        let grouped = Dictionary(grouping: snapshots, by: \.domain)
        let data: Data
        switch format {
        case .json:
            data = try Self.makeJSONExport(grouped: grouped, now: now)
        case .csv:
            data = try Self.makeCSVExport(grouped: grouped, now: now)
        }

        let filename = "mianyu-data-export-\(Self.timestamp(now)).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)

        UserDataPrivacyLogger.info(
            "export format=\(format.rawValue) domains=\(grouped.count) records=\(snapshots.count)"
        )
        return url
    }

    // MARK: - JSON 导出

    static func makeJSONExport(
        grouped: [String: [LocalDataRecordSnapshot]],
        now: Date
    ) throws -> Data {
        var domains: [String: Any] = [:]
        for domain in grouped.keys.sorted() {
            let rows = grouped[domain] ?? []
            let dates = rows.compactMap(\.occurredAt)
            let records: [[String: Any]] = rows.map { row in
                var record: [String: Any] = [
                    "kind": row.kind,
                    "recordID": row.recordID,
                    "occurredAt": Self.isoDate(row.occurredAt),
                    "updatedAt": Self.isoDate(row.updatedAt)
                ]
                let whitelist = UserDataPrivacyRegistry.exportWhitelist(for: domain)
                let fields = Self.project(payload: row.payload, whitelist: whitelist)
                if let fields, !fields.isEmpty {
                    record["fields"] = Self.jsonValueToAny(.object(fields))
                }
                return record
            }
            domains[domain] = [
                "displayName": UserDataPrivacyRegistry.displayName(for: domain),
                "recordCount": rows.count,
                "earliestAt": dates.min().map(Self.isoDate) ?? NSNull(),
                "latestAt": dates.max().map(Self.isoDate) ?? NSNull(),
                "records": records
            ]
        }

        let root: [String: Any] = [
            "app": "眠屿 - 安静的小岛",
            "exportedAt": Self.isoDate(now),
            "formatVersion": 1,
            "dataBoundary": "仅包含当前用户自己的白名单聚合字段，不含健康原始明细",
            "domains": domains
        ]
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    // MARK: - CSV 导出

    static func makeCSVExport(
        grouped: [String: [LocalDataRecordSnapshot]],
        now: Date
    ) throws -> Data {
        // 先收集所有记录的白名单扁平字段名，生成统一列头。
        var flattenedRows: [(domain: String, kind: String, recordID: String, occurredAt: Date, updatedAt: Date, flat: [String: String])] = []
        var allKeys = Set<String>()

        for domain in grouped.keys.sorted() {
            let whitelist = UserDataPrivacyRegistry.exportWhitelist(for: domain)
            for row in grouped[domain] ?? [] {
                let projected = Self.project(payload: row.payload, whitelist: whitelist)
                let flat = Self.flatten(projected)
                allKeys.formUnion(flat.keys)
                flattenedRows.append((
                    domain: domain,
                    kind: row.kind,
                    recordID: row.recordID,
                    occurredAt: row.occurredAt,
                    updatedAt: row.updatedAt,
                    flat: flat
                ))
            }
        }

        let columns = ["domain", "kind", "recordID", "occurredAt", "updatedAt"] + allKeys.sorted()
        var lines = [columns.map(Self.csvEscape).joined(separator: ",")]
        for row in flattenedRows {
            var values: [String] = [
                row.domain,
                row.kind,
                row.recordID,
                Self.isoDate(row.occurredAt),
                Self.isoDate(row.updatedAt)
            ]
            for key in allKeys.sorted() {
                values.append(row.flat[key] ?? "")
            }
            lines.append(values.map(Self.csvEscape).joined(separator: ","))
        }

        let text = lines.joined(separator: "\n")
        guard let data = text.data(using: .utf8) else {
            throw UserDataExportError.encodingFailed
        }
        return data
    }

    // MARK: - 投影

    /// 把 payload JSON 投影为白名单字段（fail-closed：只保留白名单 ∩ 实际字段）。
    static func project(payload: Data, whitelist: Set<String>) -> [String: UserDataExportValue]? {
        guard whitelist.isEmpty == false,
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return nil
        }
        var result: [String: UserDataExportValue] = [:]
        for key in whitelist {
            guard let value = object[key] else { continue }
            result[key] = convert(value)
        }
        return result.isEmpty ? nil : result
    }

    private static func convert(_ value: Any) -> UserDataExportValue {
        if let bool = value as? Bool {
            return .bool(bool)
        }
        if let number = value as? NSNumber {
            // JSONSerialization 会把 Bool 编码为 NSNumber；CFBoolean 用于区分。
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        }
        if let string = value as? String {
            return .string(string)
        }
        if let array = value as? [Any] {
            return .array(array.map(convert))
        }
        if let dict = value as? [String: Any] {
            return .object(dict.mapValues(convert))
        }
        return .string(String(describing: value))
    }

    /// 把投影值展平为标量列（嵌套对象用 `.` 连接；数组与对象在 CSV 中省略，完整内容见 JSON）。
    static func flatten(_ projected: [String: UserDataExportValue]?) -> [String: String] {
        guard let projected else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in projected {
            flattenValue(value, prefix: key, into: &result)
        }
        return result
    }

    private static func flattenValue(
        _ value: UserDataExportValue,
        prefix: String,
        into result: inout [String: String]
    ) {
        switch value {
        case .string(let string):
            result[prefix] = string
        case .number(let number):
            result[prefix] = String(number)
        case .bool(let bool):
            result[prefix] = bool ? "true" : "false"
        case .object(let object):
            for (key, nested) in object {
                flattenValue(nested, prefix: "\(prefix).\(key)", into: &result)
            }
        case .array:
            break
        }
    }

    private static func jsonValueToAny(_ value: UserDataExportValue) -> Any {
        switch value {
        case .string(let string): string
        case .number(let number): number
        case .bool(let bool): bool
        case .array(let array): array.map(jsonValueToAny)
        case .object(let object): object.mapValues(jsonValueToAny)
        }
    }

    // MARK: - 工具

    private static func isoDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

nonisolated enum UserDataExportError: Error, LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return String(localized: "导出文件生成失败，请稍后再试。")
        }
    }
}
