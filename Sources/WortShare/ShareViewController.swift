import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WortCore

/// Saves the shared text to Wort's inbox and closes. The app looks the word up
/// (article, plural, meaning) the next time it opens; nothing here needs the
/// network or the database.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await save() }
    }

    func save() async {
        let text = await sharedText()
        let item = text.flatMap { InboxItem.fromShared($0, source: "share") }
        var message = "Nothing to save"
        if let item {
            do {
                try AppGroup.inbox.add(item)
                message = item.text.isEmpty ? "Sentence saved to Wort" : "„\(item.text)“ saved to Wort"
            } catch {
                message = "Couldn't save"
            }
        }
        let host = UIHostingController(rootView: SavedBadge(message: message))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        try? await Task.sleep(for: .seconds(0.9))
        extensionContext?.completeRequest(returningItems: nil)
    }

    func sharedText() async -> String? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let s = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String { return s }
        }
        return nil
    }
}

struct SavedBadge: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.headline)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
