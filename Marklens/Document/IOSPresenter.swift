import Foundation

#if os(iOS)
import UIKit

/// UIKit presentation from places that have no view controller of their own
/// (the web view coordinator, the folder-access grant flow, the toolbar).
@MainActor
enum IOSPresenter {
    /// The controller currently on screen — walks past any sheet that's
    /// already up, so we never present onto a busy controller.
    static func top() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return nil }

        var presenter: UIViewController = root
        while let next = presenter.presentedViewController { presenter = next }
        return presenter
    }

    static func alert(title: String, message: String) {
        guard let presenter = top() else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }

    /// iOS's equivalent of a save panel: the Files picker in export mode. Only
    /// meaningful for files we generated ourselves (the exported PDF) — `asCopy`
    /// leaves our temp original alone and drops a copy where the user chooses.
    static func saveToFiles(_ url: URL) {
        guard let presenter = top() else { return }
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        presenter.present(picker, animated: true)
    }

    /// System share sheet for `url`. On iPad a popover needs an anchor — point
    /// it at the top-right, where the toolbar buttons live.
    static func share(_ url: URL) {
        guard let presenter = top() else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.maxX - 60,
                y: presenter.view.bounds.minY + 60,
                width: 1, height: 1
            )
            popover.permittedArrowDirections = .up
        }
        presenter.present(activity, animated: true)
    }

    /// Presents the Files picker restricted to folders so the user can grant
    /// one-time access to `folder` when a relative image/link next to the
    /// open document can't be read under the app's existing sandbox scope.
    /// Returns a URL with an active security scope the caller must close, or
    /// `nil` if presentation failed or the user cancelled.
    static func requestFolderAccess(for folder: URL) async -> URL? {
        guard let presenter = top() else { return nil }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.directoryURL = folder
        picker.allowsMultipleSelection = false

        let chosen: URL? = await withCheckedContinuation { continuation in
            var delegate: FolderPickerDelegate!
            delegate = FolderPickerDelegate(continuation: continuation) {
                activeFolderPickerDelegates.removeAll { $0 === delegate }
            }
            activeFolderPickerDelegates.append(delegate)
            picker.delegate = delegate
            presenter.present(picker, animated: true)
        }

        guard let chosen, chosen.startAccessingSecurityScopedResource() else { return nil }
        return chosen
    }

    /// Keeps folder-picker delegates alive for the lifetime of the picker
    /// presentation — `UIDocumentPickerViewController.delegate` is `weak`.
    private static var activeFolderPickerDelegates: [FolderPickerDelegate] = []
}

private final class FolderPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let continuation: CheckedContinuation<URL?, Never>
    private let onFinish: () -> Void
    private var didResume = false

    init(continuation: CheckedContinuation<URL?, Never>, onFinish: @escaping () -> Void) {
        self.continuation = continuation
        self.onFinish = onFinish
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(nil)
    }

    private func finish(_ url: URL?) {
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: url)
        onFinish()
    }
}
#endif