import Foundation
import WebKit

/// Drives the in-page find feature. The actual search happens in JS
/// (`window.__marklensFind` declared in `find.js`); this controller just
/// owns the SwiftUI-facing state and round-trips calls through
/// `evaluateJavaScript`.
@MainActor
final class FindController: ObservableObject {
    weak var webView: WKWebView?

    @Published var isActive: Bool = false
    @Published var query: String = ""
    @Published var currentIndex: Int = -1
    @Published var matchCount: Int = 0

    /// Bumped on every show() so FindBar re-asserts keyboard focus even
    /// when the bar is already visible (e.g. ⌘F after clicking into the
    /// document, which hands first responder to the WKWebView).
    @Published private(set) var focusToken: Int = 0

    func show() {
        isActive = true
        focusToken &+= 1
    }

    func hide() {
        let wasActive = isActive
        isActive = false
        query = ""
        currentIndex = -1
        matchCount = 0
        if wasActive {
            evaluate("window.__marklensFind && window.__marklensFind.clear();")
        }
    }

    func setQuery(_ q: String) async {
        guard let webView else { return }
        let payload = jsString(q)
        let js = "JSON.stringify(window.__marklensFind ? window.__marklensFind.setQuery(\(payload)) : [0,-1])"
        do {
            let result = try await webView.evaluateJavaScript(js)
            if let s = result as? String,
               let data = s.data(using: .utf8),
               let arr = try JSONSerialization.jsonObject(with: data) as? [Int],
               arr.count == 2 {
                matchCount = arr[0]
                currentIndex = arr[1]
                return
            }
        } catch {
            // Fall through and clear state.
        }
        matchCount = 0
        currentIndex = -1
    }

    func next() async {
        await step("next")
    }

    func previous() async {
        await step("previous")
    }

    private func step(_ method: String) async {
        guard let webView, matchCount > 0 else { return }
        let js = "window.__marklensFind ? window.__marklensFind.\(method)() : -1"
        if let result = try? await webView.evaluateJavaScript(js),
           let n = result as? NSNumber {
            currentIndex = n.intValue
        }
    }

    private func evaluate(_ js: String) {
        guard let webView else { return }
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// JSON-encode the query as a JS string literal so embedded quotes,
    /// backslashes, and newlines round-trip safely into the JS snippet.
    private func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [])) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "[\"\"]"
        // Strip the surrounding [ ] to get just the encoded string.
        let trimmed = json.dropFirst().dropLast()
        return String(trimmed)
    }
}
