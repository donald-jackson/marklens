import XCTest
@testable import MarklensCore

/// Unit tests for the source scanner alone. Failures here are far easier to
/// read than the same bug seen through a full HTML render.
final class MathExtractorTests: XCTestCase {

    private func extract(_ source: String,
                         delimiters: MathDelimiters = .standard) -> MathExtraction {
        MathExtractor.extract(from: source, delimiters: delimiters)
    }

    private func latex(_ source: String) -> [String] {
        extract(source).spans.map(\.latex)
    }

    private func described(_ result: MathExtraction) -> String {
        result.placeholder.describing(result.source)
    }

    // MARK: Happy path

    func testInlineMath() {
        let result = extract("Let $x + 1$ be")
        XCTAssertEqual(result.spans, [MathSpan(latex: "x + 1", isDisplay: false, raw: "$x + 1$")])
        XCTAssertEqual(described(result), "Let ⟦math 0⟧ be")
    }

    func testDisplayMath() {
        let result = extract("$$a = b$$")
        XCTAssertEqual(result.spans, [MathSpan(latex: "a = b", isDisplay: true, raw: "$$a = b$$")])
    }

    func testTheZARCase() {
        let result = extract(#"$$\mathbf{ZAR\ 5,000,000.00}$$"#)
        XCTAssertEqual(result.spans,
                       [MathSpan(latex: #"\mathbf{ZAR\ 5,000,000.00}"#,
                                 isDisplay: true,
                                 raw: #"$$\mathbf{ZAR\ 5,000,000.00}$$"#)])
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
        XCTAssertEqual(described(result), "⟦math 0⟧ then ⟦math 1⟧ then ⟦math 2⟧")
    }

    func testTenSpansUseMultiDigitTokens() {
        let source = (0..<12).map { "$x\($0)$" }.joined(separator: " ")
        let result = extract(source)
        XCTAssertEqual(result.spans.count, 12)
        XCTAssertEqual(result.spans.last?.latex, "x11")
        XCTAssertTrue(described(result).hasSuffix("⟦math 11⟧"))
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

    /// A candidate that opens in prose must not close on a dollar inside a
    /// code span — that silently eats the span.
    func testCloseSearchSkipsCodeSpans() {
        let result = extract("It costs $5; use `price$` literally.")
        XCTAssertTrue(result.spans.isEmpty, "got: \(result.spans)")
        XCTAssertEqual(result.source, "It costs $5; use `price$` literally.")
    }

    func testDisplayCloseSearchSkipsCodeSpans() {
        XCTAssertTrue(extract("Cost $$5 and use `a$$b` here").spans.isEmpty)
    }

    /// A backslash before the first newline of a blank line still ends a line.
    func testEscapedNewlineStillEndsTheLine() {
        XCTAssertTrue(extract("a $x\\\n\ny$ b").spans.isEmpty)
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

    /// Private Use Area scalars are legitimate content — icon fonts live
    /// there — so a document must never lose them, with or without math.
    func testPrivateUseScalarsInSourceAredPreserved() {
        let forged = "\u{E000}\u{E010}\u{E001} icon \u{E0A0} and $x$"
        let result = extract(forged)
        XCTAssertEqual(result.spans.count, 1)
        for scalar: UInt32 in [0xE000, 0xE010, 0xE001, 0xE0A0] {
            XCTAssertTrue(result.source.unicodeScalars.contains { $0.value == scalar },
                          "lost U+\(String(scalar, radix: 16, uppercase: true))")
        }
    }

    func testPlaceholderAvoidsScalarsTheDocumentUses() {
        let crowded = String(String.UnicodeScalarView((0xE000...0xE04F).map { Unicode.Scalar($0)! }))
        let result = extract(crowded + " $x$")
        XCTAssertEqual(result.spans.map(\.latex), ["x"])
        XCTAssertEqual(described(result).hasSuffix("⟦math 0⟧"), true)
        for scalar in 0xE000...0xE04F {
            XCTAssertTrue(result.source.unicodeScalars.contains { $0.value == UInt32(scalar) },
                          "lost U+\(String(scalar, radix: 16, uppercase: true))")
        }
    }

    func testSourceWithoutMathIsReturnedUnchanged() {
        let source = "# Title\n\nPlain _markdown_ with `code`. Icon \u{E005}.\n"
        let result = extract(source)
        XCTAssertFalse(result.containsMath)
        XCTAssertEqual(result.source, source)
    }

    // MARK: Markdown containers

    /// `>     $$x$$` is an indented code block inside a quote. Judged from the
    /// raw line start it looks like prose.
    func testIndentedCodeInsideABlockquoteIsNotMath() {
        XCTAssertTrue(extract("> quote\n>\n>     $$x$$\n").spans.isEmpty)
    }

    func testFencedCodeInsideABlockquoteIsNotMath() {
        XCTAssertTrue(extract("> ~~~\n> $x$\n> ~~~\n").spans.isEmpty)
    }

    func testNestedBlockquoteFenceIsNotMath() {
        XCTAssertTrue(extract("> > ```\n> > $x$\n> > ```\n").spans.isEmpty)
    }

    func testOrdinaryBlockquoteProseStillGetsMath() {
        XCTAssertEqual(latex("> a quote with $x$ in it"), ["x"])
    }

    // MARK: Opt-in delimiters

    func testParenBracketDelimitersAreOffByDefault() {
        XCTAssertTrue(extract(#"\(x\) and \[y\]"#).spans.isEmpty)
    }

    func testParenBracketDelimitersWhenEnabled() {
        let result = extract(#"\(x\) and \[y\]"#, delimiters: [.dollar, .parenBracket])
        XCTAssertEqual(result.spans, [MathSpan(latex: "x", isDisplay: false, raw: #"\(x\)"#),
                                      MathSpan(latex: "y", isDisplay: true, raw: #"\[y\]"#)])
    }
}
