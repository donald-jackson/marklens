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
            CommandGroup(after: .newItem) {
                ReloadMenuCommands()
            }
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

        // NOTE: no DocumentGroupLaunchScene here, deliberately. Declaring one
        // (iOS 18) makes DocumentGroup silently DROP documents opened from
        // outside the app: iOS delivers the file in the scene's connection
        // options — verified — and SwiftUI shows the file browser instead of
        // the document. Reproduced with `simctl openurl file://…`; removing the
        // launch scene fixes it, and scene ordering makes no difference. The
        // cost is the custom launch screen (big title + "pick a file" hint);
        // "Open in Marklens" actually working is worth more.
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

private struct ReloadMenuCommands: View {
    @FocusedValue(\.documentReloader) private var reloader

    var body: some View {
        Button("Reload") {
            reloader?.reload()
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(reloader?.canReload != true)

        Toggle("Auto-Reload on Change", isOn: Binding(
            get: { reloader?.autoReloadEnabled ?? false },
            set: { reloader?.autoReloadEnabled = $0 }
        ))
        .disabled(reloader == nil)
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

private struct DocumentReloaderFocusKey: FocusedValueKey {
    typealias Value = DocumentReloader
}

extension FocusedValues {
    var findController: FindController? {
        get { self[FindControllerFocusKey.self] }
        set { self[FindControllerFocusKey.self] = newValue }
    }

    var documentReloader: DocumentReloader? {
        get { self[DocumentReloaderFocusKey.self] }
        set { self[DocumentReloaderFocusKey.self] = newValue }
    }
}
