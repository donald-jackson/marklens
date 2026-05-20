import Foundation

public enum WebResources {
    /// URL of the bundled `Web/` directory containing template assets
    /// (styles.css, mermaid.min.js, highlight.min.js, hljs themes).
    public static var bundleURL: URL? {
        // Preferred: locate a known file inside Web/ and return its parent.
        // More reliable than url(forResource:withExtension:) for directories.
        if let stylesURL = Bundle.module.url(forResource: "styles", withExtension: "css", subdirectory: "Web") {
            return stylesURL.deletingLastPathComponent()
        }
        // Fallback: construct from resourceURL.
        return Bundle.module.resourceURL?.appendingPathComponent("Web")
    }
}
