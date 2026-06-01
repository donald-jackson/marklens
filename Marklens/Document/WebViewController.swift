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

        // Capture the entire scroll height so the PDF is one continuous tall
        // page rather than just the visible viewport. (Multi-page pagination is
        // out of scope for v1 — users can repaginate in Preview if they need to.)
        let height = try await contentHeight(of: webView)
        let width = max(webView.bounds.width, 600)  // floor in case window is tiny

        let config = WKPDFConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: width, height: height)

        return try await webView.pdf(configuration: config)
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
