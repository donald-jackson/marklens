import XCTest
@testable import MarklensCore

/// `HTMLFormatter` escapes nothing: it writes text and code straight through.
/// That is fine for prose that contains no markup, but a literal `<style>` in a
/// code span used to become a live raw-text element — the browser then consumed
/// the remainder of the page, so the document looked truncated.
final class HTMLEscapingTests: XCTestCase {
    private let renderer = MarkdownRenderer()

    // MARK: The reported failure

    func testInlineCodeWithRawTextElementStaysLiteral() {
        let body = renderer.renderHTML(from: "`Testtag` quick `<style>` fox `</body>` jump").body
        XCTAssertTrue(body.contains("<code>Testtag</code>"), "got: \(body)")
        XCTAssertTrue(body.contains("<code>&lt;style&gt;</code>"), "got: \(body)")
        XCTAssertTrue(body.contains("<code>&lt;/body&gt;</code>"), "got: \(body)")
        // Nothing after the code span may be lost.
        XCTAssertTrue(body.contains("fox"), "content after the tag was dropped: \(body)")
        XCTAssertTrue(body.contains("jump"), "content after the tag was dropped: \(body)")
    }

    func testInlineCodeNeverEmitsLiveTags() {
        let body = renderer.renderHTML(from: "`<script>alert(1)</script>`").body
        XCTAssertFalse(body.contains("<script>"), "live script tag: \(body)")
        XCTAssertTrue(body.contains("&lt;script&gt;"), "got: \(body)")
        XCTAssertTrue(body.contains("&lt;/script&gt;"), "got: \(body)")
    }

    func testInlineCodeEscapesEveryMarkupCharacter() {
        let body = renderer.renderHTML(from: "`<a href=\"x\">a & b</a>`").body
        XCTAssertFalse(body.contains("<a href="), "live anchor: \(body)")
        XCTAssertTrue(body.contains("&lt;a href=&quot;x&quot;&gt;"), "got: \(body)")
        XCTAssertTrue(body.contains("a &amp; b"), "got: \(body)")
    }

    // MARK: Prose

    func testPlainTextAngleBracketsAreEscaped() {
        let body = renderer.renderHTML(from: "if a < b and b > c then stop").body
        XCTAssertTrue(body.contains("if a &lt; b and b &gt; c then stop"), "got: \(body)")
    }

    func testPlainTextAmpersandIsEscaped() {
        let body = renderer.renderHTML(from: "Smith & Sons, AT&T").body
        XCTAssertTrue(body.contains("Smith &amp; Sons, AT&amp;T"), "got: \(body)")
    }

    /// cmark decodes entity references while parsing, so escaping what it hands
    /// back must not turn `&amp;` into `&amp;amp;`.
    func testEntityReferenceIsEscapedExactlyOnce() {
        let body = renderer.renderHTML(from: "&amp; &lt; &copy;").body
        XCTAssertTrue(body.contains("&amp; &lt; ©"), "got: \(body)")
        XCTAssertFalse(body.contains("&amp;amp;"), "double-escaped: \(body)")
        XCTAssertFalse(body.contains("&amp;lt;"), "double-escaped: \(body)")
    }

    // MARK: Code blocks

    func testFencedCodeBlockEscapesMarkup() {
        let source = """
        ```html
        <style>
          body { color: red; }
        </style>
        ```
        """
        let body = renderer.renderHTML(from: source).body
        XCTAssertTrue(body.contains("&lt;style&gt;"), "got: \(body)")
        XCTAssertTrue(body.contains("&lt;/style&gt;"), "got: \(body)")
        XCTAssertFalse(body.contains("<style>"), "live style tag: \(body)")
    }

    func testIndentedCodeBlockEscapesMarkup() {
        let body = renderer.renderHTML(from: "text\n\n    <div>&</div>\n").body
        XCTAssertTrue(body.contains("&lt;div&gt;&amp;&lt;/div&gt;"), "got: \(body)")
        XCTAssertFalse(body.contains("<div>"), "live div: \(body)")
    }

    func testCodeBlockAfterContentDoesNotSwallowIt() {
        let source = """
        before

        ```
        <b>not bold</b>
        ```

        after
        """
        let body = renderer.renderHTML(from: source).body
        XCTAssertTrue(body.contains("before"), "got: \(body)")
        XCTAssertTrue(body.contains("after"), "got: \(body)")
        XCTAssertFalse(body.contains("<b>"), "live bold: \(body)")
    }

    // MARK: Markdown's own raw HTML is left alone

    func testRawHTMLBlockIsPassedThrough() {
        let body = renderer.renderHTML(from: "<div class=\"note\">\nraw html\n</div>").body
        XCTAssertTrue(body.contains("<div class=\"note\">"), "got: \(body)")
        XCTAssertTrue(body.contains("raw html"), "got: \(body)")
    }

    func testInlineRawHTMLIsPassedThrough() {
        let body = renderer.renderHTML(from: "text with <span class=\"hl\">inline html</span> here").body
        XCTAssertTrue(body.contains("<span class=\"hl\">inline html</span>"), "got: \(body)")
    }

    // MARK: Headings

    /// Escaping runs before the tree is formatted, so the anchor injector's
    /// literal match still lines up — but the slug has to come from the
    /// unescaped text or GitHub's `tom--jerry` becomes `tom-amp-jerry`.
    func testHeadingContainingAmpersandKeepsGitHubSlug() {
        let body = renderer.renderHTML(from: "## Tom & Jerry").body
        XCTAssertTrue(body.contains("<h2 id=\"tom--jerry\">"), "got: \(body)")
        XCTAssertTrue(body.contains(">Tom &amp; Jerry</h2>"), "got: \(body)")
    }

    func testHeadingContainingInlineCodeIsEscapedAndAnchored() {
        let body = renderer.renderHTML(from: "## Use `a<b`").body
        XCTAssertTrue(body.contains("<h2 id=\"use-ab\">"), "got: \(body)")
        XCTAssertTrue(body.contains("&lt;b"), "got: \(body)")
    }

    func testHeadingContainingMathStillGetsAnchorID() {
        let body = renderer.renderHTML(from: "## A & $x$").body
        XCTAssertTrue(body.contains("<h2 id=\"a--x\">"), "got: \(body)")
    }

    // MARK: Image attributes

    func testImageTitleQuotesAreEscaped() {
        let body = renderer.renderHTML(from: "![alt](photo.png 'a \"quoted\" title')").body
        XCTAssertTrue(body.contains("title=\"a &quot;quoted&quot; title\""), "got: \(body)")
    }

    func testImageSourceAmpersandIsEscaped() {
        let body = renderer.renderHTML(from: "![alt](https://example.test/a?x=1&y=2)").body
        XCTAssertTrue(body.contains("src=\"https://example.test/a?x=1&amp;y=2\""), "got: \(body)")
    }

    func testImageWithoutSourceOrTitleIsLeftAlone() {
        let body = renderer.renderHTML(from: "![]()").body
        XCTAssertTrue(body.contains("<img"), "got: \(body)")
        XCTAssertFalse(body.contains("src="), "got: \(body)")
        XCTAssertFalse(body.contains("title="), "got: \(body)")
    }

    // MARK: Interaction with the rest of the pipeline

    func testMermaidContentIsNotEscaped() {
        let source = """
        ```mermaid
        graph TD; A-->B
        ```
        """
        let body = renderer.renderHTML(from: source).body
        XCTAssertTrue(body.contains("<div class=\"mermaid\">"), "got: \(body)")
        XCTAssertTrue(body.contains("A-->B"), "mermaid content must stay raw: \(body)")
        XCTAssertFalse(body.contains("A--&gt;B"), "mermaid content was escaped: \(body)")
    }

    func testEscapingDoesNotDisturbMathReinjection() {
        let body = renderer.renderHTML(from: "`a<b` and $x$").body
        XCTAssertTrue(body.contains("&lt;b"), "got: \(body)")
        XCTAssertTrue(body.contains("<span class=\"ml-math\">x</span>"), "got: \(body)")
    }
}
