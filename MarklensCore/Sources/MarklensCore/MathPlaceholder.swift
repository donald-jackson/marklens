import Foundation

/// The token that stands in for a formula between extraction and re-injection.
///
/// Every scalar is Private Use Area, which is what makes it survive the round
/// trip intact:
///
/// - no ASCII punctuation, so cmark sees nothing to interpret as emphasis, a
///   link, an escape or smart punctuation;
/// - no whitespace, so it always lands inside a single `Text` node and emerges
///   as one contiguous run of HTML;
/// - nothing our own HTML escaper touches.
///
/// The all-PUA digits matter for headings specifically: `HeadingSlug.slug(for:)`
/// keeps only `isLetter || isNumber || - || _`, and PUA scalars are category
/// `Co`, so the token drops out of the slug entirely. An ASCII token would leak
/// into the `id` of every heading containing math.
///
/// The scalars are chosen per document rather than fixed. A fixed range would
/// have to be scrubbed from the source to stay unforgeable, and PUA scalars are
/// legitimate content — icon fonts live there — so deleting them silently
/// damages documents that contain no math at all.
struct MathPlaceholder {
    /// Twelve consecutive scalars: open, close, then the ten digits.
    private let base: UInt32
    private static let width: UInt32 = 12

    /// Only used where no math was found and no token is ever emitted.
    static let unusedDefault = MathPlaceholder(base: 0xE000)

    private init(base: UInt32) {
        self.base = base
    }

    var open: Character { Character(Unicode.Scalar(base)!) }
    var close: Character { Character(Unicode.Scalar(base + 1)!) }
    private var digitBase: UInt32 { base + 2 }

    /// Finds a run of scalars the document doesn't already use, so a token can
    /// only ever be one we wrote. Returns nil only if the source somehow
    /// occupies the whole Private Use Area, in which case the caller should
    /// leave the document alone rather than damage it.
    static func unused(in source: String) -> MathPlaceholder? {
        let range: ClosedRange<UInt32> = 0xE000...0xF8FF
        var taken = Set<UInt32>()
        for scalar in source.unicodeScalars where range.contains(scalar.value) {
            taken.insert(scalar.value)
        }
        guard !taken.isEmpty else { return MathPlaceholder(base: range.lowerBound) }

        var candidate = range.lowerBound
        while candidate + width - 1 <= range.upperBound {
            var clash: UInt32?
            for offset in 0..<width where taken.contains(candidate + offset) {
                clash = candidate + offset
                break
            }
            guard let clash else { return MathPlaceholder(base: candidate) }
            candidate = clash + 1
        }
        return nil
    }

    func token(for index: Int) -> String {
        var token = String(open)
        for digit in String(index) {
            guard let value = digit.wholeNumberValue,
                  let scalar = Unicode.Scalar(digitBase + UInt32(value)) else { continue }
            token.unicodeScalars.append(scalar)
        }
        token.append(close)
        return token
    }

    /// Decodes the token starting at `start`, returning its span index and the
    /// position just past the closing scalar.
    func decode(at start: String.Index, in text: String) -> (index: Int, end: String.Index)? {
        var cursor = text.index(after: start)
        var value = 0
        var digits = 0

        while cursor < text.endIndex {
            let character = text[cursor]
            if character == close {
                guard digits > 0 else { return nil }
                return (value, text.index(after: cursor))
            }
            guard character.unicodeScalars.count == 1,
                  let scalar = character.unicodeScalars.first,
                  (digitBase...(digitBase + 9)).contains(scalar.value) else { return nil }
            value = value * 10 + Int(scalar.value - digitBase)
            digits += 1
            cursor = text.index(after: cursor)
        }
        return nil
    }

    /// Rewrites every token in `text`. Returning `nil` leaves one as it is.
    private func substituting(_ text: String, _ transform: (Int) -> String?) -> String {
        guard text.contains(open) else { return text }
        var result = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == open,
               let decoded = decode(at: i, in: text),
               let replacement = transform(decoded.index) {
                result += replacement
                i = decoded.end
            } else {
                result.append(text[i])
                i = text.index(after: i)
            }
        }
        return result
    }

    /// Puts the LaTeX back, for text that is read rather than rendered — a
    /// heading slug, say.
    func restoring(_ text: String, spans: [MathSpan]) -> String {
        substituting(text) { $0 < spans.count ? spans[$0].latex : nil }
    }

    /// Renders tokens readably (`⟦math 0⟧`) — PUA scalars are invisible when
    /// printed, which makes a failing test assertion impossible to read.
    func describing(_ text: String) -> String {
        substituting(text) { "⟦math \($0)⟧" }
    }
}
