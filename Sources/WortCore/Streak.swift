import Foundation

/// Days practiced in a row, from the answer logs (vocab reviews and grammar
/// attempts). Nothing stored: recomputed from the same history that syncs.
public enum Streak {
    public struct Summary: Equatable, Sendable {
        /// Days in a row up to today, or up to yesterday if today hasn't been
        /// practiced yet (the streak isn't broken until today is over).
        public var current: Int
        public var longest: Int
        public var practicedToday: Bool
        /// Answers per day (start of day), for the calendar.
        public var perDay: [Date: Int]
    }

    public static func summary(_ dates: [Date], today: Date = .now, calendar: Calendar = .current) -> Summary {
        var perDay: [Date: Int] = [:]
        for d in dates { perDay[calendar.startOfDay(for: d), default: 0] += 1 }
        let todayStart = calendar.startOfDay(for: today)
        let practicedToday = perDay[todayStart] != nil

        func dayBefore(_ d: Date) -> Date { calendar.date(byAdding: .day, value: -1, to: d)! }
        var current = 0
        var day = practicedToday ? todayStart : dayBefore(todayStart)
        while perDay[day] != nil {
            current += 1
            day = dayBefore(day)
        }

        var longest = 0, run = 0
        var previous: Date?
        for d in perDay.keys.sorted() {
            if let p = previous, calendar.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            longest = max(longest, run)
            previous = d
        }
        return Summary(current: current, longest: longest, practicedToday: practicedToday, perDay: perDay)
    }
}

/// Checking what was typed against what was spoken, word by word.
public enum Dictation {
    public struct Word: Equatable, Sendable {
        public var text: String
        /// Right, or missing/misspelled.
        public var ok: Bool
    }

    /// Lowercased, punctuation off; umlauts and ß count ("schon" ≠ "schön").
    static func normalize(_ word: Substring) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
            .trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }

    /// The expected words, each marked right if it was typed (in order; a
    /// longest-common-subsequence match, so one missed word doesn't throw off
    /// the rest).
    public static func compare(expected: String, typed: String) -> [Word] {
        let exp = expected.split(whereSeparator: \.isWhitespace)
        let a = exp.map(normalize)
        let b = typed.split(whereSeparator: \.isWhitespace).map(normalize).filter { !$0.isEmpty }
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [Word] = []
        var i = 0, j = 0
        while i < a.count {
            if j < b.count, a[i] == b[j] {
                out.append(Word(text: String(exp[i]), ok: true)); i += 1; j += 1
            } else if j < b.count, lcs[i][j + 1] > lcs[i + 1][j] {
                j += 1          // an extra typed word
            } else {
                out.append(Word(text: String(exp[i]), ok: false)); i += 1
            }
        }
        return out
    }

    /// Every word right and nothing extra.
    public static func isCorrect(expected: String, typed: String) -> Bool {
        let typedCount = typed.split(whereSeparator: \.isWhitespace).map(normalize).filter { !$0.isEmpty }.count
        let words = compare(expected: expected, typed: typed)
        return words.allSatisfy(\.ok) && typedCount == words.count
    }
}
