import XCTest
@testable import MarklensCore

final class LinkResolutionTests: XCTestCase {
    private let renderer = MarkdownRenderer()
    private let docDir = URL(fileURLWithPath: "/Users/me/notes", isDirectory: true)

    // MARK: Relative link rewriting

    func testRelativeLinkResolvesAgainstDocumentDirectory() {
        let html = renderer.renderHTML(from: "[Other](./other.md)", baseDirectory: docDir).body
        XCTAssertTrue(html.contains("href=\"file:///Users/me/notes/other.md\""), html)
    }

    func testParentRelativeLinkResolves() {
        let html = renderer.renderHTML(from: "[Up](../README.md)", baseDirectory: docDir).body
        XCTAssertTrue(html.contains("href=\"file:///Users/me/README.md\""), html)
    }

    func testBareRelativeLinkResolves() {
        let html = renderer.renderHTML(from: "[Guide](docs/guide.md)", baseDirectory: docDir).body
        XCTAssertTrue(html.contains("href=\"file:///Users/me/notes/docs/guide.md\""), html)
    }

    func testRelativeLinkWithFragmentKeepsFragment() {
        let html = renderer.renderHTML(from: "[Sec](other.md#intro)", baseDirectory: docDir).body
        XCTAssertTrue(html.contains("href=\"file:///Users/me/notes/other.md#intro\""), html)
    }

    func testAngleBracketedSpacePathIsPercentEncoded() {
        // CommonMark's way of writing a destination containing spaces.
        let html = renderer.renderHTML(from: "[Doc](<my notes.md>)", baseDirectory: docDir).body
        XCTAssertTrue(html.contains("href=\"file:///Users/me/notes/my%20notes.md\""), html)
    }

    func testAlreadyEncodedPathIsNotDoubleEncoded() {
        let html = renderer.renderHTML(from: "[Doc](my%20notes.md)", baseDirectory: docDir).body
        XCTAssertTrue(html.contains("href=\"file:///Users/me/notes/my%20notes.md\""), html)
    }

    func testAbsoluteLinksAreUntouched() {
        let html = renderer.renderHTML(from: "[Swift](https://swift.org)", baseDirectory: docDir).body
        XCTAssertTrue(html.contains("href=\"https://swift.org\""), html)
    }

    func testMailtoIsUntouched() {
        let html = renderer.renderHTML(from: "[Mail](mailto:a@b.com)", baseDirectory: docDir).body
        XCTAssertTrue(html.contains("href=\"mailto:a@b.com\""), html)
    }

    func testFragmentOnlyLinkIsUntouched() {
        let html = renderer.renderHTML(from: "[Top](#intro)", baseDirectory: docDir).body
        XCTAssertTrue(html.contains("href=\"#intro\""), html)
    }

    func testRelativeLinkLeftAloneWithoutBaseDirectory() {
        let html = renderer.renderHTML(from: "[Other](./other.md)").body
        XCTAssertTrue(html.contains("href=\"./other.md\""), html)
    }

    func testDangerousSchemeIsStripped() {
        let html = renderer.renderHTML(from: "[Click](javascript:alert(1))", baseDirectory: docDir).body
        XCTAssertFalse(html.lowercased().contains("javascript:"), html)
    }

    func testHrefIsAttributeEscaped() {
        let html = renderer.renderHTML(from: "[x](https://e.com/?a=1&b=\"2\")", baseDirectory: docDir).body
        XCTAssertFalse(html.contains("b=\"2\">"), "quote must not break out of href: \(html)")
    }

    // MARK: Navigation routing

    private let page = URL(string: "file:///App/Marklens.app/Contents/Resources/Web/")!
    private let bundleDir = URL(fileURLWithPath: "/App/Marklens.app", isDirectory: true)

    private func action(_ href: String) -> LinkAction {
        LinkRouter.action(for: URL(string: href, relativeTo: page)!.absoluteURL,
                          currentDocumentURL: page,
                          bundleDirectory: bundleDir)
    }

    func testInPageAnchorScrollsInsteadOfLeaving() {
        XCTAssertEqual(action("#getting-started"), .allowInPage)
    }

    func testHTTPLinkOpensExternally() {
        XCTAssertEqual(action("https://swift.org"), .openExternally(URL(string: "https://swift.org")!))
    }

    func testMailtoOpensExternally() {
        XCTAssertEqual(action("mailto:a@b.com"), .openExternally(URL(string: "mailto:a@b.com")!))
    }

    func testResolvedFileLinkOpensFile() {
        let target = URL(string: "file:///Users/me/notes/other.md")!
        XCTAssertEqual(action("file:///Users/me/notes/other.md"), .openFile(target))
    }

    func testUnresolvedRelativeLinkIntoAppBundleIsBlocked() {
        // No document directory known → WebKit resolves against our bundled
        // Web/ dir. Never hand app-bundle paths to LaunchServices.
        XCTAssertEqual(action("./other.md"), .block)
        XCTAssertEqual(action("../../../README.md"), .block)
    }

    func testJavaScriptURLIsBlocked() {
        XCTAssertEqual(
            LinkRouter.action(for: URL(string: "javascript:alert(1)")!,
                              currentDocumentURL: page,
                              bundleDirectory: bundleDir),
            .block
        )
    }

    func testUnknownSchemeIsBlocked() {
        XCTAssertEqual(
            LinkRouter.action(for: URL(string: "ftp://example.com/x")!,
                              currentDocumentURL: page,
                              bundleDirectory: bundleDir),
            .block
        )
    }

    func testFragmentOnDifferentDocumentOpensThatDocumentWithoutFragment() {
        // LaunchServices has no use for the fragment.
        let target = URL(string: "file:///Users/me/notes/other.md")!
        XCTAssertEqual(action("file:///Users/me/notes/other.md#intro"), .openFile(target))
    }
}

extension LinkResolutionTests {
    private var bundle: URL { URL(fileURLWithPath: "/App/Marklens.app", isDirectory: true) }

    func testTemplateLoadIsRecognised() {
        let base = URL(string: "file:///App/Marklens.app/Contents/Resources/Web/")!
        XCTAssertTrue(LinkRouter.isTemplateLoad(base, bundleDirectory: bundle))
        XCTAssertTrue(LinkRouter.isTemplateLoad(URL(string: "about:blank")!, bundleDirectory: bundle))
    }

    func testUserDocumentIsNotATemplateLoad() {
        let doc = URL(string: "file:///Users/me/notes/other.md")!
        XCTAssertFalse(LinkRouter.isTemplateLoad(doc, bundleDirectory: bundle))
    }

    func testSiblingDirectoryIsNotTreatedAsInsideBundle() {
        // "/App/Marklens.app.backup" must not count as inside "/App/Marklens.app".
        let sibling = URL(string: "file:///App/Marklens.app.backup/x.md")!
        XCTAssertFalse(LinkRouter.isTemplateLoad(sibling, bundleDirectory: bundle))
    }
}
