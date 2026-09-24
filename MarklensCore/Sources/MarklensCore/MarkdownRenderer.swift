import Foundation
import Markdown

public struct MarkdownRenderer {
    public init() {}

    /// - Parameter baseDirectory: the folder the markdown file lives in, used to
    ///   resolve document-relative links. Pass `nil` when there is no file on
    ///   disk; relative links are then left untouched.
    public func renderHTML(from source: String, baseDirectory: URL? = nil) -> RenderedDocument {
        // Math comes out before cmark ever sees it: CommonMark eats `\_`, `\*`
        // and `\\` as escapes, turns `_x_` into `<em>`, and (smart punctuation
        // is on) rewrites `--` and `"`. There is no recovering a formula from
        // the DOM afterwards.
        let math = MathExtractor.extract(from: source)
        var document = Document(parsing: math.source)

        var sanitizer = LinkSanitizer(baseDirectory: baseDirectory)
        if let rewritten = sanitizer.visit(document) as? Document {
            document = rewritten
        }

        // `HTMLFormatter` escapes nothing, so literal text and code have to be
        // escaped before it sees them — otherwise a code span holding `<style>`
        // opens a raw-text element and the browser swallows the rest of the
        // page. Raw HTML is deliberately left alone.
        var escaper = HTMLTextEscaper()
        if let rewritten = escaper.visit(document) as? Document {
            document = rewritten
        }

        var detector = MermaidDetector()
        detector.visit(document)

        var headings = HeadingCollector()
        headings.visit(document)
        // `plainText` now holds the escaped HTML the formatter will emit, which
        // is what the anchor injector matches on. Slugs are read from the
        // literal text, though: slugging the escaped text would give
        // `Tom & Jerry` the id `tom-amp-jerry` instead of GitHub's
        // `tom--jerry`. Restoring the LaTeX first keeps a heading with math
        // slugging just as GitHub would.
        let headingRefs = headings.headings.map { heading -> HeadingRef in
            let restored = math.containsMath
                ? math.placeholder.restoring(heading.plainText, spans: math.spans)
                : heading.plainText
            return HeadingRef(level: heading.level,
                              plainText: heading.plainText,
                              slugText: unescapeHTML(restored))
        }

        let rawHTML = HTMLFormatter.format(document, options: [.parseAsides])
        // Anchors first: the injector matches each heading by the literal text
        // the escapers left in the tree, so it has to run before anything
        // rewrites that text. (`HTMLFormatter` itself escapes nothing, so every
        // raw-HTML producer below still owns its own escaping.)
        let anchored = HeadingAnchorInjector.inject(into: rawHTML, headings: headingRefs)
        let mermaid = MermaidPostProcessor.transform(anchored)
        let body = MathPostProcessor.reinject(mermaid,
                                              spans: math.spans,
                                              placeholder: math.placeholder)

        return RenderedDocument(body: body,
                                containsMermaid: detector.found,
                                containsMath: math.containsMath)
    }
}

public struct RenderedDocument {
    public let body: String
    public let containsMermaid: Bool
    public let containsMath: Bool
}

/// Collects headings in document order so we can give each one an `id`.
private struct HeadingCollector: MarkupWalker {
    var headings: [HeadingRef] = []

    mutating func visitHeading(_ heading: Heading) {
        headings.append(HeadingRef(level: heading.level, plainText: heading.plainText))
    }
}

private struct MermaidDetector: MarkupWalker {
    var found = false

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        if codeBlock.language?.lowercased() == "mermaid" {
            found = true
        }
    }
}

/// Replaces `<pre><code class="language-mermaid">…</code></pre>` blocks emitted by
/// `HTMLFormatter` with raw `<div class="mermaid">…</div>` blocks that mermaid.js can render.
enum MermaidPostProcessor {
    static func transform(_ html: String) -> String {
        var result = ""
        result.reserveCapacity(html.count)
        var cursor = html.startIndex

        let openTag = "<pre><code class=\"language-mermaid\">"
        let closeTag = "</code></pre>"

        while let openRange = html.range(of: openTag, range: cursor..<html.endIndex) {
            result.append(contentsOf: html[cursor..<openRange.lowerBound])
            guard let closeRange = html.range(of: closeTag, range: openRange.upperBound..<html.endIndex) else {
                // Malformed — bail out, keep remainder as-is.
                result.append(contentsOf: html[cursor..<html.endIndex])
                return result
            }
            let escapedDiagram = String(html[openRange.upperBound..<closeRange.lowerBound])
            let rawDiagram = unescapeHTML(escapedDiagram)
            result.append("<div class=\"mermaid\">")
            result.append(rawDiagram)
            result.append("</div>")
            cursor = closeRange.upperBound
        }
        result.append(contentsOf: html[cursor..<html.endIndex])
        return result
    }
}
