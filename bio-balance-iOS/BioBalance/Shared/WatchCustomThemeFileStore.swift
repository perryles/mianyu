/// WatchCustomThemeFileStore 定义自定义 Watch 主题素材在本地文件系统的统一布局，
/// iOS（创建/传输）与 watchOS（接收/渲染）共用，保证两侧路径与 meta 格式一致。
import Foundation

/// WatchCustomThemeFileStore 收敛主题目录、素材文件与 meta 的读写。
enum WatchCustomThemeFileStore {
    /// meta 固定文件名。
    static let metaFileName = "meta.json"
    /// 文件传输 metadata 字典键（WCSession file metadata 与 meta.json 共用字段名）。
    enum MetaKey {
        static let themeId = "themeId"
        static let themeName = "themeName"
        static let slot = "slot"
        static let fileExtension = "fileExtension"
        static let isAnimated = "isAnimated"
        static let fileSize = "fileSize"
        static let version = "version"
    }

    /// 当前 meta 格式版本。
    static let metaVersion = 1

    // MARK: - 目录布局

    /// iOS / watchOS 各自容器内的主题根目录。
    static func themesRootDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("WatchThemes", isDirectory: true)
    }

    /// 单个主题目录。
    static func themeDirectory(themeId: String) -> URL {
        themesRootDirectory().appendingPathComponent(themeId, isDirectory: true)
    }

    /// 单个槽位素材文件地址。
    static func slotFileURL(themeId: String, slot: WatchThemeSlot, fileExtension: String) -> URL {
        themeDirectory(themeId: themeId).appendingPathComponent("\(slot.rawValue).\(fileExtension)")
    }

    /// 主题 meta 文件地址。
    static func metaFileURL(themeId: String) -> URL {
        themeDirectory(themeId: themeId).appendingPathComponent(metaFileName)
    }

    // MARK: - Meta 读写

    /// 写入主题 meta；目录不存在时自动创建。
    static func writeMeta(_ theme: CustomWatchTheme) throws {
        let directory = themeDirectory(themeId: theme.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(theme)
        try data.write(to: metaFileURL(themeId: theme.id), options: .atomic)
    }

    /// 读取主题 meta；不存在或损坏返回 nil。
    static func readMeta(themeId: String) -> CustomWatchTheme? {
        guard let data = try? Data(contentsOf: metaFileURL(themeId: themeId)) else { return nil }
        return try? JSONDecoder().decode(CustomWatchTheme.self, from: data)
    }

    /// 列出本地全部主题 meta（按创建时间倒序）。
    static func listThemes() -> [CustomWatchTheme] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: themesRootDirectory(),
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return contents
            .filter { $0.hasDirectoryPath }
            .compactMap { readMeta(themeId: $0.lastPathComponent) }
            .sorted { $0.sortKey > $1.sortKey }
    }

    /// 删除整个主题目录。
    static func deleteTheme(themeId: String) {
        try? FileManager.default.removeItem(at: themeDirectory(themeId: themeId))
    }

    /// 读取槽位素材数据；按回退链逐级尝试。
    static func slotData(themeId: String, slot: WatchThemeSlot) -> (data: Data, media: WatchThemeSlotMedia)? {
        for candidate in WatchThemeSlotResolver.fallbackChain(for: slot) {
            guard let media = readMeta(themeId: themeId)?.slots[candidate] else { continue }
            let url = slotFileURL(themeId: themeId, slot: candidate, fileExtension: media.fileExtension)
            if let data = try? Data(contentsOf: url) {
                return (data, media)
            }
        }
        return nil
    }
}
