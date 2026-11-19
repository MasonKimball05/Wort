import Foundation
import Testing
@testable import WortCore

func fixture(_ word: String) -> String? {
    // The Mac's filesystem ignores case, so lowercase pages that clash with a
    // capitalised one are saved as "lower-<word>.html".
    let name = word.first?.isLowercase == true && ["buch", "würde"].contains(word) ? "lower-\(word)"
        : ["Anrufen", "Würde"].contains(word) ? "upper-\(word)" : word
    // File names may be stored decomposed (ü = u + ¨), and Bundle's name lookup
    // misses them, so list the folder and compare normalised names.
    guard let dir = Bundle.module.url(forResource: "Fixtures", withExtension: nil),
          let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
          let url = files.first(where: {
              $0.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
                  == name.precomposedStringWithCanonicalMapping
          }) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

let fixtureFetcher: PageFetcher = { word in fixture(word) }

@Suite struct ParserTests {
    func entries(_ w: String) -> [DictionaryEntry] { WiktionaryParser.entries(fromPageHTML: fixture(w)!) }

    @Test func nounWithGenderAndPlural() throws {
        let e = try #require(entries("Buch").first { $0.partOfSpeech == .noun })
        #expect(e.lemma == "Buch")
        #expect(e.gender == .neuter)
        #expect(e.plural == "Bücher")
        #expect(e.glosses.first?.contains("book") == true)
    }

    @Test(arguments: [("Frau", Gender.feminine, "Frauen"), ("Mann", .masculine, "Männer"),
                      ("Haus", .neuter, "Häuser"), ("Zeitung", .feminine, "Zeitungen"),
                      ("Auto", .neuter, "Autos"), ("Handy", .neuter, "Handys")])
    func commonNouns(word: String, gender: Gender, plural: String) throws {
        let e = try #require(entries(word).first { $0.partOfSpeech == .noun })
        #expect(e.gender == gender, "\(word)")
        #expect(e.plural == plural, "\(word)")
    }

    @Test func pluralSameAsSingular() throws {
        let e = try #require(entries("Mädchen").first { $0.partOfSpeech == .noun })
        #expect(e.gender == .neuter)
        #expect(e.plural == "Mädchen")
    }

    @Test func noPlural() throws {
        let e = try #require(entries("Obst").first)
        #expect(e.gender == .neuter)
        #expect(e.noPlural)
        #expect(e.plural == nil)
        #expect(CardKind.kinds(partOfSpeech: e.partOfSpeech, gender: e.gender, plural: e.plural) == [.meaning, .recall, .gender])
    }

    @Test func pluralOnly() throws {
        for w in ["Leute", "Eltern"] {
            let e = try #require(entries(w).first { $0.partOfSpeech == .noun }, "\(w)")
            #expect(e.pluralOnly, "\(w)")
            #expect(e.gender == nil, "\(w)")
            #expect(e.plural == nil, "\(w)")
        }
    }

    @Test func twoNounsOnOnePage() {
        let nouns = entries("See").filter { $0.partOfSpeech == .noun }
        #expect(Set(nouns.compactMap(\.gender)) == [.masculine, .feminine])
    }

    @Test func verbAndAdjective() throws {
        let gehen = try #require(entries("gehen").first)
        #expect(gehen.partOfSpeech == .verb)
        #expect(gehen.gender == nil)
        #expect(gehen.glosses.first?.contains("go") == true)
        let schoen = try #require(entries("schön").first)
        #expect(schoen.partOfSpeech == .adjective)
    }

    @Test func inflectedFormsPointAtTheirLemma() throws {
        #expect(entries("Bücher").first?.formOf == "Buch")
        #expect(entries("ging").first?.formOf == "gehen")
    }

    @Test func glossesDropLabelsAndExamples() throws {
        let handy = try #require(entries("Handy").first)
        let g = try #require(handy.glosses.first)
        #expect(g.hasPrefix("mobile phone"), "\(g)")
        #expect(!g.contains("telephony"), "\(g)")
        #expect(!g.contains("Synonyms"), "\(g)")
    }

    @Test func usageExampleIsKept() throws {
        let obst = try #require(entries("Obst").first)
        #expect(obst.example?.german == "Heute esse ich nur Obst.")
        #expect(obst.example?.english == "Today I only eat fruit.")
    }

    @Test func noGermanSection() {
        #expect(WiktionaryParser.entries(fromPageHTML: "<html><h2 id=\"English\">English</h2></html>").isEmpty)
    }
}

@Suite struct LookupTests {
    let lookup = WordLookup(knownNouns: ["Artikel": .masculine, "Zeitung": .feminine], fetch: fixtureFetcher)

    @Test func plainNoun() async {
        let r = await lookup.lookUp("Buch")
        #expect(r.source == .wiktionary)
        #expect(r.entries.first?.gender == .neuter)
    }

    @Test func lowercaseInputFindsTheNounFirst() async {
        let r = await lookup.lookUp("buch")
        #expect(r.entries.first?.lemma == "Buch")
        #expect(r.entries.first?.partOfSpeech == .noun)
    }

    @Test func inflectedFormResolvesToTheLemma() async {
        let r = await lookup.lookUp("Bücher")
        #expect(r.entries.first?.lemma == "Buch")
        #expect(r.entries.first?.plural == "Bücher")
        #expect(r.enteredForm == "Bücher")
        let v = await lookup.lookUp("ging")
        #expect(v.entries.first?.lemma == "gehen")
    }

    @Test func typedArticlePicksTheEntry() async {
        #expect(await lookup.lookUp("die See").entries.first?.gender == .feminine)
        #expect(await lookup.lookUp("der See").entries.first?.gender == .masculine)
    }

    @Test func compoundWithoutAPageUsesItsHead() async {
        let r = await lookup.lookUp("Zeitungsbericht")      // no fixture → no page
        #expect(r.source == .notFound || r.source == .suffixGuess || r.entries.first?.gender == nil)
        let k = await WordLookup(knownNouns: ["Bericht": .masculine], fetch: fixtureFetcher).lookUp("Zeitungsbericht")
        #expect(k.source == .compound(head: "Bericht"))
        #expect(k.entries.first?.gender == .masculine)
    }

    @Test func suffixGuessWhenNothingElse() async {
        let r = await WordLookup(fetch: fixtureFetcher).lookUp("Verwaltungsreformierung")
        #expect(r.source == .suffixGuess)
        #expect(r.entries.first?.gender == .feminine)
    }

    @Test func typedArticleWinsWhenThereIsNoPage() async {
        let r = await WordLookup(fetch: fixtureFetcher).lookUp("das Blablub")
        #expect(r.entries.first?.gender == .neuter)
    }
}

@Suite struct GermanTests {
    @Test func parsesArticles() {
        #expect(ParsedInput("das Buch") == ParsedInput(gender: .neuter, word: "Buch"))
        #expect(ParsedInput("  Die   Zeitung. ").gender == .feminine)
        #expect(ParsedInput("Buch").gender == nil)
        #expect(ParsedInput("„Buch“").word == "Buch")
    }

    @Test(arguments: [("Zeitung", Gender.feminine), ("Freiheit", .feminine), ("Universität", .feminine),
                      ("Mädchen", .neuter), ("Dokument", .neuter), ("Lehrling", .masculine),
                      ("Kapitalismus", .masculine)])
    func suffixRules(word: String, gender: Gender) {
        #expect(GenderGuess.guess(word) == gender, "\(word)")
    }

    @Test func noRuleNoGuess() {
        #expect(GenderGuess.guess("Tisch") == nil)
    }
}

extension ParsedInput {
    init(gender: Gender?, word: String) {
        self.init("x")
        self.gender = gender
        self.word = word
    }
}

@Suite struct ParserEdgeTests {
    @Test func genderWithAQualifier() throws {
        let e = try #require(WiktionaryParser.entries(fromPageHTML: fixture("E-Mail")!).first)
        #expect(e.lemma == "E-Mail")
        #expect(e.gender == .feminine)
        #expect(e.plural == "E-Mails")
    }

    @Test func throttlingIsUnreachableNotNotFound() async {
        let r = await WordLookup(fetch: { _ in throw LookupError.unreachable }).lookUp("Buch")
        #expect(r.source == .unreachable)
    }
}

@Suite struct ShortForSenseTests {
    /// Lampe's senses include "short for Glühlampe", in the same markup as "plural of".
    /// That must not turn the noun into a redirect (it hid 13 starter-deck nouns).
    @Test(arguments: ["Lampe", "Zeit"])
    func aShortForSenseIsNotARedirect(word: String) async throws {
        let noun = try #require(WiktionaryParser.entries(fromPageHTML: fixture(word)!).first { $0.partOfSpeech == .noun })
        #expect(noun.formOf == nil)
        #expect(noun.gender == .feminine)
        let r = await WordLookup(fetch: fixtureFetcher).lookUp(word)
        #expect(r.entries.first?.partOfSpeech == .noun)
        #expect(r.entries.first?.gender == .feminine)
    }
}

@Suite struct VerbFormTests {
    @Test func strongVerbsGetPrincipalParts() throws {
        let v = try #require(WiktionaryParser.entries(fromPageHTML: fixture("verzeihen")!).first)
        #expect(v.principalParts == "verzieh, hat verziehen")
        let g = try #require(WiktionaryParser.entries(fromPageHTML: fixture("gehen")!).first)
        #expect(g.principalParts == "ging, ist gegangen")
    }

    @Test func weakVerbsDont() throws {
        let v = try #require(WiktionaryParser.entries(fromPageHTML: fixture("arbeiten")!).first)
        #expect(v.partOfSpeech == .verb)
        #expect(v.principalParts == nil)
    }

    @Test func newDrills() {
        #expect(CardKind.kinds(partOfSpeech: .verb, gender: nil, plural: nil, government: "auf + Akk.", forms: "verzichtete, hat verzichtet")
                == [.meaning, .recall, .government, .forms])
        #expect(CardKind.kinds(partOfSpeech: .phrase, gender: nil, plural: nil, government: "auf + Akk.")
                == [.meaning, .recall, .government])
    }
}

@Suite struct VerbPhraseTests {
    @Test func splitsReflexiveAndPreposition() {
        #expect(VerbPhraseInput("sich berufen auf") == VerbPhraseInput(reflexive: true, core: "berufen", preposition: "auf"))
        #expect(VerbPhraseInput("verzichten auf").preposition == "auf")
        #expect(VerbPhraseInput("verzichten").preposition == nil)
        #expect(VerbPhraseInput("auf").core == "auf")              // a bare preposition stays a word
        #expect(VerbPhraseInput("in Erwägung ziehen").preposition == nil)
    }

    @Test func reflexiveVerbLooksUpTheCore() async throws {
        let r = await WordLookup(fetch: fixtureFetcher).lookUp("sich berufen auf")
        let e = try #require(r.entries.first { $0.partOfSpeech == .verb })
        #expect(e.lemma == "sich berufen")
        #expect(e.principalParts == "berief, hat berufen")
        #expect(r.reflexive)
        #expect(r.preposition == "auf")
    }

    @Test func trailingPrepositionIsKept() async throws {
        let r = await WordLookup(fetch: fixtureFetcher).lookUp("verzichten auf")
        #expect(r.entries.first?.lemma == "verzichten")
        #expect(r.entries.first?.partOfSpeech == .verb)
        #expect(r.preposition == "auf")
    }
}

extension VerbPhraseInput {
    init(reflexive: Bool, core: String, preposition: String?) {
        self.init(core)
        self.reflexive = reflexive
        self.core = core
        self.preposition = preposition
    }
}

@Suite struct ExplainTests {
    let lookup = WordLookup(fetch: fixtureFetcher)

    @Test func glossesDontLeakTemplateJSON() throws {
        let e = try #require(WiktionaryParser.entries(fromPageHTML: fixture("anrufen")!).first)
        let g = try #require(e.glosses.first)
        #expect(g.contains("to call"), "\(g)")
        #expect(!g.contains("(dat)") && !g.contains("qq:") && !g.contains("}") && !g.contains("mw-parser"), "\(g)")
        #expect(!g.contains("["), "the usage note is split off: \(g)")
        #expect(e.usage?.contains("accusative") == true, "\(e.usage ?? "-")")
    }

    @Test func aVerbStaysAVerbWhenItsGerundExists() async {
        let x = await lookup.explain("anrufen")
        #expect(x.lookup.entries.first?.partOfSpeech == .verb, "\(x.lookup.entries.map(\.lemma))")
        // Typed in (not from a sentence), the gerund is offered too, after the verb.
        #expect(await lookup.lookUp("anrufen").entries.contains { $0.lemma == "Anrufen" })
        #expect(await lookup.lookUp("buch").entries.first?.lemma == "Buch", "but buch still finds the noun")
    }

    @Test func inflectedVerbExplainsItsFormAndBase() async throws {
        let x = await lookup.explain("anriefe")
        #expect(x.lookup.entries.first?.lemma == "anrufen")
        #expect(x.lookup.formDescription?.contains("subjunctive II of anrufen") == true, "\(x.lookup.formDescription ?? "-")")
        #expect(x.separablePrefix == "an")
        #expect(x.base?.lemma == "rufen")
        #expect(x.base?.glosses.first?.contains("call") == true)
    }

    @Test func articlesExplainTheirCase() async {
        let x = await lookup.explain("dem")
        #expect(x.lookup.formDescription?.hasPrefix("dative") == true, "\(x.lookup.formDescription ?? "-")")
        #expect(x.lookup.enteredForm == "dem")
    }

    @Test func lowercaseWordInASentenceIsNotTheNoun() async {
        let x = await lookup.explain("würde")
        #expect(x.lookup.entries.first?.lemma != "Würde", "\(x.lookup.entries.map(\.lemma))")
        #expect(x.lookup.formDescription?.contains("subjunctive II of werden") == true)
        // ...while typing "buch" in Add still finds the noun.
        #expect(await lookup.lookUp("buch").entries.first?.lemma == "Buch")
    }

    @Test func inflectionListsItsForms() async {
        let x = await lookup.explain("sagte")
        let d = x.lookup.formDescription ?? "-"
        #expect(d.hasPrefix("inflection of sagen: "), "\(d)")
        #expect(d.contains("preterite"), "\(d)")
    }

    @Test func mixedPageKeepsTheFormDescription() async {
        let x = await lookup.explain("deiner")
        #expect(!x.lookup.entries.isEmpty)
        #expect(x.lookup.formDescription?.contains("dein") == true, "\(x.lookup.formDescription ?? "-")")
    }

    @Test func nounLemmaIgnoresAnotherNounsPlural() async {
        // der Zeuge (witness), not "plural of Zeug"
        let x = await lookup.explain("Zeuge")
        #expect(x.lookup.entries.first?.gender == .masculine)
        #expect(x.lookup.formDescription == nil, "\(x.lookup.formDescription ?? "-")")
    }

    @Test func pluralNounExplainsItsForm() async {
        let x = await lookup.explain("Bücher.")
        #expect(x.lookup.formDescription?.contains("plural of Buch") == true)
        #expect(x.lookup.entries.first?.gender == .neuter)
        #expect(x.separablePrefix == nil)
    }

    @Test(arguments: [("anrufen", "an", "rufen"), ("zurückgreifen", "zurück", "greifen"), ("teilnehmen", "teil", "nehmen")])
    func separableSplits(verb: String, prefix: String, base: String) {
        let s = SeparableVerb.split(verb)
        #expect(s?.prefix == prefix && s?.base == base)
    }

    @Test func notEverythingSplits() {
        #expect(SeparableVerb.split("arbeiten") == nil)
        // "antworten" isn't an + tworten; the lookup only shows a base verb when one
        // exists on Wiktionary, so a false split shows nothing extra.
        #expect(SeparableVerb.split("antworten")?.base == "tworten")
    }
}
