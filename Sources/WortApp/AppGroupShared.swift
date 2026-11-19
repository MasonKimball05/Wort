import Foundation
import WortCore

// Shared by the app and the share extension (which has no database code).
enum AppGroup {
    static let id = "group.com.masonkimball.wort"

    /// The shared container on iOS (the share extension writes its inbox there).
    /// The Mac app has no extension, so it uses its own Application Support.
    static var containerURL: URL {
        #if os(iOS)
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) { return url }
        #endif
        let url = URL.applicationSupportDirectory.appendingPathComponent("Wort", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var inbox: Inbox { Inbox(directory: containerURL.appendingPathComponent("Inbox", isDirectory: true)) }
}
