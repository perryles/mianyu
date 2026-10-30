import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// FitnessCalendarViewModel 展示格式化子模块。
/// 从 FitnessCalendarViewModel+Presentation.swift 再拆分：配速文本、日期/范围标题、星期与日号字符串。

@MainActor
extension FitnessCalendarViewModel {

    static func paceText(_ minutesPerKilometer: Double) -> String {
        guard minutesPerKilometer.isFinite, minutesPerKilometer > 0 else { return "--" }
        let totalSeconds = Int((minutesPerKilometer * 60).rounded())
        return String(format: "%d'%02d\"", totalSeconds / 60, totalSeconds % 60)
    }

    func calendarRangeTitle(for scope: HabitCalendarScope, startDate: Date, endDate: Date) -> String {
        switch scope {
        case .week:
            return "\(Self.shortDateFormatter.string(from: startDate)) - \(Self.shortDateFormatter.string(from: endDate))"
        case .month:
            return Self.monthFormatter.string(from: startDate)
        }
    }

    func weekdayShortString(_ date: Date) -> String {
        Self.weekdayFormatter.string(from: date).replacingOccurrences(of: "周", with: "")
    }

    func dayNumberString(_ date: Date) -> String {
        Self.dayNumberFormatter.string(from: date)
    }

}
