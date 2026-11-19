import Foundation
import Testing
@testable import WortCore

@Suite struct SchedulerTests {
    let s = Scheduler()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    @Test func newCardWalksTheLearningSteps() {
        var c = CardState(due: t0)
        c = s.next(c, .good, now: t0)
        #expect(c.phase == .learning(step: 1))
        #expect(c.due == t0 + 600)
        c = s.next(c, .good, now: t0 + 600)
        #expect(c.phase == .review)
        #expect(c.interval == 1)
        #expect(c.due == t0 + 600 + day)
    }

    @Test func easyGraduatesStraightAway() {
        let c = s.next(CardState(due: t0), .easy, now: t0)
        #expect(c.phase == .review)
        #expect(c.interval == 4)
    }

    @Test func againRestartsLearning() {
        var c = s.next(CardState(due: t0), .good, now: t0)
        c = s.next(c, .again, now: t0 + 600)
        #expect(c.phase == .learning(step: 0))
        #expect(c.due == t0 + 600 + 60)
    }

    @Test func goodGrowsTheIntervalByEase() {
        var c = s.next(CardState(due: t0), .easy, now: t0)          // 4 days
        c = s.next(c, .good, now: c.due)
        #expect(c.interval == 10)                                    // 4 × 2.5
        c = s.next(c, .good, now: c.due)
        #expect(c.interval == 25)
    }

    @Test func aLapseHalvesTheIntervalAndCutsEase() {
        var c = s.next(CardState(due: t0), .easy, now: t0)
        c = s.next(c, .good, now: c.due)                              // 10 days
        c = s.next(c, .again, now: c.due)
        #expect(c.phase == .relearning(step: 0))
        #expect(c.lapses == 1)
        #expect(c.ease == 2.3)
        c = s.next(c, .good, now: c.due)
        #expect(c.phase == .review)
        #expect(c.interval == 5)
    }

    @Test func easeNeverDropsBelowTheFloor() {
        var c = s.next(CardState(due: t0), .easy, now: t0)
        for _ in 0..<20 {
            c = s.next(c, .again, now: c.due)
            c = s.next(c, .good, now: c.due)
        }
        #expect(c.ease == 1.3)
    }

    @Test func intervalsAreCapped() {
        var c = s.next(CardState(due: t0), .easy, now: t0)
        for _ in 0..<30 { c = s.next(c, .easy, now: c.due) }
        #expect(c.interval == 730)
    }

    @Test func replayIsOrderIndependentAndMatchesStepping() {
        let events = [ReviewEvent(rating: .good, at: t0), ReviewEvent(rating: .good, at: t0 + 600),
                      ReviewEvent(rating: .good, at: t0 + 600 + day)]
        var stepped = CardState(due: t0)
        for e in events { stepped = s.next(stepped, e.rating, now: e.at) }
        #expect(s.replay(events, createdAt: t0) == stepped)
        #expect(s.replay(events.reversed(), createdAt: t0) == stepped)   // two devices' logs merged in any order
    }

    @Test func cardKindsFollowTheWord() {
        #expect(CardKind.kinds(partOfSpeech: .noun, gender: .neuter, plural: "Bücher") == [.meaning, .recall, .gender, .plural])
        #expect(CardKind.kinds(partOfSpeech: .verb, gender: nil, plural: nil) == [.meaning, .recall])
        #expect(CardKind.kinds(partOfSpeech: .noun, gender: nil, plural: nil) == [.meaning, .recall])
    }
}
