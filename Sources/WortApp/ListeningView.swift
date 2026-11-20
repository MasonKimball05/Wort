import SwiftData
import SwiftUI
import WortCore

/// Hear it, type it. Words come with their article ("die Hoffnung"), so it
/// trains the gender too; sentences are your words' example sentences. The voice
/// is the device's own German text-to-speech, so it works offline. Practice
/// only: it doesn't change when cards are due.
struct ListeningView: View {
    enum Mode: String, CaseIterable { case words = "Words", sentences = "Sentences" }

    @Query private var words: [Word]
    @State private var mode = Mode.words
    @State private var round: [(text: String, english: String)] = []
    @State private var index = 0
    @State private var typed = ""
    @State private var result: [Dictation.Word]?
    @State private var right = 0
    @FocusState private var focused: Bool

    var current: (text: String, english: String)? { round.indices.contains(index) ? round[index] : nil }

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
                    Text("\(index + 1) of \(round.count) · \(right) right")
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
                            Button("Check") { check(item) }
                                .buttonStyle(.borderedProminent)
                                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
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

    @ViewBuilder func feedback(_ item: (text: String, english: String), _ words: [Dictation.Word]) -> some View {
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

    /// Ten at random. Words you've already met first (seen in Review), then any.
    func start() {
        let usable = words.filter { !$0.needsLookup }
        let met = usable.filter { ($0.cards ?? []).contains { !$0.isNew } }
        let pool = met.count >= 10 ? met : usable
        switch mode {
        case .words:
            round = pool.shuffled().prefix(10).map { (text: $0.display, english: $0.english) }
        case .sentences:
            round = pool.compactMap { w -> (text: String, english: String)? in
                guard let ex = w.exampleGerman, ex.split(separator: " ").count <= 16 else { return nil }
                return (text: ex, english: w.exampleEnglish ?? "")
            }
            .shuffled().prefix(10).map { $0 }
        }
        index = 0; right = 0
        reset()
    }

    func check(_ item: (text: String, english: String)) {
        result = Dictation.compare(expected: item.text, typed: typed)
        if Dictation.isCorrect(expected: item.text, typed: typed) { right += 1 }
    }

    func next() {
        index += 1
        reset()
    }

    func reset() {
        typed = ""; result = nil
        focused = true
        // Play the new one straight away.
        if let item = current {
            Task { try? await Task.sleep(for: .milliseconds(300)); Speaker.shared.say(item.text) }
        }
    }
}
