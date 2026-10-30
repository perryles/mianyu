import Foundation

/// 单张饮品照片的 Provider-neutral 请求，不包含位置或用户身份。
nonisolated struct AIDrinkAnalysisRequest: Sendable {
    let image: AIMealImageInput
    let capturedAt: Date
    let localeIdentifier: String

    init(
        image: AIMealImageInput,
        capturedAt: Date = Date(),
        localeIdentifier: String = Locale.current.identifier
    ) {
        self.image = image
        self.capturedAt = capturedAt
        self.localeIdentifier = localeIdentifier
    }

    func validate() throws {
        guard !image.data.isEmpty else { throw AIMealAnalysisError.invalidImageCount }
        guard image.hasSupportedMimeType else { throw AIMealAnalysisError.unsupportedImageFormat }
    }
}

nonisolated struct AIDrinkCandidate: Sendable, Equatable {
    let name: String
    let confidence: Double
}

/// 饮品识别草稿；店名只允许来自照片中可见文字，城市由设备本地位置补充。
nonisolated struct AIDrinkAnalysisResult: Sendable, Equatable {
    let primaryName: String
    let candidates: [AIDrinkCandidate]
    let storeName: String?
    let confidence: Double
    let requiresReview: Bool
    let warnings: [String]
    let provider: AIProviderID
    let model: String
}

nonisolated enum AIDrinkStructuredResponseDecoder {
    private static let maximumPayloadBytes = 256 * 1_024

    static func decode(_ data: Data, provider: AIProviderID, model: String) throws -> AIDrinkAnalysisResult {
        guard !data.isEmpty,
              data.count <= maximumPayloadBytes,
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw AIMealAnalysisError.invalidStructuredResponse
        }
        let status = payload.status.lowercased()
        if status == "abstained" {
            throw AIMealAnalysisError.abstained(bounded(payload.reason, limit: 240))
        }
        guard status == "recognized" || status == "needs_review",
              let primaryName = bounded(payload.primaryName, limit: 80, rejectsOverflow: true),
              let confidence = payload.confidence,
              confidence.isFinite,
              (0...1).contains(confidence),
              (0...5).contains(payload.candidates.count) else {
            throw AIMealAnalysisError.invalidStructuredResponse
        }

        let candidates = try payload.candidates.map { candidate -> AIDrinkCandidate in
            guard let name = bounded(candidate.name, limit: 80, rejectsOverflow: true),
                  let candidateConfidence = candidate.confidence,
                  candidateConfidence.isFinite,
                  (0...1).contains(candidateConfidence) else {
                throw AIMealAnalysisError.invalidStructuredResponse
            }
            return AIDrinkCandidate(name: name, confidence: candidateConfidence)
        }
        let warnings = Array(payload.warnings.compactMap { bounded($0, limit: 160) }.prefix(5))
        return AIDrinkAnalysisResult(
            primaryName: primaryName,
            candidates: candidates,
            storeName: bounded(payload.storeName, limit: 80),
            confidence: confidence,
            requiresReview: status == "needs_review" || confidence < 0.8,
            warnings: warnings,
            provider: provider,
            model: String(model.prefix(80))
        )
    }

    private struct Payload: Decodable {
        let status: String
        let primaryName: String?
        let storeName: String?
        let confidence: Double?
        let candidates: [Candidate]
        let warnings: [String]
        let reason: String?

        struct Candidate: Decodable {
            let name: String?
            let confidence: Double?
        }
    }

    private static func bounded(
        _ value: String?,
        limit: Int,
        rejectsOverflow: Bool = false
    ) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else { return nil }
        if rejectsOverflow, normalized.count > limit { return nil }
        return String(normalized.prefix(limit))
    }
}
