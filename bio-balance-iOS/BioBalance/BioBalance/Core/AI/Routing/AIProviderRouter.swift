import Foundation

/// 某项能力对应的候选 Provider 顺序。
nonisolated struct AIProviderRoute: Sendable, Equatable {
    let capability: AICapability
    let providerIDs: [AIProviderID]
}

/// 按路由顺序从注册表解析当前可用的 Provider 实例。
nonisolated struct AIProviderRouter: Sendable {
    let registry: AIProviderRegistry

    func textProviders(for route: AIProviderRoute) -> [any AITextProviding] {
        guard route.capability == .healthChat ||
                route.capability == .healthAnalysis ||
                route.capability == .prescriptionStructuring else { return [] }
        return route.providerIDs.compactMap {
            registry.textProvider(id: $0, capability: route.capability)
        }
    }

    func visionProviders(for route: AIProviderRoute) -> [any AIVisionProviding] {
        guard route.capability == .mealVision else { return [] }
        return route.providerIDs.compactMap { registry.visionProvider(id: $0) }
    }
}

/// 只有瞬时故障允许进入下一个 Provider；取消、鉴权和参数错误必须原样返回。
nonisolated enum AIFailurePolicy {
    static func permitsFallback(after error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError {
            return [
                .timedOut,
                .networkConnectionLost,
                .notConnectedToInternet,
                .cannotConnectToHost,
                .cannotFindHost,
                .dnsLookupFailed
            ].contains(urlError.code)
        }
        guard let serviceError = error as? AIServiceError else { return false }
        switch serviceError {
        case .httpError(let statusCode, _):
            return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        case .disabledProvider, .missingAPIKey:
            return true
        case .invalidRequest, .invalidURL, .invalidResponse, .responseTooLarge,
             .decodingFailed, .emptyResponse, .keychainFailure, .unsupportedOperation:
            return false
        }
    }
}
