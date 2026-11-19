import Foundation

/// A word from a bundled starter deck.
public struct StarterWord: Equatable, Sendable {
    public var partOfSpeech: PartOfSpeech
    public var gender: Gender?
    public var lemma: String
    public var plural: String?
    public var english: String
    public var example: String?
    public var level: String
    /// Leute, Eltern: no singular, so no gender.
    public var pluralOnly = false
    /// The preposition and case a verb, adjective or phrase takes: "auf + Akk.".
    public var government: String?
    /// Principal parts of a strong verb: "verzieh, hat verziehen".
    public var forms: String?

    /// Identifies a word across devices, so importing a deck twice (or on two
    /// devices that then sync) can be deduplicated: "n:Buch", "n:See:f", "v:gehen".
    public var key: String { WordKey.make(lemma: lemma, partOfSpeech: partOfSpeech, gender: gender, government: government) }
}

public enum WordKey {
    public static func make(lemma: String, partOfSpeech: PartOfSpeech, gender: Gender?, government: String? = nil) -> String {
        var key = "\(partOfSpeech.rawValue.prefix(1)):\(lemma.precomposedStringWithCanonicalMapping)"
        // Same spelling, different noun (der See / die See) needs its own key.
        if partOfSpeech == .noun, let g = gender { key += ":\(g.rawValue)" }
        // ...and so does a verb with a different preposition (bestehen auf / bestehen in).
        if partOfSpeech != .noun, let gov = government, !gov.isEmpty { key += ":\(gov)" }
        return key
    }
}

public enum StarterDeck {
    /// Levels with a bundled deck, easiest first, and what each one is for.
    public static let levels = ["A1", "C1"]
    public static let descriptions = [
        "A1": "Beginner: everyday words, all with articles, plurals and example sentences.",
        "C1": "Advanced: verbs with fixed prepositions, noun-verb phrases, false friends, article-changes-meaning nouns, idioms and rarer strong verbs.",
    ]

    /// The words of a level, read from `starter-<level>.tsv`.
    public static func words(level: String) -> [StarterWord] {
        guard let url = Bundle.module.url(forResource: "starter-\(level.lowercased())", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text, level: level)
    }

    public static func parse(_ text: String, level: String) -> [StarterWord] {
        text.split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            // 6 columns, or 8 with government and verb forms (the C1 deck).
            guard f.count == 6 || f.count == 8 else { return nil }
            let pos: PartOfSpeech = switch f[0] {
            case "n": .noun
            case "v": .verb
            case "a": .adjective
            case "d": .adverb
            case "p": .phrase
            default: .other
            }
            // Article column: der/die/das, or "pl" for plural-only nouns.
            var word = StarterWord(partOfSpeech: pos, gender: Gender(article: f[1]), lemma: f[2],
                                   plural: f[3].isEmpty ? nil : f[3], english: f[4],
                                   example: f[5].isEmpty ? nil : f[5], level: level)
            word.pluralOnly = f[1] == "pl"
            if f.count == 8 {
                word.government = f[6].isEmpty ? nil : f[6]
                word.forms = f[7].isEmpty ? nil : f[7]
            }
            return word
        }
    }

    /// Nouns and their genders, for the compound fallback in `WordLookup`.
    public static func knownNouns() -> [String: Gender] {
        var out: [String: Gender] = [:]
        for level in levels {
            for w in words(level: level) where w.partOfSpeech == .noun {
                if let g = w.gender { out[w.lemma] = g }
            }
        }
        return out
    }
}
