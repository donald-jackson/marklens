import SwiftUI
import MarklensCore

struct ContentView: View {
    let document: MarkdownDocument
    let fileURL: URL?

    @Environment(\.colorScheme) private var colorScheme
    @State private var rendered: RenderedDocument?
    @StateObject private var webController = WebViewController()
    @StateObject private var findController = FindController()

    var body: some View {
        Group {
            if let rendered {
                MarkdownWebView(
                    rendered: rendered,
                    dark: colorScheme == .dark,
                    baseURL: WebResources.bundleURL,
                    controller: webController
                )
            } else {
                Color.clear
            }
        }
        .overlay(alignment: .top) {
            if findController.isActive {
                FindBar(controller: findController)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: findController.isActive)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
        .navigationTitle(fileURL?.deletingPathExtension().lastPathComponent ?? "Markdown")
        .toolbar { Toolbar(fileURL: fileURL, controller: webController, findController: findController) }
        .focusedSceneValue(\.findController, findController)
        .task(id: document.source) {
            findController.hide()
            await render()
        }
        .onChange(of: webController.isReady) { _, ready in
            if ready { findController.webView = webController.webView }
        }
    }

    @MainActor
    private func render() async {
        let source = document.source
        webController.isReady = false
        let result = await Task.detached(priority: .userInitiated) {
            MarkdownRenderer().renderHTML(from: source)
        }.value
        self.rendered = result
    }
}
