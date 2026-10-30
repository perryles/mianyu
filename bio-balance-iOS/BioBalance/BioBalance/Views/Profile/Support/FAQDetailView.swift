/// FAQDetailView 由 FAQListView 调用，作为「常见问题详情」页面。
/// 负责展示问题摘要、要点、使用场景与操作建议。

import SwiftUI

/// 常见问题视图 由上级页面或路由调用，作为帮助支持模块里的界面或内容组件。
/// 负责展示常见问题、答疑详情或设备宣传信息。
struct FAQDetailView: View {
    let question: String
    @AppStorage("app_font_scale_level") private var appFontScaleLevelRaw: Int = 2

    private struct FAQPresentation {
        let category: String
        let summary: String
        let highlights: [String]
        let useCase: String
        let actionTitle: String
        let actionSummary: String
        let tint: Color
    }

    private struct RelatedQuestion: Identifiable {
        let question: String
        let hint: String

        var id: String { question }
    }

    private var normalizedQuestion: String {
        switch question {
        case "手表无法收到压力通知", "手表无法收到压力通知？":
            return "手表无法收到压力通知"
        case "表盘不会自动更新", "表盘不会自动更新？":
            return "表盘不会自动更新"
        case "Watch与iPhone同步失败？", "Watch与iPhone同步失败", "Watch与iPhone同步失败", "Watch与iPhone同步失败？":
            return "Watch与iPhone同步失败"
        case "新Watch用户必读", "新Watch用户必读":
            return "新Watch用户必读"
        case "推算血压靠谱吗？":
            return "推算血压靠谱吗？"
        case "身体年龄和实际年龄有什么区别？":
            return "身体年龄和实际年龄有什么区别"
        case "为什么身体年龄更适合按周看？":
            return "为什么身体年龄更适合按周看"
        case "哪些指标最影响身体年龄？":
            return "哪些指标最影响身体年龄"
        case "身体年龄偏高是不是就代表身体变差了？":
            return "身体年龄偏高是不是就代表身体变差了"
        case "身体年龄为什么会突然波动？":
            return "身体年龄为什么会突然波动"
        case "样本不足时怎么理解身体年龄？":
            return "样本不足时怎么理解身体年龄"
        case "心肺耐力为什么更适合按周看？":
            return "心肺耐力为什么更适合按周看"
        case "心肺耐力低是不是代表身体不好？":
            return "心肺耐力低是不是代表身体不好"
        case "怎样更容易拿到新的心肺耐力估算？":
            return "怎样更容易拿到新的心肺耐力估算"
        case "月经周期是如何计算的？":
            return "月经周期是如何计算的"
        case "排卵期与易孕期有什么区别？":
            return "排卵期与易孕期有什么区别"
        case "经期症状波动大正常吗？":
            return "经期症状波动大正常吗"
        case "经期推迟几天常见吗？":
            return "经期推迟几天常见吗"
        case "痛经什么时候该就医？":
            return "痛经什么时候该就医"
        default:
            return question
        }
    }

    private var appFontScaleLevel: AppFontScaleLevel {
        AppFontScaleLevel(rawValue: appFontScaleLevelRaw) ?? .two
    }
    
    var answer: String {
        switch normalizedQuestion {
        case "压力与HRV基础科普":
            return String(localized: "HRV（心率变异性）通常指相邻心跳间隔的波动情况。一般来说，在休息和恢复良好时 HRV 往往更高；当疲劳、压力、睡眠不足或生病时 HRV 可能降低。\n\n眠屿 会结合 HRV 与心率等指标，给出压力参考值。它不是医疗诊断，仅用于日常自我管理。")
        case "推算血压靠谱吗？":
            return String(localized: "部分可穿戴设备会尝试结合心率、HRV、年龄、性别、睡眠、运动状态，以及 PPG（光电容积波）波形等信号，去估算一个大致血压范围。有些方案还会进一步利用脉搏传导时间（Pulse Transit Time）、ECG + PPG 联合信号，或者用 Transformer、LSTM 这类模型来做拟合。\n\n但这类推算结果的误差通常很大，尤其容易受到个体差异、情绪波动、表带松紧、皮肤温度、测量姿势，以及运动后短时生理变化影响。同样的算法，换一个人、换一个时间段、甚至换一次佩戴状态，结果都可能明显不同。\n\n所以更稳妥的理解方式是：它可以作为“高风险 / 低风险提醒”或趋势线索，帮助你知道最近是否值得多留意恢复、压力和血压变化；但它不适合替代标准血压计，也不适合作为医疗诊断依据。如果你已经出现头晕、胸闷、心悸，或者近期血压异常反复出现，还是应以规范测量和医生判断为准。")
        case "身体年龄和实际年龄有什么区别":
            return String(localized: "实际年龄是从出生开始累积的日历时间，而身体年龄更像是根据近期身体状态做出的阶段性估计。它会综合睡眠、活动量、心肺水平、静息心率和恢复状态等线索。\n\n这意味着两个同龄人，即使身份证年龄一样，身体年龄也可能不同。一个人如果长期睡眠稳定、活动充足、心肺状态好，身体年龄可能会低于实际年龄；反过来，长期疲劳、活动不足或恢复变差时，身体年龄就可能暂时偏高。\n\n身体年龄更适合当作健康管理参考，而不是给自己贴标签。看到偏高时，重点应该放在找出最近哪些状态在拖累身体，而不是只盯着一个数字焦虑。")
        case "为什么身体年龄更适合按周看":
            return String(localized: "身体年龄会受到最近几天状态影响，所以它天然不适合按单天做过度解读。比如前一晚睡得少、今天训练偏重、最近压力较大，都可能让单日结果出现暂时性偏移。\n\n把它放到一周里看，更容易区分“偶发波动”和“持续走高”。如果只是一天偏高，但接下来很快回稳，通常更像短期状态；如果连续几天都偏高，才更值得回看是不是睡眠、步数、心肺或恢复一直没有跟上。\n\n真正有参考价值的，不是某一天突然多了 1 岁或少了 1 岁，而是这一周的方向是不是在慢慢变差，或者有没有逐步回稳。")
        case "哪些指标最影响身体年龄":
            return String(localized: "身体年龄通常最容易受到睡眠、活动量、心肺能力和静息恢复状态影响。它不是单一指标，而是把这些线索合在一起看，判断你最近更像在恢复、维持，还是在透支。\n\n睡眠时长和作息节律决定恢复底盘。连续几天睡不好，身体年龄往往更容易走高。步数和日常活动量则代表你有没有维持基础活动水平；如果长期活动不足，身体会更容易停留在保守估计。\n\n最大摄氧量、静息心率和 HRV 更像心肺与恢复窗口。心肺状态更好、静息心率更稳、HRV 恢复更好时，身体年龄通常更容易维持在稳定或更年轻的区间。")
        case "身体年龄偏高是不是就代表身体变差了":
            return String(localized: "不一定。身体年龄偏高更像一个提醒，说明你最近的睡眠、活动、心肺或恢复状态里，可能有一到几项正在拖累整体判断。\n\n如果只是短时间偏高，而且几天后很快回稳，通常更像短期状态波动，比如最近睡少了、训练偏累、压力偏大，或者样本刚好不完整。只有当它连续几天甚至一周都维持在偏高区间，才更值得认真回看最近节律是不是一直没有跟上。\n\n所以看到偏高时，不需要先下结论说身体一定“变差了”，更好的做法是先回看最近一周的睡眠、步数、最大摄氧量、静息心率和 HRV 有没有一起变差。")
        case "身体年龄为什么会突然波动":
            return String(localized: "身体年龄并不是固定值，它会随着近期状态变化而调整。前一晚睡眠不足、当天训练负荷偏高、最近压力明显上来，或者身体正在恢复期，都可能让单日结果短暂偏移。\n\n另一个常见原因是样本质量变化。如果最近几天健康记录不完整，比如步数、睡眠或心肺数据变少，系统会更倾向于给出保守估计，看起来就像身体年龄突然变动。\n\n判断这种波动值不值得在意，关键不是盯住某一天，而是看接下来几天有没有继续同方向变化。短期波动常见，持续走高才更值得重视。")
        case "样本不足时怎么理解身体年龄":
            return String(localized: "样本不足时，身体年龄更适合当作一个保守提醒，而不是精确结论。因为它本来就依赖睡眠、活动量、心肺能力和恢复状态等多条线索，如果这些记录缺得比较多，结果就会更容易停留在中性或偏保守的估计。\n\n这时候最重要的不是反复解读数字，而是先补齐记录。比如连续佩戴设备、保证睡眠样本能被记录、补上日常步数和活动数据，再积累几天心肺和静息状态样本。\n\n等样本覆盖更完整后，再去看最近一周的方向，会比现在盯着一个不完整结果更有参考价值。")
        case "心肺耐力为什么更适合按周看":
            return String(localized: "心肺耐力更像一条慢变量，而不是会在一天里频繁跳动的实时指标。Apple Watch 生成 VO2 Max 估算，通常需要相对稳定、质量足够的步行、跑步或骑行样本，所以它天然更适合按阶段理解，而不适合按小时甚至按单天过度解读。\n\n这意味着今天比昨天多 0.5，或者某一次突然少了 0.8，并不一定代表身体真的在短时间里发生了明显变化。单次结果会受到近期活动样本、佩戴状态、恢复情况和数据覆盖完整度影响。把它放到一周甚至几周里看，才更容易分辨你是整体在缓慢提升、维持稳定，还是最近训练刺激减少、恢复跟不上，导致趋势开始走弱。\n\n真正更值得关注的是方向，而不是某一个点位本身。如果最近几周整体缓慢上行，通常说明有氧基础在积累；如果连续几周走低，再结合睡眠、静息心率、HRV 和日常活动一起回看，会比只盯着一次结果更有参考价值。")
        case "心肺耐力低是不是代表身体不好":
            return String(localized: "不一定。心肺耐力偏低更像说明你当前的有氧基础还在建立中，或者最近可用于估算的运动样本不够充分，并不等于立刻说明身体出了问题，更不适合被直接理解成“身体不好”。\n\n这个数字会受到年龄、近期活动量、连续有氧样本、佩戴质量和恢复状态影响。对于刚开始运动、最近缺少稳定步行跑步记录、长期活动偏少，或者健康记录覆盖不完整的人来说，VO2 Max 看起来偏低都很常见。也就是说，它更像一个阶段性的体能线索，而不是对健康好坏的单一判决。\n\n更好的读法不是只看当前高低，而是看它有没有在持续改善。如果你开始规律步行、跑步或骑行，睡眠和恢复也逐渐稳定，几周后整体趋势慢慢抬升，这通常比某一次具体数值更值得关注。真正需要留意的，往往不是“现在低不低”，而是“长期有没有继续走低，或者一直提不起来”。")
        case "怎样更容易拿到新的心肺耐力估算":
            return String(localized: "想更容易拿到新的心肺耐力估算，关键是给 Apple Watch 足够稳定、连续、质量较好的有氧运动样本。一般来说，持续一段时间的步行、跑步或骑行，比零散活动、短时走动或记录不完整的训练，更容易触发新的 VO2 Max 估算。\n\n佩戴贴合也很重要。如果表带过松、心率采样不稳定，或者运动过程中信号质量不好，系统就更难形成可信的估算结果。保持日常规律佩戴、让心率记录尽量连续完整，会比偶尔点开页面看一次结果更有效。对很多人来说，问题往往不是“为什么没显示”，而是“最近有没有给系统足够好的样本”。\n\n如果最近一直没有更新，可以先回看自己是不是缺少连续步行或跑步记录，近期是否佩戴不稳定，或者大多数活动都过于零散。通常先把样本质量和连续性补上，后续几天到几周里出现新估算的概率会更高。")
        case "手表无法收到压力通知":
            return String(localized: "请确保您的 Apple Watch 已连接至 iPhone，且在 iPhone 的「Watch」应用中开启了通知权限。同时，请检查手表的「勿扰模式」或「睡眠模式」是否处于关闭状态。\n\n如问题仍未解决，请尝试重启手表并重新授权健康数据。")
        case "表盘不会自动更新":
            return String(localized: "表盘组件的数据更新频率受限于 watchOS 系统的资源管理策略。通常每 15-30 分钟会自动刷新一次。如果发现长时间未更新，您可以点击表盘组件进入 App，数据会立即触发同步更新。")
        case "Watch与iPhone同步失败":
            return String(localized: "请检查以下几点：\n1. 确保 iPhone 和 Apple Watch 的蓝牙均已开启并保持连接。\n2. 确保已在「系统设置」>「健康」中授予 眠屿 所有的读取权限。\n3. 如果长时间未同步，您可以尝试在手表端强制退出 眠屿，并重新打开它触发一次手动同步。")
        case "压力监测频率相关说明", "压力监测频率相关":
            return String(localized: "眠屿 依赖于 Apple Watch 的后台心率变异性 (HRV) 测量。默认情况下，手表会在您处于相对静止状态时自动进行测量。如果您希望提高测量频率，可以在手表端开启「正念」应用进行一分钟的呼吸训练，这会强制手表生成一次高精度的 HRV 和压力数据。")
        case "新Watch用户必读":
            return String(localized: "欢迎来到 眠屿！作为新用户，请务必完成以下三步：\n1. 在 iPhone 的「健康」App 中授权所有必要的读取权限（特别是心率、HRV 和睡眠）。\n2. 在 Apple Watch 的表盘上添加 眠屿 小组件，以便随时查看您的压力状态。\n3. 在本应用的设置中开启「压力通知」，当检测到您压力过高时，我们会及时提醒您深呼吸。")
        case "如何提高测量准确度？":
            return String(localized: "为了获得更稳定的压力、HRV 和生命体征参考结果，请优先做好这几件事：\n1. 确保表带贴合手腕，不要过松或过紧；过松会让光学信号漂移，过紧也可能影响舒适度和局部循环。\n2. 保持传感器区域清洁，尽量避免汗液、护肤品残留或表底污渍影响采样质量。\n3. 在进行静息心率、HRV 或类似恢复类测量时，尽量保持静止 1-2 分钟，避免边走边看、刚运动完立刻解读。\n4. 手冷、环境太冷、刚洗完手或运动后，信号质量和生理状态都可能暂时不稳定，这时更适合稍等片刻再看结果。\n5. 开启全天候心率监测并保持连续佩戴，让系统有更完整的上下文，而不是只依赖单次样本。\n\n如果你看到某次结果突然异常，不要只盯那一次。先回看是否刚运动完、情绪起伏较大、佩戴变松，或者最近睡眠明显不足。把这些因素排除后，再结合连续几天趋势去理解，会比单点判断更可靠。")
        case "非 Apple Watch 如何同步到健康？":
            return String(localized: "如果你使用的是华为手表或其他第三方手表，通常要先在厂商自己的健康/运动 App 里完成配对、登录和同步，再检查 iPhone 的「健康」App 是否已获得读写权限。\n\n以华为手表为例，可先安装并打开华为运动健康，登录华为帐号，按 App 指引添加设备并完成配对；之后再确认 iPhone 健康权限已打开，数据才更容易进入系统健康链路。")
        case "月经周期是如何计算的":
            return String(localized: "月经周期通常是从本次月经来潮的第一天开始，计算到下一次月经来潮前一天结束。也就是说，真正被拿来计数的不是“出血持续了几天”，而是两次月经开始之间相隔了多少天。\n\n例如，如果这次月经在 5 月 1 日开始，下次月经在 5 月 29 日开始，那么这次周期长度就是 28 天。很多人并不是每次都完全一样，前后差几天都很常见，因此更适合看最近几个月的平均节律，而不是只抓住某一次结果。\n\n在 眠屿 里，周期趋势更适合拿来帮助理解自己的节律变化。数字本身不是对错判断，关键是看你最近记录是否连续、有没有逐渐形成比较稳定的模式。")
        case "排卵期与易孕期有什么区别":
            return String(localized: "排卵日更像一个时间点，表示卵子释放的那一天；易孕期则是一段窗口，通常覆盖排卵日前后几天。因为精子和卵子在体内都有一定存活时间，所以真正可能受孕的并不只有排卵当天。\n\n换句话说，排卵日是“最核心的那一天”，而易孕期是“前后都需要留意的一段时间”。如果只盯着排卵日，往往会低估整个窗口；如果把它放到易孕期里理解，就更容易看懂为什么系统会用一段区间来提示风险或机会。\n\n这类提示更适合作为健康管理和节律观察参考，而不是绝对结论。真实周期会受睡眠、压力、旅行、体重变化和记录完整度影响，所以最好结合连续记录一起看。")
        case "经期症状波动大正常吗":
            return String(localized: "经期相关症状出现波动其实并不少见。出血量、腹痛、腰酸、疲劳感和情绪变化，都会受到睡眠、压力、饮食、运动量以及当次周期阶段变化的影响，所以同一个人在不同月份的体验也可能差别很大。\n\n如果只是短期轻中度波动，通常更像身体状态和节律变化的反映，不一定代表异常。真正更值得重视的是：波动是否持续变重、是否明显影响日常生活，或者是否伴随和平时完全不同的异常出血、剧烈疼痛等情况。\n\n对大多数人来说，更有价值的做法不是纠结某一天为什么更难受，而是连续记录几个月，看看哪些症状会反复出现、哪些生活状态容易让它加重。这样比只记住某一次不舒服，更能帮助你形成自己的周期规律判断。")
        case "经期推迟几天常见吗":
            return String(localized: "经期前后浮动几天其实并不少见。睡眠不足、压力变化、旅行、饮食波动、近期运动强度变化，甚至体重起伏，都可能让当月周期比平时提前或延后几天。\n\n如果只是偶尔一次，而且之后很快恢复到原本节律，通常更像短期状态变化，不一定代表异常。真正更值得关注的是：推迟是否反复出现、延迟时间是否越来越长，或者是否伴随明显不适、异常出血等情况。\n\n更实用的做法是先看最近几个月的整体规律，而不是只盯住某一次延迟。只要趋势大体稳定，前后少量浮动通常都还在常见范围内。")
        case "痛经什么时候该就医":
            return String(localized: "如果痛经只是轻中度不适，而且通过休息、热敷或常规止痛方式能够缓解，很多时候可以先继续观察和记录。但如果疼痛明显加重、每个月都严重影响工作学习和睡眠，或者需要频繁依赖止痛药，通常就值得进一步评估。\n\n另外，如果同时出现异常大量出血、经期明显延长、平时没有的剧烈腹痛、发热、晕厥，或者疼痛模式和过去完全不同，也建议尽快就医。因为这类情况可能不仅仅是普通经期不适，还需要排查其他妇科问题。\n\n最有帮助的准备方式，是把近几个月的出血量、痛经程度、持续时长和伴随症状先记录下来。这样在就医时，比只说“最近很痛”更容易帮助医生判断。")
        default:
            return String(localized: "如果您遇到其他问题，请随时通过「联系我们」与我们的客服团队取得联系，我们会尽快为您解答。")
        }
    }

    private var answerSections: [String] {
        answer
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var relatedQuestions: [RelatedQuestion] {
        let pool: [String]
        switch normalizedQuestion {
        case "手表无法收到压力通知", "表盘不会自动更新", "Watch与iPhone同步失败", "新Watch用户必读", "非 Apple Watch 如何同步到健康？":
            pool = [
                "手表无法收到压力通知",
                "表盘不会自动更新",
                "Watch与iPhone同步失败",
                "新Watch用户必读",
                "非 Apple Watch 如何同步到健康？"
            ]
        case "压力与HRV基础科普", "压力监测频率相关", "如何提高测量准确度？", "推算血压靠谱吗？":
            pool = [
                "压力与HRV基础科普",
                "压力监测频率相关",
                "如何提高测量准确度？",
                "推算血压靠谱吗？"
            ]
        case "身体年龄和实际年龄有什么区别", "为什么身体年龄更适合按周看", "哪些指标最影响身体年龄", "身体年龄偏高是不是就代表身体变差了", "身体年龄为什么会突然波动", "样本不足时怎么理解身体年龄":
            pool = [
                "身体年龄和实际年龄有什么区别？",
                "为什么身体年龄更适合按周看？",
                "哪些指标最影响身体年龄？",
                "身体年龄偏高是不是就代表身体变差了？",
                "身体年龄为什么会突然波动？",
                "样本不足时怎么理解身体年龄？"
            ]
        case "心肺耐力为什么更适合按周看", "心肺耐力低是不是代表身体不好", "怎样更容易拿到新的心肺耐力估算":
            pool = [
                "心肺耐力为什么更适合按周看？",
                "心肺耐力低是不是代表身体不好？",
                "怎样更容易拿到新的心肺耐力估算？"
            ]
        case "月经周期是如何计算的", "排卵期与易孕期有什么区别", "经期症状波动大正常吗", "经期推迟几天常见吗", "痛经什么时候该就医":
            pool = [
                "月经周期是如何计算的？",
                "排卵期与易孕期有什么区别？",
                "经期症状波动大正常吗？",
                "经期推迟几天常见吗？",
                "痛经什么时候该就医？"
            ]
        default:
            pool = []
        }

        return pool
            .filter { normalizedQuestion != $0 && normalizedQuestion != $0.replacingOccurrences(of: "？", with: "") }
            .prefix(3)
            .map { RelatedQuestion(question: $0, hint: relatedHint(for: $0)) }
    }

    private var presentation: FAQPresentation {
        switch normalizedQuestion {
        case "身体年龄和实际年龄有什么区别":
            return FAQPresentation(
                category: String(localized: "身体年龄基础"),
                summary: String(localized: "实际年龄是日历时间，身体年龄更像近期身体状态的阶段评分，两者不需要完全一致。"),
                highlights: [String(localized: "它反映的是近期状态"), String(localized: "同龄人之间也可能不同"), String(localized: "偏高时先找原因而不是先焦虑")],
                useCase: String(localized: "适合第一次看到身体年龄，或者不理解为什么它和身份证年龄不完全一致时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先把它当作健康线索，再回看最近睡眠、活动和恢复有没有变化。"),
                tint: Color(hex: "4C7DFF")
            )
        case "为什么身体年龄更适合按周看":
            return FAQPresentation(
                category: String(localized: "趋势阅读"),
                summary: String(localized: "身体年龄受最近几天状态影响，按周看更容易区分短期波动和持续走高。"),
                highlights: [String(localized: "单日波动不等于长期变差"), String(localized: "连续几天偏高才更值得重视"), String(localized: "方向比某一天的数字更重要")],
                useCase: String(localized: "适合看到某一天身体年龄突然变化，想知道要不要立刻解读时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先回看最近一周的方向，再决定要不要放大某一天的数字。"),
                tint: Color(hex: "F3A53B")
            )
        case "哪些指标最影响身体年龄":
            return FAQPresentation(
                category: String(localized: "关键指标"),
                summary: String(localized: "睡眠、活动量、心肺能力和静息恢复状态，是最容易带动身体年龄变化的几类线索。"),
                highlights: [String(localized: "睡眠决定恢复底盘"), String(localized: "活动量影响基础状态"), String(localized: "心肺和恢复决定是否在透支")],
                useCase: String(localized: "适合看到身体年龄变化后，想知道应该优先回看哪些健康指标时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先看睡眠、步数、最大摄氧量、静息心率和 HRV 有没有一起变差。"),
                tint: Color(hex: "F46B5A")
            )
        case "身体年龄偏高是不是就代表身体变差了":
            return FAQPresentation(
                category: String(localized: "结果解读"),
                summary: String(localized: "偏高更像提醒，不等于立刻出现问题；关键是看它是不是持续偏高，而不是只看一次结果。"),
                highlights: [String(localized: "偏高不等于马上变差"), String(localized: "短期波动很常见"), String(localized: "连续偏高才更值得回看原因")],
                useCase: String(localized: "适合看到身体年龄比实际年龄高一些，担心是不是身体马上出问题时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先回看最近一周的睡眠、活动和恢复，再判断这个偏高是不是持续现象。"),
                tint: Color(hex: "7D8BFF")
            )
        case "身体年龄为什么会突然波动":
            return FAQPresentation(
                category: String(localized: "波动原因"),
                summary: String(localized: "睡眠、训练、压力和样本完整度都会影响短期结果，所以单日波动本身并不少见。"),
                highlights: [String(localized: "前一晚状态会影响结果"), String(localized: "训练和压力会带来短期偏移"), String(localized: "样本变少时也会更保守")],
                useCase: String(localized: "适合发现身体年龄某一天变化明显，想知道是异常还是常见波动时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先看接下来几天是否继续同方向变化，而不是只放大当天结果。"),
                tint: Theme.Colors.mintGreen
            )
        case "样本不足时怎么理解身体年龄":
            return FAQPresentation(
                category: String(localized: "数据覆盖"),
                summary: String(localized: "样本不足时，身体年龄更适合当作保守估计；先补齐记录，再看趋势更可靠。"),
                highlights: [String(localized: "样本少时结果更保守"), String(localized: "先补睡眠和活动记录"), String(localized: "趋势比单次数字更重要")],
                useCase: String(localized: "适合页面里显示等待数据、覆盖率偏低，或近期健康记录明显不完整时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先连续记录几天睡眠、步数和恢复数据，再回来读身体年龄。"),
                tint: Color(hex: "5F6F86")
            )
        case "心肺耐力为什么更适合按周看":
            return FAQPresentation(
                category: String(localized: "趋势阅读"),
                summary: String(localized: "心肺耐力是慢变化指标，更新节奏本来就偏慢，按周看更容易读出真实方向，而不是被单次波动带偏。"),
                highlights: [String(localized: "VO2 Max 不适合日内追踪"), String(localized: "单次波动不等于体能突然变化"), String(localized: "连续几周更能说明趋势"), String(localized: "结合恢复与活动一起读更稳妥")],
                useCase: String(localized: "适合看到某次心肺耐力变化后，分不清该把它当作单次波动，还是该认真看长期趋势时查看。"),
                actionTitle: String(localized: "先这样读"),
                actionSummary: String(localized: "先把它放回最近几周的趋势里，再结合睡眠、恢复和活动变化判断这次波动值不值得放大。"),
                tint: Color(hex: "4C7DFF")
            )
        case "心肺耐力低是不是代表身体不好":
            return FAQPresentation(
                category: String(localized: "结果解读"),
                summary: String(localized: "心肺耐力偏低更像说明基础仍在建立，或者样本不足，不等于立刻说明身体不好，要结合活动量和恢复一起看。"),
                highlights: [String(localized: "偏低不等于立刻异常"), String(localized: "年龄与样本质量都会影响读数"), String(localized: "活动基础会直接影响表现"), String(localized: "持续改善比单次高低更重要")],
                useCase: String(localized: "适合看到当前 VO2 Max 偏低，担心是不是身体状态出了问题，或者误以为这个结果就代表健康很差时查看。"),
                actionTitle: String(localized: "先别急着下结论"),
                actionSummary: String(localized: "先看最近有没有规律有氧活动和完整记录，再观察几周后的整体方向有没有逐步改善。"),
                tint: Color(hex: "F46B5A")
            )
        case "怎样更容易拿到新的心肺耐力估算":
            return FAQPresentation(
                category: String(localized: "估算生成"),
                summary: String(localized: "连续、稳定的有氧样本，加上贴合佩戴和完整心率记录，更容易触发新的 VO2 Max 估算。"),
                highlights: [String(localized: "连续有氧比零散活动更有效"), String(localized: "佩戴贴合会影响采样质量"), String(localized: "没有有效样本时常常不会更新"), String(localized: "先补样本再等系统生成更有效")],
                useCase: String(localized: "适合发现心肺耐力很久没更新，或者明明有运动却迟迟没出现新估算，想知道该怎么补齐条件时查看。"),
                actionTitle: String(localized: "先补这几项条件"),
                actionSummary: String(localized: "先保证连续有氧样本、稳定佩戴和完整心率记录，再观察后续几天到几周是否出现新的估算。"),
                tint: Color(hex: "34C759")
            )
        case "手表无法收到压力通知":
            return FAQPresentation(
                category: String(localized: "通知"),
                summary: String(localized: "优先检查通知权限、连接状态和专注模式，绝大多数情况都能在这三处找到原因。"),
                highlights: [String(localized: "检查 Watch 通知权限"), String(localized: "确认未开启睡眠/勿扰"), String(localized: "必要时重启并重新授权")],
                useCase: String(localized: "适合已经打开提醒开关，但手表端仍完全没有收到压力提醒时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先确认 iPhone 和 Watch 的通知链路，再看专注模式和授权状态。"),
                tint: Theme.Colors.mintGreen
            )
        case "压力监测频率相关说明", "压力监测频率相关":
            return FAQPresentation(
                category: String(localized: "采样频率"),
                summary: String(localized: "压力不是按秒刷新，系统更偏向在静止和条件稳定时生成可用样本。"),
                highlights: [String(localized: "后台采样受系统策略影响"), String(localized: "静止时更容易出样本"), String(localized: "正念训练可主动触发一次")],
                useCase: String(localized: "适合想知道为什么今天压力更新偏少，或者样本不像心率那样连续时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先理解后台采样节奏，再用正念训练主动补一条高质量样本。"),
                tint: Color(hex: "6E84F7")
            )
        case "压力与HRV基础科普":
            return FAQPresentation(
                category: String(localized: "基础科普"),
                summary: String(localized: "HRV 更像恢复与调节能力的线索，眠屿 会把它和心率一起用于压力参考。"),
                highlights: [String(localized: "恢复好时 HRV 常更高"), String(localized: "疲劳压力会拉低 HRV"), String(localized: "结果仅用于日常管理参考")],
                useCase: String(localized: "适合第一次看见 HRV、压力评分，或者想知道两者关系时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先把它当作恢复线索，而不是单次结果的绝对判断。"),
                tint: Color(hex: "5E5CE6")
            )
        case "推算血压靠谱吗？":
            return FAQPresentation(
                category: String(localized: "生命体征边界"),
                summary: String(localized: "血压推算更适合当作风险提示或趋势线索，不适合替代标准血压测量。"),
                highlights: [String(localized: "会结合心率、HRV 和 PPG 等信号"), String(localized: "个体差异和佩戴状态都会放大误差"), String(localized: "更适合做高低风险提醒而非诊断")],
                useCase: String(localized: "适合看到可穿戴设备的推算血压、血压风险提示，想知道这类结果到底能不能当真时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先把它当作辅助提醒；如果连续异常或伴随不适，请用标准血压计复测并咨询医生。"),
                tint: Color(hex: "E86C5B")
            )
        case "Watch与iPhone同步失败":
            return FAQPresentation(
                category: String(localized: "同步"),
                summary: String(localized: "大多数同步问题都和连接状态、健康权限或 Watch 端前台刷新有关。"),
                highlights: [String(localized: "确认蓝牙连接正常"), String(localized: "检查健康读取权限"), String(localized: "必要时重开 Watch 端 App")],
                useCase: String(localized: "适合数据长时间没同步到 iPhone，或者今日页、趋势页明显滞后时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先排查连接和权限，再触发一次 Watch 端手动同步。"),
                tint: Theme.Colors.accentBlue
            )
        case "表盘不会自动更新":
            return FAQPresentation(
                category: String(localized: "表盘组件"),
                summary: String(localized: "表盘刷新受系统资源策略约束，延迟刷新通常不代表数据丢失。"),
                highlights: [String(localized: "自动刷新并非实时"), String(localized: "进入 App 可触发同步"), String(localized: "长时间不更新再排查")],
                useCase: String(localized: "适合表盘数字长时间不变化，但 App 内数据正常更新时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先进入 App 触发一次同步，再观察后续刷新节奏是否恢复。"),
                tint: Color(hex: "7D8BFF")
            )
        case "新Watch用户必读":
            return FAQPresentation(
                category: String(localized: "新手上手"),
                summary: String(localized: "新用户最重要的是一次性把权限、表盘组件和提醒链路配置完整。"),
                highlights: [String(localized: "先授权心率、HRV、睡眠"), String(localized: "把组件加到表盘"), String(localized: "打开关键提醒")],
                useCase: String(localized: "适合第一次安装使用，或者刚换新手表后重新配置时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "把权限、组件和提醒三件事先配完，再开始看今日页和趋势页。"),
                tint: Color(hex: "FFB340")
            )
        case "如何提高测量准确度？":
            return FAQPresentation(
                category: String(localized: "测量准确度"),
                summary: String(localized: "佩戴贴合、传感器清洁和测量时保持静止，是影响准确度最直接的几个因素。"),
                highlights: [String(localized: "表带不要过松过紧"), String(localized: "保持传感器区域清洁"), String(localized: "测量时尽量静止 1-2 分钟")],
                useCase: String(localized: "适合发现心率、HRV 或压力波动异常大，怀疑佩戴和采样质量时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先保证佩戴贴合和静止测量，再去判断数据本身是否异常。"),
                tint: Color(hex: "FF9F0A")
            )
        case "非 Apple Watch 如何同步到健康？":
            return FAQPresentation(
                category: String(localized: "第三方设备"),
                summary: String(localized: "第三方手表要先在厂商自己的健康 App 里完成配对和同步，再把数据接入 iPhone 健康。"),
                highlights: [String(localized: "先在厂商 App 配对手表"), String(localized: "登录厂商帐号并完成同步"), String(localized: "打开 iPhone 健康权限")],
                useCase: String(localized: "适合使用华为手表或其他非 Apple Watch 设备，想把数据接入 iPhone 健康时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先按厂商 App 完成配对和授权，再检查 iPhone 健康里的读写权限。"),
                tint: Color(hex: "4C7DFF")
            )
        case "月经周期是如何计算的":
            return FAQPresentation(
                category: String(localized: "周期基础"),
                summary: String(localized: "月经周期是按两次月经开始之间的间隔来计算，更适合看连续几个月的节律，而不是只看一次。"),
                highlights: [String(localized: "从本次来潮第一天算起"), String(localized: "直到下一次来潮前一天结束"), String(localized: "平均节律比单次结果更重要")],
                useCase: String(localized: "适合刚开始记录周期，或者看到“周期长度”后不清楚这个数字到底怎么算出来时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先保证月经开始日期记录连续，再结合最近几个月的平均节律去理解周期长度。"),
                tint: Color(hex: "C99690")
            )
        case "排卵期与易孕期有什么区别":
            return FAQPresentation(
                category: String(localized: "排卵与易孕"),
                summary: String(localized: "排卵日是一个时间点，易孕期是一段窗口；理解窗口比只盯住某一天更重要。"),
                highlights: [String(localized: "排卵日是核心时间点"), String(localized: "易孕期覆盖前后几天"), String(localized: "窗口阅读比单点阅读更贴近真实情况")],
                useCase: String(localized: "适合看到排卵提示和易孕窗口同时出现，却分不清它们代表什么时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先把排卵日放进整个易孕窗口里理解，再结合连续记录判断自己的节律。"),
                tint: Color(hex: "8CA6E8")
            )
        case "经期症状波动大正常吗":
            return FAQPresentation(
                category: String(localized: "症状波动"),
                summary: String(localized: "经期症状轻重波动很常见，重点是看它是否持续加重，或者是否明显影响日常生活。"),
                highlights: [String(localized: "睡眠和压力都会影响症状"), String(localized: "不同月份体验不一定一样"), String(localized: "持续异常比单次波动更值得重视")],
                useCase: String(localized: "适合发现本月腹痛、情绪或出血和上次差别较大，担心是不是不正常时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先连续记录几个月的症状变化，再观察哪些生活状态最容易让它加重。"),
                tint: Color(hex: "B28FA1")
            )
        case "经期推迟几天常见吗":
            return FAQPresentation(
                category: String(localized: "周期波动"),
                summary: String(localized: "经期前后浮动几天很常见，重点是看它是偶发变化，还是已经开始持续偏离原本节律。"),
                highlights: [String(localized: "短期延迟不一定异常"), String(localized: "压力和作息都会影响周期"), String(localized: "持续偏离才更值得重视")],
                useCase: String(localized: "适合发现本月月经比平时晚几天，担心是不是出问题时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先回看最近几个月整体节律，再判断这次延迟是偶发还是开始持续变化。"),
                tint: Color(hex: "D7A8A1")
            )
        case "痛经什么时候该就医":
            return FAQPresentation(
                category: String(localized: "就医判断"),
                summary: String(localized: "如果痛经持续加重、明显影响生活，或伴随异常出血和剧烈不适，就不建议只靠自行观察。"),
                highlights: [String(localized: "影响生活时要提高重视"), String(localized: "异常出血和剧痛要尽快评估"), String(localized: "提前整理记录会更有帮助")],
                useCase: String(localized: "适合不确定自己的痛经是常见波动，还是已经到了需要专业帮助的时候查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先记录近几个月痛经程度、持续时长和伴随症状，再尽快做专业评估。"),
                tint: Color(hex: "C39AB0")
            )
        default:
            return FAQPresentation(
                category: String(localized: "帮助"),
                summary: String(localized: "如果这条说明没有覆盖你的问题，建议继续联系我们获取更具体的排查帮助。"),
                highlights: [String(localized: "先看核心说明"), String(localized: "再看补充建议"), String(localized: "仍未解决可继续反馈")],
                useCase: String(localized: "适合遇到不在当前 FAQ 列表里的其他问题时查看。"),
                actionTitle: String(localized: "建议先做"),
                actionSummary: String(localized: "先记录现象和已尝试步骤，再进入帮助与反馈继续排查。"),
                tint: Theme.Colors.mintGreen
            )
        }
    }
    
    var body: some View {
        ZStack {
            Theme.Colors.pageBackground
                .ignoresSafeArea()

            AdaptivePageScrollView(style: .reading, topPadding: Theme.Spacing.small, bottomPadding: 88) {
                VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                    heroCard
                    quickSummaryCard
                    useCaseCard
                    quickActionCard

                    ForEach(Array(answerSections.enumerated()), id: \.offset) { index, section in
                        SettingsSectionCard(title: index == 0 ? "核心说明" : "补充建议") {
                            sectionBody(section)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }
                    }

                    SettingsSectionCard(title: "进一步排查") {
                        SettingsStatusSummaryRow(
                            icon: "bubble.left.and.exclamationmark.bubble.right.fill",
                            tint: presentation.tint,
                            title: "问题仍未解决",
                            subtitle: "记录现象、设备状态和已经尝试过的步骤，方便继续排查",
                            status: "继续检查"
                        )
                    }

                    if !relatedQuestions.isEmpty {
                        relatedQuestionsCard
                    }
                }
            }
            .readingNavigationBarMinimization()
        }
        .navigationTitle("问题详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var heroCard: some View {
        SettingsSectionCard(title: presentation.category) {
            SettingsStatusSummaryRow(
                icon: "questionmark.bubble.fill",
                tint: presentation.tint,
                title: normalizedQuestion,
                subtitle: presentation.summary,
                status: applicableSurfaceText
            )
        }
    }

    private var useCaseCard: some View {
        SettingsSectionCard(title: "适用场景") {
            Text(presentation.useCase)
                .font(Theme.Typography.scaled(size: 15, weight: .medium, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var quickActionCard: some View {
        SettingsSectionCard(title: presentation.actionTitle) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(presentation.tint.opacity(0.12))
                    Image(systemName: "wand.and.stars")
                        .font(.appSystem(size: 17, weight: .bold))
                        .foregroundColor(presentation.tint)
                }
                .frame(width: 38, height: 38)

                Text(presentation.actionSummary)
                    .font(Theme.Typography.scaled(size: 15, weight: .medium, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var quickSummaryCard: some View {
        SettingsSectionCard(title: "三个要点") {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                ForEach(presentation.highlights, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(presentation.tint.opacity(0.16))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.appSystem(size: 11, weight: .bold))
                                    .foregroundColor(presentation.tint)
                            )

                        Text(item)
                            .font(Theme.Typography.scaled(size: 15, weight: .medium, design: .rounded, level: appFontScaleLevel))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var relatedQuestionsCard: some View {
        SettingsSectionCard(title: "相关推荐 · \(relatedQuestions.count) 条") {
            VStack(spacing: 0) {
                ForEach(Array(relatedQuestions.enumerated()), id: \.offset) { index, item in
                    NavigationLink(destination: FAQDetailView(question: item.question)) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(presentation.tint.opacity(0.12))
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.appSystem(size: 14, weight: .bold))
                                    .foregroundColor(presentation.tint)
                            }
                            .frame(width: 38, height: 38)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.question)
                                    .font(Theme.Typography.scaled(size: 15, weight: .semibold, design: .rounded, level: appFontScaleLevel))
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.hint)
                                    .font(Theme.Typography.scaled(size: 13, weight: .medium, design: .rounded, level: appFontScaleLevel))
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: Theme.Icons.chevronRight)
                                .font(.appSystem(size: 13, weight: .semibold))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .padding(.vertical, 13)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)

                    if index != relatedQuestions.count - 1 {
                        Divider().padding(.leading, 48)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionBody(_ text: String) -> some View {
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if let bullet = numberedBulletText(from: line) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(bullet.index)
                            .font(Theme.Typography.scaled(size: 12, weight: .bold, design: .rounded, level: appFontScaleLevel))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .frame(width: 22, height: 22)
                            .background(Theme.Colors.secondaryBackground, in: Circle())

                        Text(bullet.content)
                            .font(Theme.Typography.scaled(size: 16, weight: .medium, design: .rounded, level: appFontScaleLevel))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(line)
                        .font(Theme.Typography.scaled(size: 16, weight: .medium, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func numberedBulletText(from line: String) -> (index: String, content: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let prefix = String(trimmed[..<dotIndex])
        guard Int(prefix) != nil else { return nil }
        let contentStart = trimmed.index(after: dotIndex)
        let content = String(trimmed[contentStart...]).trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : (prefix, content)
    }

    private var applicableSurfaceText: String {
        switch normalizedQuestion {
        case "身体年龄和实际年龄有什么区别", "为什么身体年龄更适合按周看", "哪些指标最影响身体年龄", "身体年龄偏高是不是就代表身体变差了", "身体年龄为什么会突然波动", "样本不足时怎么理解身体年龄":
            return String(localized: "身体年龄")
        case "Watch与iPhone同步失败", "表盘不会自动更新", "手表无法收到压力通知", "新Watch用户必读":
            return "Watch"
        case "压力与HRV基础科普", "压力监测频率相关", "如何提高测量准确度？", "推算血压靠谱吗？":
            return String(localized: "今日页")
        case "心肺耐力为什么更适合按周看", "心肺耐力低是不是代表身体不好", "怎样更容易拿到新的心肺耐力估算":
            return String(localized: "心肺耐力")
        case "非 Apple Watch 如何同步到健康？":
            return String(localized: "健康同步")
        case "月经周期是如何计算的", "排卵期与易孕期有什么区别", "经期症状波动大正常吗", "经期推迟几天常见吗", "痛经什么时候该就医":
            return String(localized: "生理周期")
        default:
            return String(localized: "通用")
        }
    }

    private func relatedHint(for question: String) -> String {
        switch question {
        case "手表无法收到压力通知":
            return String(localized: "先排查通知权限、连接状态和专注模式")
        case "表盘不会自动更新":
            return String(localized: "了解表盘组件刷新节奏和手动同步方式")
        case "Watch与iPhone同步失败":
            return String(localized: "继续看连接、蓝牙和权限链路")
        case "新Watch用户必读":
            return String(localized: "适合第一次上手或换新手表后重新配置")
        case "非 Apple Watch 如何同步到健康？":
            return String(localized: "第三方设备接入健康链路的步骤说明")
        case "压力与HRV基础科普":
            return String(localized: "先理解压力参考值和 HRV 的关系")
        case "压力监测频率相关":
            return String(localized: "为什么不是实时刷新，以及如何主动补样本")
        case "如何提高测量准确度？":
            return String(localized: "佩戴、清洁和静止状态都会影响结果")
        case "推算血压靠谱吗？":
            return String(localized: "看清推算血压的原理、误差来源和使用边界")
        case "身体年龄和实际年龄有什么区别？":
            return String(localized: "先理解这个结果到底在表达什么")
        case "为什么身体年龄更适合按周看？":
            return String(localized: "帮助判断该看单日还是长期方向")
        case "哪些指标最影响身体年龄？":
            return String(localized: "优先知道该回看哪些健康指标")
        case "身体年龄偏高是不是就代表身体变差了？":
            return String(localized: "偏高更像提醒，不代表立刻异常")
        case "身体年龄为什么会突然波动？":
            return String(localized: "睡眠、训练和样本变化都可能带来波动")
        case "样本不足时怎么理解身体年龄？":
            return String(localized: "样本缺失时更适合先补记录")
        case "心肺耐力为什么更适合按周看？":
            return String(localized: "VO2 Max 更适合按趋势理解")
        case "心肺耐力低是不是代表身体不好？":
            return String(localized: "当前偏低不等于立刻异常")
        case "怎样更容易拿到新的心肺耐力估算？":
            return String(localized: "看怎样补齐连续有氧样本和佩戴条件")
        case "月经周期是如何计算的？":
            return String(localized: "理解周期长度这个数字是怎么算出来的")
        case "排卵期与易孕期有什么区别？":
            return String(localized: "理解时间点和窗口的差别")
        case "经期症状波动大正常吗？":
            return String(localized: "判断波动是否常见以及何时该重视")
        case "经期推迟几天常见吗？":
            return String(localized: "先看最近几个月整体节律")
        case "痛经什么时候该就医？":
            return String(localized: "判断什么时候不该只靠自己观察")
        default:
            return String(localized: "查看这条相关问题的详细说明")
        }
    }
}

private extension View {
    func detailCardSurface(tint: Color? = nil) -> some View {
        self
            .padding(20)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.96), tint?.opacity(0.05) ?? Color.white.opacity(0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 12, x: 0, y: 7)
    }
}

/// 常见问题预览提供器 作为帮助支持模块里的预览辅助类型。
/// 负责帮助支持与 FAQ 展示。
struct FAQDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FAQDetailView(question: "手表无法收到压力通知？")
        }
    }
}
