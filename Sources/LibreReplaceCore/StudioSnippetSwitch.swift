import Foundation

/// CSV decoder and conservative conversion for an installed Espanso Free Twin.
/// It never runs imported scripts or changes existing expansion definitions.
public enum StudioSnippetSwitchError: LocalizedError, Sendable {
    case invalidInput(String)
    public var errorDescription: String? {
        switch self { case .invalidInput(let reason): return reason }
    }
}

public enum StudioSnippetDecision: String, Codable, Sendable {
    case readyForExport, needsReview, blocked
}

public struct StudioSnippetFinding: Identifiable, Sendable, Equatable {
    public let id: Int
    public let trigger: String
    public let replacement: String
    public let label: String
    public let decision: StudioSnippetDecision
    public let reasons: [String]
    public var isExportable: Bool { decision == .readyForExport }
    public var eligibleForMacTextReplacements: Bool {
        isExportable && !replacement.contains("\n") && !replacement.contains("\r") &&
        !replacement.contains("%clipboard") && !replacement.contains("%|") &&
        !replacement.contains("%Y-%m-%d") && !replacement.contains("%m/%d/%Y") &&
        !replacement.contains("%H:%M") && !replacement.contains("%B %d, %Y")
    }
}

public struct StudioSnippetTrial: Sendable {
    public let findings: [StudioSnippetFinding]
    public let originalByteCount: Int
    public let sourceDescription: String
    public var safeForEspanso: [StudioSnippetFinding] { findings.filter(\.isExportable) }
    public var safeForMac: [StudioSnippetFinding] { findings.filter(\.eligibleForMacTextReplacements) }
    public var needsReviewCount: Int { findings.filter { $0.decision == .needsReview }.count }
    public var blockedCount: Int { findings.filter { $0.decision == .blocked }.count }
    public var readyCount: Int { safeForEspanso.count }
}

public enum StudioSnippetTarget: String, Codable, Sendable {
    case espanso, macTextReplacements
    public var title: String {
        switch self {
        case .espanso: "Espanso"
        case .macTextReplacements: "macOS Text Replacements"
        }
    }
    public var extensionName: String { self == .espanso ? "yml" : "plist" }
}

public enum StudioSnippetSwitch {
    public static let maximumBytes = 64 * 1024 * 1024
    public static let maximumSnippets = 100_000

    /// The caller must select a regular local CSV. This path never executes file contents.
    public static func audit(fileURL: URL) throws -> StudioSnippetTrial {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard fileURL.isFileURL, fileURL.pathExtension.lowercased() == "csv",
              values.isRegularFile == true, values.isSymbolicLink != true,
              let length = values.fileSize, length > 0 && length <= maximumBytes else {
            throw StudioSnippetSwitchError.invalidInput("Choose a regular CSV export smaller than 64 MB. Symbolic links are not accepted.")
        }
        return try audit(data: Data(contentsOf: fileURL))
    }

    public static func audit(data: Data) throws -> StudioSnippetTrial {
        guard !data.isEmpty, data.count <= maximumBytes,
              var contents = String(data: data, encoding: .utf8) else {
            throw StudioSnippetSwitchError.invalidInput("The export must be UTF-8 CSV, between 1 byte and 64 MB.")
        }
        if contents.hasPrefix("\u{FEFF}") { contents.removeFirst() }
        guard !contents.contains("\0") else {
            throw StudioSnippetSwitchError.invalidInput("This CSV contains a null byte and cannot be safely interpreted.")
        }
        let rows = try parseCSV(contents)
        guard let headers = rows.first else {
            throw StudioSnippetSwitchError.invalidInput("The CSV has no header row.")
        }
        let keys = headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(keys).count == keys.count,
              let triggerColumn = keys.firstIndex(of: "abbreviation"),
              let textColumn = keys.firstIndex(of: "snippet") else {
            throw StudioSnippetSwitchError.invalidInput("CSV needs unique 'abbreviation' and 'snippet' columns. Export TextExpander snippets as CSV.")
        }
        let labelColumn = keys.firstIndex(of: "label")
        let records = Array(rows.dropFirst()).filter { !$0.allSatisfy(\.isEmpty) }
        guard !records.isEmpty, records.count <= maximumSnippets else {
            throw StudioSnippetSwitchError.invalidInput("Use a CSV containing 1 to 100,000 snippet rows.")
        }
        let expectedColumns = headers.count
        for (index, row) in records.enumerated() where row.count != expectedColumns {
            throw StudioSnippetSwitchError.invalidInput("CSV row \(index + 2) has \(row.count) fields, but the header has \(expectedColumns). Check quotes and delimiters.")
        }
        var groups: [String: [Int]] = [:]
        for (index, row) in records.enumerated() {
            let key = row[triggerColumn].lowercased()
            groups[key, default: []].append(index)
        }
        let findings: [StudioSnippetFinding] = records.enumerated().map { index, row in
            let trigger = row[triggerColumn]
            let replacement = row[textColumn]
            var reasons: [String] = []
            var blocked = false
            if trigger.isEmpty || replacement.isEmpty {
                blocked = true
                reasons.append("Empty trigger or replacement")
            }
            if trigger.count > 120 || replacement.utf8.count > 1024 * 1024 {
                blocked = true
                reasons.append("A trigger or replacement exceeds the supported per-snippet length")
            }
            if trigger.contains("\n") || trigger.contains("\r") || trigger.contains("\t") ||
               trigger.trimmingCharacters(in: .whitespacesAndNewlines) != trigger {
                blocked = true
                reasons.append("Trigger contains whitespace that needs manual review")
            }
            if groups[trigger.lowercased(), default: []].count > 1 {
                blocked = true
                reasons.append("Trigger conflicts with another row (including case differences)")
            }
            if replacement.unicodeScalars.contains(where: { $0.value < 32 && $0 != "\n" && $0 != "\r" && $0 != "\t" }) ||
                trigger.unicodeScalars.contains(where: { $0.value < 32 }) {
                blocked = true
                reasons.append("Contains an unsupported control character")
            }
            // Two reviewed macro bridges are safe: clipboard and one cursor
            // hint. All scripts, fill-ins, date math, and unknown variables remain
            // excluded rather than being inserted literally by accident.
            let mapped = mapSupportedMacros(replacement)
            let unknownPattern = #"(?i)%([a-z][a-z0-9_]*|\|)|\{\{[^}]*\}\}|\$\{[^}]*\}|\{(?:clipboard|date|time|cursor)[^}]*\}"#
            var unknownText = mapped.text
            if mapped.usesClipboard { unknownText = unknownText.replacingOccurrences(of: "{{lr_clipboard}}", with: "") }
            for token in mapped.dateVariables {
                unknownText = unknownText.replacingOccurrences(of: "{{\(token.name)}}", with: "")
            }
            if unknownText.range(of: unknownPattern, options: .regularExpression) != nil ||
               replacement.contains("%%") || replacement.contains("{{") || replacement.contains("$|$") {
                reasons.append("Unsupported TextExpander macro or escaped sequence needs conversion")
            }
            if replacement.components(separatedBy: "%|").count > 2 {
                reasons.append("Multiple cursor positions are not supported by Espanso")
            }
            if replacement.contains("\r") {
                reasons.append("Carriage returns need a manual line-ending review")
            }
            let decision: StudioSnippetDecision = blocked ? .blocked : (reasons.isEmpty ? .readyForExport : .needsReview)
            return StudioSnippetFinding(id: index + 2, trigger: trigger, replacement: replacement,
                                        label: labelColumn.map { row[$0] } ?? "", decision: decision, reasons: reasons)
        }
        return StudioSnippetTrial(findings: findings, originalByteCount: data.count,
                                  sourceDescription: "TextExpander-compatible UTF-8 CSV")
    }

    /// Imports multiple TextExpander groups together. Duplicate triggers across
    /// groups are excluded rather than allowing one group to override another.
    public static func audit(files: [URL]) throws -> StudioSnippetTrial {
        guard !files.isEmpty, files.count <= 128 else {
            throw StudioSnippetSwitchError.invalidInput("Choose between 1 and 128 CSV exports at once.")
        }
        guard Set(files.map { $0.standardizedFileURL.path }).count == files.count else {
            throw StudioSnippetSwitchError.invalidInput("The same CSV was selected more than once.")
        }
        let trials = try files.map { try audit(fileURL: $0) }
        let totalBytes = trials.reduce(Int64(0)) { $0 + Int64($1.originalByteCount) }
        let count = trials.reduce(0) { $0 + $1.findings.count }
        guard totalBytes <= Int64(128 * 1024 * 1024), count <= maximumSnippets else {
            throw StudioSnippetSwitchError.invalidInput("This selection exceeds 128 MB or 100,000 snippet rows. Choose smaller groups.")
        }
        var findings: [StudioSnippetFinding] = []
        findings.reserveCapacity(count)
        for trial in trials {
            for finding in trial.findings {
                findings.append(StudioSnippetFinding(id: findings.count + 1,
                    trigger: finding.trigger, replacement: finding.replacement,
                    label: finding.label, decision: finding.decision, reasons: finding.reasons))
            }
        }
        var counts: [String: Int] = [:]
        for item in findings { counts[item.trigger.lowercased(), default: 0] += 1 }
        findings = findings.map { item in
            guard counts[item.trigger.lowercased(), default: 0] > 1 else { return item }
            var reasons = item.reasons
            if !reasons.contains("Trigger conflicts across multiple exports") {
                reasons.append("Trigger conflicts across multiple exports")
            }
            return StudioSnippetFinding(id: item.id, trigger: item.trigger,
                replacement: item.replacement, label: item.label,
                decision: .blocked, reasons: reasons)
        }
        return StudioSnippetTrial(findings: findings, originalByteCount: Int(totalBytes),
                                  sourceDescription: "\(files.count) TextExpander-compatible CSV exports")
    }

    /// Only exports the conservatively identified static rows. Never includes review/blocked rows.
    public static func export(_ trial: StudioSnippetTrial, as target: StudioSnippetTarget) throws -> Data {
        let matches = target == .espanso ? trial.safeForEspanso : trial.safeForMac
        guard !matches.isEmpty else {
            throw StudioSnippetSwitchError.invalidInput("No static snippets are eligible for this target. Review the findings before exporting.")
        }
        switch target {
        case .espanso:
            var lines: [String] = [
                "# LibreReplace Studio: static snippets only; review before enabling in Espanso.",
                "# This file has NOT been tested in the Espanso application.",
                "matches:"
            ]
            for match in matches {
                let mapped = mapSupportedMacros(match.replacement)
                lines.append("  - trigger: \(try yamlQuoted(match.trigger))")
                lines.append("    replace: \(try yamlQuoted(mapped.text))")
                if mapped.usesClipboard || !mapped.dateVariables.isEmpty {
                    lines.append("    vars:")
                    if mapped.usesClipboard {
                        lines.append("      - name: lr_clipboard")
                        lines.append("        type: clipboard")
                    }
                    for token in mapped.dateVariables {
                        lines.append("      - name: \(token.name)")
                        lines.append("        type: date")
                        lines.append("        params:")
                        lines.append("          format: \(try yamlQuoted(token.format))")
                    }
                }
            }
            let output = Data((lines.joined(separator: "\n") + "\n").utf8)
            let valueLines = lines.filter { $0.hasPrefix("  - trigger: ") || $0.hasPrefix("    replace: ") }
            guard valueLines.count == matches.count * 2 else {
                throw StudioSnippetSwitchError.invalidInput("Generated configuration had an unexpected number of values.")
            }
            for (index, item) in matches.enumerated() {
                let triggerText = String(valueLines[index * 2].dropFirst("  - trigger: ".count))
                let replacementText = String(valueLines[index * 2 + 1].dropFirst("    replace: ".count))
                guard try JSONDecoder().decode(String.self, from: Data(triggerText.utf8)) == item.trigger,
                      try JSONDecoder().decode(String.self, from: Data(replacementText.utf8)) == mapSupportedMacros(item.replacement).text else {
                    throw StudioSnippetSwitchError.invalidInput("Generated configuration failed its string round-trip check.")
                }
            }
            return output
        case .macTextReplacements:
            let items: [[String: String]] = matches.map { ["shortcut": $0.trigger, "phrase": $0.replacement] }
            let data = try PropertyListSerialization.data(fromPropertyList: items, format: .xml, options: 0)
            guard let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: String]],
                  parsed == items else {
                throw StudioSnippetSwitchError.invalidInput("Generated text-replacement data did not pass the read-back check.")
            }
            return data
        }
    }

    /// Explicit allowlist: no arbitrary scripts, shell commands, or custom
    /// expressions from imported CSV are ever made executable.
    private static func mapSupportedMacros(_ input: String) ->
        (text: String, usesClipboard: Bool, dateVariables: [(name: String, format: String)]) {
        let withClipboard = input.replacingOccurrences(
            of: #"%clipboard(?![A-Za-z0-9_])"#, with: "{{lr_clipboard}}", options: .regularExpression)
        var mapped = withClipboard.replacingOccurrences(of: "%|", with: "$|$")
        // Restrict automatic date conversion to exact well-understood formats.
        // TextExpander's date math, Unicode date tokens and other macros need
        // explicit bridging instead of being silently turned into static text.
        let formats: [(source: String, name: String, format: String)] = [
            ("%B %d, %Y", "lr_date_full", "%B %d, %Y"),
            ("%Y-%m-%d", "lr_date_iso", "%Y-%m-%d"),
            ("%m/%d/%Y", "lr_date_mdy", "%m/%d/%Y"),
            ("%H:%M", "lr_time_hm", "%H:%M")
        ]
        var used: [(name: String, format: String)] = []
        for format in formats where mapped.contains(format.source) {
            mapped = mapped.replacingOccurrences(of: format.source, with: "{{\(format.name)}}")
            used.append((format.name, format.format))
        }
        return (mapped, withClipboard != input, used)
    }

    private static func yamlQuoted(_ s: String) throws -> String {
        // JSON double-quoted strings are a safe subset of YAML quoted scalar syntax.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = try encoder.encode(s)
        guard let encoded = String(data: data, encoding: .utf8), encoded.hasPrefix("\"") else {
            throw StudioSnippetSwitchError.invalidInput("A snippet could not be safely quoted.")
        }
        return encoded
    }

    /// Strict RFC 4180-style comma parser with quoted newlines, doubled quotes,
    /// CRLF support and rejection of malformed quoted data.
    private static func parseCSV(_ input: String) throws -> [[String]] {
        enum State { case start, bare, quoted, closed }
        var state: State = .start
        var field = ""
        var row: [String] = []
        var rows: [[String]] = []
        var lastWasCR = false
        func addField() { row.append(field); field = "" }
        func addRow() { addField(); rows.append(row); row = [] }
        for scalar in input.unicodeScalars {
            if lastWasCR && scalar == "\n" { lastWasCR = false; continue }
            lastWasCR = false
            if state != .quoted && (scalar == "\r" || scalar == "\n") {
                addRow(); state = .start
                lastWasCR = scalar == "\r"
                continue
            }
            switch state {
            case .start:
                if scalar == "\"" { state = .quoted }
                else if scalar == "," { addField() }
                else { field.unicodeScalars.append(scalar); state = .bare }
            case .bare:
                if scalar == "," { addField(); state = .start }
                else if scalar == "\"" {
                    throw StudioSnippetSwitchError.invalidInput("Malformed CSV: a quote appears inside an unquoted field.")
                } else { field.unicodeScalars.append(scalar) }
            case .quoted:
                if scalar == "\"" { state = .closed }
                else { field.unicodeScalars.append(scalar) }
            case .closed:
                if scalar == "\"" { field.append("\""); state = .quoted }
                else if scalar == "," { addField(); state = .start }
                else {
                    throw StudioSnippetSwitchError.invalidInput("Malformed CSV: unexpected text after a closing quote.")
                }
            }
            if rows.count > maximumSnippets + 2 {
                throw StudioSnippetSwitchError.invalidInput("The CSV has too many rows (maximum 100,000 snippets).")
            }
        }
        guard state != .quoted else {
            throw StudioSnippetSwitchError.invalidInput("Malformed CSV: an opening quote was never closed.")
        }
        if !row.isEmpty || !field.isEmpty || state != .start { addRow() }
        return rows
    }
}
