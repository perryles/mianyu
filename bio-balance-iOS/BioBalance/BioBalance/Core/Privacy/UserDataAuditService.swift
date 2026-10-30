import Foundation
import os

/// 盘点现状：本机 SwiftData 各数据域与 CloudKit 同步开关的轻量投影。
///
/// 审计只读取本机数据与 UserDefaults 开关，不发起 CloudKit 查询，
/// 因此不会因网络/账户状态阻塞，也不会把任何业务内容写入日志。
@MainActor
final class UserDataAuditService {
    static let shared = UserDataAuditService()

    private let recordStore: SwiftDataRecordStore
    private let defaults: UserDefaults

    init(
        recordStore: SwiftDataRecordStore? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.recordStore = recordStore ?? SwiftDataRecordStore()
        self.defaults = defaults
    }

    /// 生成审计报告：按实际存在的 SwiftData 域分组统计 + CloudKit 开关状态。
    func audit() -> UserDataAuditReport {
        let snapshots = recordStore.allRecords()
        let grouped = Dictionary(grouping: snapshots, by: \.domain)

        let summaries = grouped.keys.sorted().compactMap { domain -> UserDataDomainSummary? in
            let rows = grouped[domain] ?? []
            let dates = rows.compactMap(\.occurredAt)
            return UserDataDomainSummary(
                domain: domain,
                displayName: UserDataPrivacyRegistry.displayName(for: domain),
                recordCount: rows.count,
                earliestAt: dates.min(),
                latestAt: dates.max()
            )
        }

        let cloudStatus = ICloudSyncDomain.allCases.map { domain in
            CloudSyncDomainStatus(
                domain: domain.rawValue,
                displayName: UserDataPrivacyRegistry.displayName(for: domain.rawValue),
                isEnabled: defaults.bool(forKey: domain.preferenceKey),
                zoneName: Self.zoneName(for: domain)
            )
        }

        UserDataPrivacyLogger.info(
            "audit domains=\(summaries.count) records=\(snapshots.count)"
        )
        return UserDataAuditReport(generatedAt: Date(), domainSummaries: summaries, cloudSyncEnabled: cloudStatus)
    }

    private static func zoneName(for domain: ICloudSyncDomain) -> String? {
        switch domain {
        case .drinkExperience: CloudKitDataPolicy.Zone.drinkExperience
        case .sleepSummary: CloudKitDataPolicy.Zone.sleep
        case .medicationHealth: CloudKitDataPolicy.Zone.medicationHealth
        case .pregnancy: CloudKitDataPolicy.Zone.pregnancy
        case .goalMascot: CloudKitDataPolicy.Zone.goalMascot
        case .onboardingPreference: CloudKitDataPolicy.Zone.onboardingPreference
        case .socialSharing: CloudKitDataPolicy.Zone.friendHealthShare
        }
    }
}
