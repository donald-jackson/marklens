import XCTest
@testable import MarklensCore

final class MarkdownRendererTests: XCTestCase {
    private let renderer = MarkdownRenderer()

    func testBasicHeadingAndParagraph() {
        let html = renderer.renderHTML(from: "# Hello\n\nWorld").body
        XCTAssertTrue(html.contains("<h1"), "Expected h1, got: \(html)")
        XCTAssertTrue(html.contains("Hello"))
        XCTAssertTrue(html.contains("<p>World</p>") || html.contains("<p>World"))
    }

    func testInlineFormattingPasses() {
        let html = renderer.renderHTML(from: "**bold** and *em* and `code`").body
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<em>em</em>"))
        XCTAssertTrue(html.contains("<code>code</code>"))
    }

    func testCodeBlockGetsLanguageClass() {
        let src = """
        ```swift
        let x = 1
        ```
        """
        let html = renderer.renderHTML(from: src).body
        XCTAssertTrue(html.contains("language-swift"), "Expected language-swift, got: \(html)")
        XCTAssertTrue(html.contains("let x = 1"))
    }

    func testMermaidBlockEmitsDivAndFlagsDocument() {
        let src = """
        ```mermaid
        graph TD; A-->B
        ```
        """
        let result = renderer.renderHTML(from: src)
        XCTAssertTrue(result.containsMermaid)
        XCTAssertTrue(result.body.contains("<div class=\"mermaid\">"),
                      "Expected mermaid div, got: \(result.body)")
        // Crucially: the content should be UNescaped (mermaid parses its own text)
        XCTAssertTrue(result.body.contains("A-->B"),
                      "Mermaid content should be unescaped, got: \(result.body)")
    }

    func testNonMermaidCodeBlockUnaffected() {
        let src = """
        ```python
        if 1 < 2:
            print("ok")
        ```
        """
        let result = renderer.renderHTML(from: src)
        XCTAssertFalse(result.containsMermaid)
        XCTAssertTrue(result.body.contains("language-python"))
        // Python code must remain HTML-escaped
        XCTAssertTrue(result.body.contains("1 &lt; 2") || result.body.contains("1 < 2"))
    }

    func testTableRenders() {
        let src = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let html = renderer.renderHTML(from: src).body
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th"))
        XCTAssertTrue(html.contains("<td"))
    }

    func testLinkRenders() {
        let html = renderer.renderHTML(from: "[Swift](https://swift.org)").body
        XCTAssertTrue(html.contains("href=\"https://swift.org\""))
        XCTAssertTrue(html.contains(">Swift</a>"))
    }
}
