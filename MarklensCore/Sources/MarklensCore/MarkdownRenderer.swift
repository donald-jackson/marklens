import Foundation
import Markdown

public struct MarkdownRenderer {
    public init() {}

    /// - Parameter baseDirectory: the folder the markdown file lives in, used to
    ///   resolve document-relative links. Pass `nil` when there is no file on
    ///   disk; relative links are then left untouched.
    public func renderHTML(from source: String, baseDirectory: URL? = nil) -> RenderedDocument {
        var document = Document(parsing: source)

        var sanitizer = LinkSanitizer(baseDirectory: baseDirectory)
        if let rewritten = sanitizer.visit(document) as? Document {
            document = rewritten
        }

        var detector = MermaidDetector()
        detector.visit(document)

        var headings = HeadingCollector()
        headings.visit(document)

        let rawHTML = HTMLFormatter.format(document, options: [.parseAsides])
        // Anchors first: at this point mermaid bodies are still HTML-escaped, so
        // a `<h2>` inside a diagram can't be mistaken for a real heading.
        let anchored = HeadingAnchorInjector.inject(into: rawHTML, headings: headings.headings)
        let body = MermaidPostProcessor.transform(anchored)

        return RenderedDocument(body: body, containsMermaid: detector.found)
    }
}

public struct RenderedDocument {
    public let body: String
    public let containsMermaid: Bool
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

private func unescapeHTML(_ s: String) -> String {
    s
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&amp;", with: "&")
}
