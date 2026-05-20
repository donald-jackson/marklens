import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown")
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.markdownDocument, .plainText]
    }

    static var writableContentTypes: [UTType] { [] }  // read-only viewer

    var source: String

    init(source: String = "") {
        self.source = source
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.source = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Read-only viewer — should never be called.
        throw CocoaError(.featureUnsupported)
    }
}
