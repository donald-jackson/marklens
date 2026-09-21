import Foundation
import PDFKit
import WebKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Paginated PDF export.
///
/// `WKPDFConfiguration` cannot do this: it renders one page the size of the
/// rect it is given, which is why export used to produce a single sheet as
/// tall as the whole document. WebKit's *print* path paginates properly and,
/// more importantly, honours CSS paged-media rules — so where the breaks land
/// is decided by the `@media print` block in styles.css rather than by
/// arithmetic here.
enum PDFExporter {
    /// A4 at 72 dpi. 210 × 297 mm.
    static let pageSize = CGSize(width: 595.276, height: 841.89)
    /// ~17 mm on every side.
    static let margin: CGFloat = 48

    static var contentWidth: CGFloat { pageSize.width - margin * 2 }
    static var contentHeight: CGFloat { pageSize.height - margin * 2 }

    /// CSS calls a pixel 1/96 inch and PDF calls a point 1/72, and WebKit does
    /// apply that ratio when printing: the imageable box is 499pt on paper but
    /// 666 CSS px to the layout. Every measurement taken in JavaScript is in
    /// CSS px, so it has to be compared against these, not against the point
    /// sizes. (Confirmed from the output: 16px body text sets at 12pt.)
    private static let pxPerPoint: CGFloat = 96.0 / 72.0
    static var contentWidthPx: CGFloat { contentWidth * pxPerPoint }
    static var contentHeightPx: CGFloat { contentHeight * pxPerPoint }

    enum Failure: LocalizedError {
        case printFailed

        var errorDescription: String? {
            "Could not lay the document out into pages."
        }
    }

    /// Paginates the web view's current document into A4 pages.
    @MainActor
    static func export(_ webView: WKWebView) async throws -> Data {
        do {
            // A failed preparation means no forced breaks and no scaled math,
            // so the export would quietly be the wrong shape. Better to say so
            // than to hand back a PDF that looks finished.
            try await prepare(webView)
            let data = try await paginate(webView)
            await restore(webView)
            return data
        } catch {
            // `defer` can't await, and leaving the document marked up would be
            // worse than the failure itself.
            await restore(webView)
            throw error
        }
    }

    /// Lays the document out at page width, shrinks anything too wide, and
    /// marks the blocks that should start a new page.
    ///
    /// The marking is necessary because WebKit implements only half of the
    /// paged-media break rules: `break-inside: avoid` works, `break-after:
    /// avoid` does not. Rather than fight that, this measures the laid-out
    /// document and inserts *forced* breaks, which are honoured reliably.
    @MainActor
    private static func prepare(_ webView: WKWebView) async throws {
        let js = """
            // KaTeX's faces load asynchronously. Measuring before they arrive
            // takes fallback metrics, and the print pass then uses the real
            // ones — so the scaling and the page breaks would describe a
            // layout that is never printed.
            await document.fonts.ready;

            var widthPx  = \(Int(contentWidthPx.rounded()));
            var heightPx = \(Int(contentHeightPx.rounded()));

            var article = document.querySelector('article#content');
            if (!article) return 0;

            // Measure a hidden copy laid out at the printed page's width.
            // Pinning the real article instead would work, but the user would
            // watch the document snap to page width and back during an export.
            // The clone has the same structure, so an index into its children
            // is an index into the real ones.
            var probe = article.cloneNode(true);
            probe.removeAttribute('id');
            probe.setAttribute('aria-hidden', 'true');
            probe.style.cssText = 'position:absolute!important;left:-10000px!important;'
                + 'top:0!important;visibility:hidden!important;width:' + widthPx + 'px!important;'
                + 'max-width:' + widthPx + 'px!important;padding:0!important;margin:0!important;';
            document.body.appendChild(probe);

            // The copy renders under screen CSS, but the export runs under
            // print CSS, so the layout-affecting print rules have to be
            // mirrored here or every measurement describes the wrong document.
            // Code wrapping is the one that matters: unwrapped it measures far
            // shorter than it prints, and the page count comes out wrong.
            // Keep in step with the `@media print` block in styles.css.
            probe.querySelectorAll('pre').forEach(function (el) {
                el.style.overflow = 'visible';
                el.style.whiteSpace = 'pre-wrap';
                el.style.wordWrap = 'break-word';
            });
            probe.querySelectorAll('.ml-math-display').forEach(function (el) {
                el.style.overflow = 'visible';
            });

            var blocks = Array.prototype.slice.call(article.children);
            var probes = Array.prototype.slice.call(probe.children);
            if (!blocks.length || probes.length !== blocks.length) {
                document.body.removeChild(probe);
                return 0;
            }

            // Blocks that read as a unit and should not be split if they can
            // fit on a page whole.
            var ATOMIC = 'pre, table, blockquote, aside, figure, img, .mermaid, .ml-math-display';
            // How much room a heading needs beneath it to be worth keeping on
            // this page — roughly three lines of body text.
            var MIN_AFTER_HEADING = 78;
            // Absorbs sub-pixel drift between this layout and the print one, so
            // a block that only just fits doesn't spill and cause a stray page.
            var SLACK = 8;
            var usable = heightPx - SLACK;

            function fitsWhole(el, height) {
                return el.matches(ATOMIC) && height <= usable;
            }

            // Over-wide math can't be talked down by CSS — KaTeX gives a
            // formula an intrinsic width with white-space: nowrap — so it has
            // to be measured and scaled.
            //
            // Scaling is done with font-size, not `zoom`. KaTeX sizes
            // everything in em, so a smaller font size reflows the formula
            // through ordinary layout and the box height follows. `zoom` is
            // non-standard, and in a paginated layout it puts the formula in
            // the wrong place — on top of the paragraph above it.
            var targets = article.querySelectorAll('.ml-math-display');
            probe.querySelectorAll('.ml-math-display').forEach(function (el, i) {
                var inner = el.firstElementChild || el;
                var w = inner.scrollWidth || el.scrollWidth;
                if (!w || w <= widthPx) return;
                var target = targets[i];
                if (!target) return;
                // A little under the limit: scaling is proportional but text
                // shaping is not perfectly linear, so leave a hair of room.
                var scale = (widthPx / w) * 0.99;
                target.dataset.printPrevFontSize = target.style.fontSize || '';
                el.style.fontSize = target.style.fontSize = (scale * 100).toFixed(2) + '%';
            });
            probe.offsetHeight;

            var tops = probes.map(function (el) { return el.offsetTop; });
            var contentEnd = probe.offsetTop + probe.offsetHeight;
            function advance(i) {
                // Gap to the next block's top, so collapsed margins are counted
                // exactly once rather than guessed at.
                return (i + 1 < probes.length ? tops[i + 1] : contentEnd) - tops[i];
            }

            var marked = 0;
            var y = 0;   // how far down the current page we are
            for (var i = 0; i < blocks.length; i++) {
                var el = probes[i];
                var height = el.offsetHeight;
                var isHeading = /^H[1-6]$/.test(el.tagName);
                var breakHere = false;

                if (y > 0) {
                    if ((isHeading || fitsWhole(el, height)) && y + height > usable) {
                        breakHere = true;
                    } else if (isHeading) {
                        // Checking that the heading itself fits is not enough:
                        // if what follows it starts on the next page anyway,
                        // the heading is left stranded at the foot of this one.
                        // So the heading travels with its content.
                        var next = probes[i + 1];
                        if (next) {
                            var room = usable - (y + advance(i));
                            var nextHeight = next.offsetHeight;
                            breakHere = fitsWhole(next, nextHeight)
                                ? nextHeight > room
                                : room < MIN_AFTER_HEADING;
                        }
                    }
                }

                if (breakHere) {
                    blocks[i].classList.add('ml-page-break');
                    marked++;
                    y = 0;
                }

                y += advance(i);
                // A block taller than a page spills onto the next one.
                while (y >= usable) { y -= usable; }
            }

            document.body.removeChild(probe);
            return marked;
        """
        _ = try await webView.callAsyncJavaScript(js, in: nil, in: .page)
    }

    /// Puts the document back exactly as the reader left it.
    @MainActor
    private static func restore(_ webView: WKWebView) async {
        let js = """
        (function () {
            document.querySelectorAll('.ml-math-display').forEach(function (el) {
                if (el.dataset.printPrevFontSize === undefined) return;
                el.style.fontSize = el.dataset.printPrevFontSize;
                delete el.dataset.printPrevFontSize;
            });
            document.querySelectorAll('.ml-page-break').forEach(function (el) {
                el.classList.remove('ml-page-break');
            });
        })();
        """
        _ = try? await webView.evaluateJavaScript(js)
    }

    /// Drops empty pages off the end of the document.
    ///
    /// A forced break that lands where WebKit was going to break anyway leaves
    /// a spare sheet at the end. Predicting that exactly would mean predicting
    /// WebKit's own pagination, so the artifact is removed afterwards instead.
    /// Emptiness is decided by rendering the page and looking at it, because a
    /// page holding only a diagram or an image has no text but is not blank.
    static func trimmingTrailingBlankPages(_ data: Data) -> Data {
        guard let document = PDFDocument(data: data), document.pageCount > 1 else { return data }

        var trimmed = false
        while document.pageCount > 1,
              let last = document.page(at: document.pageCount - 1),
              isBlank(last) {
            document.removePage(at: document.pageCount - 1)
            trimmed = true
        }
        guard trimmed, let rewritten = document.dataRepresentation() else { return data }
        return rewritten
    }

    private static func isBlank(_ page: PDFPage) -> Bool {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return false }

        // A low-resolution greyscale thumbnail is enough to tell ink from none.
        let width = 80
        let height = max(1, Int((CGFloat(width) * bounds.height / bounds.width).rounded()))
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)

        guard let raw = context.data else { return false }
        let pixels = raw.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)

        // "Blank" cannot mean "white": the print rules keep the page
        // background, so in the dark theme an empty sheet rasterises dark
        // everywhere. A page is empty when it is all one shade, whatever that
        // shade is.
        let background = pixels[0]
        let tolerance: UInt8 = 6
        for row in 0..<height {
            let start = row * context.bytesPerRow
            for column in 0..<width {
                let value = pixels[start + column]
                let delta = value > background ? value - background : background - value
                if delta > tolerance { return false }
            }
        }
        return true
    }

    #if os(macOS)
    @MainActor
    private static func paginate(_ webView: WKWebView) async throws -> Data {
        let info = NSPrintInfo()
        info.paperSize = pageSize
        info.orientation = .portrait
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        // Fit the layout to the page width; let height run to as many pages as
        // it takes.
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        // Printing to a file is the only way to get the bytes back — there is
        // no "render to PDF data" entry point on the print path.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("marklens-export-\(UUID().uuidString).pdf")
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = CGRect(origin: .zero, size: pageSize)

        // `run()` blocks the main thread in a nested run loop while WebKit is
        // still waiting on its content process, and deadlocks. runModal is the
        // asynchronous variant — it returns immediately and calls back.
        guard let window = webView.window else { throw Failure.printFailed }
        let succeeded = await withCheckedContinuation { continuation in
            let observer = PrintObserver(continuation)
            printObservers.append(observer)
            operation.runModal(for: window,
                               delegate: observer,
                               didRun: #selector(PrintObserver.printOperationDidRun(_:success:contextInfo:)),
                               contextInfo: nil)
        }
        guard succeeded else { throw Failure.printFailed }
        defer { try? FileManager.default.removeItem(at: destination) }
        return trimmingTrailingBlankPages(try Data(contentsOf: destination))
    }

    /// `runModal` takes its delegate unowned, so each observer has to be kept
    /// alive until its callback arrives.
    ///
    /// One slot is not enough: every `DocumentGroup` window has its own export
    /// guard, so two windows can export at once. A single slot would drop the
    /// first observer when the second started, leaving `runModal` holding a
    /// dangling delegate and the first export's continuation never resumed.
    @MainActor private static var printObservers: [PrintObserver] = []

    private final class PrintObserver: NSObject {
        private let continuation: CheckedContinuation<Bool, Never>
        private var resumed = false

        init(_ continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        @objc func printOperationDidRun(_ operation: NSPrintOperation,
                                        success: Bool,
                                        contextInfo: UnsafeMutableRawPointer?) {
            guard !resumed else { return }
            resumed = true
            continuation.resume(returning: success)
            Task { @MainActor in
                PDFExporter.printObservers.removeAll { $0 === self }
            }
        }
    }
    #else
    @MainActor
    private static func paginate(_ webView: WKWebView) async throws -> Data {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)

        // paperRect and printableRect are read-only on UIPrintPageRenderer;
        // KVC is the documented-by-usage way to drive it outside a print job.
        let paper = CGRect(origin: .zero, size: pageSize)
        renderer.setValue(paper, forKey: "paperRect")
        renderer.setValue(paper.insetBy(dx: margin, dy: margin), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        let pages = renderer.numberOfPages
        guard pages > 0 else {
            UIGraphicsEndPDFContext()
            throw Failure.printFailed
        }
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
        for page in 0..<pages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return trimmingTrailingBlankPages(data as Data)
    }
    #endif
}
