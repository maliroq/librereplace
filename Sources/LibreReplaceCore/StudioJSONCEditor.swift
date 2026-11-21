import Foundation

/// Edit only reviewed top-level Zed settings, keeping every unrelated byte,
/// inline comment, and formatting choice. JSONC is accepted for the supported
/// comment grammar; unsafe or ambiguous syntax fails closed.
public enum StudioJSONCEditor {
    private struct Shape {
        var valueRanges: [String: Range<Int>]
        var closingBrace: Int
    }

    public static func topLevelDictionary(_ original: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: JSONC.stripComments(original)),
              let dictionary = object as? [String: Any] else {
            throw StudioSnippetBridgeError.malformedTarget("Zed settings JSON")
        }
        _ = try shape(Array(original))
        return dictionary
    }

    public static func merge(_ original: Data?, reviewedValues: [String: Any]) throws -> Data {
        guard !reviewedValues.isEmpty else { return original ?? Data("{}\n".utf8) }
        if original == nil {
            return try JSONSerialization.data(withJSONObject: reviewedValues, options: [.prettyPrinted, .sortedKeys])
        }
        let original = original!
        let current = try topLevelDictionary(original)
        let layout = try shape(Array(original))
        var bytes = Array(original)
        let newProperties = reviewedValues.keys.filter { current[$0] == nil }.sorted()
        if !newProperties.isEmpty {
            var fragments: [String] = []
            for key in newProperties {
                let keyLiteral = try jsonLiteral(key)
                let valueLiteral = try jsonLiteral(reviewedValues[key]!)
                fragments.append("  \(keyLiteral): \(valueLiteral)")
            }
            let beforeEnd = Data(bytes[..<layout.closingBrace])
            let cleanPrefix = String(decoding: JSONC.stripComments(beforeEnd), as: UTF8.self)
            let hasTrailingComma = cleanPrefix.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(",")
            let separator = (current.isEmpty || hasTrailingComma) ? "\n" : ",\n"
            let insertion = Array((separator + fragments.joined(separator: ",\n") + "\n").utf8)
            bytes.insert(contentsOf: insertion, at: layout.closingBrace)
        }
        // Reverse offset order means earlier source ranges are unaffected.
        for (name, range) in layout.valueRanges.sorted(by: { $0.value.lowerBound > $1.value.lowerBound }) {
            guard let value = reviewedValues[name] else { continue }
            let encoded = Array(try jsonLiteral(value).utf8)
            bytes.replaceSubrange(range, with: encoded)
        }
        let result = Data(bytes)
        let verified = try topLevelDictionary(result)
        for (key, value) in reviewedValues {
            guard let actual = verified[key] else { throw StudioSnippetBridgeError.malformedTarget("Missing changed key") }
            let wanted = try jsonLiteral(value)
            let got = try jsonLiteral(actual)
            guard wanted == got else { throw StudioSnippetBridgeError.malformedTarget("Changed key did not verify") }
        }
        return result
    }

    private static func jsonLiteral(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed, .sortedKeys])
        guard let string = String(data: data, encoding: .utf8), string.first == "[", string.last == "]" else {
            throw StudioSnippetBridgeError.malformedTarget("Unsupported JSON value")
        }
        return String(string.dropFirst().dropLast())
    }

    private static func shape(_ b: [UInt8]) throws -> Shape {
        var i = 0
        func invalid() -> StudioSnippetBridgeError { .malformedTarget("Zed settings JSON structure") }
        func skip() throws {
            while i < b.count {
                if [UInt8(32), 9, 10, 13].contains(b[i]) { i += 1; continue }
                if i + 1 < b.count && b[i] == 47 && b[i+1] == 47 {
                    i += 2; while i < b.count && b[i] != 10 { i += 1 }; continue
                }
                if i + 1 < b.count && b[i] == 47 && b[i+1] == 42 {
                    i += 2; var closed = false
                    while i + 1 < b.count {
                        if b[i] == 42 && b[i+1] == 47 { i += 2; closed = true; break }
                        i += 1
                    }
                    guard closed else { throw invalid() }
                    continue
                }
                break
            }
        }
        func stringEnd() throws -> Int {
            guard i < b.count && b[i] == 34 else { throw invalid() }
            i += 1; var escaped = false
            while i < b.count {
                let v = b[i]; i += 1
                if escaped { escaped = false; continue }
                if v == 92 { escaped = true; continue }
                if v == 34 { return i }
                if v == 10 || v == 13 { throw invalid() }
            }
            throw invalid()
        }
        func valueEnd() throws -> Int {
            guard i < b.count else { throw invalid() }
            if b[i] == 34 { return try stringEnd() }
            if b[i] == 123 || b[i] == 91 {
                var stack: [UInt8] = []
                while i < b.count {
                    let v = b[i]
                    if v == 34 { _ = try stringEnd(); continue }
                    if i + 1 < b.count && v == 47 && (b[i+1] == 47 || b[i+1] == 42) {
                        try skip(); continue
                    }
                    if v == 123 { stack.append(125) }
                    else if v == 91 { stack.append(93) }
                    else if v == 125 || v == 93 {
                        guard stack.popLast() == v else { throw invalid() }
                        i += 1
                        if stack.isEmpty { return i }
                        continue
                    }
                    i += 1
                }
                throw invalid()
            }
            while i < b.count && ![UInt8(32), 9, 10, 13, 44, 125, 47].contains(b[i]) { i += 1 }
            return i
        }

        try skip()
        guard i < b.count && b[i] == 123 else { throw invalid() }
        i += 1
        var ranges: [String: Range<Int>] = [:]
        while true {
            try skip()
            guard i < b.count else { throw invalid() }
            if b[i] == 125 {
                let closing = i; i += 1; try skip()
                guard i == b.count else { throw invalid() }
                return Shape(valueRanges: ranges, closingBrace: closing)
            }
            let startKey = i
            let endKey = try stringEnd()
            let jsonKey = "[" + String(decoding: b[startKey..<endKey], as: UTF8.self) + "]"
            guard let decoded = try? JSONSerialization.jsonObject(with: Data(jsonKey.utf8)) as? [String],
                  let key = decoded.first, ranges[key] == nil else { throw invalid() }
            try skip()
            guard i < b.count && b[i] == 58 else { throw invalid() }
            i += 1; try skip()
            let startValue = i
            let endValue = try valueEnd()
            guard endValue > startValue else { throw invalid() }
            ranges[key] = startValue..<endValue
            try skip()
            guard i < b.count else { throw invalid() }
            if b[i] == 44 { i += 1; continue }
            guard b[i] == 125 else { throw invalid() }
        }
    }
}
