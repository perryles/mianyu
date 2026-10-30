/// PrivacyPolicyView 由设置页与登录页调用，作为「隐私政策」法律说明页。
/// 负责分段展示数据采集范围、HealthKit 授权、云端存储等隐私合规说明。

import SwiftUI

/// 隐私政策视图 由上级页面或路由调用，作为法律说明模块里的界面或内容组件。
/// 负责展示隐私政策、服务条款等合规内容。
struct PrivacyPolicyView: View {
    private let sections: [LegalDocumentSection] = [
        LegalDocumentSection(
            title: String(localized: "1. 适用范围"),
            body: String(localized: "本政策用于说明 眠屿 在你使用应用、账号能力、AI 健康助手、好友共享与协作功能时，如何处理与你相关的信息。不同功能依赖的数据类型和存储位置可能不同，我们会尽量按“本地优先、最少必要”的原则处理。"),
            icon: "scope",
            tone: .mint,
            highlights: [
                String(localized: "你授予后，应用才会读取 Apple Health / HealthKit 中的对应健康数据。"),
                String(localized: "你主动输入、上传、分享或发起 AI 提问时，相关内容才会进入对应功能流程。"),
                String(localized: "部分功能依赖 Apple、iCloud、CloudKit、天气或应用后端等第三方/云端能力。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "2. 我们可能收集的信息"),
            body: String(localized: "根据你使用的功能不同，我们可能处理以下几类信息：设备与账号标识、你主动填写的资料、健康摘要、习惯记录、订阅状态，以及为完成特定功能所需的位置或协作数据。"),
            icon: "tray.full.fill",
            tone: .blue,
            highlights: [
                String(localized: "健康相关数据可能包括心率、HRV、静息心率、睡眠、步数、活动能量、运动时间、站立时长、呼吸频率、正念分钟、饮水、咖啡因、日照时间、体温、步态与情绪/状态，以及你主动填写或确认的处方、药物、病症、孕期与胎动资料。"),
                String(localized: "账号与服务数据可能包括登录凭证、Apple 登录身份标识、会员状态、购买记录状态、故障日志与必要的接口访问记录。"),
                String(localized: "在日照、天气或好友共享等场景下，可能会处理当前位置、地点名称或你主动确认共享的粗略位置摘要。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "3. HealthKit 与设备权限"),
            body: String(localized: "大部分健康分析基于 Apple Health / HealthKit。你可以拒绝授权，也可以随时在 iPhone 系统设置或 Health App 中调整读写权限。未授权时，相关页面可能只显示引导、空状态或降级后的功能。"),
            icon: "heart.text.square.fill",
            tone: .green,
            highlights: [
                String(localized: "眠屿 不会因为你安装应用就自动获得全部健康数据访问权。"),
                String(localized: "呼吸训练、正念等功能仅会在你主动记录时写入对应的正念分钟或相关结果。"),
                String(localized: "部分设备、模拟器或系统版本不支持某些 HealthKit 能力，对应功能可能不可用。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "4. 我们如何使用这些信息"),
            body: String(localized: "这些信息主要用于在应用内生成健康摘要、趋势图、恢复建议、习惯追踪、提醒、协作内容和会员能力判断，也用于保障账号安全、排查故障和提升产品稳定性。"),
            icon: "wand.and.stars",
            tone: .blue,
            highlights: [
                String(localized: "用于展示今日状态、睡眠/压力/活动趋势、行为建议和阶段性报告。"),
                String(localized: "用于同步你主动开启的好友共享摘要、共享待办、倒数日与行动记录。"),
                String(localized: "用于处理登录、恢复购买、账号删除、错误恢复和服务可用性检测。")
            ],
            footnote: String(localized: "我们不会把你的健康数据用于与健康管理无关的广告跟踪。")
        ),
        LegalDocumentSection(
            title: String(localized: "5. AI 健康助手"),
            body: String(localized: "当你使用 AI 健康助手、处方识别或相关 AI 分析能力时，你输入的问题，以及完成当前操作所需的健康摘要、上下文或处方文字，可能会被发送到云端 AI 服务或应用后端进行处理。"),
            icon: "sparkles",
            tone: .orange,
            highlights: [
                String(localized: "发送的数据通常是回答当前问题所需的摘要，而不是完整 Health 原始数据库。"),
                String(localized: "处方图片先在设备端提取文字；原图不发送给处方结构化服务，常见身份字段会在发送文字前移除，但你仍应在继续前确认图片不包含不希望云端处理的信息。"),
                String(localized: "药物、剂量、用法和病症识别结果必须由你逐项确认后才会保存，应用不会根据识别结果自动开启服药提醒。"),
                String(localized: "AI 输出仅供一般健康管理参考，不构成医疗诊断、治疗或急救建议。"),
                String(localized: "请不要在 AI 对话中提交你不希望被云端处理的敏感信息。")
            ],
            footnote: String(localized: "当前代码中已存在直连 AI 服务与后端路由能力，因此本条款按实际功能口径说明。")
        ),
        LegalDocumentSection(
            title: String(localized: "6. 好友共享、iCloud 与协作"),
            body: String(localized: "如果你主动开启好友共享，我们会通过 iCloud / CloudKit 共享最近一段时间的健康摘要、行动记录、倒数日、待办摘要，以及你通过独立开关确认共享的粗略位置摘要。位置共享默认关闭；系统定位授权不会自动开启好友位置共享。只有被你邀请并接受的人，才可以查看对应内容。"),
            icon: "person.2.fill",
            tone: .mint,
            highlights: [
                String(localized: "共享的是摘要或协作内容，不是完整的 Health 原始记录、实时定位或完整历史轨迹。"),
                String(localized: "当前好友分享中的健康摘要和共享待办对受邀者均为只读；应用不会为了待办编辑而放宽整份健康 share 的权限。"),
                String(localized: "你可以随时停止未来共享；停止后应用会尽快隐藏并清理本地缓存，但无法撤回对方此前已看见、导出或截图保存的内容。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "7. 数据存储与安全"),
            body: String(localized: "我们会结合本地存储、App Group、iCloud / CloudKit 与必要的服务端接口来支撑不同能力，并采取合理的技术和管理措施降低未经授权访问、泄露、篡改或丢失的风险。"),
            icon: "lock.shield.fill",
            tone: .green,
            highlights: [
                String(localized: "许多健康展示能力以本地处理和本地缓存为主。"),
                String(localized: "App Group 只用于同一设备上的 App、Widget 或 Complication 读取最小展示快照，不用于跨设备云同步。"),
                String(localized: "孕期设置、孕期体重与胎动时间仅写入当前 Apple ID 的 CloudKit 私有数据库，不写入 眠屿 自有后台；未完成同步的表单内容不会作为成功记录保留。"),
                String(localized: "iCloud 餐饮记录与睡眠摘要同步默认关闭；药症资料同步默认开启，只上传你确认过的结构化处方、药物和病症，不上传处方原图、OCR 全文、患者身份或 AI 服务元数据。你可以随时关闭药症同步。"),
                String(localized: "账号、购买状态、AI 请求、共享协作等功能可能涉及网络传输或云端处理。"),
                String(localized: "任何联网或存储系统都无法承诺绝对安全，但我们会持续改进。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "8. 你的选择与控制"),
            body: String(localized: "你可以通过系统设置、Health 权限、定位权限、iCloud 设置、应用内账号与订阅入口来控制数据处理范围，也可以根据功能可用性申请删除账号或停止使用服务。"),
            icon: "slider.horizontal.3",
            tone: .blue,
            highlights: [
                String(localized: "你可以关闭 HealthKit、定位、通知或共享权限。"),
                String(localized: "你可以分别关闭 iCloud 餐饮记录、睡眠摘要和药症资料同步；关闭只停止未来上传，不会自动删除此前已保存到当前 Apple ID 私有数据库的记录。"),
                String(localized: "你可以在 App Store 订阅设置中管理自动续订项目，并使用“恢复购买”同步状态。"),
                String(localized: "如应用提供账号删除入口或客服支持通道，你可以申请删除账号；但法律法规要求保留或无法技术上立即清除的内容除外。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "9. 数据保留与删除"),
            body: String(localized: "我们仅在实现功能目的、法律法规要求或保障安全所必需的期限内保留你的数据。不同类型数据的保留期不同：本地缓存由你控制；iCloud 数据随你删除账号或关闭同步后清理；必要的运维日志（不含健康内容）通常保留不超过 90 天。"),
            icon: "clock.arrow.circlepath",
            tone: .blue,
            highlights: [
                String(localized: "本地数据在你删除应用时随之清除（设备本地缓存同理）。"),
                String(localized: "iCloud 同步数据在你关闭对应同步开关后，应用会尽快清理本地缓存；云端已存储的记录需通过删除账号或在 iCloud 设置中手动清理。"),
                String(localized: "账号删除请求一旦完成，应用将在合理时间内删除与你关联的可删除数据；法律法规要求保留的除外。"),
                String(localized: "为保证安全与合规，运维日志（仅含 operation、zone、record type、稳定技术 ID、错误码与耗时）可能保留更长时间，但绝不包含健康数值、文本内容或个人身份信息。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "10. 你的隐私权利"),
            body: String(localized: "根据你所在地区的法律（如 GDPR、CCPA、PIPL 等），你可能享有以下权利。我们会尽力在合理时间内响应你的请求。"),
            icon: "person.badge.shield.checkmark",
            tone: .green,
            highlights: [
                String(localized: "知情权：你可以通过本政策了解我们处理哪些数据、为何处理以及如何保护。"),
                String(localized: "访问与携带权：你可以请求获取与你相关的数据副本（iCloud 健康数据可通过系统功能导出）。"),
                String(localized: "更正权：你可以在应用内修改个人资料，或请求更正不准确的信息。"),
                String(localized: "删除权：你可以删除应用内的特定记录，也可以申请删除账号及关联数据。"),
                String(localized: "撤回同意权：你可以在系统设置或应用内随时撤回 HealthKit、定位、通知、iCloud 同步等授权。"),
                String(localized: "反对权：对于直接营销或分析目的的数据处理，你有权提出反对。")
            ],
            footnote: String(localized: "行使上述权利可通过应用内反馈渠道或 support@boundesu.com 提出。某些例外情形下（如法律义务），我们可能无法完全满足删除或限制请求。")
        ),
        LegalDocumentSection(
            title: String(localized: "11. 跨境数据传输"),
            body: String(localized: "为提供 AI 问答、天气、订阅验证等功能，你的部分数据可能被传输至中国境外（如美国、新加坡等）的云端服务进行处理。此类传输仅在对应功能需要时发生，且我们会确保接收方提供不低于本政策所承诺的保护标准。"),
            icon: "globe.asia.australia.fill",
            tone: .orange,
            highlights: [
                String(localized: "涉及跨境传输的主要场景：AI 对话摘要发送至云端 AI 服务、天气数据请求、Apple 推送通知服务。"),
                String(localized: "跨境传输的数据均为功能所需的最小摘要或标识，不包括完整的 HealthKit 原始记录。"),
                String(localized: "如你所在地区法律对跨境传输有特殊要求，我们将在可行范围内遵守。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "12. 数据安全事件"),
            body: String(localized: "若发生可能导致你的个人信息泄露、篡改或丢失的安全事件，我们将在确认后及时启动应急响应，并在法律法规要求的时限内通知你（通过应用内通知、推送或邮件等方式）。"),
            icon: "exclamationmark.shield.fill",
            tone: .red,
            highlights: [
                String(localized: "通知内容通常包括事件性质、涉及数据范围、已采取及将采取的应对措施，以及你可以采取的自我保护建议。"),
                String(localized: "你可通过应用内反馈或 support@boundesu.com 获取更多帮助。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "13. 分析与崩溃报告"),
            body: String(localized: "为提升产品稳定性和用户体验，我们可能收集匿名化的崩溃报告和性能分析数据。这些数据不包含你的健康数值、个人输入文本、账号密码或可精确识别你身份的信息。"),
            icon: "chart.bar.fill",
            tone: .mint,
            highlights: [
                String(localized: "崩溃报告仅包含崩溃类型、堆栈摘要、设备型号、系统版本和应用版本等技术信息。"),
                String(localized: "性能分析用于监控启动时间、页面响应速度等功能指标。"),
                String(localized: "你可以在应用隐私设置中关闭共享分析数据；关闭后不会影响应用功能。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "14. 儿童隐私、政策更新与联系方式"),
            body: String(localized: "本应用主要面向一般成年人及在监护人指导下使用的未成年人。我们不主动收集 13 岁以下儿童的个人信息。如发现误收集，我们将尽快删除。我们可能根据产品能力、法律法规或合规要求更新本政策，更新后会在应用内展示最新版本。"),
            icon: "envelope.fill",
            tone: .gray,
            highlights: [
                String(localized: "如果你是未成年人，请在监护人同意和指导下使用本应用。"),
                String(localized: "继续使用更新后的服务，通常意味着你理解并接受新的政策内容。"),
                String(localized: "如果你对本政策或数据处理方式有疑问，请通过以下方式联系我们。")
            ],
            footnote: String(localized: "联系我们：\nEmail：support@boundesu.com\n应用内：设置 → 帮助与反馈")
        )
    ]

    private let updatedSections: [LegalDocumentSection] = [
        LegalDocumentSection(
            title: String(localized: "我们会处理哪些信息"),
            body: String(localized: "为了提供健康与记录功能，应用可能处理以下信息："),
            highlights: [
                String(localized: "健康数据：在你授权后读取 HealthKit 中的睡眠、活动、心率、HRV、呼吸、血氧等数据。"),
                String(localized: "你主动记录的信息：体重、饮水、餐食、情绪、压力、习惯与目标等。"),
                String(localized: "账号与订阅信息：用于登录、同步、恢复购买和账户管理。"),
                String(localized: "AI 提问内容：仅在你主动使用 AI 功能时处理。"),
                String(localized: "好友共享内容：仅在你主动开启共享后向指定好友展示。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "我们如何使用这些信息"),
            body: String(localized: "我们仅将信息用于提供你主动使用的功能，包括健康趋势分析、睡眠与压力展示、目标与习惯记录、餐食识别、AI 总结、好友共享、设备间同步和订阅管理。除非获得你的额外授权，我们不会将健康数据用于广告画像。")
        ),
        LegalDocumentSection(
            title: String(localized: "本地存储、iCloud 与云端处理"),
            body: String(localized: "应用优先在设备本地处理和保存数据。需要跨设备同步时，部分记录可通过你的 iCloud 账户同步。孕期等敏感记录默认存入你的私人 iCloud，并可在设置中关闭。使用 AI、餐食识别等功能时，相关请求可能发送至云端服务进行临时处理；页面应明确提示此类处理。")
        ),
        LegalDocumentSection(
            title: String(localized: "授权与控制权"),
            body: String(localized: "HealthKit、通知、相册、相机、好友共享等权限均由你主动授权。你可以在系统设置或应用设置中撤回授权。撤回后，对应功能可能无法继续使用，但不会影响其他不依赖该权限的功能。")
        ),
        LegalDocumentSection(
            title: String(localized: "好友共享与第三方服务"),
            body: String(localized: "好友共享默认关闭，仅在你主动开启后生效。你可以随时调整共享对象与共享内容。订阅由 App Store 处理，相关支付与结算遵循 Apple 的规则；第三方服务仅在完成功能所必需的范围内处理数据。")
        ),
        LegalDocumentSection(
            title: String(localized: "数据保留、删除与撤回"),
            body: String(localized: "你可以随时关闭云同步、撤回权限、停止好友共享，或申请删除账户。账户删除后，我们会按产品能力清除或停止处理相关账户数据；已保存在你私人 iCloud 中的数据需由你在对应系统设置中管理。")
        ),
        LegalDocumentSection(
            title: String(localized: "你的隐私权利"),
            body: String(localized: "你可以查看、修改和删除你主动记录的数据；撤回授权；管理订阅；关闭匿名分析报告；申请删除账户；以及在设置中管理数据与权限。")
        )
    ]

    var body: some View {
        LegalDocumentView(
            title: String(localized: "隐私政策"),
            subtitle: String(localized: "健康数据默认在本地处理，我们仅收集实现功能所需的信息。"),
            updatedAt: String(localized: "最后更新时间：2026-08-03"),
            intro: String(localized: "本政策说明 眠屿 如何在健康分析、账号能力、AI 问答、好友共享与订阅相关流程中收集、使用、存储和保护你的信息，以及你所享有的隐私权利。"),
            icon: "hand.raised.fill",
            keyPoints: [
                String(localized: "HealthKit 授权可随时撤回"),
                String(localized: "孕期记录仅存私人 iCloud"),
                String(localized: "AI 提问可能触发云端处理")
            ],
            sections: updatedSections,
            sectionHeading: String(localized: "完整政策"),
            sectionCaption: String(localized: "以下内容为页面正式正文"),
            closingTitle: String(localized: "隐私控制始终属于你"),
            closingDetail: String(localized: "如产品功能发生变化，政策内容也会同步更新。")
        )
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
