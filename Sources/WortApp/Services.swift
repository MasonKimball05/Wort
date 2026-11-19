import AVFoundation
import Foundation
import SwiftData
import WortCore

/// Fills in words saved without details (share sheet, links): article, plural,
/// meaning and an example, from Wiktionary.
@MainActor
enum Enricher {
    static let lookup = WordLookup(knownNouns: StarterDeck.knownNouns())

    static func run(context: ModelContext) async {
        let pending = (try? context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.needsLookup }))) ?? []
        for word in pending {
            let result = await lookup.lookUp(word.display + (word.government.map { " " + $0 } ?? ""))
            if result.source == .unreachable { return }        // offline: try again next time
            if let e = result.entries.first { apply(e, source: result.source, to: word) }
            word.needsLookup = false
            word.ensureCards(context: context)
        }
        try? context.save()
        Store.deduplicate(context: context)
    }

    static func apply(_ e: DictionaryEntry, source: LookupResult.Source, to word: Word) {
        word.lemma = e.lemma
        word.partOfSpeech = e.partOfSpeech
        if word.gender == nil || source == .wiktionary { word.gender = e.gender ?? word.gender }
        word.genderSource = label(source)
        word.plural = e.plural ?? word.plural
        word.pluralOnly = e.pluralOnly
        if word.forms == nil { word.forms = e.principalParts }
        if word.english.isEmpty { word.english = shortGloss(e.glosses) }
        if word.exampleGerman == nil, let ex = e.example {
            word.exampleGerman = ex.german
            word.exampleEnglish = ex.english
        }
    }

    /// The first sense, cut to something that fits on a card.
    static func shortGloss(_ glosses: [String]) -> String {
        guard let first = glosses.first else { return "" }
        let parts = first.split(separator: ",").prefix(3).map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.joined(separator: ", ")
    }

    static func label(_ source: LookupResult.Source) -> String? {
        switch source {
        case .wiktionary: "Wiktionary"
        case .compound(let head): "from “\(head)”"
        case .suffixGuess: "guess from the ending"
        case .notFound, .unreachable: nil
        }
    }
}

/// German text to speech, with the on-device voice.
@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()

    func say(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "de-DE")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synth.speak(u)
    }
}

/// What to review now: everything due, plus a few new cards a day.
@MainActor
enum Queue {
    static var newPerDay: Int {
        get { UserDefaults.standard.object(forKey: "newPerDay") as? Int ?? 15 }
        set { UserDefaults.standard.set(newValue, forKey: "newPerDay") }
    }

    static func next(context: ModelContext, now: Date = .now) -> [Card] {
        let due = (try? context.fetch(FetchDescriptor<Card>(
            predicate: #Predicate { !$0.isNew && $0.due <= now }, sortBy: [SortDescriptor(\.due)]))) ?? []
        let startOfDay = Calendar.current.startOfDay(for: now)
        let firstReviewsToday = ((try? context.fetch(FetchDescriptor<Review>(predicate: #Predicate { $0.at >= startOfDay }))) ?? [])
            .compactMap(\.card).filter { ($0.reviews ?? []).map(\.at).min().map { $0 >= startOfDay } ?? false }
        let newLeft = max(0, newPerDay - Set(firstReviewsToday.map(\.persistentModelID)).count)
        var fresh = FetchDescriptor<Card>(predicate: #Predicate { $0.isNew }, sortBy: [SortDescriptor(\.createdAt)])
        fresh.fetchLimit = newLeft * 4      // over-fetch, then keep one kind per word for variety
        var seenWords = Set<PersistentIdentifier>()
        let newCards = ((try? context.fetch(fresh)) ?? []).filter { card in
            // Meaning first: a word's other drills wait until it's been met.
            guard card.kind == .meaning, let w = card.word else { return false }
            return seenWords.insert(w.persistentModelID).inserted
        }.prefix(newLeft)
        // Other drills of words that have been met become available as "new" too.
        let followUps = ((try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.isNew }))) ?? [])
            .filter { card in
                card.kind != .meaning &&
                (card.word?.cards ?? []).contains { $0.kind == .meaning && !$0.isNew }
            }.prefix(newLeft)
        return due + Array(newCards) + Array(followUps)
    }

    static func answer(_ card: Card, _ rating: Rating, context: ModelContext, now: Date = .now) {
        let review = Review(rating: rating, at: now)
        context.insert(review)
        review.card = card
        card.recompute()
        try? context.save()
    }

    /// When the next review would be for each rating, for the button labels.
    static func preview(_ card: Card, now: Date = .now) -> [Rating: String] {
        let s = card.state
        var out: [Rating: String] = [:]
        for r in Rating.allCases {
            let next = Scheduler().next(s, r, now: now)
            out[r] = humanInterval(next.due.timeIntervalSince(now))
        }
        return out
    }

    static func humanInterval(_ t: TimeInterval) -> String {
        if t < 3600 { return "\(max(1, Int(t / 60)))m" }
        if t < 86_400 { return "\(Int(t / 3600))h" }
        let d = Int((t / 86_400).rounded())
        return d < 30 ? "\(d)d" : d < 365 ? "\(d / 30)mo" : "\(d / 365)y"
    }
}
