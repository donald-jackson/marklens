import Foundation

public struct HTMLTemplate {
    public static func page(body: String, containsMermaid: Bool, dark: Bool = false, title: String = "") -> String {
        let theme = dark ? "dark" : "light"
        let hljsTheme = dark ? "hljs-dark.css" : "hljs-light.css"
        let escapedTitle = escapeForHTML(title)

        let mermaidTag = containsMermaid ? "<script src=\"mermaid.min.js\" defer></script>" : ""
        let mermaidBootstrap = containsMermaid ? Self.mermaidBootstrap : ""

        return """
        <!DOCTYPE html>
        <html lang="en" data-theme="\(theme)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=5, user-scalable=yes">
        <title>\(escapedTitle)</title>
        <link rel="stylesheet" href="styles.css">
        <link rel="stylesheet" id="hljs-theme" href="\(hljsTheme)">
        <script src="highlight.min.js" defer></script>
        <script src="find.js" defer></script>
        \(mermaidTag)
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
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ready) {
                window.webkit.messageHandlers.ready.postMessage('ready');
            }
        });
        </script>
        </body>
        </html>
        """
    }

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
