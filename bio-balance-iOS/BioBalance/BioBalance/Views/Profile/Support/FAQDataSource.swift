import Foundation
import SwiftUI

enum FAQCategory: String, CaseIterable, Identifiable {
    case stressRecovery
    case watchSync
    case sleep
    case dataPrivacy
    case accountOther

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stressRecovery: String(localized: "压力与恢复")
        case .watchSync: String(localized: "Watch 与同步")
        case .sleep: String(localized: "睡眠")
        case .dataPrivacy: String(localized: "数据与隐私")
        case .accountOther: String(localized: "账号与其他")
        }
    }

    var symbol: String {
        switch self {
        case .stressRecovery: "waveform.path.ecg"
        case .watchSync: "applewatch"
        case .sleep: "moon.zzz.fill"
        case .dataPrivacy: "lock.shield.fill"
        case .accountOther: "person.crop.circle"
        }
    }

    var tint: Color {
        switch self {
        case .stressRecovery: MianyuSupportPalette.green
        case .watchSync: Color(hex: "656FFF")
        case .sleep: Color(hex: "8066CC")
        case .dataPrivacy: Color(hex: "C57922")
        case .accountOther: Color(hex: "55606F")
        }
    }
}

struct SupportFAQItem: Identifiable, Hashable {
    let id: String
    let category: FAQCategory
    let question: String
    let answer: String
    let summary: String
}

enum FAQDataSource {
    static let items: [SupportFAQItem] = [
        SupportFAQItem(id: "stress-hrv-basics", category: .stressRecovery, question: String(localized: "压力与 HRV 基础科普"), answer: String(localized: "HRV 是心跳间隔变化的参考指标，通常需要结合个人基线、睡眠、活动和当下状态理解。单次高低不能独立代表健康好坏，也不用于医疗诊断。"), summary: String(localized: "了解参考值与 HRV 的关系")),
        SupportFAQItem(id: "stress-refresh", category: .stressRecovery, question: String(localized: "压力监测多久更新一次？"), answer: String(localized: "压力参考值会在获得足够的心率与 HRV 样本后更新，并非实时连续测量。佩戴手表、保持授权开启并在安静状态下等待一段时间，有助于获得新结果。"), summary: String(localized: "刷新频率与主动触发方式")),
        SupportFAQItem(id: "measurement-accuracy", category: .stressRecovery, question: String(localized: "如何提高测量准确度？"), answer: String(localized: "请让手表贴合但不过紧，保持传感器清洁，并尽量在静止、呼吸自然的状态下测量。运动、松动佩戴或皮肤潮湿都可能影响结果。"), summary: String(localized: "佩戴、清洁和静止状态")),
        SupportFAQItem(id: "estimated-blood-pressure", category: .stressRecovery, question: String(localized: "推算血压靠谱吗？"), answer: String(localized: "眠屿展示的血压相关信息只用于趋势理解，可能受到设备、个人基线和采样条件影响，不能替代袖带血压计或专业医疗诊断。"), summary: String(localized: "原理、误差来源和适用边界")),

        SupportFAQItem(id: "watch-not-syncing", category: .watchSync, question: String(localized: "Apple Watch 数据没有同步怎么办？"), answer: String(localized: "请确认 iPhone 与 Apple Watch 已连接、健康权限已开启，并分别打开一次眠屿与手表 App。仍未更新时，可检查系统健康 App 中是否已经出现对应数据。"), summary: String(localized: "授权、连接与刷新检查")),
        SupportFAQItem(id: "watch-notification", category: .watchSync, question: String(localized: "手表无法收到压力通知"), answer: String(localized: "请在 iPhone 的系统设置和眠屿通知设置中同时开启通知，并确认 Apple Watch 未处于勿扰或低电量限制状态。"), summary: String(localized: "通知权限与专注模式")),
        SupportFAQItem(id: "complication-refresh", category: .watchSync, question: String(localized: "表盘组件为什么不会立刻更新？"), answer: String(localized: "表盘组件由系统安排刷新时间。打开眠屿或手表 App 可请求新快照，但具体显示时机仍由 watchOS 根据电量与使用情况决定。"), summary: String(localized: "系统刷新机制说明")),
        SupportFAQItem(id: "other-watch", category: .watchSync, question: String(localized: "非 Apple Watch 如何同步到健康？"), answer: String(localized: "只要设备厂商能够把数据写入 Apple 健康，眠屿在获得授权后就可以读取支持的数据类型。具体同步能力由设备厂商决定。"), summary: String(localized: "第三方设备的数据路径")),

        SupportFAQItem(id: "sleep-stage-difference", category: .sleep, question: String(localized: "睡眠阶段为什么和系统不同？"), answer: String(localized: "不同页面可能采用不同聚合方式、时间边界或有效样本规则，因此阶段时长会有轻微差异。眠屿会优先保留来源并用一致规则解释趋势。"), summary: String(localized: "数据来源、算法与展示差异")),
        SupportFAQItem(id: "sleep-missing", category: .sleep, question: String(localized: "昨晚的睡眠数据没有出现"), answer: String(localized: "请先确认系统健康 App 中已有昨晚记录，并检查睡眠读取权限。系统完成合并后，再回到眠屿下拉刷新。"), summary: String(localized: "检查来源与读取权限")),
        SupportFAQItem(id: "sleep-time-boundary", category: .sleep, question: String(localized: "跨零点睡眠会怎么归属？"), answer: String(localized: "跨零点的主要睡眠通常归到醒来的那一天，短暂小睡则按实际发生时间展示，便于与当天状态对应。"), summary: String(localized: "日期边界与归属规则")),
        SupportFAQItem(id: "sleep-score", category: .sleep, question: String(localized: "睡眠分数是怎么计算的？"), answer: String(localized: "睡眠分综合考虑时长、连续性、阶段结构与个人基线。它适合观察变化，不代表医学结论，也不应成为焦虑来源。"), summary: String(localized: "时长、连续性与个人基线")),
        SupportFAQItem(id: "sleep-trend", category: .sleep, question: String(localized: "为什么建议按周看睡眠？"), answer: String(localized: "单晚睡眠容易受临时安排、环境和设备采样影响。一周趋势更能体现规律与变化，也更适合指导小行动。"), summary: String(localized: "趋势比单次结果更稳定")),

        SupportFAQItem(id: "privacy-manage", category: .dataPrivacy, question: String(localized: "如何管理健康数据与隐私？"), answer: String(localized: "你可以随时在系统健康设置中调整眠屿的读取权限，也可以在眠屿的数据与隐私页面查看、导出或删除本地数据。"), summary: String(localized: "权限、存储与删除方式")),
        SupportFAQItem(id: "data-source", category: .dataPrivacy, question: String(localized: "健康数据来自哪里？"), answer: String(localized: "眠屿优先读取你明确授权的 Apple 健康数据，并标注无法确认或样本不足的状态，不会凭空生成测量值。"), summary: String(localized: "设备、系统与授权来源")),
        SupportFAQItem(id: "icloud-sync", category: .dataPrivacy, question: String(localized: "多设备数据如何同步？"), answer: String(localized: "支持同步的数据通过你的 iCloud 与 CloudKit 私有空间传递，不依赖眠屿的业务后端账号。请确认设备登录同一 Apple ID 且 iCloud 可用。"), summary: String(localized: "iCloud 与 CloudKit 私有同步")),
        SupportFAQItem(id: "delete-data", category: .dataPrivacy, question: String(localized: "删除 App 会清除所有数据吗？"), answer: String(localized: "本地数据会随 App 删除；已同步到 iCloud 的数据可能仍保留在你的私有空间。重新安装前如需彻底清理，请先使用应用内删除入口。"), summary: String(localized: "本地与云端数据区别")),

        SupportFAQItem(id: "account-required", category: .accountOther, question: String(localized: "一定要登录才能使用吗？"), answer: String(localized: "核心健康查看可在本机使用。部分跨设备或需要身份关联的能力可能要求登录，页面会在需要时明确说明。"), summary: String(localized: "本机能力与账号边界")),
        SupportFAQItem(id: "contact-change", category: .accountOther, question: String(localized: "如何修改个人资料？"), answer: String(localized: "前往“我的－我的信息”即可调整可编辑资料。与健康权限相关的内容仍需在系统设置或健康 App 中修改。"), summary: String(localized: "个人信息与系统信息")),
        SupportFAQItem(id: "widget-stale", category: .accountOther, question: String(localized: "小组件内容没有更新"), answer: String(localized: "请先打开眠屿刷新数据。小组件更新时间由系统调度；若长期不更新，可移除后重新添加，并确认低电量模式没有长期限制后台刷新。"), summary: String(localized: "刷新快照与系统调度")),
        SupportFAQItem(id: "offline", category: .accountOther, question: String(localized: "没有网络还能使用吗？"), answer: String(localized: "已经保存在本机的数据可以离线查看。需要 iCloud 同步、外部链接或发送反馈的功能，会在网络恢复后才能完成。"), summary: String(localized: "本地可用与联网功能")),
        SupportFAQItem(id: "medical-boundary", category: .accountOther, question: String(localized: "眠屿能替代医生诊断吗？"), answer: String(localized: "不能。眠屿用于记录、整理和理解日常健康信息，不提供诊断或治疗。出现持续不适、异常指标或紧急情况时，请及时寻求专业医疗帮助。"), summary: String(localized: "健康信息的使用边界")),
        SupportFAQItem(id: "feedback-reply", category: .accountOther, question: String(localized: "提交反馈后多久会回复？"), answer: String(localized: "通常会在 1–3 个工作日内回复。信息越完整，越有助于我们定位问题；请不要在附件中包含不必要的敏感健康信息。"), summary: String(localized: "反馈处理时间与隐私提醒"))
    ]

    static var featuredItems: [SupportFAQItem] {
        let featuredIDs = Set(["stress-hrv-basics", "stress-refresh", "measurement-accuracy", "estimated-blood-pressure"])
        return items.filter { featuredIDs.contains($0.id) }
    }

    static func item(id: String) -> SupportFAQItem? {
        items.first { $0.id == id }
    }

    static func count(for category: FAQCategory) -> Int {
        items.lazy.filter { $0.category == category }.count
    }

    static func filteredItems(searchText: String, category: FAQCategory? = nil) -> [SupportFAQItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            let categoryMatches = category == nil || item.category == category
            guard categoryMatches else { return false }
            guard !query.isEmpty else { return true }
            return item.question.localizedCaseInsensitiveContains(query)
                || item.answer.localizedCaseInsensitiveContains(query)
                || item.summary.localizedCaseInsensitiveContains(query)
                || item.category.title.localizedCaseInsensitiveContains(query)
        }
    }
}
