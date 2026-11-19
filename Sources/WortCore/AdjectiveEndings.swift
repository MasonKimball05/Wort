import Foundation

/// Adjective-ending exercises, generated: a determiner, a case, a noun from the
/// decks and an adjective make a phrase like "ohne den alt___ Tisch" (→ -en).
/// Every combination is checked against the ending tables below, so the supply is
/// endless and the answers are always right.
/// A noun and the adjectives that naturally go with it (starker Kaffee, eine
/// schwierige Frage), so generated phrases are real German, not "a light daughter".
public struct AdjNoun: Equatable, Sendable {
    public var word: StarterWord
    public var adjectives: [String]
}

public enum AdjectiveEndings {

    public enum Case: String, CaseIterable, Sendable {
        case nom, akk, dat, gen
        var label: String {
            switch self {
            case .nom: "Nominativ"
            case .akk: "Akkusativ"
            case .dat: "Dativ"
            case .gen: "Genitiv"
            }
        }
    }

    /// m, f, n singular, or plural.
    public enum Slot: String, CaseIterable, Sendable {
        case m, f, n, pl
        var label: String {
            switch self {
            case .m: "maskulin"
            case .f: "feminin"
            case .n: "neutral"
            case .pl: "Plural"
            }
        }
        init(_ g: Gender) {
            switch g {
            case .masculine: self = .m
            case .feminine: self = .f
            case .neuter: self = .n
            }
        }
    }

    /// The three declension patterns, by what comes before the adjective.
    public enum Pattern: Sendable {
        case weak     // after der, dieser…: the article shows the case
        case mixed    // after ein, mein, kein…: strong where ein has no ending
        case strong   // no article: the adjective shows the case
        var label: String {
            switch self {
            case .weak: "nach bestimmtem Artikel (der, dieser)"
            case .mixed: "nach ein-Wort (ein, mein, kein)"
            case .strong: "ohne Artikel"
            }
        }
    }

    /// Ending tables: [case][slot].
    static let endings: [Pattern: [Case: [Slot: String]]] = [
        .weak: [
            .nom: [.m: "e", .f: "e", .n: "e", .pl: "en"],
            .akk: [.m: "en", .f: "e", .n: "e", .pl: "en"],
            .dat: [.m: "en", .f: "en", .n: "en", .pl: "en"],
            .gen: [.m: "en", .f: "en", .n: "en", .pl: "en"],
        ],
        .mixed: [
            .nom: [.m: "er", .f: "e", .n: "es", .pl: "en"],
            .akk: [.m: "en", .f: "e", .n: "es", .pl: "en"],
            .dat: [.m: "en", .f: "en", .n: "en", .pl: "en"],
            .gen: [.m: "en", .f: "en", .n: "en", .pl: "en"],
        ],
        .strong: [
            .nom: [.m: "er", .f: "e", .n: "es", .pl: "e"],
            .akk: [.m: "en", .f: "e", .n: "es", .pl: "e"],
            .dat: [.m: "em", .f: "er", .n: "em", .pl: "en"],
            .gen: [.m: "en", .f: "er", .n: "en", .pl: "er"],
        ],
    ]

    public static func ending(_ p: Pattern, _ c: Case, _ s: Slot) -> String { endings[p]![c]![s]! }

    /// Determiners and their forms: [case][slot]; nil where a determiner has no form
    /// (ein has no plural).
    struct Determiner: Sendable {
        let key: String
        let pattern: Pattern
        let forms: [Case: [Slot: String]]
    }

    static let determiners: [Determiner] = [
        Determiner(key: "der", pattern: .weak, forms: [
            .nom: [.m: "der", .f: "die", .n: "das", .pl: "die"],
            .akk: [.m: "den", .f: "die", .n: "das", .pl: "die"],
            .dat: [.m: "dem", .f: "der", .n: "dem", .pl: "den"],
            .gen: [.m: "des", .f: "der", .n: "des", .pl: "der"]]),
        Determiner(key: "dieser", pattern: .weak, forms: [
            .nom: [.m: "dieser", .f: "diese", .n: "dieses", .pl: "diese"],
            .akk: [.m: "diesen", .f: "diese", .n: "dieses", .pl: "diese"],
            .dat: [.m: "diesem", .f: "dieser", .n: "diesem", .pl: "diesen"],
            .gen: [.m: "dieses", .f: "dieser", .n: "dieses", .pl: "dieser"]]),
        Determiner(key: "ein", pattern: .mixed, forms: [
            .nom: [.m: "ein", .f: "eine", .n: "ein"],
            .akk: [.m: "einen", .f: "eine", .n: "ein"],
            .dat: [.m: "einem", .f: "einer", .n: "einem"],
            .gen: [.m: "eines", .f: "einer", .n: "eines"]]),
        Determiner(key: "mein", pattern: .mixed, forms: [
            .nom: [.m: "mein", .f: "meine", .n: "mein", .pl: "meine"],
            .akk: [.m: "meinen", .f: "meine", .n: "mein", .pl: "meine"],
            .dat: [.m: "meinem", .f: "meiner", .n: "meinem", .pl: "meinen"],
            .gen: [.m: "meines", .f: "meiner", .n: "meines", .pl: "meiner"]]),
        Determiner(key: "kein", pattern: .mixed, forms: [
            .nom: [.m: "kein", .f: "keine", .n: "kein", .pl: "keine"],
            .akk: [.m: "keinen", .f: "keine", .n: "kein", .pl: "keine"],
            .dat: [.m: "keinem", .f: "keiner", .n: "keinem", .pl: "keinen"],
            .gen: [.m: "keines", .f: "keiner", .n: "keines", .pl: "keiner"]]),
        Determiner(key: "0", pattern: .strong, forms: [
            .nom: [.m: "", .f: "", .n: "", .pl: ""],
            .akk: [.m: "", .f: "", .n: "", .pl: ""],
            .dat: [.m: "", .f: "", .n: "", .pl: ""],
            .gen: [.m: "", .f: "", .n: "", .pl: ""]]),
    ]

    /// A frame per case. Prepositions keep the meaning neutral, so any noun fits.
    static let frames: [Case: [(singular: String, plural: String)]] = [
        .nom: [("Hier ist {np}.", "Hier sind {np}."), ("Das ist {np}.", "Das sind {np}.")],
        .akk: [("Ich komme ohne {np}.", "Ich komme ohne {np}."), ("Das ist für {np}.", "Das ist für {np}.")],
        .dat: [("Ich komme mit {np}.", "Ich komme mit {np}."), ("Wir sprechen von {np}.", "Wir sprechen von {np}.")],
        .gen: [("Wir bleiben wegen {np}.", "Wir bleiben wegen {np}."), ("Trotz {np} sind wir zufrieden.", "Trotz {np} sind wir zufrieden.")],
    ]

    /// n-declension masculines change the noun itself in Akk/Dat (den Kollegen),
    /// so they're left out: mostly masculines in -e, plus a few without.
    static let weakNouns: Set<String> = ["Mensch", "Herr", "Student", "Nachbar", "Präsident", "Bär", "Held",
                                         "Fürst", "Graf", "Prinz", "Soldat", "Polizist", "Journalist", "Tourist"]

    /// Masculines in -e are n-declension (der Kollege → den Kollegen), except the
    /// ones in -ee and der Käse, which decline normally (des Kaffees, des Käses).
    public static func isWeakNoun(_ w: StarterWord) -> Bool {
        guard w.gender == .masculine else { return false }
        if weakNouns.contains(w.lemma) { return true }
        return w.lemma.hasSuffix("e") && !w.lemma.hasSuffix("ee") && w.lemma != "Käse"
    }

    /// The noun's form in a case and number. Dative plural adds -n (den Kindern)
    /// unless the plural already ends in -n or -s. Masculine and neuter genitive
    /// singular add -(e)s, which is irregular enough that those aren't generated.
    static func nounForm(_ w: StarterWord, _ c: Case, _ s: Slot) -> String? {
        if s == .pl {
            guard let p = w.plural else { return nil }
            if c == .dat, !p.hasSuffix("n"), !p.hasSuffix("s") { return p + "n" }
            return p
        }
        if c == .gen, s != .f { return nil }
        return w.lemma
    }

    static func nounKey(_ w: StarterWord) -> String { "\(w.lemma).\(w.gender?.rawValue ?? "")" }

    // MARK: Building items

    /// "adj:<determiner>:<case>:<slot>:<noun>.<gender>:<adjective>:<frame>". The gender
    /// is part of the noun key because some lemmas have two (der/das Erbe, der/die/das Band).
    public static func item(id: String, nouns: [AdjNoun]) -> GrammarItem? {
        let f = id.split(separator: ":").map(String.init)
        guard f.count == 7, f[0] == "adj",
              let det = determiners.first(where: { $0.key == f[1] }),
              let c = Case(rawValue: f[2]), let s = Slot(rawValue: f[3]),
              let pair = nouns.first(where: { nounKey($0.word) == f[4] }),
              pair.adjectives.contains(f[5]), let frameIndex = Int(f[6]) else { return nil }
        return build(det: det, c: c, s: s, noun: pair.word, adjective: f[5], frameIndex: frameIndex)
    }

    static func build(det: Determiner, c: Case, s: Slot, noun: StarterWord, adjective: String, frameIndex: Int) -> GrammarItem? {
        // No article in the singular only sounds right with a mass noun (frisches
        // Obst, mit kalter Milch); with a countable noun it needs an article.
        let isMass = noun.plural == nil
        if det.pattern == .strong, s != .pl, !isMass { return nil }
        if isMass, det.pattern != .strong || s == .pl { return nil }
        guard let article = det.forms[c]?[s],
              let nounText = nounForm(noun, c, s),
              s == .pl || Slot(noun.gender!) == s,
              let frameList = frames[c], frameList.indices.contains(frameIndex) else { return nil }
        let frame = s == .pl ? frameList[frameIndex].plural : frameList[frameIndex].singular
        let ending = ending(det.pattern, c, s)
        let np = [article, "\(adjective)___", nounText].filter { !$0.isEmpty }.joined(separator: " ")
        var prompt = frame.replacingOccurrences(of: "{np}", with: np)
        if prompt.hasPrefix("___") == false, let first = prompt.first, first.isLowercase {
            prompt = prompt.prefix(1).uppercased() + prompt.dropFirst()
        }
        let id = "adj:\(det.key):\(c.rawValue):\(s.rawValue):\(nounKey(noun)):\(adjective):\(frameIndex)"
        let explanation = "\(c.label) · \(s.label) · \(det.pattern.label) → -\(ending)"
        return GrammarItem(id: id, topic: .adjectiveEndings, kind: .gap, prompt: prompt,
                           answers: [ending, adjective + ending], explanation: explanation)
    }

    /// A random valid combination.
    public static func random<R: RandomNumberGenerator>(nouns: [AdjNoun], using rng: inout R) -> GrammarItem? {
        guard !nouns.isEmpty else { return nil }
        let countable = nouns.filter { $0.word.plural != nil }
        let mass = nouns.filter { $0.word.plural == nil }
        for _ in 0..<50 {
            let det = determiners.randomElement(using: &rng)!
            let plural = Int.random(in: 0..<4, using: &rng) == 0
            let pool = det.pattern == .strong && !plural && !mass.isEmpty ? mass : countable
            guard let pair = pool.randomElement(using: &rng) else { continue }
            let noun = pair.word
            let s = plural ? Slot.pl : Slot(noun.gender!)
            let c = Case.allCases.randomElement(using: &rng)!
            let adjective = pair.adjectives.randomElement(using: &rng)!
            let frameIndex = Int.random(in: 0..<(frames[c]?.count ?? 1), using: &rng)
            if let item = build(det: det, c: c, s: s, noun: noun, adjective: adjective, frameIndex: frameIndex) {
                return item
            }
        }
        return nil
    }
}
