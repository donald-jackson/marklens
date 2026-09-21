import XCTest
@testable import MarklensCore

final class HTMLTemplateTests: XCTestCase {

    func testKatexIsOmittedWhenThereIsNoMath() {
        let page = HTMLTemplate.page(body: "<p>hi</p>", containsMermaid: false, containsMath: false)
        XCTAssertFalse(page.contains("katex.min.js"), "KaTeX should not load for a math-free document")
        XCTAssertFalse(page.contains("katex.min.css"))
        XCTAssertFalse(page.contains("katex.render"))
    }

    func testKatexIsIncludedWhenThereIsMath() {
        let page = HTMLTemplate.page(body: "<p>hi</p>", containsMermaid: false, containsMath: true)
        XCTAssertTrue(page.contains("<script src=\"katex.min.js\" defer></script>"), "got: \(page)")
        XCTAssertTrue(page.contains("<link rel=\"stylesheet\" href=\"katex.min.css\">"), "got: \(page)")
        XCTAssertTrue(page.contains("katex.render"), "got: \(page)")
    }

    /// KaTeX's stylesheet must come first so the overrides in styles.css win on
    /// document order rather than specificity.
    func testKatexStylesheetPrecedesOurs() {
        let page = HTMLTemplate.page(body: "", containsMermaid: false, containsMath: true)
        guard let katex = page.range(of: "katex.min.css"),
              let ours = page.range(of: "styles.css") else {
            return XCTFail("Expected both stylesheets, got: \(page)")
        }
        XCTAssertTrue(katex.lowerBound < ours.lowerBound, "got: \(page)")
    }

    /// `containsMath` is defaulted, so the pre-change argument list still
    /// compiles and still produces a KaTeX-free page.
    func testContainsMathDefaultsToFalse() {
        let page = HTMLTemplate.page(body: "<p>hi</p>", containsMermaid: false, dark: true)
        XCTAssertFalse(page.contains("katex"))
        XCTAssertTrue(page.contains("data-theme=\"dark\""))
    }

    func testMermaidIsUnaffectedByTheNewParameter() {
        let page = HTMLTemplate.page(body: "", containsMermaid: true, containsMath: true)
        XCTAssertTrue(page.contains("mermaid.min.js"))
        XCTAssertTrue(page.contains("katex.min.js"))
    }
}
