import Foundation

// MARK: Items

public enum GrammarTopic: String, Codable, CaseIterable, Sendable, Identifiable {
    case adjectiveEndings, konjunktiv, passive, cases, prepositions

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .adjectiveEndings: "Adjective endings"
        case .konjunktiv: "Konjunktiv I & II"
        case .passive: "Passive & participles"
        case .cases: "Cases & prepositions"
        case .prepositions: "Verbs with prepositions"
        }
    }

    public var summary: String {
        switch self {
        case .adjectiveEndings: "der/ein/no article × case × gender, generated from everyday noun–adjective pairs."
        case .konjunktiv: "Indirect speech, wishes, hypotheticals and the past subjunctive."
        case .passive: "Vorgangs- and Zustandspassiv, passive with modals, participial phrases."
        case .cases: "Two-way and genitive prepositions, n-declension, case after verbs."
        case .prepositions: "Fixed prepositions after verbs, adjectives and nouns, plus da- and wo-words."
        }
    }

    /// The authored bank's file name, or nil for a generated topic.
    var bankFile: String? {
        switch self {
        case .adjectiveEndings: nil
        case .konjunktiv: "grammar-konjunktiv"
        case .passive: "grammar-passive"
        case .cases: "grammar-cases"
        case .prepositions: "grammar-prepositions"
        }
    }
}

/// One exercise: a gap to type, or a choice between options.
public struct GrammarItem: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case gap                        // type the missing part
        case choice(options: [String])  // pick one (the answer is among the options)
    }

    /// Stable across devices and launches, so progress can follow it.
    public var id: String
    public var topic: GrammarTopic
    public var kind: Kind
    /// The sentence, with "___" where the answer goes (for a gap).
    public var prompt: String
    /// Every accepted answer; the first is the one shown as correct.
    public var answers: [String]
    /// The rule, shown after answering.
    public var explanation: String

    public init(id: String, topic: GrammarTopic, kind: Kind, prompt: String, answers: [String], explanation: String) {
        self.id = id
        self.topic = topic
        self.kind = kind
        self.prompt = prompt
        self.answers = answers
        self.explanation = explanation
    }

    /// The prompt with the gap filled in with the main answer.
    public var solved: String {
        guard case .gap = kind, let a = answers.first else { return prompt }
        // The hint after a gap ("___ (anrufen)") goes once the answer is in.
        return prompt.replacingOccurrences(of: #"___\s*\([^)]*\)"#, with: a, options: .regularExpression)
            .replacingOccurrences(of: "___", with: a)
    }

    public func isCorrect(_ response: String) -> Bool {
        let r = Self.normalize(response)
        guard !r.isEmpty else { return false }
        return answers.contains { Self.normalize($0) == r }
    }

    /// Case, spacing and final punctuation don't count; spelling (ä, ß) does.
    static func normalize(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "’", with: "'")
            .lowercased()
    }
}

// MARK: Scheduling

/// One answer to a grammar item. Appended only, like vocab reviews.
public struct GrammarAttemptEvent: Equatable, Sendable {
    public var correct: Bool
    public var at: Date
    /// Answered right with a hint.
    public var hinted: Bool
    public init(correct: Bool, at: Date, hinted: Bool = false) {
        self.correct = correct
        self.at = at
        self.hinted = hinted
    }
}

/// Leitner boxes: right moves an item up a box and spaces it out; wrong sends it
/// back to box 1, due again right away, so a mistake comes back in the next session.
public struct LeitnerState: Equatable, Sendable {
    public var box = 0
    public var due: Date
    public var attempts = 0
    public var misses = 0

    public static let intervals: [Double] = [0, 1, 3, 7, 16, 35]   // days, by box

    public init(due: Date) { self.due = due }

    /// A right answer with a hint keeps the item in its box (at least box 1) and
    /// brings it back tomorrow, instead of moving it up.
    public func next(correct: Bool, at: Date, hinted: Bool = false) -> LeitnerState {
        var n = self
        n.attempts += 1
        if correct, hinted {
            n.box = max(box, 1)
            n.due = at + 86_400
            return n
        }
        if correct {
            n.box = min(box + 1, Self.intervals.count - 1)
        } else {
            n.misses += 1
            n.box = 1
        }
        n.due = correct ? at + Self.intervals[n.box] * 86_400 : at
        return n
    }

    public static func replay(_ events: [GrammarAttemptEvent]) -> LeitnerState? {
        let sorted = events.sorted { $0.at < $1.at }
        guard let first = sorted.first else { return nil }
        return sorted.reduce(LeitnerState(due: first.at)) { $0.next(correct: $1.correct, at: $1.at, hinted: $1.hinted) }
    }
}

public enum GrammarSession {
    /// A session: items due again first (missed ones before the rest), then new ones.
    public static func build(topic: GrammarTopic, progress: [String: LeitnerState], now: Date = .now,
                             size: Int = 10, seed: UInt64 = UInt64.random(in: 0...UInt64.max),
                             nouns: [AdjNoun] = GrammarBank.nouns()) -> [GrammarItem] {
        var rng = SeededRandom(seed: seed)
        let due = progress.filter { $0.value.due <= now }
            .sorted { ($0.value.box, $0.value.due) < ($1.value.box, $1.value.due) }
            .compactMap { GrammarBank.item(id: $0.key, nouns: nouns) }
            .filter { $0.topic == topic }
        var out = Array(due.prefix(size))
        guard out.count < size else { return out }

        let seen = Set(progress.keys)
        if topic == .adjectiveEndings {
            var tries = 0
            while out.count < size, tries < size * 20 {
                tries += 1
                if let item = AdjectiveEndings.random(nouns: nouns, using: &rng),
                   !seen.contains(item.id), !out.contains(where: { $0.id == item.id }) {
                    out.append(item)
                }
            }
        } else {
            let fresh = GrammarBank.items(topic: topic).filter { !seen.contains($0.id) }
            out += fresh.shuffled(using: &rng).prefix(size - out.count)
        }
        return out
    }
}

/// Small deterministic generator, so tests can pin a session.
public struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    public mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}

// MARK: Banks

public enum GrammarBank {
    /// Authored items of a topic, from `grammar-<topic>.tsv`.
    public static func items(topic: GrammarTopic) -> [GrammarItem] {
        guard let file = topic.bankFile,
              let url = Bundle.module.url(forResource: file, withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text, topic: topic)
    }

    /// Columns: id, kind (g = gap, c = choice), prompt, answers (| separated),
    /// options (| separated, choices only), explanation.
    public static func parse(_ text: String, topic: GrammarTopic) -> [GrammarItem] {
        text.split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 6, !f[0].isEmpty else { return nil }
            let answers = f[3].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            let kind: GrammarItem.Kind = f[1] == "c"
                ? .choice(options: f[4].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) })
                : .gap
            return GrammarItem(id: "\(topic.rawValue):\(f[0])", topic: topic, kind: kind,
                               prompt: f[2], answers: answers, explanation: f[5])
        }
    }

    /// Any item by id: authored ones from their bank, generated ones rebuilt from the id.
    public static func item(id: String, nouns: [AdjNoun] = nouns()) -> GrammarItem? {
        if id.hasPrefix("adj:") { return AdjectiveEndings.item(id: id, nouns: nouns) }
        guard let topic = GrammarTopic(rawValue: String(id.prefix { $0 != ":" })) else { return nil }
        return items(topic: topic).first { $0.id == id }
    }

    /// The curated noun + adjective pairs (`grammar-adjectives.tsv`), minus
    /// n-declension nouns (der Kollege → den Kollegen), whose own endings would
    /// muddy an adjective-ending drill.
    public static func nouns() -> [AdjNoun] {
        guard let url = Bundle.module.url(forResource: "grammar-adjectives", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line -> AdjNoun? in
            guard !line.hasPrefix("#") else { return nil }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, let g = Gender(article: f[0]) else { return nil }
            let word = StarterWord(partOfSpeech: .noun, gender: g, lemma: f[1],
                                   plural: f[2].isEmpty ? nil : f[2], english: "", example: nil, level: "grammar")
            let adjectives = f[3].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard !AdjectiveEndings.isWeakNoun(word), !adjectives.isEmpty else { return nil }
            return AdjNoun(word: word, adjectives: adjectives)
        }
    }
}
