import Foundation
import Testing
@testable import WortCore

@Suite struct InboxTests {
    @Test func roundTripsAndDrains() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wort-inbox-\(UUID())")
        let inbox = Inbox(directory: dir)
        try inbox.add(InboxItem(text: "Tisch", source: "share", savedAt: Date(timeIntervalSince1970: 1)))
        try inbox.add(InboxItem(text: "Stuhl", source: "share", savedAt: Date(timeIntervalSince1970: 2)))
        #expect(inbox.drain().map(\.text) == ["Tisch", "Stuhl"])
        #expect(inbox.drain().isEmpty)
    }

    @Test func sharedTextSplitsWordFromSentence() {
        #expect(InboxItem.fromShared(" Tisch ", source: "s")?.text == "Tisch")
        #expect(InboxItem.fromShared("der Tisch", source: "s")?.text == "der Tisch")
        let s = InboxItem.fromShared("Ich habe heute keine Zeit.", source: "s")
        #expect(s?.text == "")
        #expect(s?.sentence == "Ich habe heute keine Zeit.")
        #expect(InboxItem.fromShared("   ", source: "s") == nil)
        // A long selection is a text to read, not a word.
        let long = InboxItem.fromShared(String(repeating: "Wort ", count: 60), source: "s")
        #expect(long?.reading?.text.hasPrefix("Wort Wort") == true && long?.text == "")
        #expect(InboxItem.fromShared("Erster Absatz.\n\nZweiter.", source: "s")?.reading != nil)
        #expect(InboxItem.fromShared(String(repeating: "a", count: 200_001), source: "s") == nil)
    }

    @Test func addLinks() throws {
        let link = try #require(AddLink(url: URL(string: "wort://add?de=das%20Buch&en=book")!))
        #expect(link.german == "das Buch")
        #expect(link.english == "book")
        #expect(AddLink(url: URL(string: "wort://delete?de=x")!) == nil)
        #expect(AddLink(url: URL(string: "https://add?de=x")!) == nil)
        #expect(AddLink(url: URL(string: "wort://add?de=")!) == nil)
        let made = try #require(AddLink.url(german: "Straße", english: "street"))
        #expect(AddLink(url: made)?.german == "Straße")
    }

    @Test func oldInboxFilesStillDecode() throws {
        let json = #"{"text":"Tisch","source":"share","savedAt":"2026-01-01T00:00:00Z"}"#
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let item = try d.decode(InboxItem.self, from: Data(json.utf8))
        #expect(item.text == "Tisch" && item.reading == nil)
    }

    @Test func articleKeepsTitleAndURL() {
        let a = InboxItem.article(title: " Der Zug ", text: "Absatz eins.\n\nAbsatz zwei.", url: "https://example.org/a", source: "share")
        #expect(a?.reading == SharedText(title: "Der Zug", text: "Absatz eins.\n\nAbsatz zwei.", url: "https://example.org/a"))
        #expect(InboxItem.article(title: "x", text: "  ", url: nil, source: "share") == nil)
    }
}
