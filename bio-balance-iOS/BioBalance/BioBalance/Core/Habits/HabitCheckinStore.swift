/// Habit Checkin Store 负责习惯数据的持久化与同步，用于记录、读取和更新用户的行为打卡状态。
import Foundation

public final class HabitCheckinStore {
    public static let shared = HabitCheckinStore()
    private let actionStore: ActionRecordStore
    
    private init(actionStore: ActionRecordStore = .shared) {
        self.actionStore = actionStore
    }
    
    public func loadTodayTypes() -> Set<String> {
        loadTypes(on: Date())
    }

    public func loadTypes(on date: Date) -> Set<String> {
        Set(actionStore.record(for: date).completedActions.map(\.rawValue))
    }
    
    public func saveTodayTypes(_ types: Set<String>) {
        saveTypes(types, on: Date())
    }

    public func saveTypes(_ types: Set<String>, on date: Date) {
        actionStore.updateRecord(for: date) { record in
            record.completedActions = types.compactMap(SharedActionKind.init(rawValue:))
        }
    }
}