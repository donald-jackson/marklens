import SwiftUI
import WebKit
import MarklensCore

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

struct MarkdownWebView: PlatformViewRepresentable {
    let rendered: RenderedDocument
    let dark: Bool
    let baseURL: URL?

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { update(webView, context: context) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { update(webView, context: context) }
    #endif

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func makeWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Enable Web Inspector (Cmd+Opt+I) so devs can debug the rendered page.
        if webView.responds(to: Selector(("setInspectable:"))) {
            webView.perform(Selector(("setInspectable:")), with: true)
        }
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        #endif
        return webView
    }

    private func update(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        let html = HTMLTemplate.page(
            body: rendered.body,
            containsMermaid: rendered.containsMermaid,
            dark: dark
        )
        // Only reload if the rendered content changed; theme-only changes are pushed via JS.
        if coordinator.lastBody != rendered.body || coordinator.lastMermaid != rendered.containsMermaid {
            webView.loadHTMLString(html, baseURL: baseURL)
            coordinator.lastBody = rendered.body
            coordinator.lastMermaid = rendered.containsMermaid
            coordinator.lastDark = dark
        } else if coordinator.lastDark != dark {
            let theme = dark ? "dark" : "light"
            let hljsHref = dark ? "hljs-dark.css" : "hljs-light.css"
            let js = """
            (function(){
                document.documentElement.dataset.theme = '\(theme)';
                var link = document.getElementById('hljs-theme');
                if (link) link.href = '\(hljsHref)';
                if (window.mermaid) {
                    document.querySelectorAll('.mermaid').forEach(function(el){ el.removeAttribute('data-processed'); });
                    window.mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: '\(theme)' });
                    window.mermaid.run({ querySelector: '.mermaid' });
                }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
            coordinator.lastDark = dark
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastBody: String = ""
        var lastMermaid: Bool = false
        var lastDark: Bool = false

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow); return
            }
            // Allow the initial loadHTMLString navigation (about:blank or file://)
            if navigationAction.navigationType == .other,
               url.scheme == "about" || url.isFileURL {
                decisionHandler(.allow); return
            }
            // Anything user-initiated → open in default browser.
            if navigationAction.navigationType == .linkActivated {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                UIApplication.shared.open(url)
                #endif
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
    }
}
