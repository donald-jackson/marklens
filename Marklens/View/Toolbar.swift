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

    @State private var iOSExportURL: URL?
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
                findController.show()
            } label: {
                Label("Find", systemImage: "magnifyingglass")
            }
            .disabled(!controller.isReady)
            .keyboardShortcut("f", modifiers: .command)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await prepareIOSExport() }
            } label: {
                Label("Export as PDF", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(!controller.isReady)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await presentShareSheet() }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(fileURL == nil && iOSExportURL == nil)
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
            // Hand the freshly-exported PDF straight to the share sheet so
            // tapping Export-as-PDF surfaces something useful in one tap.
            presentActivity(for: url)
        } catch {
            iOSExportURL = nil
        }
    }

    /// Presents the system share sheet with the most relevant item:
    /// the just-exported PDF if one exists, otherwise a copy of the
    /// original markdown file made in our own tmp dir (so the system
    /// share sheet doesn't trip on the security-scoped DocumentGroup URL,
    /// which is why `ShareLink(item: fileURL)` silently no-ops).
    @MainActor
    private func presentShareSheet() async {
        var url: URL?
        if let pdf = iOSExportURL {
            url = pdf
        } else if let original = fileURL {
            url = await copyForSharing(original)
        }
        guard let url else { return }
        presentActivity(for: url)
    }

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
    private func presentActivity(for url: URL) {
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return }
        // Walk to the currently-presented controller so we don't try to
        // present on something that already has a sheet up.
        var presenter: UIViewController = root
        while let next = presenter.presentedViewController { presenter = next }
        // iPad needs a popover anchor — anchor to the top-right of the
        // presenter's view so it points at the toolbar button.
        if let popover = av.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.maxX - 60,
                y: presenter.view.bounds.minY + 60,
                width: 1, height: 1
            )
            popover.permittedArrowDirections = .up
        }
        presenter.present(av, animated: true)
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
