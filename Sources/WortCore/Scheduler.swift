import Foundation

/// The drills a word gets. Each one is scheduled on its own, so missing
/// der/die/das doesn't reset how well you know what the word means.
public enum CardKind: String, Codable, CaseIterable, Sendable {
    case meaning   // German → English
    case recall    // English → German
    case gender    // der, die or das? (nouns with a known gender)
    case plural    // what's the plural? (nouns with a plural)
    case government // which preposition and case? "verzichten ___" → auf + Akk.
    case forms     // principal parts of a strong verb: verzeihen → verzieh, hat verziehen

    public var title: String {
        switch self {
        case .meaning: "Meaning"
        case .recall: "Recall"
        case .gender: "Article"
        case .plural: "Plural"
        case .government: "Preposition & case"
        case .forms: "Verb forms"
        }
    }

    /// Which drills make sense for a word.
    public static func kinds(partOfSpeech: PartOfSpeech, gender: Gender?, plural: String?,
                             government: String? = nil, forms: String? = nil) -> [CardKind] {
        var kinds: [CardKind] = [.meaning, .recall]
        if partOfSpeech == .noun, gender != nil { kinds.append(.gender) }
        if partOfSpeech == .noun, let p = plural, !p.isEmpty { kinds.append(.plural) }
        if let g = government, !g.isEmpty { kinds.append(.government) }
        if partOfSpeech == .verb, let f = forms, !f.isEmpty { kinds.append(.forms) }
        return kinds
    }
}

public enum Rating: Int, Codable, CaseIterable, Sendable {
    case again = 1, hard, good, easy
    public var label: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

/// One answer. Reviews are only ever appended (never edited), and a card's state is
/// replayed from them, so two devices reviewing offline merge without losing either.
public struct ReviewEvent: Equatable, Codable, Sendable {
    public var rating: Rating
    public var at: Date
    public init(rating: Rating, at: Date) {
        self.rating = rating
        self.at = at
    }
}

public struct CardState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case new
        case learning(step: Int)
        case review
        case relearning(step: Int)
    }
    public var phase: Phase = .new
    public var ease: Double = 2.5
    /// Days, for cards in review.
    public var interval: Double = 0
    public var due: Date
    public var reviews = 0
    public var lapses = 0

    public init(due: Date) { self.due = due }

    public var isNew: Bool { phase == .new }
}

/// SM-2 with learning steps, the scheme Anki used for years. Deterministic: no
/// random fuzz, and `now` is always passed in, so the tests can pin the clock.
public struct Scheduler: Sendable {
    public var learningSteps: [TimeInterval] = [60, 10 * 60]          // 1 min, 10 min
    public var relearningSteps: [TimeInterval] = [10 * 60]
    public var graduatingInterval: Double = 1                          // days
    public var easyInterval: Double = 4
    public var minimumEase = 1.3
    public var maximumInterval: Double = 365 * 2

    public init() {}

    static let day: TimeInterval = 86_400

    public func next(_ s: CardState, _ rating: Rating, now: Date) -> CardState {
        var n = s
        n.reviews += 1
        switch s.phase {
        case .new, .learning:
            let step: Int
            if case .learning(let k) = s.phase { step = k } else { step = 0 }
            switch rating {
            case .again:
                n.phase = .learning(step: 0)
                n.due = now + learningSteps[0]
            case .hard:
                n.phase = .learning(step: step)
                // Halfway to the next step, or the current step again on the last.
                let cur = learningSteps[min(step, learningSteps.count - 1)]
                let nxt = step + 1 < learningSteps.count ? learningSteps[step + 1] : cur
                n.due = now + (cur + nxt) / 2
            case .good:
                if step + 1 < learningSteps.count {
                    n.phase = .learning(step: step + 1)
                    n.due = now + learningSteps[step + 1]
                } else {
                    graduate(&n, days: graduatingInterval, now: now)
                }
            case .easy:
                graduate(&n, days: easyInterval, now: now)
            }
        case .relearning(let step):
            switch rating {
            case .again:
                n.phase = .relearning(step: 0)
                n.due = now + relearningSteps[0]
            case .hard:
                n.due = now + relearningSteps[min(step, relearningSteps.count - 1)]
            case .good, .easy:
                if step + 1 < relearningSteps.count && rating == .good {
                    n.phase = .relearning(step: step + 1)
                    n.due = now + relearningSteps[step + 1]
                } else {
                    // Back to review at the reduced interval set when it lapsed.
                    graduate(&n, days: max(1, s.interval), now: now)
                }
            }
        case .review:
            let overdueDays = max(0, now.timeIntervalSince(s.due) / Self.day)
            switch rating {
            case .again:
                n.lapses += 1
                n.ease = max(minimumEase, s.ease - 0.2)
                n.interval = max(1, s.interval * 0.5)
                n.phase = .relearning(step: 0)
                n.due = now + relearningSteps[0]
            case .hard:
                n.ease = max(minimumEase, s.ease - 0.15)
                schedule(&n, days: max(s.interval + 1, s.interval * 1.2), now: now)
            case .good:
                schedule(&n, days: max(s.interval + 1, (s.interval + overdueDays / 2) * s.ease), now: now)
            case .easy:
                n.ease = s.ease + 0.15
                schedule(&n, days: max(s.interval + 1, (s.interval + overdueDays) * s.ease * 1.3), now: now)
            }
        }
        return n
    }

    /// The state a card is in after these reviews, oldest first.
    public func replay(_ events: [ReviewEvent], createdAt: Date) -> CardState {
        events.sorted { $0.at < $1.at }
            .reduce(CardState(due: createdAt)) { next($0, $1.rating, now: $1.at) }
    }

    private func graduate(_ n: inout CardState, days: Double, now: Date) {
        n.phase = .review
        schedule(&n, days: days, now: now)
    }

    private func schedule(_ n: inout CardState, days: Double, now: Date) {
        n.interval = min(maximumInterval, days.rounded())
        n.due = now + n.interval * Self.day
    }
}
