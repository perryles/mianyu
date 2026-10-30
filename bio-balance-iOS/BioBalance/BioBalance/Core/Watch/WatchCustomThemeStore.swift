/// WatchCustomThemeStore 管理 iOS 端自定义主题的生命周期：创建、更新、删除与使用切换，
/// 并负责在使用主题变化时触发到手表的文件传输与快照同步。
import Foundation
import SwiftUI

/// WatchCustomThemeStore 是 iOS 端自定义主题仓库（@Observable 单例）。
@MainActor
@Observable
final class WatchCustomThemeStore {
    static let shared = WatchCustomThemeStore()

    /// 本地全部主题（内存缓存，载入后由各写操作维护）。
    private(set) var themes: [CustomWatchTheme] = []

    /// 当前使用中的主题 id；nil 表示使用官方主题。
    private(set) var activeThemeId: String?

    /// 最近一次文件传输状态描述（用于 UI 提示）。
    private(set) var lastSyncNotice: String?

    private init() {
        themes = WatchCustomThemeFileStore.listThemes()
        activeThemeId = UserDefaults.standard.string(forKey: AppGroupSchema.Keys.watchCustomThemeId)
        // 使用中的主题被系统目录清理等意外删除时自动回退官方主题。
        if let activeThemeId, !themes.contains(where: { $0.id == activeThemeId }) {
            self.activeThemeId = nil
            persistActiveThemeId(nil)
        }
    }

    /// 是否正在使用自定义主题。
    var isUsingCustomTheme: Bool { activeThemeId != nil }

    /// 当前使用中的主题。
    var activeTheme: CustomWatchTheme? {
        themes.first(where: { $0.id == activeThemeId })
    }

    // MARK: - 增删改查

    /// 新建主题（素材已由管线写入主题目录并返回槽位元信息）。
    func createTheme(name: String, slots: [WatchThemeSlot: WatchThemeSlotMedia]) -> CustomWatchTheme {
        let theme = CustomWatchTheme(
            id: UUID().uuidString,
            name: WatchCustomThemePolicy.normalizedThemeName(name),
            slots: slots
        )
        save(theme)
        return theme
    }

    /// 更新主题名称或素材。
    func updateTheme(_ theme: CustomWatchTheme) {
        var updated = theme
        updated.updatedAt = Date()
        save(updated)
    }

    /// 删除主题；若正在使用则先回退官方主题并同步。
    func deleteTheme(themeId: String) {
        if activeThemeId == themeId {
            restoreOfficialTheme()
        }
        WatchCustomThemeFileStore.deleteTheme(themeId: themeId)
        themes.removeAll { $0.id == themeId }
        WatchConnectivitySyncService.shared.removeWatchThemeFiles(themeId: themeId)
    }

    /// 「恢复默认主题」：停用自定义主题并回同步快照。
    func restoreOfficialTheme() {
        guard activeThemeId != nil else { return }
        persistActiveThemeId(nil)
        activeThemeId = nil
        AppGroupManager.shared.saveWatchCustomThemeId(nil)
        HealthDataManager.shared.syncWatchCustomThemeSelection(nil)
        lastSyncNotice = "已恢复默认主题"
    }

    /// 「立即使用」：保存使用标记 → 同步快照 → 传输素材文件。
    func useTheme(_ theme: CustomWatchTheme) {
        persistActiveThemeId(theme.id)
        activeThemeId = theme.id
        AppGroupManager.shared.saveWatchCustomThemeId(theme.id)
        HealthDataManager.shared.syncWatchCustomThemeSelection(theme.id)
        transferTheme(theme)
    }

    /// 传输主题素材文件到手表。
    func transferTheme(_ theme: CustomWatchTheme) {
        let queued = WatchConnectivitySyncService.shared.transferThemeFiles(theme: theme)
        lastSyncNotice = queued
            ? "主题将同步到手表；若长时间未更新，请在手表中打开眠屿"
            : "未检测到手表，主题将在手表连接后自动同步"
    }

    // MARK: - 私有实现

    private func save(_ theme: CustomWatchTheme) {
        do {
            try WatchCustomThemeFileStore.writeMeta(theme)
        } catch {
            lastSyncNotice = "主题保存失败，请重试"
            return
        }
        if let index = themes.firstIndex(where: { $0.id == theme.id }) {
            themes[index] = theme
        } else {
            themes.insert(theme, at: 0)
        }
    }

    private func persistActiveThemeId(_ value: String?) {
        if let value {
            UserDefaults.standard.set(value, forKey: AppGroupSchema.Keys.watchCustomThemeId)
        } else {
            UserDefaults.standard.removeObject(forKey: AppGroupSchema.Keys.watchCustomThemeId)
        }
    }
}
