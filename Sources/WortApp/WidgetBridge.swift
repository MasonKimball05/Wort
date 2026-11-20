import Foundation
import SwiftData
import WidgetKit
import WortCore

/// Writes what the widget shows into the App Group and asks it to redraw.
@MainActor
enum WidgetBridge {
    static func update(context: ModelContext) {
        let reviewed = (try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { !$0.isNew }))) ?? []
        // The soonest 2000 is plenty: the widget only looks ahead 12 hours.
        let dueDates = Array(reviewed.map(\.due).sorted().prefix(2000))
        let now = Date.now
        let newToday = Queue.next(context: context, now: now).filter(\.isNew).count
        let reviews = (try? context.fetch(FetchDescriptor<Review>())) ?? []
        let attempts = (try? context.fetch(FetchDescriptor<GrammarAttempt>())) ?? []
        let streak = Streak.summary(reviews.map(\.at) + attempts.map(\.at), today: now)
        let snapshot = WidgetSnapshot(dueDates: dueDates, newToday: newToday, streak: streak.current,
                                      practicedToday: streak.practicedToday, updatedAt: now)
        guard let data = snapshot.encoded(), let defaults = UserDefaults(suiteName: AppGroup.id) else { return }
        defaults.set(data, forKey: WidgetSnapshot.key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
