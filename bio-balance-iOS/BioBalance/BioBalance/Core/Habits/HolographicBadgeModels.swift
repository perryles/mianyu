/// HolographicBadge 域：模型 + 徽章目录 + 数据快照。
/// 徽章是「展示型激励」：从行为记录与健康报告派生解锁状态，不代表临床健康结论。

import Foundation

// MARK: - 奖章主题

/// 奖章的金属/珐琅配色主题，驱动 HolographicMedalView 的着色。
nonisolated enum HolographicBadgeTheme: String, Codable, CaseIterable, Sendable {
    /// 蓝金：月度活跃挑战（参考「征途挑战」的宝蓝 + 金边）。
    case azureGold
    /// 紫铜：连续记录（参考「青铜共建官」的哑光铜色）。
    case bronze
    /// 暖金：里程碑（参考「答题急先锋」的亮金缎带）。
    case warmGold
    /// 青玉：轻养生与放松。
    case jade
    /// 幻彩：特殊纪念。
    case iridescent

    var id: String { rawValue }

    /// 金属主色（外圈/边框）。
    var metal: (light: String, dark: String) {
        switch self {
        case .azureGold: return ("F7D98B", "C99B3F")
        case .bronze: return ("E8B99B", "A9714B")
        case .warmGold: return ("FCE9B0", "D8A94E")
        case .jade: return ("BFDEC9", "5F9B7C")
        case .iridescent: return ("E8D9F5", "9B7FC4")
        }
    }

    /// 珐琅底色（奖章内部区域，上→下）。
    var enamel: [String] {
        switch self {
        case .azureGold: return ["5B8DEF", "3E63C4", "2C4A9E"]
        case .bronze: return ["D9A67F", "B87E56", "96593A"]
        case .warmGold: return ["F6D488", "E3AC4E", "C98F35"]
        case .jade: return ["9FD8B7", "67B18B", "4C9070"]
        case .iridescent: return ["C9B6F2", "9E86D9", "7763B5"]
        }
    }

    /// 高光强调（顶部标签、内环）。
    var highlight: String {
        switch self {
        case .azureGold: return "7FA8F5"
        case .bronze: return "E9C4A4"
        case .warmGold: return "FBE6A9"
        case .jade: return "C2E6D0"
        case .iridescent: return "DCCBFA"
        }
    }
}

// MARK: - 徽章定义

/// 一枚可解锁的全息徽章。目录静态定义；解锁状态由 Store 派生。
nonisolated struct HolographicBadgeDefinition: Identifiable, Equatable, Sendable {
    let id: String
    /// 展示名（本地化 key）。
    let titleKey: String
    /// 系列名（本地化 key，如「月度挑战」「连续记录」）。
    let seriesKey: String
    let theme: HolographicBadgeTheme
    /// 中央图案。
    let symbol: String
    /// 获取条件的简述（本地化 key，占位符 %lld 表示目标天数）。
    let requirementKey: String
    /// 解锁需要的行为天数。
    let requiredDays: Int
    /// 是否按月重置（月度挑战类）；false 表示累计型。
    let isMonthly: Bool
}

// MARK: - 解锁状态

/// 一枚徽章的当前解锁状态，由 Store 从各行为 Store 聚合派生。
nonisolated struct HolographicBadgeStatus: Identifiable, Equatable, Sendable {
    let definition: HolographicBadgeDefinition
    /// 已累计/本月已达成天数。
    let progressDays: Int
    /// 解锁时间；nil 表示尚未解锁。
    let unlockedAt: Date?
    /// 本徽章是否为解锁后尚未确认（弹窗/「新获得」角标的依据）。
    let isPendingCelebration: Bool

    var id: String { definition.id }
    var isUnlocked: Bool { unlockedAt != nil }
    var remainingDays: Int { max(0, definition.requiredDays - progressDays) }
    var progressFraction: Double {
        guard definition.requiredDays > 0 else { return 0 }
        return min(1, Double(progressDays) / Double(definition.requiredDays))
    }

    func unlockedDateText(calendar: Calendar = .current) -> String? {
        guard let unlockedAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy.M.d"
        return formatter.string(from: unlockedAt)
    }
}

// MARK: - 快照持久化

/// 持久化的解锁快照：解锁时间与庆祝确认。进度本身从行为 Store 实时聚合。
nonisolated struct HolographicBadgeSnapshot: Codable, Sendable, Equatable {
    var badgeID: String
    var unlockedAt: Date
    var celebratedAt: Date? = nil

    var isPendingCelebration: Bool { celebratedAt == nil }
}

// MARK: - 持久化载荷（SwiftData payload 编码用）

nonisolated struct HolographicBadgePayload: Codable, Sendable {
    var snapshots: [HolographicBadgeSnapshot]
}
