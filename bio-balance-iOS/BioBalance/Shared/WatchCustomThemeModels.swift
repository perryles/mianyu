/// WatchCustomThemeModels 定义自定义 Watch 主题的数据结构与状态槽位解析规则。
import Foundation

/// WatchThemeSlot 对应手表主页的四个压力状态素材槽位。
nonisolated enum WatchThemeSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case excellent
    case normal
    case mild
    case overloaded

    var id: String { rawValue }

    /// 状态标签文案（与趋势页压力分桶一致）。
    var displayTitle: String {
        switch self {
        case .excellent: return "状态优秀"
        case .normal: return "状态正常"
        case .mild: return "有点压力"
        case .overloaded: return "压力过载"
        }
    }
}

/// WatchThemeSlotMedia 描述单个槽位已转码素材的元信息。
nonisolated struct WatchThemeSlotMedia: Codable, Equatable, Hashable, Sendable {
    /// 槽位。
    var slot: WatchThemeSlot
    /// 文件扩展名：png（静态）或 gif（动图）。
    var fileExtension: String
    /// 是否动图。
    var isAnimated: Bool
    /// 转码后文件字节数。
    var fileSize: Int
}

/// CustomWatchTheme 是一组用户上传素材构成的自定义手表主题。
struct CustomWatchTheme: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    /// 槽位素材，缺失槽位渲染时逐级回退。
    var slots: [WatchThemeSlot: WatchThemeSlotMedia]

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt
        case updatedAt
        case slots
    }

    /// slots 嵌套字典的解码键（值不固定，仅用于逐槽容错读取）。
    struct WatchThemeSlotKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }

    init(id: String, name: String, createdAt: Date = Date(), updatedAt: Date = Date(), slots: [WatchThemeSlot: WatchThemeSlotMedia]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.slots = slots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        // 单个槽位损坏时丢弃该槽位而不是整个 meta，渲染层可走官方主题回退。
        var resolved: [WatchThemeSlot: WatchThemeSlotMedia] = [:]
        if container.contains(.slots),
           let nested = try? container.nestedContainer(keyedBy: WatchThemeSlotKey.self, forKey: .slots) {
            for key in nested.allKeys {
                guard let slot = WatchThemeSlot(rawValue: key.stringValue),
                      let media = try? nested.decode(WatchThemeSlotMedia.self, forKey: key) else {
                    continue
                }
                resolved[slot] = media
            }
        }
        slots = resolved
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        var rawSlots: [String: WatchThemeSlotMedia] = [:]
        for (slot, media) in slots {
            rawSlots[slot.rawValue] = media
        }
        try container.encode(rawSlots, forKey: .slots)
    }

    /// 展示排序：新创建的在前。
    var sortKey: Date { createdAt }
}

/// WatchThemeSlotResolver 将健康快照解析为素材槽位，iOS 预览与手表渲染使用一致规则。
enum WatchThemeSlotResolver {
    /// 手表端 hero 状态使用 HRV 主导档位（≥48 恢复良好 / ≥25 正常 / >0 需要恢复），
    /// 映射到四档素材；压力值仅用于补充“压力过载”判定。
    static func slot(hrv: Double, stress: Int) -> WatchThemeSlot {
        if stress >= 75 { return .overloaded }
        if hrv >= 48 { return .excellent }
        if hrv >= 25 { return .normal }
        if hrv > 0 { return .mild }
        // 无 HRV 数据时按压力值兜底。
        if stress >= 55 { return .mild }
        return .normal
    }

    /// 槽位缺失时的回退顺序：自身 → 正常槽 → 任意可用槽。
    static func fallbackChain(for slot: WatchThemeSlot) -> [WatchThemeSlot] {
        switch slot {
        case .normal:
            return [.normal]
        default:
            var chain: [WatchThemeSlot] = [slot, .normal]
            for candidate in WatchThemeSlot.allCases where !chain.contains(candidate) {
                chain.append(candidate)
            }
            return chain
        }
    }
}

/// WatchCustomThemePolicy 收敛自定义主题的约束常量与输入校验。
nonisolated enum WatchCustomThemePolicy {
    /// 主题名称上限。
    static let maximumNameLength = 12
    /// 动图素材时长上限（秒）。
    static let maximumAnimationDuration: Double = 5
    /// 动图目标帧率。
    static let animationFrameRate: Int = 10
    /// 动图最大帧数。
    static let maximumAnimationFrameCount = 50
    /// 静态图最长边。
    static let maximumStaticImageDimension: CGFloat = 512
    /// 动图最长边。
    static let maximumAnimatedImageDimension: CGFloat = 300

    static func normalizedThemeName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maximumNameLength))
    }
}
