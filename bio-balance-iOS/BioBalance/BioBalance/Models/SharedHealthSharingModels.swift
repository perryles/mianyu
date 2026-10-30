import Foundation

nonisolated enum SocialSharingPreferenceKeys {
    static let profileSearchable = "social.sharing.profile-searchable.v1"
    static let specialFocusFriendIDs = "social.focus.friend-ids.v1"
    static let specialFocusNewStatus = "social.focus.new-status.v1"
    static let specialFocusWorkoutCompleted = "social.focus.workout-completed.v1"
    static let specialFocusSharingChanged = "social.focus.sharing-changed.v1"
    static let specialFocusPinnedActivity = "social.focus.pinned-activity.v1"
}

/// 好友健康摘要的逐项授权。权限在生成共享快照前生效，而不是仅在 UI 隐藏。
/// 当前 CloudKit 白名单只允许睡眠与步速摘要；其余敏感指标在合同扩展前不进入该模型。
nonisolated struct FriendSharePermission: Codable, Equatable, Sendable {
    var sleep: Bool
    var activity: Bool
    var liveStatus: Bool
    var showsLastUpdated: Bool

    static let conservativeDefault = FriendSharePermission(
        sleep: true,
        activity: true,
        liveStatus: false,
        showsLastUpdated: true
    )

    func filtering(_ snapshot: SharedHealthSnapshot) -> SharedHealthSnapshot {
        let filteredDays = snapshot.days.map {
            SharedHealthDay(
                date: $0.date,
                sleepMinutes: sleep ? $0.sleepMinutes : nil,
                walkingSpeedMps: activity ? $0.walkingSpeedMps : nil
            )
        }
        let sleepValues = filteredDays.compactMap(\.sleepMinutes)
        let walkingValues = filteredDays.compactMap(\.walkingSpeedMps)
        return SharedHealthSnapshot(
            ownerUserID: snapshot.ownerUserID,
            ownerDisplayName: snapshot.ownerDisplayName,
            generatedAt: snapshot.generatedAt,
            days: filteredDays,
            highlights: SharedHealthHighlights(
                averageSleepMinutes: sleepValues.isEmpty ? nil : Int((Double(sleepValues.reduce(0, +)) / Double(sleepValues.count)).rounded()),
                averageWalkingSpeedMps: walkingValues.isEmpty ? nil : walkingValues.reduce(0, +) / Double(walkingValues.count),
                validSleepDays: sleepValues.count,
                validWalkingSpeedDays: walkingValues.count
            ),
            location: snapshot.location,
            payloadVersion: snapshot.payloadVersion,
            sharedActionRecords: snapshot.sharedActionRecords,
            sharedCountdownItems: snapshot.sharedCountdownItems,
            sharedTodoListSummary: snapshot.sharedTodoListSummary
        )
    }
}

nonisolated enum SharedActionKind: String, Codable, Hashable, Sendable, CaseIterable {
    case water
    case sunlight
    case mindfulness
    case stand

    var title: String {
        switch self {
        case .water:
            return "补水"
        case .sunlight:
            return String(localized: "晒太阳")
        case .mindfulness:
            return "呼吸正念"
        case .stand:
            return "起身活动"
        }
    }
}

enum SharedHealthPermissionState: String, Codable, Sendable {
    case unavailable
    case needsPermission
    case partialPermission
    case ready

    var title: String {
        switch self {
        case .unavailable:
            return String(localized: "当前设备不支持")
        case .needsPermission:
            return String(localized: "需要授权")
        case .partialPermission:
            return String(localized: "部分可用")
        case .ready:
            return String(localized: "已准备好")
        }
    }
}

enum HealthMetricAccessState: String, Codable, Sendable {
    case unavailable
    case unauthorized
    case authorized

    var title: String {
        switch self {
        case .unavailable:
            return String(localized: "不可用")
        case .unauthorized:
            return String(localized: "未连接")
        case .authorized:
            return String(localized: "已连接")
        }
    }
}

enum SharedHealthSyncState: String, Codable, Sendable {
    case idle
    case syncing
    case synced
    case stale
    case failed

    var title: String {
        switch self {
        case .idle:
            return String(localized: "等待同步")
        case .syncing:
            return String(localized: "同步中")
        case .synced:
            return "已同步"
        case .stale:
            return String(localized: "缓存数据")
        case .failed:
            return "同步失败"
        }
    }
}

enum SocialSharingPhase: String, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

enum InviteFlowState: String, Sendable {
    case idle
    case confirming
    case preparing
    case ready
    case presenting
    case sent
    case failed
}

enum SocialInvitePolicy {
    static func requiresHealthAuthorization(_ permissionState: SharedHealthPermissionState) -> Bool {
        permissionState == .needsPermission
    }

    static func canPrepareInvite(
        permissionState: SharedHealthPermissionState,
        hasSnapshot: Bool,
        isICloudAvailable: Bool
    ) -> Bool {
        guard isICloudAvailable, hasSnapshot else { return false }
        return permissionState == .ready || permissionState == .partialPermission
    }
}

enum SocialSharingEmptyStateReason: String, Sendable {
    case none
    case needsPermission
    case noFriends
    case noDataYet
    case iCloudUnavailable
}

enum SocialSharingCacheState: String, Sendable {
    case none
    case showingCachedFriends
    case partialFreshFriends
}

enum RelationshipState: String, Codable, Hashable, Sendable {
    case incomingShared
    case outgoingShared
    case mutualShared
    case pendingOutgoingInvite

    var title: String {
        switch self {
        case .incomingShared:
            return String(localized: "对方向你共享")
        case .outgoingShared:
            return String(localized: "已发送共享")
        case .mutualShared:
            return String(localized: "双方互相关注")
        case .pendingOutgoingInvite:
            return String(localized: "等待对方接受")
        }
    }
}

nonisolated enum FriendPermissionRole: String, Codable, Hashable, Sendable {
    case readOnly
    // 保留 raw value 兼容旧缓存和 payload；它只用于表示所有者管理自己的本地清单。
    // 好友 CKShare 接收方永远会在 CloudKit 读取边界降级为 readOnly。
    case collaborator

    var title: String {
        switch self {
        case .readOnly:
            return String(localized: "只读")
        case .collaborator:
            return String(localized: "所有者可管理")
        }
    }
}

struct PendingInvite: Hashable, Sendable {
    let ownerRecordName: String
    let displayName: String
    let createdAt: Date
}

struct PublicUserProfile: Identifiable, Codable, Hashable, Sendable {
    let recordName: String
    let handle: String
    let displayName: String
    let avatarSeed: String?
    let isSearchable: Bool
    let updatedAt: Date?

    var id: String { recordName }
}

struct SocialRelationshipOverview: Hashable, Sendable {
    let mutualCount: Int
    let incomingCount: Int
    let outgoingOnlyCount: Int
    let pendingCount: Int

    static let empty = SocialRelationshipOverview(
        mutualCount: 0,
        incomingCount: 0,
        outgoingOnlyCount: 0,
        pendingCount: 0
    )
}

struct CloudKitOwnedParticipant: Hashable, Sendable {
    let userRecordName: String?
    let displayName: String?
    let acceptanceStatus: String
}

struct OutgoingShareProfile: Identifiable, Hashable, Sendable {
    let id: String
    let ownerUserRecordName: String?
    let displayName: String
    let handle: String?
    let avatarSeed: String?
    let relationshipState: RelationshipState
    let acceptanceText: String
    let lastUpdatedText: String
    let publicProfile: PublicUserProfile?
}

nonisolated struct SharedHealthDay: Codable, Hashable, Sendable, Identifiable {
    let date: Date
    let sleepMinutes: Int?
    let walkingSpeedMps: Double?

    var id: TimeInterval { date.timeIntervalSince1970 }
}

nonisolated struct SharedHealthHighlights: Codable, Hashable, Sendable {
    let averageSleepMinutes: Int?
    let averageWalkingSpeedMps: Double?
    let validSleepDays: Int
    let validWalkingSpeedDays: Int
}

nonisolated struct SharedLocationSummary: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracyMeters: Double?
    let label: String?
    let capturedAt: Date

    var displayText: String {
        if let label, !label.isEmpty {
            return label
        }
        return String(format: "%.2f, %.2f", latitude, longitude)
    }
}

nonisolated struct SharedActionRecord: Codable, Hashable, Sendable, Identifiable {
    let date: Date
    let completedActions: [SharedActionKind]
    let summaryText: String
    let progressText: String

    var id: TimeInterval { date.timeIntervalSince1970 }
}

nonisolated struct SharedCountdownItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let targetDate: Date
    let relativeText: String
    let note: String?
}

nonisolated struct SharedTodoFieldTimestamps: Codable, Hashable, Sendable {
    let titleUpdatedAt: Date
    let completionUpdatedAt: Date
    let noteUpdatedAt: Date
    let dueDateUpdatedAt: Date

    init(
        titleUpdatedAt: Date,
        completionUpdatedAt: Date,
        noteUpdatedAt: Date,
        dueDateUpdatedAt: Date
    ) {
        self.titleUpdatedAt = titleUpdatedAt
        self.completionUpdatedAt = completionUpdatedAt
        self.noteUpdatedAt = noteUpdatedAt
        self.dueDateUpdatedAt = dueDateUpdatedAt
    }

    static func uniform(_ date: Date) -> SharedTodoFieldTimestamps {
        SharedTodoFieldTimestamps(
            titleUpdatedAt: date,
            completionUpdatedAt: date,
            noteUpdatedAt: date,
            dueDateUpdatedAt: date
        )
    }
}

nonisolated struct SharedTodoItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let isCompleted: Bool
    let note: String?
    let dueDate: Date?
    let createdByUserRecordName: String?
    let createdAt: Date
    let updatedAt: Date
    let fieldTimestamps: SharedTodoFieldTimestamps

    var summaryText: String {
        let completionText = isCompleted ? "已完成" : "待完成"
        if let dueDate {
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate("Md")
            return String(localized: "\(completionText) · 截止 \(formatter.string(from: dueDate))")
        }
        return completionText
    }
}

nonisolated struct SharedTodoList: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let ownerUserRecordName: String?
    let items: [SharedTodoItem]
    let updatedAt: Date
    let lastEditedByUserRecordName: String?
    let permissionRole: FriendPermissionRole

    var completedCount: Int {
        items.filter(\.isCompleted).count
    }

    var summaryText: String {
        guard !items.isEmpty else {
            return String(localized: "还没有共享待办")
        }
        return String(localized: "共 \(items.count) 项，已完成 \(completedCount) 项")
    }
}

nonisolated struct SharedTodoListSummary: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let ownerUserRecordName: String?
    let itemCount: Int
    let completedCount: Int
    let updatedAt: Date
    let lastEditedByUserRecordName: String?
    let permissionRole: FriendPermissionRole
    let previewItems: [SharedTodoItem]

    var summaryText: String {
        guard itemCount > 0 else {
            return String(localized: "还没有共享待办")
        }
        return String(localized: "共 \(itemCount) 项，已完成 \(completedCount) 项")
    }
}

nonisolated struct SharedHealthSnapshot: Codable, Hashable, Sendable {
    let ownerUserID: String?
    let ownerDisplayName: String
    let generatedAt: Date
    let days: [SharedHealthDay]
    let highlights: SharedHealthHighlights
    let location: SharedLocationSummary?
    let payloadVersion: Int
    let sharedActionRecords: [SharedActionRecord]
    let sharedCountdownItems: [SharedCountdownItem]
    let sharedTodoListSummary: SharedTodoListSummary?

    nonisolated init(
        ownerUserID: String?,
        ownerDisplayName: String,
        generatedAt: Date,
        days: [SharedHealthDay],
        highlights: SharedHealthHighlights,
        location: SharedLocationSummary? = nil,
        payloadVersion: Int,
        sharedActionRecords: [SharedActionRecord] = [],
        sharedCountdownItems: [SharedCountdownItem] = [],
        sharedTodoListSummary: SharedTodoListSummary? = nil
    ) {
        self.ownerUserID = ownerUserID
        self.ownerDisplayName = ownerDisplayName
        self.generatedAt = generatedAt
        self.days = days
        self.highlights = highlights
        self.location = location
        self.payloadVersion = payloadVersion
        self.sharedActionRecords = sharedActionRecords
        self.sharedCountdownItems = sharedCountdownItems
        self.sharedTodoListSummary = sharedTodoListSummary
    }

    private enum CodingKeys: String, CodingKey {
        case ownerUserID
        case ownerDisplayName
        case generatedAt
        case days
        case highlights
        case location
        case payloadVersion
        case sharedActionRecords
        case sharedCountdownItems
        case sharedTodoListSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ownerUserID = try container.decodeIfPresent(String.self, forKey: .ownerUserID)
        ownerDisplayName = try container.decode(String.self, forKey: .ownerDisplayName)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        days = try container.decode([SharedHealthDay].self, forKey: .days)
        highlights = try container.decode(SharedHealthHighlights.self, forKey: .highlights)
        location = try container.decodeIfPresent(SharedLocationSummary.self, forKey: .location)
        payloadVersion = try container.decodeIfPresent(Int.self, forKey: .payloadVersion) ?? 1
        sharedActionRecords = try container.decodeIfPresent([SharedActionRecord].self, forKey: .sharedActionRecords) ?? []
        sharedCountdownItems = try container.decodeIfPresent([SharedCountdownItem].self, forKey: .sharedCountdownItems) ?? []
        if let summary = try? container.decode(SharedTodoListSummary.self, forKey: .sharedTodoListSummary) {
            sharedTodoListSummary = summary
        } else if let legacyList = try? container.decode(SharedTodoList.self, forKey: .sharedTodoListSummary) {
            // 旧 payload 在同一 key 下保存了完整待办。只在解码边界转成当前摘要，
            // 新缓存和 CloudKit 写入不再传播完整旧结构。
            sharedTodoListSummary = SharedTodoListSummary(
                id: legacyList.id,
                title: legacyList.title,
                ownerUserRecordName: legacyList.ownerUserRecordName,
                itemCount: legacyList.items.count,
                completedCount: legacyList.completedCount,
                updatedAt: legacyList.updatedAt,
                lastEditedByUserRecordName: legacyList.lastEditedByUserRecordName,
                permissionRole: legacyList.permissionRole,
                previewItems: Array(legacyList.items.prefix(3))
            )
        } else {
            sharedTodoListSummary = nil
        }
    }

    /// CKShare 的服务端权限才是事实来源。旧 payload 里的 collaborator 仅为兼容
    /// 字段，接收方读取时必须降级，避免缓存或未来 UI 误把它当作写权限。
    func sanitizedForFriendRecipient() -> SharedHealthSnapshot {
        let sanitizedTodoSummary = sharedTodoListSummary.map { summary in
            SharedTodoListSummary(
                id: summary.id,
                title: summary.title,
                ownerUserRecordName: summary.ownerUserRecordName,
                itemCount: summary.itemCount,
                completedCount: summary.completedCount,
                updatedAt: summary.updatedAt,
                lastEditedByUserRecordName: summary.lastEditedByUserRecordName,
                permissionRole: .readOnly,
                previewItems: summary.previewItems
            )
        }
        return SharedHealthSnapshot(
            ownerUserID: ownerUserID,
            ownerDisplayName: ownerDisplayName,
            generatedAt: generatedAt,
            days: days,
            highlights: highlights,
            location: location,
            payloadVersion: payloadVersion,
            sharedActionRecords: sharedActionRecords,
            sharedCountdownItems: sharedCountdownItems,
            sharedTodoListSummary: sanitizedTodoSummary
        )
    }

    /// 返回一份移除粗略位置字段的副本。
    ///
    /// 位置共享是独立的显式同意（`social.sharing.approximate-location-enabled.v1`，默认关闭）。
    /// 用户关闭后，任何可能进入共享载荷、本地预览或邀请 payload 的快照都必须立即移除旧位置，
    /// 不能因缓存降级而继续携带上一次开启时留下的粗略坐标（`ICLOUD_DATA_ARCHITECTURE.md`
    /// “关闭后下一份有效快照必须移除位置字段”）。
    func removingLocation() -> SharedHealthSnapshot {
        guard location != nil else { return self }
        return SharedHealthSnapshot(
            ownerUserID: ownerUserID,
            ownerDisplayName: ownerDisplayName,
            generatedAt: generatedAt,
            days: days,
            highlights: highlights,
            location: nil,
            payloadVersion: payloadVersion,
            sharedActionRecords: sharedActionRecords,
            sharedCountdownItems: sharedCountdownItems,
            sharedTodoListSummary: sharedTodoListSummary
        )
    }
}

struct MySharedHealthStatus: Hashable, Sendable {
    let displayName: String
    let permissionState: SharedHealthPermissionState
    let sleepAccess: HealthMetricAccessState
    let walkingAccess: HealthMetricAccessState
    let locationAccess: HealthMetricAccessState
    let syncState: SharedHealthSyncState
    let sharedFriendCount: Int
    let summaryText: String
    let detailText: String
    let lastUpdatedText: String
    let isSharingEnabled: Bool
    let isUsingCachedSnapshot: Bool
    let snapshot: SharedHealthSnapshot?
}

struct FriendHealthProfile: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let ownerUserRecordName: String?
    let name: String
    let relationshipState: RelationshipState
    let permissionRole: FriendPermissionRole
    let statusText: String
    let sleepText: String
    let walkingText: String
    let lastUpdated: Date
    let isStale: Bool
    let publicProfile: PublicUserProfile?
    let availableContentSummary: String
    let snapshot: SharedHealthSnapshot

    private enum CodingKeys: String, CodingKey {
        case id
        case ownerUserRecordName
        case name
        case relationshipState
        case permissionRole
        case statusText
        case sleepText
        case walkingText
        case lastUpdated
        case isStale
        case publicProfile
        case availableContentSummary
        case snapshot
    }

    init(
        id: String,
        ownerUserRecordName: String?,
        name: String,
        relationshipState: RelationshipState,
        permissionRole: FriendPermissionRole,
        statusText: String,
        sleepText: String,
        walkingText: String,
        lastUpdated: Date,
        isStale: Bool,
        publicProfile: PublicUserProfile?,
        availableContentSummary: String,
        snapshot: SharedHealthSnapshot
    ) {
        self.id = id
        self.ownerUserRecordName = ownerUserRecordName
        self.name = name
        self.relationshipState = relationshipState
        self.permissionRole = permissionRole
        self.statusText = statusText
        self.sleepText = sleepText
        self.walkingText = walkingText
        self.lastUpdated = lastUpdated
        self.isStale = isStale
        self.publicProfile = publicProfile
        self.availableContentSummary = availableContentSummary
        self.snapshot = snapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        ownerUserRecordName = try container.decodeIfPresent(String.self, forKey: .ownerUserRecordName)
        name = try container.decode(String.self, forKey: .name)
        relationshipState = try container.decode(RelationshipState.self, forKey: .relationshipState)
        // FriendHealthProfile 只表示收到的好友数据。忽略旧缓存里的 collaborator，
        // 避免离线启动时短暂恢复已经废弃的好友写权限。
        _ = try container.decodeIfPresent(FriendPermissionRole.self, forKey: .permissionRole)
        permissionRole = .readOnly
        statusText = try container.decode(String.self, forKey: .statusText)
        sleepText = try container.decode(String.self, forKey: .sleepText)
        walkingText = try container.decode(String.self, forKey: .walkingText)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        isStale = try container.decode(Bool.self, forKey: .isStale)
        publicProfile = try container.decodeIfPresent(PublicUserProfile.self, forKey: .publicProfile)
        snapshot = try container.decode(SharedHealthSnapshot.self, forKey: .snapshot)
            .sanitizedForFriendRecipient()
        availableContentSummary = try container.decodeIfPresent(String.self, forKey: .availableContentSummary) ?? [
            snapshot.location == nil ? nil : "位置",
            snapshot.sharedActionRecords.isEmpty ? nil : "行动 \(snapshot.sharedActionRecords.count) 条",
            snapshot.sharedCountdownItems.isEmpty ? nil : "倒数日 \(snapshot.sharedCountdownItems.count) 个",
            (snapshot.sharedTodoListSummary?.itemCount ?? 0) > 0 ? "待办 \(snapshot.sharedTodoListSummary?.itemCount ?? 0) 条" : nil
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

struct SocialSharingState: Hashable, Sendable {
    var phase: SocialSharingPhase
    var isICloudAvailable: Bool
    var inviteFlowState: InviteFlowState
    var inviteResultMessage: String?
    var pendingInvite: PendingInvite?
    var emptyStateReason: SocialSharingEmptyStateReason
    var staleFriendCacheState: SocialSharingCacheState
    var postAcceptNavigationTarget: FriendHealthProfile?
    var myPublicProfile: PublicUserProfile?
    var relationshipOverview: SocialRelationshipOverview
    var outgoingShares: [OutgoingShareProfile]
    var myStatus: MySharedHealthStatus
    var friends: [FriendHealthProfile]
    var errorMessage: String?

    static let empty = SocialSharingState(
        phase: .idle,
        isICloudAvailable: false,
        inviteFlowState: .idle,
        inviteResultMessage: nil,
        pendingInvite: nil,
        emptyStateReason: .needsPermission,
        staleFriendCacheState: .none,
        postAcceptNavigationTarget: nil,
        myPublicProfile: nil,
        relationshipOverview: .empty,
        outgoingShares: [],
        myStatus: MySharedHealthStatus(
            displayName: "我",
            permissionState: .needsPermission,
            sleepAccess: .unauthorized,
            walkingAccess: .unauthorized,
            locationAccess: .unauthorized,
            syncState: .idle,
            sharedFriendCount: 0,
            summaryText: "开启后会生成最近 7 天的睡眠、步速摘要；粗略位置默认不共享。",
            detailText: "我们只共享健康摘要，不会共享完整 Health 原始记录。",
            lastUpdatedText: "尚未同步",
            isSharingEnabled: false,
            isUsingCachedSnapshot: false,
            snapshot: nil
        ),
        friends: [],
        errorMessage: nil
    )
}
