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
            Section("Drills") {
                ForEach((word.cards ?? []).sorted { $0.kindRaw < $1.kindRaw }) { card in
                    LabeledContent(card.kind.title) {
                        Text(card.isNew ? "new" : "due \(card.due.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(.secondary)
                    }
                }
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

    /// A text field for an optional string: empty means nil.
    func optional(_ b: Binding<String?>) -> Binding<String> {
        Binding(get: { b.wrappedValue ?? "" }, set: { b.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
