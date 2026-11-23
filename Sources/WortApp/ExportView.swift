import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WortCore

/// A file to save: the words as CSV, or everything as JSON.
struct ExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText, .json]
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
enum Exporter {
    static func file(context: ModelContext) -> Backup.File {
        let words = ((try? context.fetch(FetchDescriptor<Word>(sortBy: [SortDescriptor(\.lemma)]))) ?? []).map { w in
            Backup.WordRecord(
                german: w.display, lemma: w.lemma, partOfSpeech: w.partOfSpeechRaw, gender: w.genderRaw,
                plural: w.pluralOnly ? nil : w.plural, english: w.english,
                exampleGerman: w.exampleGerman, exampleEnglish: w.exampleEnglish,
                government: w.government, forms: w.forms, source: w.source, addedAt: w.createdAt,
                reviews: (w.cards ?? []).flatMap { card in
                    (card.reviews ?? []).map {
                        Backup.ReviewRecord(drill: card.kindRaw, rating: (Rating(rawValue: $0.ratingRaw) ?? .good).label.lowercased(),
                                            at: $0.at, hinted: $0.hinted)
                    }
                }.sorted { $0.at < $1.at })
        }
        let grammar = ((try? context.fetch(FetchDescriptor<GrammarAttempt>(sortBy: [SortDescriptor(\.at)]))) ?? []).map {
            Backup.GrammarRecord(item: $0.itemID, topic: $0.topicRaw, correct: $0.correct, at: $0.at, hinted: $0.hinted)
        }
        let readings = ((try? context.fetch(FetchDescriptor<Reading>(sortBy: [SortDescriptor(\.addedAt)]))) ?? []).map {
            Backup.ReadingRecord(title: $0.title, text: $0.text, addedAt: $0.addedAt)
        }
        let listening = ((try? context.fetch(FetchDescriptor<ListeningAttempt>(sortBy: [SortDescriptor(\.at)]))) ?? []).map {
            Backup.ListeningRecord(word: $0.wordKey, mode: $0.mode, correct: $0.correct, hinted: $0.hinted, at: $0.at)
        }
        return Backup.File(exportedAt: .now, words: words, grammar: grammar, readings: readings, listening: listening)
    }

    static var dateStamp: String { Date.now.formatted(.iso8601.year().month().day()) }
}

/// The Settings section with the two export buttons.
struct ExportSection: View {
    @Environment(\.modelContext) private var context
    @State private var document: ExportFile?
    @State private var type: UTType = .commaSeparatedText
    @State private var name = ""
    @State private var exporting = false
    @State private var message: String?

    var body: some View {
        Section {
            Button("Export words (CSV)", systemImage: "tablecells") {
                prepare(Data(Backup.csv(Exporter.file(context: context).words).utf8), .commaSeparatedText, "Wort words")
            }
            Button("Export everything (JSON)", systemImage: "externaldrive") {
                guard let data = try? Backup.json(Exporter.file(context: context)) else { message = "Couldn't export"; return }
                prepare(data, .json, "Wort backup")
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        } header: {
            Text("Backup")
        } footer: {
            Text("The CSV opens in Numbers or Excel. The JSON has everything: words, every review and grammar answer, and your texts.")
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: type, defaultFilename: name) { result in
            switch result {
            case .success: message = "Saved."
            case .failure(let e): message = "Couldn't save: \(e.localizedDescription)"
            }
        }
    }

    func prepare(_ data: Data, _ type: UTType, _ base: String) {
        document = ExportFile(data: data)
        self.type = type
        name = "\(base) \(Exporter.dateStamp)"
        message = nil
        exporting = true
    }
}
