import XCTest
@testable import MarklensCore

final class RelativeReferenceRewriterTests: XCTestCase {
    func testRelativeImageSrcIsRewritten() {
        let html = #"<img src="diagram.png" />"#
        let result = RelativeReferenceRewriter.rewrite(html)
        XCTAssertEqual(result, #"<img src="marklens-asset:///diagram.png" />"#)
    }

    func testRelativeLinkHrefIsRewritten() {
        let html = #"<a href="Notes.md">Notes</a>"#
        let result = RelativeReferenceRewriter.rewrite(html)
        XCTAssertEqual(result, #"<a href="marklens-asset:///Notes.md">Notes</a>"#)
    }

    func testNestedRelativePathIsRewritten() {
        let html = #"<img src="images/diagram.png" />"#
        let result = RelativeReferenceRewriter.rewrite(html)
        XCTAssertEqual(result, #"<img src="marklens-asset:///images/diagram.png" />"#)
    }

    func testAbsoluteHTTPURLsAreLeftAlone() {
        let html = #"<a href="https://example.com">Ext</a><img src="http://example.com/a.png" />"#
        let result = RelativeReferenceRewriter.rewrite(html)
        XCTAssertEqual(result, html)
    }

    func testAnchorLinksAreLeftAlone() {
        let html = ##"<a href="#section">Anchor</a>"##
        XCTAssertEqual(RelativeReferenceRewriter.rewrite(html), html)
    }

    func testAbsolutePathsAreLeftAlone() {
        let html = #"<img src="/abs/path.png" />"#
        XCTAssertEqual(RelativeReferenceRewriter.rewrite(html), html)
    }

    func testProtocolRelativeURLsAreLeftAlone() {
        let html = #"<img src="//cdn.example.com/a.png" />"#
        XCTAssertEqual(RelativeReferenceRewriter.rewrite(html), html)
    }

    func testDataURIsAreLeftAlone() {
        let html = #"<img src="data:image/png;base64,AAAA" />"#
        XCTAssertEqual(RelativeReferenceRewriter.rewrite(html), html)
    }

    func testMailtoLinksAreLeftAlone() {
        let html = #"<a href="mailto:a@b.com">Email</a>"#
        XCTAssertEqual(RelativeReferenceRewriter.rewrite(html), html)
    }

    func testAlreadyRewrittenReferencesAreNotDoubleRewritten() {
        let html = #"<img src="marklens-asset:///diagram.png" />"#
        XCTAssertEqual(RelativeReferenceRewriter.rewrite(html), html)
    }

    func testEndToEndThroughMarkdownRenderer() {
        let src = "![Diagram](diagram.png)\n\n[Notes](Notes.md)\n\n[External](https://example.com)"
        let body = MarkdownRenderer().renderHTML(from: src).body
        XCTAssertTrue(body.contains(#"src="marklens-asset:///diagram.png""#), body)
        XCTAssertTrue(body.contains(#"href="marklens-asset:///Notes.md""#), body)
        XCTAssertTrue(body.contains(#"href="https://example.com""#), body)
    }
}

final class DocumentAssetResolverTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/tmp/doc-folder")

    func testRelativeReferenceExtractsPathFromAssetURL() {
        let url = URL(string: "marklens-asset:///diagram.png")!
        XCTAssertEqual(DocumentAssetResolver.relativeReference(from: url), "diagram.png")
    }

    func testRelativeReferenceExtractsNestedPath() {
        let url = URL(string: "marklens-asset:///images/diagram.png")!
        XCTAssertEqual(DocumentAssetResolver.relativeReference(from: url), "images/diagram.png")
    }

    func testRelativeReferenceDecodesPercentEncoding() {
        let url = URL(string: "marklens-asset:///my%20image.png")!
        XCTAssertEqual(DocumentAssetResolver.relativeReference(from: url), "my image.png")
    }

    func testRelativeReferenceReturnsNilForOtherSchemes() {
        let url = URL(string: "https:///diagram.png")!
        XCTAssertNil(DocumentAssetResolver.relativeReference(from: url))
    }

    func testResolveJoinsReferenceWithFolder() {
        let resolved = DocumentAssetResolver.resolve("diagram.png", in: folder)
        XCTAssertEqual(resolved?.path, "/tmp/doc-folder/diagram.png")
    }

    func testResolveJoinsNestedReferenceWithFolder() {
        let resolved = DocumentAssetResolver.resolve("images/diagram.png", in: folder)
        XCTAssertEqual(resolved?.path, "/tmp/doc-folder/images/diagram.png")
    }

    func testResolveRejectsPathTraversalEscapingFolder() {
        XCTAssertNil(DocumentAssetResolver.resolve("../secret.txt", in: folder))
        XCTAssertNil(DocumentAssetResolver.resolve("../../etc/passwd", in: folder))
    }

    func testResolveRejectsSiblingFolderPrefixCollision() {
        // "doc-folder-evil" starts with the same string prefix as "doc-folder"
        // but is not the same directory — must not be treated as contained.
        XCTAssertNil(DocumentAssetResolver.resolve("../doc-folder-evil/secret.txt", in: folder))
    }
}
