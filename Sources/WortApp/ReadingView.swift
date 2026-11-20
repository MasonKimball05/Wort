import SwiftData
import SwiftUI
import WortCore

/// Texts you've pasted in to read, newest first.
struct ReadingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Reading.addedAt, order: .reverse) private var readings: [Reading]
    @State private var pasting = false

    var body: some View {
        List {
            ForEach(readings) { r in
                NavigationLink { ReaderView(reading: r) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.title).font(.headline).lineLimit(1)
                        Text(r.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        Text("\(r.text.split(whereSeparator: \.isWhitespace).count) words")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(readings[i]) }
                try? context.save()
            }
        }
        .overlay {
            if readings.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to read yet", systemImage: "book.pages")
                } description: {
                    Text("Paste a German article, email or chapter. Tap any word to see what it means and add it to your words.")
                } actions: {
                    Button("Paste a text") { pasting = true }.buttonStyle(.borderedProminent)
                    Button("Try a sample") { addSample() }
                }
            }
        }
        .navigationTitle("Reading")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Paste a text", systemImage: "plus") { pasting = true }
            }
        }
        .sheet(isPresented: $pasting) { PasteTextView() }
    }

    func addSample() {
        context.insert(Reading(title: "Der verspätete Zug", text: Self.sample))
        try? context.save()
    }

    /// A short original text at about B2/C1, to try the reader with.
    static let sample = """
    Als der Zug endlich in den Bahnhof einfuhr, hatte Lena die Hoffnung schon fast aufgegeben. Seit über einer Stunde stand sie auf dem zugigen Bahnsteig, den Kaffee längst ausgetrunken, und hörte sich die immer gleichen Durchsagen an.

    Eine Weichenstörung, hieß es zunächst, dann ein Polizeieinsatz, schließlich gar keine Begründung mehr. Die Fahrgäste um sie herum reagierten unterschiedlich: Manche schimpften lautstark, andere hatten sich offenbar längst damit abgefunden und vertieften sich in ihre Bücher.

    Lena hingegen ärgerte sich weniger über die Verspätung als über sich selbst. Hätte sie doch den früheren Zug genommen, wie ihr Bruder es ihr geraten hatte! Nun würde sie das Vorstellungsgespräch, auf das sie sich wochenlang vorbereitet hatte, nur mit Mühe rechtzeitig erreichen.
    """
}

/// Paste or type a text; the title is optional.
struct PasteTextView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (optional)", text: $title)
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 240)
                        .autocorrectionDisabled()
                    // PasteButton reads the clipboard without the "allow paste?" prompt.
                    PasteButton(payloadType: String.self) { strings in
                        text = strings.joined(separator: "\n\n")
                    }
                } header: {
                    Text("German text")
                } footer: {
                    Text("Blank lines start a new paragraph.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New text")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 460)
        #endif
    }

    func save() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.trimmingCharacters(in: .whitespaces)
        context.insert(Reading(title: name.isEmpty ? ReadingText.title(for: body) : name, text: body))
        try? context.save()
        dismiss()
    }
}

/// The text, paragraph by paragraph. Tap a word (click, on the Mac) to see what
/// it means, its gender and form, and add it. Words you already have are tinted.
struct ReaderView: View {
    @Bindable var reading: Reading
    @Query private var words: [Word]
    @State private var known: Set<String> = []
    #if os(iOS)
    // One sheet for the whole text: tapping a word in another paragraph while
    // it's open swaps the word shown.
    @State private var picked: PickedWord?
    #endif

    var body: some View {
        let paragraphs = ReadingText.paragraphs(reading.text)
        ScrollView {
            // Lazy, so a long text only lays out the paragraphs on screen. Words
            // aren't looked up ahead of time here (a whole article would mean
            // hundreds of requests); a tap looks up that one word.
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(reading.title).font(.title2.bold())
                    Label("Tap a word to look it up. Words you already have are in color.", systemImage: "hand.tap")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                    #if os(iOS)
                    TappableSentence(text: p, font: .title3, prefetch: false, underlineAll: false,
                                     hover: false, known: known, keepsSentence: true,
                                     onPick: { picked = PickedWord(token: $0, source: "reading", sentence: $1) })
                    #else
                    TappableSentence(text: p, font: .title3, prefetch: false, underlineAll: false,
                                     hover: false, known: known, keepsSentence: true)
                    #endif
                }
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(reading.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .wordSheet($picked)
        #endif
        .onAppear { reading.openedAt = .now }
        // Recomputed when a word is added, so it turns colored right away.
        .task(id: words.count) {
            known = ReadingText.knownForms(words.map { (lemma: $0.lemma, plural: $0.plural) })
        }
    }
}
