import Foundation
import os

/// 好友共享摘要上传到 CloudKit 前的隐私白名单校验器。
///
/// 根据 `ICLOUD_DATA_ARCHITECTURE.md` 第 1 节和第 6 节的硬性规则，上传到
/// `FriendHealthShareZone` 的 `SharedHealthSnapshot` 必须只包含处理后的摘要数据，
/// 严禁携带 HealthKit 原始样本、RR 间期、精确位置轨迹、模型对话全文、Embedding
/// 或 API 凭据。该校验器作为"最后一道防线"，防止未来模型新增字段意外泄密。
///
/// ## 校验维度
/// 1. **字段白名单**：编码后的 JSON 只允许已知的 key 存在。
/// 2. **payload 大小**：超过阈值的 payload 会被拒绝，防止意外编码大数组。
/// 3. **位置精度**：坐标必须有足够模糊度（horizontalAccuracy ≥ 500m）。
/// 4. **天数上限**：`days` 数组长度不能超过预期范围。
nonisolated enum SharedHealthSnapshotPrivacyValidator {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "SocialSharing.Privacy")

    /// 编码后 payload 的最大字节数。当前正常摘要约 2-4 KB，设 64 KB 留充足余量。
    static let maxEncodedPayloadBytes = 64 * 1024

    /// 好友共享允许的最多天数。超过此值说明可能误传了原始 HealthKit 样本。
    static let maxSharedDays = 14

    /// 位置坐标最低精度要求（米），低于此值视为精确坐标。
    static let minLocationHorizontalAccuracyMeters = 500.0

    // MARK: - 编码后白名单校验

    /// 校验编码后的 JSON Data 是否只包含允许的顶层 key。
    ///
    /// - Parameter data: `JSONEncoder` 编码后的 payload
    /// - Returns: 通过校验则返回 `nil`，否则返回拒绝原因
    static func validateEncodedPayload(_ data: Data) -> PrivacyValidationError? {
        if data.count > maxEncodedPayloadBytes {
            return .payloadTooLarge(byteCount: data.count, maxBytes: maxEncodedPayloadBytes)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return .invalidJSON
        }

        let allowedKeys: Set<String> = [
            "ownerUserID",
            "ownerDisplayName",
            "generatedAt",
            "days",
            "highlights",
            "location",
            "payloadVersion",
            "sharedActionRecords",
            "sharedCountdownItems",
            "sharedTodoListSummary"
        ]

        let unexpectedKeys = Set(json.keys).subtracting(allowedKeys)
        if !unexpectedKeys.isEmpty {
            return .unexpectedFields(unexpectedKeys.sorted())
        }

        return nil
    }

    // MARK: - 模型层校验

    /// 校验 `SharedHealthSnapshot` 模型是否符合好友共享隐私约束。
    static func validate(_ snapshot: SharedHealthSnapshot) -> PrivacyValidationError? {
        if snapshot.days.count > maxSharedDays {
            return .tooManyDays(count: snapshot.days.count, max: maxSharedDays)
        }

        if let location = snapshot.location {
            if let accuracy = location.horizontalAccuracyMeters,
               accuracy < minLocationHorizontalAccuracyMeters {
                return .locationTooPrecise(accuracyMeters: accuracy, minAccuracy: minLocationHorizontalAccuracyMeters)
            }
        }

        // payloadVersion 必须是已知版本，旧版本应先做兼容升级
        guard snapshot.payloadVersion >= 1, snapshot.payloadVersion <= 3 else {
            return .unknownPayloadVersion(snapshot.payloadVersion)
        }

        // ownerDisplayName 不应包含看起来像 token / credential 的内容
        let suspiciousPatterns: [String] = [
            "Bearer ",
            "sk-",
            "AKIA",
            "xoxb-"
        ]
        for pattern in suspiciousPatterns where snapshot.ownerDisplayName.contains(pattern) {
            return .displayNameContainsSuspiciousContent
        }

        return nil
    }

    // MARK: - 完整校验（模型 + 编码）

    /// 对 snapshot 做完整校验并编码为 Data，任一环节失败则抛出错误。
    ///
    /// 调用方（如 `CloudKitSharingRepository`）应使用此方法替代直接 `JSONEncoder.encode`，
    /// 以确保上传前自动完成隐私白名单检查。
    static func encodeAndValidate(
        _ snapshot: SharedHealthSnapshot,
        encoder: JSONEncoder
    ) throws -> Data {
        if let modelError = validate(snapshot) {
            logger.error("[隐私校验] 模型层拒绝上传 snapshot error=\(modelError.localizedDescription, privacy: .public)")
            throw modelError
        }

        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            logger.error("[隐私校验] 编码失败 error=\(error.localizedDescription, privacy: .public)")
            throw PrivacyValidationError.encodingFailed(error.localizedDescription)
        }

        if let payloadError = validateEncodedPayload(data) {
            logger.error("[隐私校验] 编码后 payload 被拒绝 error=\(payloadError.localizedDescription, privacy: .public)")
            throw payloadError
        }

        return data
    }
}

// MARK: - PrivacyValidationError

/// 隐私白名单校验失败原因。
///
/// 遵循 `ICLOUD_DATA_ARCHITECTURE.md` 第 6 节的日志约束，错误描述不含业务内容。
nonisolated enum PrivacyValidationError: Error, LocalizedError, Equatable, Sendable {
    case payloadTooLarge(byteCount: Int, maxBytes: Int)
    case invalidJSON
    case unexpectedFields([String])
    case tooManyDays(count: Int, max: Int)
    case locationTooPrecise(accuracyMeters: Double, minAccuracy: Double)
    case unknownPayloadVersion(Int)
    case displayNameContainsSuspiciousContent
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .payloadTooLarge(let bytes, let max):
            return "共享摘要体积超过上限 (\(bytes) > \(max) bytes)，可能编码了非预期的数据。"
        case .invalidJSON:
            return "共享摘要编码后的数据不是有效 JSON。"
        case .unexpectedFields(let fields):
            return "共享摘要包含不在白名单中的字段：\(fields.joined(separator: ", "))。"
        case .tooManyDays(let count, let max):
            return "共享天数超过上限 (\(count) > \(max))，可能误传了原始健康样本。"
        case .locationTooPrecise(let accuracy, let minAccuracy):
            return "位置精度高于允许阈值 (\(accuracy)m < \(minAccuracy)m)，拒绝上传精确坐标。"
        case .unknownPayloadVersion(let version):
            return "未知的 payload version (\(version))，需要先做兼容升级。"
        case .displayNameContainsSuspiciousContent:
            return "显示名包含疑似凭据内容，已拒绝上传。"
        case .encodingFailed(let message):
            return "共享摘要编码失败：\(message)"
        }
    }
}
