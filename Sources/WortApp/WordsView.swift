import SwiftData
import SwiftUI
import WortCore

struct WordsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Word.lemma) private var words: [Word]
    @State private var search = ""

    var filtered: [Word] {
        guard !search.isEmpty else { return words }
        return words.filter {
            $0.lemma.localizedCaseInsensitiveContains(search) || $0.english.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { word in
                    NavigationLink(value: word) { WordRow(word: word) }
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(filtered[i]) }
                    try? context.save()
                }
            }
            .searchable(text: $search, prompt: "German or English")
            .navigationTitle("Words (\(words.count))")
            .navigationDestination(for: Word.self) { WordDetailView(word: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { TroubleSpotsView() } label: {
                        Label("Trouble spots", systemImage: "exclamationmark.triangle")
                    }
                }
            }
            .overlay {
                if words.isEmpty {
                    ContentUnavailableView("No words yet", systemImage: "character.book.closed",
                                           description: Text("Add one, or a starter deck from Settings."))
                }
            }
        }
    }
}

struct WordRow: View {
    let word: Word
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(word.display).font(.body.weight(.medium))
                if let gov = word.government { Text(gov).font(.caption).foregroundStyle(.secondary) }
                if word.needsLookup { Image(systemName: "clock").font(.caption).foregroundStyle(.secondary) }
            }
            Text(word.english.isEmpty ? "—" : word.english).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct WordDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var word: Word

    var body: some View {
        Form {
            Section("Word") {
                TextField("German", text: $word.lemma)
                Picker("Part of speech", selection: Binding(get: { word.partOfSpeech }, set: { word.partOfSpeech = $0 })) {
                    ForEach(PartOfSpeech.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                if word.partOfSpeech == .noun {
                    Picker("Article", selection: Binding(get: { word.gender }, set: { word.gender = $0; word.genderSource = "you" })) {
                        Text("—").tag(Gender?.none)
                        ForEach(Gender.allCases, id: \.self) { Text($0.article).tag(Gender?.some($0)) }
                    }
                    if let src = word.genderSource { LabeledContent("Article from", value: src) }
                    TextField("Plural", text: optional($word.plural))
                    Toggle("Plural only", isOn: $word.pluralOnly)
                } else {
                    TextField("Preposition + case (e.g. auf + Akk.)", text: optional($word.government))
                }
                if word.partOfSpeech == .verb {
                    TextField("Verb forms (e.g. verzieh, hat verziehen)", text: optional($word.forms))
                }
                TextField("English", text: $word.english)
            }
            Section("Example") {
                TextField("German sentence", text: optional($word.exampleGerman), axis: .vertical)
                TextField("English", text: optional($word.exampleEnglish), axis: .vertical)
            }
            Section {
                ForEach((word.cards ?? []).sorted { $0.kindRaw < $1.kindRaw }) { card in
                    VStack(alignment: .leading, spacing: 2) {
                        LabeledContent(card.kind.title) {
                            Text(card.isNew ? "new" : "due \(card.due.formatted(.relative(presentation: .named)))")
                                .foregroundStyle(.secondary)
                        }
                        if let stats = PracticeStats(card.reviews ?? []) {
                            Text(stats.line).font(.caption).foregroundStyle(stats.hintRate >= 0.5 ? .orange : .secondary)
                        }
                    }
                }
                if let listening = listeningStats {
                    LabeledContent("Listening") { Text(listening).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Drills")
            } footer: {
                Text("A hint lowers how much an answer counts, so a word you often need hints for comes back sooner.")
            }
            Section {
                Button("Say it", systemImage: "speaker.wave.2") { Speaker.shared.say(word.display) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(word.display)
        .onDisappear {
            word.refreshKey()
            word.ensureCards(context: context)
            try? context.save()
            Store.deduplicate(context: context)
        }
    }

    var listeningStats: String? {
        let key = word.key
        let attempts = (try? context.fetch(FetchDescriptor<ListeningAttempt>(predicate: #Predicate { $0.wordKey == key }))) ?? []
        guard !attempts.isEmpty else { return nil }
        let right = attempts.filter(\.correct).count, hints = attempts.filter(\.hinted).count
        return "\(right) of \(attempts.count) right" + (hints > 0 ? ", \(hints) with a hint" : "")
    }

    /// A text field for an optional string: empty means nil.
    func optional(_ b: Binding<String?>) -> Binding<String> {
        Binding(get: { b.wrappedValue ?? "" }, set: { b.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

/// How a drill has gone: answers, misses, hints.
struct PracticeStats {
    let answers: Int
    let misses: Int
    let hints: Int

    init?(_ reviews: [Review]) {
        guard !reviews.isEmpty else { return nil }
        answers = reviews.count
        misses = reviews.filter { $0.ratingRaw == Rating.again.rawValue }.count
        hints = reviews.filter(\.hinted).count
    }

    var hintRate: Double { Double(hints) / Double(answers) }

    var line: String {
        var parts = ["\(answers) \(answers == 1 ? "answer" : "answers")"]
        if misses > 0 { parts.append("\(misses) missed") }
        if hints > 0 { parts.append("hint \(hints)×") }
        return parts.joined(separator: " · ")
    }
}
