import Foundation

/// What you keep getting wrong, read off the answer logs (vocab reviews and
/// grammar attempts). Nothing is stored: it's recomputed from the same append-only
/// history that drives scheduling, so it syncs for free.
public enum Trouble {
    /// One answer, right or wrong. For vocab, "Again" is wrong; Hard, Good and Easy are right.
    public struct Result: Equatable, Sendable {
        public var correct: Bool
        public var at: Date
        /// Right, but with a hint: not a miss, but not a clean answer either.
        public var hinted: Bool
        public init(correct: Bool, at: Date, hinted: Bool = false) {
            self.correct = correct
            self.at = at
            self.hinted = hinted
        }
        var clean: Bool { correct && !hinted }
    }

    public struct Summary: Equatable, Sendable {
        /// Misses among the recent answers (the last `window`).
        public var misses: Int
        /// Right answers that needed a hint, among the recent ones.
        public var hints: Int = 0
        /// How many recent answers that's out of.
        public var recent: Int
        /// The last miss or hinted answer.
        public var lastMissed: Date
    }

    /// How many recent answers count.
    public static let window = 8

    /// A trouble spot, or nil if it isn't one. It is when the latest answer was
    /// wrong (not counting a very first answer: missing a word the first time you
    /// meet it is normal), or when it was missed twice or more recently and hasn't
    /// been answered right three times running since. One old miss followed by
    /// right answers is not trouble.
    public static func summarize(_ results: [Result], window: Int = window) -> Summary? {
        let sorted = results.sorted { $0.at < $1.at }
        guard let last = sorted.last else { return nil }
        let recent = sorted.suffix(window)
        let misses = recent.filter { !$0.correct }.count
        let hints = recent.filter { $0.correct && $0.hinted }.count
        guard misses + hints > 0, let lastMissed = recent.last(where: { !$0.clean })?.at else { return nil }
        // Only clean answers clear a trouble spot: leaning on hints keeps it.
        let streak = sorted.reversed().prefix { $0.clean }.count
        let lastWrong = !last.correct && sorted.count > 1
        guard lastWrong || (misses + hints >= 2 && streak < 3) else { return nil }
        return Summary(misses: misses, hints: hints, recent: recent.count, lastMissed: lastMissed)
    }

    /// Worst first: more recent misses, then the most recently missed.
    public static func ranked<ID>(_ items: [ID: [Result]]) -> [(id: ID, summary: Summary)] {
        items.compactMap { id, results in summarize(results).map { (id: id, summary: $0) } }
            .sorted { a, b in
                let wa = 2 * a.summary.misses + a.summary.hints, wb = 2 * b.summary.misses + b.summary.hints
                if wa != wb { return wa > wb }
                return a.summary.lastMissed > b.summary.lastMissed
            }
    }

    /// A rule you get wrong often, across every exercise that tests it.
    public struct WeakRule: Equatable, Sendable {
        public var rule: String
        public var right: Int
        public var total: Int
        public var accuracy: Int { total == 0 ? 0 : right * 100 / total }
    }

    /// Adjective-ending rules (case + what comes before the adjective, e.g.
    /// "Dativ · nach ein-Wort") right less than `below` percent of the time, over
    /// at least `minimum` answers. Weakest first.
    public static func weakRules(_ attempts: [(itemID: String, correct: Bool)],
                                 minimum: Int = 3, below: Int = 75) -> [WeakRule] {
        var tally: [String: (right: Int, total: Int)] = [:]
        for a in attempts {
            guard let rule = AdjectiveEndings.rule(id: a.itemID) else { continue }
            tally[rule, default: (0, 0)].total += 1
            if a.correct { tally[rule, default: (0, 0)].right += 1 }
        }
        return tally.map { WeakRule(rule: $0.key, right: $0.value.right, total: $0.value.total) }
            .filter { $0.total >= minimum && $0.accuracy < below }
            .sorted { ($0.accuracy, -$0.total) < ($1.accuracy, -$1.total) }
    }
}

extension AdjectiveEndings {
    /// The rule an adjective-ending item tests, from its id: "Dativ · nach ein-Wort".
    public static func rule(id: String) -> String? {
        let f = id.split(separator: ":").map(String.init)
        guard f.count == 7, f[0] == "adj",
              let det = determiners.first(where: { $0.key == f[1] }),
              let c = Case(rawValue: f[2]) else { return nil }
        let pattern: String
        switch det.pattern {
        case .weak: pattern = "nach der/dieser"
        case .mixed: pattern = "nach ein/mein/kein"
        case .strong: pattern = "ohne Artikel"
        }
        return "\(c.label) · \(pattern)"
    }
}

extension GrammarBank {
    /// Many items by id, reading each bank and the noun list once (`item(id:)`
    /// re-reads them per call, too slow in a loop).
    public static func items(ids: [String]) -> [String: GrammarItem] {
        let nouns = nouns()
        var authored: [String: GrammarItem] = [:]
        for topic in GrammarTopic.allCases where topic.bankFile != nil {
            for item in items(topic: topic) { authored[item.id] = item }
        }
        var out: [String: GrammarItem] = [:]
        for id in ids {
            if id.hasPrefix("adj:") {
                out[id] = AdjectiveEndings.item(id: id, nouns: nouns)
            } else {
                out[id] = authored[id]
            }
        }
        return out
    }
}
