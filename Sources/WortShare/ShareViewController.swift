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
        let item = await sharedItem()
        var message = "Nothing to save"
        if let item {
            do {
                try AppGroup.inbox.add(item)
                if item.reading != nil {
                    message = "Saved to your reading list"
                } else {
                    message = item.text.isEmpty ? "Sentence saved to Wort" : "„\(item.text)“ saved to Wort"
                }
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

    /// A Safari page comes as the result of ExtractArticle.js: a selection is
    /// handled like shared text (a word, a sentence, or a passage to read);
    /// without one, the article's paragraphs go to the reading list. Text shared
    /// from anywhere else (Notes, Books) is plain text.
    func sharedItem() async -> InboxItem? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
            guard let dict = try? await p.loadItem(forTypeIdentifier: UTType.propertyList.identifier) as? [String: Any],
                  let page = dict[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] else { continue }
            let selection = (page["selection"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !selection.isEmpty { return InboxItem.fromShared(selection, source: "share") }
            return InboxItem.article(title: page["title"] as? String, text: page["text"] as? String ?? "",
                                     url: page["url"] as? String, source: "share")
        }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let s = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                return InboxItem.fromShared(s, source: "share")
            }
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
