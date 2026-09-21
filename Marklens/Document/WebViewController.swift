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

        // Strip any in-page find highlights so they don't bake into the PDF.
        _ = try? await webView.evaluateJavaScript(
            "window.__marklensFind && window.__marklensFind.clear();"
        )

        return try await PDFExporter.export(webView)
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
