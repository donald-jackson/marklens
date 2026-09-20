import XCTest
@testable import MarklensCore

/// Unit tests for the source scanner alone. Failures here are far easier to
/// read than the same bug seen through a full HTML render.
final class MathExtractorTests: XCTestCase {

    private func extract(_ source: String,
                         delimiters: MathDelimiters = .standard) -> MathExtraction {
        MathExtractor.extract(from: source, delimiters: delimiters)
    }

    private func latex(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        extract(source).spans.map(\.latex)
    }

    // MARK: Happy path

    func testInlineMath() {
        let result = extract("Let $x + 1$ be")
        XCTAssertEqual(result.spans, [MathSpan(latex: "x + 1", isDisplay: false)])
        XCTAssertEqual(MathPlaceholder.describing(result.source), "Let ⟦math 0⟧ be")
    }

    func testDisplayMath() {
        let result = extract("$$a = b$$")
        XCTAssertEqual(result.spans, [MathSpan(latex: "a = b", isDisplay: true)])
    }

    func testTheZARCase() {
        let result = extract(#"$$\mathbf{ZAR\ 5,000,000.00}$$"#)
        XCTAssertEqual(result.spans,
                       [MathSpan(latex: #"\mathbf{ZAR\ 5,000,000.00}"#, isDisplay: true)])
    }

    func testDisplayMathSpanningBlankLines() {
        let result = extract("$$\n\na = 1\n\n$$")
        XCTAssertEqual(result.spans.count, 1)
        XCTAssertEqual(result.spans.first?.isDisplay, true)
        XCTAssertEqual(result.spans.first?.latex, "\n\na = 1\n\n")
    }

    func testMultipleSpansNumberedInOrder() {
        let result = extract("$a$ then $$b$$ then $c$")
        XCTAssertEqual(result.spans.map(\.latex), ["a", "b", "c"])
        XCTAssertEqual(result.spans.map(\.isDisplay), [false, true, false])
        XCTAssertEqual(MathPlaceholder.describing(result.source),
                       "⟦math 0⟧ then ⟦math 1⟧ then ⟦math 2⟧")
    }

    func testTenSpansUseMultiDigitTokens() {
        let source = (0..<12).map { "$x\($0)$" }.joined(separator: " ")
        let result = extract(source)
        XCTAssertEqual(result.spans.count, 12)
        XCTAssertEqual(result.spans.last?.latex, "x11")
        XCTAssertTrue(MathPlaceholder.describing(result.source).hasSuffix("⟦math 11⟧"))
    }

    // MARK: LaTeX that CommonMark would otherwise destroy

    func testUnderscoresAndAsterisksSurvive() {
        XCTAssertEqual(latex("$a_1 + b_2$"), ["a_1 + b_2"])
        XCTAssertEqual(latex("$a*b*c$"), ["a*b*c"])
    }

    func testBackslashEscapesSurvive() {
        XCTAssertEqual(latex(#"$\{x\} \\ \_y$"#), [#"\{x\} \\ \_y"#])
    }

    func testSmartPunctuationCandidatesSurvive() {
        XCTAssertEqual(latex("$a -- b$"), ["a -- b"])
        XCTAssertEqual(latex(#"$\text{"q"}$"#), [#"\text{"q"}"#])
    }

    func testEscapedDollarIsNotADelimiter() {
        XCTAssertTrue(extract(#"\$x\$"#).spans.isEmpty)
    }

    func testDoubleBackslashDoesNotEatTheDelimiter() {
        XCTAssertEqual(latex(#"$\\$"#), [#"\\"#])
    }

    // MARK: Code must never be treated as math

    func testBacktickFence() {
        XCTAssertTrue(extract("```\n$$x$$\n```").spans.isEmpty)
    }

    func testTildeFence() {
        XCTAssertTrue(extract("~~~\n$x$\n~~~").spans.isEmpty)
    }

    func testFenceWithInfoString() {
        XCTAssertTrue(extract("````latex\n$$x$$\n````").spans.isEmpty)
    }

    func testShorterInnerFenceDoesNotCloseOuterFence() {
        XCTAssertTrue(extract("````\n```\n$x$\n````").spans.isEmpty)
    }

    func testTildeFenceIsNotClosedByBacktickFence() {
        XCTAssertTrue(extract("~~~\n```\n$x$\n~~~").spans.isEmpty)
    }

    func testIndentedCodeBlock() {
        XCTAssertTrue(extract("text\n\n    $$x$$\n").spans.isEmpty)
    }

    func testIndentedCodeDoesNotSwallowFollowingParagraph() {
        XCTAssertEqual(latex("text\n\n    code\n\nthen $x$ here"), ["x"])
    }

    func testInlineCodeSpan() {
        XCTAssertTrue(extract("`$x$`").spans.isEmpty)
    }

    func testDoubleBacktickCodeSpan() {
        XCTAssertTrue(extract("``a $x$ b``").spans.isEmpty)
    }

    func testSingleBacktickDoesNotCloseDoubleBacktickSpan() {
        XCTAssertTrue(extract("``$x$ ` more``").spans.isEmpty)
    }

    /// The inverse guard: an unmatched backtick is literal text, so a scanner
    /// that skips to end-of-chunk on it would silently lose real math.
    func testUnmatchedBacktickDoesNotSwallowMath() {
        XCTAssertEqual(latex("a ` b $x$"), ["x"])
    }

    func testFenceInterruptsADisplayCandidate() {
        XCTAssertTrue(extract("$$\n```\nx\n```\n$$").spans.isEmpty)
    }

    // MARK: Currency must not be read as math

    func testCurrencyPairIsNotMath() {
        let result = extract("Costs $5 and $10 today.")
        XCTAssertTrue(result.spans.isEmpty, "got: \(result.spans)")
        XCTAssertEqual(result.source, "Costs $5 and $10 today.")
    }

    func testCurrencyAdjacentIsNotMath() {
        XCTAssertTrue(extract("$5 and$10").spans.isEmpty)
    }

    func testOpeningDollarFollowedBySpaceIsNotMath() {
        XCTAssertTrue(extract("$ x $").spans.isEmpty)
    }

    func testCurrencyThenRealMath() {
        let result = extract("It costs $5. Also $x+y$ holds.")
        XCTAssertEqual(result.spans.map(\.latex), ["x+y"])
        XCTAssertTrue(result.source.contains("$5."), "got: \(result.source)")
    }

    /// The cheaper fix for greedy matching — "an opening `$` may not be
    /// followed by a digit" — would have cost this.
    func testFormulaStartingWithADigitStillWorks() {
        XCTAssertEqual(latex("$5x + 1$"), ["5x + 1"])
    }

    func testUnescapedDollarInsideACandidateAbandonsIt() {
        XCTAssertTrue(extract("$a $ b$").spans.isEmpty)
    }

    func testEscapedDollarInsideMathIsFine() {
        XCTAssertEqual(latex(#"$a \$ b$"#), [#"a \$ b"#])
    }

    func testUnclosedInlineDollarIsLiteral() {
        XCTAssertTrue(extract("The cost is $x and nothing else").spans.isEmpty)
    }

    func testUnclosedDisplayDollarsAreLiteral() {
        XCTAssertTrue(extract("$$x with no close").spans.isEmpty)
    }

    func testInlineMathDoesNotCrossABlankLine() {
        XCTAssertTrue(extract("a $x\n\ny$ b").spans.isEmpty)
    }

    func testInlineMathMayCrossASingleNewline() {
        XCTAssertEqual(latex("a $x +\ny$ b"), ["x +\ny"])
    }

    func testEmptyDelimitersAreLiteral() {
        XCTAssertTrue(extract("$$$$").spans.isEmpty)
        XCTAssertTrue(extract("$$ $$").spans.isEmpty)
    }

    // MARK: Placeholder integrity

    func testReservedScalarsInSourceAreStripped() {
        let forged = "\u{E000}\u{E010}\u{E001} and $x$"
        let result = extract(forged)
        XCTAssertEqual(result.spans.count, 1)
        XCTAssertEqual(MathPlaceholder.describing(result.source), " and ⟦math 0⟧")
    }

    func testSourceWithoutMathIsReturnedUnchanged() {
        let source = "# Title\n\nPlain _markdown_ with `code`.\n"
        let result = extract(source)
        XCTAssertFalse(result.containsMath)
        XCTAssertEqual(result.source, source)
    }

    // MARK: Opt-in delimiters

    func testParenBracketDelimitersAreOffByDefault() {
        XCTAssertTrue(extract(#"\(x\) and \[y\]"#).spans.isEmpty)
    }

    func testParenBracketDelimitersWhenEnabled() {
        let result = extract(#"\(x\) and \[y\]"#, delimiters: [.dollar, .parenBracket])
        XCTAssertEqual(result.spans, [MathSpan(latex: "x", isDisplay: false),
                                      MathSpan(latex: "y", isDisplay: true)])
    }
}
