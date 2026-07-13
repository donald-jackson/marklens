import Foundation

/// Owns the *live* markdown source for a document window and keeps it in sync
/// with the file on disk. `DocumentGroup` reads a `MarkdownDocument` once at
/// open time; this object re-reads the file on demand (menu/toolbar "Reload")
/// and, when auto-reload is on, whenever a `FileWatcher` reports a change.
///
/// The view renders from `source` rather than the frozen `document.source`, so
/// reloads never touch the read-only `FileDocument`'s dirty-tracking.
@MainActor
final class DocumentReloader: ObservableObject {
    /// The current markdown text — updated in place on reload.
    @Published private(set) var source: String

    /// True once a file URL is known (so Reload can act).
    @Published private(set) var canReload: Bool = false

    /// The disk copy changed while auto-reload was off — lets the UI surface
    /// that the view is stale.
    @Published private(set) var hasExternalChanges: Bool = false

    @Published var autoReloadEnabled: Bool = true {
        didSet {
            if autoReloadEnabled && hasExternalChanges { reload() }
        }
    }

    private var fileURL: URL?
    private var isAccessingScope = false
    private var watcher: FileWatcher?

    init(initialSource: String) {
        self.source = initialSource
    }

    deinit {
        watcher?.stop()
        if isAccessingScope { fileURL?.stopAccessingSecurityScopedResource() }
    }

    /// Point the reloader at the document's file. Safe to call repeatedly with
    /// the same URL (a no-op). Opens security-scoped access that lasts for the
    /// window's lifetime so both the watcher's `open()` and disk reads succeed
    /// inside the sandbox.
    func configure(fileURL: URL?) {
        guard fileURL != self.fileURL else { return }

        watcher?.stop()
        watcher = nil
        if isAccessingScope { self.fileURL?.stopAccessingSecurityScopedResource() }
        isAccessingScope = false

        self.fileURL = fileURL
        canReload = fileURL != nil
        hasExternalChanges = false

        guard let fileURL else { return }
        isAccessingScope = fileURL.startAccessingSecurityScopedResource()
        watcher = FileWatcher(url: fileURL) { [weak self] in
            self?.fileDidChange()
        }
    }

    /// Re-read the file and swap in its contents. No-op if the file can't be
    /// read or is byte-for-byte identical to what's already showing.
    func reload() {
        guard let fileURL, let text = Self.read(fileURL) else { return }
        hasExternalChanges = false
        if text != source { source = text }
    }

    private func fileDidChange() {
        if autoReloadEnabled {
            reload()
        } else {
            hasExternalChanges = true
        }
    }

    /// Mirrors `MarkdownDocument`'s decoding: UTF-8, falling back to ASCII.
    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
    }
}
