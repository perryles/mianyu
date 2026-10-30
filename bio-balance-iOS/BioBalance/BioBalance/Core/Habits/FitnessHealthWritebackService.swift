import Foundation

/// 健身详情页保存后的健康 App 写回结果，用于给用户提示同步状态。
struct FitnessHealthWritebackOutcome: Sendable {
    var workoutSynced = false
    var moodSynced = false
    var didFail = false

    var didSyncAnything: Bool { workoutSynced || moodSynced }
}

/// 把健身详情页确认后的运动时长/距离与当日心情写回健康 App，并维护本地记录里的样本引用。
/// 写回失败不影响本地保存：本地记录始终先落库，健康 App 只是镜像（与 CloudKit“云端失败不得表现为本地保存失败”的口径一致）。
final class FitnessHealthWritebackService {
    static let shared = FitnessHealthWritebackService()

    private let healthKit: HealthKitManager
    private let store: FitnessCalendarStore

    init(
        healthKit: HealthKitManager = .shared,
        store: FitnessCalendarStore = .shared
    ) {
        self.healthKit = healthKit
        self.store = store
    }

    /// 根据保存草稿同步训练与心情。重复编辑同一天时会替换本 App 上一次写入的样本，避免在健康 App 里重复计入。
    func sync(draft: FitnessDayDetailDraft, for date: Date) async -> FitnessHealthWritebackOutcome {
        var outcome = FitnessHealthWritebackOutcome()
        guard draft.syncToHealthApp else { return outcome }

        let record = store.record(for: date)

        if draft.mode == .workout, draft.minutes > 0 {
            let window = Self.workoutWindow(for: date, minutes: draft.minutes, checkedInAt: record.checkedInAt)
            do {
                let uuid = try await healthKit.saveWorkoutSession(
                    start: window.start,
                    end: window.end,
                    effort: draft.effort,
                    note: draft.note,
                    distanceKm: draft.distanceKm > 0 ? draft.distanceKm : nil,
                    replacingWorkoutUUID: record.healthKitWorkoutUUID.flatMap(UUID.init(uuidString:))
                )
                store.updateRecord(for: date) { $0.healthKitWorkoutUUID = uuid.uuidString }
                outcome.workoutSynced = true
            } catch {
                outcome.didFail = true
            }
        }

        if let mood = draft.mood {
            do {
                let uuid = try await healthKit.saveDailyMood(
                    valence: mood.valence,
                    on: date,
                    replacingUUID: record.healthKitMoodUUID.flatMap(UUID.init(uuidString:))
                )
                store.updateRecord(for: date) { $0.healthKitMoodUUID = uuid.uuidString }
                outcome.moodSynced = true
            } catch {
                outcome.didFail = true
            }
        }

        return outcome
    }

    /// 推算写入健康 App 的训练时间窗：今天以“现在”收尾；历史日优先用当天打卡时刻，否则按 19:00 结束。
    static func workoutWindow(for date: Date, minutes: Int, checkedInAt: Date?) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let end: Date
        if calendar.isDateInToday(date) {
            end = Date()
        } else if let checkedInAt, calendar.isDate(checkedInAt, inSameDayAs: date) {
            end = checkedInAt
        } else {
            end = dayStart.addingTimeInterval(19 * 3600)
        }
        let start = max(dayStart, end.addingTimeInterval(-Double(max(minutes, 1)) * 60))
        return (start, end)
    }
}
