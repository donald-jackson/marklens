import Foundation

/// Persists security-scoped bookmarks for folders the user has explicitly
/// granted read access to, so sibling assets (images, linked docs) can be
/// resolved without re-prompting on every launch. See `AssetSchemeHandler`.
final class FolderAccessStore {
    static let shared = FolderAccessStore()

    private let defaultsKey = "com.marklens.folderAccessBookmarks"
    private var bookmarks: [String: Data]

    private init() {
        bookmarks = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }

    /// Returns a URL with an active security scope for `folder`, resolving a
    /// previously stored bookmark. Returns `nil` if no bookmark is stored or
    /// resolution fails. The caller owns the scope and must call
    /// `stopAccessingSecurityScopedResource()` when done.
    func startAccessing(_ folder: URL) -> URL? {
        let key = folder.standardizedFileURL.path
        guard let data = bookmarks[key] else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: Self.resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        guard url.startAccessingSecurityScopedResource() else { return nil }
        if isStale { store(bookmarkFor: url, key: key) }
        return url
    }

    /// Records a security-scoped bookmark for `url` (the folder the user just
    /// granted access to) so future launches don't need to re-prompt.
    func remember(_ url: URL) {
        store(bookmarkFor: url, key: url.standardizedFileURL.path)
    }

    private func store(bookmarkFor url: URL, key: String) {
        guard let data = try? url.bookmarkData(
            options: Self.creationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        bookmarks[key] = data
        UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
    }

    #if os(macOS)
    private static let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let creationOptions: URL.BookmarkCreationOptions = []
    private static let resolutionOptions: URL.BookmarkResolutionOptions = []
    #endif
}
