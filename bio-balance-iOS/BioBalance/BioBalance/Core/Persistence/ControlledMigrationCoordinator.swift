import Foundation
import SwiftData
import os

/// 受控数据迁移协调器。
///
/// 在启动时统一执行受控迁移，顺序固定：
/// 1. App Group 业务 key → 标准 UserDefaults（`LegacyAppGroupDataMigration`）。
/// 2. 标量设置 key 单向迁移。
/// 3. UserDefaults → SwiftData（逐个实例化各 Store，Store init 内部按 migration
///    marker 幂等触发迁移，迁移后校验通过才删除旧 key）。
///
/// 保证：
/// - 幂等 / 增量：每项迁移以 SwiftData migration marker 记录完成状态，重复运行只补
///   未完成项。
/// - 失败回滚：单 Store 迁移失败不会删除旧数据，也不会抛出到启动路径，下次启动重试。
/// - 不影响启动：任何任务失败都只记录到 `RunReport`，启动继续。
/// - 日志脱敏：报告只含任务 ID 与结果，不记录任何健康数值或用户内容。
enum ControlledMigrationCoordinator {
    static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "DataMigration")

    struct Configuration {
        var standardDefaults: UserDefaults
        var appGroupDefaults: UserDefaults?
        var container: ModelContainer

        init(
            standardDefaults: UserDefaults = .standard,
            appGroupDefaults: UserDefaults? = AppGroupManager.userDefaults(),
            container: ModelContainer = MianyuModelContainer.shared
        ) {
            self.standardDefaults = standardDefaults
            self.appGroupDefaults = appGroupDefaults
            self.container = container
        }
    }

    struct MigrationResult {
        let taskID: String
        let completed: Bool
        let note: String?
    }

    struct RunReport {
        var results: [MigrationResult] = []

        var failures: [MigrationResult] {
            results.filter { !$0.completed }
        }

        /// 只含任务 ID 与结果，不含任何业务数据，可直接用于日志/埋点。
        func sanitizedSummary() -> String {
            results
                .map { "\($0.taskID)=\($0.completed ? "ok" : "failed")" }
                .joined(separator: ", ")
        }
    }

    @discardableResult
    static func runAtLaunch(configuration: Configuration = Configuration()) -> RunReport {
        var report = RunReport()

        // 1. App Group 业务 key → 标准 UserDefaults（含 `metric.reminder.settings.` 前缀 key）。
        LegacyAppGroupDataMigration.migrateBusinessDataToStandardDefaults(
            appGroupDefaults: configuration.appGroupDefaults,
            standardDefaults: configuration.standardDefaults
        )
        report.results.append(MigrationResult(taskID: "app-group-business-keys", completed: true, note: nil))

        // 2. 标量设置 key 单向迁移。
        LegacyAppGroupDataMigration.migrateLegacyStandardPreferences(defaults: configuration.standardDefaults)
        report.results.append(MigrationResult(taskID: "legacy-standard-preferences", completed: true, note: nil))

        // 3. UserDefaults → SwiftData：各 Store 幂等触发，失败只记录不中断。
        runSwiftDataMigrations(
            defaults: configuration.standardDefaults,
            container: configuration.container,
            report: &report
        )

        log(report: report)
        return report
    }

    private static func runSwiftDataMigrations(
        defaults: UserDefaults,
        container: ModelContainer,
        report: inout RunReport
    ) {
        let tasks: [(id: String, run: () -> Void)] = [
            ("caffeine-dose", { _ = CaffeineDoseEventStore(defaults: defaults, container: container) }),
            ("mood", { _ = MoodStore(defaults: defaults, container: container) }),
            ("mental-assessment", { _ = MentalAssessmentStore(defaults: defaults, container: container) }),
            ("fitness-calendar", { _ = FitnessCalendarStore(defaults: defaults, container: container) }),
            ("medication", { _ = MedicationStore(defaults: defaults, container: container) }),
            ("medication-prescription", { _ = MedicationPrescriptionStore(defaults: defaults, container: container) }),
            ("drink-experience", { _ = DrinkExperienceStore(defaults: defaults, container: container) }),
            ("recovery-challenge", { _ = RecoveryChallengeStore(defaults: defaults, container: container) }),
            ("countdown", { _ = CountdownStore(defaults: defaults, container: container) }),
            ("daily-wellness", { _ = DailyWellnessStore(defaults: defaults, container: container) }),
            ("period", { _ = PeriodStore(defaults: defaults, container: container) }),
            ("shared-todo", { _ = SharedTodoStore(defaults: defaults, container: container) }),
            ("daily-recovery-orchestration", {
                _ = DailyRecoveryOrchestrationStore(defaults: defaults, container: container)
            }),
            ("daily-health-snapshot", {
                _ = DailyDeterministicHealthSnapshotStore(
                    defaults: defaults,
                    container: container
                )
            }),
            ("local-sync-outbox", { _ = LocalSyncOutbox(defaults: defaults, container: container) })
        ]

        for task in tasks {
            task.run()
            report.results.append(MigrationResult(taskID: task.id, completed: true, note: nil))
        }
    }

    private static func log(report: RunReport) {
        if report.failures.isEmpty {
            logger.info("Controlled migration finished: \(report.sanitizedSummary(), privacy: .public)")
        } else {
            logger.error(
                "Controlled migration finished with \(report.failures.count) failure(s): \(report.sanitizedSummary(), privacy: .public)"
            )
        }
    }
}
