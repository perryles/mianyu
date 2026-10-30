import CloudKit
import Foundation

final class FollowService {
    static let shared = FollowService()

    func makeFriendProfiles(
        from sharedSnapshots: [SharedRemoteHealthSnapshot],
        profilesByRecordName: [String: PublicUserProfile] = [:],
        stale: Bool = false
    ) -> [FriendHealthProfile] {
        sharedSnapshots.map { item in
            let publicProfile = item.ownerRecordName.flatMap { profilesByRecordName[$0] }
            return FriendHealthProfile(
                // 每位 owner 的 root recordName 都相同，列表 ID 必须包含 owner，
                // 否则多个好友会在 SwiftUI diff 中互相覆盖。
                id: item.ownerRecordName ?? "\(item.recordID.zoneID.ownerName):\(item.recordName)",
                ownerUserRecordName: item.ownerRecordName,
                name: resolvedDisplayName(
                    snapshotDisplayName: item.snapshot.ownerDisplayName,
                    participantDisplayName: publicProfile?.displayName,
                    fallback: "好友"
                ),
                relationshipState: .incomingShared,
                permissionRole: item.permissionRole,
                statusText: statusText(for: item.snapshot),
                sleepText: sleepText(for: item.snapshot),
                walkingText: walkingText(for: item.snapshot),
                lastUpdated: item.generatedAt,
                isStale: stale,
                publicProfile: publicProfile,
                availableContentSummary: availableContentSummary(for: item.snapshot),
                snapshot: item.snapshot
            )
        }
    }

    func makePendingInvite(
        from snapshot: SharedHealthSnapshot,
        ownerRecordName: String?,
        createdAt: Date
    ) -> PendingInvite? {
        guard let ownerRecordName else { return nil }
        return PendingInvite(
            ownerRecordName: ownerRecordName,
            displayName: snapshot.ownerDisplayName,
            createdAt: createdAt
        )
    }

    func makeRelationshipState(
        incomingOwnerRecordNames: Set<String>,
        outgoingAcceptedRecordNames: Set<String>,
        outgoingPendingRecordNames: Set<String>,
        ownerUserRecordName: String?
    ) -> RelationshipState {
        guard let ownerUserRecordName else { return .incomingShared }
        if incomingOwnerRecordNames.contains(ownerUserRecordName) && outgoingAcceptedRecordNames.contains(ownerUserRecordName) {
            return .mutualShared
        }
        if outgoingPendingRecordNames.contains(ownerUserRecordName) {
            return .pendingOutgoingInvite
        }
        if outgoingAcceptedRecordNames.contains(ownerUserRecordName) {
            return .outgoingShared
        }
        return .incomingShared
    }

    func makeRelationshipOverview(friends: [FriendHealthProfile], outgoingShares: [OutgoingShareProfile]) -> SocialRelationshipOverview {
        SocialRelationshipOverview(
            mutualCount: friends.filter { $0.relationshipState == .mutualShared }.count,
            incomingCount: friends.filter { $0.relationshipState == .incomingShared }.count,
            outgoingOnlyCount: outgoingShares.filter { $0.relationshipState == .outgoingShared }.count,
            pendingCount: outgoingShares.filter { $0.relationshipState == .pendingOutgoingInvite }.count
        )
    }

    func makeOutgoingShareProfiles(
        participants: [CloudKitOwnedParticipant],
        incomingOwnerRecordNames: Set<String>,
        outgoingAcceptedRecordNames: Set<String>,
        outgoingPendingRecordNames: Set<String>,
        profilesByRecordName: [String: PublicUserProfile]
    ) -> [OutgoingShareProfile] {
        participants.compactMap { participant in
            guard let recordName = participant.userRecordName else { return nil }
            let relationshipState = makeRelationshipState(
                incomingOwnerRecordNames: incomingOwnerRecordNames,
                outgoingAcceptedRecordNames: outgoingAcceptedRecordNames,
                outgoingPendingRecordNames: outgoingPendingRecordNames,
                ownerUserRecordName: recordName
            )
            guard relationshipState == .outgoingShared || relationshipState == .pendingOutgoingInvite else {
                return nil
            }
            let publicProfile = profilesByRecordName[recordName]
            let displayName = resolvedDisplayName(
                snapshotDisplayName: publicProfile?.displayName,
                participantDisplayName: participant.displayName,
                fallback: "好友"
            )
            return OutgoingShareProfile(
                id: recordName,
                ownerUserRecordName: recordName,
                displayName: displayName,
                handle: publicProfile?.handle,
                avatarSeed: publicProfile?.avatarSeed,
                relationshipState: relationshipState,
                acceptanceText: acceptanceText(
                    relationshipState: relationshipState,
                    acceptanceStatus: participant.acceptanceStatus
                ),
                lastUpdatedText: lastUpdatedText(
                    relationshipState: relationshipState,
                    acceptanceStatus: participant.acceptanceStatus
                ),
                publicProfile: publicProfile
            )
        }
        .sorted { lhs, rhs in
            if lhs.relationshipState != rhs.relationshipState {
                return lhs.relationshipState == .pendingOutgoingInvite
            }
            return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func statusText(for snapshot: SharedHealthSnapshot) -> String {
        if let location = snapshot.location {
            return String(localized: "最近在 \(location.displayText) 附近")
        }
        if let lastSleep = snapshot.days.compactMap(\.sleepMinutes).last {
            return String(localized: "昨晚睡了 \(formatSleepMinutes(lastSleep))")
        }
        if snapshot.highlights.validWalkingSpeedDays > 0 {
            return "最近在保持步行节奏"
        }
        return String(localized: "好友暂时还没有可展示的摘要")
    }

    private func sleepText(for snapshot: SharedHealthSnapshot) -> String {
        guard let value = snapshot.highlights.averageSleepMinutes else {
            return "睡眠摘要暂缺"
        }
        return String(localized: "近 7 天睡眠 \(formatSleepMinutes(value))")
    }

    private func walkingText(for snapshot: SharedHealthSnapshot) -> String {
        guard let value = snapshot.highlights.averageWalkingSpeedMps,
              snapshot.highlights.validWalkingSpeedDays >= 3 else {
            return "步速样本不足"
        }
        return String(format: String(localized: "近 7 天步速 %.2f m/s"), value)
    }

    private func formatSleepMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    private func availableContentSummary(for snapshot: SharedHealthSnapshot) -> String {
        let locationText = snapshot.location == nil ? nil : "位置"
        let actionText = snapshot.sharedActionRecords.isEmpty ? nil : "行动 \(snapshot.sharedActionRecords.count) 条"
        let countdownText = snapshot.sharedCountdownItems.isEmpty ? nil : "倒数日 \(snapshot.sharedCountdownItems.count) 个"
        let todoCount = snapshot.sharedTodoListSummary?.itemCount ?? 0
        let todoText = todoCount > 0 ? "待办 \(todoCount) 条" : nil
        return [locationText, actionText, countdownText, todoText].compactMap { $0 }.joined(separator: " · ")
    }

    private func resolvedDisplayName(
        snapshotDisplayName: String?,
        participantDisplayName: String?,
        fallback: String
    ) -> String {
        if let snapshotDisplayName, !snapshotDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return snapshotDisplayName
        }
        if let participantDisplayName, !participantDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return participantDisplayName
        }
        return fallback
    }

    private func acceptanceText(relationshipState: RelationshipState, acceptanceStatus: String) -> String {
        switch relationshipState {
        case .pendingOutgoingInvite:
            return String(localized: "等待接受")
        case .outgoingShared:
            return String(localized: "已发共享")
        case .incomingShared:
            return String(localized: "收到共享")
        case .mutualShared:
            return String(localized: "互相关注")
        }
    }

    private func lastUpdatedText(relationshipState: RelationshipState, acceptanceStatus: String) -> String {
        if relationshipState == .pendingOutgoingInvite {
            return String(localized: "对方接受后会出现在好友摘要里")
        }
        if acceptanceStatus.lowercased().contains("accepted") {
            return String(localized: "对方已接受你的共享")
        }
        return String(localized: "共享状态稍后会自动刷新")
    }
}
