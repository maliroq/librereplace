import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ReportExporter {
    static func saveMarkdown(_ markdown: String) throws {
        let panel = NSSavePanel()
        panel.title = "Export privacy-safe LibreReplace report"
        panel.nameFieldStringValue = "LibreReplace-report.md"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    static func copyToClipboard(_ markdown: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}
