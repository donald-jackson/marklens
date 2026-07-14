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
}
#endif