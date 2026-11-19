import Foundation

/// One German entry from an English Wiktionary page (a page can hold several:
/// "See" is der See, lake, and die See, sea).
public struct DictionaryEntry: Equatable, Sendable {
    public var lemma: String
    public var partOfSpeech: PartOfSpeech
    public var gender: Gender?
    /// Nominative plural; nil when unknown, when there is none, or for non-nouns.
    public var plural: String?
    public var pluralOnly = false          // Leute, Eltern
    public var noPlural = false            // Obst
    public var glosses: [String] = []      // English meanings, most common first
    public var example: Example?
    /// Set when this page is an inflected form: "Bücher" → "Buch", "ging" → "gehen".
    public var formOf: String?
    /// Principal parts of a strong, mixed or irregular verb: "verzieh, hat verziehen".
    /// Nil for weak verbs, whose forms are predictable.
    public var principalParts: String?
    /// A usage note from the first sense, often the case a verb takes:
    /// "with accusative or dative or bei + dative" (anrufen).
    public var usage: String?

    public init(lemma: String, partOfSpeech: PartOfSpeech) {
        self.lemma = lemma
        self.partOfSpeech = partOfSpeech
    }
}

public struct Example: Equatable, Codable, Sendable {
    public var german: String
    public var english: String?
    public init(german: String, english: String?) {
        self.german = german
        self.english = english
    }
}

/// Reads the German section of a page from Wiktionary's REST API
/// (`/api/rest_v1/page/html/<word>`), which is Parsoid HTML.
///
/// It reads the rendered headword line (`<span class="gender">`, the `plural`
/// label) rather than the `de-noun` template's compressed arguments, because the
/// rendered form is what the template is for and has been stable through the
/// template's own rewrites.
public enum WiktionaryParser {

    public static func entries(fromPageHTML html: String) -> [DictionaryEntry] {
        guard let section = germanSection(html) else { return [] }
        let starts = ranges(of: "class=\"headword-line\"", in: section)
        var out: [DictionaryEntry] = []
        for (i, start) in starts.enumerated() {
            let end = i + 1 < starts.count ? starts[i + 1].lowerBound : section.endIndex
            let block = String(section[start.lowerBound..<end])
            if let entry = entry(fromBlock: block) { out.append(entry) }
        }
        return out
    }

    // MARK: Sections

    static func germanSection(_ html: String) -> Substring? {
        guard let id = html.range(of: "id=\"German\"") else { return nil }
        let rest = html[id.upperBound...]
        let end = rest.range(of: "<h2")?.lowerBound ?? html.endIndex
        return html[id.upperBound..<end]
    }

    // MARK: One headword and its senses

    static func entry(fromBlock block: String) -> DictionaryEntry? {
        guard let headwordEnd = block.range(of: "</strong>"),
              let lemma = firstMatch(#"<strong class="[^"]*headword[^"]*"[^>]*>(.*?)</strong>"#, in: block).map(text)
        else { return nil }

        let template = firstMatch(#""target":\{"wt":"([a-z-]+)""#, in: block) ?? ""
        var entry = DictionaryEntry(lemma: lemma, partOfSpeech: partOfSpeech(template: template, block: block))

        // The headword line runs to the first sense list.
        let lineEnd = block.range(of: "<ol")?.lowerBound ?? block.endIndex
        let line = String(block[headwordEnd.upperBound..<lineEnd])

        if entry.partOfSpeech == .noun {
            // The gender span can start with a qualifier: "(predominantly) f" for E-Mail.
            if let title = firstMatch(#"<span class="gender">(?:(?!</abbr>).)*?<abbr title="([a-z ]+)""#, in: line) {
                if title.hasPrefix("masculine") { entry.gender = .masculine }
                else if title.hasPrefix("feminine") { entry.gender = .feminine }
                else if title.hasPrefix("neuter") { entry.gender = .neuter }
                else if title.hasPrefix("plural") { entry.pluralOnly = true }
            }
            let plain = text(line)
            if plain.contains("plural only") { entry.pluralOnly = true }
            if plain.contains("no plural") { entry.noPlural = true }
            if !entry.pluralOnly, !entry.noPlural,
               let p = firstMatch(#"<i>plural</i>\s*<b[^>]*>(.*?)</b>"#, in: line).map(text) {
                entry.plural = p
            }
        }

        if entry.partOfSpeech == .verb {
            entry.principalParts = principalParts(line: line)
        }

        // Senses: each <li> of the first <ol>, up to its nested example/quote lists.
        if let olStart = block.range(of: "<ol") {
            let senses = String(block[olStart.lowerBound...])
            for li in topLevelItems(senses).prefix(6) {
                // Only a non-lemma entry ({{head|de|noun form}}, "plural of Buch") is an
                // inflected form. A lemma's sense can use the same markup ("short for
                // Glühlampe" on Lampe), and treating that as a redirect lost the noun.
                if entry.formOf == nil, template == "head", li.contains("form-of-definition"),
                   let target = firstMatch(#"form-of-definition-link"><i[^>]*><a[^>]*>(.*?)</a>"#, in: li).map(text) {
                    entry.formOf = target
                }
                var gloss = glossText(li)
                // "inflection of sagen:" lists its forms in a nested list: add them
                // ("…: first/third-person singular preterite; …").
                if gloss.hasSuffix(":"), let nested = li.range(of: "<ol") {
                    let forms = topLevelItems(String(li[nested.lowerBound...])).map(glossText).filter { !$0.isEmpty }
                    if !forms.isEmpty { gloss += " " + forms.prefix(4).joined(separator: "; ") }
                }
                // "[with accusative or dative]" is a usage note, not part of the meaning.
                if let r = gloss.range(of: #"\s*\[[^\]]*\]"#, options: .regularExpression) {
                    let note = gloss[r].trimmingCharacters(in: CharacterSet(charactersIn: " []"))
                    if entry.usage == nil, !note.isEmpty { entry.usage = note }
                    gloss.removeSubrange(r)
                    gloss = gloss.trimmingCharacters(in: .whitespaces)
                }
                if !gloss.isEmpty { entry.glosses.append(gloss) }
                if entry.example == nil,
                   let de = firstMatch(#"<i class="[^"]*e-example[^"]*"[^>]*>(.*?)</i>"#, in: li).map(text) {
                    let en = firstMatch(#"<span class="e-translation">(.*?)</span>"#, in: li).map(text)
                    entry.example = Example(german: de, english: en)
                }
            }
        }
        return entry
    }

    /// "verzieh, hat verziehen" from the headword line of a strong verb.
    static func principalParts(line: String) -> String? {
        let plain = text(line)
        guard plain.contains("strong") || plain.contains("irregular") || plain.contains("mixed") else { return nil }
        func form(_ label: String) -> String? {
            firstMatch("<i>\(label)</i>\\s*<b[^>]*>(.*?)</b>", in: line).map(text)
        }
        guard let past = form("past tense"), let participle = form("past participle") else { return nil }
        let aux = form("auxiliary")
        let helper = aux == "sein" ? "ist" : aux == "haben" ? "hat" : (aux.map { "\($0)" } ?? "")
        return helper.isEmpty ? "\(past), \(participle)" : "\(past), \(helper) \(participle)"
    }

    static func partOfSpeech(template: String, block: String) -> PartOfSpeech {
        switch template {
        case "de-noun", "de-proper noun": return .noun
        case "de-verb": return .verb
        case "de-adj": return .adjective
        case "de-adv": return .adverb
        case "head":
            // {{head|de|noun plural form}} and friends: read the category text.
            if block.contains("\"wt\":\"verb form") { return .verb }
            if block.contains("\"wt\":\"noun form") || block.contains("noun plural form") { return .noun }
            if block.contains("\"wt\":\"adjective form") { return .adjective }
            return .other
        default: return .other
        }
    }

    // MARK: Text helpers

    /// The <li> elements directly inside the first <ol>, without nested lists.
    static func topLevelItems(_ html: String) -> [String] {
        var items: [String] = []
        var depth = 0, current = "", inItem = false
        var i = html.startIndex
        while i < html.endIndex {
            let rest = html[i...]
            if rest.hasPrefix("<ol") || rest.hasPrefix("<ul") || rest.hasPrefix("<dl>") || rest.hasPrefix("<dl ") { depth += 1 }
            if rest.hasPrefix("</ol>") || rest.hasPrefix("</ul>") || rest.hasPrefix("</dl>") {
                depth -= 1
                if depth == 0 { break }
            }
            // "<li>" or "<li " exactly: a bare "<li" prefix also matches "<link".
            if depth == 1, rest.hasPrefix("<li>") || rest.hasPrefix("<li ") { inItem = true; current = "" }
            if depth == 1, rest.hasPrefix("</li>") {
                items.append(current); inItem = false
            }
            if inItem { current.append(html[i]) }
            i = html.index(after: i)
        }
        return items
    }

    /// A sense's English meaning: the text before its nested lists, without
    /// usage labels ("(mobile telephony)"), qualifiers or parenthetical glosses.
    static func glossText(_ li: String) -> String {
        var s = li
        for marker in ["<dl", "<ul", "<ol"] {
            if let r = s.range(of: marker) { s = String(s[..<r.lowerBound]) }
        }
        for cls in ["usage-label-sense", "qualifier-brac", "qualifier-content", "mention-gloss-paren", "mention-gloss"] {
            s = removingSpans(withClass: cls, from: s)
        }
        var t = text(s)
        t = t.replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+([,.;])"#, with: "$1", options: .regularExpression)
        return t.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;.")))
    }

    /// Removes every `<span>` whose class list contains `cls`, with its contents,
    /// counting nested spans (a usage label holds several).
    static func removingSpans(withClass cls: String, from html: String) -> String {
        var s = html
        while let open = s.range(of: #"<span class="[^"]*\b\#(cls)\b[^"]*"[^>]*>"#, options: .regularExpression) {
            var depth = 1
            var i = open.upperBound
            while depth > 0, i < s.endIndex {
                let rest = s[i...]
                if rest.hasPrefix("<span") { depth += 1; i = s.index(i, offsetBy: 5) }
                else if rest.hasPrefix("</span>") {
                    depth -= 1
                    i = s.index(i, offsetBy: 7)
                } else { i = s.index(after: i) }
            }
            s.removeSubrange(open.lowerBound..<i)
        }
        return s
    }

    /// Strips tags and entities, collapses whitespace.
    static func text<S: StringProtocol>(_ html: S) -> String {
        // Parsoid's data-mw attributes hold template JSON that can contain ">",
        // which would end a tag early and leak the JSON into the text: drop them first.
        var s = String(html)
            .replacingOccurrences(of: #"<style[^>]*>.*?</style>"#, with: "", options: [.regularExpression])
            .replacingOccurrences(of: #"\sdata-mw='[^']*'"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\sdata-mw="[^"]*""#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (e, c) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            s = s.replacingOccurrences(of: e, with: c)
        }
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    static func ranges(of needle: String, in s: Substring) -> [Range<Substring.Index>] {
        var out: [Range<Substring.Index>] = []
        var from = s.startIndex
        while let r = s.range(of: needle, range: from..<s.endIndex) {
            out.append(r); from = r.upperBound
        }
        return out
    }
}
