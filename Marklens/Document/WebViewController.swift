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

    /// Hands the document to the system print panel.
    ///
    /// This is the same WebKit print engine `PDFExporter` drives, but with
    /// none of the preparation: no measured page breaks, no scaling of wide
    /// formulas. Fewer moving parts, and the reader gets paper size, margins,
    /// scale-to-fit and page range — plus "Save as PDF" — from the panel
    /// itself. When an export comes out wrong, this is the path that says
    /// whether the fault is ours or WebKit's.
    func printDocument() {
        guard let webView else { return }

        #if os(macOS)
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        // A4 as the starting point, to match Export PDF. The panel can change it.
        info.paperSize = PDFExporter.pageSize
        info.topMargin = PDFExporter.margin
        info.bottomMargin = PDFExporter.margin
        info.leftMargin = PDFExporter.margin
        info.rightMargin = PDFExporter.margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.view?.frame = CGRect(origin: .zero, size: PDFExporter.pageSize)

        if let window = webView.window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
        #else
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = webView.title ?? "Document"

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printFormatter = webView.viewPrintFormatter()
        controller.present(animated: true, completionHandler: nil)
        #endif
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
