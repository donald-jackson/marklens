import Cocoa
import Quartz
import WebKit
import MarklensCore

final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    private var loadContinuation: CheckedContinuation<Void, Error>?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        container.addSubview(webView)
        self.view = container
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let source = try String(contentsOf: url, encoding: .utf8)
        let rendered = MarkdownRenderer().renderHTML(from: source)
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

    // MARK: WKNavigationDelegate

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
