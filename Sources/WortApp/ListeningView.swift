import SwiftData
import SwiftUI
import WortCore

/// Hear it, type it. Words come with their article ("die Hoffnung"), so it
/// trains the gender too; sentences are your words' example sentences. The voice
/// is the device's own German text-to-speech, so it works offline. Practice
/// only: it doesn't change when cards are due.
struct ListeningView: View {
    enum Mode: String, CaseIterable { case words = "Words", sentences = "Sentences" }

    struct Item: Equatable {
        var text: String
        var english: String
        var key: String
    }

    @Environment(\.modelContext) private var context
    @Query private var words: [Word]
    @State private var mode = Mode.words
    @State private var round: [Item] = []
    /// What the round can still draw from; picked one at a time at the level.
    @State private var pool: [Item] = []
    @State private var index = 0
    @State private var typed = ""
    @State private var result: [Dictation.Word]?
    @State private var right = 0
    @State private var hinted = false
    @State private var tuner = Tuner(level: 2)
    @State private var levelNote: String?
    @FocusState private var focused: Bool

    static let roundSize = 10

    var current: Item? { round.indices.contains(index) ? round[index] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if !Speaker.hasGermanVoice {
                    Label("No German voice installed. Add one in Settings › Accessibility › Spoken Content › Voices.",
                          systemImage: "speaker.slash").font(.callout).foregroundStyle(.orange)
                }

                if let item = current {
                    HStack(spacing: 8) {
                        Text("\(index + 1) of \(roundLength) · \(right) right")
                        LevelDots(level: tuner.level)
                        if let levelNote { Text(levelNote).foregroundStyle(.tint) }
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            Button { Speaker.shared.say(item.text) } label: {
                                Label("Play", systemImage: "play.circle.fill").font(.title2)
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut("p", modifiers: .command)
                            Button { Speaker.shared.say(item.text, slow: true) } label: {
                                Label("Slower", systemImage: "tortoise.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                        TextField(mode == .words ? "Type what you hear, with the article" : "Type the sentence",
                                  text: $typed, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .focused($focused)
                            .disabled(result != nil)
                            .onSubmit { result == nil ? check(item) : next() }
                        if result == nil {
                            if hinted {
                                Label(Hints.letters(item.text), systemImage: "lightbulb.fill")
                                    .font(.callout.monospaced()).foregroundStyle(.orange)
                            }
                            HStack {
                                if !hinted {
                                    Button("Hint", systemImage: "lightbulb") { hinted = true }
                                        .buttonStyle(.bordered).tint(.orange)
                                }
                                Button("Check") { check(item) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if let result { feedback(item, result) }
                } else if !round.isEmpty {
                    ContentUnavailableView {
                        Label("\(right) of \(round.count) right", systemImage: "ear")
                    } actions: {
                        Button("Another round") { start() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView("Nothing to listen to yet", systemImage: "ear",
                                           description: Text(mode == .words
                                                ? "Add some words, or a starter deck from Settings."
                                                : "None of your words has an example sentence yet."))
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
        .navigationTitle("Listening")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { if round.isEmpty { start() } }
        .onChange(of: mode) { start() }
    }

    var roundLength: Int { min(Self.roundSize, round.count + pool.count) }

    @ViewBuilder func feedback(_ item: Item, _ words: [Dictation.Word]) -> some View {
        let ok = Dictation.isCorrect(expected: item.text, typed: typed)
        VStack(alignment: .leading, spacing: 10) {
            Label(ok ? "Richtig" : "Not quite", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline).foregroundStyle(ok ? .green : .red)
            // The words you missed or misspelled in red.
            WrapLayout(spacing: 5) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                    Text(w.text).font(.title3.weight(.medium))
                        .foregroundStyle(w.ok ? Color.primary : Color.red)
                        .underline(!w.ok, color: .red)
                }
            }
            if !item.english.isEmpty {
                Text(item.english).font(.callout).foregroundStyle(.secondary)
            }
            Button("Next") { next() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Words you've already met first (seen in Review), then any. The round
    /// starts at the level your last listening answers suggest and picks each
    /// next item to match the level as it changes.
    func start() {
        let usable = words.filter { !$0.needsLookup }
        let met = usable.filter { ($0.cards ?? []).contains { !$0.isNew } }
        let source = met.count >= Self.roundSize ? met : usable
        switch mode {
        case .words:
            pool = source.map { Item(text: $0.display, english: $0.english, key: $0.key) }
        case .sentences:
            pool = source.compactMap { w in
                guard let ex = w.exampleGerman, ex.split(separator: " ").count <= 16 else { return nil }
                return Item(text: ex, english: w.exampleEnglish ?? "", key: w.key)
            }
        }
        pool.shuffle()
        round = []; index = 0; right = 0; levelNote = nil
        tuner = Tuner(level: Tuner.startLevel(recentResults()))
        addNext()
        reset()
    }

    func recentResults() -> [(correct: Bool, hinted: Bool)] {
        let m = mode == .words ? "word" : "sentence"
        var d = FetchDescriptor<ListeningAttempt>(predicate: #Predicate { $0.mode == m },
                                                  sortBy: [SortDescriptor(\.at, order: .reverse)])
        d.fetchLimit = 12
        return ((try? context.fetch(d)) ?? []).reversed().map { (correct: $0.correct, hinted: $0.hinted) }
    }

    /// The next item: the closest to the current level that's left.
    func addNext() {
        guard round.count < Self.roundSize, !pool.isEmpty else { return }
        let sentence = mode == .sentences
        let best = pool.indices.min { a, b in
            abs(Dictation.level(of: pool[a].text, sentence: sentence) - tuner.level)
                < abs(Dictation.level(of: pool[b].text, sentence: sentence) - tuner.level)
        }!
        round.append(pool.remove(at: best))
    }

    func check(_ item: Item) {
        result = Dictation.compare(expected: item.text, typed: typed)
        let ok = Dictation.isCorrect(expected: item.text, typed: typed)
        if ok { right += 1 }
        context.insert(ListeningAttempt(wordKey: item.key, mode: mode == .words ? "word" : "sentence",
                                        correct: ok, hinted: hinted))
        try? context.save()
        levelNote = nil
        switch tuner.record(id: item.key, correct: ok, hinted: hinted) {
        case .easier: levelNote = "Easing off a little"
        case .harder: levelNote = "Stepping it up"
        case nil: break
        }
    }

    func next() {
        index += 1
        if index >= round.count { addNext() }
        reset()
    }

    func reset() {
        typed = ""; result = nil; hinted = false
        // A moment later: the field is still disabled in this same update.
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(60)); focused = true }
        // Play the new one straight away.
        if let item = current {
            Task { try? await Task.sleep(for: .milliseconds(300)); Speaker.shared.say(item.text) }
        }
    }
}
