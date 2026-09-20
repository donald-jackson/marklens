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
}

struct MathExtraction {
    /// The source with every span replaced by a placeholder token.
    let source: String
    /// Spans in document order; a token's decoded value indexes into this.
    let spans: [MathSpan]

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
        // Strip the placeholder range first so a document can't forge a token.
        let sanitized = MathPlaceholder.stripReserved(from: source)

        let hasCandidate = (delimiters.contains(.dollar) && sanitized.contains("$"))
            || (delimiters.contains(.parenBracket) && sanitized.contains("\\"))
        guard hasCandidate else { return MathExtraction(source: sanitized, spans: []) }

        var spans: [MathSpan] = []
        var out = ""
        out.reserveCapacity(sanitized.count)

        // Eligible lines are grouped into maximal runs. Display math may span
        // lines within a chunk but never across one, so a fence or indented
        // block in the middle of a candidate simply terminates it.
        for chunk in eligibleChunks(of: sanitized) {
            switch chunk {
            case .skipped(let text):
                out.append(contentsOf: text)
            case .scannable(let text):
                scan(text, delimiters: delimiters, spans: &spans, into: &out)
            }
        }

        return MathExtraction(source: out, spans: spans)
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
            let line = dropTerminator(rawLine)
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
                             spans: inout [MathSpan],
                             into out: inout String) {
        let chars = Array(chunk)
        var literalStart = 0
        var i = 0

        func emit(latex: String, isDisplay: Bool, from start: Int, to end: Int) {
            out.append(contentsOf: chars[literalStart..<start])
            out.append(MathPlaceholder.token(for: spans.count))
            spans.append(MathSpan(latex: latex, isDisplay: isDisplay))
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
                // A code span is opaque. A run with no equal-length partner is
                // literal text, so keep scanning past it — `` a ` b $x$ `` is
                // math.
                var run = 0
                var j = i
                while j < chars.count, chars[j] == "`" {
                    run += 1
                    j += 1
                }
                i = findBacktickRun(chars, from: j, length: run).map { $0 + run } ?? j
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
                i += 2
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
