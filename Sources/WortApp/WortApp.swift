import SwiftData
import SwiftUI
import WortCore

@main
struct WortApp: App {
    let container = Store.makeContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in handle(url) }
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 760, height: 640)
        #endif
    }

    /// `wort://add?de=…&en=…`: from Hop on the Mac, or a Shortcut.
    @MainActor func handle(_ url: URL) {
        guard let link = AddLink(url: url) else { return }
        let context = container.mainContext
        Store.addPending(german: link.german, english: link.english, example: link.example,
                         source: "link", context: context)
        try? context.save()
        Task { await Enricher.run(context: context) }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TabView {
            Tab("Review", systemImage: "rectangle.stack") { ReviewView() }
            Tab("Grammar", systemImage: "text.badge.checkmark") { GrammarView() }
            Tab("Words", systemImage: "character.book.closed") { WordsView() }
            Tab("Add", systemImage: "plus.circle") { AddWordView() }
            Tab("Settings", systemImage: "gearshape") { SettingsView() }
        }
        .task { await refresh() }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await refresh() } }
            // Leaving the app: bring the widget up to date with what was just done.
            if p == .background || p == .inactive { WidgetBridge.update(context: context) }
        }
    }

    /// On launch and whenever the app comes back: pick up shared words, merge
    /// anything synced twice, and look up whatever is still missing details.
    func refresh() async {
        _ = Store.importInbox(context: context)
        Store.deduplicate(context: context)
        await Enricher.run(context: context)
        WidgetBridge.update(context: context)
    }
}
