import Foundation

/// Resolves a `marklens-asset:` reference produced by `RelativeReferenceRewriter`
/// back to a file on disk, next to the open document.
public enum DocumentAssetResolver {
    /// Extracts the raw relative reference encoded in a `marklens-asset:` URL,
    /// e.g. `marklens-asset:///diagram.png` → `"diagram.png"`, or
    /// `marklens-asset:///sub/Notes.md` → `"sub/Notes.md"`. Returns `nil` for
    /// URLs using a different scheme or with no path.
    public static func relativeReference(from url: URL) -> String? {
        guard url.scheme == RelativeReferenceRewriter.scheme else { return nil }
        var path = url.path
        while path.hasPrefix("/") { path.removeFirst() }
        guard !path.isEmpty else { return nil }
        return path.removingPercentEncoding ?? path
    }

    /// Resolves `reference` against `folder`, returning `nil` if the result
    /// would escape `folder` — e.g. a reference containing `../../etc/passwd`.
    public static func resolve(_ reference: String, in folder: URL) -> URL? {
        let standardizedFolder = folder.standardizedFileURL
        let candidate = standardizedFolder.appendingPathComponent(reference).standardizedFileURL

        let folderPath = standardizedFolder.path.hasSuffix("/")
            ? standardizedFolder.path
            : standardizedFolder.path + "/"
        guard candidate.path.hasPrefix(folderPath) else { return nil }
        return candidate
    }
}
