import Foundation

/// What the widget shows, written by the app into the App Group. The widget never
/// opens the database. Cards become due while the app is closed, so this keeps
/// the due *dates*, not a count, and the widget counts what's due at each hour.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// When each reviewed card is next due, soonest first.
    public var dueDates: [Date]
    /// New cards still to meet today, as of `updatedAt`.
    public var newToday: Int
    public var streak: Int
    public var practicedToday: Bool
    public var updatedAt: Date

    public init(dueDates: [Date], newToday: Int, streak: Int, practicedToday: Bool, updatedAt: Date) {
        self.dueDates = dueDates.sorted()
        self.newToday = newToday
        self.streak = streak
        self.practicedToday = practicedToday
        self.updatedAt = updatedAt
    }

    public static let key = "widgetSnapshot"

    /// Cards to review at `date`: those due by then, plus today's new ones if
    /// it's still the day the snapshot was taken (new ones reset at midnight).
    public func due(at date: Date, calendar: Calendar = .current) -> Int {
        let reviews = dueDates.prefix { $0 <= date }.count
        return reviews + (calendar.isDate(date, inSameDayAs: updatedAt) ? newToday : 0)
    }

    /// The streak as of `date`: still alive the day after practice, gone after that.
    public func streak(at date: Date, calendar: Calendar = .current) -> (days: Int, practicedToday: Bool) {
        if calendar.isDate(date, inSameDayAs: updatedAt) { return (streak, practicedToday) }
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: updatedAt)!
        if calendar.isDate(date, inSameDayAs: dayAfter), practicedToday { return (streak, false) }
        return (0, false)
    }

    /// The next time a card becomes due after `date`, for "next in 2 h".
    public func nextDue(after date: Date) -> Date? { dueDates.first { $0 > date } }

    public func encoded() -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        return try? e.encode(self)
    }

    public static func decode(_ data: Data?) -> WidgetSnapshot? {
        guard let data else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(WidgetSnapshot.self, from: data)
    }
}
