import Foundation

/// Rewrites document-relative `src="…"` / `href="…"` attribute values emitted
/// by the Markdown formatter so they no longer resolve against the WKWebView's
/// `baseURL` — which stays pinned to the bundled `Web/` assets so `styles.css`,
/// `highlight.min.js`, etc. keep loading. Without this, a relative image or
/// link in the document (e.g. `![Diagram](diagram.png)`) would try to load
/// `Web/diagram.png` from the app bundle and silently fail.
///
/// Rewritten references are addressed via a private `marklens-asset:` scheme
/// instead, e.g. `diagram.png` → `marklens-asset:///diagram.png`. The host app
/// registers a `WKURLSchemeHandler` for that scheme that resolves the
/// reference against the folder the open document lives in (see
/// `DocumentAssetResolver`).
public enum RelativeReferenceRewriter {
    /// Scheme used to address files next to the rendered document.
    public static let scheme = "marklens-asset"

    /// Rewrites every rewritable `src`/`href` attribute in `html`.
    public static func rewrite(_ html: String) -> String {
        rewriteAttribute(srcRegex, name: "src", in: rewriteAttribute(hrefRegex, name: "href", in: html))
    }

    private static let hrefRegex = try! NSRegularExpression(pattern: "href=\"([^\"]*)\"")
    private static let srcRegex = try! NSRegularExpression(pattern: "src=\"([^\"]*)\"")

    private static func rewriteAttribute(_ regex: NSRegularExpression, name: String, in html: String) -> String {
        let ns = html as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var result = ""
        var cursor = 0

        for match in regex.matches(in: html, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let full = match.range
            let valueRange = match.range(at: 1)

            result += ns.substring(with: NSRange(location: cursor, length: full.location - cursor))

            let value = ns.substring(with: valueRange)
            if isRewritable(value) {
                result += "\(name)=\"\(scheme):///\(value)\""
            } else {
                result += ns.substring(with: full)
            }
            cursor = full.location + full.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// Whether `value` looks like a bare document-relative reference — i.e.
    /// not an anchor, an absolute path, a protocol-relative URL, a `data:`
    /// URI, or a URL with its own scheme (`https:`, `mailto:`, …).
    static func isRewritable(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value.hasPrefix("#") { return false }
        if value.hasPrefix("//") { return false }
        if value.hasPrefix("/") { return false }
        if value.hasPrefix(scheme + ":") { return false }
        if hasURIScheme(value) { return false }
        return true
    }

    private static func hasURIScheme(_ value: String) -> Bool {
        guard let colonIndex = value.firstIndex(of: ":") else { return false }
        let candidate = value[value.startIndex..<colonIndex]
        guard let first = candidate.first, first.isLetter else { return false }
        return candidate.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
    }
}
