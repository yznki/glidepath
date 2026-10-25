import Foundation

/// What Glidepath learns from an edited draft or a reopened thread. The prompts ask a small model for one line.
enum Lessons {
    static let ask = "What should Glidepath learn? Write at most one terse lesson line, under 160 characters, about this "
        + "repo or this reviewer. Reply with that line only, or NONE if there is nothing worth keeping."

    static func editPrompt(draft: String, final: String, author: String) -> String {
        "Glidepath drafted a reply to \(author) and the developer sent a different one.\n\nDraft:\n\(draft)\n\n"
            + "Sent:\n\(final)\n\n" + ask
    }

    static func pushbackPrompt(thread: String, ours: String) -> String {
        "Glidepath replied to a review thread and resolved it, and the thread was reopened.\n\nThread:\n\(thread)\n\n"
            + "Our reply:\n\(ours)\n\n" + ask
    }

    /// The model's lesson: its last non-empty line, without a leading "- ", at most 160 characters. Nil for NONE.
    static func parse(_ text: String) -> String? {
        guard var line = text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { !$0.isEmpty }) else { return nil }
        if line.hasPrefix("- ") { line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        if line.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == "NONE" { return nil }
        let clipped = String(line.prefix(160)).trimmingCharacters(in: .whitespaces)
        return clipped.isEmpty ? nil : clipped
    }
}
