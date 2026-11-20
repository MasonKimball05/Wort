import Foundation

/// Your data as files you keep: a CSV of the words (opens in Numbers, Excel,
/// Anki's importer) and a full JSON backup with every review and grammar answer.
public enum Backup {
    public struct WordRecord: Codable, Equatable, Sendable {
        public var german: String          // "das Buch"
        public var lemma: String
        public var partOfSpeech: String
        public var gender: String?
        public var plural: String?
        public var english: String
        public var exampleGerman: String?
        public var exampleEnglish: String?
        public var government: String?
        public var forms: String?
        public var source: String
        public var addedAt: Date
        public var reviews: [ReviewRecord]

        public init(german: String, lemma: String, partOfSpeech: String, gender: String?, plural: String?,
                    english: String, exampleGerman: String?, exampleEnglish: String?, government: String?,
                    forms: String?, source: String, addedAt: Date, reviews: [ReviewRecord]) {
            self.german = german; self.lemma = lemma; self.partOfSpeech = partOfSpeech; self.gender = gender
            self.plural = plural; self.english = english; self.exampleGerman = exampleGerman
            self.exampleEnglish = exampleEnglish; self.government = government; self.forms = forms
            self.source = source; self.addedAt = addedAt; self.reviews = reviews
        }
    }

    public struct ReviewRecord: Codable, Equatable, Sendable {
        public var drill: String
        public var rating: String
        public var at: Date
        public init(drill: String, rating: String, at: Date) { self.drill = drill; self.rating = rating; self.at = at }
    }

    public struct GrammarRecord: Codable, Equatable, Sendable {
        public var item: String
        public var topic: String
        public var correct: Bool
        public var at: Date
        public init(item: String, topic: String, correct: Bool, at: Date) {
            self.item = item; self.topic = topic; self.correct = correct; self.at = at
        }
    }

    public struct ReadingRecord: Codable, Equatable, Sendable {
        public var title: String
        public var text: String
        public var addedAt: Date
        public init(title: String, text: String, addedAt: Date) { self.title = title; self.text = text; self.addedAt = addedAt }
    }

    public struct File: Codable, Equatable, Sendable {
        public var app = "Wort"
        public var version = 1
        public var exportedAt: Date
        public var words: [WordRecord]
        public var grammar: [GrammarRecord]
        public var readings: [ReadingRecord]
        public init(exportedAt: Date, words: [WordRecord], grammar: [GrammarRecord], readings: [ReadingRecord]) {
            self.exportedAt = exportedAt; self.words = words; self.grammar = grammar; self.readings = readings
        }
    }

    public static func json(_ file: File) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(file)
    }

    public static func decode(_ data: Data) throws -> File {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(File.self, from: data)
    }

    /// One row per word. Fields with a comma, quote or line break are quoted,
    /// quotes doubled (RFC 4180).
    public static func csv(_ words: [WordRecord]) -> String {
        let header = ["German", "English", "Part of speech", "Plural", "Preposition + case", "Verb forms",
                      "Example", "Example (English)", "Added"]
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withFullDate]
        let rows = words.map { w in
            [w.german, w.english, w.partOfSpeech, w.plural ?? "", w.government ?? "", w.forms ?? "",
             w.exampleGerman ?? "", w.exampleEnglish ?? "", dates.string(from: w.addedAt)]
        }
        return ([header] + rows).map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func field(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
