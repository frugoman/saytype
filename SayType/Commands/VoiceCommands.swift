import Foundation

/// What to do with a dictated utterance once voice commands have been interpreted.
enum DictationAction: Equatable {
    case text(String)
    case newLine
    case newParagraph
    case pressEnter
    case undo
    case selectAll
    /// Delete what SayType typed last.
    case deleteLast
}

struct VoiceCommandOptions: Equatable {
    var commands = true
    var spokenPunctuation = false
}

/// Turns "hello new line how are you scratch that" into typed text and key presses.
enum VoiceCommands {
    /// Phrases that only count when they are the whole utterance, so ordinary sentences are safe.
    private static let standalone: [(phrase: [String], action: DictationAction)] = [
        (["undo", "that"], .undo), (["undo", "it"], .undo), (["undo"], .undo),
        (["select", "all"], .selectAll), (["select", "everything"], .selectAll),
        (["press", "enter"], .pressEnter), (["press", "return"], .pressEnter),
        (["hit", "enter"], .pressEnter), (["hit", "return"], .pressEnter),
        (["enter"], .pressEnter), (["return"], .pressEnter),
        (["new", "line"], .newLine), (["newline"], .newLine), (["next", "line"], .newLine),
        (["line", "break"], .newLine),
        (["new", "paragraph"], .newParagraph), (["next", "paragraph"], .newParagraph),
        // "scratch that" is often heard as "scratch there" or "scratch this".
        (["scratch", "that"], .deleteLast), (["scratch", "there"], .deleteLast), (["scratch", "this"], .deleteLast),
        (["delete", "that"], .deleteLast), (["delete", "this"], .deleteLast), (["erase", "that"], .deleteLast),
        (["remove", "that"], .deleteLast), (["strike", "that"], .deleteLast), (["cancel", "that"], .deleteLast),
    ]

    /// Filler and politeness words that don't stop a command from counting ("uh, press enter").
    private static let fillers: Set<String> = [
        "uh", "um", "uhm", "umm", "er", "erm", "ah", "eh", "hm", "hmm", "mm", "mhm", "oh",
        "okay", "ok", "so", "please", "now", "and", "then",
    ]

    /// Phrases recognised anywhere in the utterance.
    private static let inline: [(phrase: [String], action: DictationAction)] = [
        (["new", "paragraph"], .newParagraph),
        (["new", "line"], .newLine),
        (["newline"], .newLine),
        (["scratch", "that"], .deleteLast),
        (["delete", "that"], .deleteLast),
        (["strike", "that"], .deleteLast),
    ]

    private enum Mark { case close(String), open(String), quote }

    private static let punctuation: [(phrase: [String], mark: Mark)] = [
        (["question", "mark"], .close("?")),
        (["exclamation", "mark"], .close("!")),
        (["exclamation", "point"], .close("!")),
        (["full", "stop"], .close(".")),
        (["period"], .close(".")),
        (["comma"], .close(",")),
        (["colon"], .close(":")),
        (["semicolon"], .close(";")),
        (["ellipsis"], .close("…")),
        (["close", "paren"], .close(")")),
        (["close", "parenthesis"], .close(")")),
        (["close", "bracket"], .close("]")),
        (["open", "paren"], .open("(")),
        (["open", "parenthesis"], .open("(")),
        (["open", "bracket"], .open("[")),
        (["open", "quote"], .quote),
        (["close", "quote"], .quote),
        (["end", "quote"], .quote),
        (["unquote"], .quote),
        (["quote"], .quote),
        (["hyphen"], .close("-")),
    ]

    static func parse(_ text: String, options: VoiceCommandOptions) -> [DictationAction] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard options.commands || options.spokenPunctuation else { return [.text(trimmed)] }

        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        let normalized = words.map(normalize)

        if options.commands {
            // Ignore fillers at either end, so "Uh, press enter." still counts as the command.
            var core = normalized[...]
            while let first = core.first, fillers.contains(first) { core = core.dropFirst() }
            while let last = core.last, fillers.contains(last) { core = core.dropLast() }
            for entry in standalone where Array(core) == entry.phrase { return [entry.action] }
        }

        var actions: [DictationAction] = []
        var buffer = TextBuffer()
        var capitalizeNext = false

        func flush() {
            if let t = buffer.take() { actions.append(.text(t)) }
        }

        var i = 0
        while i < words.count {
            if options.commands, let hit = match(inline, at: i, in: normalized) {
                i += hit.length
                switch hit.action {
                case .deleteLast:
                    // Drop what was said earlier in this utterance; if nothing, undo the previous typing.
                    let hadEarlierSpeech = !actions.isEmpty || !buffer.isEmpty
                    actions.removeAll()
                    buffer = TextBuffer()
                    if !hadEarlierSpeech { actions.append(.deleteLast) }
                    capitalizeNext = false
                default:
                    flush()
                    actions.append(hit.action)
                    capitalizeNext = true
                }
                continue
            }
            if options.spokenPunctuation, let hit = matchPunctuation(at: i, in: normalized) {
                i += hit.length
                switch hit.mark {
                case .close(let p):
                    buffer.attach(p)
                    if ".?!…".contains(p) { capitalizeNext = true }
                case .open(let p): buffer.open(p)
                case .quote: buffer.toggleQuote()
                }
                continue
            }
            var word = words[i]
            if capitalizeNext, let first = word.first, first.isLowercase {
                word = first.uppercased() + word.dropFirst()
            }
            capitalizeNext = false
            buffer.append(word)
            i += 1
        }
        flush()
        return actions
    }

    // MARK: - Matching

    private static func normalize(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }

    private static func match(_ table: [(phrase: [String], action: DictationAction)], at i: Int, in words: [String])
        -> (length: Int, action: DictationAction)? {
        for entry in table where i + entry.phrase.count <= words.count
            && Array(words[i..<i + entry.phrase.count]) == entry.phrase {
            return (entry.phrase.count, entry.action)
        }
        return nil
    }

    private static func matchPunctuation(at i: Int, in words: [String]) -> (length: Int, mark: Mark)? {
        for entry in punctuation where i + entry.phrase.count <= words.count
            && Array(words[i..<i + entry.phrase.count]) == entry.phrase {
            return (entry.phrase.count, entry.mark)
        }
        return nil
    }

    // MARK: - Text assembly

    /// Builds a sentence word by word, attaching punctuation without stray spaces.
    private struct TextBuffer {
        private var text = ""
        private var skipSpace = false
        private var quoteOpen = false

        var isEmpty: Bool { text.isEmpty }

        mutating func take() -> String? {
            defer { self = TextBuffer() }
            let t = text.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }

        mutating func append(_ word: String) {
            if !text.isEmpty && !skipSpace { text += " " }
            text += word
            skipSpace = false
        }

        mutating func attach(_ mark: String) {
            // Whisper often already wrote a comma or period before the spoken word.
            while let last = text.last, ",.;:".contains(last) { text.removeLast() }
            text += mark
            skipSpace = false
        }

        mutating func open(_ mark: String) {
            if !text.isEmpty { text += " " }
            text += mark
            skipSpace = true
        }

        mutating func toggleQuote() {
            if quoteOpen { text += "\"" } else {
                if !text.isEmpty { text += " " }
                text += "\""
                skipSpace = true
            }
            quoteOpen.toggle()
        }
    }
}
