import Foundation

/// Puts the extracted LaTeX back into the formatted HTML, wrapped in elements
/// the KaTeX bootstrap renders in place.
///
/// Runs last in the pipeline. `HeadingAnchorInjector` finds each heading by
/// literal-matching `"<hN>" + heading.plainText + "</hN>"`, and `plainText`
/// comes from the parsed tree — so it holds the *token*. Re-injecting first
/// would leave the HTML holding a `<span>` where `plainText` holds the token,
/// no match, and every heading containing math would silently lose its `id`.
enum MathPostProcessor {
    static func reinject(_ html: String, spans: [MathSpan]) -> String {
        guard !spans.isEmpty else { return html }

        var result = ""
        result.reserveCapacity(html.count + spans.count * 48)
        var cursor = html.startIndex
        var i = html.startIndex

        while i < html.endIndex {
            guard html[i] == MathPlaceholder.open,
                  let decoded = MathPlaceholder.decode(at: i, in: html),
                  decoded.index < spans.count else {
                i = html.index(after: i)
                continue
            }

            let span = spans[decoded.index]
            var start = i
            var end = decoded.end
            var tag = "span"

            // A display formula that owns its paragraph becomes a block, so the
            // `overflow-x` that lets wide equations scroll has something to
            // apply to. A `<span>` inside a `<p>` can't take it.
            if span.isDisplay,
               let openParagraph = html.index(start, offsetBy: -3, limitedBy: html.startIndex),
               html[openParagraph..<start] == "<p>",
               let closeParagraph = html.index(end, offsetBy: 4, limitedBy: html.endIndex),
               html[end..<closeParagraph] == "</p>" {
                start = openParagraph
                end = closeParagraph
                tag = "div"
            }

            let classes = span.isDisplay ? "ml-math ml-math-display" : "ml-math"
            result.append(contentsOf: html[cursor..<start])
            result.append("<\(tag) class=\"\(classes)\">")
            // `HTMLFormatter` escapes nothing, so this is the only thing
            // standing between a formula's `<`, `&` or `"` and the parser.
            result.append(escapeHTML(span.latex))
            result.append("</\(tag)>")

            cursor = end
            i = end
        }

        result.append(contentsOf: html[cursor..<html.endIndex])
        return result
    }
}
