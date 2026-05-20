import SwiftUI

struct Toolbar: ToolbarContent {
    let fileURL: URL?

    var body: some ToolbarContent {
        #if os(macOS)
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
            if let fileURL {
                ShareLink(item: fileURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        #endif
    }
}
