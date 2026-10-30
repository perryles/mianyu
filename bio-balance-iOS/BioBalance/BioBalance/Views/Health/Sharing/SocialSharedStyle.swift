/// SocialSharedStyle 作为社交共享模块的共享样式扩展。
/// 负责为 RelationshipState 提供不同关系状态的配色方案。

import SwiftUI

extension RelationshipState {
    var storyTint: Color {
        switch self {
        case .incomingShared:
            return Color(hex: "FF8B6B")
        case .outgoingShared:
            return Color(hex: "7A7DFF")
        case .mutualShared:
            return Color(hex: "6B62FF")
        case .pendingOutgoingInvite:
            return Color(hex: "FF9B68")
        }
    }

    var ringColors: [Color] {
        switch self {
        case .incomingShared:
            return [Color(hex: "FFAE7A"), Color(hex: "FF6B88")]
        case .outgoingShared:
            return [Color(hex: "6F7CFF"), Color(hex: "9D73FF")]
        case .mutualShared:
            return [Color(hex: "5F70FF"), Color(hex: "C86FFF")]
        case .pendingOutgoingInvite:
            return [Color(hex: "FFBA6B"), Color(hex: "FF8F6B")]
        }
    }
}

extension FriendHealthProfile {
    var storySubtitle: String {
        if isStale {
            return String(localized: "缓存摘要")
        }
        if relationshipState == .mutualShared {
            return String(localized: "在线")
        }
        return statusChipText
    }

    var storyStatusColor: Color {
        if isStale {
            return Color(hex: "FF9B68")
        }
        if relationshipState == .mutualShared {
            return Color(hex: "56E39F")
        }
        return relationshipState.storyTint
    }

    var statusChipText: String {
        if statusText.contains("恢复") {
            return "恢复不错"
        }
        if statusText.contains("压力") {
            return String(localized: "刚刚更新")
        }
        if statusText.contains("睡") {
            return "睡得不错"
        }
        if statusText.contains("节奏") {
            return "节奏稳定"
        }
        if isStale {
            return String(localized: "缓存摘要")
        }
        return String(localized: "刚刚更新")
    }
}