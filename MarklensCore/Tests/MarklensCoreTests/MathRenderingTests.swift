import XCTest
@testable import MarklensCore

final class MathRenderingTests: XCTestCase {
    private let renderer = MarkdownRenderer()

    // MARK: Shape

    func testInlineMathEmitsSpan() {
        let result = renderer.renderHTML(from: "Let $x$ be")
        XCTAssertTrue(result.containsMath)
        XCTAssertTrue(result.body.contains("<span class=\"ml-math\">x</span>"),
                      "Expected inline math span, got: \(result.body)")
    }

    func testDisplayMathOwningAParagraphBecomesADiv() {
        let result = renderer.renderHTML(from: "before\n\n$$\nx = 1\n$$\n\nafter")
        XCTAssertTrue(result.body.contains("<div class=\"ml-math ml-math-display\">"),
                      "Expected display div, got: \(result.body)")
        XCTAssertFalse(result.body.contains("<p><div"),
                       "Display math should replace its paragraph, got: \(result.body)")
        XCTAssertFalse(result.body.contains("<p></p>"),
                       "Paragraph wrapper should be consumed, got: \(result.body)")
    }

    func testDisplayMathInsideAParagraphStaysInline() {
        let result = renderer.renderHTML(from: "text $$x$$ text")
        XCTAssertTrue(result.body.contains("<span class=\"ml-math ml-math-display\">x</span>"),
                      "Expected inline display span, got: \(result.body)")
        XCTAssertFalse(result.body.contains("<div"), "got: \(result.body)")
    }

    /// The case this feature was asked for.
    func testMathbfCurrencyRendersVerbatim() {
        let result = renderer.renderHTML(from: #"$$\mathbf{ZAR\ 5,000,000.00}$$"#)
        XCTAssertTrue(result.containsMath)
        XCTAssertTrue(result.body.contains(#"<div class="ml-math ml-math-display">\mathbf{ZAR\ 5,000,000.00}</div>"#),
                      "Expected verbatim LaTeX, got: \(result.body)")
    }

    // MARK: LaTeX survives CommonMark

    func testUnderscoresInMathSurvive() {
        let result = renderer.renderHTML(from: "$a_1 + b_2$")
        XCTAssertTrue(result.body.contains("a_1 + b_2"), "got: \(result.body)")
        XCTAssertFalse(result.body.contains("<em>"), "got: \(result.body)")
    }

    func testAsterisksInMathSurvive() {
        let result = renderer.renderHTML(from: "$a*b*c$")
        XCTAssertTrue(result.body.contains("a*b*c"), "got: \(result.body)")
        XCTAssertFalse(result.body.contains("<em>"), "got: \(result.body)")
    }

    func testBackslashEscapesInMathSurvive() {
        let result = renderer.renderHTML(from: #"$$\{x\} \\ \_y$$"#)
        XCTAssertTrue(result.body.contains(#"\{x\} \\ \_y"#), "got: \(result.body)")
    }

    /// Smart punctuation is on by default, so `--` and `"` would otherwise be
    /// rewritten inside what should be a formula.
    func testSmartPunctuationDoesNotReachMath() {
        let dashes = renderer.renderHTML(from: "$a -- b$").body
        XCTAssertTrue(dashes.contains("a -- b"), "got: \(dashes)")
        XCTAssertFalse(dashes.contains("\u{2013}"), "en dash leaked into math: \(dashes)")

        let quotes = renderer.renderHTML(from: #"$\text{"q"}$"#).body
        XCTAssertTrue(quotes.contains("&quot;q&quot;"), "got: \(quotes)")
        XCTAssertFalse(quotes.contains("\u{201C}"), "curly quote leaked into math: \(quotes)")
    }

    // MARK: Escaping — HTMLFormatter escapes nothing, so this is all ours

    func testAngleBracketInMathIsEscaped() {
        let body = renderer.renderHTML(from: "$a < b$").body
        XCTAssertTrue(body.contains("a &lt; b"), "got: \(body)")
    }

    func testAmpersandInMathIsEscapedExactlyOnce() {
        let body = renderer.renderHTML(from: #"$$\begin{matrix} a & b \end{matrix}$$"#).body
        XCTAssertTrue(body.contains("a &amp; b"), "got: \(body)")
        XCTAssertFalse(body.contains("&amp;amp;"), "double-escaped: \(body)")
    }

    // MARK: Code is never math

    func testMathInsideFencedCodeBlockIsNotExtracted() {
        let source = """
        ```
        $$x$$
        ```
        """
        let result = renderer.renderHTML(from: source)
        XCTAssertFalse(result.containsMath)
        XCTAssertFalse(result.body.contains("ml-math"), "got: \(result.body)")
        XCTAssertTrue(result.body.contains("$$x$$"), "got: \(result.body)")
    }

    func testMathInsideInlineCodeIsNotExtracted() {
        let result = renderer.renderHTML(from: "`$x$`")
        XCTAssertFalse(result.containsMath)
        XCTAssertTrue(result.body.contains("<code>$x$</code>"), "got: \(result.body)")
    }

    func testMathInsideIndentedCodeBlockIsNotExtracted() {
        let result = renderer.renderHTML(from: "text\n\n    $$x$$\n")
        XCTAssertFalse(result.containsMath)
        XCTAssertTrue(result.body.contains("<pre>"), "got: \(result.body)")
    }

    // MARK: Currency

    func testCurrencyPairIsNotMath() {
        let result = renderer.renderHTML(from: "Costs $5 and $10 today.")
        XCTAssertFalse(result.containsMath)
        XCTAssertTrue(result.body.contains("$5 and $10"), "got: \(result.body)")
    }

    func testCurrencyThenRealMathRendersOnlyTheMath() {
        let result = renderer.renderHTML(from: "It costs $5. Also $x+y$ holds.")
        XCTAssertTrue(result.body.contains("<span class=\"ml-math\">x+y</span>"), "got: \(result.body)")
        XCTAssertTrue(result.body.contains("$5."), "got: \(result.body)")
    }

    // MARK: Interaction with the rest of the pipeline

    /// Math re-injection runs after `HeadingAnchorInjector`, which matches
    /// headings by the literal text the parser saw. Reversed, every heading
    /// containing math would silently lose its `id`.
    func testMathInHeadingStillGetsAnchorID() {
        let body = renderer.renderHTML(from: "## Cost $x$").body
        // `cost-x` is what GitHub's slugger gives this heading. Slugging the
        // placeholder instead would give `cost-`.
        XCTAssertTrue(body.contains("<h2 id=\"cost-x\">"), "Expected anchored heading, got: \(body)")
        XCTAssertTrue(body.contains("ml-math"), "got: \(body)")
    }

    func testHeadingSlugsAreUnaffectedWithoutMath() {
        let body = renderer.renderHTML(from: "## Getting Started").body
        XCTAssertTrue(body.contains("<h2 id=\"getting-started\">"), "got: \(body)")
    }

    func testMathInListItemAndTableAndBlockquote() {
        let list = renderer.renderHTML(from: "- item $x$").body
        XCTAssertTrue(list.contains("<li>") && list.contains("ml-math"), "got: \(list)")

        let table = renderer.renderHTML(from: "| A |\n|---|\n| $x$ |").body
        XCTAssertTrue(table.contains("<td") && table.contains("ml-math"), "got: \(table)")

        let quote = renderer.renderHTML(from: "> quoted $x$").body
        XCTAssertTrue(quote.contains("<blockquote>") && quote.contains("ml-math"), "got: \(quote)")
    }

    func testMermaidAndMathCoexist() {
        let source = """
        ```mermaid
        graph TD; A-->B
        ```

        $$x = 1$$
        """
        let result = renderer.renderHTML(from: source)
        XCTAssertTrue(result.containsMermaid)
        XCTAssertTrue(result.containsMath)
        XCTAssertTrue(result.body.contains("<div class=\"mermaid\">"), "got: \(result.body)")
        XCTAssertTrue(result.body.contains("A-->B"), "mermaid stays unescaped: \(result.body)")
        XCTAssertTrue(result.body.contains("ml-math-display"), "got: \(result.body)")
    }

    func testDocumentWithoutMathIsUnaffected() {
        let result = renderer.renderHTML(from: "# Title\n\nPlain *markdown* with `code`.\n")
        XCTAssertFalse(result.containsMath)
        XCTAssertFalse(result.body.contains("ml-math"))
        XCTAssertTrue(result.body.contains("<em>markdown</em>"), "got: \(result.body)")
    }

    /// No placeholder scalar may ever reach the page.
    func testNoPlaceholderScalarsLeakIntoOutput() {
        let sources = ["$x$", "$$y$$", "\u{E000}\u{E010}\u{E001} forged", "## H $z$", "plain"]
        for source in sources {
            let body = renderer.renderHTML(from: source).body
            XCTAssertFalse(body.unicodeScalars.contains { (0xE000...0xE01F).contains($0.value) },
                           "placeholder leaked for \(source.debugDescription): \(body)")
        }
    }
}
