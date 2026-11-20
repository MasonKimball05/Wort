import Foundation
import Testing
@testable import WortCore

@Suite struct StreakTests {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }
    func day(_ d: Int, _ h: Int = 12) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }

    @Test func countsBackFromToday() {
        let s = Streak.summary([day(17), day(18), day(19, 8), day(19, 20)], today: day(19, 22), calendar: cal)
        #expect(s.current == 3 && s.practicedToday)
        #expect(s.perDay[cal.startOfDay(for: day(19))] == 2)
    }

    @Test func todayNotYetDoesNotBreakIt() {
        let s = Streak.summary([day(16), day(17), day(18)], today: day(19, 9), calendar: cal)
        #expect(s.current == 3 && !s.practicedToday)
    }

    @Test func aGapEndsItAndLongestIsKept() {
        let s = Streak.summary([day(10), day(11), day(12), day(13), day(17), day(19)], today: day(19), calendar: cal)
        #expect(s.current == 1)
        #expect(s.longest == 4)
        #expect(Streak.summary([], today: day(19), calendar: cal).current == 0)
    }
}

@Suite struct DictationTests {
    @Test func exactIsCorrectIgnoringCaseAndPunctuation() {
        #expect(Dictation.isCorrect(expected: "Das Buch liegt auf dem Tisch.", typed: "das buch liegt auf dem tisch"))
    }

    @Test func umlautsCount() {
        #expect(!Dictation.isCorrect(expected: "Er ist schön.", typed: "er ist schon"))
    }

    @Test func aMissedWordIsMarkedAndTheRestStillMatch() {
        let w = Dictation.compare(expected: "Ich habe den Zug verpasst.", typed: "ich habe zug verpasst")
        #expect(w.map(\.ok) == [true, true, false, true, true])
    }

    @Test func extraWordsMakeItWrong() {
        #expect(!Dictation.isCorrect(expected: "das Buch", typed: "das das Buch"))
        #expect(Dictation.compare(expected: "das Buch", typed: "das das Buch").allSatisfy { $0.ok })
    }

    @Test func missingArticleIsWrong() {
        #expect(!Dictation.isCorrect(expected: "die Hoffnung", typed: "Hoffnung"))
    }
}

@Suite struct BackupTests {
    let word = Backup.WordRecord(german: "das Buch", lemma: "Buch", partOfSpeech: "noun", gender: "n", plural: "Bücher",
                                 english: "book, volume", exampleGerman: "Er sagte: \"Lies das\".", exampleEnglish: nil,
                                 government: nil, forms: nil, source: "manual",
                                 addedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                 reviews: [.init(drill: "meaning", rating: "good", at: Date(timeIntervalSince1970: 1_800_000_100))])

    @Test func csvQuotesWhatNeedsIt() {
        let csv = Backup.csv([word])
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0].hasPrefix("German,English,"))
        #expect(lines[1].hasPrefix("das Buch,\"book, volume\",noun,Bücher,,,\"Er sagte: \"\"Lies das\"\".\","))
        #expect(lines[1].hasSuffix(",2027-01-15"))
    }

    @Test func jsonRoundTrips() throws {
        let file = Backup.File(exportedAt: Date(timeIntervalSince1970: 1_800_000_200), words: [word],
                               grammar: [.init(item: "cases:c01", topic: "cases", correct: false, at: Date(timeIntervalSince1970: 1_800_000_300))],
                               readings: [.init(title: "T", text: "Text", addedAt: Date(timeIntervalSince1970: 1_800_000_400))])
        #expect(try Backup.decode(Backup.json(file)) == file)
    }
}

@Suite struct WidgetSnapshotTests {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }
    func at(_ d: Int, _ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }

    @Test func countsWhatBecomesDueAndDropsNewAtMidnight() {
        let s = WidgetSnapshot(dueDates: [at(19, 15), at(19, 8), at(20, 9)], newToday: 5, streak: 3,
                               practicedToday: true, updatedAt: at(19, 10))
        #expect(s.due(at: at(19, 10), calendar: cal) == 1 + 5)
        #expect(s.due(at: at(19, 16), calendar: cal) == 2 + 5)
        #expect(s.due(at: at(20, 10), calendar: cal) == 3)
        #expect(s.nextDue(after: at(19, 10)) == at(19, 15))
        #expect(WidgetSnapshot.decode(s.encoded()) == s)
    }

    @Test func streakSurvivesUntilTheDayAfter() {
        let s = WidgetSnapshot(dueDates: [], newToday: 0, streak: 4, practicedToday: true, updatedAt: at(19, 10))
        #expect(s.streak(at: at(19, 22), calendar: cal).days == 4 && s.streak(at: at(19, 22), calendar: cal).practicedToday)
        #expect(s.streak(at: at(20, 9), calendar: cal).days == 4)
        #expect(s.streak(at: at(21, 9), calendar: cal).days == 0)
    }
}
