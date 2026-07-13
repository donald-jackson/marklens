import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct Toolbar: ToolbarContent {
    let fileURL: URL?
    @ObservedObject var controller: WebViewController
    @ObservedObject var findController: FindController
    @ObservedObject var reloader: DocumentReloader

    @State private var isExporting = false

    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button {
                findController.show()
            } label: {
                Label("Find", systemImage: "magnifyingglass")
            }
            .disabled(!controller.isReady)
            .help("Find in document (⌘F)")
            // No .keyboardShortcut here: ⌘F is owned by the Find… menu
            // command. Registering it twice makes SwiftUI pick a handler
            // arbitrarily, which made find-bar focus behavior flaky.
        }
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
            exportMarkdownButton
        }
        ToolbarItem(placement: .primaryAction) {
            exportPDFMenu
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
        ToolbarItem(placement: .primaryAction) {
            reloadButton
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            Button {
                findController.show()
            } label: {
                Label("Find", systemImage: "magnifyingglass")
            }
            .disabled(!controller.isReady)
            .keyboardShortcut("f", modifiers: .command)
        }
        ToolbarItem(placement: .primaryAction) {
            exportMarkdownButton
        }
        ToolbarItem(placement: .primaryAction) {
            exportPDFMenu
        }
        ToolbarItem(placement: .primaryAction) {
            reloadButton
        }
        #endif
    }

    // MARK: Export

    /// Sends the Markdown file itself somewhere — Mail, Messages, AirDrop.
    /// Deliberately *not* a save-to-file: the file already exists on disk, and
    /// on iOS the share sheet is the only way out of the app anyway.
    @ViewBuilder
    private var exportMarkdownButton: some View {
        Button {
            Task { await shareMarkdown() }
        } label: {
            Label("Export Markdown", systemImage: "square.and.arrow.up")
        }
        .disabled(fileURL == nil)
        #if os(macOS)
        .help("Send this Markdown file to another app or person")
        #endif
    }

    /// PDF is a *new* file, so it gets both destinations: hand it to someone
    /// (share) or put it somewhere (save). A dropdown keeps the distinction
    /// explicit instead of guessing which one was meant — the old single button
    /// silently did both, and then leaked the exported PDF into the Share
    /// action so sharing the document sent a PDF instead of the Markdown.
    @ViewBuilder
    private var exportPDFMenu: some View {
        Menu {
            Button {
                Task { await sharePDF() }
            } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button {
                Task { await savePDF() }
            } label: {
                Label("Save to File…", systemImage: "folder")
            }
            #if os(macOS)
            .keyboardShortcut("e", modifiers: [.command, .shift])
            #endif
        } label: {
            Label("Export PDF", systemImage: "arrow.up.doc")
        }
        .disabled(!controller.isReady || isExporting)
        #if os(macOS)
        .help("Export the rendered document as a PDF")
        #endif
    }

    /// Re-read the file from disk. Emphasized with a filled glyph when the
    /// on-disk copy has changed but auto-reload is off, so the view's staleness
    /// is visible at a glance.
    @ViewBuilder
    private var reloadButton: some View {
        Button {
            reloader.reload()
        } label: {
            Label(
                "Reload",
                systemImage: reloader.hasExternalChanges
                    ? "arrow.clockwise.circle.fill"
                    : "arrow.clockwise"
            )
        }
        .disabled(!reloader.canReload)
        #if os(macOS)
        .help(reloader.hasExternalChanges
              ? "This file changed on disk — reload to update (⌘R)"
              : "Reload this file from disk (⌘R)")
        .keyboardShortcut("r", modifiers: .command)
        #endif
    }

    private var suggestedName: String {
        let stem = fileURL?.deletingPathExtension().lastPathComponent ?? "Document"
        return "\(stem).pdf"
    }

    /// Renders the current page to a PDF in our temp dir. Always produced fresh
    /// — never cached — so it can't go stale against the document on screen
    /// (which, since links now navigate in place on iOS, can change).
    @MainActor
    private func renderPDF() async -> URL? {
        guard !isExporting else { return nil }
        isExporting = true
        defer { isExporting = false }
        do {
            let data = try await controller.exportPDF()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(suggestedName)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            await reportExportFailure(error)
            return nil
        }
    }

    // MARK: - macOS

    #if os(macOS)
    @MainActor
    private func shareMarkdown() async {
        guard let fileURL else { return }
        presentSharingPicker(for: [fileURL])
    }

    @MainActor
    private func sharePDF() async {
        guard let pdf = await renderPDF() else { return }
        presentSharingPicker(for: [pdf])
    }

    @MainActor
    private func savePDF() async {
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
            await reportExportFailure(error)
        }
    }

    /// Anchors the share picker under the toolbar, on the trailing side where
    /// the export buttons live.
    @MainActor
    private func presentSharingPicker(for items: [Any]) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let view = window.contentView
        else { return }
        let picker = NSSharingServicePicker(items: items)
        let anchor = NSRect(x: view.bounds.maxX - 90, y: view.bounds.maxY - 1, width: 1, height: 1)
        picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }

    @MainActor
    private func reportExportFailure(_ error: Error) async {
        let alert = NSAlert()
        alert.messageText = "Couldn't export PDF"
        alert.informativeText = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    @MainActor
    private func shareMarkdown() async {
        guard let original = fileURL, let copy = await copyForSharing(original) else { return }
        IOSPresenter.share(copy)
    }

    @MainActor
    private func sharePDF() async {
        guard let pdf = await renderPDF() else { return }
        IOSPresenter.share(pdf)
    }

    @MainActor
    private func savePDF() async {
        guard let pdf = await renderPDF() else { return }
        IOSPresenter.saveToFiles(pdf)
    }

    /// The share sheet trips over the security-scoped DocumentGroup URL — which
    /// is why `ShareLink(item: fileURL)` silently no-ops — so hand it a copy in
    /// our own temp dir instead.
    @MainActor
    private func copyForSharing(_ source: URL) async -> URL? {
        let didStart = source.startAccessingSecurityScopedResource()
        defer { if didStart { source.stopAccessingSecurityScopedResource() } }
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent(source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: source, to: dst)
            return dst
        } catch {
            return nil
        }
    }

    @MainActor
    private func reportExportFailure(_ error: Error) async {
        IOSPresenter.alert(
            title: "Couldn't Export PDF",
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        )
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