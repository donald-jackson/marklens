import Foundation
import Markdown

public struct MarkdownRenderer {
    public init() {}

    public func renderHTML(from source: String) -> RenderedDocument {
        let document = Document(parsing: source)

        var detector = MermaidDetector()
        detector.visit(document)

        let rawHTML = HTMLFormatter.format(document, options: [.parseAsides])
        let mermaidBody = MermaidPostProcessor.transform(rawHTML)
        let body = RelativeReferenceRewriter.rewrite(mermaidBody)

        return RenderedDocument(body: body, containsMermaid: detector.found)
    }
}

public struct RenderedDocument {
    public let body: String
    public let containsMermaid: Bool
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
