import Foundation
import Testing
@testable import WortCore

@Suite struct AdjectiveEndingTests {
    typealias A = AdjectiveEndings

    /// Spot checks against phrases any grammar book gives.
    @Test(arguments: [
        (A.Pattern.weak, A.Case.nom, A.Slot.m, "e"),     // der alte Mann
        (.weak, .akk, .m, "en"),                          // den alten Mann
        (.weak, .nom, .pl, "en"),                         // die alten Männer
        (.mixed, .nom, .m, "er"),                         // ein alter Mann
        (.mixed, .nom, .n, "es"),                         // ein altes Haus
        (.mixed, .akk, .n, "es"),                         // ein altes Haus
        (.mixed, .dat, .f, "en"),                         // einer alten Frau
        (.strong, .dat, .m, "em"),                        // mit kaltem Kaffee
        (.strong, .dat, .f, "er"),                        // mit kalter Milch
        (.strong, .nom, .pl, "e"),                        // alte Bücher
        (.strong, .gen, .pl, "er"),                       // alter Bücher
        (.strong, .nom, .n, "es"),                        // frisches Obst
    ])
    func table(p: A.Pattern, c: A.Case, s: A.Slot, ending: String) {
        #expect(A.ending(p, c, s) == ending)
    }

    let nouns = GrammarBank.nouns()

    @Test func nounPoolIsSensible() {
        #expect(nouns.count > 60)
        #expect(!nouns.contains { A.isWeakNoun($0.word) }, "n-declension nouns are left out")
        #expect(nouns.contains { $0.word.lemma == "Obst" && $0.word.plural == nil }, "mass nouns are in, for the no-article singular")
        #expect(nouns.first { $0.word.lemma == "Kaffee" }?.adjectives.contains("stark") == true)
        let kollege = StarterWord(partOfSpeech: .noun, gender: .masculine, lemma: "Kollege", plural: "Kollegen", english: "", example: nil, level: "")
        let tee = StarterWord(partOfSpeech: .noun, gender: .masculine, lemma: "Tee", plural: "Tees", english: "", example: nil, level: "")
        #expect(A.isWeakNoun(kollege) && !A.isWeakNoun(tee))
    }

    @Test func generatedItemsAreValidAndRebuildFromTheirID() {
        var rng = SeededRandom(seed: 42)
        for _ in 0..<500 {
            let item = try! #require(A.random(nouns: nouns, using: &rng))
            #expect(item.prompt.contains("___"))
            #expect(item.isCorrect(item.answers[0]))
            #expect(item.isCorrect(item.answers[1]), "the whole adjective is accepted too")
            #expect(A.item(id: item.id, nouns: nouns) == item, "\(item.id)")
            #expect(GrammarBank.item(id: item.id, nouns: nouns) == item)
            #expect(!item.prompt.contains("  "))
        }
    }

    @Test func noArticleSingularOnlyWithMassNouns() {
        var rng = SeededRandom(seed: 7)
        for _ in 0..<1000 {
            let item = A.random(nouns: nouns, using: &rng)!
            let f = item.id.split(separator: ":").map(String.init)
            let noun = nouns.first { A.nounKey($0.word) == f[4] }!.word
            if f[1] == "0" && f[3] != "pl" { #expect(noun.plural == nil, "\(item.id)") }
            if noun.plural == nil { #expect(f[1] == "0" && f[3] != "pl", "\(item.id)") }
        }
    }

    @Test func knownPhrases() throws {
        let tisch = try #require(nouns.first { $0.word.lemma == "Tisch" })
        let akk = try #require(A.item(id: "adj:der:akk:m:Tisch.m:rund:0", nouns: [tisch]))
        #expect(akk.prompt == "Ich komme ohne den rund___ Tisch.")
        #expect(akk.answers.first == "en")
        let datPl = try #require(A.item(id: "adj:mein:dat:pl:Tisch.m:groß:0", nouns: [tisch]))
        #expect(datPl.prompt == "Ich komme mit meinen groß___ Tischen.")   // dative plural -n on the noun
        #expect(datPl.answers.first == "en")
        let obst = try #require(nouns.first { $0.word.lemma == "Obst" })
        let strong = try #require(A.item(id: "adj:0:nom:n:Obst.n:frisch:0", nouns: [obst]))
        #expect(strong.prompt == "Hier ist frisch___ Obst.")
        #expect(strong.answers.first == "es")
        #expect(A.item(id: "adj:der:gen:m:Tisch.m:rund:0", nouns: [tisch]) == nil, "masculine genitive needs -(e)s on the noun; not generated")
        #expect(A.item(id: "adj:der:akk:m:Tisch.m:süß:0", nouns: [tisch]) == nil, "only the noun's own adjectives")
        #expect(A.item(id: "adj:ein:nom:pl:Tisch.m:rund:0", nouns: [tisch]) == nil, "ein has no plural")
    }
}

@Suite struct GrammarBankTests {
    @Test(arguments: [GrammarTopic.konjunktiv, .passive, .cases])
    func banksLoad(topic: GrammarTopic) {
        let items = GrammarBank.items(topic: topic)
        #expect(items.count >= 25, "\(topic)")
        #expect(Set(items.map(\.id)).count == items.count, "unique ids in \(topic)")
        for item in items {
            #expect(!item.answers.isEmpty && !item.explanation.isEmpty, "\(item.id)")
            switch item.kind {
            case .gap: #expect(item.prompt.contains("___"), "\(item.id) has no gap")
            case .choice(let options):
                #expect(options.count >= 3, "\(item.id)")
                #expect(options.contains(item.answers[0]), "\(item.id): answer not among the options")
                #expect(Set(options).count == options.count, "\(item.id): duplicate options")
            }
            #expect(GrammarBank.item(id: item.id) == item)
        }
    }

    @Test func checking() {
        let item = GrammarItem(id: "t", topic: .konjunktiv, kind: .gap, prompt: "Er sagte, er ___ krank.",
                               answers: ["sei", "wäre"], explanation: "")
        #expect(item.isCorrect("sei"))
        #expect(item.isCorrect("  Sei. "))
        #expect(item.isCorrect("wa\u{0308}re"), "decomposed ä counts")
        #expect(!item.isCorrect("ist"))
        #expect(!item.isCorrect(""))
        #expect(item.solved == "Er sagte, er sei krank.")
        let hinted = GrammarItem(id: "h", topic: .konjunktiv, kind: .gap, prompt: "Wenn sie doch nur ___ (anrufen)!",
                                 answers: ["anriefe"], explanation: "")
        #expect(hinted.solved == "Wenn sie doch nur anriefe!")
    }
}

@Suite struct LeitnerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func rightSpacesOutWrongResets() {
        var s = LeitnerState(due: t0)
        s = s.next(correct: true, at: t0)
        #expect(s.box == 1 && s.due == t0 + 86_400)
        s = s.next(correct: true, at: s.due)
        #expect(s.box == 2)
        s = s.next(correct: false, at: s.due)
        #expect(s.box == 1 && s.misses == 1)
        #expect(s.due == t0 + 86_400 + 3 * 86_400, "a miss is due again straight away")
    }

    @Test func replayMatchesStepping() {
        let events = [GrammarAttemptEvent(correct: true, at: t0), GrammarAttemptEvent(correct: false, at: t0 + 100),
                      GrammarAttemptEvent(correct: true, at: t0 + 200)]
        var s = LeitnerState(due: t0)
        for e in events { s = s.next(correct: e.correct, at: e.at) }
        #expect(LeitnerState.replay(events) == s)
        #expect(LeitnerState.replay(events.reversed()) == s)
        #expect(LeitnerState.replay([]) == nil)
    }

    @Test func sessionsPutMissesFirstThenNewItems() {
        let bank = GrammarBank.items(topic: .cases)
        let missed = bank[3], learned = bank[5]
        let progress: [String: LeitnerState] = [
            missed.id: LeitnerState(due: t0).next(correct: false, at: t0),
            learned.id: LeitnerState(due: t0).next(correct: true, at: t0),   // due tomorrow
        ]
        let session = GrammarSession.build(topic: .cases, progress: progress, now: t0 + 60, size: 10, seed: 1)
        #expect(session.count == 10)
        #expect(session.first?.id == missed.id)
        #expect(!session.contains { $0.id == learned.id }, "not due yet")
        #expect(Set(session.map(\.id)).count == 10)
    }

    @Test func adjectiveSessionsAreGenerated() {
        let session = GrammarSession.build(topic: .adjectiveEndings, progress: [:], now: t0, size: 10, seed: 3)
        #expect(session.count == 10)
        #expect(session.allSatisfy { $0.topic == .adjectiveEndings })
    }
}
