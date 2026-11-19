import SwiftData
import SwiftUI
import WortCore

struct ReviewView: View {
    @Environment(\.modelContext) private var context
    @State private var queue: [Card] = []
    @State private var revealed = false
    @State private var picked: Gender?
    @State private var doneToday = 0

    var body: some View {
        NavigationStack {
            Group {
                if let card = queue.first, let word = card.word {
                    CardView(card: card, word: word, revealed: $revealed, picked: $picked,
                             onAnswer: { answer(card, $0) })
                        .id(card.persistentModelID)
                } else {
                    ContentUnavailableView {
                        Label(doneToday > 0 ? "Fertig für heute!" : "Nothing to review",
                              systemImage: doneToday > 0 ? "checkmark.seal" : "rectangle.stack")
                    } description: {
                        Text(doneToday > 0 ? "\(doneToday) cards reviewed. Come back tomorrow."
                             : "Add words, or a starter deck from Settings.")
                    }
                }
            }
            .navigationTitle("Review")
            .toolbar {
                if !queue.isEmpty {
                    ToolbarItem { Text("\(queue.count) left").monospacedDigit().foregroundStyle(.secondary) }
                }
            }
        }
        .onAppear(perform: reload)
    }

    func reload() {
        queue = Queue.next(context: context)
        revealed = false
        picked = nil
    }

    func answer(_ card: Card, _ rating: Rating) {
        Queue.answer(card, rating, context: context)
        doneToday += 1
        queue.removeFirst()
        // A card that's due again within this session goes to the back.
        if card.due.timeIntervalSinceNow < 20 * 60 { queue.append(card) }
        revealed = false
        picked = nil
    }
}

struct CardView: View {
    let card: Card
    let word: Word
    @Binding var revealed: Bool
    @Binding var picked: Gender?
    let onAnswer: (Rating) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(card.kind.title.uppercased())
                .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            front
            if revealed { back.transition(.opacity) }
            Spacer(minLength: 0)
            controls
        }
        .padding(24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.15), value: revealed)
    }

    @ViewBuilder var front: some View {
        switch card.kind {
        case .meaning:
            HStack { Text(word.display).font(.largeTitle.bold()).multilineTextAlignment(.center); speakButton }
        case .recall:
            Text(word.english).font(.title.bold()).multilineTextAlignment(.center)
        case .gender:
            VStack(spacing: 16) {
                Text("___ \(word.lemma)").font(.largeTitle.bold())
                // The meaning tells same-spelling nouns apart: der Verdienst (earnings)
                // vs das Verdienst (merit), der/das/die Band.
                Text(word.english).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    ForEach(Gender.allCases, id: \.self) { g in
                        Button(g.article) { pick(g) }
                            .buttonStyle(.bordered).controlSize(.large)
                            .tint(tint(for: g))
                            .disabled(revealed)
                    }
                }
            }
        case .plural:
            VStack(spacing: 8) {
                Text(word.display).font(.title.bold())
                Text("die … ?").font(.title2).foregroundStyle(.secondary)
            }
        case .government:
            VStack(spacing: 8) {
                Text("\(word.lemma) ___").font(.title.bold()).multilineTextAlignment(.center)
                Text("Which preposition, and which case?").font(.callout).foregroundStyle(.secondary)
            }
        case .forms:
            VStack(spacing: 8) {
                Text(word.lemma).font(.largeTitle.bold())
                Text("Präteritum, Perfekt?").font(.title3).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder var back: some View {
        VStack(spacing: 10) {
            switch card.kind {
            case .meaning: Text(word.english).font(.title2).multilineTextAlignment(.center)
            case .recall, .gender: HStack { Text(word.display).font(.title.bold()); speakButton }
            case .plural: HStack { Text("die \(word.plural ?? "–")").font(.title.bold()); speakButton }
            case .government: Text("\(word.lemma) \(word.government ?? "")").font(.title.bold())
            case .forms: HStack { Text(word.forms ?? "–").font(.title.bold()); speakButton }
            }
            // The preposition belongs to the word, so show it whenever the word is shown.
            if let gov = word.government, card.kind == .meaning || card.kind == .recall {
                Text("\(word.lemma) \(gov)").font(.headline).foregroundStyle(.secondary)
            }
            if let ex = word.exampleGerman {
                Text(ex).font(.callout).italic().multilineTextAlignment(.center).padding(.top, 8)
                if let en = word.exampleEnglish { Text(en).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder var controls: some View {
        if !revealed {
            if card.kind != .gender {
                Button("Show answer") { revealed = true }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [])
            }
        } else if card.kind == .gender {
            // Graded by the pick itself.
            Button("Next") { onAnswer(picked == word.gender ? .good : .again) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.space, modifiers: [])
        } else {
            let preview = Queue.preview(card)
            HStack(spacing: 8) {
                ForEach(Rating.allCases, id: \.self) { r in
                    Button { onAnswer(r) } label: {
                        VStack(spacing: 2) {
                            Text(r.label).font(.subheadline.weight(.semibold))
                            Text(preview[r] ?? "").font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(r == .again ? .red : r == .good ? .green : .accentColor)
                    .keyboardShortcut(KeyEquivalent(Character("\(r.rawValue)")), modifiers: [])
                }
            }
        }
    }

    var spoken: String {
        switch card.kind {
        case .plural: "die \(word.plural ?? "")"
        case .forms: "\(word.lemma), \(word.forms ?? "")"
        default: word.display
        }
    }

    var speakButton: some View {
        Button { Speaker.shared.say(spoken) } label: { Image(systemName: "speaker.wave.2") }
            .buttonStyle(.borderless)
            .accessibilityLabel("Say it")
    }

    func pick(_ g: Gender) {
        picked = g
        revealed = true
        Speaker.shared.say(word.display)
    }

    func tint(for g: Gender) -> Color? {
        guard revealed else { return nil }
        if g == word.gender { return .green }
        if g == picked { return .red }
        return nil
    }
}
