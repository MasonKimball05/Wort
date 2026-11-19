import Foundation
import SwiftData
import WortCore

// CloudKit rules for SwiftData: every attribute optional or defaulted, every
// relationship optional, no @Attribute(.unique). Duplicates (the same word added
// on two devices) are merged by `Store.deduplicate()` on the `key` instead.

@Model
final class Word {
    /// WordKey: "n:Buch", "n:See:f", "v:gehen". Same word, same key, on every device.
    var key: String = ""
    var lemma: String = ""
    var partOfSpeechRaw: String = PartOfSpeech.other.rawValue
    var genderRaw: String?
    var plural: String?
    var pluralOnly: Bool = false
    var english: String = ""
    var exampleGerman: String?
    var exampleEnglish: String?
    /// "starter-A1", "manual", "share", "hop"…
    var source: String = "manual"
    var createdAt: Date = Date.now
    /// Saved from the share sheet or a link and not looked up yet.
    var needsLookup: Bool = false
    /// How the gender was found, shown so a guess isn't mistaken for a fact.
    var genderSource: String?
    /// Preposition and case a verb, adjective or phrase takes: "auf + Akk.".
    var government: String?
    /// Principal parts of a strong verb: "verzieh, hat verziehen".
    var forms: String?

    @Relationship(deleteRule: .cascade, inverse: \Card.word)
    var cards: [Card]? = []

    init(lemma: String, partOfSpeech: PartOfSpeech, gender: Gender?, english: String, source: String) {
        self.lemma = lemma
        self.partOfSpeechRaw = partOfSpeech.rawValue
        self.genderRaw = gender?.rawValue
        self.english = english
        self.source = source
        self.key = WordKey.make(lemma: lemma, partOfSpeech: partOfSpeech, gender: gender)
    }

    var partOfSpeech: PartOfSpeech {
        get { PartOfSpeech(rawValue: partOfSpeechRaw) ?? .other }
        set { partOfSpeechRaw = newValue.rawValue; refreshKey() }
    }

    var gender: Gender? {
        get { genderRaw.flatMap(Gender.init(rawValue:)) }
        set { genderRaw = newValue?.rawValue; refreshKey() }
    }

    /// "das Buch", "gehen", "die Leute".
    var display: String {
        if let g = gender { return "\(g.article) \(lemma)" }
        if pluralOnly { return "die \(lemma)" }
        return lemma
    }

    func refreshKey() { key = WordKey.make(lemma: lemma, partOfSpeech: partOfSpeech, gender: gender, government: government) }

    /// Adds the drills this word should have and doesn't yet (a gender found
    /// later adds the article drill), without touching existing ones.
    func ensureCards(context: ModelContext) {
        let wanted = CardKind.kinds(partOfSpeech: partOfSpeech, gender: gender, plural: pluralOnly ? nil : plural,
                                    government: government, forms: forms)
        let have = Set((cards ?? []).map(\.kindRaw))
        for kind in wanted where !have.contains(kind.rawValue) {
            let card = Card(kind: kind)
            context.insert(card)
            card.word = self
        }
    }
}

@Model
final class Card {
    var kindRaw: String = CardKind.meaning.rawValue
    var createdAt: Date = Date.now
    /// Cached from the review log (see `recompute`), so the queue can be queried.
    var due: Date = Date.now
    var isNew: Bool = true
    var word: Word?

    @Relationship(deleteRule: .cascade, inverse: \Review.card)
    var reviews: [Review]? = []

    init(kind: CardKind) {
        kindRaw = kind.rawValue
    }

    var kind: CardKind { CardKind(rawValue: kindRaw) ?? .meaning }

    var events: [ReviewEvent] {
        (reviews ?? []).map { ReviewEvent(rating: Rating(rawValue: $0.ratingRaw) ?? .good, at: $0.at) }
    }

    var state: CardState { Scheduler().replay(events, createdAt: createdAt) }

    /// Re-derives `due` and `isNew` from the reviews. Run after answering, and
    /// after a sync brings in reviews made on the other device.
    func recompute() {
        let s = state
        // Assign only on a real change: an unchanged card written back on every
        // launch would be uploaded to CloudKit again from each device.
        if due != s.due { due = s.due }
        if isNew != s.isNew { isNew = s.isNew }
    }
}

/// One answer. Only ever inserted, so two devices never fight over a card.
@Model
final class Review {
    var ratingRaw: Int = Rating.good.rawValue
    var at: Date = Date.now
    var card: Card?

    init(rating: Rating, at: Date) {
        ratingRaw = rating.rawValue
        self.at = at
    }
}
