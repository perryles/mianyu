//
//  BioBalanceWatchApp.swift
//  BioBalanceWatch Watch App
//
//  Created by lihaha on 2026/4/13.
//

import SwiftUI

/// Apple Watch 应用入口 作为手表端应用的启动入口。
/// 负责挂载手表端根视图，并初始化应用级场景结构。
@main
struct MianyuWatch_Watch_AppApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var receiver = WatchConnectivityReceiver.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .task {
                    _ = receiver
                    receiver.requestLatestFromiPhone()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    receiver.requestLatestFromiPhone()
                }
        }
    }
}
