import SwiftUI

@main
struct MarklensApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}  // viewer only — no "New"
        }
    }
}
