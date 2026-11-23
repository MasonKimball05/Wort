import Foundation

// MARK: Hints

/// What a hint shows, per kind of question. A hint gives part of the way, never
/// the whole answer.
public enum Hints {
    /// "H _ _ _ _ _ _ _": the first `reveal` letters of each word, the rest as
    /// blanks, so the length shows too. Articles count as words.
    public static func letters(_ answer: String, reveal: Int = 1) -> String {
        answer.split(separator: " ").map { word in
            word.enumerated().map { i, c in
                i < reveal || !c.isLetter ? String(c) : "_"
            }.joined(separator: " ")
        }.joined(separator: "   ")
    }

    /// How a plural is formed: "-en", "¨-er", "¨", "no change", "-s".
    public static func pluralPattern(lemma: String, plural: String) -> String {
        if plural == lemma { return "same as the singular" }
        let umlauts: [Character: Character] = ["a": "ä", "o": "ö", "u": "ü", "A": "Ä", "O": "Ö", "U": "Ü"]
        func strip(_ s: String) -> String {
            String(s.map { c in umlauts.first { $0.value == c }?.key ?? c })
        }
        let hasUmlaut = strip(plural) != plural && strip(lemma) == lemma
        let base = strip(plural)
        guard base.hasPrefix(lemma) else { return hasUmlaut ? "with an umlaut" : "irregular" }
        let ending = String(base.dropFirst(lemma.count))
        switch (hasUmlaut, ending.isEmpty) {
        case (true, true): return "¨ (umlaut, no ending)"
        case (true, false): return "¨ + -\(ending)"
        case (false, true): return "same as the singular"
        case (false, false): return "-\(ending)"
        }
    }

    /// The suffix rule for a noun's gender, if one applies: "-ung → die".
    public static func genderRule(_ lemma: String) -> String? {
        guard let (suffix, g) = GenderGuess.rule(lemma) else { return nil }
        return "Nouns in -\(suffix) are usually \(g.article)"
    }

    /// The preposition without its case: "auf + Akk." → "auf + ?".
    public static func preposition(_ government: String) -> String {
        let prep = government.split(separator: "+").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? government
        return "\(prep) + ?"
    }

    /// Which auxiliary the Perfekt takes, from "verzieh, hat verziehen".
    public static func auxiliary(_ forms: String) -> String? {
        let words = forms.lowercased().split(whereSeparator: { !$0.isLetter })
        if words.contains("ist") { return "Perfekt with „ist“" }
        if words.contains("hat") { return "Perfekt with „hat“" }
        return nil
    }
}

extension GrammarItem {
    /// For a gap: the first letter and the length of the answer; for adjective
    /// endings (one or two letters, so letters would give it away) the rule that
    /// decides it. For a choice: nil (the hint removes an option instead).
    public var hint: String? {
        guard case .gap = kind, let answer = answers.first else { return nil }
        if topic == .adjectiveEndings {
            return explanation.components(separatedBy: "→").first?.trimmingCharacters(in: .whitespaces)
        }
        return Hints.letters(answer)
    }

    /// A wrong option to strike out as a choice hint, the same one each time.
    public func optionToRemove(keeping removed: Set<String> = []) -> String? {
        guard case .choice(let options) = kind else { return nil }
        let wrong = options.filter { !answers.contains($0) && !removed.contains($0) }
        guard wrong.count > 1 else { return nil }     // always leave a real choice
        var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: id.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) }))
        return wrong.randomElement(using: &rng)
    }
}

extension Scheduler {
    /// The rating a hinted answer counts as. In review a hint turns Good or Easy
    /// into Hard: the card comes back sooner and gets a little harder. While
    /// learning, Hard never moves a card on, so a hint there only turns Easy
    /// into Good. A card you always need a hint for still graduates.
    public static func rating(_ r: Rating, hinted: Bool, phase: CardState.Phase) -> Rating {
        guard hinted else { return r }
        switch phase {
        case .review: return r == .good || r == .easy ? .hard : r
        case .new, .learning, .relearning: return r == .easy ? .good : r
        }
    }
}

extension GenderGuess {
    /// The suffix rule behind `guess`, for showing it as a hint.
    public static func rule(_ word: String) -> (suffix: String, gender: Gender)? {
        let w = word.lowercased()
        let rules: [(String, Gender)] =
            feminine.map { ($0, .feminine) } + neuter.map { ($0, .neuter) } + masculine.map { ($0, .masculine) }
        return rules.filter { w.hasSuffix($0.0) && w.count > $0.0.count + 1 }
            .max { $0.0.count < $1.0.count }.map { (suffix: $0.0, gender: $0.1) }
    }
}

// MARK: Difficulty

/// Eases off when you're struggling and steps up when it's going well, within a
/// practice round. Levels 1 (easy) to 3 (hard). It changes one step at a time,
/// only after a few answers since the last change, a hinted right answer counts
/// as half, and a retry of the same item isn't counted twice.
public struct Tuner: Equatable, Sendable {
    public enum Change: Equatable, Sendable { case easier, harder }

    public private(set) var level: Int
    var recent: [Double] = []
    var sinceChange = 0
    var counted: Set<String> = []

    /// Answers needed since the last change before it can change again.
    public static let settle = 3

    public init(level: Int) { self.level = min(3, max(1, level)) }

    public mutating func record(id: String, correct: Bool, hinted: Bool) -> Change? {
        guard counted.insert(id).inserted else { return nil }
        recent.append(correct ? (hinted ? 0.5 : 1) : 0)
        sinceChange += 1
        guard sinceChange >= Self.settle else { return nil }
        let window = recent.suffix(min(5, sinceChange))
        let average = window.reduce(0, +) / Double(window.count)
        if average < 0.5, level > 1 {
            level -= 1; sinceChange = 0
            return .easier
        }
        if average >= 0.9, level < 3 {
            level += 1; sinceChange = 0
            return .harder
        }
        return nil
    }

    /// Where to start a round, from the last answers on this topic (oldest
    /// first): so a round picks up where the last ones left off, on any device.
    public static func startLevel(_ results: [(correct: Bool, hinted: Bool)]) -> Int {
        let last = results.suffix(12)
        guard last.count >= 4 else { return 2 }
        let score = last.map { $0.correct ? ($0.hinted ? 0.5 : 1) : 0 }.reduce(0, +) / Double(last.count)
        return score >= 0.85 ? 3 : score >= 0.6 ? 2 : 1
    }
}

extension AdjectiveEndings {
    /// How hard a combination is: the hardest of its parts. After der/dieser in
    /// Nominativ or Akkusativ singular is 1; ein-words, Dativ or plural 2; no
    /// article or Genitiv 3.
    static func difficulty(_ det: Determiner, _ c: Case, _ s: Slot) -> Int {
        let pattern = det.pattern == .weak ? 1 : det.pattern == .mixed ? 2 : 3
        let kase = c == .nom || c == .akk ? 1 : c == .dat ? 2 : 3
        return max(pattern, kase, s == .pl ? 2 : 1)
    }

    /// The difficulty of an item, from its id.
    public static func difficulty(id: String) -> Int? {
        let f = id.split(separator: ":").map(String.init)
        guard f.count == 7, let det = determiners.first(where: { $0.key == f[1] }),
              let c = Case(rawValue: f[2]), let s = Slot(rawValue: f[3]) else { return nil }
        return difficulty(det, c, s)
    }

    /// A random item at `level`, or easier if none turns up at it.
    public static func random<R: RandomNumberGenerator>(nouns: [AdjNoun], level: Int, excluding: Set<String>,
                                                        using rng: inout R) -> GrammarItem? {
        var fallback: GrammarItem?
        for _ in 0..<200 {
            guard let item = random(nouns: nouns, using: &rng), !excluding.contains(item.id),
                  let d = difficulty(id: item.id) else { continue }
            if d == level { return item }
            if d < level, fallback == nil { fallback = item }
        }
        return fallback
    }
}

extension GrammarSession {
    /// The next new item for a round at `level`. Adjective endings are generated
    /// at that difficulty. The written banks have no difficulty of their own, so
    /// the level picks the format: easy prefers multiple choice, hard prefers
    /// typing the answer. Nil when the topic has nothing new left.
    public static func fresh<R: RandomNumberGenerator>(topic: GrammarTopic, level: Int, excluding: Set<String>,
                                                       nouns: [AdjNoun] = GrammarBank.nouns(),
                                                       using rng: inout R) -> GrammarItem? {
        if topic == .adjectiveEndings {
            return AdjectiveEndings.random(nouns: nouns, level: level, excluding: excluding, using: &rng)
        }
        let unseen = GrammarBank.items(topic: topic).filter { !excluding.contains($0.id) }
        func isChoice(_ i: GrammarItem) -> Bool { if case .choice = i.kind { return true }; return false }
        let preferred: [GrammarItem]
        switch level {
        case 1: preferred = unseen.filter(isChoice)
        case 3: preferred = unseen.filter { !isChoice($0) }
        default: preferred = unseen
        }
        return (preferred.isEmpty ? unseen : preferred).randomElement(using: &rng)
    }

    /// Due items only (missed ones first), for a round that fills the rest with
    /// `fresh` as it goes.
    public static func due(topic: GrammarTopic, progress: [String: LeitnerState], now: Date = .now,
                           size: Int = 10, nouns: [AdjNoun] = GrammarBank.nouns()) -> [GrammarItem] {
        let ids = progress.filter { $0.value.due <= now }
            .sorted { ($0.value.box, $0.value.due) < ($1.value.box, $1.value.due) }
            .map(\.key)
        let items = GrammarBank.items(ids: ids)
        return Array(ids.compactMap { items[$0] }.filter { $0.topic == topic }.prefix(size))
    }
}
