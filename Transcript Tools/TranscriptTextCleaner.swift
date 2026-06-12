import Foundation

enum TranscriptTextCleaner {
    private static let specialTokenPattern = #"<\|[^|]*\|>"#
    private static let timestampPattern = #"^\s*\[[0-9]{2}:[0-9]{2}(?::[0-9]{2})?(?:\.[0-9]{3})?\]\s*"#
    private static let whitespacePattern = #"\s+"#
    private static let punctuationSpacingPattern = #"\s+([,.;:!?])"#
    private static let placeholderPhrases: Set<String> = [
        "speaking in foreign language",
        "foreign language",
        "inaudible",
        "music",
        "silence",
        "blank audio",
        "no speech"
    ]

    nonisolated static func clean(_ rawText: String) -> String {
        var text = rawText
        text = replacing(pattern: specialTokenPattern, in: text, with: " ")
        text = replacing(pattern: timestampPattern, in: text, with: "")
        text = replacing(pattern: punctuationSpacingPattern, in: text, with: "$1")
        text = replacing(pattern: whitespacePattern, in: text, with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func usefulText(from rawText: String) -> String? {
        let text = clean(rawText)
        guard !text.isEmpty else { return nil }
        guard !isPlaceholder(text) else { return nil }
        return text
    }

    nonisolated private static func isPlaceholder(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}"))
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return placeholderPhrases.contains(normalized)
    }

    nonisolated private static func replacing(pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
