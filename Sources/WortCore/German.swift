import Foundation

/// Grammatical gender of a German noun, and the article that goes with it.
public enum Gender: String, Codable, CaseIterable, Sendable {
    case masculine = "m", feminine = "f", neuter = "n"

    /// Nominative singular definite article.
    public var article: String {
        switch self {
        case .masculine: "der"
        case .feminine: "die"
        case .neuter: "das"
        }
    }

    public init?(article: String) {
        switch article.lowercased() {
        case "der": self = .masculine
        case "die": self = .feminine
        case "das": self = .neuter
        default: return nil
        }
    }
}

public enum PartOfSpeech: String, Codable, CaseIterable, Sendable {
    case noun, verb, adjective, adverb, phrase, other
}

/// What the person typed, shared or saved, split into an optional article and the word.
///
///     "das Buch"   → (.neuter, "Buch")
///     "Buch"       → (nil, "Buch")
///     "  die  Zeitung " → (.feminine, "Zeitung")
public struct ParsedInput: Equatable, Sendable {
    public var gender: Gender?
    public var word: String

    public init(_ raw: String) {
        let parts = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count == 2, let g = Gender(article: parts[0]) {
            gender = g
            word = parts[1]
        } else {
            gender = nil
            word = parts.joined(separator: " ")
        }
        word = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?\"'„“”‚‘’()[]«»"))
    }

    /// German nouns are capitalised, so a capital first letter is a (weak) hint.
    public var looksLikeNoun: Bool { word.first?.isUppercase ?? false }
}

/// Suffix rules for guessing a noun's gender when no dictionary entry is found.
/// Only the reliable ones; anything else returns nil rather than a coin flip.
public enum GenderGuess {
    static let feminine = ["ung", "heit", "keit", "schaft", "ion", "tät", "ität", "ik", "ur", "enz", "anz", "ei", "ie"]
    static let neuter = ["chen", "lein", "ment", "tum", "um", "ma"]
    static let masculine = ["ling", "ismus", "ist", "or", "eur", "ant", "ent"]

    /// The guess for `word`, or nil if no rule applies.
    public static func guess(_ word: String) -> Gender? {
        let w = word.lowercased()
        // Longest suffix wins, so "-ität" beats "-tät" and "-ismus" beats "-us".
        let rules: [(String, Gender)] =
            feminine.map { ($0, .feminine) } + neuter.map { ($0, .neuter) } + masculine.map { ($0, .masculine) }
        return rules.filter { w.hasSuffix($0.0) && w.count > $0.0.count + 1 }
            .max { $0.0.count < $1.0.count }?.1
    }

    /// A compound noun takes the gender of its last part: "Zeitungsartikel" → "Artikel".
    /// Returns the longest known noun that `word` ends with, from `known`.
    public static func compoundHead(of word: String, known: Set<String>) -> String? {
        let lower = word.lowercased()
        var best: String?
        for noun in known where noun.count >= 3 && noun.count < word.count {
            if lower.hasSuffix(noun.lowercased()), noun.count > (best?.count ?? 0) { best = noun }
        }
        return best
    }
}
