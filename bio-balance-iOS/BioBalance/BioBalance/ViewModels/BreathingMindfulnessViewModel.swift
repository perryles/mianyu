import Foundation
import SwiftUI

@MainActor
protocol BreathingLiveActivityCoordinating: AnyObject {
    func start(durationSeconds: Int)
    func end()
}

@MainActor
private final class DisabledBreathingLiveActivityCoordinator: BreathingLiveActivityCoordinating {
    func start(durationSeconds: Int) {}
    func end() {}
}

/// 呼吸正念视图模型 作为视图模型层里的界面状态管理入口。
/// 负责连接界面与底层数据源，处理状态管理、业务计算和用户操作响应。
@MainActor
@Observable
final class BreathingMindfulnessViewModel {
    /// Range 枚举，作为内部辅助类型，用于细分外层界面状态管理与业务编排中的状态或分支。
    enum Range: String, CaseIterable, Identifiable {
        case day
        case week
        case month
        
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .day: return "日"
            case .week: return "周"
            case .month: return "月"
            }
        }
        
        func startDate(now: Date) -> Date {
            let cal = Calendar.current
            switch self {
            case .day:
                return cal.startOfDay(for: now)
            case .week:
                return cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
            case .month:
                return cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now)) ?? now
            }
        }
    }

    /// Session Length 枚举，作为内部辅助类型，用于细分外层界面状态管理与业务编排中的状态或分支。
    enum SessionLength: Int, CaseIterable, Identifiable {
        case one = 60
        case three = 180
        case five = 300

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .one: return "1分钟"
            case .three: return "3分钟"
            case .five: return "5分钟"
            }
        }

        var shortTitle: String {
            switch self {
            case .one: return "1 分钟"
            case .three: return "3 分钟"
            case .five: return "5 分钟"
            }
        }
    }

    /// Session State 枚举，作为内部辅助类型，用于细分外层界面状态管理与业务编排中的状态或分支。
    enum SessionState: Equatable {
        case idle
        case running
        case saving
        case completed
        case failed(String)
    }
    
    var range: Range = .day
    var points: [HealthKitManager.RespiratoryRatePoint] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var selectedSessionLength: SessionLength = .three
    var sessionState: SessionState = .idle
    var remainingSeconds: Int = SessionLength.three.rawValue

    private var sessionTask: Task<Void, Never>?
    private var sessionStart: Date?
    @ObservationIgnored private let liveActivityCoordinator: BreathingLiveActivityCoordinating
    /// 加载代际：快速切换范围时只允许最新一次加载写入结果。
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    init() {
        liveActivityCoordinator = DisabledBreathingLiveActivityCoordinator()
    }

    init(liveActivityCoordinator: BreathingLiveActivityCoordinating) {
        self.liveActivityCoordinator = liveActivityCoordinator
    }
    
    func reload() {
        let now = Date()
        let start = range.startDate(now: now)
        let end = now

        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration

        isLoading = true
        errorMessage = nil

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let pts = try await HealthKitManager.shared.fetchRespiratoryRateSeries(start: start, end: end)
                guard !Task.isCancelled, generation == self.loadGeneration else { return }
                self.points = pts
                self.isLoading = false
                if pts.isEmpty {
                    self.errorMessage = "暂无呼吸频率数据。请确认健康 App 中存在记录，并已授权读取。"
                }
            } catch {
                guard !Task.isCancelled, generation == self.loadGeneration else { return }
                self.points = []
                self.isLoading = false
                self.errorMessage = "读取失败。请检查健康权限后重试。"
            }
        }
    }

    func prepareSession() {
        guard !isSessionRunning else { return }
        remainingSeconds = selectedSessionLength.rawValue
        if case .completed = sessionState {
            sessionState = .idle
        }
    }

    func startSession() {
        guard !isSessionRunning else { return }

        prepareSession()
        sessionStart = Date()
        sessionState = .running
        liveActivityCoordinator.start(durationSeconds: selectedSessionLength.rawValue)

        sessionTask?.cancel()
        sessionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                guard !Task.isCancelled else { return }

                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                }

                if self.remainingSeconds == 0 {
                    await self.finishSession()
                    return
                }
            }
        }
    }

    func cancelSession() {
        sessionTask?.cancel()
        sessionTask = nil
        sessionState = .idle
        remainingSeconds = selectedSessionLength.rawValue
        liveActivityCoordinator.end()
    }

    private func finishSession() async {
        sessionTask?.cancel()
        sessionTask = nil
        liveActivityCoordinator.end()
        sessionState = .saving

        let end = Date()
        let start = sessionStart ?? end.addingTimeInterval(-TimeInterval(selectedSessionLength.rawValue))

        do {
            try await HealthKitManager.shared.saveMindfulSession(start: start, end: end)
            // 本地优先：无自建后端，正念记录仅写入 HealthKit。
            sessionState = .completed
            remainingSeconds = selectedSessionLength.rawValue
            reload()
        } catch {
            sessionState = .failed("未能写入正念记录，请检查健康权限。")
            remainingSeconds = selectedSessionLength.rawValue
        }
    }
    
    func requestAuthorizationAndReload() {
        isLoading = true
        errorMessage = nil
        isLoading = false
        errorMessage = "健康权限入口已调整到今日页面，请先到今日页面完成授权。"
    }
    
    var latestValue: Double? {
        chartPoints.last(where: { $0.value > 0 })?.value
    }
    
    var averageValue: Double? {
        let values = chartPoints.map(\.value).filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        let sum = values.reduce(0, +)
        return sum / Double(values.count)
    }
    
    var minValue: Double? {
        chartPoints.map(\.value).filter { $0 > 0 }.min()
    }
    
    var maxValue: Double? {
        chartPoints.map(\.value).filter { $0 > 0 }.max()
    }

    var isSessionRunning: Bool {
        if case .running = sessionState {
            return true
        }
        return false
    }

    var chartPoints: [HealthKitManager.RespiratoryRatePoint] {
        switch range {
        case .day:
            return points
        case .week, .month:
            let calendar = Calendar.current
            let days = range == .week ? 7 : 30
            let start = range.startDate(now: Date())
            let grouped = Dictionary(grouping: points) { point in
                calendar.startOfDay(for: point.date)
            }

            return (0..<days).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                let normalized = calendar.startOfDay(for: date)
                let values = grouped[normalized]?.map(\.value) ?? []
                let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
                return HealthKitManager.RespiratoryRatePoint(date: normalized, value: average)
            }
        }
    }

    var xAxisDates: [Date] {
        let calendar = Calendar.current
        let now = Date()
        switch range {
        case .day:
            let start = calendar.startOfDay(for: now)
            return stride(from: 0, through: 24, by: 6).compactMap {
                calendar.date(byAdding: .hour, value: $0, to: start)
            }
        case .week:
            let start = range.startDate(now: now)
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        case .month:
            let start = range.startDate(now: now)
            return stride(from: 0, through: 25, by: 5).compactMap {
                calendar.date(byAdding: .day, value: $0, to: start)
            }
        }
    }

    var xAxisDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()
        switch range {
        case .day:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .hour, value: 24, to: start) ?? start.addingTimeInterval(86_400)
            return start...end
        case .week, .month:
            guard let first = chartPoints.first?.date,
                  let last = chartPoints.last?.date,
                  let upper = calendar.date(byAdding: .day, value: 1, to: last) else {
                let start = range.startDate(now: now)
                let end = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
                return start...end
            }
            return first...upper
        }
    }

    var yAxisValues: [Double] {
        let values = chartPoints.map(\.value).filter { $0 > 0 }
        guard let minValue = values.min(), let maxValue = values.max() else {
            return [10, 14, 18, 22]
        }

        let lower = max(6, floor((minValue - 1.5) / 2.0) * 2.0)
        let upper = max(lower + 2, ceil((maxValue + 1.5) / 2.0) * 2.0)
        let step = max(1, (upper - lower) / 3.0)
        return [lower, lower + step, lower + step * 2, upper]
    }
}
