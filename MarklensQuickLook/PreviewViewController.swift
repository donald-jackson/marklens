import Cocoa
import Quartz
import WebKit
import MarklensCore

/// `WKUserContentController` holds its message handlers strongly, and the web
/// view that owns it is a stored property below — registering `self` directly
/// would leak the whole controller. Bounce through a weak box instead.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

final class PreviewViewController: NSViewController, QLPreviewingController,
                                   WKNavigationDelegate, WKScriptMessageHandler {
    private static let linkMessageName = "marklensLink"

    private let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    private var loadContinuation: CheckedContinuation<Void, Error>?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        // See MarkdownWebView: WebKit won't navigate to files outside the
        // template's base directory, so links.js posts them here instead.
        webView.configuration.userContentController.add(WeakScriptMessageHandler(self),
                                                        name: Self.linkMessageName)
        webView.setValue(false, forKey: "drawsBackground")
        container.addSubview(webView)
        self.view = container
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let source = try String(contentsOf: url, encoding: .utf8)
        let rendered = MarkdownRenderer().renderHTML(
            from: source,
            baseDirectory: url.deletingLastPathComponent()
        )
        let isDark = effectiveAppearanceIsDark()
        let html = HTMLTemplate.page(
            body: rendered.body,
            containsMermaid: rendered.containsMermaid,
            dark: isDark
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.loadContinuation = continuation
            DispatchQueue.main.async { [self] in
                webView.loadHTMLString(html, baseURL: WebResources.bundleURL)
            }
        }
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == Self.linkMessageName,
              let href = message.body as? String,
              let url = URL(string: href, relativeTo: webView.url)?.absoluteURL
        else { return }
        route(url)
    }

    /// A Quick Look panel is not a browser — anything that isn't an anchor into
    /// the preview itself goes to the system.
    private func route(_ url: URL) {
        switch LinkRouter.action(for: url,
                                 currentDocumentURL: webView.url,
                                 bundleDirectory: Bundle.main.bundleURL) {
        case .openExternally(let target), .openFile(let target):
            NSWorkspace.shared.open(target)
        case .allowInPage, .block:
            break
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel); return
        }
        // The template load itself — our base URL inside the extension bundle.
        if navigationAction.navigationType == .other,
           LinkRouter.isTemplateLoad(url, bundleDirectory: Bundle.main.bundleURL) {
            decisionHandler(.allow); return
        }

        if case .allowInPage = LinkRouter.action(for: url,
                                                 currentDocumentURL: webView.url,
                                                 bundleDirectory: Bundle.main.bundleURL) {
            // Anchor within the preview — scroll, don't navigate away.
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        route(url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resumeOnce()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resumeOnce(throwing: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resumeOnce(throwing: error)
    }

    private func resumeOnce(throwing error: Error? = nil) {
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }

    private func effectiveAppearanceIsDark() -> Bool {
        let appearance = view.effectiveAppearance
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
