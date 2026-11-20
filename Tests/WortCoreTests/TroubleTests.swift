import Foundation
import Testing
@testable import WortCore

@Suite struct TroubleTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func results(_ pattern: String) -> [Trouble.Result] {
        pattern.enumerated().map { i, c in Trouble.Result(correct: c == "y", at: t0 + Double(i) * 3600) }
    }

    @Test func missedLastTimeIsTrouble() {
        #expect(Trouble.summarize(results("yyyn")) != nil)
    }

    @Test func aFirstMissAloneIsNot() {
        // Missing a word the first time you meet it is normal.
        #expect(Trouble.summarize(results("n")) == nil)
    }

    @Test func oneOldMissThenRightIsNot() {
        #expect(Trouble.summarize(results("nyyyyy")) == nil)
        #expect(Trouble.summarize(results("ynyy")) == nil)
    }

    @Test func repeatedMissesStayUntilThreeRightRunning() {
        #expect(Trouble.summarize(results("nnyy"))?.misses == 2)
        #expect(Trouble.summarize(results("nnyyy")) == nil)
    }

    @Test func onlyTheRecentWindowCounts() {
        let s = Trouble.summarize(results("nnnnyynyyyyyn"))
        #expect(s?.recent == 8)
        #expect(s?.misses == 2)
    }

    @Test func rankedWorstFirst() {
        let r = Trouble.ranked(["a": results("ynyn"), "b": results("nnnn"), "c": results("yyyy")])
        #expect(r.map(\.id) == ["b", "a"])
    }

    @Test func weakRulesGroupAdjectiveItems() {
        let dat = "adj:ein:dat:m:Tisch.m:alt:0"
        let dat2 = "adj:mein:dat:f:Frage.f:schwierig:1"
        let nom = "adj:der:nom:m:Tisch.m:alt:0"
        let attempts = [(dat, false), (dat2, false), (dat, true), (nom, true), (nom, true), (nom, true),
                        ("cases:x1", false)].map { (itemID: $0.0, correct: $0.1) }
        let rules = Trouble.weakRules(attempts)
        #expect(rules.count == 1)
        #expect(rules.first?.rule == "Dativ · nach ein/mein/kein")
        #expect(rules.first?.right == 1 && rules.first?.total == 3)
    }

    @Test func bulkItemLookupMatchesSingle() {
        let any = GrammarBank.items(topic: .cases).first!
        var rng = SeededRandom(seed: 7)
        let adj = AdjectiveEndings.random(nouns: GrammarBank.nouns(), using: &rng)!
        let found = GrammarBank.items(ids: [any.id, adj.id, "cases:nope"])
        #expect(found[any.id] == any)
        #expect(found[adj.id] == adj)
        #expect(found["cases:nope"] == nil)
    }
}

@Suite struct ReadingTests {
    @Test func paragraphsSplitOnBlankLinesAndJoinWrappedLines() {
        let text = "Erster Satz,\nder umbricht.\n\n  Zweiter   Absatz.\r\n\r\n\n Dritter."
        #expect(ReadingText.paragraphs(text) == ["Erster Satz, der umbricht.", "Zweiter Absatz.", "Dritter."])
    }

    @Test func titleIsTheFirstWords() {
        #expect(ReadingText.title(for: "Als der Zug endlich in den Bahnhof einfuhr") == "Als der Zug endlich in den…")
        #expect(ReadingText.title(for: "Kurz.") == "Kurz.")
    }

    @Test func knownMatchesLemmaAndPluralIgnoringPunctuation() {
        let known = ReadingText.knownForms([(lemma: "Buch", plural: "Bücher"), (lemma: "gehen", plural: nil)])
        #expect(ReadingText.isKnown("Bücher.", in: known))
        #expect(ReadingText.isKnown("„Buch“", in: known))
        #expect(ReadingText.isKnown("Gehen,", in: known))
        #expect(!ReadingText.isKnown("ging", in: known))
    }

    @Test func sentenceAroundAWord() {
        let p = "Er kam am 3. Mai an, z. B. mit Dr. Weber. Dann ging er! Sie blieb."
        let words = p.split(separator: " ").map(String.init)
        #expect(ReadingText.sentence(around: words.firstIndex(of: "Weber.")!, in: p)
                == "Er kam am 3. Mai an, z. B. mit Dr. Weber.")
        #expect(ReadingText.sentence(around: words.firstIndex(of: "ging")!, in: p) == "Dann ging er!")
        #expect(ReadingText.sentence(around: words.count - 1, in: p) == "Sie blieb.")
        #expect(ReadingText.sentence(around: 0, in: "„Komm her“, rief sie. Er kam.") == "„Komm her“, rief sie.")
    }
}
