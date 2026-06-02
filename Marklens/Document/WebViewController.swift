import Foundation
import WebKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared bridge between the SwiftUI view tree and the live WKWebView so toolbar
/// and menu actions (export, zoom) can reach it without poking through view layers.
@MainActor
final class WebViewController: ObservableObject {
    weak var webView: WKWebView?
    @Published var isReady: Bool = false

    static let minZoom: CGFloat = 0.5
    static let maxZoom: CGFloat = 5.0
    private let zoomStep: CGFloat = 1.25

    // MARK: Export

    func exportPDF() async throws -> Data {
        guard let webView else { throw ExportError.notReady }

        // On iPhone the visible WebView is ~400 pt wide. The PDF
        // capture rect can be wider, but content is laid out at the
        // viewport width — so a wider rect just gave us 400 pt of
        // content with 200 pt of blank right margin. Widen <body>
        // via CSS so layout reflows to a page-friendly width, then
        // restore once we've grabbed the PDF data.
        let pdfWidth: CGFloat = max(webView.bounds.width, 612)
        let didReflow = await reflowBody(of: webView, to: pdfWidth)

        // Capture the entire scroll height so the PDF is one continuous tall
        // page rather than just the visible viewport. (Multi-page pagination
        // is out of scope for v1 — users can repaginate in Preview.)
        let height = try await contentHeight(of: webView)

        let config = WKPDFConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: pdfWidth, height: height)

        let data = try await webView.pdf(configuration: config)

        if didReflow { await restoreBodyWidth(of: webView) }
        return data
    }

    /// Forces the document layout to a target width so CSS reflows
    /// for PDF capture. iOS WebKit ties many layout decisions to the
    /// viewport (width=device-width), not the body, so we have to pin
    /// html, body, AND article#content explicitly. Returns true if we
    /// actually changed anything.
    private func reflowBody(of webView: WKWebView, to width: CGFloat) async -> Bool {
        guard webView.bounds.width < width - 0.5 else { return false }
        let w = Int(width)
        let js = """
        (function () {
            var html = document.documentElement;
            var body = document.body;
            var article = document.querySelector('article#content');
            body.dataset.pdfPrevHtmlWidth   = html.style.width || '';
            body.dataset.pdfPrevHtmlMinW    = html.style.minWidth || '';
            body.dataset.pdfPrevBodyWidth   = body.style.width || '';
            body.dataset.pdfPrevBodyMinW    = body.style.minWidth || '';
            if (article) {
                body.dataset.pdfPrevArtWidth = article.style.width || '';
                body.dataset.pdfPrevArtMaxW  = article.style.maxWidth || '';
            }
            html.style.width    = '\(w)px';
            html.style.minWidth = '\(w)px';
            body.style.width    = '\(w)px';
            body.style.minWidth = '\(w)px';
            if (article) {
                article.style.width    = '\(w)px';
                article.style.maxWidth = '\(w)px';
            }
            // Force a synchronous layout so the next PDF rect sees the new size.
            return body.offsetWidth;
        })();
        """
        _ = try? await webView.evaluateJavaScript(js)
        return true
    }

    private func restoreBodyWidth(of webView: WKWebView) async {
        let js = """
        (function () {
            var html = document.documentElement;
            var body = document.body;
            var article = document.querySelector('article#content');
            html.style.width    = body.dataset.pdfPrevHtmlWidth || '';
            html.style.minWidth = body.dataset.pdfPrevHtmlMinW  || '';
            body.style.width    = body.dataset.pdfPrevBodyWidth || '';
            body.style.minWidth = body.dataset.pdfPrevBodyMinW  || '';
            if (article) {
                article.style.width    = body.dataset.pdfPrevArtWidth || '';
                article.style.maxWidth = body.dataset.pdfPrevArtMaxW  || '';
            }
            delete body.dataset.pdfPrevHtmlWidth;
            delete body.dataset.pdfPrevHtmlMinW;
            delete body.dataset.pdfPrevBodyWidth;
            delete body.dataset.pdfPrevBodyMinW;
            delete body.dataset.pdfPrevArtWidth;
            delete body.dataset.pdfPrevArtMaxW;
        })();
        """
        _ = try? await webView.evaluateJavaScript(js)
    }

    private func contentHeight(of webView: WKWebView) async throws -> CGFloat {
        let result = try await webView.evaluateJavaScript(
            "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"
        )
        if let n = result as? NSNumber { return CGFloat(n.doubleValue) }
        return webView.bounds.height
    }

    // MARK: Zoom

    func zoomIn() { applyZoom(currentZoom * zoomStep) }
    func zoomOut() { applyZoom(currentZoom / zoomStep) }
    func resetZoom() { applyZoom(1.0) }

    private var currentZoom: CGFloat {
        #if os(macOS)
        webView?.magnification ?? 1.0
        #else
        webView?.scrollView.zoomScale ?? 1.0
        #endif
    }

    private func applyZoom(_ value: CGFloat) {
        let clamped = min(max(value, Self.minZoom), Self.maxZoom)
        #if os(macOS)
        webView?.magnification = clamped
        #else
        webView?.scrollView.setZoomScale(clamped, animated: true)
        #endif
    }

    enum ExportError: LocalizedError {
        case notReady

        var errorDescription: String? {
            switch self {
            case .notReady: return "The document is still loading."
            }
        }
    }
}
