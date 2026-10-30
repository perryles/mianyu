/// User Info Store 负责应用内的共享核心能力，用于处理深链、登录、订阅、评估结果或购买流程等基础服务。
import Foundation

/// User信息存储器 作为核心能力层里的数据读写与状态保存入口。
/// 负责核心业务服务与应用基础能力。
struct UserInfoStore {
    static let nicknameKey = "userNickname"
    static let usernameKey = "userUsername"

    static func save(nickname: String?, username: String?, defaults: UserDefaults = .standard) {
        if let nickname {
            defaults.set(nickname, forKey: nicknameKey)
        } else {
            defaults.removeObject(forKey: nicknameKey)
        }
        if let username {
            defaults.set(username, forKey: usernameKey)
        } else {
            defaults.removeObject(forKey: usernameKey)
        }
    }

    static func load(defaults: UserDefaults = .standard) -> (nickname: String?, username: String?) {
        (
            defaults.string(forKey: nicknameKey),
            defaults.string(forKey: usernameKey)
        )
    }
}
