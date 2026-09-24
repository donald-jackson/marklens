import Foundation

/// GitHub-compatible heading slugs, so a table of contents written for GitHub
/// (`[Getting Started](#getting-started)`) lands on the right heading here too.
public enum HeadingSlug {
    /// Lowercases, drops punctuation, and turns whitespace into hyphens.
    /// Letters and digits keep their Unicode form — GitHub keeps accents.
    public static func slug(for text: String) -> String {
        var slug = ""
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                slug.append(character)
            } else if character.isWhitespace {
                slug.append("-")
            }
            // Everything else (punctuation, symbols) is dropped, as GitHub does.
        }
        return slug.isEmpty ? "section" : slug
    }

    /// Appends `-1`, `-2`, … to repeats so every heading gets a unique target.
    static func unique(_ slug: String, seen: inout [String: Int]) -> String {
        let count = seen[slug, default: 0]
        seen[slug] = count + 1
        return count == 0 ? slug : "\(slug)-\(count)"
    }
}

/// A heading as `HTMLFormatter` will emit it, captured in document order.
struct HeadingRef {
    let level: Int
    /// `HTMLFormatter.visitHeading` flattens headings to their plain text, so
    /// this is exactly what lands between the tags — which lets us find the
    /// tag by literal match instead of parsing HTML.
    let plainText: String
    /// What the `id` is derived from. Normally the same string, but a heading
    /// containing math holds a placeholder token in `plainText`, and slugging
    /// that would give `## Cost $x$` the id `cost-` instead of GitHub's
    /// `cost-x`.
    let slugText: String

    init(level: Int, plainText: String, slugText: String? = nil) {
        self.level = level
        self.plainText = plainText
        self.slugText = slugText ?? plainText
    }
}

/// Adds `id` attributes to the headings `HTMLFormatter` emits without them.
/// Without these, every `#anchor` link in a document is a dead end.
enum HeadingAnchorInjector {
    static func inject(into html: String, headings: [HeadingRef]) -> String {
        guard !headings.isEmpty else { return html }

        var result = ""
        result.reserveCapacity(html.count + headings.count * 24)
        var cursor = html.startIndex
        var seen: [String: Int] = [:]

        for heading in headings {
            let openTag = "<h\(heading.level)>"
            let tag = openTag + heading.plainText + "</h\(heading.level)>"
            let id = HeadingSlug.unique(HeadingSlug.slug(for: heading.slugText), seen: &seen)

            guard let range = html.range(of: tag, range: cursor..<html.endIndex) else {
                // Shouldn't happen, but never drop content if it does — the
                // slug counter has already advanced, keeping later ids stable.
                continue
            }
            result.append(contentsOf: html[cursor..<range.lowerBound])
            result.append("<h\(heading.level) id=\"\(escapeHTML(id))\">")
            result.append(contentsOf: html[html.index(range.lowerBound, offsetBy: openTag.count)..<range.upperBound])
            cursor = range.upperBound
        }

        result.append(contentsOf: html[cursor..<html.endIndex])
        return result
    }
}
