import Foundation
import SwiftData
import WortCore

enum Store {
    static let schema = Schema([Word.self, Card.self, Review.self])

    /// The database. Syncs through the iCloud container when the build is signed
    /// with the CloudKit entitlement (`.automatic`); a local-only store otherwise,
    /// so an unsigned or simulator build still runs.
    /// Whether this run syncs, shown in Settings so a silent fallback can't pass
    /// for working sync (sync can only really be tested on two signed-in devices).
    nonisolated(unsafe) static var syncStatus = "Unknown"

    static func makeContainer() -> ModelContainer {
        let url = AppGroup.containerURL.appendingPathComponent("Wort.store")
        do {
            // Throws without the iCloud entitlement (unsigned and simulator builds).
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .private("iCloud.com.masonkimball.wort"))
            let container = try ModelContainer(for: schema, configurations: config)
            syncStatus = "On (iCloud)"
            return container
        } catch {
            syncStatus = "Local only: \(error.localizedDescription)"
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: config)
        }
    }

    // MARK: Adding words

    /// Adds a word unless one with the same key exists; returns the word either way.
    @MainActor @discardableResult
    static func add(lemma: String, partOfSpeech: PartOfSpeech, gender: Gender?, plural: String?,
                    pluralOnly: Bool = false, english: String, example: Example?, source: String,
                    genderSource: String? = nil, government: String? = nil, forms: String? = nil,
                    context: ModelContext) -> Word {
        let key = WordKey.make(lemma: lemma, partOfSpeech: partOfSpeech, gender: gender, government: government)
        if let existing = try? context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.key == key })).first {
            return existing
        }
        let word = Word(lemma: lemma, partOfSpeech: partOfSpeech, gender: gender, english: english, source: source)
        word.plural = plural
        word.pluralOnly = pluralOnly
        word.exampleGerman = example?.german
        word.exampleEnglish = example?.english
        word.genderSource = genderSource
        word.government = government
        word.forms = forms
        word.refreshKey()
        context.insert(word)
        word.ensureCards(context: context)
        return word
    }

    /// How many words of a level are already in the collection (for Settings).
    /// By key, not by source: a word in two decks (der Chef is in A1 and C1)
    /// counts for both, however it was first added.
    @MainActor
    static func imported(level: String, context: ModelContext) -> Int {
        let have = Set(((try? context.fetch(FetchDescriptor<Word>())) ?? []).map(\.key))
        return StarterDeck.words(level: level).filter { have.contains($0.key) }.count
    }

    /// Imports a starter deck level. Explicit, never automatic: if both devices
    /// seeded on first launch, CloudKit would merge two copies of every card.
    @MainActor
    static func importStarter(level: String, context: ModelContext) -> Int {
        let existing = Set(((try? context.fetch(FetchDescriptor<Word>())) ?? []).map(\.key))
        var added = 0
        for w in StarterDeck.words(level: level) where !existing.contains(w.key) {
            add(lemma: w.lemma, partOfSpeech: w.partOfSpeech, gender: w.gender, plural: w.plural,
                pluralOnly: w.pluralOnly, english: w.english,
                example: w.example.map { Example(german: $0, english: nil) },
                source: "starter-\(level)", government: w.government, forms: w.forms, context: context)
            added += 1
        }
        try? context.save()
        return added
    }

    /// Saved words from the share extension and `wort://add` links, as words
    /// marked `needsLookup` so the next lookup pass fills them in.
    @MainActor
    static func importInbox(context: ModelContext) -> Int {
        let items = AppGroup.inbox.drain()
        for item in items {
            // A shared sentence waits on the Add tab for the person to pick the word.
            if item.text.isEmpty {
                if let s = item.sentence { SavedSentences.add(s) }
                continue
            }
            addPending(german: item.text, english: item.english, example: item.sentence,
                       source: item.source, context: context)
        }
        try? context.save()
        return items.count
    }

    @MainActor
    static func addPending(german: String, english: String?, example: String?, source: String, context: ModelContext) {
        let input = ParsedInput(german)
        let pos: PartOfSpeech = input.looksLikeNoun || input.gender != nil ? .noun : .other
        let key = WordKey.make(lemma: input.word, partOfSpeech: pos, gender: input.gender)
        let isNew = ((try? context.fetchCount(FetchDescriptor<Word>(predicate: #Predicate { $0.key == key }))) ?? 0) == 0
        let word = add(lemma: input.word, partOfSpeech: pos, gender: input.gender, plural: nil,
                       english: english ?? "", example: example.map { Example(german: $0, english: nil) },
                       source: source, context: context)
        // "verzichten auf" from Hop: keep the preposition; the lookup finds the verb.
        let phrase = VerbPhraseInput(german)
        if let prep = phrase.preposition, word.government == nil {
            word.government = prep
            word.lemma = (phrase.reflexive ? "sich " : "") + phrase.core
        }
        // A new word is always looked up: even with an English meaning from Hop, the
        // part of speech, article, plural and verb forms come from Wiktionary. The
        // lookup only fills empty fields, so nothing that came with the link is lost.
        if isNew { word.needsLookup = true }
    }

    // MARK: Keeping it consistent

    /// Merges words with the same key (added on two devices, or a deck imported
    /// on both) into the oldest, moving reviews across so no history is lost,
    /// then re-derives every card's due date from its reviews.
    @MainActor
    static func deduplicate(context: ModelContext) {
        guard let words = try? context.fetch(FetchDescriptor<Word>(sortBy: [SortDescriptor(\.createdAt)])) else { return }
        var keep: [String: Word] = [:]
        for word in words {
            guard let survivor = keep[word.key] else { keep[word.key] = word; continue }
            for card in word.cards ?? [] {
                if let target = (survivor.cards ?? []).first(where: { $0.kindRaw == card.kindRaw }) {
                    for review in card.reviews ?? [] { review.card = target }
                    context.delete(card)
                } else {
                    card.word = survivor
                }
            }
            if survivor.english.isEmpty { survivor.english = word.english }
            if survivor.exampleGerman == nil { survivor.exampleGerman = word.exampleGerman }
            context.delete(word)
        }
        // Cards of one kind on one word, the same merge one level down.
        for word in keep.values {
            var byKind: [String: Card] = [:]
            for card in (word.cards ?? []).sorted(by: { $0.createdAt < $1.createdAt }) {
                if let first = byKind[card.kindRaw] {
                    for review in card.reviews ?? [] { review.card = first }
                    context.delete(card)
                } else {
                    byKind[card.kindRaw] = card
                }
            }
            for card in byKind.values { card.recompute() }
        }
        try? context.save()
    }
}


/// Sentences shared without a single word picked. Shown on the Add tab, where
/// tapping a word in one looks it up with the sentence as its example. Kept per
/// device (they're a to-do list, not part of the collection).
enum SavedSentences {
    static let key = "savedSentences"

    static var all: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func add(_ sentence: String) {
        var list = all
        guard !list.contains(sentence) else { return }
        list.append(sentence)
        UserDefaults.standard.set(Array(list.suffix(50)), forKey: key)
    }

    static func remove(_ sentence: String) {
        UserDefaults.standard.set(all.filter { $0 != sentence }, forKey: key)
    }

    /// The words of a sentence, without punctuation, for tapping.
    static func words(_ sentence: String) -> [String] {
        sentence.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { !$0.isEmpty }
    }
}
