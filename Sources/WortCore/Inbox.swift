import Foundation

/// A word waiting to be added: saved by the share extension (or anything else
/// that can't open the app's database), picked up by the app on its next launch.
///
/// The extension only writes these small JSON files, never the database: that
/// keeps CloudKit and SwiftData out of the extension, and a word saved while
/// offline still gets looked up later.
public struct InboxItem: Codable, Equatable, Sendable {
    public var text: String
    /// The sentence it came from, if the selection was longer than one word.
    public var sentence: String?
    public var english: String?
    public var source: String
    public var savedAt: Date
    /// A whole text (an article shared from Safari, a long selection), for the
    /// reading list. Optional, so files written by older builds still decode.
    public var reading: SharedText?

    public init(text: String, sentence: String? = nil, english: String? = nil, source: String,
                savedAt: Date = .now, reading: SharedText? = nil) {
        self.text = text
        self.sentence = sentence
        self.english = english
        self.source = source
        self.savedAt = savedAt
        self.reading = reading
    }

    /// Longer than this many words (or with a paragraph break) and it's a text to read.
    public static let readingWords = 40

    /// An article shared from a web page: its title and the paragraphs pulled out of it.
    public static func article(title: String?, text: String, url: String?, source: String) -> InboxItem? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 200_000 else { return nil }
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return InboxItem(text: "", source: source,
                         reading: SharedText(title: name?.isEmpty == false ? name : nil, text: body, url: url))
    }

    /// Splits shared text into the word to learn and its sentence. A single word
    /// (or "der Tisch") is the word; anything longer is kept as the sentence, and
    /// the word is left for the person to pick in the app.
    public static func fromShared(_ raw: String, source: String) -> InboxItem? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 200_000 else { return nil }
        let words = text.split(whereSeparator: \.isWhitespace)
        if words.count > readingWords || text.contains("\n\n") {
            return article(title: nil, text: text, url: nil, source: source)
        }
        if words.count == 1 || (words.count == 2 && Gender(article: String(words[0])) != nil) {
            return InboxItem(text: text, source: source)
        }
        return InboxItem(text: "", sentence: text, source: source)
    }
}

public struct SharedText: Codable, Equatable, Sendable {
    public var title: String?
    public var text: String
    public var url: String?
    public init(title: String?, text: String, url: String?) {
        self.title = title
        self.text = text
        self.url = url
    }
}

public struct Inbox: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func add(_ item: InboxItem) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let name = "\(Int(item.savedAt.timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).json"
        // Atomic, so the app never reads half a file.
        try encoder.encode(item).write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    /// Every waiting item, oldest first, removing each file once it's read.
    public func drain() -> [InboxItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files.compactMap { url in
            defer { try? FileManager.default.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(InboxItem.self, from: data)
        }
    }
}

/// `wort://add?de=…&en=…&ex=…`, so Hop (or a Shortcut) can add a word without
/// sharing a container. Only adds; never reads or deletes.
public struct AddLink: Equatable, Sendable {
    public var german: String
    public var english: String?
    public var example: String?

    public init?(url: URL) {
        guard url.scheme == "wort", url.host == "add",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let de = items.first(where: { $0.name == "de" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !de.isEmpty, de.count <= 200 else { return nil }
        german = de
        english = items.first(where: { $0.name == "en" })?.value.flatMap { $0.isEmpty ? nil : String($0.prefix(300)) }
        example = items.first(where: { $0.name == "ex" })?.value.flatMap { $0.isEmpty ? nil : String($0.prefix(500)) }
    }

    public static func url(german: String, english: String?) -> URL? {
        var c = URLComponents()
        c.scheme = "wort"; c.host = "add"
        c.queryItems = [URLQueryItem(name: "de", value: german)] + (english.map { [URLQueryItem(name: "en", value: $0)] } ?? [])
        return c.url
    }
}
