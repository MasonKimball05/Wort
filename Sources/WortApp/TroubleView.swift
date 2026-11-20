import SwiftData
import SwiftUI
import WortCore

/// Trouble spots, worked out from the answer logs.
@MainActor
enum TroubleData {
    static func grammar(_ attempts: [GrammarAttempt]) -> [(item: GrammarItem, summary: Trouble.Summary)] {
        let byItem = Dictionary(grouping: attempts, by: \.itemID)
            .mapValues { $0.map { Trouble.Result(correct: $0.correct, at: $0.at) } }
        let ranked = Trouble.ranked(byItem)
        let items = GrammarBank.items(ids: ranked.map(\.id))
        return ranked.compactMap { r in items[r.id].map { (item: $0, summary: r.summary) } }
    }

    /// Per drill (a word's article drill apart from its meaning drill). "Again"
    /// is a miss; Hard, Good and Easy are right.
    static func words(_ reviews: [Review]) -> [(card: Card, summary: Trouble.Summary)] {
        var cards: [PersistentIdentifier: Card] = [:]
        var results: [PersistentIdentifier: [Trouble.Result]] = [:]
        for r in reviews {
            guard let card = r.card, card.word != nil else { continue }
            let id = card.persistentModelID
            cards[id] = card
            results[id, default: []].append(Trouble.Result(correct: r.ratingRaw != Rating.again.rawValue, at: r.at))
        }
        return Trouble.ranked(results).compactMap { r in cards[r.id].map { (card: $0, summary: r.summary) } }
    }

    /// The worst ten, read fresh from the store for each round, so items
    /// answered right drop out.
    static func practice(context: ModelContext) -> [GrammarItem] {
        let attempts = (try? context.fetch(FetchDescriptor<GrammarAttempt>())) ?? []
        return Array(grammar(attempts).prefix(10).map(\.item))
    }

    static func weakRules(_ attempts: [GrammarAttempt]) -> [Trouble.WeakRule] {
        Trouble.weakRules(attempts.map { (itemID: $0.itemID, correct: $0.correct) })
    }
}

struct TroubleSpotsView: View {
    @Query private var attempts: [GrammarAttempt]
    @Query private var reviews: [Review]
    @State private var grammar: [(item: GrammarItem, summary: Trouble.Summary)] = []
    @State private var words: [(card: Card, summary: Trouble.Summary)] = []
    @State private var rules: [Trouble.WeakRule] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded, grammar.isEmpty, words.isEmpty, rules.isEmpty {
                ContentUnavailableView("No trouble spots", systemImage: "checkmark.seal",
                                       description: Text("Words and exercises you keep missing show up here, until you've got them right a few times running."))
                    .listRowBackground(Color.clear)
            }

            if !rules.isEmpty {
                Section {
                    ForEach(rules, id: \.rule) { r in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(r.rule).font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(r.right) of \(r.total) right").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            ProgressView(value: Double(r.right), total: Double(r.total))
                                .tint(r.accuracy < 50 ? .red : .orange)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Adjective endings you miss")
                } footer: {
                    Text("Across every phrase that tests the rule, so it's the rule that's shaky, not one sentence.")
                }
            }

            if !grammar.isEmpty {
                Section {
                    NavigationLink {
                        GrammarSessionView(topic: grammar[0].item.topic, practice: TroubleData.practice)
                    } label: {
                        Label("Practice these (\(min(grammar.count, 10)))", systemImage: "play.fill")
                            .font(.body.weight(.semibold))
                    }
                    ForEach(grammar, id: \.item.id) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(g.item.solved).font(.callout)
                            HStack(spacing: 8) {
                                Chip(text: g.item.topic.title, tint: g.item.topic.tint)
                                Text(missed(g.summary)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Grammar")
                }
            }

            if !words.isEmpty {
                Section {
                    ForEach(words, id: \.card.persistentModelID) { w in
                        if let word = w.card.word {
                            NavigationLink { WordDetailView(word: word) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(word.display).font(.body.weight(.medium))
                                        Chip(text: w.card.kind.title, tint: .orange)
                                    }
                                    Text(word.english).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                    Text(missed(w.summary)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Words")
                } footer: {
                    Text("These come back in Review on their own schedule; a miss already brings a card back sooner.")
                }
            }
        }
        .navigationTitle("Trouble spots")
        .task(id: attempts.count + reviews.count) { reload() }
    }

    func reload() {
        grammar = TroubleData.grammar(attempts)
        words = TroubleData.words(reviews)
        rules = TroubleData.weakRules(attempts)
        loaded = true
    }

    func missed(_ s: Trouble.Summary) -> String {
        "Missed \(s.misses) of the last \(s.recent) · \(s.lastMissed.formatted(.relative(presentation: .named)))"
    }
}
