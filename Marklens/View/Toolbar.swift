import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct Toolbar: ToolbarContent {
    let fileURL: URL?
    @ObservedObject var controller: WebViewController

    @State private var iOSExportURL: URL?
    @State private var isExporting = false

    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                controller.zoomOut()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .disabled(!controller.isReady)
            .help("Zoom out")
            .keyboardShortcut("-", modifiers: .command)

            Button {
                controller.zoomIn()
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .disabled(!controller.isReady)
            .help("Zoom in")
            .keyboardShortcut("=", modifiers: .command)

            Button {
                controller.resetZoom()
            } label: {
                Label("Actual Size", systemImage: "1.magnifyingglass")
            }
            .disabled(!controller.isReady)
            .help("Actual size")
            .keyboardShortcut("0", modifiers: .command)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await exportPDFOnMac() }
            } label: {
                Label("Export as PDF", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(!controller.isReady || isExporting)
            .help("Export the rendered document as a PDF")
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                if let fileURL { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .disabled(fileURL == nil)
            .help("Show this file in Finder")
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await prepareIOSExport() }
            } label: {
                Label("Export as PDF", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(!controller.isReady)
        }
        ToolbarItem(placement: .primaryAction) {
            if let url = iOSExportURL {
                ShareLink(item: url, preview: SharePreview(url.lastPathComponent)) {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
            } else if let fileURL {
                ShareLink(item: fileURL) {
                    Label("Share file", systemImage: "square.and.arrow.up")
                }
            }
        }
        #endif
    }

    private var suggestedName: String {
        let stem = fileURL?.deletingPathExtension().lastPathComponent ?? "Document"
        return "\(stem).pdf"
    }

    #if os(macOS)
    @MainActor
    private func exportPDFOnMac() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }

        do {
            let data = try await controller.exportPDF()

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = suggestedName
            panel.directoryURL = fileURL?.deletingLastPathComponent()

            let response = await panel.beginAsync()
            guard response == .OK, let url = panel.url else { return }
            try data.write(to: url)
        } catch {
            await presentAlert(error: error)
        }
    }

    @MainActor
    private func presentAlert(error: Error) async {
        let alert = NSAlert()
        alert.messageText = "Couldn't export PDF"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }
    #else
    @MainActor
    private func prepareIOSExport() async {
        do {
            let data = try await controller.exportPDF()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(suggestedName)
            try data.write(to: url, options: .atomic)
            iOSExportURL = url
        } catch {
            // On iPad the toolbar can't show alerts directly; surface the
            // failure by leaving iOSExportURL nil so the share button doesn't appear.
            iOSExportURL = nil
        }
    }
    #endif
}

#if os(macOS)
private extension NSSavePanel {
    /// Async presentation. Uses `begin(completionHandler:)` which presents the
    /// panel as its own window — works regardless of which window has focus
    /// and plays nicely with sandboxed apps that go through PowerBox.
    func beginAsync() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            begin { response in
                cont.resume(returning: response)
            }
        }
    }
}
#endif
