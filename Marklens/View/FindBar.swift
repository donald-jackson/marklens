import SwiftUI

struct FindBar: View {
    @ObservedObject var controller: FindController
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find", text: $controller.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit { Task { await controller.next() } }
                .frame(minWidth: 120, maxWidth: 240)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif

            if controller.matchCount > 0 {
                Text("\(controller.currentIndex + 1) of \(controller.matchCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if !controller.query.isEmpty {
                Text("No matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button { Task { await controller.previous() } } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(controller.matchCount == 0)
            .help("Previous match")
            #if os(macOS)
            .keyboardShortcut("g", modifiers: [.command, .shift])
            #endif

            Button { Task { await controller.next() } } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(controller.matchCount == 0)
            .help("Next match")
            #if os(macOS)
            .keyboardShortcut("g", modifiers: .command)
            #endif

            Button { controller.hide() } label: {
                Image(systemName: "xmark")
            }
            .help("Close find bar")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .onAppear { focused = true }
        .task(id: controller.query) {
            // Debounce typing so rapid keystrokes don't thrash the
            // TreeWalker on long documents.
            try? await Task.sleep(nanoseconds: 150_000_000)
            await controller.setQuery(controller.query)
        }
    }
}
