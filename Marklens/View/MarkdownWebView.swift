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
    let fileURL: URL?
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

        // Serves document-relative `<img src>`/`<a href>` (rewritten to
        // `marklens-asset:` by MarklensCore) from the folder the document
        // lives in, instead of the bundled `Web/` dir that `baseURL` points at.
        let assetHandler = AssetSchemeHandler()
        assetHandler.documentFolder = fileURL?.deletingLastPathComponent()
        config.setURLSchemeHandler(assetHandler, forURLScheme: AssetSchemeHandler.scheme)
        context.coordinator.assetHandler = assetHandler

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
        coordinator.assetHandler?.documentFolder = fileURL?.deletingLastPathComponent()
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
        weak var controller: WebViewController?
        var assetHandler: AssetSchemeHandler?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in self.controller?.isReady = true }
        }

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
            // A relative link in the document (rewritten to `marklens-asset:`
            // by MarklensCore) — resolve it against the document's folder and
            // open the target file (e.g. a sibling .md) instead of no-oping.
            if navigationAction.navigationType == .linkActivated, url.scheme == AssetSchemeHandler.scheme {
                openRelativeLink(url)
                decisionHandler(.cancel); return
            }
            // Anything else user-initiated → open in default browser.
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

        private func openRelativeLink(_ url: URL) {
            guard let folder = assetHandler?.documentFolder,
                  let reference = DocumentAssetResolver.relativeReference(from: url),
                  let target = DocumentAssetResolver.resolve(reference, in: folder)
            else { return }
            #if os(macOS)
            NSWorkspace.shared.open(target)
            #else
            // `UIApplication.shared.open` on a bare file:// URL only succeeds
            // if some installed app claims the target's UTI; there's no
            // iOS equivalent of "reveal/open with default app" for a document
            // living outside our own sandbox container. Best effort — most
            // relative links point at another Markdown file we can't yet
            // hand off to ourselves without a document-browser integration.
            UIApplication.shared.open(target, options: [:]) { success in
                guard !success else { return }
                Task { @MainActor in
                    IOSPresenter.alert(title: "Couldn't Open Link", message: "This link couldn't be opened.")
                }
            }
            #endif
        }
    }
}
