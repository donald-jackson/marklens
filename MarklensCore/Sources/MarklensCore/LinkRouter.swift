import Foundation
import Markdown

/// What the web view should do with a clicked link.
public enum LinkAction: Equatable {
    /// An anchor into the page we're already showing — let WebKit scroll to it.
    case allowInPage
    /// Hand to the system browser / mail client.
    case openExternally(URL)
    /// Hand to the system so it opens in whichever app owns the file type.
    case openFile(URL)
    /// Refuse: an unsupported scheme, or a path inside our own app bundle.
    case block
}

public enum LinkRouter {
    /// Schemes we're willing to hand to the system. Deliberately narrow:
    /// a `.md` file is untrusted input, and a link in one must not be able to
    /// launch arbitrary URL handlers.
    public static let externalSchemes: Set<String> = ["http", "https", "mailto"]

    private static let dangerousSchemes: Set<String> = ["javascript", "data", "vbscript", "blob"]

    /// Decides how to handle a navigation the web view is about to perform.
    ///
    /// - Parameters:
    ///   - url: the URL WebKit resolved for the click.
    ///   - currentDocumentURL: the web view's own URL (our HTML template's base).
    ///   - bundleDirectory: the app/extension bundle. Anything resolving inside
    ///     it is a relative link we couldn't resolve (no document directory), so
    ///     it points at our own resources rather than the user's file.
    public static func action(for url: URL,
                              currentDocumentURL: URL?,
                              bundleDirectory: URL?) -> LinkAction {
        // In-page anchor: same document, only the fragment differs. Letting
        // this through is what makes tables of contents work.
        if url.fragment != nil, isSameDocument(url, as: currentDocumentURL) {
            return .allowInPage
        }

        guard let scheme = url.scheme?.lowercased(), !dangerousSchemes.contains(scheme) else {
            return .block
        }
        if externalSchemes.contains(scheme) {
            return .openExternally(url)
        }
        guard scheme == "file" else { return .block }

        let file = url.standardizedFileURL
        if let bundleDirectory, isInside(file, bundleDirectory) { return .block }
        // The fragment is meaningless to LaunchServices — drop it.
        return .openFile(strippingFragment(file))
    }

    /// True for the navigation `loadHTMLString` performs to display the
    /// template itself — the base URL inside our bundle, or `about:blank` when
    /// there isn't one. Everything else is a link worth routing.
    public static func isTemplateLoad(_ url: URL, bundleDirectory: URL?) -> Bool {
        if url.scheme == "about" { return true }
        guard url.isFileURL, let bundleDirectory else { return false }
        return isInside(url.standardizedFileURL, bundleDirectory)
    }

    /// True when two URLs name the same document and differ only by fragment.
    static func isSameDocument(_ url: URL, as other: URL?) -> Bool {
        guard let other else { return false }
        return strippingFragment(url) == strippingFragment(other)
    }

    private static func strippingFragment(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        guard components.fragment != nil else { return url }
        components.fragment = nil
        return components.url ?? url
    }

    static func isInside(_ url: URL, _ directory: URL) -> Bool {
        let base = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().path
        return path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }
}

// MARK: - Rewriting destinations at render time

/// Makes link destinations safe and absolute before they reach the HTML.
///
/// Two jobs:
/// 1. Resolve document-relative destinations (`./other.md`) against the folder
///    the markdown file lives in. The page's base URL is our bundled `Web/`
///    directory — it has to be, that's where `styles.css` lives — so without
///    this every relative link would point inside the app bundle.
/// 2. Strip script-bearing schemes and escape the destination for use in an
///    HTML attribute, neither of which `HTMLFormatter` does for us.
struct LinkSanitizer: MarkupRewriter {
    let baseDirectory: URL?

    mutating func visitLink(_ link: Link) -> (any Markup)? {
        var link = link
        guard let destination = link.destination, !destination.isEmpty else {
            return defaultVisit(link)
        }
        link.destination = LinkSanitizer.rewrite(destination, baseDirectory: baseDirectory)
        return defaultVisit(link)
    }

    /// Returns the destination to emit, or `nil` to drop the `href` entirely.
    static func rewrite(_ destination: String, baseDirectory: URL?) -> String? {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let scheme = scheme(of: trimmed) {
            // Absolute URL. Keep it unless it can execute.
            let dangerous: Set<String> = ["javascript", "data", "vbscript"]
            return dangerous.contains(scheme) ? nil : escapeAttribute(trimmed)
        }

        // Fragment-only links stay relative — they're anchors into this page.
        if trimmed.hasPrefix("#") { return escapeAttribute(trimmed) }

        // Document-relative. Without a document directory (an unsaved buffer)
        // there's nothing to resolve against, so leave it be.
        guard let baseDirectory else { return escapeAttribute(trimmed) }

        let (path, fragment) = splitFragment(trimmed)
        guard !path.isEmpty else { return escapeAttribute(trimmed) }

        // Markdown destinations may already be percent-encoded; decode first so
        // `URL(fileURLWithPath:)` doesn't double-encode `%20` into `%2520`.
        let decoded = path.removingPercentEncoding ?? path
        let resolved = URL(fileURLWithPath: decoded, relativeTo: baseDirectory).standardizedFileURL
        let absolute = fragment.map { "\(resolved.absoluteString)#\($0)" } ?? resolved.absoluteString
        return escapeAttribute(absolute)
    }

    /// RFC 3986 scheme prefix, lowercased — `URL(string:)` rejects destinations
    /// with spaces, so we can't rely on it to tell relative from absolute.
    private static func scheme(of destination: String) -> String? {
        guard let colon = destination.firstIndex(of: ":") else { return nil }
        let candidate = destination[destination.startIndex..<colon]
        guard let first = candidate.first, first.isLetter else { return nil }
        guard candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else { return nil }
        return candidate.lowercased()
    }

    private static func splitFragment(_ destination: String) -> (path: String, fragment: String?) {
        guard let hash = destination.firstIndex(of: "#") else { return (destination, nil) }
        return (String(destination[destination.startIndex..<hash]),
                String(destination[destination.index(after: hash)...]))
    }
}
