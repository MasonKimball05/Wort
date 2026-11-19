import SwiftData
import SwiftUI
import WortCore

/// Lookups for tapped words, remembered for the rest of the run.
@MainActor
final class ExplanationCache {
    static let shared = ExplanationCache()
    private var done: [String: WordExplanation] = [:]
    private let lookup = WordLookup(knownNouns: StarterDeck.knownNouns())

    func explain(_ token: String) async -> WordExplanation {
        let key = ParsedInput(token).word
        if let hit = done[key] { return hit }
        let x = await lookup.explain(key)
        if x.lookup.source != .unreachable { done[key] = x }
        return x
    }
}

/// A sentence whose words can be tapped (or hovered, on the Mac) for their
/// meaning, gender, form and case. The gap stays a gap.
struct TappableSentence: View {
    let text: String
    var font: Font = .title3.weight(.medium)

    var body: some View {
        WrapLayout(spacing: 5) {
            ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { _, piece in
                let token = String(piece)
                if token.contains("___") {
                    Text(token.replacingOccurrences(of: "___", with: "＿＿＿")).font(font)
                } else {
                    WordToken(token: token, font: font)
                }
            }
        }
    }
}

struct WordToken: View {
    let token: String
    let font: Font
    @State private var showing = false
    @State private var hoverTask: Task<Void, Never>?

    var lookable: Bool { ParsedInput(token).word.count > 1 }

    var body: some View {
        Text(token)
            .font(font)
            .underline(lookable, pattern: .dot, color: .secondary.opacity(0.5))
            .contentShape(Rectangle())
            .onTapGesture { if lookable { showing.toggle() } }
            #if os(macOS)
            .onHover { inside in
                hoverTask?.cancel()
                guard lookable else { return }
                if inside {
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        if !Task.isCancelled { showing = true }
                    }
                }
            }
            #endif
            // Below the word: above it is the navigation bar, below it the room
            // between the answer field and the keyboard.
            .popover(isPresented: $showing, arrowEdge: .top) {
                WordInfoView(token: token)
                    .presentationCompactAdaptation(.popover)   // a popover on iPhone too, not a sheet
            }
            .accessibilityAddTraits(lookable ? .isButton : [])
            .accessibilityHint(lookable ? "Shows the meaning and grammar of this word" : "")
    }
}

/// What a word is: meaning, article and gender, plural, verb forms, the form it
/// takes here (case, number, tense) and, for a separable verb, its base verb.
struct WordInfoView: View {
    @Environment(\.modelContext) private var context
    let token: String
    @State private var x: WordExplanation?
    @State private var added = false

    var entry: DictionaryEntry? { x?.lookup.entries.first }

    var body: some View {
        // As tall as the content, and scrolling only when there isn't room
        // (the keyboard is up on the iPhone).
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            ScrollView { content }
        }
        .frame(width: 300)
        .task { x = await ExplanationCache.shared.explain(token) }
    }

    @ViewBuilder var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let x {
                if x.lookup.source == .unreachable {
                    Label("Couldn't reach Wiktionary", systemImage: "wifi.slash").font(.callout)
                } else if let e = entry {
                    HStack(alignment: .firstTextBaseline) {
                        Text(display(e)).font(.title3.bold())
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
                    Button(added ? "Added to your words" : "Add to Wort", systemImage: added ? "checkmark" : "plus") { add(e) }
                        .disabled(added)
                        .font(.callout)
                } else if let form = x.lookup.formDescription {
                    Text("**\(token)**: \(form)").font(.callout)
                } else {
                    Text("No entry for „\(ParsedInput(token).word)“").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .padding(14)
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
                  pluralOnly: e.pluralOnly, english: Enricher.shortGloss(e.glosses), example: e.example,
                  source: "grammar", genderSource: "Wiktionary", forms: e.principalParts, context: context)
        try? context.save()
        added = true
    }
}
