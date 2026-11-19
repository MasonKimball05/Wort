import SwiftData
import SwiftUI
import WortCore

/// Progress per item for a topic, replayed from the attempt log.
@MainActor
enum GrammarProgress {
    static func states(topic: GrammarTopic, context: ModelContext) -> [String: LeitnerState] {
        let raw = topic.rawValue
        let attempts = (try? context.fetch(FetchDescriptor<GrammarAttempt>(predicate: #Predicate { $0.topicRaw == raw }))) ?? []
        return Dictionary(grouping: attempts, by: \.itemID).compactMapValues { list in
            LeitnerState.replay(list.map { GrammarAttemptEvent(correct: $0.correct, at: $0.at) })
        }
    }
}

struct GrammarView: View {
    @Environment(\.modelContext) private var context
    @Query private var attempts: [GrammarAttempt]

    var body: some View {
        NavigationStack {
            List(GrammarTopic.allCases) { topic in
                NavigationLink(value: topic) { TopicRow(topic: topic, attempts: attempts.filter { $0.topicRaw == topic.rawValue }) }
            }
            .navigationTitle("Grammar")
            .navigationDestination(for: GrammarTopic.self) { GrammarSessionView(topic: $0) }
        }
    }
}

struct TopicRow: View {
    let topic: GrammarTopic
    let attempts: [GrammarAttempt]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(topic.title).font(.headline)
            Text(topic.summary).font(.caption).foregroundStyle(.secondary)
            if !attempts.isEmpty {
                let right = attempts.filter(\.correct).count
                let due = Dictionary(grouping: attempts, by: \.itemID).compactMapValues {
                    LeitnerState.replay($0.map { GrammarAttemptEvent(correct: $0.correct, at: $0.at) })
                }.values.filter { $0.due <= .now }.count
                Text("\(right * 100 / attempts.count)% right · \(due) to repeat")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct GrammarSessionView: View {
    @Environment(\.modelContext) private var context
    let topic: GrammarTopic

    @State private var items: [GrammarItem] = []
    @State private var index = 0
    @State private var response = ""
    @State private var answered: Bool?          // nil until checked
    @State private var picked: String?
    @State private var right = 0
    @State private var total = 0
    @State private var retried = Set<String>()
    /// When the answer was checked: the Return that checks an answer must not
    /// also press Next (they share the key), or the feedback is skipped.
    @State private var checkedAt = Date.distantPast
    @FocusState private var focused: Bool

    var item: GrammarItem? { items.indices.contains(index) ? items[index] : nil }

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("\(index + 1) of \(items.count)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(right)/\(total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        // Tap (or hover, on the Mac) any word for its meaning and grammar.
                        TappableSentence(text: item.prompt)
                        answerArea(item)
                        if let ok = answered { feedback(item, ok) }
                    }
                    .padding(20)
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            } else if total > 0 {
                ContentUnavailableView {
                    Label("\(right) of \(total) right", systemImage: right == total ? "star.fill" : "checkmark.circle")
                } description: {
                    Text("Missed items come back in your next session. Tap any word in an exercise to look it up.")
                } actions: {
                    Button("Another round") { start() }.buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(topic.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { if items.isEmpty { start() } }
    }

    @ViewBuilder func answerArea(_ item: GrammarItem) -> some View {
        switch item.kind {
        case .gap:
            HStack {
                TextField("Answer", text: $response)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .focused($focused)
                    .disabled(answered != nil)
                    .onSubmit { answered == nil ? check(item, response) : next() }
                if answered == nil {
                    Button("Check") { check(item, response) }
                        .buttonStyle(.borderedProminent)
                        .disabled(response.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        case .choice(let options):
            VStack(spacing: 10) {
                ForEach(shuffled(options, for: item), id: \.self) { option in
                    Button {
                        // Not .disabled after answering: that greys out the green/red.
                        guard answered == nil else { return }
                        picked = option; check(item, option)
                    } label: {
                        Text(option).frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(tint(option, item))
                }
            }
        }
    }

    @ViewBuilder func feedback(_ item: GrammarItem, _ ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(ok ? "Richtig" : "Not quite", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline).foregroundStyle(ok ? .green : .red)
            if case .gap = item.kind {
                TappableSentence(text: item.solved, font: .body.italic())
                if item.answers.count > 1, !item.id.hasPrefix("adj:") {
                    Text("Also accepted: \(item.answers.dropFirst().joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                TappableSentence(text: item.answers[0], font: .body.italic())
            }
            Text(item.explanation).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Next") { next() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(14)
        .background((ok ? Color.green : Color.red).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    func start() {
        items = GrammarSession.build(topic: topic, progress: GrammarProgress.states(topic: topic, context: context))
        index = 0; right = 0; total = 0; retried = []
        reset()
    }

    func check(_ item: GrammarItem, _ answer: String) {
        let ok = item.isCorrect(answer)
        answered = ok
        checkedAt = .now
        total += 1
        if ok { right += 1 }
        context.insert(GrammarAttempt(itemID: item.id, topic: topic, correct: ok))
        try? context.save()
        // A miss comes back once at the end of this session.
        if !ok, !retried.contains(item.id) { retried.insert(item.id); items.append(item) }
    }

    func next() {
        guard Date.now.timeIntervalSince(checkedAt) > 0.4 else { return }
        index += 1
        reset()
    }

    func reset() {
        response = ""; answered = nil; picked = nil
        focused = true
    }

    /// Options in a stable shuffled order per item, so they don't jump around on redraw.
    func shuffled(_ options: [String], for item: GrammarItem) -> [String] {
        var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: item.id.hashValue))
        return options.shuffled(using: &rng)
    }

    func tint(_ option: String, _ item: GrammarItem) -> Color? {
        guard answered != nil else { return nil }
        if option == item.answers[0] { return .green }
        if option == picked { return .red }
        return nil
    }
}
