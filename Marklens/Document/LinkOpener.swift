import Foundation
import MarklensCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Hands links the web view can't follow itself to the rest of the system.
enum LinkOpener {
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    /// Opens a file the document linked to, in whichever app owns its type.
    ///
    /// Inside the sandbox this only succeeds for files we've been granted —
    /// the one the user opened, or anything else they've since let us at. A
    /// link to an unrelated file on disk is refused by LaunchServices, which
    /// is the correct outcome: the sandbox is the boundary, not a bug to work
    /// around. We make the honest attempt and leave it there.
    static func openFile(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        // iOS has no equivalent: the app only ever holds the one document the
        // document browser handed it, so there is nothing safe to open here.
        _ = url
        #endif
    }
}
