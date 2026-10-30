import Foundation

enum LegacyAppGroupDataMigration {
    private static let legacyPreferenceMappings = [
        "sleepGoalHours": "daily_sleep_goal_hours",
        "stressAlertThreshold": "stress_alert_threshold"
    ]
    private static let businessKeys = [
        "selfObservationStore.v1",
        "social.sharedTodoStore.v1",
        "countdownStore.v1",
        "moodStore.v1",
        "drinkExperienceStore.v1",
        "mealRecognitionStore.v1",
        "medicationStore.v1",
        "medicationStore.v2",
        "medicationPrescriptionStore.v1",
        "mentalAssessmentStore.v1",
        "sync.local-outbox.v1",
        "periodStore.v1",
        "recoveryChallengeStore.v1",
        "actionRecordStore.v1",
        "actionRecordStore.v2",
        "caffeineDoseEventStore.v1",
        "dailyWellnessStore.records.v1",
        "dailyWellnessStore.reminder.v1",
        "goals.store.payload.v1",
        CloudKitDataPolicy.AccountBindingKey.goalMascot,
        "notificationManagement.unifiedReminderCandidates.v1",
        "personalizedReminderCenter.preferences.v1",
        "notificationManagement.preferences.v1",
        "notificationManagement.suspendedQuietHoursRequests.v1",
        "habitReminderSettings.v1",
        "daily.recovery.suggestion-cooldowns.v1",
        "health.deterministic.daily-snapshots.v1",
        "sleepEnvironmentManagementStore.v1",
        "daily.recovery.orchestration.v1",
        "daily.recovery.orchestration.action-states.v1",
        "sleepRhythmProtectionStore.v1"
    ]

    private static let businessKeyPrefixes = [
        "metric.reminder.settings."
    ]

    /// 把 App Group 中的业务 key 单向搬到标准 UserDefaults：目标 key 已有值时不覆盖，
    /// 迁移完成后删除旧 key（失败场景由调用方保证：只有标准 defaults 写入成功后旧 key
    /// 才会被移除，App Group 数据在删除前仍可重试）。
    /// 默认参数保持线上行为；测试可注入独立 defaults 验证（mock 数据）。
    static func migrateBusinessDataToStandardDefaults(
        appGroupDefaults: UserDefaults? = AppGroupManager.userDefaults(),
        standardDefaults: UserDefaults = .standard
    ) {
        guard let appGroupDefaults else { return }

        let prefixedKeys = appGroupDefaults.dictionaryRepresentation().keys.filter { key in
            businessKeyPrefixes.contains { key.hasPrefix($0) }
        }

        for key in businessKeys + prefixedKeys {
            if standardDefaults.object(forKey: key) == nil,
               let legacyValue = appGroupDefaults.object(forKey: key) {
                standardDefaults.set(legacyValue, forKey: key)
            }
            appGroupDefaults.removeObject(forKey: key)
        }
    }

    /// 标量偏好只迁移一次：新 Key 已有值时以新值为准，随后停止旧 Key 双写。
    /// 默认参数保持线上行为；测试可注入独立 defaults 验证（mock 数据）。
    static func migrateLegacyStandardPreferences(defaults: UserDefaults = .standard) {
        for (legacyKey, currentKey) in legacyPreferenceMappings {
            if defaults.object(forKey: currentKey) == nil,
               let legacyValue = defaults.object(forKey: legacyKey) {
                defaults.set(legacyValue, forKey: currentKey)
            }
            defaults.removeObject(forKey: legacyKey)
        }
    }
}
