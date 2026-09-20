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
enum MathPlaceholder {
    static let open: Character = "\u{E000}"
    static let close: Character = "\u{E001}"

    private static let digitBase: UInt32 = 0xE010
    private static let reserved: ClosedRange<UInt32> = 0xE000...0xE01F

    static func token(for index: Int) -> String {
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
    static func decode(at start: String.Index, in text: String) -> (index: Int, end: String.Index)? {
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

    /// Removes the reserved range from user input, so a token can only ever be
    /// one we wrote — unforgeable rather than merely improbable.
    static func stripReserved(from source: String) -> String {
        guard source.unicodeScalars.contains(where: { reserved.contains($0.value) }) else {
            return source
        }
        var scalars = String.UnicodeScalarView()
        for scalar in source.unicodeScalars where !reserved.contains(scalar.value) {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Rewrites every token in `text`. Returning `nil` leaves one as it is.
    private static func substituting(_ text: String,
                                     _ transform: (Int) -> String?) -> String {
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
    static func restoring(_ text: String, spans: [MathSpan]) -> String {
        substituting(text) { $0 < spans.count ? spans[$0].latex : nil }
    }

    /// Renders tokens readably (`⟦math 0⟧`) — PUA scalars are invisible when
    /// printed, which makes a failing test assertion impossible to read.
    static func describing(_ text: String) -> String {
        substituting(text) { "⟦math \($0)⟧" }
    }
}
