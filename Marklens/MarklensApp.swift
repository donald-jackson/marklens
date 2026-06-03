import SwiftUI

@main
struct MarklensApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}  // viewer only — no "New"
            #if os(macOS)
            CommandGroup(after: .textEditing) {
                FindMenuCommands()
            }
            CommandGroup(replacing: .help) {
                HelpMenuCommands()
            }
            #endif
        }

        #if os(macOS)
        Window("Marklens Help", id: "marklens-help") {
            HelpView()
        }
        .windowResizability(.contentSize)
        #endif

        #if os(iOS)
        // iPad/iPhone launch screen: small subtitle below "Marklens" so a
        // first-run user knows to bring in a file (vs. expecting an editor).
        // Anything placed in `actions` gets styled as a giant blue pill
        // button — so the hint goes through `overlayAccessoryView` and is
        // positioned manually under the title view.
        DocumentGroupLaunchScene("Marklens") {
            EmptyView()
        } backgroundAccessoryView: { _ in
            EmptyView()
        } overlayAccessoryView: { proxy in
            // proxy.titleViewFrame reports the title LAYOUT box, which is
            // larger than the visible rounded card. We clamp the hint to
            // the card width and place it just below the title glyphs via
            // card.midY + small offset, where center matches the inside of
            // the visible card on both iPhone and iPad.
            let card = proxy.titleViewFrame
            Text("Pick a Markdown file or share one to Marklens to view it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: max(80, card.width * 0.78))
                .position(x: card.midX, y: card.midY + 35)
        }
        #endif
    }
}

#if os(macOS)
private struct HelpMenuCommands: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Marklens Help") {
            openWindow(id: "marklens-help")
        }
        .keyboardShortcut("?", modifiers: .command)
    }
}

private struct FindMenuCommands: View {
    @FocusedValue(\.findController) private var findController

    var body: some View {
        Button("Find…") {
            findController?.show()
        }
        .keyboardShortcut("f", modifiers: .command)
        .disabled(findController == nil)

        Button("Find Next") {
            guard let fc = findController else { return }
            Task { await fc.next() }
        }
        .keyboardShortcut("g", modifiers: .command)
        .disabled(findController == nil)

        Button("Find Previous") {
            guard let fc = findController else { return }
            Task { await fc.previous() }
        }
        .keyboardShortcut("g", modifiers: [.command, .shift])
        .disabled(findController == nil)
    }
}
#endif

private struct FindControllerFocusKey: FocusedValueKey {
    typealias Value = FindController
}

extension FocusedValues {
    var findController: FindController? {
        get { self[FindControllerFocusKey.self] }
        set { self[FindControllerFocusKey.self] = newValue }
    }
}
