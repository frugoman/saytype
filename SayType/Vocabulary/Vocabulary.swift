import Foundation

/// A word the user wants transcribed exactly, e.g. a project name or a technical term.
struct VocabularyEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    /// How it should be written: "gira-planner", "Next.js", "kubectl".
    var term: String
    /// What the recognizer tends to hear instead: "hera planner", "next jay ess".
    /// Filled in manually or by "Teach by voice".
    var soundsLike: [String] = []
}

/// Stores the user's vocabulary and applies it in two ways:
/// 1. **Biasing**: terms are fed to Whisper as a prompt so it's more likely to hear them right.
/// 2. **Correction**: known mis-hearings (and obvious spoken forms like "next dot js") are
///    rewritten to the exact spelling after transcription.
@MainActor
final class VocabularyStore: ObservableObject {
    @Published var entries: [VocabularyEntry] = [] {
        didSet { save(); rebuildRules() }
    }

    private var rules: [(regex: NSRegularExpression, replacement: String)] = []

    /// Primes Whisper for developer speech when "code context" is on.
    static let codeContext = "Software developer dictation with code terms: GitHub, TypeScript, JavaScript, JSON, API, npm, pnpm, Git, PostgreSQL, Kubernetes, Docker, localhost, README, async/await, OAuth, CLI, Xcode, SwiftUI, Python, regex, PR, CI/CD, env, stdout."

    private let file: URL

    init(file: URL = AppPaths.vocabularyFile) {
        self.file = file
        load()
        rebuildRules()
    }

    // MARK: - Biasing

    func prompt(includeCodeContext: Bool) -> String? {
        var parts: [String] = []
        if includeCodeContext { parts.append(Self.codeContext) }
        let terms = entries.map(\.term).filter { !$0.isEmpty }
        // User terms go last: Whisper keeps the end of an over-long prompt.
        if !terms.isEmpty { parts.append("Also: " + terms.joined(separator: ", ") + ".") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Correction

    func apply(to text: String) -> String {
        var result = text
        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(in: result, range: range,
                                                         withTemplate: NSRegularExpression.escapedTemplate(for: rule.replacement))
        }
        return result
    }

    private func rebuildRules() {
        var pairs: [(alias: String, term: String)] = []
        for entry in entries where !entry.term.isEmpty {
            var aliases = Set(entry.soundsLike.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            aliases.formUnion(Self.spokenForms(of: entry.term))
            for alias in aliases where !alias.isEmpty { pairs.append((alias, entry.term)) }
        }
        // Longest aliases first so "gira planner app" beats "gira planner".
        pairs.sort { $0.alias.count > $1.alias.count }
        rules = pairs.compactMap { pair in
            guard let regex = try? NSRegularExpression(pattern: Self.pattern(for: pair.alias),
                                                       options: [.caseInsensitive]) else { return nil }
            return (regex, pair.term)
        }
    }

    /// "Say Type" matches "say type", "Say-Type", "say, type" …
    nonisolated static func pattern(for alias: String) -> String {
        let words = alias.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return NSRegularExpression.escapedPattern(for: alias) }
        let body = words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: #"[\s\-_.,]*"#)
        return #"(?<![\p{L}\p{N}])"# + body + #"(?![\p{L}\p{N}])"#
    }

    /// Ways a term is likely to come out of the recognizer when spoken.
    static func spokenForms(of term: String) -> [String] {
        var forms: [String] = [term]
        // camelCase / PascalCase → separate words: "SayType" → "voice typer"
        let split = term.replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
        forms.append(split)
        // Punctuation spoken aloud: "Next.js" → "next dot js", "gira-planner" → "gira dash planner"
        let spoken = split
            .replacingOccurrences(of: ".", with: " dot ")
            .replacingOccurrences(of: "-", with: " dash ")
            .replacingOccurrences(of: "_", with: " underscore ")
            .replacingOccurrences(of: "/", with: " slash ")
        forms.append(spoken)
        return forms
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([VocabularyEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
