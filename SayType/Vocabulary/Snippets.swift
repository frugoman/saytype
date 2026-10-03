import Foundation

/// A phrase that expands into a saved block of text: say "my address", get the whole address.
struct Snippet: Codable, Identifiable, Hashable {
    var id = UUID()
    var trigger: String
    var expansion: String
}

enum SnippetExpander {
    /// Replaces trigger phrases with their expansions. `{date}`, `{time}` and `{clipboard}` are filled in.
    static func expand(_ text: String, snippets: [Snippet], now: Date = Date(), clipboard: String? = nil) -> String {
        var result = text
        let ordered = snippets.filter { !$0.trigger.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.trigger.count > $1.trigger.count }
        for snippet in ordered {
            // A trailing sentence mark Whisper added after the trigger is dropped when the trigger ends the text.
            let pattern = VocabularyStore.pattern(for: snippet.trigger) + #"(?:[.!?]+(?=\s*$))?"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            guard regex.firstMatch(in: result, range: range) != nil else { continue }
            let body = fill(snippet.expansion, now: now, clipboard: clipboard)
            result = regex.stringByReplacingMatches(in: result, range: range,
                                                    withTemplate: NSRegularExpression.escapedTemplate(for: body))
        }
        return result
    }

    static func fill(_ template: String, now: Date, clipboard: String?) -> String {
        guard template.contains("{") else { return template }
        let date = DateFormatter()
        date.dateStyle = .long
        date.timeStyle = .none
        let time = DateFormatter()
        time.dateStyle = .none
        time.timeStyle = .short
        return template
            .replacingOccurrences(of: "{date}", with: date.string(from: now))
            .replacingOccurrences(of: "{time}", with: time.string(from: now))
            .replacingOccurrences(of: "{clipboard}", with: clipboard ?? "")
    }
}

@MainActor
final class SnippetStore: ObservableObject {
    @Published var entries: [Snippet] = [] {
        didSet { if loaded { save() } }
    }
    private let file: URL
    private var loaded = false

    init(file: URL = AppPaths.snippetsFile) {
        self.file = file
        if let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode([Snippet].self, from: data) {
            entries = decoded
        }
        loaded = true
    }

    func expand(_ text: String, clipboard: String?) -> String {
        SnippetExpander.expand(text, snippets: entries, clipboard: clipboard)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
