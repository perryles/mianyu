import Foundation

/// 健康问答的数据上传开关与后端能力策略。
enum HealthAIConfiguration {
    /// 今日摘要默认优先使用已安全配置的千问，运行时不可用时由路由回落本地。
    static var isTodayCloudUploadAuthorized: Bool {
        AIBuildPolicy.allowsDirectCloudProviders
    }

    /// 长期档案只能经单独授权后的第一方后端发送，当前阶段固定本地处理。
    static var isSecureProfileBackendConfigured: Bool {
        false
    }
}
