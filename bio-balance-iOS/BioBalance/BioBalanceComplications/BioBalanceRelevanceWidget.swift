#if os(watchOS) && compiler(>=6.2)
import AppIntents
import RelevanceKit
import SwiftUI
import WidgetKit

@available(watchOS 26.0, *)
enum RelevanceTemplate: String, AppEnum, CaseIterable {
    case morningRecovery, recoveryAction, activityProgress, sleepPreparation, hydration

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "主动健康场景")
    static let caseDisplayRepresentations: [RelevanceTemplate: DisplayRepresentation] = [
        .morningRecovery: "晨间恢复",
        .recoveryAction: "恢复行动",
        .activityProgress: "活动进度",
        .sleepPreparation: "睡眠准备",
        .hydration: "补水提醒"
    ]
}

@available(watchOS 26.0, *)
struct MianyuRelevanceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "眠屿 主动健康"

    @Parameter(title: "场景")
    var template: RelevanceTemplate?

    init() { template = .morningRecovery }
    init(template: RelevanceTemplate) { self.template = template }
}

@available(watchOS 26.0, *)
struct MianyuRelevanceEntry: RelevanceEntry {
    let candidate: WidgetRelevanceCandidate?
}

@available(watchOS 26.0, *)
struct MianyuRelevanceProvider: RelevanceEntriesProvider {
    typealias Entry = MianyuRelevanceEntry
    typealias Configuration = MianyuRelevanceIntent

    func relevance() async -> WidgetRelevance<MianyuRelevanceIntent> {
        let attributes = candidates().map { candidate in
            WidgetRelevanceAttribute(
                configuration: MianyuRelevanceIntent(template: template(for: candidate.kind)),
                context: .date(
                    interval: DateInterval(start: candidate.startDate, end: candidate.endDate),
                    kind: .informational
                )
            )
        }
        return WidgetRelevance(attributes)
    }

    func entry(configuration: MianyuRelevanceIntent, context: Context) async throws -> Entry {
        let requestedTemplate = configuration.template ?? .morningRecovery
        return Entry(candidate: candidates().first { template(for: $0.kind) == requestedTemplate })
    }

    func placeholder(context: Context) -> Entry {
        Entry(candidate: WidgetRelevanceCandidate(
            id: "preview-recovery",
            kind: .recoveryAction,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            priority: 100,
            title: "起来活动一下",
            detail: "用两分钟恢复状态",
            symbolName: "figure.walk",
            deepLink: URL(string: "biobalance://widget/activity")!
        ))
    }

    private func candidates() -> [WidgetRelevanceCandidate] {
        guard let snapshot = AppGroupSnapshotStore.load() else { return [] }
        return WidgetRelevanceResolver.candidates(from: snapshot)
    }

    private func template(for kind: WidgetRelevanceKind) -> RelevanceTemplate {
        switch kind {
        case .morningRecovery: .morningRecovery
        case .recoveryAction: .recoveryAction
        case .activityProgress: .activityProgress
        case .sleepPreparation: .sleepPreparation
        case .hydration: .hydration
        }
    }
}

@available(watchOS 26.0, *)
struct MianyuRelevanceWidget: Widget {
    let kind = AppGroupSchema.Kind.complicationRelevance

    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: kind, provider: MianyuRelevanceProvider()) { entry in
            MianyuRelevanceView(entry: entry)
        }
        .configurationDisplayName("主动健康")
        .description("在合适的时间显示恢复、活动、睡眠与补水建议。")
    }
}

@available(watchOS 26.0, *)
private struct MianyuRelevanceView: View {
    let entry: MianyuRelevanceEntry

    var body: some View {
        if let candidate = entry.candidate {
            VStack(alignment: .leading, spacing: 4) {
                Label(candidate.title, systemImage: candidate.symbolName)
                    .font(.headline)
                    .lineLimit(1)
                Text(candidate.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .widgetURL(candidate.deepLink)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            Label("健康数据同步后显示", systemImage: "heart.text.square")
                .font(.caption)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}
#endif
