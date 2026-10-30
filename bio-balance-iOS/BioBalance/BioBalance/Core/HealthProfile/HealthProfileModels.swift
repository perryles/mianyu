import Foundation

enum HealthProfileRange: String, Codable, Hashable, Sendable {
    case sevenDays
    case thirtyDays
    case ninetyDays

    var dayCount: Int {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        }
    }

    var title: String {
        switch self {
        case .sevenDays: return "最近 7 天"
        case .thirtyDays: return "最近 30 天"
        case .ninetyDays: return "最近 90 天"
        }
    }
}

enum HealthProfileStatus: String, Codable, Hashable, Sendable {
    case building
    case growing
    case stable
    case needsRepair
    case volatile

    var title: String {
        switch self {
        case .building: return "档案建立中"
        case .growing: return "稳定成长"
        case .stable: return "正在恢复"
        case .needsRepair: return "需要修复"
        case .volatile: return "波动较大"
        }
    }
}

enum HealthProfileTrend: String, Codable, Hashable, Sendable {
    case improving
    case stable
    case declining
    case observing
    case missing

    var title: String {
        switch self {
        case .improving: return "改善"
        case .stable: return "稳定"
        case .declining: return "波动"
        case .observing: return "观察中"
        case .missing: return "缺样本"
        }
    }
}

enum HealthProfileDimensionKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case sleepRhythm
    case recoveryVitals
    case stressStability
    case activityBase
    case habitConsistency
    case menstrualWellbeing
    case symptomObservation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleepRhythm: return "睡眠节律"
        case .recoveryVitals: return "恢复信号"
        case .stressStability: return "压力稳定度"
        case .activityBase: return "活动基础"
        case .habitConsistency: return "习惯连续性"
        case .menstrualWellbeing: return "周期健康"
        case .symptomObservation: return "症状观察"
        }
    }

    var symbol: String {
        switch self {
        case .sleepRhythm: return "moon.zzz.fill"
        case .recoveryVitals: return "waveform.path.ecg"
        case .stressStability: return "brain.head.profile"
        case .activityBase: return "figure.walk"
        case .habitConsistency: return "checkmark.seal.fill"
        case .menstrualWellbeing: return "circle.hexagongrid.fill"
        case .symptomObservation: return "person.text.rectangle.fill"
        }
    }
}

enum HealthProfileConfidence: String, Codable, Hashable, Sendable {
    case high
    case medium
    case low

    var title: String {
        switch self {
        case .high: return "高置信"
        case .medium: return "中等置信"
        case .low: return "正在观察"
        }
    }
}

enum HealthProfileChangeKind: String, Codable, Hashable, Sendable {
    case positive
    case risk
    case stable
    case observing
}

enum HealthProfileImpact: String, Codable, Hashable, Sendable {
    case sleep
    case recovery
    case stress
    case activity
    case habit
    case data
}

enum HealthProfileModule: String, Codable, Hashable, Sendable {
    case sleep
    case stress
    case activity
    case sedentary
    case habits
    case reproductive
    case symptoms
    case healthKit
}

enum HealthProfileDataCompletenessState: String, Codable, Hashable, Sendable {
    case synced
    case insufficient
    case unauthorized
    case generated
    case notEnabled
    case notApplicable

    var title: String {
        switch self {
        case .synced: return "已同步"
        case .insufficient: return "样本不足"
        case .unauthorized: return "未授权"
        case .generated: return "已生成"
        case .notEnabled: return "未启用"
        case .notApplicable: return "不适用"
        }
    }
}

enum HealthProfileActionPriority: String, Codable, Hashable, Sendable {
    case high
    case medium
    case low

    var title: String {
        switch self {
        case .high: return "优先"
        case .medium: return "建议"
        case .low: return "保持"
        }
    }
}

struct HealthProfileDimension: Codable, Hashable, Identifiable, Sendable {
    var id: HealthProfileDimensionKind { kind }
    let kind: HealthProfileDimensionKind
    let title: String
    let statusText: String
    let score: Int?
    let trend: HealthProfileTrend
    let detail: String
}

struct HealthProfileChange: Codable, Hashable, Identifiable, Sendable {
    var id: String { "\(kind.rawValue)-\(title)-\(relatedModule.rawValue)" }
    let title: String
    let detail: String
    let kind: HealthProfileChangeKind
    let impact: HealthProfileImpact
    let relatedModule: HealthProfileModule
}

struct HealthProfileTag: Codable, Hashable, Identifiable, Sendable {
    var id: String { title }
    let title: String
    let detail: String
    let confidence: HealthProfileConfidence
    let evidence: [String]
    let firstDetectedAt: Date?
}

struct HealthProfileMilestone: Codable, Hashable, Identifiable, Sendable {
    var id: String { "\(title)-\(achievedAt.timeIntervalSince1970)" }
    let title: String
    let detail: String
    let achievedAt: Date
    let relatedModule: HealthProfileModule
}

struct HealthProfileRiskTendency: Codable, Hashable, Identifiable, Sendable {
    var id: String { "\(module.rawValue)-\(title)" }
    let title: String
    let detail: String
    let suggestion: String
    let module: HealthProfileModule
}

struct HealthProfileActionRecommendation: Codable, Hashable, Identifiable, Sendable {
    var id: String { "\(module.rawValue)-\(title)-\(priority.rawValue)" }
    let title: String
    let detail: String
    let reason: String
    let priority: HealthProfileActionPriority
    let module: HealthProfileModule
}

struct HealthProfileDataCompleteness: Codable, Hashable, Identifiable, Sendable {
    var id: String { title }
    let title: String
    let state: HealthProfileDataCompletenessState
    let detail: String
    let sampleCount: Int
}

struct HealthProfileDataQuality: Codable, Hashable, Sendable {
    let score: Int
    let confidence: HealthProfileConfidence
    let availableModules: Int
    let totalModules: Int
    let missingModules: [String]
    let unauthorizedModules: [String]
    let summary: String
}

struct HealthProfileSummary: Codable, Hashable, Sendable {
    let generatedAt: Date
    let range: HealthProfileRange
    let headline: String
    let status: HealthProfileStatus
    let growthScore: Int
    let dimensions: [HealthProfileDimension]
    let changes: [HealthProfileChange]
    let tags: [HealthProfileTag]
    let milestones: [HealthProfileMilestone]
    let riskTendencies: [HealthProfileRiskTendency]
    let actionRecommendations: [HealthProfileActionRecommendation]
    let dataCompleteness: [HealthProfileDataCompleteness]

    var isBuilding: Bool {
        status == .building
    }

    var dataQuality: HealthProfileDataQuality {
        // 派生行（例如本地压力估算）只用于解释画像，并非独立数据源，不能重复提高覆盖率。
        let applicable = dataCompleteness.filter {
            $0.title != "压力" &&
            $0.state != .notApplicable &&
            $0.state != .notEnabled &&
            $0.state != .generated
        }
        let available = applicable.filter { $0.state == .synced }
        let unauthorized = applicable.filter { $0.state == .unauthorized }.map(\.title)
        let missing = applicable.filter { $0.state == .insufficient }.map(\.title)
        let total = max(applicable.count, 1)
        let coverage = Double(available.count) / Double(total)
        let sampleScore = min(1, Double(applicable.reduce(0) { $0 + min($1.sampleCount, 7) }) / Double(total * 7))
        let score = Int((coverage * 70 + sampleScore * 30).rounded())
        let confidence: HealthProfileConfidence = score >= 80 ? .high : (score >= 55 ? .medium : .low)
        let summary: String
        if !unauthorized.isEmpty {
            summary = "\(available.count)/\(total) 项数据可用，\(unauthorized.joined(separator: "、"))尚未授权。"
        } else if !missing.isEmpty {
            summary = "\(available.count)/\(total) 项数据可用，\(missing.joined(separator: "、"))仍需更多样本。"
        } else {
            summary = "\(available.count)/\(total) 项核心数据可用，长期画像依据较完整。"
        }
        return HealthProfileDataQuality(
            score: max(0, min(100, score)),
            confidence: confidence,
            availableModules: available.count,
            totalModules: total,
            missingModules: missing,
            unauthorizedModules: unauthorized,
            summary: summary
        )
    }

    var aiDigest: HealthProfileAIDigest {
        let dimensionDigests = dimensions.prefix(7).map {
            HealthProfileAIDimensionDigest(
                title: $0.title,
                status: $0.statusText,
                score: $0.score,
                trend: $0.trend.title,
                summary: $0.detail
            )
        }
        let dimensionEvidence = dimensionDigests.map { item in
            if let score = item.score {
                return String(localized: "\(item.title)：\(score) 分，\(item.status)")
            }
            return "\(item.title)：\(item.status)"
        }
        let tagEvidence = tags
            .prefix(3)
            .flatMap { $0.evidence.prefix(2) }

        return HealthProfileAIDigest(
            range: range,
            generatedAt: generatedAt,
            headline: headline,
            status: status.title,
            growthScore: growthScore,
            dimensions: Array(dimensionDigests),
            evidence: Array((dimensionEvidence + tagEvidence).prefix(10)),
            topTags: tags.prefix(3).map(\.title),
            topRisks: riskTendencies.prefix(3).map(\.title),
            nextActions: actionRecommendations.prefix(3).map(\.title),
            recentChanges: changes.prefix(3).map(\.title),
            dataQualityScore: dataQuality.score,
            dataQualitySummary: dataQuality.summary,
            missingData: Array((dataQuality.unauthorizedModules + dataQuality.missingModules).prefix(4))
        )
    }
}

struct HealthProfileAIDimensionDigest: Codable, Hashable, Sendable {
    let title: String
    let status: String
    let score: Int?
    let trend: String
    let summary: String
}

struct HealthProfileAIDigest: Codable, Hashable, Sendable {
    let range: HealthProfileRange
    let generatedAt: Date
    let headline: String
    let status: String
    let growthScore: Int
    let dimensions: [HealthProfileAIDimensionDigest]
    let evidence: [String]
    let topTags: [String]
    let topRisks: [String]
    let nextActions: [String]
    let recentChanges: [String]
    let dataQualityScore: Int
    let dataQualitySummary: String
    let missingData: [String]

    private enum CodingKeys: String, CodingKey {
        case range
        case generatedAt
        case headline
        case status
        case growthScore
        case dimensions
        case evidence
        case topTags
        case topRisks
        case nextActions
        case recentChanges
        case dataQualityScore
        case dataQualitySummary
        case missingData
    }

    init(
        range: HealthProfileRange = .thirtyDays,
        generatedAt: Date = Date(),
        headline: String,
        status: String,
        growthScore: Int,
        dimensions: [HealthProfileAIDimensionDigest] = [],
        evidence: [String] = [],
        topTags: [String],
        topRisks: [String],
        nextActions: [String],
        recentChanges: [String],
        dataQualityScore: Int = 0,
        dataQualitySummary: String = "数据质量待评估",
        missingData: [String] = []
    ) {
        self.range = range
        self.generatedAt = generatedAt
        self.headline = headline
        self.status = status
        self.growthScore = growthScore
        self.dimensions = Array(dimensions.prefix(8))
        self.evidence = Array(evidence.prefix(12))
        self.topTags = Array(topTags.prefix(4))
        self.topRisks = Array(topRisks.prefix(4))
        self.nextActions = Array(nextActions.prefix(4))
        self.recentChanges = Array(recentChanges.prefix(4))
        self.dataQualityScore = max(0, min(100, dataQualityScore))
        self.dataQualitySummary = dataQualitySummary
        self.missingData = Array(missingData.prefix(6))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decodeIfPresent(HealthProfileRange.self, forKey: .range) ?? .thirtyDays
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .distantPast
        headline = try container.decode(String.self, forKey: .headline)
        status = try container.decode(String.self, forKey: .status)
        growthScore = try container.decode(Int.self, forKey: .growthScore)
        dimensions = Array((try container.decodeIfPresent([HealthProfileAIDimensionDigest].self, forKey: .dimensions) ?? []).prefix(8))
        evidence = Array((try container.decodeIfPresent([String].self, forKey: .evidence) ?? []).prefix(12))
        topTags = Array((try container.decodeIfPresent([String].self, forKey: .topTags) ?? []).prefix(4))
        topRisks = Array((try container.decodeIfPresent([String].self, forKey: .topRisks) ?? []).prefix(4))
        nextActions = Array((try container.decodeIfPresent([String].self, forKey: .nextActions) ?? []).prefix(4))
        recentChanges = Array((try container.decodeIfPresent([String].self, forKey: .recentChanges) ?? []).prefix(4))
        dataQualityScore = max(0, min(100, try container.decodeIfPresent(Int.self, forKey: .dataQualityScore) ?? 0))
        dataQualitySummary = try container.decodeIfPresent(String.self, forKey: .dataQualitySummary) ?? "数据质量待评估"
        missingData = Array((try container.decodeIfPresent([String].self, forKey: .missingData) ?? []).prefix(6))
    }
}
