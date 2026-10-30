import SwiftUI
import UIKit
import WidgetKit

struct SunlightEntry: TimelineEntry {
    let date: Date
    let minutesToday: Int?
    let goalMinutes: Int
    let completionRate: Double?
    let lastSyncTime: Date?
}

struct SunlightProvider: TimelineProvider {
    func placeholder(in context: Context) -> SunlightEntry {
        SunlightEntry(date: .now, minutesToday: 12, goalMinutes: 20, completionRate: 0.6, lastSyncTime: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (SunlightEntry) -> Void) {
        completion(loadEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SunlightEntry>) -> Void) {
        let now = Date()
        let base = loadEntry(date: now)
        // 多 entry 让同日判断与时间文案在两次刷新之间也能持续推进
        let entries = (0..<8).map { offset in
            SunlightEntry(
                date: now.addingTimeInterval(TimeInterval(offset) * 15 * 60),
                minutesToday: base.minutesToday,
                goalMinutes: base.goalMinutes,
                completionRate: base.completionRate,
                lastSyncTime: base.lastSyncTime
            )
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func loadEntry(date: Date) -> SunlightEntry {
        let snapshot = WidgetSharedStore.loadSnapshot(now: date)
        let directGoal = AppGroupManager.shared.getSunlightGoalMinutes()
        let directMinutesToday = AppGroupManager.shared.getSunlightMinutesToday()
        let directRate = AppGroupManager.shared.getSunlightCompletionRate()
        let directUpdatedAt = AppGroupManager.shared.getSunlightUpdatedAt()

        let goal = max(1, directGoal ?? snapshot.sunlightGoalMinutes ?? 20)
        let minutesToday = directMinutesToday ?? snapshot.sunlightMinutesToday
        let rate = directRate
            ?? snapshot.sunlightCompletionRate
            ?? minutesToday.map { min(1.0, Double(max(0, $0)) / Double(goal)) }
        let lastSyncTime = directUpdatedAt ?? snapshot.sunlightLastExposureAt ?? snapshot.lastSyncTime
        return SunlightEntry(
            date: date,
            minutesToday: minutesToday,
            goalMinutes: goal,
            completionRate: rate,
            lastSyncTime: lastSyncTime
        )
    }
}

struct SunlightWidget: Widget {
    let kind: String = AppGroupSchema.Kind.sunlight

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SunlightProvider()) { entry in
            SunlightWidgetEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("晒太阳")
        .description("用一张小卡快速看今天晒了多久，还差几分钟达标。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

private struct SunlightWidgetEntryView: View {
    let entry: SunlightEntry

    var body: some View {
        SunlightSmallCard(entry: entry)
            .widgetURL(MianyuWidgetDeepLink.sunlight)
    }
}

private struct SunlightDescriptor {
    let state: WidgetDataState
    let title: String
    let subtitle: String
    let accent: Color
    let progress: Double
    let minutesText: String
    let unitText: String
    let syncText: String

    static func resolve(entry: SunlightEntry) -> SunlightDescriptor {
        let dataState = sunlightDataState(for: entry)
        let minutes = max(0, entry.minutesToday ?? 0)
        let goal = max(1, entry.goalMinutes)
        let rate = min(1.0, max(0.0, entry.completionRate ?? Double(minutes) / Double(goal)))

        switch dataState {
        case .missing:
            return SunlightDescriptor(
                state: .missing,
                title: String(localized: "等待同步"),
                subtitle: String(localized: "打开 App 同步自然光数据"),
                accent: WidgetPalette.textSecondary,
                progress: 0.10,
                minutesText: "--",
                unitText: String(localized: "分钟"),
                syncText: String(localized: "待同步")
            )
        case .stale:
            return SunlightDescriptor(
                state: .stale,
                title: String(localized: "数据较旧"),
                subtitle: String(localized: "结果仅供参考"),
                accent: WidgetPalette.accentOrange,
                progress: max(0.12, rate),
                minutesText: minutes > 0 ? "\(minutes)" : "--",
                unitText: String(localized: "分钟"),
                syncText: String(localized: "较旧")
            )
        case .fresh:
            if minutes <= 0 {
                return SunlightDescriptor(
                    state: .fresh,
                    title: String(localized: "待开始"),
                    subtitle: String(localized: "出门晒一会"),
                    accent: WidgetPalette.accentOrange,
                    progress: 0.06,
                    minutesText: "0",
                    unitText: String(localized: "分钟"),
                    syncText: widgetClockText(for: entry.lastSyncTime, staleAfter: AppGroupSchema.Freshness.sunlightStaleAfter, now: entry.date)
                )
            }

            if rate >= 1.0 {
                return SunlightDescriptor(
                    state: .fresh,
                    title: String(localized: "已达标"),
                    subtitle: String(localized: "今天保持得不错"),
                    accent: WidgetPalette.accentOrange,
                    progress: 1.0,
                    minutesText: "\(minutes)",
                    unitText: String(localized: "分钟"),
                    syncText: widgetClockText(for: entry.lastSyncTime, staleAfter: AppGroupSchema.Freshness.sunlightStaleAfter, now: entry.date)
                )
            }

            return SunlightDescriptor(
                state: .fresh,
                title: String(localized: "待补足"),
                subtitle: String(localized: "还差 \(max(0, goal - minutes)) 分钟"),
                accent: WidgetPalette.accentOrange,
                progress: max(0.08, rate),
                minutesText: "\(minutes)",
                unitText: String(localized: "分钟"),
                syncText: widgetClockText(for: entry.lastSyncTime, staleAfter: AppGroupSchema.Freshness.sunlightStaleAfter, now: entry.date)
            )
        }
    }
}

private struct SunlightSmallCard: View {
    let entry: SunlightEntry

    var body: some View {
        let descriptor = SunlightDescriptor.resolve(entry: entry)
        let shape = RoundedRectangle(cornerRadius: WidgetGlassMetrics.outerRadiusSmall, style: .continuous)

        ZStack {
            WidgetReferenceCardBackground(tint: descriptor.accent, cornerRadius: WidgetGlassMetrics.outerRadiusSmall)
            VStack(alignment: .leading, spacing: 5) {
                WidgetReferenceHeader(icon: "sun.max.fill", title: String(localized: "晒太阳"), status: descriptor.title, tint: descriptor.accent)
                WidgetReferenceMetric(value: descriptor.minutesText, unit: descriptor.unitText)
                VStack(alignment: .leading, spacing: 6) {
                    Text(descriptor.subtitle)
                        .font(.widgetAppSystem(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(1)
                    WidgetReferenceProgressTrack(progress: descriptor.progress, tint: descriptor.accent)
                        .frame(height: 12)
                }
                .frame(height: 34, alignment: .center)
                WidgetReferenceFooter(stats: [
                    WidgetReferenceStat(value: descriptor.minutesText, label: String(localized: "时长"), tint: descriptor.accent),
                    WidgetReferenceStat(value: "\(entry.goalMinutes)", label: String(localized: "目标"), tint: WidgetPalette.brandCyan),
                    WidgetReferenceStat(value: descriptor.syncText, label: String(localized: "同步"), tint: Color.white.opacity(0.72))
                ])
            }
            .padding(12)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }
}

private struct SunlightHeroImage: View {
    let accent: Color
    let isMuted: Bool

    var body: some View {
        Group {
            if imageExists {
                Image("SunlightWidgetHero")
                    .resizable()
                    #if compiler(>=6.2)
                    .widgetAccentedRenderingMode(.accentedDesaturated)
                    #endif
                    .scaledToFit()
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.22), Color.white.opacity(0.88)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sun.max.fill")
                        .font(.widgetAppSystem(size: 32, weight: .bold))
                        .foregroundStyle(accent)
                }
            }
        }
        .frame(width: WidgetGlassMetrics.smallCornerOrbSize, height: WidgetGlassMetrics.smallCornerOrbSize)
        .opacity(isMuted ? 0.45 : 1.0)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 5)
    }

    private var imageExists: Bool {
        // Asset Catalog 里的图片无法用 Bundle.path 检测，需用 UIImage(named:) 判断
        UIImage(named: "SunlightWidgetHero") != nil
    }
}

private func sunlightDataState(for entry: SunlightEntry) -> WidgetDataState {
    guard let lastSyncTime = entry.lastSyncTime else { return .missing }
    let calendar = Calendar.current
    return calendar.isDate(lastSyncTime, inSameDayAs: entry.date) ? .fresh : .stale
}

#if ENABLE_WIDGET_PREVIEWS
#Preview("Sunlight Small", as: .systemSmall) {
    SunlightWidget()
} timeline: {
    SunlightEntry(date: .now, minutesToday: 25, goalMinutes: 60, completionRate: 25.0 / 60.0, lastSyncTime: .now)
    SunlightEntry(date: .now, minutesToday: 0, goalMinutes: 20, completionRate: 0, lastSyncTime: .now)
    SunlightEntry(date: .now, minutesToday: nil, goalMinutes: 20, completionRate: nil, lastSyncTime: nil)
}
#endif
