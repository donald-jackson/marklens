import Foundation
import WebKit
import UniformTypeIdentifiers
import MarklensCore

#if os(macOS)
import AppKit
#endif

/// `WKURLSchemeHandler` for the `marklens-asset:` scheme that `MarklensCore`
/// rewrites document-relative `src`/`href` attributes to (see
/// `RelativeReferenceRewriter`). Resolves each request against the folder the
/// currently displayed document lives in, requesting one-time folder access
/// (and remembering it via a security-scoped bookmark) if the sandbox denies
/// a direct read.
@MainActor
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = RelativeReferenceRewriter.scheme

    /// The folder the currently displayed document lives in. The hosting
    /// view updates this whenever a new document is opened.
    var documentFolder: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        Task { [weak self] in
            await self?.handle(urlSchemeTask)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Requests are local file reads that resolve quickly; there's no
        // in-flight network operation worth cancelling.
    }

    private func handle(_ task: WKURLSchemeTask) async {
        guard let requestURL = task.request.url,
              let reference = DocumentAssetResolver.relativeReference(from: requestURL),
              let folder = documentFolder,
              let target = DocumentAssetResolver.resolve(reference, in: folder)
        else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        guard let data = await Self.readData(at: target, folder: folder) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(
            url: requestURL,
            mimeType: Self.mimeType(for: target),
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    /// Reads `target`, falling back to a previously granted folder bookmark
    /// and, failing that, a one-time folder-access prompt.
    static func readData(at target: URL, folder: URL) async -> Data? {
        if let data = try? Data(contentsOf: target) { return data }

        if let scoped = FolderAccessStore.shared.startAccessing(folder) {
            defer { scoped.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: target) { return data }
        }

        guard await grantedFolderAccess(for: folder) else { return nil }
        guard let scoped = FolderAccessStore.shared.startAccessing(folder) else { return nil }
        defer { scoped.stopAccessingSecurityScopedResource() }
        return try? Data(contentsOf: target)
    }

    /// Coalesces concurrent asset requests from the same page load (e.g. a
    /// document with several images) into a single folder-access prompt.
    private static var pendingGrants: [String: Task<Bool, Never>] = [:]

    private static func grantedFolderAccess(for folder: URL) async -> Bool {
        let key = folder.standardizedFileURL.path
        if let existing = pendingGrants[key] {
            return await existing.value
        }
        let task = Task<Bool, Never> {
            guard let granted = await requestFolderAccess(for: folder) else { return false }
            FolderAccessStore.shared.remember(granted)
            granted.stopAccessingSecurityScopedResource()
            return true
        }
        pendingGrants[key] = task
        let result = await task.value
        pendingGrants[key] = nil
        return result
    }

    static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}

#if os(macOS)
extension AssetSchemeHandler {
    /// Prompts the user, once per folder, to grant read access via the
    /// standard Open panel restricted to the document's own folder. Returns
    /// a URL with an active security scope the caller must close.
    static func requestFolderAccess(for folder: URL) async -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Marklens needs one-time access to \u{201c}\(folder.lastPathComponent)\u{201d} "
            + "to show images and open links next to this document."
        panel.prompt = "Grant Access"
        panel.directoryURL = folder
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        let response = await panel.beginAsync()
        guard response == .OK,
              let chosen = panel.url,
              chosen.standardizedFileURL.path == folder.standardizedFileURL.path,
              chosen.startAccessingSecurityScopedResource()
        else { return nil }
        return chosen
    }
}

private extension NSOpenPanel {
    /// Async presentation — mirrors `NSSavePanel.beginAsync()` in `Toolbar.swift`.
    func beginAsync() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            begin { response in
                cont.resume(returning: response)
            }
        }
    }
}
#else
extension AssetSchemeHandler {
    static func requestFolderAccess(for folder: URL) async -> URL? {
        await IOSPresenter.requestFolderAccess(for: folder)
    }
}
#endif
