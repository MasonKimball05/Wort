import Foundation

/// Pasted German text, split into what the reader shows: paragraphs of words.
public enum ReadingText {
    /// Paragraphs, each with its whitespace collapsed to single spaces, so a word
    /// never gets glued to the next across a line break. A line break inside a
    /// paragraph (copied text often wraps hard) joins up; a blank line splits.
    public static func paragraphs(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n")
            .split { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { lines in
                lines.joined(separator: " ")
                    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            .filter { !$0.isEmpty }
    }

    /// The first few words, for a text saved without a title.
    public static func title(for text: String, words: Int = 6) -> String {
        let all = text.split(whereSeparator: \.isWhitespace)
        let head = all.prefix(words).joined(separator: " ")
        return all.count > words ? head + "…" : head
    }

    /// Lowercased forms of the words you already have (lemma and plural), for
    /// marking them in a text. Surface forms only: "Bücher" matches das Buch
    /// through its plural, but an inflected verb like "ging" won't match gehen.
    public static func knownForms(_ words: [(lemma: String, plural: String?)]) -> Set<String> {
        var set = Set<String>()
        for w in words {
            set.insert(w.lemma.lowercased())
            if let p = w.plural, !p.isEmpty { set.insert(p.lowercased()) }
        }
        return set
    }

    /// Whether a token from the text ("Buch," "Bücher.") is one of those forms.
    public static func isKnown(_ token: String, in known: Set<String>) -> Bool {
        let w = ParsedInput(token).word.lowercased()
        return !w.isEmpty && known.contains(w)
    }

    /// Abbreviations whose dot doesn't end a sentence.
    static let abbreviations: Set<String> = [
        "z.", "b.", "z.b.", "d.h.", "u.a.", "bzw.", "usw.", "ca.", "etc.", "vgl.", "dr.", "prof.", "nr.",
        "s.", "st.", "hr.", "fr.", "evtl.", "ggf.", "inkl.", "zzgl.", "bspw.", "sog.", "u.", "a.", "o.ä.", "mio.", "mrd.",
    ]

    /// The sentence the word at `index` (counting words split on spaces) sits in,
    /// to keep as the example when the word is added. "z. B.", "Dr." and dates
    /// like "am 3. Mai" don't end a sentence.
    public static func sentence(around index: Int, in paragraph: String) -> String {
        let tokens = paragraph.split(separator: " ").map(String.init)
        guard tokens.indices.contains(index) else { return paragraph }
        func ends(_ i: Int) -> Bool {
            let t = tokens[i].trimmingCharacters(in: CharacterSet(charactersIn: "\"“”„»«)’'"))
            guard let last = t.last, ".!?".contains(last) else { return false }
            if last != "." { return true }
            if abbreviations.contains(t.lowercased()) { return false }
            // An ordinal or date ("3.", "19."): not an end.
            if t.dropLast().allSatisfy(\.isNumber) { return false }
            // A single capital letter ("Johann S. Bach"): an initial.
            if t.count == 2, t.first?.isUppercase == true { return false }
            return true
        }
        var start = index
        while start > 0, !ends(start - 1) { start -= 1 }
        var end = index
        while end < tokens.count - 1, !ends(end) { end += 1 }
        return tokens[start...end].joined(separator: " ")
    }
}
