import Foundation
import Testing
@testable import WortCore

@Suite struct HintTests {
    @Test func lettersShowFirstAndLength() {
        #expect(Hints.letters("die Hoffnung") == "d _ _   H _ _ _ _ _ _ _")
        #expect(Hints.letters("zur") == "z _ _")
    }

    @Test(arguments: [("Buch", "Bücher", "¨ + -er"), ("Frau", "Frauen", "-en"), ("Auto", "Autos", "-s"),
                      ("Lehrer", "Lehrer", "same as the singular"), ("Vater", "Väter", "¨ (umlaut, no ending)"),
                      ("Tisch", "Tische", "-e")])
    func pluralPatterns(lemma: String, plural: String, expected: String) {
        #expect(Hints.pluralPattern(lemma: lemma, plural: plural) == expected)
    }

    @Test func otherHints() {
        #expect(Hints.genderRule("Hoffnung") == "Nouns in -ung are usually die")
        #expect(Hints.genderRule("Tisch") == nil)
        #expect(Hints.preposition("auf + Akk.") == "auf + ?")
        #expect(Hints.auxiliary("ging, ist gegangen") == "Perfekt with „ist“")
        #expect(Hints.auxiliary("verzieh, hat verziehen") == "Perfekt with „hat“")
    }

    @Test func grammarHints() {
        let gap = GrammarItem(id: "konjunktiv:x", topic: .konjunktiv, kind: .gap, prompt: "Er sagte, er ___ krank.",
                              answers: ["sei"], explanation: "Konjunktiv I.")
        #expect(gap.hint == "s _ _")
        var rng = SeededRandom(seed: 1)
        let adj = AdjectiveEndings.random(nouns: GrammarBank.nouns(), using: &rng)!
        #expect(adj.hint?.contains("→") == false)
        #expect(adj.hint?.contains("·") == true, "the rule, not the ending")
        let choice = GrammarBank.items(topic: .prepositions).first { if case .choice = $0.kind { return true }; return false }!
        let removed = choice.optionToRemove()
        #expect(removed != nil && !choice.answers.contains(removed!))
        #expect(choice.optionToRemove() == removed, "the same one each time")
        let second = choice.optionToRemove(keeping: [removed!])
        #expect(second != removed)
        #expect(choice.optionToRemove(keeping: [removed!, second!]) == nil, "always leaves two options")
    }
}

@Suite struct HintedSchedulingTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func reviewHintTurnsGoodIntoHard() {
        #expect(Scheduler.rating(.good, hinted: true, phase: .review) == .hard)
        #expect(Scheduler.rating(.again, hinted: true, phase: .review) == .again)
        #expect(Scheduler.rating(.good, hinted: false, phase: .review) == .good)
    }

    /// Hard never moves a learning card on, so a hint there must not cap Good.
    @Test func alwaysHintedCardStillGraduatesAndGrows() {
        let s = Scheduler()
        var state = CardState(due: t0)
        var now = t0
        for _ in 0..<12 {
            let r = Scheduler.rating(.good, hinted: true, phase: state.phase)
            state = s.next(state, r, now: now)
            now = max(now + 60, state.due)
        }
        #expect(state.phase == .review)
        #expect(state.interval > 5, "still spaced out, just more slowly: \(state.interval)")
    }

    @Test func hintedGrammarStaysInItsBox() {
        let start = LeitnerState(due: t0).next(correct: true, at: t0).next(correct: true, at: t0 + 86_400)
        #expect(start.box == 2)
        let hinted = start.next(correct: true, at: t0 + 4 * 86_400, hinted: true)
        #expect(hinted.box == 2)
        #expect(hinted.due == t0 + 5 * 86_400)
        let replayed = LeitnerState.replay([.init(correct: true, at: t0), .init(correct: true, at: t0 + 10, hinted: true)])
        #expect(replayed?.box == 1)
    }

    @Test func hintsKeepATroubleSpot() {
        let r = { (c: Bool, h: Bool, i: Int) in Trouble.Result(correct: c, at: self.t0 + Double(i) * 3600, hinted: h) }
        // Missed, then right three times but with hints: still trouble.
        let s = Trouble.summarize([r(false, false, 0), r(true, true, 1), r(true, true, 2), r(true, true, 3)])
        #expect(s?.misses == 1 && s?.hints == 3)
        // Leaning on hints alone, never missing, is trouble too.
        #expect(Trouble.summarize([r(true, true, 0), r(true, true, 1)]) != nil)
        // Three clean answers clear it.
        #expect(Trouble.summarize([r(false, false, 0), r(true, true, 1), r(true, false, 2), r(true, false, 3), r(true, false, 4)]) == nil)
    }
}

@Suite struct TunerTests {
    @Test func easesOffAfterMissesOneStepAtATime() {
        var t = Tuner(level: 3)
        #expect(t.record(id: "a", correct: false, hinted: false) == nil)
        #expect(t.record(id: "b", correct: false, hinted: false) == nil)
        #expect(t.record(id: "c", correct: false, hinted: false) == .easier)
        #expect(t.level == 2)
        #expect(t.record(id: "d", correct: false, hinted: false) == nil, "waits a few answers before changing again")
        #expect(t.record(id: "e", correct: false, hinted: false) == nil)
        #expect(t.record(id: "f", correct: false, hinted: false) == .easier)
        #expect(t.level == 1)
        #expect(t.record(id: "g", correct: false, hinted: false) == nil)
        #expect(t.record(id: "h", correct: false, hinted: false) == nil)
        #expect(t.record(id: "i", correct: false, hinted: false) == nil, "never below 1")
    }

    @Test func stepsUpWhenItGoesWell() {
        var t = Tuner(level: 1)
        _ = t.record(id: "a", correct: true, hinted: false)
        _ = t.record(id: "b", correct: true, hinted: false)
        #expect(t.record(id: "c", correct: true, hinted: false) == .harder)
        #expect(t.level == 2)
    }

    @Test func hintsCountHalfAndRetriesOnce() {
        var t = Tuner(level: 1)
        _ = t.record(id: "a", correct: true, hinted: true)
        _ = t.record(id: "b", correct: true, hinted: true)
        #expect(t.record(id: "c", correct: true, hinted: true) == nil, "all hinted: not doing well enough to step up")
        var u = Tuner(level: 2)
        _ = u.record(id: "a", correct: false, hinted: false)
        #expect(u.record(id: "a", correct: false, hinted: false) == nil)
        #expect(u.record(id: "a", correct: false, hinted: false) == nil, "the retry of a doesn't count again")
        #expect(u.level == 2)
    }

    @Test func startLevelFromHistory() {
        #expect(Tuner.startLevel([]) == 2)
        #expect(Tuner.startLevel(Array(repeating: (true, false), count: 10)) == 3)
        #expect(Tuner.startLevel(Array(repeating: (false, false), count: 6) + Array(repeating: (true, false), count: 4)) == 1)
        #expect(Tuner.startLevel(Array(repeating: (true, true), count: 8)) == 1, "all hinted counts as half")
    }
}

@Suite struct AdaptiveSessionTests {
    @Test func adjectiveLevelsMatchTheirRules() {
        let nouns = GrammarBank.nouns()
        var rng = SeededRandom(seed: 9)
        for level in 1...3 {
            for _ in 0..<20 {
                let item = AdjectiveEndings.random(nouns: nouns, level: level, excluding: [], using: &rng)!
                #expect(AdjectiveEndings.difficulty(id: item.id)! <= level)
            }
        }
        let easy = AdjectiveEndings.random(nouns: nouns, level: 1, excluding: [], using: &rng)!
        let f = easy.id.split(separator: ":")
        #expect(["der", "dieser"].contains(String(f[1])) && ["nom", "akk"].contains(String(f[2])) && f[3] != "pl")
    }

    @Test func freshDoesNotStarveOrRepeat() {
        var rng = SeededRandom(seed: 4)
        let bank = GrammarBank.items(topic: .prepositions)
        let allButOne = Set(bank.dropFirst().map(\.id))
        #expect(GrammarSession.fresh(topic: .prepositions, level: 3, excluding: allButOne, using: &rng)?.id == bank[0].id)
        #expect(GrammarSession.fresh(topic: .prepositions, level: 2, excluding: Set(bank.map(\.id)), using: &rng) == nil)
        let easy = GrammarSession.fresh(topic: .prepositions, level: 1, excluding: [], using: &rng)!
        if case .choice = easy.kind {} else { Issue.record("level 1 prefers multiple choice") }
    }

    @Test func dueReturnsOnlyDueItemsOfTheTopic() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let bank = GrammarBank.items(topic: .cases)
        let progress = [bank[0].id: LeitnerState(due: t0).next(correct: false, at: t0),
                        bank[1].id: LeitnerState(due: t0).next(correct: true, at: t0 - 10 * 86_400)]
        let due = GrammarSession.due(topic: .cases, progress: progress, now: t0 + 60)
        #expect(Set(due.map(\.id)) == [bank[0].id, bank[1].id])
        #expect(due.allSatisfy { $0.topic == .cases })
    }
}
