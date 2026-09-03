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
    let controller: WebViewController

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
        // links.js posts clicked hrefs here. WebKit won't navigate a
        // loadHTMLString page to a file outside its base directory — and won't
        // ask the navigation delegate first — so links between documents have
        // to come through this bridge rather than as navigations.
        config.userContentController.add(context.coordinator, name: Coordinator.linkMessageName)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.controller = controller
        controller.webView = webView
        // Enable Web Inspector (Cmd+Opt+I) so devs can debug the rendered page.
        if webView.responds(to: Selector(("setInspectable:"))) {
            webView.perform(Selector(("setInspectable:")), with: true)
        }
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true  // trackpad pinch-to-zoom
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        // Stop UIScrollView from auto-adjusting content insets for the safe
        // area / status bar — that's the SwiftUI parent's job. With
        // .automatic we sometimes saw a small horizontal scroll offset on
        // iPhone that made content look cropped on the left.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let linkMessageName = "marklensLink"

        var lastBody: String = ""
        var lastMermaid: Bool = false
        var lastDark: Bool = false
        weak var controller: WebViewController?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in self.controller?.isReady = true }
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == Coordinator.linkMessageName,
                  let href = message.body as? String,
                  let webView = message.webView,
                  let url = URL(string: href, relativeTo: webView.url)?.absoluteURL
            else { return }
            route(url, from: webView)
        }

        /// Shared by the message bridge and the navigation delegate so both
        /// paths apply the same rules.
        private func route(_ url: URL, from webView: WKWebView) {
            switch LinkRouter.action(for: url,
                                     currentDocumentURL: webView.url,
                                     bundleDirectory: Bundle.main.bundleURL) {
            case .openExternally(let target): LinkOpener.open(target)
            case .openFile(let target): LinkOpener.openFile(target)
            case .allowInPage, .block: break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel); return
            }
            // The template load itself — not a link the user clicked.
            if navigationAction.navigationType == .other,
               LinkRouter.isTemplateLoad(url, bundleDirectory: Bundle.main.bundleURL) {
                decisionHandler(.allow); return
            }

            // Anchors reach us as navigations; everything else normally arrives
            // through the links.js bridge. This still runs as a backstop for
            // navigations the page starts on its own.
            if case .allowInPage = LinkRouter.action(for: url,
                                                     currentDocumentURL: webView.url,
                                                     bundleDirectory: Bundle.main.bundleURL) {
                // An anchor into the page we're already showing: letting this
                // through is what makes a table of contents scroll.
                decisionHandler(.allow); return
            }
            decisionHandler(.cancel)
            route(url, from: webView)
        }
    }
}
