import SwiftData
import SwiftUI
import WortCore

/// Lookups for tapped words, remembered for the rest of the run.
@MainActor
final class ExplanationCache {
    static let shared = ExplanationCache()
    private var done: [String: WordExplanation] = [:]
    /// Lookups under way, so a tap during prefetching waits for the same request.
    private var running: [String: Task<WordExplanation, Never>] = [:]
    private let lookup = WordLookup(knownNouns: StarterDeck.knownNouns())

    func explain(_ token: String) async -> WordExplanation {
        let key = ParsedInput(token).word
        if let hit = done[key] { return hit }
        if let task = running[key] { return await task.value }
        let lookup = self.lookup
        let task = Task { await lookup.explain(key) }
        running[key] = task
        let x = await task.value
        running[key] = nil
        if x.lookup.source != .unreachable { done[key] = x }
        return x
    }

    /// Looks up a sentence's words ahead of time, a few at a time, so a tap is
    /// usually instant. Stops early if the sentence goes away (`Task` cancelled).
    func prefetch(_ text: String) async {
        let words = text.split(separator: " ").map(String.init)
            .filter { !$0.contains("___") }
            .map { ParsedInput($0).word }
            .filter { $0.count > 1 && done[$0] == nil }
        var seen = Set<String>()
        let unique = words.filter { seen.insert($0).inserted }
        for chunk in stride(from: 0, to: unique.count, by: 3).map({ Array(unique[$0..<min($0 + 3, unique.count)]) }) {
            if Task.isCancelled { return }
            await withTaskGroup(of: Void.self) { group in
                for w in chunk { group.addTask { _ = await self.explain(w) } }
            }
        }
    }
}

/// A sentence whose words can be tapped (or hovered, on the Mac) for their
/// meaning, gender, form and case. The gap stays a gap.
struct TappableSentence: View {
    let text: String
    var font: Font = .title3.weight(.medium)
    /// Look every word up as soon as the sentence appears. Right for a short
    /// exercise; off for a long text, which would mean hundreds of requests.
    var prefetch = true
    /// Dotted underline under every word (exercises). Off in running text.
    var underlineAll = true
    /// Mac: open the popover on hover. Off in running text, where the mouse
    /// crosses words all the time.
    var hover = true
    /// Words you already have (lowercased), shown in the accent color.
    var known: Set<String> = []
    /// Keep the sentence a word came from, as its example when it's added
    /// (reading). Off in exercises, whose sentences have a gap in them.
    var keepsSentence = false
    /// iPhone: someone above shows the sheet (a text of many paragraphs needs one
    /// sheet for all of them). Nil: this sentence shows its own.
    var onPick: ((String, String?) -> Void)? = nil
    #if os(iOS)
    // One sheet for the whole sentence, so tapping another word while it's open
    // swaps the word shown instead of trying to stack a second sheet.
    @State private var picked: PickedWord?
    #endif

    var body: some View {
        content
            .task(id: text) { if prefetch { await ExplanationCache.shared.prefetch(text) } }
            #if os(iOS)
            .wordSheet($picked)
            .onChange(of: text) { picked = nil }
            #endif
    }

    #if os(iOS)
    func show(_ token: String, _ sentence: String?) {
        if let onPick { onPick(token, sentence); return }
        PickedWord.dismissKeyboard()
        picked = PickedWord(token: token)
    }
    #endif

    var content: some View {
        WrapLayout(spacing: 5) {
            ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { i, piece in
                let token = String(piece)
                let sentence = keepsSentence ? ReadingText.sentence(around: i, in: text) : nil
                if token.contains("___") {
                    Text(token.replacingOccurrences(of: "___", with: "＿＿＿")).font(font)
                } else {
                    #if os(iOS)
                    WordToken(token: token, font: font, underline: underlineAll, hover: hover,
                              known: ReadingText.isKnown(token, in: known), onTap: { show(token, sentence) })
                    #else
                    WordToken(token: token, font: font, underline: underlineAll, hover: hover,
                              known: ReadingText.isKnown(token, in: known), sentence: sentence,
                              source: keepsSentence ? "reading" : "grammar")
                    #endif
                }
            }
        }
    }
}

#if os(iOS)
/// The word shown in the iPhone sheet. One fixed id: a new word updates the
/// open sheet rather than replacing it.
struct PickedWord: Identifiable {
    let id = "word"
    let token: String
    var source = "grammar"
    var sentence: String? = nil

    /// The keyboard would cover the sheet's lower half.
    @MainActor static func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// A half-height sheet, like the system's Look Up. An iPhone popover
    /// dismisses itself whenever the layout under it shifts (the keyboard, a
    /// redraw), so it closed on its own; a sheet stays until swiped away.
    func wordSheet(_ picked: Binding<PickedWord?>) -> some View {
        sheet(item: picked) { p in
            WordInfoView(token: p.token, inSheet: true, source: p.source, sentence: p.sentence)
                .id(p.token)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }
}
#endif

struct WordToken: View {
    let token: String
    let font: Font
    var underline = true
    var hover = true
    var known = false
    /// iPhone: the sentence shows its sheet. Mac: the word shows its own popover.
    var onTap: (() -> Void)? = nil
    var sentence: String? = nil
    var source = "grammar"
    @State private var showing = false
    @State private var hoverTask: Task<Void, Never>?

    var lookable: Bool { ParsedInput(token).word.count > 1 }

    var body: some View {
        Text(token)
            .font(font)
            .foregroundStyle(known ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .underline(lookable && underline, pattern: .dot, color: .secondary.opacity(0.5))
            .contentShape(Rectangle())
            .onTapGesture {
                guard lookable else { return }
                if let onTap { onTap() } else { showing.toggle() }
            }
            #if os(macOS)
            .onHover { inside in
                hoverTask?.cancel()
                guard lookable, hover else { return }
                if inside {
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        if !Task.isCancelled { showing = true }
                    }
                }
            }
            // Below the word, clear of the toolbar and tabs.
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                WordInfoView(token: token, source: source, sentence: sentence)
            }
            #endif
            .accessibilityAddTraits(lookable ? .isButton : [])
            .accessibilityHint(lookable ? "Shows the meaning and grammar of this word" : "")
    }
}

/// What a word is: meaning, article and gender, plural, verb forms, the form it
/// takes here (case, number, tense) and, for a separable verb, its base verb.
struct WordInfoView: View {
    @Environment(\.modelContext) private var context
    let token: String
    /// In the iPhone sheet: full width and scrolling; in the Mac popover: 320 wide.
    var inSheet = false
    /// Where an added word came from: "grammar", "reading".
    var source = "grammar"
    /// The sentence the word was tapped in, kept as its example.
    var sentence: String? = nil
    @State private var x: WordExplanation?
    @State private var added = false
    @State private var alreadyHave = false

    var entry: DictionaryEntry? { x?.lookup.entries.first }

    var body: some View {
        Group {
            if inSheet {
                ScrollView { content.padding(.top, 8) }
            } else {
                // NSPopover takes its size when it opens (while still loading) and
                // doesn't grow with ViewThatFits, so the content sizes itself and the
                // popover follows its ideal size.
                content.fixedSize(horizontal: false, vertical: true).frame(width: 320)
            }
        }
        .task {
            x = await ExplanationCache.shared.explain(token)
            if let e = entry { alreadyHave = Store.has(lemma: e.lemma, partOfSpeech: e.partOfSpeech, context: context) }
        }
    }

    @ViewBuilder var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let x {
                if x.lookup.source == .unreachable {
                    Label("Couldn't reach Wiktionary", systemImage: "wifi.slash").font(.callout)
                } else if let e = entry {
                    HStack(alignment: .firstTextBaseline) {
                        Text(display(e)).font(inSheet ? .title.bold() : .title3.bold())
                        Spacer(minLength: 12)
                        Button { Speaker.shared.say(display(e)) } label: { Image(systemName: "speaker.wave.2") }
                            .buttonStyle(.borderless)
                    }
                    Text(details(e)).font(.caption).foregroundStyle(.secondary)
                    if let form = x.lookup.formDescription, let entered = x.lookup.enteredForm {
                        Text("**\(entered)**: \(form)").font(.callout)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                    ForEach(Array(e.glosses.prefix(3).enumerated()), id: \.offset) { i, g in
                        Text("\(i + 1). \(g)").font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    if let usage = e.usage {
                        Text(usage).font(.caption).italic().foregroundStyle(.secondary)
                    }
                    if let prefix = x.separablePrefix, let base = x.base {
                        Divider()
                        Text("**\(prefix)** + **\(base.lemma)**").font(.callout)
                        if let g = base.glosses.first {
                            Text(g).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Divider()
                    if alreadyHave && !added {
                        Label("Already in your words", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
                    } else {
                        Button(added ? "Added to your words" : "Add to Wort", systemImage: added ? "checkmark" : "plus") { add(e) }
                            .disabled(added)
                            .font(.callout)
                    }
                } else if let form = x.lookup.formDescription {
                    Text("**\(token)**: \(form)").font(.callout)
                } else {
                    Text("No entry for „\(ParsedInput(token).word)“").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(inSheet ? 20 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func display(_ e: DictionaryEntry) -> String {
        if let g = e.gender { return "\(g.article) \(e.lemma)" }
        return e.pluralOnly ? "die \(e.lemma) (pl.)" : e.lemma
    }

    /// "noun · neuter · plural Bücher", "verb · rief an, hat angerufen".
    func details(_ e: DictionaryEntry) -> String {
        var parts = [e.partOfSpeech.rawValue]
        if let g = e.gender {
            parts.append(g == .masculine ? "masculine" : g == .feminine ? "feminine" : "neuter")
        }
        if let p = e.plural { parts.append("plural \(p)") }
        if e.noPlural { parts.append("no plural") }
        if let f = e.principalParts { parts.append(f) }
        return parts.joined(separator: " · ")
    }

    func add(_ e: DictionaryEntry) {
        Store.add(lemma: e.lemma, partOfSpeech: e.partOfSpeech, gender: e.gender, plural: e.plural,
                  pluralOnly: e.pluralOnly, english: Enricher.shortGloss(e.glosses),
                  // Your own sentence beats the dictionary's.
                  example: sentence.map { Example(german: $0, english: nil) } ?? e.example,
                  source: source, genderSource: "Wiktionary", forms: e.principalParts, context: context)
        try? context.save()
        added = true
    }
}
