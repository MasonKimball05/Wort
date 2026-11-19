import SwiftData
import SwiftUI
import WortCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var words: [Word]
    @State private var newPerDay = Queue.newPerDay
    @State private var message: String?
    @State private var counts: [String: Int] = [:]

    var body: some View {
        NavigationStack {
            Form {
                // The level selector: add whichever starter decks fit. Each is added
                // once (re-adding skips words already there), and only when asked,
                // so two synced devices never import the same deck twice.
                Section {
                    ForEach(StarterDeck.levels, id: \.self) { level in
                        let total = StarterDeck.words(level: level).count
                        let have = counts[level] ?? 0
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(level).font(.headline)
                                Text(StarterDeck.descriptions[level] ?? "").font(.caption).foregroundStyle(.secondary)
                                Text(have == 0 ? "\(total) words" : "\(have) of \(total) added")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if have < total {
                                Button(have == 0 ? "Add" : "Add rest") { add(level) }
                                    .buttonStyle(.bordered)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                } header: {
                    Text("Starter decks")
                } footer: {
                    Text("Pick the level that fits. A1 is for starting out; C1 is for polishing advanced German.")
                }

                Section("Daily") {
                    Stepper("New words a day: \(newPerDay)", value: $newPerDay, in: 0...50, step: 5)
                        .onChange(of: newPerDay) { _, v in Queue.newPerDay = v }
                }

                Section("Sync") {
                    LabeledContent("iCloud sync", value: Store.syncStatus)
                }

                Section("Collection") {
                    LabeledContent("Words", value: "\(words.count)")
                    LabeledContent("Waiting for lookup", value: "\(words.filter(\.needsLookup).count)")
                }

                Section {
                    Text("Meanings, articles, plurals and verb forms of words you add come from Wiktionary (CC BY-SA). Only the word itself is sent.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let m = message {
                    Section { Label(m, systemImage: "checkmark.circle").foregroundStyle(.green) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .onAppear(perform: refreshCounts)
        }
    }

    func add(_ level: String) {
        let n = Store.importStarter(level: level, context: context)
        Store.deduplicate(context: context)
        message = n == 0 ? "\(level) was already added." : "Added \(n) \(level) words."
        refreshCounts()
    }

    func refreshCounts() {
        for level in StarterDeck.levels { counts[level] = Store.imported(level: level, context: context) }
    }
}
