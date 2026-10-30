import SwiftUI

/// 内容视图 由上级页面或路由调用，作为当前模块里的界面或内容组件。
/// 负责组织核心模块入口和主流程展示。
struct ContentView: View {
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("isGuest") private var isGuest: Bool = false
    @AppStorage(AppOnboardingPreferences.completedKey) private var hasCompletedAppOnboarding: Bool = false
    @State private var hasFinishedLaunch: Bool = false

    init() {
        AppOnboardingPreferences.migrateIfNeeded()
    }
    
    var body: some View {
        Group {
            if !hasFinishedLaunch {
                AppLaunchView {
                    hasFinishedLaunch = true
                }
            } else if !hasCompletedAppOnboarding {
                AppOnboardingView {
                    if !isLoggedIn {
                        isGuest = true
                    }
                    hasCompletedAppOnboarding = true
                }
            } else if isLoggedIn || isGuest {
                MainTabView()
            } else {
                LoginView()
            }
        }
    }
}

/// 内容预览提供器 作为当前模块里的预览辅助类型。
/// 负责当前模块的核心逻辑。
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
