import Foundation

struct SocialShareExtras: Sendable {
    let actionRecords: [SharedActionRecord]
    let countdownItems: [SharedCountdownItem]
    let todoListSummary: SharedTodoListSummary?
}

struct SocialShareExtrasBuilder {
    private let actionStore: ActionRecordStore
    private let countdownStore: CountdownStore
    private let todoStore: SharedTodoStore
    private let calendar: Calendar

    init(
        actionStore: ActionRecordStore? = nil,
        countdownStore: CountdownStore? = nil,
        todoStore: SharedTodoStore? = nil,
        calendar: Calendar = .current
    ) {
        self.actionStore = actionStore ?? .shared
        self.countdownStore = countdownStore ?? .shared
        self.todoStore = todoStore ?? .shared
        self.calendar = calendar
    }

    func build(
        limit: Int = 3,
        referenceDate: Date = Date(),
        currentUserRecordName: String? = nil,
        // 该摘要会进入好友 CKShare，payload 只声明接收方实际拥有的只读权限。
        // 所有者在本机管理待办时会由调用方显式传入 `.collaborator`。
        permissionRole: FriendPermissionRole = .readOnly
    ) -> SocialShareExtras {
        let actionRecords = actionStore.recentSharedRecords(limit: limit).map(makeSharedActionRecord)
        let countdownItems = countdownStore.recentSharedItems(limit: limit).map {
            makeSharedCountdownItem($0, referenceDate: referenceDate)
        }
        let todoListSummary = makeSharedTodoList(
            todoStore.loadList(),
            currentUserRecordName: currentUserRecordName,
            permissionRole: permissionRole
        )
        return SocialShareExtras(
            actionRecords: actionRecords,
            countdownItems: countdownItems,
            todoListSummary: todoListSummary
        )
    }

    private func makeSharedActionRecord(_ record: LocalActionDayRecord) -> SharedActionRecord {
        let completedTitles = record.completedActions.map(\.title)
        let summaryText: String
        if completedTitles.isEmpty {
            summaryText = "这一天还没有完成的行动项。"
        } else {
            summaryText = "完成了 \(completedTitles.joined(separator: "、"))。"
        }

        var parts: [String] = []
        if record.waterMl > 0 {
            parts.append("饮水 \(record.waterMl) ml")
        }
        if record.caffeineMg > 0 {
            parts.append("咖啡因 \(record.caffeineMg) mg")
        }
        if record.sunlightMinutes > 0 {
            parts.append("日照 \(record.sunlightMinutes) 分钟")
        }
        if record.mindfulnessMinutes > 0 {
            parts.append("正念 \(record.mindfulnessMinutes) 分钟")
        }
        if record.standHours > 0 {
            parts.append("站立 \(record.standHours) 小时")
        }

        return SharedActionRecord(
            date: record.date,
            completedActions: record.completedActions,
            summaryText: summaryText,
            progressText: parts.isEmpty ? "当天没有更多可展示进度" : parts.joined(separator: " · ")
        )
    }

    private func makeSharedCountdownItem(_ item: LocalCountdownItem, referenceDate: Date) -> SharedCountdownItem {
        let start = calendar.startOfDay(for: referenceDate)
        let target = calendar.startOfDay(for: item.targetDate)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0

        let relativeText: String
        switch days {
        case 1...:
            relativeText = "还有 \(days) 天"
        case 0:
            relativeText = "就是今天"
        default:
            relativeText = "已过去 \(abs(days)) 天"
        }

        return SharedCountdownItem(
            id: item.id,
            title: item.title,
            targetDate: item.targetDate,
            relativeText: relativeText,
            note: item.note
        )
    }

    private func makeSharedTodoList(
        _ list: LocalSharedTodoList,
        currentUserRecordName: String?,
        permissionRole: FriendPermissionRole
    ) -> SharedTodoListSummary? {
        guard list.isShared else { return nil }

        let items = list.items.map { item in
            SharedTodoItem(
                id: item.id,
                title: item.title,
                isCompleted: item.isCompleted,
                note: item.note,
                dueDate: item.dueDate,
                createdByUserRecordName: item.createdByUserRecordName,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                fieldTimestamps: item.fieldTimestamps
            )
        }

        return SharedTodoListSummary(
            id: list.id,
            title: list.title,
            ownerUserRecordName: currentUserRecordName,
            itemCount: items.count,
            completedCount: items.filter(\.isCompleted).count,
            updatedAt: list.updatedAt,
            lastEditedByUserRecordName: items.sorted { $0.updatedAt > $1.updatedAt }.first?.createdByUserRecordName,
            permissionRole: permissionRole,
            previewItems: Array(items.prefix(3))
        )
    }
}
