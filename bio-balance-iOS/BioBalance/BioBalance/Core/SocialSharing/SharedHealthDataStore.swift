import CloudKit
import Foundation
import os

@MainActor
@Observable
final class SharedHealthDataStore {
    static let shared = SharedHealthDataStore()
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "SocialSharing")

    private(set) var state: SocialSharingState = .empty

    private enum CacheKeys {
        static let legacyRemoteFriends = "social.sharing.remote.friends.v1"
        static let remoteFriends = "social.sharing.remote.friends.v2"
        static let cloudAccount = CloudKitDataPolicy.AccountBindingKey.socialSharing
    }

    private struct FriendCacheEnvelope: Codable {
        let accountIdentifier: String
        let savedAt: Date
        let profiles: [FriendHealthProfile]
    }

    /// 好友摘要属于健康敏感缓存，只允许短期离线展示且必须绑定 CloudKit 账号。
    private static let friendCacheLifetime: TimeInterval = 24 * 60 * 60

    private let healthService: HealthKitSharingService
    private let cloudKitService: CloudKitSharingService
    private let followService: FollowService
    private let todoStore: SharedTodoStore
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var hasBootstrapped = false
    private var refreshTask: Task<Void, Never>?
    private var activeRefreshID: UUID?
    private var accountChangeObserver: NSObjectProtocol?

    struct RefreshFriendsResult: Sendable {
        let profiles: [FriendHealthProfile]
        let outgoingShares: [OutgoingShareProfile]
        let myPublicProfile: PublicUserProfile?
        let relationshipOverview: SocialRelationshipOverview
        let staleState: SocialSharingCacheState
        let errorMessage: String?
        let postAcceptNavigationTarget: FriendHealthProfile?
    }

    init(
        healthService: HealthKitSharingService? = nil,
        cloudKitService: CloudKitSharingService? = nil,
        followService: FollowService? = nil,
        todoStore: SharedTodoStore? = nil,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.healthService = healthService ?? .shared
        self.cloudKitService = cloudKitService ?? .shared
        self.followService = followService ?? .shared
        self.todoStore = todoStore ?? .shared
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        // 注册必须在 init 返回前完成，否则启动后立即到来的账号切换通知可能被漏掉。
        accountChangeObserver = notificationCenter.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let store = self else { return }
            Task { @MainActor in
                store.handleCloudKitAccountChange()
            }
        }
    }

    func bootstrap() async {
        print("[社交共享] 数据存储开始启动 hasBootstrapped=\(hasBootstrapped)")
        guard defaults.bool(forKey: CloudKitDataPolicy.PreferenceKey.socialSharingEnabled) else { return }
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await refresh()
    }

    func lookupPublicProfile(handle: String) async throws -> PublicUserProfile {
        let normalized = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        guard !normalized.isEmpty else { throw CloudKitDomainError.profileNotFound }
        return try await cloudKitService.lookupProfile(handle: normalized)
    }

    func refresh() async {
        print("[社交共享] 请求刷新好友共享状态")
        guard defaults.bool(forKey: CloudKitDataPolicy.PreferenceKey.socialSharingEnabled) else {
            refreshTask?.cancel()
            return
        }
        refreshTask?.cancel()
        let refreshID = UUID()
        activeRefreshID = refreshID
        let task = Task { @MainActor in
            defer {
                if activeRefreshID == refreshID {
                    activeRefreshID = nil
                    refreshTask = nil
                }
            }
            state.phase = .loading
            state.errorMessage = nil

            let hasAvailableAccountStatus = await cloudKitService.isICloudAvailable()
            guard isCurrentRefresh(refreshID) else { return }
            let currentAccountIdentifier = hasAvailableAccountStatus
                ? await cloudKitService.currentUserRecordName()
                : nil
            guard isCurrentRefresh(refreshID) else { return }
            let isICloudAvailable = hasAvailableAccountStatus && currentAccountIdentifier != nil

            if let currentAccountIdentifier {
                bindFriendCache(to: currentAccountIdentifier)
            } else {
                invalidateFriendCacheForUnverifiedAccount()
            }

            let buildResult = await healthService.buildMyShareSnapshot()
            guard isCurrentRefresh(refreshID) else { return }
            print("[社交共享] 刷新状态 iCloud=\(isICloudAvailable) source=\(buildResult.source) permission=\(buildResult.permissionState) sleep=\(buildResult.sleepAccess) walking=\(buildResult.walkingAccess) location=\(buildResult.locationAccess) hasSnapshot=\(buildResult.snapshot != nil)")

            var participantCount = 0
            var outgoingAcceptedRecordNames = Set<String>()
            var outgoingPendingRecordNames = Set<String>()
            var myShareError: String?
            var friendFetchError: String?
            var hasOwnedShare = false

            if isICloudAvailable, let currentAccountIdentifier {
                do {
                    hasOwnedShare = try await cloudKitService.hasOwnedShare()
                } catch {
                    myShareError = localizedSharingError(error)
                }
                guard await validateCloudAccount(
                    currentAccountIdentifier,
                    refreshID: refreshID
                ) else { return }

                if let sharingGraph = try? await cloudKitService.fetchSharingGraph() {
                    outgoingAcceptedRecordNames = sharingGraph.outgoingAcceptedRecordNames
                    outgoingPendingRecordNames = sharingGraph.outgoingPendingRecordNames
                    participantCount = outgoingAcceptedRecordNames.count
                    print("[社交共享] 已发送共享统计 accepted=\(outgoingAcceptedRecordNames.count) pending=\(outgoingPendingRecordNames.count)")
                }
                guard await validateCloudAccount(
                    currentAccountIdentifier,
                    refreshID: refreshID
                ) else { return }
            }

            // 只有用户已经创建过 CKShare 后才持续更新自己的摘要。仅打开好友页
            // 不得在 private database 中自动创建 HealthShareRoot。
            if isICloudAvailable,
               hasOwnedShare,
               let currentAccountIdentifier,
               let snapshot = buildResult.snapshot {
                await cloudKitService.upsertUserProfile(
                    displayName: snapshot.ownerDisplayName,
                    isSearchable: defaults.bool(forKey: SocialSharingPreferenceKeys.profileSearchable),
                    expectedUserRecordName: currentAccountIdentifier
                )
                guard await validateCloudAccount(
                    currentAccountIdentifier,
                    refreshID: refreshID
                ) else { return }
                // 位置共享关闭后，即使本次健康读取失败，也必须立即上传一份移除
                // 位置字段的快照，避免旧粗略坐标继续留在已共享的 CloudKit 载荷中。
                // saveMySharedSnapshot 内部会做 payload 变更检测，未变化时不产生写入。
                let locationSharingEnabled = defaults.bool(
                    forKey: SocialSharingDataPolicy.approximateLocationSharingEnabledKey
                )
                let shouldUploadSnapshot = buildResult.source == .fresh
                    || (!locationSharingEnabled && snapshot.location == nil)
                if shouldUploadSnapshot {
                    do {
                        let context = try await cloudKitService.saveMySharedSnapshot(
                            snapshot,
                            expectedUserRecordName: currentAccountIdentifier
                        )
                        guard await validateCloudAccount(
                            currentAccountIdentifier,
                            refreshID: refreshID
                        ) else { return }
                        if buildResult.source == .fresh {
                            try await syncOwnedTodoRecords(
                                expectedUserRecordName: currentAccountIdentifier
                            )
                        }
                        participantCount = context.acceptedParticipantCount
                        print("[社交共享] 已保存我的共享摘要 participantCount=\(participantCount) root=\(context.rootRecordName)")
                    } catch {
                        myShareError = localizedSharingError(error)
                        print("[社交共享] 保存我的共享摘要失败 mappedError=\(myShareError ?? "nil")")
                    }
                }
                guard await validateCloudAccount(
                    currentAccountIdentifier,
                    refreshID: refreshID
                ) else { return }
            }

            let refreshFriendsResult: RefreshFriendsResult
            var emptyReason: SocialSharingEmptyStateReason = .none

            // 接收好友分享不依赖当前用户是否授权自己的 HealthKit。
            if isICloudAvailable, let currentAccountIdentifier {
                refreshFriendsResult = await makeRefreshFriendsResult(
                    outgoingAcceptedRecordNames: outgoingAcceptedRecordNames,
                    outgoingPendingRecordNames: outgoingPendingRecordNames,
                    postAcceptNavigationTarget: state.postAcceptNavigationTarget,
                    verifiedAccountIdentifier: currentAccountIdentifier,
                    refreshID: refreshID
                )
                guard await validateCloudAccount(
                    currentAccountIdentifier,
                    refreshID: refreshID
                ) else { return }
                friendFetchError = refreshFriendsResult.errorMessage
            } else {
                refreshFriendsResult = RefreshFriendsResult(
                    profiles: [],
                    outgoingShares: [],
                    myPublicProfile: nil,
                    relationshipOverview: .empty,
                    staleState: .none,
                    errorMessage: nil,
                    postAcceptNavigationTarget: nil
                )
            }

            if !isICloudAvailable {
                emptyReason = .iCloudUnavailable
            } else if refreshFriendsResult.profiles.isEmpty,
                      refreshFriendsResult.outgoingShares.isEmpty,
                      buildResult.permissionState == .needsPermission {
                emptyReason = .needsPermission
            } else if refreshFriendsResult.profiles.isEmpty && refreshFriendsResult.outgoingShares.isEmpty {
                emptyReason = .noFriends
            }

            let snapshot = buildResult.snapshot
            if let currentAccountIdentifier {
                guard await validateCloudAccount(
                    currentAccountIdentifier,
                    refreshID: refreshID
                ) else { return }
            } else {
                guard isCurrentRefresh(refreshID) else { return }
            }
            state = SocialSharingState(
                phase: .loaded,
                isICloudAvailable: isICloudAvailable,
                inviteFlowState: state.inviteFlowState,
                inviteResultMessage: state.inviteResultMessage,
                pendingInvite: state.pendingInvite,
                emptyStateReason: emptyReason,
                staleFriendCacheState: refreshFriendsResult.staleState,
                postAcceptNavigationTarget: refreshFriendsResult.postAcceptNavigationTarget,
                myPublicProfile: refreshFriendsResult.myPublicProfile,
                relationshipOverview: refreshFriendsResult.relationshipOverview,
                outgoingShares: refreshFriendsResult.outgoingShares,
                myStatus: MySharedHealthStatus(
                    displayName: snapshot?.ownerDisplayName ?? HealthKitSharingService.resolveDisplayName(override: nil),
                    permissionState: buildResult.permissionState,
                    sleepAccess: buildResult.sleepAccess,
                    walkingAccess: buildResult.walkingAccess,
                    locationAccess: buildResult.locationAccess,
                    syncState: buildResult.syncState,
                    sharedFriendCount: participantCount,
                    summaryText: Self.makeSummaryText(snapshot: snapshot, permissionState: buildResult.permissionState),
                    detailText: buildResult.detailText,
                    lastUpdatedText: Self.makeLastUpdatedText(snapshot: snapshot, syncState: buildResult.syncState),
                    isSharingEnabled: buildResult.permissionState == .ready || buildResult.permissionState == .partialPermission,
                    isUsingCachedSnapshot: buildResult.source == .cacheFallback,
                    snapshot: snapshot
                ),
                friends: refreshFriendsResult.profiles,
                errorMessage: Self.resolveRefreshErrorMessage(
                    permissionState: buildResult.permissionState,
                    myShareError: myShareError,
                    friendFetchError: friendFetchError
                ) ?? Self.makeGlobalErrorMessage(
                    iCloudAvailable: isICloudAvailable,
                    friendProfiles: refreshFriendsResult.profiles,
                    staleState: refreshFriendsResult.staleState
                )
            )
            print("[社交共享] 刷新完成 friends=\(refreshFriendsResult.profiles.count) participantCount=\(participantCount) emptyReason=\(emptyReason) stale=\(refreshFriendsResult.staleState) error=\(state.errorMessage ?? "nil")")
        }

        refreshTask = task
        await task.value
    }

    func requestAuthorization() async {
        print("[社交共享] 请求健康数据授权")
        do {
            try await healthService.requestAuthorization()
            print("[社交共享] 健康数据授权成功")
        } catch {
            state.errorMessage = localizedSharingError(error)
            print("[社交共享] 健康数据授权失败 mappedError=\(localizedSharingError(error))")
        }
        await refresh()
    }

    /// 位置共享开关变化时调用：关闭时先清理本地缓存中的旧粗略位置，再刷新，
    /// 确保关闭动作立刻生效（包括已存在 CKShare 时的云端载荷移除）。
    func updateApproximateLocationSharing(_ enabled: Bool) async {
        if !enabled {
            healthService.clearCachedLocationIfSharingDisabled()
        }
        await refresh()
    }

    func beginInviteFlow() {
        print("[社交共享] 开始邀请流程")
        state.inviteFlowState = .confirming
        state.inviteResultMessage = nil
        state.errorMessage = nil
    }

    func cancelInviteFlow() {
        print("[社交共享] 取消邀请流程")
        state.inviteFlowState = .idle
    }

    func prepareInvitePayload() async throws -> CloudKitShareInvitePayload {
        state.inviteFlowState = .preparing
        state.inviteResultMessage = "正在准备 iCloud 共享邀请..."
        let buildResult = await healthService.buildMyShareSnapshot()
        Self.logger.info("[社交共享] 准备邀请 payload source=\(String(describing: buildResult.source), privacy: .public) permission=\(String(describing: buildResult.permissionState), privacy: .public) hasSnapshot=\(buildResult.snapshot != nil, privacy: .public)")
        print("[社交共享] 准备邀请 payload source=\(buildResult.source) permission=\(buildResult.permissionState) hasSnapshot=\(buildResult.snapshot != nil)")
        guard let snapshot = buildResult.snapshot else {
            state.inviteFlowState = .failed
            state.inviteResultMessage = nil
            state.pendingInvite = nil
            throw CloudKitDomainError.missingPayload
        }

        guard let ownerRecordName = await cloudKitService.currentUserRecordName() else {
            state.inviteFlowState = .failed
            state.inviteResultMessage = nil
            state.pendingInvite = nil
            throw CloudKitDomainError.notAuthenticated
        }
        state.pendingInvite = followService.makePendingInvite(
            from: snapshot,
            ownerRecordName: ownerRecordName,
            createdAt: Date()
        )

        do {
            let payload = try await cloudKitService.prepareInvitePayload(
                for: snapshot,
                expectedUserRecordName: ownerRecordName
            )
            try await syncOwnedTodoRecords(expectedUserRecordName: ownerRecordName)
            guard await validateCloudAccount(ownerRecordName) else {
                throw CloudKitDomainError.iCloudUnavailable
            }
            state.inviteFlowState = .ready
            state.inviteResultMessage = "邀请已准备好，请在系统分享面板中选择好友。"
            Self.logger.info("[社交共享] 邀请已就绪 share=\(payload.share.recordID.recordName, privacy: .public)")
            print("[社交共享] 邀请已就绪 share=\(payload.share.recordID.recordName)")
            return payload
        } catch {
            state.inviteFlowState = .failed
            state.inviteResultMessage = nil
            state.pendingInvite = nil
            Self.logger.error("[社交共享] 准备邀请失败 mappedError=\(self.localizedSharingError(error), privacy: .public)")
            print("[社交共享] 准备邀请失败 mappedError=\(localizedSharingError(error))")
            throw error
        }
    }

    func markInviteSheetPresented() {
        print("[社交共享] 系统分享面板已展示")
        state.inviteFlowState = .presenting
        state.inviteResultMessage = "系统分享面板已打开，邀请会以只读权限发送。"
    }

    func markInviteReadyToSend() {
        print("[社交共享] 邀请链接已准备")
        state.inviteFlowState = .ready
        state.inviteResultMessage = "邀请已准备好，请选择发送给好友的方式。"
    }

    func markInviteSent() {
        print("[社交共享] 邀请已发送")
        state.inviteFlowState = .sent
        state.inviteResultMessage = "邀请已发送，等待对方接受后会出现在好友列表。"
        // 系统面板关闭后以 CKShare participant 为准；本地占位没有受邀者身份，
        // 继续保留会与 outgoingShares 重复并错误显示成自己的名字。
        state.pendingInvite = nil
    }

    func markInviteDeliveryCancelled() {
        state.inviteFlowState = .idle
        state.inviteResultMessage = nil
        state.pendingInvite = nil
        Task {
            do {
                try await cloudKitService.discardOwnedShareIfNoParticipants()
            } catch {
                state.errorMessage = localizedSharingError(error)
            }
            await refresh()
        }
    }

    func markInviteFailed(_ error: Error) {
        print("[社交共享] 邀请发送失败 mappedError=\(localizedSharingError(error))")
        state.inviteFlowState = .failed
        state.inviteResultMessage = nil
        state.pendingInvite = nil
        state.errorMessage = localizedSharingError(error)
        Self.logger.error("[社交共享] 邀请面板失败 mappedError=\(self.localizedSharingError(error), privacy: .public)")
        print("[社交共享] 邀请面板失败 mappedError=\(localizedSharingError(error))")
    }

    func markInviteStopped() {
        print("[社交共享] 邀请流程已停止")
        state.inviteFlowState = .idle
        state.inviteResultMessage = nil
        state.pendingInvite = nil
    }

    func markInviteSheetDismissed() async {
        print("[社交共享] 系统分享面板关闭后刷新状态")
        if state.inviteFlowState != .sent {
            state.inviteFlowState = .idle
            state.inviteResultMessage = nil
        }
        await refresh()
    }

    func acceptShare(metadata: CKShare.Metadata) async {
        do {
            print("[社交共享] 开始接收好友分享 share=\(metadata.share.recordID.recordName)")
            try await cloudKitService.accept(metadata: metadata)
            if let recordID = metadata.hierarchicalRootRecordID,
               let fetched = try? await cloudKitService.fetchSharedSnapshot(recordID: recordID) {
                let incomingOwnerRecordNames = Set([fetched.ownerRecordName].compactMap { $0 })
                let profileMap = await fetchProfileMap(recordNames: [fetched.ownerRecordName].compactMap { $0 })
                let profile = followService.makeFriendProfiles(
                    from: [fetched],
                    profilesByRecordName: profileMap
                ).map { friend in
                    FriendHealthProfile(
                        id: friend.id,
                        ownerUserRecordName: friend.ownerUserRecordName,
                        name: friend.name,
                        relationshipState: followService.makeRelationshipState(
                            incomingOwnerRecordNames: incomingOwnerRecordNames,
                            outgoingAcceptedRecordNames: [],
                            outgoingPendingRecordNames: [],
                            ownerUserRecordName: friend.ownerUserRecordName
                        ),
                        permissionRole: friend.permissionRole,
                        statusText: friend.statusText,
                        sleepText: friend.sleepText,
                        walkingText: friend.walkingText,
                        lastUpdated: friend.lastUpdated,
                        isStale: false,
                        publicProfile: friend.publicProfile,
                        availableContentSummary: friend.availableContentSummary,
                        snapshot: friend.snapshot
                    )
                }.first
                state.postAcceptNavigationTarget = profile
            }
            print("[社交共享] 接收好友分享成功 share=\(metadata.share.recordID.recordName)")
        } catch {
            print("[社交共享] 接收好友分享失败 mappedError=\(localizedSharingError(error))")
            state.errorMessage = localizedSharingError(error)
        }
        await refresh()
    }

    func consumePostAcceptNavigationTarget() -> FriendHealthProfile? {
        let target = state.postAcceptNavigationTarget
        state.postAcceptNavigationTarget = nil
        return target
    }

    func removeFriend(_ friend: FriendHealthProfile) async {
        do {
            switch friend.relationshipState {
            case .incomingShared:
                try await cloudKitService.leaveSharedSnapshot(
                    recordName: CloudKitSharingService.healthShareRootRecordName,
                    ownerUserRecordName: friend.ownerUserRecordName
                )
            case .mutualShared:
                // “移除好友”表示同时停止双方共享。先撤销自己发出的权限，再退出
                // 对方的 share；任一步失败都会保留明确错误并重新刷新真实状态。
                try await cloudKitService.removeParticipant(ownerUserRecordName: friend.ownerUserRecordName)
                try await cloudKitService.leaveSharedSnapshot(
                    recordName: CloudKitSharingService.healthShareRootRecordName,
                    ownerUserRecordName: friend.ownerUserRecordName
                )
            case .outgoingShared, .pendingOutgoingInvite:
                try await cloudKitService.removeParticipant(ownerUserRecordName: friend.ownerUserRecordName)
            }
            removeCachedFriend(friend)
            state.friends.removeAll { $0.id == friend.id }
        } catch {
            state.errorMessage = localizedSharingError(error)
        }
        await refresh()
    }

    func removeOutgoingShare(_ profile: OutgoingShareProfile) async {
        do {
            try await cloudKitService.removeParticipant(ownerUserRecordName: profile.ownerUserRecordName)
            state.outgoingShares.removeAll { $0.id == profile.id }
        } catch {
            state.errorMessage = localizedSharingError(error)
        }
        await refresh()
    }

    func stopSharing() async {
        do {
            Self.logger.info("[社交共享] 请求停止共享")
            print("[社交共享] 请求停止共享")
            try await cloudKitService.stopSharing()
            healthService.clearCachedSnapshot()
            Self.logger.info("[社交共享] 停止共享成功")
            print("[社交共享] 停止共享成功")
        } catch {
            state.errorMessage = localizedSharingError(error)
            Self.logger.error("[社交共享] 停止共享失败 mappedError=\(self.localizedSharingError(error), privacy: .public)")
            print("[社交共享] 停止共享失败 mappedError=\(localizedSharingError(error))")
        }
        await refresh()
    }

    func loadLocalSharedTodoList() -> LocalSharedTodoList {
        todoStore.loadList()
    }

    func updateSharedTodoListTitle(_ title: String) {
        todoStore.updateListTitle(title)
        Task {
            await syncOwnerSnapshotAfterLocalTodoChange()
            await refresh()
        }
    }

    func setSharedTodoListEnabled(_ isShared: Bool) {
        todoStore.setShared(isShared)
        Task {
            await syncOwnerSnapshotAfterLocalTodoChange()
            await refresh()
        }
    }

    func upsertSharedTodoItem(
        id: String? = nil,
        title: String,
        isCompleted: Bool,
        note: String?,
        dueDate: Date?
    ) async {
        let currentUserRecordName = await cloudKitService.currentUserRecordName()
        todoStore.upsertItem(
            id: id,
            title: title,
            isCompleted: isCompleted,
            note: note,
            dueDate: dueDate,
            currentUserRecordName: currentUserRecordName
        )

        await syncOwnerSnapshotAfterLocalTodoChange()
        await refresh()
    }

    func deleteSharedTodoItem(id: String) async {
        let currentUserRecordName = await cloudKitService.currentUserRecordName()
        let deleted = todoStore.deleteItem(id: id, currentUserRecordName: currentUserRecordName)
        if !deleted {
            state.errorMessage = "只有创建这条待办的人才能删除它。"
            return
        }

        await syncOwnerSnapshotAfterLocalTodoChange()
        await refresh()
    }

    func fetchCollaborativeTodoList(ownerUserRecordName: String?) async -> SharedTodoList? {
        let currentUserRecordName = await cloudKitService.currentUserRecordName()
        if ownerUserRecordName == nil || ownerUserRecordName == currentUserRecordName {
            return makeCurrentSharedTodoSummary(currentUserRecordName: currentUserRecordName)
        }

        do {
            let result = try await cloudKitService.fetchCollaborativeTodoList(ownerUserRecordName: ownerUserRecordName)
            if let error = result.error {
                state.errorMessage = error.localizedDescription
            }
            return result.list
        } catch {
            state.errorMessage = localizedSharingError(error)
            return nil
        }
    }

    func upsertCollaborativeTodoItem(
        ownerUserRecordName: String?,
        listTitle: String,
        id: String? = nil,
        title: String,
        isCompleted: Bool,
        note: String?,
        dueDate: Date?
    ) async {
        let currentUserRecordName = await cloudKitService.currentUserRecordName()
        if ownerUserRecordName == nil || ownerUserRecordName == currentUserRecordName {
            await upsertSharedTodoItem(
                id: id,
                title: title,
                isCompleted: isCompleted,
                note: note,
                dueDate: dueDate
            )
            return
        }

        guard var list = await fetchCollaborativeTodoList(ownerUserRecordName: ownerUserRecordName) else {
            state.errorMessage = "暂时无法读取这份共享待办。"
            return
        }
        guard list.permissionRole == .collaborator else {
            state.errorMessage = "当前好友共享是只读的，不能修改对方的待办。"
            return
        }

        let now = Date()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        list = SharedTodoList(
            id: list.id,
            title: listTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? list.title : listTitle,
            ownerUserRecordName: list.ownerUserRecordName,
            items: mergeTodoItems(
                existingItems: list.items,
                id: id,
                title: trimmedTitle,
                isCompleted: isCompleted,
                note: note,
                dueDate: dueDate,
                currentUserRecordName: currentUserRecordName,
                now: now
            ),
            updatedAt: now,
            lastEditedByUserRecordName: currentUserRecordName,
            permissionRole: .collaborator
        )

        do {
            _ = try await cloudKitService.syncCollaborativeTodoList(list, ownerUserRecordName: ownerUserRecordName)
        } catch {
            state.errorMessage = localizedSharingError(error)
        }
        await refresh()
    }

    func deleteCollaborativeTodoItem(id: String, ownerUserRecordName: String?) async {
        let currentUserRecordName = await cloudKitService.currentUserRecordName()
        if ownerUserRecordName == nil || ownerUserRecordName == currentUserRecordName {
            await deleteSharedTodoItem(id: id)
            return
        }

        guard let list = await fetchCollaborativeTodoList(ownerUserRecordName: ownerUserRecordName),
              list.permissionRole == .collaborator else {
            state.errorMessage = "当前好友共享是只读的，不能删除对方的待办。"
            return
        }

        do {
            _ = try await cloudKitService.deleteCollaborativeTodoItem(
                itemID: id,
                ownerUserRecordName: ownerUserRecordName,
                currentUserRecordName: currentUserRecordName
            )
        } catch {
            state.errorMessage = localizedSharingError(error)
        }
        await refresh()
    }

    private func localizedSharingError(_ error: Error) -> String {
        cloudKitService.map(error).localizedDescription
    }

    func currentErrorMessage(for error: Error) -> String {
        localizedSharingError(error)
    }

    private func persistRemoteFriendProfiles(
        _ profiles: [FriendHealthProfile],
        accountIdentifier: String? = nil
    ) {
        guard let accountIdentifier = accountIdentifier ?? defaults.string(forKey: CacheKeys.cloudAccount) else {
            return
        }
        let envelope = FriendCacheEnvelope(
            accountIdentifier: accountIdentifier,
            savedAt: Date(),
            profiles: profiles
        )
        guard let data = try? encoder.encode(envelope) else { return }
        defaults.set(data, forKey: CacheKeys.remoteFriends)
    }

    private func cachedRemoteFriendProfiles() -> [FriendHealthProfile] {
        // v1 没有账号绑定，不能安全判断缓存属于哪个 Apple ID。
        defaults.removeObject(forKey: CacheKeys.legacyRemoteFriends)
        guard let data = defaults.data(forKey: CacheKeys.remoteFriends),
              let envelope = try? decoder.decode(FriendCacheEnvelope.self, from: data),
              envelope.accountIdentifier == defaults.string(forKey: CacheKeys.cloudAccount),
              Date().timeIntervalSince(envelope.savedAt) <= Self.friendCacheLifetime else {
            defaults.removeObject(forKey: CacheKeys.remoteFriends)
            return []
        }
        return envelope.profiles
    }

    private func removeCachedFriend(_ friend: FriendHealthProfile) {
        var friends = cachedRemoteFriendProfiles()
        friends.removeAll { $0.id == friend.id }
        persistRemoteFriendProfiles(friends)
    }

    private func isCurrentRefresh(_ refreshID: UUID) -> Bool {
        activeRefreshID == refreshID && !Task.isCancelled
    }

    private func validateCloudAccount(
        _ expectedAccountIdentifier: String,
        refreshID: UUID? = nil
    ) async -> Bool {
        if let refreshID, !isCurrentRefresh(refreshID) {
            return false
        }

        let confirmedAccountIdentifier = await cloudKitService.currentUserRecordName()
        if let refreshID, !isCurrentRefresh(refreshID) {
            return false
        }
        guard confirmedAccountIdentifier == expectedAccountIdentifier else {
            handleCloudKitAccountChange()
            return false
        }
        return true
    }

    private func handleCloudKitAccountChange() {
        activeRefreshID = nil
        refreshTask?.cancel()
        refreshTask = nil
        hasBootstrapped = false
        invalidateFriendCacheForUnverifiedAccount()
    }

    /// 好友健康缓存只有在当前 CloudKit user record 可验证时才允许保留。
    /// 退出 iCloud、账号切换通知或身份读取失败都必须立即清除磁盘与内存中的账号数据。
    func invalidateFriendCacheForUnverifiedAccount() {
        defaults.removeObject(forKey: CacheKeys.remoteFriends)
        defaults.removeObject(forKey: CacheKeys.legacyRemoteFriends)
        defaults.removeObject(forKey: CacheKeys.cloudAccount)
        clearAccountScopedFriendState()
        state.phase = .loaded
        state.isICloudAvailable = false
        state.emptyStateReason = .iCloudUnavailable
        state.errorMessage = "当前 iCloud 账号已变化或暂时无法确认，请重新刷新。"
    }

    func bindFriendCache(to accountIdentifier: String) {
        let normalizedIdentifier = accountIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else {
            invalidateFriendCacheForUnverifiedAccount()
            return
        }

        if defaults.string(forKey: CacheKeys.cloudAccount) != normalizedIdentifier {
            defaults.removeObject(forKey: CacheKeys.remoteFriends)
            defaults.removeObject(forKey: CacheKeys.legacyRemoteFriends)
            clearAccountScopedFriendState()
        }
        defaults.set(normalizedIdentifier, forKey: CacheKeys.cloudAccount)
    }

    private func clearAccountScopedFriendState() {
        state.inviteFlowState = .idle
        state.inviteResultMessage = nil
        state.pendingInvite = nil
        state.staleFriendCacheState = .none
        state.postAcceptNavigationTarget = nil
        state.myPublicProfile = nil
        state.relationshipOverview = .empty
        state.outgoingShares = []
        state.friends = []

        let status = state.myStatus
        state.myStatus = MySharedHealthStatus(
            displayName: status.displayName,
            permissionState: status.permissionState,
            sleepAccess: status.sleepAccess,
            walkingAccess: status.walkingAccess,
            locationAccess: status.locationAccess,
            syncState: status.syncState,
            sharedFriendCount: 0,
            summaryText: status.summaryText,
            detailText: status.detailText,
            lastUpdatedText: status.lastUpdatedText,
            isSharingEnabled: status.isSharingEnabled,
            isUsingCachedSnapshot: status.isUsingCachedSnapshot,
            snapshot: status.snapshot
        )
    }

    private func makeRefreshFriendsResult(
        outgoingAcceptedRecordNames: Set<String>,
        outgoingPendingRecordNames: Set<String>,
        postAcceptNavigationTarget: FriendHealthProfile?,
        verifiedAccountIdentifier: String,
        refreshID: UUID
    ) async -> RefreshFriendsResult {
        do {
            let sharedSnapshotsResult = try await cloudKitService.fetchSharedSnapshots()
            guard isCurrentRefresh(refreshID) else { throw CancellationError() }
            let incomingOwnerRecordNames = Set(sharedSnapshotsResult.snapshots.compactMap(\.ownerRecordName))
            let participantList = (try? await cloudKitService.fetchOwnedParticipants()) ?? []
            guard isCurrentRefresh(refreshID) else { throw CancellationError() }
            let participantRecordNames = participantList.compactMap(\.userRecordName)
            let snapshotRecordNames = sharedSnapshotsResult.snapshots.compactMap(\.ownerRecordName)
            let recordNames = Array(Set(snapshotRecordNames + participantRecordNames + [verifiedAccountIdentifier]))
            let profileMap = await fetchProfileMap(recordNames: recordNames)
            guard isCurrentRefresh(refreshID) else { throw CancellationError() }

            let profiles = followService.makeFriendProfiles(
                from: sharedSnapshotsResult.snapshots,
                profilesByRecordName: profileMap
            ).map { friend in
                FriendHealthProfile(
                    id: friend.id,
                    ownerUserRecordName: friend.ownerUserRecordName,
                    name: friend.name,
                    relationshipState: followService.makeRelationshipState(
                        incomingOwnerRecordNames: incomingOwnerRecordNames,
                        outgoingAcceptedRecordNames: outgoingAcceptedRecordNames,
                        outgoingPendingRecordNames: outgoingPendingRecordNames,
                        ownerUserRecordName: friend.ownerUserRecordName
                    ),
                    permissionRole: friend.permissionRole,
                    statusText: friend.statusText,
                    sleepText: friend.sleepText,
                    walkingText: friend.walkingText,
                    lastUpdated: friend.lastUpdated,
                    isStale: false,
                    publicProfile: friend.publicProfile,
                    availableContentSummary: friend.availableContentSummary,
                    snapshot: friend.snapshot
                )
            }
            let outgoingShares = followService.makeOutgoingShareProfiles(
                participants: participantList,
                incomingOwnerRecordNames: incomingOwnerRecordNames,
                outgoingAcceptedRecordNames: outgoingAcceptedRecordNames,
                outgoingPendingRecordNames: outgoingPendingRecordNames,
                profilesByRecordName: profileMap
            )

            guard await validateCloudAccount(
                verifiedAccountIdentifier,
                refreshID: refreshID
            ) else { throw CancellationError() }
            persistRemoteFriendProfiles(profiles, accountIdentifier: verifiedAccountIdentifier)

            let target = resolvePostAcceptNavigationTarget(
                profiles: profiles,
                pendingTarget: postAcceptNavigationTarget
            )

            let staleState: SocialSharingCacheState = sharedSnapshotsResult.source == .partial ? .partialFreshFriends : .none
            let errorMessage = sharedSnapshotsResult.error?.localizedDescription
            return RefreshFriendsResult(
                profiles: profiles,
                outgoingShares: outgoingShares,
                myPublicProfile: profileMap[verifiedAccountIdentifier],
                relationshipOverview: followService.makeRelationshipOverview(friends: profiles, outgoingShares: outgoingShares),
                staleState: staleState,
                errorMessage: errorMessage,
                postAcceptNavigationTarget: target
            )
        } catch {
            let emptyResult = RefreshFriendsResult(
                profiles: [],
                outgoingShares: [],
                myPublicProfile: nil,
                relationshipOverview: .empty,
                staleState: .none,
                errorMessage: nil,
                postAcceptNavigationTarget: nil
            )
            guard isCurrentRefresh(refreshID) else { return emptyResult }
            guard await validateCloudAccount(
                verifiedAccountIdentifier,
                refreshID: refreshID
            ) else { return emptyResult }

            let errorMessage = Self.makeFriendFetchErrorMessage(error, cloudKitService: cloudKitService)
            print("[社交共享] 拉取好友摘要失败 mappedError=\(errorMessage)")
            let cached = cachedRemoteFriendProfiles().map(Self.markFriendProfileStale)
            return RefreshFriendsResult(
                profiles: cached,
                outgoingShares: [],
                myPublicProfile: nil,
                relationshipOverview: followService.makeRelationshipOverview(friends: cached, outgoingShares: []),
                staleState: cached.isEmpty ? .none : .showingCachedFriends,
                errorMessage: errorMessage,
                postAcceptNavigationTarget: postAcceptNavigationTarget
            )
        }
    }

    private func resolvePostAcceptNavigationTarget(
        profiles: [FriendHealthProfile],
        pendingTarget: FriendHealthProfile?
    ) -> FriendHealthProfile? {
        guard let pendingTarget else { return nil }
        return profiles.first {
            $0.id == pendingTarget.id || $0.ownerUserRecordName == pendingTarget.ownerUserRecordName
        }
    }

    private static func markFriendProfileStale(_ friend: FriendHealthProfile) -> FriendHealthProfile {
        FriendHealthProfile(
            id: friend.id,
            ownerUserRecordName: friend.ownerUserRecordName,
            name: friend.name,
            relationshipState: friend.relationshipState,
            // v2 缓存可能由修复前版本写入 collaborator。离线读取不能因此恢复
            // 已废弃的写权限；好友健康 share 的接收方始终只读。
            permissionRole: .readOnly,
            statusText: friend.statusText,
            sleepText: friend.sleepText,
            walkingText: friend.walkingText,
            lastUpdated: friend.lastUpdated,
            isStale: true,
            publicProfile: friend.publicProfile,
            availableContentSummary: friend.availableContentSummary,
            snapshot: friend.snapshot
        )
    }

    private func fetchProfileMap(recordNames: [String]) async -> [String: PublicUserProfile] {
        guard !recordNames.isEmpty else { return [:] }
        do {
            let profiles = try await cloudKitService.fetchProfiles(recordNames: recordNames)
            return Dictionary(uniqueKeysWithValues: profiles.map { ($0.recordName, $0) })
        } catch {
            return [:]
        }
    }

    private static func makeSummaryText(
        snapshot: SharedHealthSnapshot?,
        permissionState: SharedHealthPermissionState
    ) -> String {
        guard let snapshot else {
            switch permissionState {
            case .needsPermission:
                return String(localized: "连接睡眠或步速后，就能开始和好友共享健康摘要；粗略位置可单独选择。")
            case .partialPermission:
                return String(localized: "现在可以先共享已授权的那部分健康摘要。")
            case .unavailable:
                return String(localized: "当前设备还不能生成好友可见的健康摘要。")
            case .ready:
                return String(localized: "最近还没有形成可共享的摘要。")
            }
        }

        let sleepText: String
        if let averageSleep = snapshot.highlights.averageSleepMinutes {
            let hours = averageSleep / 60
            let minutes = averageSleep % 60
            sleepText = minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        } else {
            sleepText = "暂无"
        }

        let walkingText: String
        if let averageWalking = snapshot.highlights.averageWalkingSpeedMps,
           snapshot.highlights.validWalkingSpeedDays >= 3 {
            walkingText = String(format: "%.2f m/s", averageWalking)
        } else {
            walkingText = "样本不足"
        }

        let locationText = snapshot.location == nil ? "位置未共享" : "位置已共享"
        let actionText = snapshot.sharedActionRecords.isEmpty ? "行动记录未共享" : "行动记录 \(snapshot.sharedActionRecords.count) 条"
        let countdownText = snapshot.sharedCountdownItems.isEmpty ? "倒数日未共享" : "倒数日 \(snapshot.sharedCountdownItems.count) 个"
        let todoCount = snapshot.sharedTodoListSummary?.itemCount ?? 0
        let todoText = todoCount > 0 ? "共享待办 \(todoCount) 条" : "共享待办未共享"
        return String(localized: "你当前共享：睡眠 \(sleepText) · 步速 \(walkingText) · \(locationText) · \(actionText) · \(countdownText) · \(todoText)")
    }

    private static func makeLastUpdatedText(snapshot: SharedHealthSnapshot?, syncState: SharedHealthSyncState) -> String {
        guard let generatedAt = snapshot?.generatedAt else {
            return syncState.title
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.unitsStyle = .short
        return String(localized: "更新于 \(formatter.localizedString(for: generatedAt, relativeTo: Date()))")
    }

    private static func makeGlobalErrorMessage(
        iCloudAvailable: Bool,
        friendProfiles: [FriendHealthProfile],
        staleState: SocialSharingCacheState
    ) -> String? {
        if !iCloudAvailable {
            return String(localized: "当前 iCloud 不可用，好友共享会在你登录后恢复。")
        }
        if !friendProfiles.isEmpty && staleState == .showingCachedFriends {
            return String(localized: "当前显示的是最近一次缓存的好友摘要，可能不是最新状态。")
        }
        if !friendProfiles.isEmpty && staleState == .partialFreshFriends {
            return String(localized: "部分好友摘要刚刚刷新成功，但仍有少量共享数据暂时未能拉取完整。")
        }
        return nil
    }

    private static func resolveRefreshErrorMessage(
        permissionState: SharedHealthPermissionState,
        myShareError: String?,
        friendFetchError: String?
    ) -> String? {
        if let myShareError {
            return myShareError
        }

        if permissionState == .needsPermission {
            return nil
        }

        return friendFetchError
    }

    private static func makeFriendFetchErrorMessage(
        _ error: Error,
        cloudKitService: CloudKitSharingService
    ) -> String {
        let mapped = cloudKitService.map(error)
        switch mapped {
        case .serverRejectedRequest:
                return String(localized: "好友摘要暂时无法从 iCloud 拉取，可能是 Apple CloudKit 临时错误。你仍可以先完成健康权限授权后重新刷新。")
        case .networkUnavailable:
                return String(localized: "网络不可用，暂时无法拉取好友摘要。")
        case .notAuthenticated:
                return String(localized: "当前 iCloud 账号未登录或暂时不可用，无法拉取好友摘要。")
        case .requestRateLimited:
            return mapped.localizedDescription
        default:
            return mapped.localizedDescription
        }
    }

    private func makeCurrentSharedTodoSummary(currentUserRecordName: String?) -> SharedTodoList? {
        makeOwnedTodoList(currentUserRecordName: currentUserRecordName)
    }

    private func makeOwnedTodoList(currentUserRecordName: String?) -> SharedTodoList? {
        let localList = todoStore.loadList()
        guard localList.isShared else { return nil }
        let items = localList.items.map { item in
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
        return SharedTodoList(
            id: localList.id,
            title: localList.title,
            ownerUserRecordName: currentUserRecordName,
            items: items,
            updatedAt: localList.updatedAt,
            lastEditedByUserRecordName: items.max(by: { $0.updatedAt < $1.updatedAt })?.createdByUserRecordName,
            permissionRole: .collaborator
        )
    }

    /// 同步完整待办 record 层级。健康 root 的 payload 只保留三条预览；完整清单
    /// 通过 parent 关系继承同一 CKShare 的只读权限。关闭共享时删除全部待办 records。
    private func syncOwnedTodoRecords(expectedUserRecordName: String) async throws {
        guard await validateCloudAccount(expectedUserRecordName) else {
            throw CloudKitDomainError.iCloudUnavailable
        }
        if let list = makeOwnedTodoList(currentUserRecordName: expectedUserRecordName) {
            _ = try await cloudKitService.syncCollaborativeTodoList(
                list,
                ownerUserRecordName: expectedUserRecordName
            )
        } else {
            try await cloudKitService.removeCollaborativeTodoList(
                ownerUserRecordName: expectedUserRecordName
            )
        }
        guard await validateCloudAccount(expectedUserRecordName) else {
            throw CloudKitDomainError.iCloudUnavailable
        }
    }

    private func syncOwnerSnapshotAfterLocalTodoChange() async {
        let isICloudAvailable = await cloudKitService.isICloudAvailable()
        guard isICloudAvailable else { return }
        guard let expectedUserRecordName = await cloudKitService.currentUserRecordName() else {
            invalidateFriendCacheForUnverifiedAccount()
            return
        }

        let buildResult = await healthService.buildMyShareSnapshot()
        guard let snapshot = buildResult.snapshot else { return }
        guard await validateCloudAccount(expectedUserRecordName) else { return }

        guard (try? await cloudKitService.hasOwnedShare()) == true else { return }
        guard await validateCloudAccount(expectedUserRecordName) else { return }
        await cloudKitService.upsertUserProfile(
            displayName: snapshot.ownerDisplayName,
            isSearchable: defaults.bool(forKey: SocialSharingPreferenceKeys.profileSearchable),
            expectedUserRecordName: expectedUserRecordName
        )
        guard await validateCloudAccount(expectedUserRecordName) else { return }
        guard buildResult.source == .fresh else { return }
        do {
            _ = try await cloudKitService.saveMySharedSnapshot(
                snapshot,
                expectedUserRecordName: expectedUserRecordName
            )
            try await syncOwnedTodoRecords(expectedUserRecordName: expectedUserRecordName)
        } catch {
            state.errorMessage = localizedSharingError(error)
        }
    }

    private func mergeTodoItems(
        existingItems: [SharedTodoItem],
        id: String?,
        title: String,
        isCompleted: Bool,
        note: String?,
        dueDate: Date?,
        currentUserRecordName: String?,
        now: Date
    ) -> [SharedTodoItem] {
        if let id, let existingIndex = existingItems.firstIndex(where: { $0.id == id }) {
            var item = existingItems[existingIndex]
            let normalizedNote = normalize(note)
            let fieldTimestamps = SharedTodoFieldTimestamps(
                titleUpdatedAt: item.title == title ? item.fieldTimestamps.titleUpdatedAt : now,
                completionUpdatedAt: item.isCompleted == isCompleted ? item.fieldTimestamps.completionUpdatedAt : now,
                noteUpdatedAt: item.note == normalizedNote ? item.fieldTimestamps.noteUpdatedAt : now,
                dueDateUpdatedAt: item.dueDate == dueDate ? item.fieldTimestamps.dueDateUpdatedAt : now
            )
            item = SharedTodoItem(
                id: item.id,
                title: title,
                isCompleted: isCompleted,
                note: normalizedNote,
                dueDate: dueDate,
                createdByUserRecordName: item.createdByUserRecordName,
                createdAt: item.createdAt,
                updatedAt: now,
                fieldTimestamps: fieldTimestamps
            )
            var items = existingItems
            items[existingIndex] = item
            return items.sorted(by: sortTodoItems)
        }

        var items = existingItems
        items.append(
            SharedTodoItem(
                id: id ?? UUID().uuidString,
                title: title,
                isCompleted: isCompleted,
                note: normalize(note),
                dueDate: dueDate,
                createdByUserRecordName: currentUserRecordName,
                createdAt: now,
                updatedAt: now,
                fieldTimestamps: .uniform(now)
            )
        )
        return items.sorted(by: sortTodoItems)
    }

    private func sortTodoItems(lhs: SharedTodoItem, rhs: SharedTodoItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted {
            return !lhs.isCompleted && rhs.isCompleted
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func normalize(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
