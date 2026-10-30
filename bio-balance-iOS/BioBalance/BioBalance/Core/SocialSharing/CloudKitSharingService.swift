import CloudKit
import Foundation
import os

struct CloudKitOwnedShareContext: Sendable {
    let rootRecordName: String
    let acceptedParticipantCount: Int
    let generatedAt: Date
}

struct SharedRemoteHealthSnapshot: Sendable {
    let recordID: CKRecord.ID
    let recordName: String
    let ownerRecordName: String?
    let permissionRole: FriendPermissionRole
    let snapshot: SharedHealthSnapshot
    let generatedAt: Date
}

struct CloudKitSharingGraphResult: Sendable {
    let snapshots: [SharedRemoteHealthSnapshot]
    let outgoingAcceptedRecordNames: Set<String>
    let outgoingPendingRecordNames: Set<String>
    let source: CloudKitResultSource
    let error: CloudKitDomainError?
}

struct CloudKitShareInvitePayload: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

struct CloudKitFriendSnapshotsResult: Sendable {
    let snapshots: [SharedRemoteHealthSnapshot]
    let source: CloudKitResultSource
    let error: CloudKitDomainError?
}

struct CollaborativeTodoSyncResult: Sendable {
    let list: SharedTodoList?
    let permissionRole: FriendPermissionRole
    let source: CloudKitResultSource
    let error: CloudKitDomainError?
}

struct CloudKitTodoItemRecord: Sendable {
    let recordID: CKRecord.ID
    let item: SharedTodoItem
}

protocol CloudKitCollaborativeListRepositoryProtocol: Sendable {
    func fetchTodoList(ownerUserRecordName: String?) async throws -> CollaborativeTodoSyncResult
    func upsertTodoListMetadata(_ list: SharedTodoList, ownerUserRecordName: String?) async throws -> SharedTodoList
    func upsertTodoItem(_ item: SharedTodoItem, listTitle: String, ownerUserRecordName: String?) async throws -> SharedTodoList
    func deleteTodoItem(itemID: String, ownerUserRecordName: String?, currentUserRecordName: String?) async throws -> SharedTodoList?
    func fetchTodoItems(ownerUserRecordName: String?) async throws -> [CloudKitTodoItemRecord]
    func rebuildTodoSummary(ownerUserRecordName: String?) async throws -> SharedTodoListSummary?
}

protocol CloudKitSharingRepositoryProtocol: Sendable {
    func isICloudAvailable() async -> Bool
    func currentUserRecordName() async -> String?
    func hasOwnedShare() async throws -> Bool
    func discardOwnedShareIfNoParticipants() async throws
    func upsertUserProfile(displayName: String, handle: String?, avatarSeed: String?, isSearchable: Bool, expectedUserRecordName: String?) async
    func lookupProfile(handle: String) async throws -> PublicUserProfile
    func fetchProfiles(recordNames: [String]) async throws -> [PublicUserProfile]
    func saveMySharedSnapshot(_ snapshot: SharedHealthSnapshot, expectedUserRecordName: String?) async throws -> CloudKitOwnedShareContext
    func prepareInvitePayload(for snapshot: SharedHealthSnapshot, expectedUserRecordName: String?) async throws -> CloudKitShareInvitePayload
    func fetchOwnedParticipants() async throws -> [CloudKitOwnedParticipant]
    func fetchSharedSnapshots() async throws -> CloudKitFriendSnapshotsResult
    func fetchSharingGraph() async throws -> CloudKitSharingGraphResult
    func fetchSharedSnapshot(recordID: CKRecord.ID) async throws -> SharedRemoteHealthSnapshot?
    func fetchCollaborativeTodoList(ownerUserRecordName: String?) async throws -> CollaborativeTodoSyncResult
    func syncCollaborativeTodoList(_ list: SharedTodoList, ownerUserRecordName: String?) async throws -> SharedTodoList
    func removeCollaborativeTodoList(ownerUserRecordName: String?) async throws
    func deleteCollaborativeTodoItem(itemID: String, ownerUserRecordName: String?, currentUserRecordName: String?) async throws -> SharedTodoList?
    func accept(metadata: CKShare.Metadata) async throws
    func removeParticipant(ownerUserRecordName: String?) async throws
    func leaveSharedSnapshot(recordName: String, ownerUserRecordName: String?) async throws
    func stopSharing() async throws
}

final class CloudKitSharingRepository: CloudKitSharingRepositoryProtocol, CloudKitCollaborativeListRepositoryProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "SocialSharing")

    nonisolated private enum Constants {
        // 健康摘要与共享待办位于同一个只读 CKShare。CloudKit 权限是 share 级别，
        // 未来若开放待办协作，必须拆到独立可写 zone/share，不能放宽健康摘要权限。
        // Zone 与 record type 集中登记在 CloudKitDataPolicy，保证与已部署 schema 一致。
        static let zoneName = CloudKitDataPolicy.Zone.friendHealthShare
        static let rootRecordName = "CurrentHealthShareRoot"
        static let recordType = CloudKitDataPolicy.RecordType.healthShareRoot
        static let userProfileType = CloudKitDataPolicy.RecordType.userProfile
        static let fieldOwnerUserRecordName = CloudKitDataPolicy.PublicProfile.ownerUserRecordNameField
        static let fieldOwnerDisplayName = "ownerDisplayName"
        static let fieldPayloadVersion = "payloadVersion"
        static let fieldGeneratedAt = "generatedAt"
        static let fieldPayloadData = "payloadData"
        static let fieldShareRecordName = "shareRecordName"
        static let fieldHandle = "handle"
        static let fieldAvatarSeed = "avatarSeed"
        static let fieldIsSearchable = "isSearchable"
        static let fieldUpdatedAt = "updatedAt"
        static let collaborativeTodoRecordType = CloudKitDataPolicy.RecordType.collaborativeTodoList
        static let collaborativeTodoItemRecordType = CloudKitDataPolicy.RecordType.collaborativeTodoItem
        static let collaborativeTodoRecordPrefix = "CollaborativeTodoList"
        static let collaborativeTodoItemRecordPrefix = "CollaborativeTodoItem"
        static let fieldTodoListData = "todoListData"
        static let fieldTodoListTitle = "todoListTitle"
        static let fieldTodoOwnerRecordName = "todoOwnerRecordName"
        static let fieldTodoListReference = "todoListReference"
        static let fieldTodoItemID = "todoItemID"
        static let fieldTodoTitle = "todoTitle"
        static let fieldTodoIsCompleted = "todoIsCompleted"
        static let fieldTodoNote = "todoNote"
        static let fieldTodoDueDate = "todoDueDate"
        static let fieldTodoCreatedBy = "todoCreatedBy"
        static let fieldTodoCreatedAt = "todoCreatedAt"
        static let fieldTodoTitleUpdatedAt = "todoTitleUpdatedAt"
        static let fieldTodoCompletionUpdatedAt = "todoCompletionUpdatedAt"
        static let fieldTodoNoteUpdatedAt = "todoNoteUpdatedAt"
        static let fieldTodoDueDateUpdatedAt = "todoDueDateUpdatedAt"
        static let shareTitle = "好友健康摘要"
    }

    private let container: CKContainer
    private let privateDB: CKDatabase
    private let sharedDB: CKDatabase
    private let publicDB: CKDatabase
    private let client: CloudKitClientProtocol
    private let executor: CloudKitOperationExecutor
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        container: CKContainer = CloudKitDataPolicy.makeContainer(),
        client: CloudKitClientProtocol = CloudKitClient(),
        executor: CloudKitOperationExecutor = CloudKitOperationExecutor()
    ) {
        self.container = container
        self.privateDB = container.privateCloudDatabase
        self.sharedDB = container.sharedCloudDatabase
        self.publicDB = container.publicCloudDatabase
        self.client = client
        self.executor = executor
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func isICloudAvailable() async -> Bool {
        do {
            let status = try await executor.run(
                context: CloudKitLoggerContext(operation: "accountStatus")
            ) {
                try await self.client.accountStatus(container: self.container)
            }
            return status == .available
        } catch {
            return false
        }
    }

    func currentUserRecordName() async -> String? {
        do {
            let recordID = try await fetchUserRecordID()
            return recordID.recordName
        } catch {
            return nil
        }
    }

    func hasOwnedShare() async throws -> Bool {
        let zoneID = CKRecordZone.ID(zoneName: Constants.zoneName, ownerName: CKCurrentUserDefaultName)
        let rootID = CKRecord.ID(recordName: Constants.rootRecordName, zoneID: zoneID)
        let root: CKRecord
        do {
            guard let fetched = try await fetch(recordID: rootID, from: privateDB, scope: .private) else {
                return false
            }
            root = fetched
        } catch let error as CloudKitDomainError {
            guard error == .unknownItem || error == .zoneNotFound else { throw error }
            return false
        }
        if try await resolveExistingShare(for: root) != nil {
            return true
        }

        // 旧版本只要打开好友页就会创建未共享的健康 root。没有 CKShare 时整区
        // 都没有接收方，删除 orphan zone，避免继续保留无用途的云端健康副本。
        do {
            try await executor.run(
                context: CloudKitLoggerContext(
                    operation: "cleanup-unshared-health-zone",
                    database: .private,
                    zoneID: zoneID.zoneName
                )
            ) { [client, privateDB] in
                try await client.delete(zoneID: zoneID, in: privateDB)
            }
        } catch let error as CloudKitDomainError {
            // 多设备可能同时发现并清理同一个旧 zone。已经不存在等同于清理成功。
            guard error == .unknownItem || error == .zoneNotFound else { throw error }
        }
        return false
    }

    /// 用户取消首次邀请投递时清理无人参与的 root/share；已有好友的 share 必须保留。
    func discardOwnedShareIfNoParticipants() async throws {
        guard let share = try await fetchOwnedShare() else { return }
        let hasOtherParticipants = share.participants.contains { $0.role != .owner }
        guard !hasOtherParticipants else { return }

        let zoneID = CKRecordZone.ID(zoneName: Constants.zoneName, ownerName: CKCurrentUserDefaultName)
        do {
            try await executor.run(
                context: CloudKitLoggerContext(
                    operation: "discard-empty-health-share",
                    database: .private,
                    zoneID: zoneID.zoneName,
                    shareID: share.recordID.recordName
                )
            ) { [client, privateDB] in
                try await client.delete(zoneID: zoneID, in: privateDB)
            }
        } catch let error as CloudKitDomainError {
            // 系统分享面板和其他设备都可能先一步删除空 share/zone。
            guard error == .unknownItem || error == .zoneNotFound else { throw error }
        }
    }

    func upsertUserProfile(
        displayName: String,
        handle: String? = nil,
        avatarSeed: String? = nil,
        isSearchable: Bool = false,
        expectedUserRecordName: String? = nil
    ) async {
        guard let ownerUserRecordName = try? await requireCurrentUserRecordName(
            expectedUserRecordName
        ) else { return }
        let query = CKQuery(
            recordType: Constants.userProfileType,
            predicate: NSPredicate(
                format: "%K == %@",
                Constants.fieldOwnerUserRecordName,
                ownerUserRecordName
            )
        )
        guard let candidates = try? await queryRecords(query, in: publicDB, scope: .public) else {
            return
        }
        let existing = Self.mostRecentValidProfileRecord(
            candidates,
            expectedOwnerUserRecordName: ownerUserRecordName
        )
        let recordID = CKRecord.ID(recordName: CloudKitDataPolicy.PublicProfile.recordName())
        let record = existing ?? CKRecord(recordType: Constants.userProfileType, recordID: recordID)
        record[Constants.fieldOwnerUserRecordName] = ownerUserRecordName as CKRecordValue
        record[Constants.fieldOwnerDisplayName] = displayName as CKRecordValue
        record[Constants.fieldHandle] = resolveHandle(
            displayName: displayName,
            fallback: handle ?? ownerUserRecordName
        ) as CKRecordValue
        if let avatarSeed {
            record[Constants.fieldAvatarSeed] = avatarSeed as CKRecordValue
        }
        record[Constants.fieldIsSearchable] = NSNumber(value: isSearchable)
        record[Constants.fieldUpdatedAt] = Date() as CKRecordValue
        guard (try? await requireCurrentUserRecordName(ownerUserRecordName)) != nil else { return }
        _ = try? await save(record: record, in: publicDB, scope: .public)
    }

    func lookupProfile(handle: String) async throws -> PublicUserProfile {
        let query = CKQuery(
            recordType: Constants.userProfileType,
            predicate: NSPredicate(
                format: "%K == %@ AND %K == %@",
                Constants.fieldHandle,
                handle,
                Constants.fieldIsSearchable,
                NSNumber(value: true)
            )
        )
        let records = try await queryRecords(query, in: publicDB, scope: .public)
        let profiles = records.compactMap { try? Self.profile(from: $0) }
        let profilesByOwner = Dictionary(grouping: profiles, by: \.recordName)
        guard profilesByOwner.count == 1,
              let candidates = profilesByOwner.values.first,
              let profile = Self.mostRecentProfile(candidates) else {
            throw CloudKitDomainError.profileNotFound
        }
        return profile
    }

    func fetchProfiles(recordNames: [String]) async throws -> [PublicUserProfile] {
        try await withThrowingTaskGroup(of: PublicUserProfile?.self) { group in
            for recordName in recordNames {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    let query = CKQuery(
                        recordType: Constants.userProfileType,
                        predicate: NSPredicate(
                            format: "%K == %@",
                            Constants.fieldOwnerUserRecordName,
                            recordName
                        )
                    )
                    let records = try await self.queryRecords(query, in: self.publicDB, scope: .public)
                    let profiles = records.compactMap { try? Self.profile(from: $0) }
                        .filter { $0.recordName == recordName }
                    guard let profile = Self.mostRecentProfile(profiles) else {
                        return nil
                    }
                    return profile
                }
            }

            var profiles: [PublicUserProfile] = []
            for try await profile in group {
                if let profile {
                    profiles.append(profile)
                }
            }
            return profiles
        }
    }

    func saveMySharedSnapshot(
        _ snapshot: SharedHealthSnapshot,
        expectedUserRecordName: String? = nil
    ) async throws -> CloudKitOwnedShareContext {
        let rootRecord = try await upsertRootRecord(
            for: snapshot,
            saveIfChangedOnly: true,
            expectedUserRecordName: expectedUserRecordName
        )
        let share = try await resolveExistingShare(for: rootRecord)
        _ = try await requireCurrentUserRecordName(expectedUserRecordName)
        let acceptedCount = (share?.participants ?? []).filter {
            $0.role != .owner && $0.acceptanceStatus == .accepted
        }.count

        return CloudKitOwnedShareContext(
            rootRecordName: rootRecord.recordID.recordName,
            acceptedParticipantCount: acceptedCount,
            generatedAt: snapshot.generatedAt
        )
    }

    func prepareInvitePayload(
        for snapshot: SharedHealthSnapshot,
        expectedUserRecordName: String? = nil
    ) async throws -> CloudKitShareInvitePayload {
        var rootRecord = try await upsertRootRecord(
            for: snapshot,
            saveIfChangedOnly: false,
            expectedUserRecordName: expectedUserRecordName
        )
        let share = try await resolveShareForInvite(rootRecord: rootRecord)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = Constants.shareTitle as CKRecordValue
        rootRecord[Constants.fieldShareRecordName] = share.recordID.recordName as CKRecordValue

        do {
            _ = try await requireCurrentUserRecordName(expectedUserRecordName)
            _ = try await modify(
                recordsToSave: [rootRecord, share],
                recordIDsToDelete: [],
                in: privateDB,
                scope: .private,
                contextName: "prepareInvitePayload.modify"
            )
        } catch let error as CloudKitDomainError {
            if shouldRecoverExistingShare(from: error) {
                let recoveredRoot = try await fetch(recordID: rootRecord.recordID, from: privateDB, scope: .private) ?? rootRecord
                if let existingShare = try await resolveExistingShare(for: recoveredRoot) {
                    _ = try await requireCurrentUserRecordName(expectedUserRecordName)
                    existingShare.publicPermission = .none
                    existingShare[CKShare.SystemFieldKey.title] = Constants.shareTitle as CKRecordValue
                    return CloudKitShareInvitePayload(share: existingShare, container: container)
                }
            }
            throw error
        }

        rootRecord = try await fetch(recordID: rootRecord.recordID, from: privateDB, scope: .private) ?? rootRecord
        let validatedShare = try await resolveExistingShare(for: rootRecord) ?? share
        _ = try await requireCurrentUserRecordName(expectedUserRecordName)
        return CloudKitShareInvitePayload(share: validatedShare, container: container)
    }

    func fetchOwnedParticipants() async throws -> [CloudKitOwnedParticipant] {
        guard let share = try await fetchOwnedShare() else { return [] }
        return share.participants
            .filter { $0.role != .owner }
            .map { participant in
                CloudKitOwnedParticipant(
                    userRecordName: participant.userIdentity.userRecordID?.recordName,
                    displayName: participant.userIdentity.nameComponents?.givenName,
                    acceptanceStatus: String(describing: participant.acceptanceStatus)
                )
            }
    }

    func fetchSharedSnapshots() async throws -> CloudKitFriendSnapshotsResult {
        let zoneIDs = try await fetchAllRecordZoneIDs(in: sharedDB, scope: .shared)
        var allRecords: [CKRecord] = []
        var partialError: CloudKitDomainError?

        for zoneID in zoneIDs {
            do {
                let records = try await queryAllRecords(
                    ofType: Constants.recordType,
                    in: sharedDB,
                    scope: .shared,
                    zoneID: zoneID
                )
                allRecords.append(contentsOf: records)
            } catch {
                partialError = executor.map(error)
                let description = partialError?.localizedDescription ?? "unknown"
                Self.logger.error("[社交共享] 拉取好友摘要出现部分失败 zone=\(zoneID.zoneName, privacy: .public) error=\(description, privacy: .public)")
            }
        }

        let snapshots = try allRecords.compactMap { try recordToSharedSnapshot($0) }
            .sorted { $0.generatedAt > $1.generatedAt }

        if let partialError {
            return CloudKitFriendSnapshotsResult(
                snapshots: snapshots,
                source: .partial,
                error: .partialFailure(message: partialError.localizedDescription)
            )
        }

        return CloudKitFriendSnapshotsResult(snapshots: snapshots, source: .fresh, error: nil)
    }

    func fetchSharingGraph() async throws -> CloudKitSharingGraphResult {
        let snapshotsResult = try await fetchSharedSnapshots()
        let participants = (try? await fetchOwnedParticipants()) ?? []
        var accepted = Set<String>()
        var pending = Set<String>()
        for participant in participants {
            guard let recordName = participant.userRecordName else { continue }
            if participant.acceptanceStatus.lowercased().contains("accepted") {
                accepted.insert(recordName)
            } else {
                pending.insert(recordName)
            }
        }
        return CloudKitSharingGraphResult(
            snapshots: snapshotsResult.snapshots,
            outgoingAcceptedRecordNames: accepted,
            outgoingPendingRecordNames: pending,
            source: snapshotsResult.source,
            error: snapshotsResult.error
        )
    }

    func fetchSharedSnapshot(recordID: CKRecord.ID) async throws -> SharedRemoteHealthSnapshot? {
        guard let record = try await fetch(recordID: recordID, from: sharedDB, scope: .shared) else {
            return nil
        }
        return try recordToSharedSnapshot(record)
    }

    func fetchTodoList(ownerUserRecordName: String?) async throws -> CollaborativeTodoSyncResult {
        let snapshotResult = try await fetchSharedSnapshots()
        let matchedSnapshot = snapshotResult.snapshots.first { $0.ownerRecordName == ownerUserRecordName }

        do {
            let items = try await fetchTodoItems(ownerUserRecordName: ownerUserRecordName)
            if let root = try await fetchTodoRootRecord(ownerUserRecordName: ownerUserRecordName, database: sharedDB, scope: .shared) {
                let list = try makeSharedTodoList(from: root, items: items, fallbackSummary: matchedSnapshot?.snapshot.sharedTodoListSummary)
                return CollaborativeTodoSyncResult(
                    list: list,
                    permissionRole: matchedSnapshot?.permissionRole ?? .readOnly,
                    source: snapshotResult.source,
                    error: snapshotResult.error
                )
            }

            if let fallbackSummary = matchedSnapshot?.snapshot.sharedTodoListSummary {
                let migratedList = makeList(from: fallbackSummary)
                return CollaborativeTodoSyncResult(
                    list: migratedList,
                    permissionRole: matchedSnapshot?.permissionRole ?? .readOnly,
                    source: .staleFallback,
                    error: snapshotResult.error
                )
            }
        } catch {
            return CollaborativeTodoSyncResult(
                list: nil,
                permissionRole: matchedSnapshot?.permissionRole ?? .readOnly,
                source: .staleFallback,
                error: executor.map(error)
            )
        }

        return CollaborativeTodoSyncResult(
            list: nil,
            permissionRole: matchedSnapshot?.permissionRole ?? .readOnly,
            source: .staleFallback,
            error: snapshotResult.error
        )
    }

    func fetchCollaborativeTodoList(ownerUserRecordName: String?) async throws -> CollaborativeTodoSyncResult {
        try await fetchTodoList(ownerUserRecordName: ownerUserRecordName)
    }

    func syncCollaborativeTodoList(_ list: SharedTodoList, ownerUserRecordName: String?) async throws -> SharedTodoList {
        let current = try await requireCurrentUserRecordName(ownerUserRecordName)

        let existingItems = try await fetchTodoItems(ownerUserRecordName: ownerUserRecordName)
        _ = try await requireCurrentUserRecordName(current)
        _ = try await upsertTodoListMetadata(list, ownerUserRecordName: ownerUserRecordName)
        _ = try await requireCurrentUserRecordName(current)
        guard let rootRecord = try await fetchTodoRootRecord(
            ownerUserRecordName: ownerUserRecordName,
            database: privateDB,
            scope: .private
        ) else {
            throw CloudKitDomainError.invalidRecord
        }

        for item in list.items {
            _ = try await saveTodoItemRecord(
                item,
                rootRecord: rootRecord,
                expectedUserRecordName: current
            )
        }

        let retainedItemIDs = Set(list.items.map(\.id))
        let deletedRecordIDs = existingItems
            .filter { !retainedItemIDs.contains($0.item.id) }
            .map(\.recordID)
        try await deleteOwnedTodoRecords(
            deletedRecordIDs,
            contextName: "syncCollaborativeTodoList.deleteRemovedItems",
            expectedUserRecordName: current
        )

        _ = try await requireCurrentUserRecordName(current)
        let summary = try await rebuildTodoSummary(ownerUserRecordName: ownerUserRecordName)
        _ = try await requireCurrentUserRecordName(current)
        return SharedTodoList(
            id: summary?.id ?? list.id,
            title: summary?.title ?? list.title,
            ownerUserRecordName: ownerUserRecordName ?? current,
            items: list.items,
            updatedAt: summary?.updatedAt ?? list.updatedAt,
            lastEditedByUserRecordName: summary?.lastEditedByUserRecordName ?? list.lastEditedByUserRecordName,
            permissionRole: .collaborator
        )
    }

    func removeCollaborativeTodoList(ownerUserRecordName: String?) async throws {
        let current = try await requireCurrentUserRecordName(ownerUserRecordName)

        let items = try await fetchTodoItems(ownerUserRecordName: ownerUserRecordName)
        let root = try await fetchTodoRootRecord(
            ownerUserRecordName: ownerUserRecordName,
            database: privateDB,
            scope: .private
        )
        let recordIDs = items.map(\.recordID) + [root?.recordID].compactMap { $0 }
        try await deleteOwnedTodoRecords(
            recordIDs,
            contextName: "removeCollaborativeTodoList.modify",
            expectedUserRecordName: current
        )
        _ = try await requireCurrentUserRecordName(current)
        try await syncTodoSummaryIntoSnapshot(nil, ownerUserRecordName: ownerUserRecordName)
        _ = try await requireCurrentUserRecordName(current)
    }

    /// CloudKit 单次 modify 有记录数上限；分批删除也保证 list root 排在最后，
    /// 不会先删父记录再留下无法通过层级访问的 item。
    private func deleteOwnedTodoRecords(
        _ recordIDs: [CKRecord.ID],
        contextName: String,
        expectedUserRecordName: String
    ) async throws {
        let batchSize = 200
        for start in stride(from: 0, to: recordIDs.count, by: batchSize) {
            let end = min(start + batchSize, recordIDs.count)
            _ = try await requireCurrentUserRecordName(expectedUserRecordName)
            _ = try await modify(
                recordsToSave: [],
                recordIDsToDelete: Array(recordIDs[start..<end]),
                in: privateDB,
                scope: .private,
                contextName: contextName
            )
        }
        _ = try await requireCurrentUserRecordName(expectedUserRecordName)
    }

    func deleteCollaborativeTodoItem(itemID: String, ownerUserRecordName: String?, currentUserRecordName: String?) async throws -> SharedTodoList? {
        try await deleteTodoItem(itemID: itemID, ownerUserRecordName: ownerUserRecordName, currentUserRecordName: currentUserRecordName)
    }

    func accept(metadata: CKShare.Metadata) async throws {
        let rootRecordName = metadata.hierarchicalRootRecordID?.recordName ?? metadata.share.recordID.recordName
        try await executor.run(
            context: CloudKitLoggerContext(
                operation: "acceptShare",
                recordID: rootRecordName,
                shareID: metadata.share.recordID.recordName
            )
        ) {
            try await self.client.accept(metadata: metadata, container: self.container)
        }
    }

    func removeParticipant(ownerUserRecordName: String?) async throws {
        guard let ownerUserRecordName else {
            throw CloudKitDomainError.participantNotFound
        }
        // 撤回邀请/停止共享是幂等操作；另一台设备已移除时直接视为成功。
        guard let share = try await fetchOwnedShare() else { return }

        guard let participant = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == ownerUserRecordName
        }) else { return }

        share.removeParticipant(participant)
        _ = try await modify(
            recordsToSave: [share],
            recordIDsToDelete: [],
            in: privateDB,
            scope: .private,
            contextName: "removeParticipant.modify"
        )
    }

    /// 接收方退出别人拥有的 CKShare。删除 shared database 中的 CKShare record
    /// 只会移除当前用户的参与关系，不会删除 owner 的私有数据。
    func leaveSharedSnapshot(recordName: String, ownerUserRecordName: String?) async throws {
        guard let ownerUserRecordName else {
            throw CloudKitDomainError.participantNotFound
        }

        let zoneID = CKRecordZone.ID(
            zoneName: Constants.zoneName,
            ownerName: ownerUserRecordName
        )
        let rootID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let root: CKRecord
        do {
            guard let fetched = try await fetch(recordID: rootID, from: sharedDB, scope: .shared) else {
                return
            }
            root = fetched
        } catch let error as CloudKitDomainError {
            // 已由其他设备退出，或 owner 已停止分享，均等同于目标状态已完成。
            guard error == .unknownItem || error == .zoneNotFound else { throw error }
            return
        }
        guard let shareID = root.share?.recordID else {
            throw CloudKitDomainError.invalidRecord
        }

        _ = try await modify(
            recordsToSave: [],
            recordIDsToDelete: [shareID],
            in: sharedDB,
            scope: .shared,
            contextName: "leaveSharedSnapshot.modify"
        )
    }

    func stopSharing() async throws {
        let zoneID = CKRecordZone.ID(zoneName: Constants.zoneName, ownerName: CKCurrentUserDefaultName)
        do {
            // 整个 zone 只属于好友分享域。删除 zone 可同时撤销 CKShare 并清理
            // 健康 root、待办层级和未来新增的共享子记录，不会影响本地数据。
            try await executor.run(
                context: CloudKitLoggerContext(
                    operation: "stopSharing.deleteZone",
                    database: .private,
                    zoneID: zoneID.zoneName
                )
            ) { [client, privateDB] in
                try await client.delete(zoneID: zoneID, in: privateDB)
            }
        } catch let error as CloudKitDomainError {
            switch error {
            case .unknownItem, .zoneNotFound:
                return
            default:
                throw error
            }
        }
    }

    private func upsertRootRecord(
        for snapshot: SharedHealthSnapshot,
        saveIfChangedOnly: Bool,
        expectedUserRecordName: String?
    ) async throws -> CKRecord {
        // 创建区域或记录前先解析已认证的 CloudKit 身份；
        // 否则共享后，占位所有者会变成攻击者可控的元数据。
        let userRecordName = try await requireCurrentUserRecordName(expectedUserRecordName)
        try await ensureZone()
        _ = try await requireCurrentUserRecordName(userRecordName)
        let zoneID = CKRecordZone.ID(zoneName: Constants.zoneName, ownerName: CKCurrentUserDefaultName)
        let rootID = CKRecord.ID(recordName: Constants.rootRecordName, zoneID: zoneID)
        let payloadData = try encode(snapshot: snapshot)

        let rootRecord = try await fetch(recordID: rootID, from: privateDB, scope: .private) ?? CKRecord(recordType: Constants.recordType, recordID: rootID)
        let existingPayload = rootRecord[Constants.fieldPayloadData] as? Data
        let existingOwnerUserRecordName = rootRecord[Constants.fieldOwnerUserRecordName] as? String

        rootRecord[Constants.fieldOwnerUserRecordName] = userRecordName as CKRecordValue
        rootRecord[Constants.fieldOwnerDisplayName] = snapshot.ownerDisplayName as CKRecordValue
        rootRecord[Constants.fieldPayloadVersion] = NSNumber(value: snapshot.payloadVersion)
        rootRecord[Constants.fieldGeneratedAt] = snapshot.generatedAt as CKRecordValue
        rootRecord[Constants.fieldPayloadData] = payloadData as CKRecordValue

        if !saveIfChangedOnly
            || existingPayload != payloadData
            || existingOwnerUserRecordName != userRecordName {
            _ = try await requireCurrentUserRecordName(userRecordName)
            _ = try await modify(
                recordsToSave: [rootRecord],
                recordIDsToDelete: [],
                in: privateDB,
                scope: .private,
                contextName: "upsertRootRecord.modify"
            )
        }

        let savedRecord = try await fetch(recordID: rootID, from: privateDB, scope: .private) ?? rootRecord
        _ = try await requireCurrentUserRecordName(userRecordName)
        return savedRecord
    }

    private func recordToSharedSnapshot(_ record: CKRecord) throws -> SharedRemoteHealthSnapshot? {
        let zoneOwnerRecordName = record.recordID.zoneID.ownerName
        guard let declaredOwnerRecordName = record[Constants.fieldOwnerUserRecordName] as? String,
              declaredOwnerRecordName == zoneOwnerRecordName,
              let payloadData = record[Constants.fieldPayloadData] as? Data,
              let decodedSnapshot = try? decoder.decode(SharedHealthSnapshot.self, from: payloadData) else {
            return nil
        }

        let snapshot = decodedSnapshot.sanitizedForFriendRecipient()
        let generatedAt = (record[Constants.fieldGeneratedAt] as? Date) ?? snapshot.generatedAt
        // 这份 share 固定为 read-only。待办和健康摘要在同一 CKShare 中，不能伪造
        // 字段级“可协作”权限，否则接收方写入会失败或迫使健康摘要一起变为可写。
        let permissionRole: FriendPermissionRole = .readOnly
        return SharedRemoteHealthSnapshot(
            recordID: record.recordID,
            recordName: record.recordID.recordName,
            ownerRecordName: zoneOwnerRecordName,
            permissionRole: permissionRole,
            snapshot: snapshot,
            generatedAt: generatedAt
        )
    }

    private func collaborativeTodoRootRecordID(ownerUserRecordName: String?, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "\(Constants.collaborativeTodoRecordPrefix).\(ownerUserRecordName ?? CKCurrentUserDefaultName)",
            zoneID: zoneID
        )
    }

    private func collaborativeTodoItemRecordID(itemID: String, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "\(Constants.collaborativeTodoItemRecordPrefix).\(itemID)",
            zoneID: zoneID
        )
    }

    private func fetchTodoRootRecord(
        ownerUserRecordName: String?,
        database: CKDatabase,
        scope: CloudKitDatabaseScope
    ) async throws -> CKRecord? {
        let zoneOwnerName = scope == .shared
            ? ownerUserRecordName ?? CKCurrentUserDefaultName
            : CKCurrentUserDefaultName
        let zoneID = CKRecordZone.ID(zoneName: Constants.zoneName, ownerName: zoneOwnerName)
        let recordID = collaborativeTodoRootRecordID(ownerUserRecordName: ownerUserRecordName, zoneID: zoneID)
        return try await fetch(recordID: recordID, from: database, scope: scope)
    }

    func fetchTodoItems(ownerUserRecordName: String?) async throws -> [CloudKitTodoItemRecord] {
        let current = await currentUserRecordName()
        let isOwner = ownerUserRecordName == nil || ownerUserRecordName == current
        let database = isOwner ? privateDB : sharedDB
        let scope: CloudKitDatabaseScope = isOwner ? .private : .shared
        guard let rootRecord = try await fetchTodoRootRecord(
            ownerUserRecordName: ownerUserRecordName,
            database: database,
            scope: scope
        ) else {
            return []
        }

        let reference = CKRecord.Reference(recordID: rootRecord.recordID, action: .none)
        let query = CKQuery(
            recordType: Constants.collaborativeTodoItemRecordType,
            predicate: NSPredicate(format: "%K == %@", Constants.fieldTodoListReference, reference)
        )
        let records = try await queryRecords(
            query,
            in: database,
            scope: scope,
            zoneID: rootRecord.recordID.zoneID
        )
        return records.compactMap(makeTodoItemRecord)
    }

    func upsertTodoListMetadata(_ list: SharedTodoList, ownerUserRecordName: String?) async throws -> SharedTodoList {
        let currentUserRecordName = try await requireCurrentUserRecordName(ownerUserRecordName)
        let zoneID = CKRecordZone.ID(zoneName: Constants.zoneName, ownerName: CKCurrentUserDefaultName)
        let recordID = collaborativeTodoRootRecordID(ownerUserRecordName: ownerUserRecordName, zoneID: zoneID)
        let record = try await fetch(recordID: recordID, from: privateDB, scope: .private) ?? CKRecord(
            recordType: Constants.collaborativeTodoRecordType,
            recordID: recordID
        )

        // `CKShare(rootRecord:)` 只共享 root 的层级后代，不会自动共享 zone 中的
        // 无关记录。待办 root 必须挂到 HealthShareRoot，接收方才能在 shared DB 读取。
        let healthRootID = CKRecord.ID(recordName: Constants.rootRecordName, zoneID: zoneID)
        record.parent = CKRecord.Reference(recordID: healthRootID, action: .none)

        record[Constants.fieldTodoListTitle] = list.title as CKRecordValue
        record[Constants.fieldTodoOwnerRecordName] = (ownerUserRecordName ?? currentUserRecordName) as CKRecordValue
        record[Constants.fieldUpdatedAt] = list.updatedAt as CKRecordValue
        record[Constants.fieldOwnerDisplayName] = (list.lastEditedByUserRecordName ?? "unknown") as CKRecordValue

        _ = try await requireCurrentUserRecordName(currentUserRecordName)
        _ = try await modify(
            recordsToSave: [record],
            recordIDsToDelete: [],
            in: privateDB,
            scope: .private,
            contextName: "upsertTodoListMetadata.modify"
        )
        _ = try await requireCurrentUserRecordName(currentUserRecordName)
        return list
    }

    func upsertTodoItem(_ item: SharedTodoItem, listTitle: String, ownerUserRecordName: String?) async throws -> SharedTodoList {
        let currentUserRecordName = try await requireCurrentUserRecordName(ownerUserRecordName)

        let rootList = SharedTodoList(
            id: "shared-todo-list",
            title: listTitle,
            ownerUserRecordName: ownerUserRecordName,
            items: [],
            updatedAt: item.updatedAt,
            lastEditedByUserRecordName: currentUserRecordName,
            permissionRole: .collaborator
        )
        _ = try await upsertTodoListMetadata(rootList, ownerUserRecordName: ownerUserRecordName)
        guard let rootRecord = try await fetchTodoRootRecord(
            ownerUserRecordName: ownerUserRecordName,
            database: privateDB,
            scope: .private
        ) else {
            throw CloudKitDomainError.invalidRecord
        }
        _ = try await saveTodoItemRecord(
            item,
            rootRecord: rootRecord,
            expectedUserRecordName: currentUserRecordName
        )

        let rebuiltSummary = try await rebuildTodoSummary(ownerUserRecordName: ownerUserRecordName)
        return SharedTodoList(
            id: rebuiltSummary?.id ?? rootList.id,
            title: rebuiltSummary?.title ?? listTitle,
            ownerUserRecordName: ownerUserRecordName,
            items: try await fetchTodoItems(ownerUserRecordName: ownerUserRecordName).map(\.item),
            updatedAt: rebuiltSummary?.updatedAt ?? item.updatedAt,
            lastEditedByUserRecordName: rebuiltSummary?.lastEditedByUserRecordName ?? currentUserRecordName,
            permissionRole: rebuiltSummary?.permissionRole ?? .collaborator
        )
    }

    private func saveTodoItemRecord(
        _ item: SharedTodoItem,
        rootRecord: CKRecord,
        expectedUserRecordName: String
    ) async throws -> CKRecord {
        let recordID = collaborativeTodoItemRecordID(
            itemID: item.id,
            zoneID: rootRecord.recordID.zoneID
        )
        let record = try await fetch(recordID: recordID, from: privateDB, scope: .private) ?? CKRecord(
            recordType: Constants.collaborativeTodoItemRecordType,
            recordID: recordID
        )
        let listReference = CKRecord.Reference(recordID: rootRecord.recordID, action: .none)
        record.parent = listReference
        record[Constants.fieldTodoItemID] = item.id as CKRecordValue
        record[Constants.fieldTodoListReference] = listReference
        record[Constants.fieldTodoTitle] = item.title as CKRecordValue
        record[Constants.fieldTodoIsCompleted] = NSNumber(value: item.isCompleted)
        if let note = item.note {
            record[Constants.fieldTodoNote] = note as CKRecordValue
        } else {
            record[Constants.fieldTodoNote] = nil
        }
        if let dueDate = item.dueDate {
            record[Constants.fieldTodoDueDate] = dueDate as CKRecordValue
        } else {
            record[Constants.fieldTodoDueDate] = nil
        }
        record[Constants.fieldTodoCreatedBy] = (item.createdByUserRecordName ?? "unknown") as CKRecordValue
        record[Constants.fieldTodoCreatedAt] = item.createdAt as CKRecordValue
        record[Constants.fieldUpdatedAt] = item.updatedAt as CKRecordValue
        record[Constants.fieldTodoTitleUpdatedAt] = item.fieldTimestamps.titleUpdatedAt as CKRecordValue
        record[Constants.fieldTodoCompletionUpdatedAt] = item.fieldTimestamps.completionUpdatedAt as CKRecordValue
        record[Constants.fieldTodoNoteUpdatedAt] = item.fieldTimestamps.noteUpdatedAt as CKRecordValue
        record[Constants.fieldTodoDueDateUpdatedAt] = item.fieldTimestamps.dueDateUpdatedAt as CKRecordValue

        _ = try await requireCurrentUserRecordName(expectedUserRecordName)
        _ = try await modify(
            recordsToSave: [record],
            recordIDsToDelete: [],
            in: privateDB,
            scope: .private,
            contextName: "upsertTodoItem.modify"
        )
        _ = try await requireCurrentUserRecordName(expectedUserRecordName)
        return record
    }

    func deleteTodoItem(itemID: String, ownerUserRecordName: String?, currentUserRecordName fallbackCurrentUserRecordName: String?) async throws -> SharedTodoList? {
        let resolvedCurrentUserRecordName = await currentUserRecordName() ?? fallbackCurrentUserRecordName
        let isOwner = ownerUserRecordName == nil || ownerUserRecordName == resolvedCurrentUserRecordName
        guard isOwner else { throw CloudKitDomainError.permissionFailure }
        let zoneID = CKRecordZone.ID(zoneName: Constants.zoneName, ownerName: CKCurrentUserDefaultName)
        let recordID = collaborativeTodoItemRecordID(itemID: itemID, zoneID: zoneID)

        guard let existing = try await fetch(recordID: recordID, from: privateDB, scope: .private) else {
            return nil
        }

        let creator = existing[Constants.fieldTodoCreatedBy] as? String
        guard creator == nil || creator == resolvedCurrentUserRecordName else {
            throw CloudKitDomainError.permissionFailure
        }

        _ = try await modify(
            recordsToSave: [],
            recordIDsToDelete: [recordID],
            in: privateDB,
            scope: .private,
            contextName: "deleteTodoItem.modify"
        )

        let summary = try await rebuildTodoSummary(ownerUserRecordName: ownerUserRecordName)
        return summary.map { summary in
            SharedTodoList(
                id: summary.id,
                title: summary.title,
                ownerUserRecordName: summary.ownerUserRecordName,
                items: summary.previewItems,
                updatedAt: summary.updatedAt,
                lastEditedByUserRecordName: summary.lastEditedByUserRecordName,
                permissionRole: .collaborator
            )
        }
    }

    func rebuildTodoSummary(ownerUserRecordName: String?) async throws -> SharedTodoListSummary? {
        let current = await currentUserRecordName()
        let items = try await fetchTodoItems(ownerUserRecordName: ownerUserRecordName).map(\.item)
        let isOwner = ownerUserRecordName == nil || ownerUserRecordName == current
        let scope: CloudKitDatabaseScope = isOwner ? .private : .shared
        let database: CKDatabase = isOwner ? privateDB : sharedDB

        guard let rootRecord = try await fetchTodoRootRecord(ownerUserRecordName: ownerUserRecordName, database: database, scope: scope) else {
            return nil
        }

        let summary = SharedTodoListSummary(
            id: rootRecord.recordID.recordName,
            title: (rootRecord[Constants.fieldTodoListTitle] as? String) ?? "共享待办",
            ownerUserRecordName: ownerUserRecordName,
            itemCount: items.count,
            completedCount: items.filter(\.isCompleted).count,
            updatedAt: (rootRecord[Constants.fieldUpdatedAt] as? Date) ?? Date(),
            lastEditedByUserRecordName: rootRecord[Constants.fieldOwnerDisplayName] as? String,
            permissionRole: isOwner ? .collaborator : .readOnly,
            previewItems: Array(items.prefix(3))
        )

        try await syncTodoSummaryIntoSnapshot(summary, ownerUserRecordName: ownerUserRecordName)
        return summary
    }

    private func syncTodoSummaryIntoSnapshot(_ summary: SharedTodoListSummary?, ownerUserRecordName: String?) async throws {
        let current = await currentUserRecordName()
        let isOwner = ownerUserRecordName == nil || ownerUserRecordName == current
        let scope: CloudKitDatabaseScope = isOwner ? .private : .shared
        let database: CKDatabase = isOwner ? privateDB : sharedDB

        guard let snapshotRoot = try await fetchHealthRootRecord(ownerUserRecordName: ownerUserRecordName, database: database, scope: scope) else {
            return
        }
        guard let payloadData = snapshotRoot[Constants.fieldPayloadData] as? Data,
              var snapshot = try? decoder.decode(SharedHealthSnapshot.self, from: payloadData) else {
            return
        }

        snapshot = SharedHealthSnapshot(
            ownerUserID: snapshot.ownerUserID,
            ownerDisplayName: snapshot.ownerDisplayName,
            generatedAt: Date(),
            days: snapshot.days,
            highlights: snapshot.highlights,
            location: snapshot.location,
            payloadVersion: max(snapshot.payloadVersion, 3),
            sharedActionRecords: snapshot.sharedActionRecords,
            sharedCountdownItems: snapshot.sharedCountdownItems,
            sharedTodoListSummary: summary
        )
        snapshotRoot[Constants.fieldPayloadData] = try encode(snapshot: snapshot) as CKRecordValue
        snapshotRoot[Constants.fieldGeneratedAt] = snapshot.generatedAt as CKRecordValue
        snapshotRoot[Constants.fieldUpdatedAt] = snapshot.generatedAt as CKRecordValue

        if isOwner {
            guard let current else { throw CloudKitDomainError.notAuthenticated }
            _ = try await requireCurrentUserRecordName(current)
        }
        _ = try await modify(
            recordsToSave: [snapshotRoot],
            recordIDsToDelete: [],
            in: database,
            scope: scope,
            contextName: "syncTodoSummaryIntoSnapshot.modify"
        )
        if isOwner, let current {
            _ = try await requireCurrentUserRecordName(current)
        }
    }

    private func fetchHealthRootRecord(
        ownerUserRecordName: String?,
        database: CKDatabase,
        scope: CloudKitDatabaseScope
    ) async throws -> CKRecord? {
        if scope == .private {
            let zoneID = CKRecordZone.ID(zoneName: Constants.zoneName, ownerName: CKCurrentUserDefaultName)
            let rootID = CKRecord.ID(recordName: Constants.rootRecordName, zoneID: zoneID)
            return try await fetch(recordID: rootID, from: database, scope: scope)
        }

        let snapshots = try await fetchSharedSnapshots()
        return try await fetch(
            recordID: snapshots.snapshots.first { $0.ownerRecordName == ownerUserRecordName }?.recordID ?? CKRecord.ID(recordName: Constants.rootRecordName),
            from: database,
            scope: scope
        )
    }

    private func makeTodoItemRecord(_ record: CKRecord) -> CloudKitTodoItemRecord? {
        guard let itemID = record[Constants.fieldTodoItemID] as? String,
              let title = record[Constants.fieldTodoTitle] as? String,
              let createdAt = record[Constants.fieldTodoCreatedAt] as? Date,
              let updatedAt = record[Constants.fieldUpdatedAt] as? Date,
              let titleUpdatedAt = record[Constants.fieldTodoTitleUpdatedAt] as? Date,
              let completionUpdatedAt = record[Constants.fieldTodoCompletionUpdatedAt] as? Date,
              let noteUpdatedAt = record[Constants.fieldTodoNoteUpdatedAt] as? Date,
              let dueDateUpdatedAt = record[Constants.fieldTodoDueDateUpdatedAt] as? Date else {
            return nil
        }

        let item = SharedTodoItem(
            id: itemID,
            title: title,
            isCompleted: (record[Constants.fieldTodoIsCompleted] as? NSNumber)?.boolValue ?? false,
            note: record[Constants.fieldTodoNote] as? String,
            dueDate: record[Constants.fieldTodoDueDate] as? Date,
            createdByUserRecordName: record[Constants.fieldTodoCreatedBy] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt,
            fieldTimestamps: SharedTodoFieldTimestamps(
                titleUpdatedAt: titleUpdatedAt,
                completionUpdatedAt: completionUpdatedAt,
                noteUpdatedAt: noteUpdatedAt,
                dueDateUpdatedAt: dueDateUpdatedAt
            )
        )

        return CloudKitTodoItemRecord(recordID: record.recordID, item: item)
    }

    private func makeSharedTodoList(
        from root: CKRecord,
        items: [CloudKitTodoItemRecord],
        fallbackSummary: SharedTodoListSummary?
    ) throws -> SharedTodoList {
        SharedTodoList(
            id: root.recordID.recordName,
            title: (root[Constants.fieldTodoListTitle] as? String) ?? fallbackSummary?.title ?? "共享待办",
            ownerUserRecordName: root[Constants.fieldTodoOwnerRecordName] as? String ?? fallbackSummary?.ownerUserRecordName,
            items: items.map(\.item).sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted && rhs.isCompleted
                }
                return lhs.updatedAt > rhs.updatedAt
            },
            updatedAt: (root[Constants.fieldUpdatedAt] as? Date) ?? fallbackSummary?.updatedAt ?? Date(),
            lastEditedByUserRecordName: root[Constants.fieldOwnerDisplayName] as? String ?? fallbackSummary?.lastEditedByUserRecordName,
            // 当前健康 share 固定为只读；payload 中旧的 collaborator 标记不能
            // 提升 CloudKit 实际权限。
            permissionRole: .readOnly
        )
    }

    private func makeList(from summary: SharedTodoListSummary) -> SharedTodoList {
        SharedTodoList(
            id: summary.id,
            title: summary.title,
            ownerUserRecordName: summary.ownerUserRecordName,
            items: summary.previewItems,
            updatedAt: summary.updatedAt,
            lastEditedByUserRecordName: summary.lastEditedByUserRecordName,
            permissionRole: .readOnly
        )
    }

    nonisolated private static func profile(from record: CKRecord) throws -> PublicUserProfile {
        guard let ownerUserRecordName = validatedProfileOwner(from: record),
              let handle = record[Constants.fieldHandle] as? String,
              let displayName = record[Constants.fieldOwnerDisplayName] as? String else {
            throw CloudKitDomainError.invalidRecord
        }

        return PublicUserProfile(
            recordName: ownerUserRecordName,
            handle: handle,
            displayName: displayName,
            avatarSeed: record[Constants.fieldAvatarSeed] as? String,
            // 旧记录没有显式选择可搜索时必须按最严格隐私默认值处理。
            isSearchable: (record[Constants.fieldIsSearchable] as? NSNumber)?.boolValue ?? false,
            updatedAt: record[Constants.fieldUpdatedAt] as? Date
        )
    }

    nonisolated private static func validatedProfileOwner(from record: CKRecord) -> String? {
        CloudKitDataPolicy.PublicProfile.validatedOwnerUserRecordName(
            profileRecordName: record.recordID.recordName,
            declaredOwnerUserRecordName: record[Constants.fieldOwnerUserRecordName] as? String,
            creatorUserRecordName: record.creatorUserRecordID?.recordName
        )
    }

    nonisolated private static func mostRecentValidProfileRecord(
        _ records: [CKRecord],
        expectedOwnerUserRecordName: String
    ) -> CKRecord? {
        records
            .filter { validatedProfileOwner(from: $0) == expectedOwnerUserRecordName }
            .max { lhs, rhs in
                let lhsDate = lhs[Constants.fieldUpdatedAt] as? Date ?? .distantPast
                let rhsDate = rhs[Constants.fieldUpdatedAt] as? Date ?? .distantPast
                return lhsDate < rhsDate
            }
    }

    nonisolated private static func mostRecentProfile(
        _ profiles: [PublicUserProfile]
    ) -> PublicUserProfile? {
        profiles.max {
            ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast)
        }
    }

    private func resolveHandle(displayName: String, fallback: String) -> String {
        let base = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { return fallback.lowercased() }
        let slug = base
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return slug.isEmpty ? fallback.lowercased() : slug
    }

    private func encode(snapshot: SharedHealthSnapshot) throws -> Data {
        guard let data = try? encoder.encode(snapshot) else {
            throw CloudKitDomainError.missingPayload
        }
        return data
    }

    private func fetchUserRecordID() async throws -> CKRecord.ID {
        try await executor.run(
            context: CloudKitLoggerContext(operation: "fetchUserRecordID")
        ) {
            try await self.client.fetchUserRecordID(container: self.container)
        }
    }

    private func requireCurrentUserRecordName(_ expectedUserRecordName: String?) async throws -> String {
        let currentUserRecordName = try await fetchUserRecordID().recordName
        guard expectedUserRecordName == nil || currentUserRecordName == expectedUserRecordName else {
            throw CloudKitDomainError.iCloudUnavailable
        }
        return currentUserRecordName
    }

    private func ensureZone() async throws {
        let zone = CKRecordZone(zoneName: Constants.zoneName)
        do {
            _ = try await executor.run(
                context: CloudKitLoggerContext(
                    operation: "ensureZone",
                    database: .private,
                    zoneID: zone.zoneID.zoneName
                )
            ) {
                try await self.client.save(zone: zone, in: self.privateDB)
            }
        } catch let error as CloudKitDomainError {
            if error == .zoneNotFound || error == .conflict {
                return
            }
            throw error
        }
    }

    private func fetchOwnedShare() async throws -> CKShare? {
        let zoneID = CKRecordZone.ID(zoneName: Constants.zoneName, ownerName: CKCurrentUserDefaultName)
        let rootID = CKRecord.ID(recordName: Constants.rootRecordName, zoneID: zoneID)
        let rootRecord: CKRecord
        do {
            guard let fetched = try await fetch(recordID: rootID, from: privateDB, scope: .private) else {
                return nil
            }
            rootRecord = fetched
        } catch let error as CloudKitDomainError {
            guard error == .unknownItem || error == .zoneNotFound else { throw error }
            return nil
        }
        return try await resolveExistingShare(for: rootRecord)
    }

    private func resolveExistingShare(for rootRecord: CKRecord) async throws -> CKShare? {
        if let existingShare = rootRecord.share,
           let fetched = try await fetch(recordID: existingShare.recordID, from: privateDB, scope: .private) as? CKShare {
            return fetched
        }

        if let shareRecordName = rootRecord[Constants.fieldShareRecordName] as? String,
           let existing = try await fetch(
                recordID: CKRecord.ID(recordName: shareRecordName, zoneID: rootRecord.recordID.zoneID),
                from: privateDB,
                scope: .private
           ) as? CKShare {
            return existing
        }

        return nil
    }

    private func resolveShareForInvite(rootRecord: CKRecord) async throws -> CKShare {
        if let existing = try await resolveExistingShare(for: rootRecord) {
            return existing
        }
        return CKShare(rootRecord: rootRecord)
    }

    private func shouldRecoverExistingShare(from error: CloudKitDomainError) -> Bool {
        switch error {
        case .conflict, .serverRejectedRequest:
            return true
        default:
            return false
        }
    }

    private func fetch(
        recordID: CKRecord.ID,
        from database: CKDatabase,
        scope: CloudKitDatabaseScope
    ) async throws -> CKRecord? {
        try await executor.run(
            context: CloudKitLoggerContext(
                operation: "fetchRecord",
                database: scope,
                zoneID: recordID.zoneID.zoneName,
                recordID: recordID.recordName
            )
        ) {
            try await self.client.fetch(recordID: recordID, in: database)
        }
    }

    private func save(
        record: CKRecord,
        in database: CKDatabase,
        scope: CloudKitDatabaseScope
    ) async throws -> CKRecord {
        try await executor.run(
            context: CloudKitLoggerContext(
                operation: "saveRecord",
                database: scope,
                zoneID: record.recordID.zoneID.zoneName,
                recordID: record.recordID.recordName
            )
        ) {
            try await self.client.save(record: record, in: database)
        }
    }

    private func modify(
        recordsToSave: [CKRecord],
        recordIDsToDelete: [CKRecord.ID],
        in database: CKDatabase,
        scope: CloudKitDatabaseScope,
        contextName: String
    ) async throws -> [CKRecord] {
        try await executor.run(
            context: CloudKitLoggerContext(
                operation: contextName,
                database: scope,
                zoneID: recordsToSave.first?.recordID.zoneID.zoneName ?? recordIDsToDelete.first?.zoneID.zoneName,
                recordID: recordsToSave.first?.recordID.recordName ?? recordIDsToDelete.first?.recordName,
                shareID: recordsToSave.compactMap { $0 as? CKShare }.first?.recordID.recordName
            )
        ) {
            try await self.client.modify(
                recordsToSave: recordsToSave,
                recordIDsToDelete: recordIDsToDelete,
                savePolicy: .changedKeys,
                in: database
            )
        }
    }

    private func queryRecords(
        _ query: CKQuery,
        in database: CKDatabase,
        scope: CloudKitDatabaseScope,
        zoneID: CKRecordZone.ID? = nil
    ) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var nextQuery: CKQuery? = query
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let currentQuery = nextQuery
            let currentCursor = cursor
            let result: (records: [CKRecord], cursor: CKQueryOperation.Cursor?)
            do {
                result = try await executor.run(
                    context: CloudKitLoggerContext(
                        operation: "queryRecords",
                        database: scope,
                        zoneID: zoneID?.zoneName
                    )
                ) {
                    try await self.client.runQuery(
                        query: currentQuery,
                        cursor: currentCursor,
                        zoneID: zoneID,
                        in: database
                    )
                }
            } catch CloudKitDomainError.unknownItem {
                // CKQuery 场景下 `.unknownItem` 表示 record type 尚未在 schema 中创建
                // （Development 环境 schema 由首次 save 即时生成，查询不会创建；
                // Production 则说明 schema 未部署）。语义上等价于"没有任何记录"，
                // 按空结果返回——否则 publishOrUpdateMyProfile 会因查询失败提前返回，
                // 首条记录永远无法保存，record type 也就永远不会被创建。
                return records
            }
            records.append(contentsOf: result.records)
            cursor = result.cursor
            nextQuery = nil
        } while cursor != nil

        return records
    }

    private func queryAllRecords(
        ofType recordType: String,
        in database: CKDatabase,
        scope: CloudKitDatabaseScope,
        zoneID: CKRecordZone.ID? = nil
    ) async throws -> [CKRecord] {
        var allRecords: [CKRecord] = []
        var nextCursor: CKQueryOperation.Cursor?
        var nextQuery: CKQuery? = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))

        repeat {
            let query = nextQuery
            let cursor = nextCursor
            let batch = try await executor.run(
                context: CloudKitLoggerContext(
                    operation: "queryAllRecords",
                    database: scope,
                    zoneID: zoneID?.zoneName
                )
            ) {
                try await self.client.runQuery(query: query, cursor: cursor, zoneID: zoneID, in: database)
            }
            allRecords.append(contentsOf: batch.records)
            nextCursor = batch.cursor
            nextQuery = nil
        } while nextCursor != nil

        return allRecords
    }

    private func fetchAllRecordZoneIDs(
        in database: CKDatabase,
        scope: CloudKitDatabaseScope
    ) async throws -> [CKRecordZone.ID] {
        try await executor.run(
            context: CloudKitLoggerContext(
                operation: "fetchAllRecordZoneIDs",
                database: scope
            )
        ) {
            try await self.client.fetchAllZoneIDs(in: database)
        }
    }
}

final class CloudKitSharingService {
    static let shared = CloudKitSharingService()
    nonisolated static let healthShareRootRecordName = "CurrentHealthShareRoot"

    let container: CKContainer
    private let repository: CloudKitSharingRepositoryProtocol
    private let executor: CloudKitOperationExecutor

    init(
        container: CKContainer = CloudKitDataPolicy.makeContainer(),
        repository: CloudKitSharingRepositoryProtocol? = nil,
        executor: CloudKitOperationExecutor = CloudKitOperationExecutor()
    ) {
        self.container = container
        self.executor = executor
        self.repository = repository ?? CloudKitSharingRepository(container: container, executor: executor)
    }

    func isICloudAvailable() async -> Bool {
        await repository.isICloudAvailable()
    }

    func currentUserRecordName() async -> String? {
        await repository.currentUserRecordName()
    }

    func hasOwnedShare() async throws -> Bool {
        try await repository.hasOwnedShare()
    }

    func discardOwnedShareIfNoParticipants() async throws {
        try await repository.discardOwnedShareIfNoParticipants()
    }

    func upsertUserProfile(
        displayName: String,
        handle: String? = nil,
        avatarSeed: String? = nil,
        isSearchable: Bool = false,
        expectedUserRecordName: String? = nil
    ) async {
        await repository.upsertUserProfile(
            displayName: displayName,
            handle: handle,
            avatarSeed: avatarSeed,
            isSearchable: isSearchable,
            expectedUserRecordName: expectedUserRecordName
        )
    }

    func lookupProfile(handle: String) async throws -> PublicUserProfile {
        try await repository.lookupProfile(handle: handle)
    }

    func fetchProfiles(recordNames: [String]) async throws -> [PublicUserProfile] {
        try await repository.fetchProfiles(recordNames: recordNames)
    }

    func saveMySharedSnapshot(
        _ snapshot: SharedHealthSnapshot,
        expectedUserRecordName: String? = nil
    ) async throws -> CloudKitOwnedShareContext {
        try await repository.saveMySharedSnapshot(
            snapshot,
            expectedUserRecordName: expectedUserRecordName
        )
    }

    func prepareInvitePayload(
        for snapshot: SharedHealthSnapshot,
        expectedUserRecordName: String? = nil
    ) async throws -> CloudKitShareInvitePayload {
        try await repository.prepareInvitePayload(
            for: snapshot,
            expectedUserRecordName: expectedUserRecordName
        )
    }

    func fetchOwnedParticipants() async throws -> [CloudKitOwnedParticipant] {
        try await repository.fetchOwnedParticipants()
    }

    func fetchSharedSnapshots() async throws -> CloudKitFriendSnapshotsResult {
        try await repository.fetchSharedSnapshots()
    }

    func fetchSharingGraph() async throws -> CloudKitSharingGraphResult {
        try await repository.fetchSharingGraph()
    }

    func fetchSharedSnapshot(recordID: CKRecord.ID) async throws -> SharedRemoteHealthSnapshot? {
        try await repository.fetchSharedSnapshot(recordID: recordID)
    }

    func fetchCollaborativeTodoList(ownerUserRecordName: String?) async throws -> CollaborativeTodoSyncResult {
        try await repository.fetchCollaborativeTodoList(ownerUserRecordName: ownerUserRecordName)
    }

    func syncCollaborativeTodoList(_ list: SharedTodoList, ownerUserRecordName: String?) async throws -> SharedTodoList {
        try await repository.syncCollaborativeTodoList(list, ownerUserRecordName: ownerUserRecordName)
    }

    func removeCollaborativeTodoList(ownerUserRecordName: String?) async throws {
        try await repository.removeCollaborativeTodoList(ownerUserRecordName: ownerUserRecordName)
    }

    func deleteCollaborativeTodoItem(itemID: String, ownerUserRecordName: String?, currentUserRecordName: String?) async throws -> SharedTodoList? {
        try await repository.deleteCollaborativeTodoItem(
            itemID: itemID,
            ownerUserRecordName: ownerUserRecordName,
            currentUserRecordName: currentUserRecordName
        )
    }

    func accept(metadata: CKShare.Metadata) async throws {
        try await repository.accept(metadata: metadata)
    }

    func removeParticipant(ownerUserRecordName: String?) async throws {
        try await repository.removeParticipant(ownerUserRecordName: ownerUserRecordName)
    }

    func leaveSharedSnapshot(recordName: String, ownerUserRecordName: String?) async throws {
        try await repository.leaveSharedSnapshot(
            recordName: recordName,
            ownerUserRecordName: ownerUserRecordName
        )
    }

    func stopSharing() async throws {
        try await repository.stopSharing()
    }

    func map(_ error: Error) -> CloudKitDomainError {
        executor.map(error)
    }
}
