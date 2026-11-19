import Foundation
import Testing
@testable import WortCore

@Suite struct StarterDeckTests {
    let a1 = StarterDeck.words(level: "A1")
    let c1 = StarterDeck.words(level: "C1")

    @Test func c1Loads() {
        #expect(c1.count > 230)
        #expect(Set(c1.map(\.key)).count == c1.count, "duplicate keys in C1")
        let verzichten = c1.first { $0.lemma == "verzichten" }
        #expect(verzichten?.government == "auf + Akk.")
        #expect(c1.first { $0.lemma == "gedeihen" }?.forms == "gedieh, ist gediehen")
        // Article changes meaning: both are there, with their own keys.
        #expect(c1.filter { $0.lemma == "Verdienst" }.compactMap(\.gender).sorted { $0.rawValue < $1.rawValue } == [.masculine, .neuter])
        #expect(c1.contains { $0.partOfSpeech == .phrase && $0.lemma == "in Erwägung ziehen" })
    }

    @Test func everyDeckHasADescription() {
        for level in StarterDeck.levels { #expect(StarterDeck.descriptions[level] != nil, "\(level)") }
    }

    @Test func loads() {
        #expect(a1.count > 400)
        #expect(a1.contains { $0.lemma == "Buch" && $0.gender == .neuter && $0.plural == "Bücher" })
    }

    @Test func everyNounHasAGenderUnlessPluralOnly() {
        let missing = a1.filter { $0.partOfSpeech == .noun && $0.gender == nil && !$0.pluralOnly }
        #expect(a1.filter(\.pluralOnly).map(\.lemma).sorted() == ["Eltern", "Leute"])
        #expect(missing.isEmpty, "\(missing.map(\.lemma))")
    }

    @Test func keysAreUnique() {
        let keys = a1.map(\.key)
        #expect(Set(keys).count == keys.count, "\(Dictionary(grouping: keys, by: { $0 }).filter { $1.count > 1 }.keys)")
    }

    @Test func everyWordHasAnExampleThatUsesIt() {
        let bad = a1.filter { w in
            guard let ex = w.example else { return true }
            // Separable and irregular verbs change shape (aufstehen → "stehe ... auf"); check the stem loosely.
            return !ex.lowercased().contains(w.lemma.lowercased().prefix(3))
        }
        #expect(bad.count < 25, "\(bad.map(\.lemma))")
    }

    /// Network check, run on purpose: WORT_VALIDATE=1 swift test --filter wiktionaryAgrees
    /// Prints every noun whose gender or plural disagrees with Wiktionary.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WORT_VALIDATE"] == "1"))
    func wiktionaryAgrees() async throws {
        let lookup = WordLookup()
        var report: [String] = []
        let level = ProcessInfo.processInfo.environment["WORT_LEVEL"] ?? "A1"
        for w in StarterDeck.words(level: level) where w.partOfSpeech == .noun {
            try await Task.sleep(for: .milliseconds(600))     // be polite to Wikimedia
            let r = await lookup.lookUp(w.lemma)
            let nouns = r.entries.filter { $0.partOfSpeech == .noun && $0.lemma == w.lemma }
            if r.source == .unreachable { report.append("UNREACHABLE \(w.lemma)"); continue }
            guard !nouns.isEmpty else { report.append("NOPAGE \(w.lemma)"); continue }
            if w.pluralOnly { if !nouns.contains(where: \.pluralOnly) { report.append("PLURALONLY? \(w.lemma)") }; continue }
            let match = nouns.first { $0.gender == w.gender } ?? nouns[0]
            if match.gender != w.gender {
                report.append("GENDER \(w.lemma): deck \(w.gender?.article ?? "-") wiki \(nouns.compactMap { $0.gender?.article })")
            }
            let wikiPlural = match.plural
            if let mine = w.plural, let theirs = wikiPlural, mine != theirs {
                report.append("PLURAL \(w.lemma): deck \(mine) wiki \(theirs)")
            }
            if w.plural == nil, let theirs = wikiPlural, !match.noPlural, !match.pluralOnly {
                report.append("PLURAL? \(w.lemma): deck none, wiki \(theirs)")
            }
            if w.plural != nil, match.noPlural { report.append("PLURAL? \(w.lemma): deck \(w.plural!), wiki none") }
        }
        print("VALIDATION\n" + report.joined(separator: "\n"))
    }

    /// Network check of the C1 deck's strong-verb principal parts:
    /// WORT_VALIDATE=1 swift test --filter wiktionaryVerbForms
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WORT_VALIDATE"] == "1"))
    func wiktionaryVerbForms() async throws {
        let lookup = WordLookup()
        var report: [String] = []
        for w in c1 where w.partOfSpeech == .verb && w.forms != nil {
            try await Task.sleep(for: .milliseconds(600))
            let core = VerbPhraseInput(w.lemma).core
            let r = await lookup.lookUp(core)
            let theirs = r.entries.first { $0.partOfSpeech == .verb }?.principalParts
            if theirs != w.forms { report.append("FORMS \(w.lemma): deck \(w.forms ?? "-") wiki \(theirs ?? "-")") }
        }
        print("VERBFORMS\n" + report.joined(separator: "\n"))
    }
}
