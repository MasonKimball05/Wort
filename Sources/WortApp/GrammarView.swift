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
            LeitnerState.replay(list.map(\.event))
        }
    }
}

struct GrammarView: View {
    @Query private var attempts: [GrammarAttempt]

    var today: [GrammarAttempt] {
        let start = Calendar.current.startOfDay(for: .now)
        return attempts.filter { $0.at >= start }
    }

    /// Exercises you keep missing (counting doesn't need the items themselves).
    var troubleCount: Int {
        Trouble.ranked(Dictionary(grouping: attempts, by: \.itemID)
            .mapValues { $0.map { Trouble.Result(correct: $0.correct, at: $0.at, hinted: $0.hinted) } }).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TodayHeader(answered: today.count, right: today.filter(\.correct).count,
                                due: GrammarTopic.allCases.reduce(0) { $0 + TopicStats(topic: $1, attempts: attempts).due })
                    if troubleCount > 0 {
                        NavigationLink { TroubleSpotsView() } label: {
                            TroubleCard(count: troubleCount)
                        }
                        .buttonStyle(.plain)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach(GrammarTopic.allCases) { topic in
                            NavigationLink(value: topic) {
                                TopicCard(topic: topic, stats: TopicStats(topic: topic, attempts: attempts))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Tap any word in an exercise to see its meaning, gender, form and case.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(Color.groupedBackground)
            .navigationTitle("Grammar")
            .navigationDestination(for: GrammarTopic.self) { GrammarSessionView(topic: $0) }
        }
    }
}

/// Per-topic numbers for the cards, replayed from the attempt log.
struct TopicStats {
    var answered = 0
    var right = 0
    var seen = 0
    var mastered = 0      // box 3 or higher: spaced out a week or more
    var due = 0
    var total: Int?       // nil for the generated topic, which has no fixed size

    init(topic: GrammarTopic, attempts: [GrammarAttempt]) {
        let mine = attempts.filter { $0.topicRaw == topic.rawValue }
        answered = mine.count
        right = mine.filter(\.correct).count
        let states = Dictionary(grouping: mine, by: \.itemID).compactMapValues {
            LeitnerState.replay($0.map(\.event))
        }
        seen = states.count
        mastered = states.values.filter { $0.box >= 3 }.count
        due = states.values.filter { $0.due <= .now }.count
        total = topic == .adjectiveEndings ? nil : GrammarBank.items(topic: topic).count
    }

    var accuracy: Int? { answered == 0 ? nil : right * 100 / answered }

    /// Share of the topic mastered; for the endless topic, out of 50 phrases.
    var progress: Double {
        let denominator = Double(total ?? 50)
        return min(1, Double(mastered) / max(1, denominator))
    }
}

extension GrammarTopic {
    var symbol: String {
        switch self {
        case .adjectiveEndings: "textformat.abc"
        case .konjunktiv: "quote.bubble"
        case .passive: "arrow.triangle.2.circlepath"
        case .cases: "point.topleft.down.to.point.bottomright.curvepath"
        case .prepositions: "link"
        }
    }

    var tint: Color {
        switch self {
        case .adjectiveEndings: .orange
        case .konjunktiv: .purple
        case .passive: .teal
        case .cases: .blue
        case .prepositions: .indigo
        }
    }

    var sample: String {
        switch self {
        case .adjectiveEndings: "mit kalter Milch"
        case .konjunktiv: "Er sagte, er sei krank."
        case .passive: "Das wurde gestern beschlossen."
        case .cases: "trotz des Regens"
        case .prepositions: "Es kommt darauf an."
        }
    }
}

struct TodayHeader: View {
    let answered: Int
    let right: Int
    let due: Int

    var body: some View {
        HStack(spacing: 12) {
            StatTile(value: "\(answered)", label: "answered today", symbol: "checkmark.circle", tint: .green)
            StatTile(value: answered == 0 ? "–" : "\(right * 100 / answered)%", label: "right today", symbol: "target", tint: .blue)
            StatTile(value: "\(due)", label: "to repeat", symbol: "arrow.counterclockwise", tint: .orange)
        }
    }
}

struct TroubleCard: View {
    let count: Int
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Trouble spots").font(.headline)
                Text("\(count) \(count == 1 ? "exercise" : "exercises") you keep missing or need hints for")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.footnote.weight(.semibold)).foregroundStyle(tint)
            Text(value).font(.title2.weight(.bold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct TopicCard: View {
    let topic: GrammarTopic
    let stats: TopicStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: topic.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(topic.tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title).font(.headline)
                    Text(topic.summary).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }

            Text(topic.sample).font(.callout.italic()).foregroundStyle(topic.tint)

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: stats.progress).tint(topic.tint)
                HStack(spacing: 8) {
                    if let total = stats.total {
                        Text("\(stats.mastered) of \(total) mastered")
                    } else {
                        Text(stats.seen == 0 ? "Endless: generated each time" : "\(stats.mastered) phrases mastered")
                    }
                    Spacer()
                    if let a = stats.accuracy { Chip(text: "\(a)% right", tint: .green) }
                    if stats.due > 0 { Chip(text: "\(stats.due) due", tint: .orange) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.quaternary, lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct Chip: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

extension Color {
    /// The grouped-list background and the card on it, matching each platform.
    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

struct GrammarSessionView: View {
    @Environment(\.modelContext) private var context
    let topic: GrammarTopic
    /// A fixed set to practice (trouble spots, from any topic) instead of the
    /// topic's own session; called again for "Another round".
    var practice: ((ModelContext) -> [GrammarItem])? = nil

    @State private var items: [GrammarItem] = []
    @State private var index = 0
    @State private var response = ""
    @State private var answered: Bool?          // nil until checked
    @State private var picked: String?
    @State private var right = 0
    @State private var total = 0
    @State private var retried = Set<String>()
    /// Missed items, asked again once the new ones are done.
    @State private var retries: [GrammarItem] = []
    /// New items still to come; picked one at a time at the current level.
    @State private var freshLeft = 0
    @State private var excluded = Set<String>()
    @State private var tuner = Tuner(level: 2)
    @State private var levelNote: String?
    @State private var hinted = false
    /// Choice options struck out (by a hint, or one up front at level 1).
    @State private var removed = Set<String>()
    @State private var rng = SeededRandom(seed: UInt64.random(in: 1...UInt64.max))
    /// When the answer was checked: the Return that checks an answer must not
    /// also press Next (they share the key), or the feedback is skipped.
    @State private var checkedAt = Date.distantPast
    @FocusState private var focused: Bool

    var item: GrammarItem? { items.indices.contains(index) ? items[index] : nil }

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: Double(index), total: Double(max(roundLength, 1)))
                                .tint(topic.tint)
                            HStack {
                                Text("\(index + 1) of \(roundLength)")
                                LevelDots(level: tuner.level)
                                if let levelNote {
                                    Text(levelNote).foregroundStyle(topic.tint).transition(.opacity)
                                }
                                Spacer()
                                Label("\(right)/\(total)", systemImage: "checkmark")
                                    .labelStyle(.titleAndIcon)
                            }
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 18) {
                            Label(kindLabel(item), systemImage: item.topic.symbol)
                                .font(.caption.weight(.semibold)).foregroundStyle(item.topic.tint)
                            // Tap (or hover, on the Mac) any word for its meaning and grammar.
                            TappableSentence(text: item.prompt)
                            answerArea(item)
                            hintArea(item)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        if let ok = answered { feedback(item, ok) }
                    }
                    .padding(20)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .background(Color.groupedBackground)
            } else if total > 0 {
                ContentUnavailableView {
                    Label("\(right) of \(total) right", systemImage: right == total ? "star.fill" : "checkmark.circle")
                        .foregroundStyle(topic.tint)
                } description: {
                    Text("Missed items come back in your next session. Tap any word in an exercise to look it up.")
                } actions: {
                    Button("Another round") { start() }.buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(practice == nil ? topic.title : "Trouble spots")
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
                ForEach(shuffled(options, for: item).filter { !removed.contains($0) }, id: \.self) { option in
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .leading) {
            // A colored edge says right or wrong at a glance.
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, style: .continuous)
                .fill(ok ? Color.green : Color.red).frame(width: 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    var roundLength: Int { items.count + freshLeft + retries.count }

    /// A hint: the first letter (or, for endings, the rule) for a gap; one
    /// wrong option struck out for a choice. Only before answering.
    @ViewBuilder func hintArea(_ item: GrammarItem) -> some View {
        if answered == nil {
            if hinted, let text = item.hint {
                Label(text, systemImage: "lightbulb.fill").font(.callout).foregroundStyle(.orange)
            } else if !hinted, item.hint != nil || item.optionToRemove(keeping: removed) != nil {
                Button("Hint", systemImage: "lightbulb") { useHint(item) }
                    .buttonStyle(.bordered).tint(.orange).controlSize(.small)
            }
        }
    }

    func useHint(_ item: GrammarItem) {
        hinted = true
        if item.hint == nil, let strike = item.optionToRemove(keeping: removed) { removed.insert(strike) }
    }

    func kindLabel(_ item: GrammarItem) -> String {
        if case .choice = item.kind { return "Choose the right sentence" }
        return item.topic == .adjectiveEndings ? "Fill in the ending" : "Fill the gap"
    }

    /// Due items first (never skipped, whatever the level), then new ones picked
    /// one at a time to match the level, then this round's misses again.
    func start() {
        index = 0; right = 0; total = 0; retried = []; retries = []; levelNote = nil
        if let practice {
            items = practice(context)
            freshLeft = 0
            tuner = Tuner(level: 2)
        } else {
            let progress = GrammarProgress.states(topic: topic, context: context)
            items = GrammarSession.due(topic: topic, progress: progress)
            freshLeft = max(0, 10 - items.count)
            excluded = Set(progress.keys)
            tuner = Tuner(level: Tuner.startLevel(recentResults()))
            if items.isEmpty { addNext() }
        }
        reset()
    }

    /// This topic's last answers, oldest first, for the starting level.
    func recentResults() -> [(correct: Bool, hinted: Bool)] {
        let raw = topic.rawValue
        var d = FetchDescriptor<GrammarAttempt>(predicate: #Predicate { $0.topicRaw == raw },
                                                sortBy: [SortDescriptor(\.at, order: .reverse)])
        d.fetchLimit = 12
        return ((try? context.fetch(d)) ?? []).reversed().map { (correct: $0.correct, hinted: $0.hinted) }
    }

    /// Puts the next item on the end: a new one at the current level, or once
    /// those are done, a miss to try again.
    func addNext() {
        if freshLeft > 0 {
            excluded.formUnion(items.map(\.id))
            if let item = GrammarSession.fresh(topic: topic, level: tuner.level, excluding: excluded, using: &rng) {
                items.append(item)
                freshLeft -= 1
                return
            }
            freshLeft = 0      // nothing new left in this topic
        }
        if !retries.isEmpty { items.append(retries.removeFirst()) }
    }

    func check(_ item: GrammarItem, _ answer: String) {
        let ok = item.isCorrect(answer)
        answered = ok
        checkedAt = .now
        total += 1
        if ok { right += 1 }
        context.insert(GrammarAttempt(itemID: item.id, topic: item.topic, correct: ok, hinted: hinted))
        try? context.save()
        // A miss comes back once at the end of this session.
        if !ok, !retried.contains(item.id) { retried.insert(item.id); retries.append(item) }
        levelNote = nil
        switch tuner.record(id: item.id, correct: ok, hinted: hinted) {
        case .easier: levelNote = "Easing off a little"
        case .harder: levelNote = "Stepping it up"
        case nil: break
        }
    }

    func next() {
        guard Date.now.timeIntervalSince(checkedAt) > 0.4 else { return }
        index += 1
        if index >= items.count { addNext() }
        reset()
    }

    func reset() {
        response = ""; answered = nil; picked = nil; hinted = false
        removed = []
        // Easiest level: one fewer option to choose from (not counted as a hint).
        if tuner.level == 1, let item, let strike = item.optionToRemove() { removed = [strike] }
        refocus()
    }

    /// The field is still disabled in the same update that clears the answer, so
    /// focusing it straight away is ignored; a moment later it takes.
    func refocus() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
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

/// The current difficulty, as three dots.
struct LevelDots: View {
    let level: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                Circle().fill(i <= level ? Color.primary.opacity(0.6) : Color.secondary.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel("Difficulty \(level) of 3")
        .help("Difficulty adapts as you answer")
    }
}
