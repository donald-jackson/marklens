import Foundation

/// A LaTeX formula lifted out of the markdown source *before* it is parsed.
///
/// This has to happen before `Document(parsing:)` because CommonMark destroys
/// LaTeX on contact: `\_`, `\*`, `\{` and `\\` are consumed as escapes, `_x_`
/// becomes `<em>`, and smart punctuation (on by default — `MarkdownRenderer`
/// never passes `.disableSmartOpts`) turns `--` into an en dash and `"` into
/// curly quotes. By the time there is a DOM to walk, the formula is gone.
struct MathSpan: Equatable {
    let latex: String
    let isDisplay: Bool
    /// The matched source text, delimiters included. Used where a formula
    /// turns out to sit somewhere markup can't take an element — a link
    /// destination, say — and the original text has to go back instead.
    let raw: String
}

struct MathExtraction {
    /// The source with every span replaced by a placeholder token.
    let source: String
    /// Spans in document order; a token's decoded value indexes into this.
    let spans: [MathSpan]
    /// The scalars this document's tokens were built from.
    let placeholder: MathPlaceholder

    var containsMath: Bool { !spans.isEmpty }
}

/// Which delimiters the scanner recognises.
///
/// Only `.dollar` ships. `\[…\]` collides with a legitimate markdown idiom —
/// escaping brackets so they aren't read as link syntax (`see \[note 3\]`) —
/// which would turn ordinary prose into display math for someone who has never
/// written LaTeX. Enabling it is a caller-side choice, not a default.
struct MathDelimiters: OptionSet {
    let rawValue: Int

    static let dollar = MathDelimiters(rawValue: 1 << 0)
    static let parenBracket = MathDelimiters(rawValue: 1 << 1)

    static let standard: MathDelimiters = [.dollar]
}

enum MathExtractor {
    static func extract(from source: String,
                        delimiters: MathDelimiters = .standard) -> MathExtraction {
        let hasCandidate = (delimiters.contains(.dollar) && source.contains("$"))
            || (delimiters.contains(.parenBracket) && source.contains("\\"))
        // Tokens are built from scalars this document doesn't use, so nothing
        // has to be stripped out of it to keep them unforgeable. If there is
        // no free run — which would take a document occupying the whole
        // Private Use Area — leave it alone rather than damage it.
        guard hasCandidate, let placeholder = MathPlaceholder.unused(in: source) else {
            return MathExtraction(source: source, spans: [], placeholder: .unusedDefault)
        }

        var spans: [MathSpan] = []
        var out = ""
        out.reserveCapacity(source.count)

        // Eligible lines are grouped into maximal runs. Display math may span
        // lines within a chunk but never across one, so a fence or indented
        // block in the middle of a candidate simply terminates it.
        for chunk in eligibleChunks(of: source) {
            switch chunk {
            case .skipped(let text):
                out.append(contentsOf: text)
            case .scannable(let text):
                scan(text, delimiters: delimiters, placeholder: placeholder,
                     spans: &spans, into: &out)
            }
        }

        return MathExtraction(source: out, spans: spans, placeholder: placeholder)
    }

    // MARK: Phase 1 — line classification

    private enum Chunk {
        case scannable(Substring)
        case skipped(Substring)
    }

    /// Splits the source into runs of lines that may hold math and runs that
    /// may not (fenced and indented code).
    private static func eligibleChunks(of source: String) -> [Chunk] {
        let lines = splitLines(source)
        guard !lines.isEmpty else { return [] }

        var eligible = [Bool](repeating: true, count: lines.count)
        var openFence: (char: Character, count: Int)?
        var inIndentedCode = false
        var previousBlank = true

        for (n, rawLine) in lines.enumerated() {
            let line = strippingQuoteMarkers(dropTerminator(rawLine))
            let blank = line.allSatisfy { $0.isWhitespace }
            let (indent, contentStart) = indentWidth(of: line)

            if let open = openFence {
                eligible[n] = false
                if indent <= 3, let run = fenceRun(in: line, from: contentStart),
                   run.char == open.char, run.count >= open.count,
                   line[run.after...].allSatisfy({ $0.isWhitespace }) {
                    openFence = nil
                }
                previousBlank = blank
                continue
            }

            // Indented code wins over a fence opener: inside it, ``` is content.
            if inIndentedCode, blank || indent >= 4 {
                eligible[n] = false
                previousBlank = blank
                continue
            }
            inIndentedCode = false

            if indent <= 3, let run = fenceRun(in: line, from: contentStart) {
                // CommonMark: a backtick fence's info string may not contain a
                // backtick (a tilde fence's may).
                let info = line[run.after...]
                if run.char == "~" || !info.contains("`") {
                    openFence = (run.char, run.count)
                    eligible[n] = false
                    previousBlank = blank
                    continue
                }
            }

            if !blank, indent >= 4, previousBlank {
                inIndentedCode = true
                eligible[n] = false
                previousBlank = blank
                continue
            }

            eligible[n] = true
            previousBlank = blank
        }

        var chunks: [Chunk] = []
        var runStart = 0
        for n in 0...lines.count {
            let ended = n == lines.count || eligible[n] != eligible[runStart]
            guard ended, n > runStart else { continue }
            let text = lines[runStart].base[lines[runStart].startIndex..<lines[n - 1].endIndex]
            chunks.append(eligible[runStart] ? .scannable(text) : .skipped(text))
            runStart = n
        }
        return chunks
    }

    /// Lines including their terminator. `\r\n` is a single `Character` in
    /// Swift, so `isNewline` is the only correct test here.
    private static func splitLines(_ s: String) -> [Substring] {
        var lines: [Substring] = []
        var start = s.startIndex
        var i = s.startIndex
        while i < s.endIndex {
            let next = s.index(after: i)
            if s[i].isNewline {
                lines.append(s[start..<next])
                start = next
            }
            i = next
        }
        if start < s.endIndex { lines.append(s[start..<s.endIndex]) }
        return lines
    }

    /// Removes CommonMark blockquote markers so the indent and fence tests see
    /// what the block parser sees. `>     $$x$$` is an indented code block
    /// inside a quote, and `> ~~~` opens a fence there — judged from the raw
    /// line start, both look like ordinary prose.
    private static func strippingQuoteMarkers(_ line: Substring) -> Substring {
        var rest = line
        while true {
            var i = rest.startIndex
            var spaces = 0
            while i < rest.endIndex, rest[i] == " ", spaces < 3 {
                spaces += 1
                i = rest.index(after: i)
            }
            guard i < rest.endIndex, rest[i] == ">" else { return rest }
            i = rest.index(after: i)
            if i < rest.endIndex, rest[i] == " " { i = rest.index(after: i) }
            rest = rest[i...]
        }
    }

    private static func dropTerminator(_ line: Substring) -> Substring {
        guard let last = line.last, last.isNewline else { return line }
        return line.dropLast()
    }

    /// Indent in columns, tabs advancing to the next multiple of four.
    private static func indentWidth(of line: Substring) -> (width: Int, start: String.Index) {
        var width = 0
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == " " {
                width += 1
            } else if c == "\t" {
                width += 4 - (width % 4)
            } else {
                break
            }
            i = line.index(after: i)
        }
        return (width, i)
    }

    private static func fenceRun(in line: Substring,
                                 from start: String.Index) -> (char: Character, count: Int, after: String.Index)? {
        guard start < line.endIndex else { return nil }
        let c = line[start]
        guard c == "`" || c == "~" else { return nil }
        var count = 0
        var i = start
        while i < line.endIndex, line[i] == c {
            count += 1
            i = line.index(after: i)
        }
        guard count >= 3 else { return nil }
        return (c, count, i)
    }

    // MARK: Phase 2 — character scan

    private static func scan(_ chunk: Substring,
                             delimiters: MathDelimiters,
                             placeholder: MathPlaceholder,
                             spans: inout [MathSpan],
                             into out: inout String) {
        let chars = Array(chunk)
        var literalStart = 0
        var i = 0

        func emit(latex: String, isDisplay: Bool, from start: Int, to end: Int) {
            out.append(contentsOf: chars[literalStart..<start])
            out.append(placeholder.token(for: spans.count))
            spans.append(MathSpan(latex: latex,
                                  isDisplay: isDisplay,
                                  raw: String(chars[start..<end])))
            literalStart = end
            i = end
        }

        while i < chars.count {
            let c = chars[i]

            if c == "\\" {
                // `\(`/`\[` are openers when enabled; otherwise a backslash
                // always swallows the next character, which is what makes `\$`
                // literal while `\\$x$` is still math.
                if delimiters.contains(.parenBracket), i + 1 < chars.count,
                   chars[i + 1] == "(" || chars[i + 1] == "[" {
                    let isDisplay = chars[i + 1] == "["
                    let closer: Character = isDisplay ? "]" : ")"
                    if let close = findEscapedClose(chars, from: i + 2, closer: closer),
                       hasContent(chars, i + 2, close) {
                        emit(latex: String(chars[(i + 2)..<close]),
                             isDisplay: isDisplay, from: i, to: close + 2)
                        continue
                    }
                }
                i += min(2, chars.count - i)
                continue
            }

            if c == "`" {
                i = skippingCodeSpan(chars, from: i)
                continue
            }

            guard delimiters.contains(.dollar), c == "$" else {
                i += 1
                continue
            }

            if i + 1 < chars.count, chars[i + 1] == "$" {
                // `$$ x $$` is idiomatic, so display math takes no
                // non-whitespace guard — only a non-empty body.
                if let close = findDisplayClose(chars, from: i + 2),
                   hasContent(chars, i + 2, close) {
                    emit(latex: String(chars[(i + 2)..<close]),
                         isDisplay: true, from: i, to: close + 2)
                } else {
                    i += 2
                }
                continue
            }

            if let close = findInlineClose(chars, from: i + 1) {
                emit(latex: String(chars[(i + 1)..<close]),
                     isDisplay: false, from: i, to: close + 1)
            } else {
                i += 1
            }
        }

        out.append(contentsOf: chars[literalStart...])
    }

    private static func hasContent(_ chars: [Character], _ start: Int, _ end: Int) -> Bool {
        chars[start..<end].contains { !$0.isWhitespace }
    }

    /// Steps over a code span beginning at a backtick run. A run with no
    /// equal-length partner is literal text, so this lands just past the run
    /// itself and scanning continues — `` a ` b $x$ `` is math.
    ///
    /// Both close searches use this too. Without it a candidate that opens in
    /// prose can close on a dollar *inside* a code span, which silently eats
    /// the span: "It costs $5; use `price$` literally."
    private static func skippingCodeSpan(_ chars: [Character], from start: Int) -> Int {
        var run = 0
        var j = start
        while j < chars.count, chars[j] == "`" {
            run += 1
            j += 1
        }
        return findBacktickRun(chars, from: j, length: run).map { $0 + run } ?? j
    }

    /// The start of the next run of *exactly* `length` backticks — CommonMark's
    /// matching rule, which is why a longer run doesn't close a shorter one.
    private static func findBacktickRun(_ chars: [Character], from start: Int, length: Int) -> Int? {
        var i = start
        while i < chars.count {
            guard chars[i] == "`" else {
                i += 1
                continue
            }
            var j = i
            while j < chars.count, chars[j] == "`" { j += 1 }
            if j - i == length { return i }
            i = j
        }
        return nil
    }

    private static func findDisplayClose(_ chars: [Character], from start: Int) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i] == "\\" {
                i += 2
                continue
            }
            if chars[i] == "`" {
                i = skippingCodeSpan(chars, from: i)
                continue
            }
            if chars[i] == "$", i + 1 < chars.count, chars[i + 1] == "$" { return i }
            i += 1
        }
        return nil
    }

    private static func findEscapedClose(_ chars: [Character], from start: Int, closer: Character) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i] == "\\" {
                if i + 1 < chars.count, chars[i + 1] == closer { return i }
                i += 2
                continue
            }
            i += 1
        }
        return nil
    }

    /// Inline math, with the guards that keep currency out of it. The opening
    /// `$` must be followed by non-whitespace; the closing `$` must be preceded
    /// by non-whitespace and *not* followed by a digit; and the body may not
    /// contain an unescaped `$` — a `$` that fails the close guards abandons
    /// the whole candidate rather than being scanned past.
    ///
    /// That last rule is what stops `It costs $5. Also $x+y$ holds.` matching
    /// greedily from `$5` all the way to the `$` after `y`. It costs nothing
    /// real: a literal dollar inside math has to be written `\$` in TeX anyway.
    private static func findInlineClose(_ chars: [Character], from start: Int) -> Int? {
        guard start < chars.count else { return nil }
        let first = chars[start]
        guard !first.isWhitespace, first != "$" else { return nil }

        var i = start
        var newlinesSinceContent = 0

        while i < chars.count {
            let c = chars[i]

            if c == "\\" {
                // An escaped newline is still a line ending. Left uncounted, a
                // candidate can run straight through a blank line and swallow
                // the paragraph break.
                if i + 1 < chars.count, chars[i + 1].isNewline {
                    newlinesSinceContent += 1
                    if newlinesSinceContent >= 2 { return nil }
                } else {
                    newlinesSinceContent = 0
                }
                i += 2
                continue
            }
            if c == "`" {
                i = skippingCodeSpan(chars, from: i)
                newlinesSinceContent = 0
                continue
            }
            if c.isNewline {
                // A blank line ends the paragraph, and inline math can't cross
                // one. A single newline is fine — prose wraps.
                newlinesSinceContent += 1
                if newlinesSinceContent >= 2 { return nil }
                i += 1
                continue
            }
            if !c.isWhitespace { newlinesSinceContent = 0 }

            if c == "$" {
                let followedByDigit = i + 1 < chars.count
                    && chars[i + 1].isASCII && chars[i + 1].isNumber
                guard !chars[i - 1].isWhitespace, !followedByDigit else { return nil }
                return i
            }
            i += 1
        }
        return nil
    }
}
