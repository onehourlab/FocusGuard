import Foundation

/// 端末のカレンダー上の「1日」。日付が変わったら当日の集計をリセットするための単位。
public struct DayKey: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public func startDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        let base = startDate(calendar: calendar)
        let moved = calendar.date(byAdding: .day, value: days, to: base) ?? base
        return DayKey(moved, calendar: calendar)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// 画面表示用（例: 11/20）
    public var shortLabel: String { "\(month)/\(day)" }
}
