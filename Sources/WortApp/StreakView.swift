import SwiftData
import SwiftUI
import WortCore

/// Days in a row, and a calendar of the last 16 weeks. Counts vocab reviews,
/// grammar answers and listening.
struct StreakView: View {
    @Environment(\.dismiss) private var dismiss
    let summary: Streak.Summary

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        StatTile(value: "\(summary.current)", label: summary.current == 1 ? "day in a row" : "days in a row",
                                 symbol: "flame.fill", tint: .orange)
                        StatTile(value: "\(summary.longest)", label: "longest", symbol: "trophy.fill", tint: .yellow)
                    }
                    if !summary.practicedToday, summary.current > 0 {
                        Label("Practice today to keep it going.", systemImage: "clock")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    CalendarGrid(perDay: summary.perDay)
                        .padding(16)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(20)
            }
            .background(Color.groupedBackground)
            .navigationTitle("Streak")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }
}

/// Weeks as columns, Monday to Sunday down, darker for more answers.
struct CalendarGrid: View {
    let perDay: [Date: Int]
    var weeks = 16

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        // Back to the Monday that starts the first column.
        let weekday = (cal.component(.weekday, from: today) + 5) % 7      // Monday = 0
        let start = cal.date(byAdding: .day, value: -(weekday + 7 * (weeks - 1)), to: today)!
        VStack(alignment: .leading, spacing: 8) {
            Text("Last \(weeks) weeks").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(perDay[day] ?? 0, future: day > today))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    if day == today { RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.5)) }
                                }
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach([0, 5, 20, 50], id: \.self) { n in
                    RoundedRectangle(cornerRadius: 2).fill(color(n, future: false)).frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    func color(_ n: Int, future: Bool) -> Color {
        if future { return .clear }
        switch n {
        case 0: return Color.secondary.opacity(0.15)
        case 1..<10: return Color.green.opacity(0.4)
        case 10..<30: return Color.green.opacity(0.7)
        default: return Color.green
        }
    }
}
