/// Watch Face Library Manager 负责手表同步相关的数据结构或管理逻辑，用于在 iPhone 与 Apple Watch 之间同步关键状态。
import Foundation
import ClockKit
import WatchConnectivity

enum OfficialWatchFaceKind: String, CaseIterable, Identifiable {
    case recoveryOverview
    case dualModule

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recoveryOverview:
            return "恢复概览"
        case .dualModule:
            return String(localized: "双模块")
        }
    }

    var expectedPath: String {
        switch self {
        case .recoveryOverview:
            return "WatchFaces/BalenWatch-RecoveryOverview.watchface"
        case .dualModule:
            return "WatchFaces/BalenWatch-DualModule.watchface"
        }
    }

    var primaryResourceName: String {
        switch self {
        case .recoveryOverview:
            return "BalenWatch-RecoveryOverview"
        case .dualModule:
            return "BalenWatch-DualModule"
        }
    }

    var candidateNames: [String] {
        switch self {
        case .recoveryOverview:
            return [
                "BalenWatch-RecoveryOverview",
                "RecoveryOverview",
                "Recovery Overview",
                "恢复概览",
                "模块"
            ]
        case .dualModule:
            return [
                "BalenWatch-DualModule",
                "DualModule",
                "Dual Module",
                "双模块"
            ]
        }
    }

    var filenameKeywords: [String] {
        switch self {
        case .recoveryOverview:
            return ["recovery", "overview", "恢复", "模块"]
        case .dualModule:
            return ["dual", "module", "双模块"]
        }
    }
}

/// 表盘Launch枚举 作为手表同步能力层里的状态与分类定义。
/// 负责描述手机与手表之间的数据同步过程中会用到的状态、分类或分支。
enum WatchFaceLaunchState: Equatable {
    case idle
    case launching
    case openedOfficialFlow
    case failed(WatchFaceLaunchError)
}

/// 表盘Launch错误枚举 作为手表同步能力层里的错误状态定义。
/// 负责描述手机与手表之间的数据同步过程中会用到的状态、分类或分支。
enum WatchFaceLaunchError: LocalizedError, Equatable {
    case watchUnavailable
    case notPaired
    case watchAppNotInstalled
    case resourceMissing
    case userCancelled
    case systemFailure(String)

    var errorDescription: String? {
        switch self {
        case .watchUnavailable:
            return String(localized: "这台 iPhone 当前不支持 Apple Watch 表盘添加。")
        case .notPaired:
            return String(localized: "还没有检测到已配对的 Apple Watch。")
        case .watchAppNotInstalled:
            return String(localized: "请先在已配对的 Apple Watch 上安装 眠屿。")
        case .resourceMissing:
            return String(localized: "当前表盘资源尚未打包到 iPhone App。请确认对应的 .watchface 文件已加入 眠屿 主 App target。")
        case .userCancelled:
            return String(localized: "你已取消本次表盘添加。")
        case .systemFailure(let message):
            return message
        }
    }
}

enum WatchFaceResourceStatus: Equatable {
    case available(URL)
    case missing(expectedPath: String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

/// 表盘Library管理器 作为手表同步能力层里的服务或调度入口。
/// 负责手机与手表之间的数据同步。
@MainActor
final class WatchFaceLibraryManager {
    static let shared = WatchFaceLibraryManager()

    private init() {}

    func resourceStatus(for kind: OfficialWatchFaceKind, bundle: Bundle = .main) -> WatchFaceResourceStatus {
        if let url = bundledWatchFaceURL(for: kind, bundle: bundle) {
            return .available(url)
        }
        return .missing(expectedPath: kind.expectedPath)
    }

    func addFace(_ kind: OfficialWatchFaceKind) async -> WatchFaceLaunchState {
        guard WCSession.isSupported() else {
            return .failed(.watchUnavailable)
        }

        let session = WCSession.default
        guard session.isPaired else {
            return .failed(.notPaired)
        }
        guard session.isWatchAppInstalled else {
            return .failed(.watchAppNotInstalled)
        }
        guard case let .available(resourceURL) = resourceStatus(for: kind) else {
            return .failed(.resourceMissing)
        }

        do {
            try await addWatchFace(at: resourceURL)
            return .openedOfficialFlow
        } catch let error as WatchFaceLaunchError {
            return .failed(error)
        } catch {
            return .failed(.systemFailure(error.localizedDescription))
        }
    }

    private func bundledWatchFaceURL(for kind: OfficialWatchFaceKind, bundle: Bundle = .main) -> URL? {
        if let url = bundle.url(
            forResource: kind.primaryResourceName,
            withExtension: "watchface",
            subdirectory: "WatchFaces"
        ) {
            return url
        }

        let candidateSubdirectories: [String?] = ["WatchFaces", "Resources/WatchFaces", nil]

        for subdirectory in candidateSubdirectories {
            for name in kind.candidateNames {
                if let url = bundle.url(forResource: name, withExtension: "watchface", subdirectory: subdirectory) {
                    return url
                }
            }
        }

        for subdirectory in candidateSubdirectories {
            let urls = bundle.urls(forResourcesWithExtension: "watchface", subdirectory: subdirectory) ?? []
            if let matchedURL = urls.first(where: { url in
                let filename = url.deletingPathExtension().lastPathComponent.lowercased()
                return kind.filenameKeywords.contains(where: { filename.contains($0.lowercased()) })
            }) {
                return matchedURL
            }
        }

        return nil
    }

    private func addWatchFace(at url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CLKWatchFaceLibrary().addWatchFace(at: url) { error in
                if let error {
                    let nsError = error as NSError
                    if nsError.code == NSUserCancelledError {
                        continuation.resume(throwing: WatchFaceLaunchError.userCancelled)
                    } else {
                        continuation.resume(throwing: WatchFaceLaunchError.systemFailure(error.localizedDescription))
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
