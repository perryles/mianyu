/// Deep Link Store 负责应用内的共享核心能力，用于处理深链、登录、订阅、评估结果或购买流程等基础服务。
import Foundation
import SwiftUI

/// 应用深度链接枚举 作为核心能力层里的能力或分类定义。
/// 负责描述核心业务服务与应用基础能力过程中会用到的状态、分类或分支。
enum MianyuDeepLink: Equatable {
    /// Widget 枚举，作为内部辅助类型，用于细分外层核心业务服务与应用基础能力中的状态或分支。
    enum Widget: String, Equatable {
        case overall
        case vitals
        case stress
        case activity
        case sleep
        case sunlight
    }

    case home
    
    case widget(Widget)
    case watchDashboard
    /// Live Activity 点击跳转，携带提醒标识符
    case reminder(identifier: String?)
    
    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "biobalance" else { return nil }
        
        let host = url.host?.lowercased() ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()

        if host == "home", path.isEmpty {
            self = .home
            return
        }
        
        if host == "widget", let widget = Widget(rawValue: path) {
            self = .widget(widget)
            return
        }
        
        if host == "watch", path == "dashboard" {
            self = .watchDashboard
            return
        }
        
        if host == "reminder" {
            // 提醒标识符大小写敏感，使用原始路径并还原百分号编码
            let rawPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let decoded = rawPath.removingPercentEncoding ?? rawPath
            self = .reminder(identifier: decoded.isEmpty ? nil : decoded)
            return
        }
        
        return nil
    }
}

/// 深度链接存储器 作为核心能力层里的数据读写与状态保存入口。
/// 负责核心业务服务与应用基础能力。
@MainActor
@Observable
final class DeepLinkStore {
    var pending: MianyuDeepLink?
    
    func handle(_ url: URL) {
        pending = MianyuDeepLink(url: url)
    }
}
