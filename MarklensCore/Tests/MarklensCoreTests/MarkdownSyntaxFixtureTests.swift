import XCTest
@testable import MarklensCore

/// Renders `Samples/markdown-syntax.md` — the repository's full-syntax fixture —
/// and checks that every construct in it survives the pipeline.
///
/// The point is the last assertion set: the fixture deliberately puts raw-text
/// elements (`<style>`, `<script>`, `<title>`, `<textarea>`, `</body>`) inside
/// code spans. If any of them reached the page unescaped it would open a
/// raw-text element and the browser would drop everything after it, so a
/// document that renders to its sentinel line is a document that rendered in
/// full.
final class MarkdownSyntaxFixtureTests: XCTestCase {
    private let renderer = MarkdownRenderer()

    /// `<repo root>/Samples/markdown-syntax.md`, found from this source file so
    /// the test works both under `swift test` and from Xcode.
    private static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // MarklensCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // MarklensCore
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Samples/markdown-syntax.md")
    }

    private func renderFixture() throws -> RenderedDocument {
        let url = Self.fixtureURL
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            XCTFail("Could not read the syntax fixture at \(url.path): \(error)")
            throw error
        }
        return renderer.renderHTML(from: source, baseDirectory: url.deletingLastPathComponent())
    }

    func testFixtureRendersToTheEnd() throws {
        let body = try renderFixture().body
        XCTAssertTrue(body.contains("If you can read this sentinel line"),
                      "the fixture did not render to its final line")
    }

    /// The failure this fixture exists for: literal HTML in code must come out
    /// escaped, never as live markup.
    func testLiteralHTMLIsEscapedNotExecuted() throws {
        let body = try renderFixture().body
        for raw in ["<style>", "<script>", "</script>", "<title>", "<textarea>"] {
            XCTAssertFalse(body.contains(raw),
                           "\(raw) reached the page unescaped: \(body)")
        }
        XCTAssertTrue(body.contains("<code>&lt;style&gt;</code>"), "got: \(body)")
        XCTAssertTrue(body.contains("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"),
                      "got: \(body)")
    }

    func testBlockElementsRender() throws {
        let body = try renderFixture().body
        XCTAssertTrue(body.contains("<h1 id=\"marklens-syntax-reference\">"), "got: \(body)")
        XCTAssertTrue(body.contains("<h1 id=\"setext-heading-level-one\">"), "setext h1: \(body)")
        XCTAssertTrue(body.contains("<h2 id=\"setext-heading-level-two\">"), "setext h2: \(body)")
        XCTAssertTrue(body.contains("<h6 id=\"level-six\">"), "h6: \(body)")
        XCTAssertTrue(body.contains("<blockquote>"), "blockquote: \(body)")
        XCTAssertTrue(body.contains("<ol start=\"3\">"), "ordered list start: \(body)")
        XCTAssertTrue(body.contains("<pre><code class=\"language-swift\">"), "swift fence: \(body)")
        XCTAssertTrue(body.contains("<pre><code class=\"language-html\">"), "html fence: \(body)")
        XCTAssertTrue(body.contains("<hr />"), "thematic break: \(body)")
        XCTAssertTrue(body.contains("<table>"), "table: \(body)")
        XCTAssertTrue(body.contains("<th align=\"center\">"), "table alignment: \(body)")
        XCTAssertTrue(body.contains("<input type=\"checkbox\" disabled=\"\" checked=\"\" />"),
                      "checked task list item: \(body)")
        XCTAssertTrue(body.contains("<input type=\"checkbox\" disabled=\"\" />"),
                      "unchecked task list item: \(body)")
    }

    func testInlineElementsRender() throws {
        let body = try renderFixture().body
        XCTAssertTrue(body.contains("<em>emphasis</em>"), "got: \(body)")
        XCTAssertTrue(body.contains("<strong>strong</strong>"), "got: \(body)")
        XCTAssertTrue(body.contains("<del>strikethrough</del>"), "got: \(body)")
        XCTAssertTrue(body.contains("<br />"), "hard break: \(body)")
        XCTAssertTrue(body.contains("<a href=\"https://spec.commonmark.org/\">"), "reference link: \(body)")
        XCTAssertTrue(body.contains("<a href=\"mailto:hello@example.com\">"), "email autolink: \(body)")
        XCTAssertTrue(body.contains("<img src=\"https://placehold.co/120x40\""), "image: \(body)")
        XCTAssertTrue(body.contains("5 &lt; 6, 6 &gt; 5, AT&amp;T"), "prose escaping: \(body)")
        XCTAssertTrue(body.contains("© &amp; &lt; &gt; &quot;"), "entities: \(body)")
    }

    /// Raw HTML is legal markdown and is meant to render as markup.
    func testRawHTMLIsPassedThrough() throws {
        let body = try renderFixture().body
        XCTAssertTrue(body.contains("<div class=\"raw-block\">"), "got: \(body)")
        XCTAssertTrue(body.contains("<mark>highlighted</mark>"), "got: \(body)")
        XCTAssertTrue(body.contains("<kbd>⌘K</kbd>"), "got: \(body)")
    }

    func testMathAndMermaidAreDetected() throws {
        let result = try renderFixture()
        XCTAssertTrue(result.containsMath)
        XCTAssertTrue(result.containsMermaid)
        XCTAssertTrue(result.body.contains("<span class=\"ml-math\">E = mc^2</span>"), "got: \(result.body)")
        XCTAssertTrue(result.body.contains("<div class=\"ml-math ml-math-display\">"), "got: \(result.body)")
        XCTAssertTrue(result.body.contains("a &amp; b \\\\ c &amp; d"),
                      "math ampersands escaped once: \(result.body)")
        XCTAssertTrue(result.body.contains("<div class=\"mermaid\">"), "got: \(result.body)")
        XCTAssertFalse(result.body.contains("--&gt;"), "mermaid was escaped: \(result.body)")
    }
}
