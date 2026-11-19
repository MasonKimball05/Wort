import Foundation

/// What Wort knows about a word after looking it up.
public struct LookupResult: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case wiktionary
        /// No page for the word itself; the gender comes from its last part ("Zeitungsartikel" → "Artikel").
        case compound(head: String)
        /// No page and no known compound head: a suffix rule ("-ung" → die). Shown as a guess.
        case suffixGuess
        case notFound
        /// Wiktionary couldn't be reached (offline, throttled); try again later.
        case unreachable
    }
    /// One per German entry; several when a word has more than one ("See": lake, sea).
    public var entries: [DictionaryEntry]
    public var source: Source
    /// When the input was an inflected form ("Bücher"), the form that was entered.
    public var enteredForm: String?
    /// What that form is, in Wiktionary's words: "nominative/accusative/genitive
    /// plural of Buch", "dative masculine/neuter singular of der".
    public var formDescription: String?
    /// "sich berufen": the entries are for "berufen"; the word to save is reflexive.
    public var reflexive = false
    /// "verzichten auf": the preposition that was typed after the verb.
    public var preposition: String?
}

/// Splits what a learner types around a verb: "sich berufen auf" → reflexive,
/// "berufen", preposition "auf". Wiktionary has no page under "sich berufen".
public struct VerbPhraseInput: Equatable, Sendable {
    public static let prepositions: Set<String> = ["an", "auf", "aus", "bei", "für", "gegen", "in", "mit",
                                                   "nach", "über", "um", "unter", "von", "vor", "zu", "als"]
    public var reflexive = false
    public var core: String
    public var preposition: String?

    public init(_ raw: String) {
        var parts = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count > 1, parts[0].lowercased() == "sich" { reflexive = true; parts.removeFirst() }
        if parts.count > 1, let last = parts.last, Self.prepositions.contains(last.lowercased()) {
            preposition = last.lowercased(); parts.removeLast()
        }
        core = parts.joined(separator: " ")
    }
}

/// Fetches a Wiktionary page's HTML, or nil if there's no such page.
public typealias PageFetcher = @Sendable (String) async throws -> String?

public enum LookupError: Error, Sendable { case unreachable }

public struct WordLookup: Sendable {
    let fetch: PageFetcher
    /// Nouns Wort already knows (the starter deck plus the person's words),
    /// for the compound fallback.
    let knownNouns: [String: Gender]

    public init(knownNouns: [String: Gender] = [:], fetch: @escaping PageFetcher = WordLookup.wiktionary) {
        self.fetch = fetch
        self.knownNouns = knownNouns
    }

    /// `exactCase`: the word comes from a sentence, where German capitalisation is
    /// meaningful. A lowercase word there is never a noun ("würde" is werden, not die
    /// Würde), and a capitalised one at the start of a sentence ("Wenn") falls back
    /// to its lowercase page.
    public func lookUp(_ raw: String, exactCase: Bool = false) async -> LookupResult {
        // "sich berufen auf": look up "berufen", then put "sich" and "auf" back.
        let phrase = VerbPhraseInput(raw)
        if phrase.reflexive || phrase.preposition != nil {
            var r = await lookUpWord(phrase.core, exactCase: exactCase)
            r.reflexive = phrase.reflexive
            r.preposition = phrase.preposition
            if phrase.reflexive {
                for i in r.entries.indices where r.entries[i].partOfSpeech == .verb || r.entries[i].partOfSpeech == .other {
                    r.entries[i].lemma = "sich " + r.entries[i].lemma
                }
            }
            return r
        }
        return await lookUpWord(raw, exactCase: exactCase)
    }

    func lookUpWord(_ raw: String, exactCase: Bool = false) async -> LookupResult {
        let input = ParsedInput(raw)
        guard !input.word.isEmpty else { return LookupResult(entries: [], source: .notFound) }

        // As typed, then capitalised: "buch" is a verb form on Wiktionary, but
        // someone typing "buch" more likely means the noun. Both are kept when
        // both exist; nouns first.
        var entries: [DictionaryEntry]
        do { entries = try await germanEntriesOrThrow(input.word) }
        catch { return LookupResult(entries: [], source: .unreachable) }
        let capital = input.word.prefix(1).uppercased() + input.word.dropFirst()
        if exactCase {
            let lower = input.word.lowercased()
            if entries.isEmpty, lower != input.word {
                entries = (try? await germanEntriesOrThrow(lower)) ?? []
            }
        } else if capital != input.word {
            let nouns = await germanEntries(capital).filter { $0.partOfSpeech == .noun }
            // The noun leads only when the lowercase page has no real entry of its own:
            // "buch" (just an imperative of buchen) → das Buch, but "anrufen" stays the
            // verb, with das Anrufen after it.
            let lowerHasLemma = entries.contains { $0.formOf == nil }
            entries = lowerHasLemma ? entries + nouns : nouns + entries
        }

        // Inflected forms point at their lemma: follow once.
        var enteredForm: String?
        var formDescription: String?
        if !entries.isEmpty, entries.allSatisfy({ $0.formOf != nil }), let lemma = entries.first?.formOf {
            // What the form is ("dative … singular of der") is worth keeping even if
            // the lemma's page can't be fetched.
            enteredForm = input.word
            formDescription = Self.formDescriptions(entries)
            let lemmaEntries = await germanEntries(lemma)
            if !lemmaEntries.isEmpty { entries = lemmaEntries }
        } else {
            // Mixed page ("deiner": a pronoun, and an inflection of dein): keep the
            // lemma entries, but remember what the form is, for the case it shows.
            if entries.contains(where: { $0.formOf == nil }) {
                let forms = Self.formDescriptions(entries)
                if !forms.isEmpty {
                    enteredForm = input.word
                    formDescription = forms
                }
                entries.removeAll { $0.formOf != nil }
            }
        }

        // The article the person typed picks between entries ("die See" → sea).
        if let g = input.gender, entries.contains(where: { $0.gender == g }) {
            entries.sort { ($0.gender == g ? 0 : 1) < ($1.gender == g ? 0 : 1) }
        }

        if !entries.isEmpty {
            return LookupResult(entries: entries, source: .wiktionary, enteredForm: enteredForm,
                                formDescription: formDescription)
        }

        // No page. For a noun, fall back to its compound head, then a suffix rule.
        guard input.looksLikeNoun || input.gender != nil else {
            return LookupResult(entries: [], source: .notFound)
        }
        var guess = DictionaryEntry(lemma: input.word, partOfSpeech: .noun)
        if let g = input.gender {
            guess.gender = g
            return LookupResult(entries: [guess], source: .suffixGuess)
        }
        if let head = GenderGuess.compoundHead(of: input.word, known: Set(knownNouns.keys)) {
            guess.gender = knownNouns[head]
            return LookupResult(entries: [guess], source: .compound(head: head))
        }
        if let g = GenderGuess.guess(input.word) {
            guess.gender = g
            return LookupResult(entries: [guess], source: .suffixGuess)
        }
        return LookupResult(entries: [guess], source: .notFound)
    }

    /// Every reading of an inflected form, joined: "deiner" is both "genitive of du"
    /// and "inflection of dein: genitive/dative feminine singular".
    static func formDescriptions(_ entries: [DictionaryEntry]) -> String {
        var seen: [String] = []
        for e in entries where e.formOf != nil {
            if let g = e.glosses.first, !seen.contains(g) { seen.append(g) }
        }
        return seen.joined(separator: "; ")
    }

    func germanEntries(_ word: String) async -> [DictionaryEntry] {
        (try? await germanEntriesOrThrow(word)) ?? []
    }

    func germanEntriesOrThrow(_ word: String) async throws -> [DictionaryEntry] {
        guard let html = try await fetch(word) else { return [] }
        return WiktionaryParser.entries(fromPageHTML: html)
    }

    /// Wiktionary's REST API. Only the word itself is sent. Wikimedia asks
    /// automated clients to identify themselves; this names the app, no person.
    public static let wiktionary: PageFetcher = { word in
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard let path = word.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://en.wiktionary.org/api/rest_v1/page/html/\(path)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Wort/0.1 (personal vocabulary app)", forHTTPHeaderField: "User-Agent")
        // 404 means there is no page. Throttling (429) and server errors are not
        // "no page": retry once after a pause, then throw so the caller can say
        // Wiktionary couldn't be reached rather than that the word doesn't exist.
        for attempt in 0..<2 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return String(decoding: data, as: UTF8.self) }
            if status == 404 { return nil }
            if attempt == 0 { try await Task.sleep(for: .seconds(2)) }
        }
        throw LookupError.unreachable
    }
}

/// Separable-prefix verbs: "anrufen" is an + rufen. Only splits when the rest is
/// still a plausible verb (at least "-en" plus a stem).
public enum SeparableVerb {
    public static let prefixes = ["zurück", "zusammen", "weiter", "wieder", "statt", "teil", "fest", "frei",
                                  "fort", "heim", "her", "hin", "los", "weg", "vor", "nach", "mit", "bei",
                                  "auf", "aus", "ein", "an", "ab", "zu", "dar", "um"]

    public static func split(_ verb: String) -> (prefix: String, base: String)? {
        let v = verb.lowercased()
        guard v.hasSuffix("en") || v.hasSuffix("ern") || v.hasSuffix("eln") else { return nil }
        // Longest prefix first, so "zurück" beats "zu".
        for p in prefixes.sorted(by: { $0.count > $1.count }) where v.hasPrefix(p) {
            let base = String(v.dropFirst(p.count))
            if base.count >= 4 { return (p, base) }
        }
        return nil
    }
}

/// Everything shown when a word in an exercise is tapped or hovered.
public struct WordExplanation: Equatable, Sendable {
    public var token: String
    public var lookup: LookupResult
    /// For a separable verb, its prefix and the base verb's entry: an + rufen.
    public var separablePrefix: String?
    public var base: DictionaryEntry?
}

extension WordLookup {
    /// Looks up a word as it appears in a sentence ("anriefe", "dem", "Tischen"):
    /// its lemma, what form it is, and for a separable verb, the base verb too.
    public func explain(_ token: String) async -> WordExplanation {
        let word = ParsedInput(token).word
        let result = await lookUp(word, exactCase: true)
        var explanation = WordExplanation(token: word, lookup: result)
        if let verb = result.entries.first(where: { $0.partOfSpeech == .verb }),
           let (prefix, base) = SeparableVerb.split(verb.lemma.replacingOccurrences(of: "sich ", with: "")) {
            let baseEntries = await lookUp(base).entries.filter { $0.partOfSpeech == .verb }
            if let b = baseEntries.first {
                explanation.separablePrefix = prefix
                explanation.base = b
            }
        }
        return explanation
    }
}
