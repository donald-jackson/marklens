import XCTest
@testable import MarklensCore

final class HeadingAnchorTests: XCTestCase {
    private let renderer = MarkdownRenderer()

    // MARK: Slugs

    func testSlugMatchesGitHubConventions() {
        XCTAssertEqual(HeadingSlug.slug(for: "Getting Started"), "getting-started")
        XCTAssertEqual(HeadingSlug.slug(for: "API Reference"), "api-reference")
        XCTAssertEqual(HeadingSlug.slug(for: "What's New?"), "whats-new")
        XCTAssertEqual(HeadingSlug.slug(for: "C++ & Rust"), "c--rust")
        XCTAssertEqual(HeadingSlug.slug(for: "  Padded  "), "padded")
        XCTAssertEqual(HeadingSlug.slug(for: "snake_case kept"), "snake_case-kept")
        XCTAssertEqual(HeadingSlug.slug(for: "Ünïcode Wörks"), "ünïcode-wörks")
    }

    func testEmptySlugFallsBackToSection() {
        XCTAssertEqual(HeadingSlug.slug(for: "!!!"), "section")
    }

    // MARK: Injection

    func testHeadingsGetIDs() {
        let html = renderer.renderHTML(from: "# My Doc\n\n## Getting Started\n\ntext").body
        XCTAssertTrue(html.contains("<h1 id=\"my-doc\">My Doc</h1>"), html)
        XCTAssertTrue(html.contains("<h2 id=\"getting-started\">Getting Started</h2>"), html)
    }

    func testDuplicateHeadingsGetUniqueIDs() {
        let html = renderer.renderHTML(from: "## Notes\n\n## Notes\n\n## Notes").body
        XCTAssertTrue(html.contains("<h2 id=\"notes\">"), html)
        XCTAssertTrue(html.contains("<h2 id=\"notes-1\">"), html)
        XCTAssertTrue(html.contains("<h2 id=\"notes-2\">"), html)
    }

    func testTableOfContentsLinksHaveMatchingTargets() {
        let src = """
        # Doc

        - [Getting Started](#getting-started)
        - [API Reference](#api-reference)

        ## Getting Started

        ## API Reference
        """
        let html = renderer.renderHTML(from: src).body
        for slug in ["getting-started", "api-reference"] {
            XCTAssertTrue(html.contains("href=\"#\(slug)\""), "missing link for \(slug): \(html)")
            XCTAssertTrue(html.contains("id=\"\(slug)\""), "missing target for \(slug): \(html)")
        }
    }

    func testHeadingIDsAreHTMLSafe() {
        let html = renderer.renderHTML(from: "## a\"b<c>").body
        XCTAssertFalse(html.contains("id=\"a\"b"), "id attribute must not break out: \(html)")
    }

    func testMermaidBlocksStillWorkAlongsideHeadings() {
        let src = """
        ## Diagram

        ```mermaid
        graph TD; A-->B
        ```
        """
        let result = renderer.renderHTML(from: src)
        XCTAssertTrue(result.containsMermaid)
        XCTAssertTrue(result.body.contains("<h2 id=\"diagram\">Diagram</h2>"), result.body)
        XCTAssertTrue(result.body.contains("<div class=\"mermaid\">"), result.body)
        XCTAssertTrue(result.body.contains("A-->B"), result.body)
    }
}
