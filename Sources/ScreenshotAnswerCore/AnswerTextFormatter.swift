import Foundation

/// Prepares a generated answer for display.
///
/// Local models routinely emit Markdown emphasis, but SwiftUI only interprets
/// Markdown in string literals, so `Text(answer)` shows the markers verbatim.
/// Parsing here keeps the overlay and the menu-bar panel identical.
///
/// The answer is derived from untrusted OCR and transcript text, so Markdown
/// links and images are discarded rather than rendered as tappable
/// destinations.
public enum AnswerTextFormatter {
    public static func attributed(_ answer: String) -> AttributedString {
        let source = blockMarkersResolved(in: answer)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard var parsed = try? AttributedString(markdown: source, options: options) else {
            return AttributedString(source)
        }
        for run in parsed.runs {
            if run.link != nil {
                parsed[run.range].link = nil
            }
            if run.imageURL != nil {
                parsed[run.range].imageURL = nil
            }
        }
        return parsed
    }

    /// Rewrites the block markers that inline parsing leaves behind.
    ///
    /// `inlineOnlyPreservingWhitespace` keeps every line break, which the
    /// answer card needs, but it only interprets inline markup: a model that
    /// replies with a bullet list leaves its `*` and `#` markers on screen.
    /// SwiftUI `Text` cannot lay out real list structure either, so the markers
    /// become plain bullets instead of presentation intents.
    static func blockMarkersResolved(in answer: String) -> String {
        answer
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap(blockMarkersResolved(inLine:))
            .joined(separator: "\n")
    }

    /// Returns `nil` for a line that should disappear entirely, such as the
    /// `|---|---|` rule under a table header.
    private static func blockMarkersResolved(inLine line: Substring) -> String? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let body = line.dropFirst(indent.count)

        if let row = tableRowResolved(in: body) {
            return row.isEmpty ? nil : "\(indent)\(row)"
        }

        // A list marker is always followed by a space; emphasis never is, so
        // "* item" cannot be confused with "*emphasis*".
        if let marker = body.first, "-*+".contains(marker), body.dropFirst().first == " " {
            let content = body.dropFirst(2).drop { $0 == " " }
            return "\(indent)• \(content)"
        }

        let hashes = body.prefix { $0 == "#" }
        if !hashes.isEmpty, hashes.count <= 6, body.dropFirst(hashes.count).first == " " {
            let content = body.dropFirst(hashes.count + 1).drop { $0 == " " }
            return "\(indent)\(content)"
        }

        // A single stranded pipe is not table structure. OCR reads a printed
        // rule, such as the bar before a menu item, as a leading pipe, and a
        // model that starts a table and gives up leaves a trailing one.
        if body.filter({ $0 == "|" }).count == 1 {
            if body.hasPrefix("|") {
                return "\(indent)\(body.dropFirst().drop { $0 == " " })"
            }
            if body.hasSuffix("|") {
                var trimmed = String(body.dropLast())
                while trimmed.hasSuffix(" ") { trimmed.removeLast() }
                return "\(indent)\(trimmed)"
            }
        }

        return String(line)
    }

    /// Flattens a Markdown table row into one readable line, or an empty string
    /// for the separator rule. Returns `nil` when the line is not a table row.
    private static func tableRowResolved(in body: Substring) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.dropFirst().contains("|") else { return nil }

        let cells = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let isSeparator = cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
        guard !isSeparator else { return "" }

        return cells.filter { !$0.isEmpty }.joined(separator: " — ")
    }
}
