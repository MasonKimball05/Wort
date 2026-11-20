import SwiftUI
import WidgetKit
import WortCore

/// Cards to review and the streak, on the Home Screen, Lock Screen and Mac desktop.
/// Reads only the snapshot the app writes into the App Group.
struct Entry: TimelineEntry {
    let date: Date
    let due: Int
    let streak: Int
    let practicedToday: Bool
    let nextDue: Date?
    let hasData: Bool
}

struct Provider: TimelineProvider {
    static let groupID = "group.com.masonkimball.wort"

    func snapshot() -> WidgetSnapshot? {
        WidgetSnapshot.decode(UserDefaults(suiteName: Self.groupID)?.data(forKey: WidgetSnapshot.key))
    }

    func entry(_ s: WidgetSnapshot?, at date: Date) -> Entry {
        guard let s else { return Entry(date: date, due: 0, streak: 0, practicedToday: false, nextDue: nil, hasData: false) }
        let streak = s.streak(at: date)
        return Entry(date: date, due: s.due(at: date), streak: streak.days, practicedToday: streak.practicedToday,
                     nextDue: s.nextDue(after: date), hasData: true)
    }

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, due: 12, streak: 5, practicedToday: true, nextDue: nil, hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(snapshot(), at: .now))
    }

    /// An entry each hour for the next 12, so the count rises as cards fall due
    /// with the app closed; the app also reloads it whenever it answers a card.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let s = snapshot()
        let now = Date.now
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        var entries = [entry(s, at: now)]
        for h in 1...12 {
            if let d = Calendar.current.date(byAdding: .hour, value: h, to: hour) { entries.append(entry(s, at: d)) }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WortWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryCircular:
            Gauge(value: 0) { Text("Wort") } currentValueLabel: { Text("\(entry.due)") }
                .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Wort").font(.headline)
                Text(entry.due == 0 ? "All done" : "\(entry.due) to review")
                Label("\(entry.streak) days", systemImage: "flame.fill").font(.caption)
            }
        #endif
        case .systemMedium:
            HStack(spacing: 20) {
                count
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    streak
                    if let next = entry.nextDue, entry.due == 0 {
                        Label { Text("Next \(next, style: .relative)") } icon: { Image(systemName: "clock") }
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                count
                Spacer(minLength: 0)
                streak
            }
        }
    }

    var count: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Wort").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(entry.due)").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
            Text(!entry.hasData ? "Open Wort once" : entry.due == 0 ? "all done" : "to review")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    var streak: some View {
        Label("\(entry.streak)", systemImage: "flame.fill")
            .font(.headline)
            .foregroundStyle(entry.practicedToday ? .orange : .secondary)
    }
}

@main
struct WortWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WortWidget", provider: Provider()) { entry in
            WortWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Wort")
        .description("Cards to review and your streak.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
        #else
        .supportedFamilies([.systemSmall, .systemMedium])
        #endif
    }
}
