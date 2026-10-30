import Foundation
import SwiftData

struct LocalSharedTodoItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var title: String
    var isCompleted: Bool
    var note: String?
    var dueDate: Date?
    var createdByUserRecordName: String?
    let createdAt: Date
    var updatedAt: Date
    var fieldTimestamps: SharedTodoFieldTimestamps
}

struct LocalSharedTodoList: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var title: String
    var isShared: Bool
    var items: [LocalSharedTodoItem]
    var updatedAt: Date

    var completedCount: Int {
        items.filter(\.isCompleted).count
    }
}

final class SharedTodoStore {
    static let shared = SharedTodoStore()

    private let key = "social.sharedTodoStore.v1"
    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let domain = "shared-todo"
    private let kind = "list"

    init(
        defaults: UserDefaults = .standard,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        records = SwiftDataRecordStore(container: container)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        migrateLegacyDataIfNeeded()
    }

    func loadList() -> LocalSharedTodoList {
        if let row = records.records(domain: domain, kind: kind)?.first,
           let list = try? decoder.decode(LocalSharedTodoList.self, from: row.payload) {
            return list
        }

        return loadLegacyList() ?? emptyList()
    }

    private func loadLegacyList() -> LocalSharedTodoList? {
        if let data = defaults.data(forKey: key),
           let list = try? decoder.decode(LocalSharedTodoList.self, from: data) {
            return list
        }
        return nil
    }

    private func emptyList() -> LocalSharedTodoList {
        let now = Date()
        return LocalSharedTodoList(
            id: "shared-todo-list",
            title: "我的共享待办",
            isShared: false,
            items: [],
            updatedAt: now
        )
    }

    func updateListTitle(_ title: String) {
        mutateList { list in
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                list.title = trimmed
            }
        }
    }

    func setShared(_ isShared: Bool) {
        mutateList { list in
            list.isShared = isShared
        }
    }

    func upsertItem(
        id: String? = nil,
        title: String,
        isCompleted: Bool,
        note: String?,
        dueDate: Date?,
        currentUserRecordName: String?
    ) {
        let now = Date()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        mutateList { list in
            if let id, let index = list.items.firstIndex(where: { $0.id == id }) {
                var item = list.items[index]
                if item.title != trimmedTitle {
                    item.title = trimmedTitle
                    item.fieldTimestamps = SharedTodoFieldTimestamps(
                        titleUpdatedAt: now,
                        completionUpdatedAt: item.fieldTimestamps.completionUpdatedAt,
                        noteUpdatedAt: item.fieldTimestamps.noteUpdatedAt,
                        dueDateUpdatedAt: item.fieldTimestamps.dueDateUpdatedAt
                    )
                }
                if item.isCompleted != isCompleted {
                    item.isCompleted = isCompleted
                    item.fieldTimestamps = SharedTodoFieldTimestamps(
                        titleUpdatedAt: item.fieldTimestamps.titleUpdatedAt,
                        completionUpdatedAt: now,
                        noteUpdatedAt: item.fieldTimestamps.noteUpdatedAt,
                        dueDateUpdatedAt: item.fieldTimestamps.dueDateUpdatedAt
                    )
                }
                let sanitizedNote = sanitize(note)
                if item.note != sanitizedNote {
                    item.note = sanitizedNote
                    item.fieldTimestamps = SharedTodoFieldTimestamps(
                        titleUpdatedAt: item.fieldTimestamps.titleUpdatedAt,
                        completionUpdatedAt: item.fieldTimestamps.completionUpdatedAt,
                        noteUpdatedAt: now,
                        dueDateUpdatedAt: item.fieldTimestamps.dueDateUpdatedAt
                    )
                }
                if item.dueDate != dueDate {
                    item.dueDate = dueDate
                    item.fieldTimestamps = SharedTodoFieldTimestamps(
                        titleUpdatedAt: item.fieldTimestamps.titleUpdatedAt,
                        completionUpdatedAt: item.fieldTimestamps.completionUpdatedAt,
                        noteUpdatedAt: item.fieldTimestamps.noteUpdatedAt,
                        dueDateUpdatedAt: now
                    )
                }
                item.updatedAt = now
                list.items[index] = item
            } else {
                list.items.append(
                    LocalSharedTodoItem(
                        id: id ?? UUID().uuidString,
                        title: trimmedTitle,
                        isCompleted: isCompleted,
                        note: sanitize(note),
                        dueDate: dueDate,
                        createdByUserRecordName: currentUserRecordName,
                        createdAt: now,
                        updatedAt: now,
                        fieldTimestamps: .uniform(now)
                    )
                )
            }
            list.items.sort { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted && rhs.isCompleted
                }
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    func deleteItem(id: String, currentUserRecordName: String?) -> Bool {
        var didDelete = false
        mutateList { list in
            guard let index = list.items.firstIndex(where: { $0.id == id }) else { return }
            let item = list.items[index]
            guard item.createdByUserRecordName == nil || item.createdByUserRecordName == currentUserRecordName else {
                return
            }
            list.items.remove(at: index)
            didDelete = true
        }
        return didDelete
    }

    private func mutateList(_ mutate: (inout LocalSharedTodoList) -> Void) {
        var list = loadList()
        mutate(&list)
        list.updatedAt = Date()
        persist(list)
    }

    private func persist(_ list: LocalSharedTodoList) {
        guard let data = try? encoder.encode(list) else { return }
        _ = records.replace(
            domain: domain,
            kind: kind,
            with: [LocalDataRecordSeed(
                domain: domain,
                recordID: list.id,
                kind: kind,
                occurredAt: list.updatedAt,
                updatedAt: list.updatedAt,
                payload: data
            )]
        )
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "social.sharedTodoStore.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            return
        }
        let legacyData = defaults.data(forKey: key)
        let list: LocalSharedTodoList?
        if let legacyData {
            guard let decoded = try? decoder.decode(LocalSharedTodoList.self, from: legacyData) else { return }
            list = decoded
        } else {
            list = nil
        }
        let seeds = list.flatMap { list -> [LocalDataRecordSeed]? in
            guard let data = try? encoder.encode(list) else { return nil }
            return [LocalDataRecordSeed(
                domain: domain,
                recordID: list.id,
                kind: kind,
                occurredAt: list.updatedAt,
                updatedAt: list.updatedAt,
                payload: data
            )]
        } ?? []
        guard records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: key)
    }

    private func sanitize(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
