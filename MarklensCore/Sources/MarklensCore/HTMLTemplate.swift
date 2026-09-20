import Foundation

public struct HTMLTemplate {
    public static func page(body: String,
                            containsMermaid: Bool,
                            containsMath: Bool = false,
                            dark: Bool = false,
                            title: String = "") -> String {
        let theme = dark ? "dark" : "light"
        let hljsTheme = dark ? "hljs-dark.css" : "hljs-light.css"
        let escapedTitle = escapeForHTML(title)

        let mermaidTag = containsMermaid ? "<script src=\"mermaid.min.js\" defer></script>" : ""
        let mermaidBootstrap = containsMermaid ? Self.mermaidBootstrap : ""

        // KaTeX's stylesheet goes above ours so our overrides win on document
        // order rather than on specificity.
        let katexStyle = containsMath ? "<link rel=\"stylesheet\" href=\"katex.min.css\">" : ""
        let katexTag = containsMath ? "<script src=\"katex.min.js\" defer></script>" : ""
        let katexBootstrap = containsMath ? Self.katexBootstrap : ""

        return """
        <!DOCTYPE html>
        <html lang="en" data-theme="\(theme)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=5, user-scalable=yes">
        <title>\(escapedTitle)</title>
        \(katexStyle)
        <link rel="stylesheet" href="styles.css">
        <link rel="stylesheet" id="hljs-theme" href="\(hljsTheme)">
        <script src="highlight.min.js" defer></script>
        <script src="find.js" defer></script>
        <script src="links.js" defer></script>
        \(mermaidTag)
        \(katexTag)
        </head>
        <body>
        <article id="content">
        \(body)
        </article>
        <script>
        window.addEventListener('DOMContentLoaded', function () {
            if (window.hljs) {
                document.querySelectorAll('pre code').forEach(function (el) { window.hljs.highlightElement(el); });
            }
            \(mermaidBootstrap)
            \(katexBootstrap)
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ready) {
                window.webkit.messageHandlers.ready.postMessage('ready');
            }
        });
        </script>
        </body>
        </html>
        """
    }

    /// Renders each extracted formula in place.
    ///
    /// Deliberately not KaTeX's `auto-render`: that re-detects delimiters in
    /// the DOM, where the LaTeX has already been through CommonMark — the very
    /// problem `MathExtractor` exists to avoid. Here `displayMode` comes from
    /// the source delimiters, which is authoritative.
    private static let katexBootstrap = """
    if (window.katex) {
        document.querySelectorAll('.ml-math').forEach(function (el) {
            var tex = el.textContent;
            // katex.render replaces the element's children, so the source has
            // to be stashed before it does.
            el.dataset.tex = tex;
            try {
                window.katex.render(tex, el, {
                    displayMode: el.classList.contains('ml-math-display'),
                    throwOnError: false,
                    // A red that stays legible on both themes. It has to be
                    // decided here: KaTeX writes it as an inline style, which
                    // no stylesheet can override, and math is deliberately not
                    // re-rendered when the theme flips.
                    errorColor: '#e5484d',
                    strict: 'ignore'
                });
            } catch (err) {
                console.error('katex:', err);
                el.textContent = tex;
            }
        });
    }
    """

    private static let mermaidBootstrap = """
    if (window.mermaid) {
        try {
            var isDark = document.documentElement.dataset.theme === 'dark';
            window.mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: isDark ? 'dark' : 'default' });
            window.mermaid.run({ querySelector: '.mermaid' });
        } catch (err) { console.error('mermaid:', err); }
    }
    """
}

private func escapeForHTML(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
}
