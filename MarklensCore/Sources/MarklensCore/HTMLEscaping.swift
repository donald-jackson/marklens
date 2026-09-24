import Foundation
import Markdown

/// Escapes text for use in HTML. `&` must go first or every ampersand ends up
/// double-escaped — which is exactly the `\begin{matrix} a & b \end{matrix}`
/// case. Used by `HTMLTextEscaper`, `LinkSanitizer` and `MathPostProcessor`.
func escapeHTML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

/// Reverses `escapeHTML`. Used both to read mermaid source back out of the
/// formatted HTML and to recover literal heading text for slugging.
func unescapeHTML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&amp;", with: "&")
}

/// Escapes the literal text and code that `HTMLFormatter` writes verbatim.
///
/// `HTMLFormatter` escapes nothing. `Text` and code content are emitted exactly
/// as cmark handed them over, so `` `<style>` `` — an inline code span whose
/// code is `<style>` — reaches the page as `<code><style></code>`. The HTML
/// parser reads that as a live `<style>` start tag, switches to raw-text mode,
/// and consumes the rest of the document: the page looks truncated at the code
/// span. Fenced code as ordinary as `if a < b` has the same problem.
///
/// Escaping the leaves of the tree before formatting keeps literals literal.
/// Raw HTML is *not* touched: `<div>`, `<span>` and friends are legal markdown
/// and are meant to render as markup.
///
/// The rewritten strings feed two later stages, so the escaping has to be
/// invertible: `HeadingAnchorInjector` matches headings by the exact text the
/// formatter emits, and `MathPostProcessor` replaces our placeholder tokens
/// with `escapeHTML(span.raw)`.
struct HTMLTextEscaper: MarkupRewriter {
    mutating func visitText(_ text: Text) -> Markup? {
        var text = text
        text.string = escapeHTML(text.string)
        return text
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> Markup? {
        var inlineCode = inlineCode
        inlineCode.code = escapeHTML(inlineCode.code)
        return inlineCode
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> Markup? {
        var codeBlock = codeBlock
        codeBlock.code = escapeHTML(codeBlock.code)
        return codeBlock
    }

    /// `HTMLFormatter.visitImage` interpolates the source and title into
    /// double-quoted attributes without escaping them, so a title containing
    /// `"` ends the attribute early and spills the rest into the tag.
    ///
    /// Its children are not visited: `HTMLFormatter` drops them (it emits no
    /// `alt`), so there is no text to escape.
    mutating func visitImage(_ image: Image) -> Markup? {
        var image = image
        if let source = image.source { image.source = escapeHTML(source) }
        if let title = image.title { image.title = escapeHTML(title) }
        return image
    }
}
