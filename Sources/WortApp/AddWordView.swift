import SwiftData
import SwiftUI
import WortCore

/// Type a word (with or without its article, or an inflected form like "Bücher");
/// Wort looks it up and fills in the rest, which you can correct before saving.
struct AddWordView: View {
    @Environment(\.modelContext) private var context
    @State private var input = ""
    @State private var result: LookupResult?
    @State private var choice = 0
    @State private var looking = false
    @State private var english = ""
    @State private var government = ""
    @State private var example = ""
    @State private var saved: String?
    @State private var sentences: [String] = []
    /// The shared sentence the current word was picked from, removed once saved.
    @State private var fromSentence: String?

    var entry: DictionaryEntry? {
        guard let r = result, r.entries.indices.contains(choice) else { return nil }
        return r.entries[choice]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("German word, e.g. „die See“ or „verzichten“", text: $input)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit { Task { await lookUp() } }
                    Button(looking ? "Looking up…" : "Look up") { Task { await lookUp() } }
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || looking)
                }

                if !sentences.isEmpty, result == nil {
                    Section("From the share sheet: tap the word to learn") {
                        ForEach(sentences, id: \.self) { sentence in
                            VStack(alignment: .leading, spacing: 8) {
                                FlowWords(words: SavedSentences.words(sentence)) { word in
                                    input = word
                                    fromSentence = sentence
                                    Task { await lookUp(); example = sentence }
                                }
                                Button("Dismiss", role: .destructive) {
                                    SavedSentences.remove(sentence); sentences = SavedSentences.all
                                }
                                .font(.caption).buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if let r = result {
                    if r.source == .unreachable {
                        Section { Label("Couldn't reach Wiktionary. Check your connection and try again.", systemImage: "wifi.slash") }
                    } else if r.entries.isEmpty {
                        Section { Label("No German entry found. You can still save it and fill in the details.", systemImage: "questionmark.circle") }
                    }
                    if r.entries.count > 1 {
                        Section("Which one?") {
                            Picker("Entry", selection: $choice) {
                                ForEach(r.entries.indices, id: \.self) { i in
                                    Text(label(r.entries[i])).tag(i)
                                }
                            }
                            .pickerStyle(.inline).labelsHidden()
                        }
                    }
                    if let e = entry {
                        Section(r.enteredForm.map { "“\($0)” is a form of" } ?? "Found") {
                            LabeledContent("Word", value: display(e))
                            LabeledContent("Type", value: e.partOfSpeech.rawValue.capitalized)
                            if let p = e.plural { LabeledContent("Plural", value: "die \(p)") }
                            if e.pluralOnly { LabeledContent("Plural", value: "plural only") }
                            if let f = e.principalParts { LabeledContent("Forms", value: f) }
                            if case .compound(let head) = r.source { Text("Article taken from “\(head)”").font(.caption) }
                            if r.source == .suffixGuess { Text("Article guessed from the ending. Check it.").font(.caption).foregroundStyle(.orange) }
                        }
                    }
                    Section("Details") {
                        TextField("English", text: $english)
                        TextField("Preposition + case (optional, e.g. auf + Akk.)", text: $government)
                        TextField("Example sentence (optional)", text: $example, axis: .vertical)
                    }
                    Section {
                        Button("Save", systemImage: "plus") { save() }
                            .disabled(entry == nil && input.isEmpty)
                    }
                }
                if let s = saved {
                    Section { Label("Added \(s)", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add a word")
            .onChange(of: choice) { _, _ in fillDetails() }
            .onAppear { sentences = SavedSentences.all }
        }
    }

    func lookUp() async {
        looking = true
        saved = nil
        let lookup = WordLookup(knownNouns: StarterDeck.knownNouns())
        result = await lookup.lookUp(input)
        choice = 0
        fillDetails()
        // "verzichten auf": the typed preposition goes in the field; add the case.
        if let prep = result?.preposition, government.isEmpty { government = "\(prep) + " }
        looking = false
    }

    func fillDetails() {
        guard let e = entry else { return }
        english = Enricher.shortGloss(e.glosses)
        example = e.example?.german ?? ""
    }

    func save() {
        let parsed = ParsedInput(input)
        let e = entry ?? DictionaryEntry(lemma: parsed.word, partOfSpeech: parsed.looksLikeNoun ? .noun : .other)
        let word = Store.add(
            lemma: e.lemma, partOfSpeech: e.partOfSpeech, gender: e.gender ?? parsed.gender,
            plural: e.plural, pluralOnly: e.pluralOnly, english: english,
            example: example.isEmpty ? nil : Example(german: example, english: e.example?.german == example ? e.example?.english : nil),
            source: "manual", genderSource: result.flatMap { Enricher.label($0.source) },
            government: government.isEmpty ? nil : government, forms: e.principalParts, context: context)
        try? context.save()
        if let s = fromSentence { SavedSentences.remove(s); sentences = SavedSentences.all; fromSentence = nil }
        saved = word.display
        input = ""; english = ""; government = ""; example = ""; result = nil
    }

    func display(_ e: DictionaryEntry) -> String {
        if let g = e.gender { return "\(g.article) \(e.lemma)" }
        return e.pluralOnly ? "die \(e.lemma)" : e.lemma
    }

    func label(_ e: DictionaryEntry) -> String {
        "\(display(e)): \(Enricher.shortGloss(e.glosses))"
    }
}


/// Words laid out like text, each one a button.
struct FlowWords: View {
    let words: [String]
    let tap: (String) -> Void

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                Button(w) { tap(w) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }
}

/// A simple wrapping row layout.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            maxX = max(maxX, x)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
