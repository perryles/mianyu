/// ChineseDateText 作为共享界面层的能力定义，负责提供中文日期格式化。
/// 负责提供全日期、月日、数字等中文日期文案的静态方法。

import Foundation

/// Chinese日期Text枚举 作为共享界面层里的能力或分类定义。
/// 负责描述共享布局与通用界面能力过程中会用到的状态、分类或分支。
enum ChineseDateText {
    static func fullDate(_ date: Date) -> String {
        let year = Calendar.current.component(.year, from: date)
        let month = Calendar.current.component(.month, from: date)
        let day = Calendar.current.component(.day, from: date)
        return String(localized: "\(year)年\(month)月\(day)日")
    }

    static func writtenMonthDay(_ date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        let day = Calendar.current.component(.day, from: date)
        return String(localized: "\(writtenNumber(month))月\(writtenNumber(day))日")
    }

    static func writtenMonth(_ date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        return String(localized: "\(writtenNumber(month))月")
    }

    static func writtenDay(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return String(localized: "\(writtenNumber(day))日")
    }

    static func compactMonthDay(_ date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        let day = Calendar.current.component(.day, from: date)
        return String(localized: "\(month)月\(day)日")
    }

    static func compactMonth(_ date: Date) -> String {
        let year = Calendar.current.component(.year, from: date)
        let month = Calendar.current.component(.month, from: date)
        return String(localized: "\(year)年\(month)月")
    }

    static func compactDay(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return String(localized: "\(day)日")
    }

    static func shortWeekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "E"
        return formatter.string(from: date).replacingOccurrences(of: "周", with: "")
    }

    private static func writtenNumber(_ value: Int) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

        switch value {
        case ..<0:
            return "\(value)"
        case 0...10:
            return value == 10 ? "十" : digits[value]
        case 11...19:
            return "十" + digits[value - 10]
        case 20...99:
            let tens = value / 10
            let ones = value % 10
            return digits[tens] + "十" + (ones == 0 ? "" : digits[ones])
        default:
            return "\(value)"
        }
    }
}
