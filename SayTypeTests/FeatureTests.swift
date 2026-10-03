import XCTest

final class VoiceCommandTests: XCTestCase {
    private let on = VoiceCommandOptions(commands: true, spokenPunctuation: false)
    private let punct = VoiceCommandOptions(commands: true, spokenPunctuation: true)

    func testPlainTextPassesThrough() {
        XCTAssertEqual(VoiceCommands.parse("Hello there.", options: on), [.text("Hello there.")])
    }

    func testStandaloneCommands() {
        XCTAssertEqual(VoiceCommands.parse("Undo that.", options: on), [.undo])
        XCTAssertEqual(VoiceCommands.parse("Select all", options: on), [.selectAll])
        XCTAssertEqual(VoiceCommands.parse("Press enter.", options: on), [.pressEnter])
        XCTAssertEqual(VoiceCommands.parse("New line.", options: on), [.newLine])
    }

    func testFillersAroundACommandDontStopIt() {
        XCTAssertEqual(VoiceCommands.parse("Uh press enter.", options: on), [.pressEnter])
        XCTAssertEqual(VoiceCommands.parse("Uh undo that.", options: on), [.undo])
        XCTAssertEqual(VoiceCommands.parse("Okay, so new line please", options: on), [.newLine])
        XCTAssertEqual(VoiceCommands.parse("Hit enter", options: on), [.pressEnter])
        XCTAssertEqual(VoiceCommands.parse("Enter.", options: on), [.pressEnter])
    }

    func testMisheardScratchStillWorks() {
        XCTAssertEqual(VoiceCommands.parse("Ah, scratch there.", options: on), [.deleteLast])
        XCTAssertEqual(VoiceCommands.parse("Scratch this", options: on), [.deleteLast])
    }

    func testSentencesContainingCommandWordsStayText() {
        let sentence = "If I press enter it takes me to the tracks tab."
        XCTAssertEqual(VoiceCommands.parse(sentence, options: on), [.text(sentence)])
        XCTAssertEqual(VoiceCommands.parse("Press enter to continue", options: on), [.text("Press enter to continue")])
    }

    func testStandaloneCommandsAreIgnoredInsideSentences() {
        XCTAssertEqual(VoiceCommands.parse("Please select all the items.", options: on), [.text("Please select all the items.")])
        XCTAssertEqual(VoiceCommands.parse("You can undo that change later.", options: on), [.text("You can undo that change later.")])
    }

    func testInlineNewLineSplitsAndCapitalizes() {
        XCTAssertEqual(VoiceCommands.parse("Dear Sam new line thanks for the update", options: on),
                       [.text("Dear Sam"), .newLine, .text("Thanks for the update")])
        XCTAssertEqual(VoiceCommands.parse("Done. New paragraph. Next topic", options: on),
                       [.text("Done."), .newParagraph, .text("Next topic")])
    }

    func testScratchThatDeletesPreviousTyping() {
        XCTAssertEqual(VoiceCommands.parse("Scratch that.", options: on), [.deleteLast])
        XCTAssertEqual(VoiceCommands.parse("Send it tomorrow scratch that send it today", options: on), [.text("send it today")])
    }

    func testCommandsCanBeDisabled() {
        let off = VoiceCommandOptions(commands: false, spokenPunctuation: false)
        XCTAssertEqual(VoiceCommands.parse("New line", options: off), [.text("New line")])
    }

    func testSpokenPunctuation() {
        XCTAssertEqual(VoiceCommands.parse("Hello comma how are you question mark", options: punct), [.text("Hello, how are you?")])
        XCTAssertEqual(VoiceCommands.parse("Wait period it works", options: punct), [.text("Wait. It works")])
        XCTAssertEqual(VoiceCommands.parse("Call me open paren later close paren", options: punct), [.text("Call me (later)")])
        XCTAssertEqual(VoiceCommands.parse("He said open quote hi close quote", options: punct), [.text("He said \"hi\"")])
    }

    func testSpokenPunctuationReplacesWhispersOwnPunctuation() {
        XCTAssertEqual(VoiceCommands.parse("Hello, comma, how are you?", options: punct), [.text("Hello, how are you?")])
    }

    func testSpokenPunctuationIsOffByDefault() {
        XCTAssertEqual(VoiceCommands.parse("It was a long period of time", options: on), [.text("It was a long period of time")])
    }
}

@MainActor
final class SnippetTests: XCTestCase {
    private let sig = Snippet(trigger: "sign off snippet", expansion: "Best,\nNico")

    func testExpandsWholeUtteranceAndDropsTrailingPeriod() {
        XCTAssertEqual(SnippetExpander.expand("Sign off snippet.", snippets: [sig]), "Best,\nNico")
    }

    func testExpandsInsideText() {
        XCTAssertEqual(SnippetExpander.expand("Thanks a lot, sign off snippet", snippets: [sig]), "Thanks a lot, Best,\nNico")
    }

    func testPlaceholders() {
        let snippet = Snippet(trigger: "stamp", expansion: "{date} at {time}: {clipboard}")
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let out = SnippetExpander.expand("stamp", snippets: [snippet], now: date, clipboard: "copied")
        XCTAssertTrue(out.hasSuffix(": copied"))
        XCTAssertFalse(out.contains("{date}"))
        XCTAssertFalse(out.contains("{time}"))
    }

    func testLongestTriggerWinsAndNoPartialWords() {
        let a = Snippet(trigger: "my address", expansion: "ONE")
        let b = Snippet(trigger: "my address book", expansion: "TWO")
        XCTAssertEqual(SnippetExpander.expand("open my address book", snippets: [a, b]), "open TWO")
        XCTAssertEqual(SnippetExpander.expand("my addresses", snippets: [a]), "my addresses")
    }

    func testReplacementIsLiteral() {
        let s = Snippet(trigger: "price", expansion: "$5 \\1 $0")
        XCTAssertEqual(SnippetExpander.expand("the price", snippets: [s]), "the $5 \\1 $0")
    }

    func testPersistence() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("snip-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = SnippetStore(file: file)
        store.entries = [sig]
        XCTAssertEqual(SnippetStore(file: file).entries, [sig])
    }
}

@MainActor
final class HistoryTests: XCTestCase {
    private func makeStore() -> (HistoryStore, URL, URL) {
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("hist-\(UUID()).json")
        let last = dir.appendingPathComponent("last-\(UUID()).txt")
        Pref.registerDefaults()
        Pref.defaults.set(true, forKey: Pref.historyEnabled)
        return (HistoryStore(file: file, lastTranscriptFile: last), file, last)
    }

    func testAddSearchRemoveAndPersist() throws {
        let (store, file, last) = makeStore()
        defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: last) }
        store.add("Deploy looks good", app: "Slack")
        store.add("Buy oat milk", app: "Notes")
        XCTAssertEqual(store.entries.first?.text, "Buy oat milk")
        XCTAssertEqual(store.search("deploy").count, 1)
        XCTAssertEqual(store.search("notes").count, 1)
        XCTAssertEqual(try String(contentsOf: last), "Buy oat milk")
        XCTAssertEqual(HistoryStore(file: file, lastTranscriptFile: last).entries.count, 2)
        store.remove(store.entries[0].id)
        XCTAssertEqual(store.entries.count, 1)
    }

    func testDisabledHistoryStoresNothing() {
        let (store, file, last) = makeStore()
        defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: last) }
        Pref.defaults.set(false, forKey: Pref.historyEnabled)
        store.add("secret", app: "Mail")
        Pref.defaults.set(true, forKey: Pref.historyEnabled)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: last.path))
    }

    func testClearRemovesEverythingIncludingLastTranscript() {
        let (store, file, last) = makeStore()
        defer { try? FileManager.default.removeItem(at: file) }
        store.add("hello", app: "Mail")
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: last.path))
    }
}

@MainActor
final class ProfileTests: XCTestCase {
    private func store() -> ProfileStore {
        ProfileStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("prof-\(UUID()).json"))
    }

    func testFallsBackToGeneralSettings() {
        let s = store().effective(for: "com.example.app", pause: 0.8, language: "en")
        XCTAssertEqual(s, EffectiveSettings(pauseToCommit: 0.8, language: "en", tone: .standard, stripTrailingPeriod: false, extraTerms: ""))
    }

    func testProfileOverrides() {
        let st = store()
        st.profiles = [AppProfile(bundleID: "com.slack", name: "Slack", tone: .casual, pauseToCommit: 0.5, language: "es",
                                  stripTrailingPeriod: true, extraTerms: "Kubernetes")]
        let s = st.effective(for: "com.slack", pause: 0.8, language: "en")
        XCTAssertEqual(s.pauseToCommit, 0.5)
        XCTAssertEqual(s.language, "es")
        XCTAssertEqual(s.tone, .casual)
        XCTAssertTrue(s.stripTrailingPeriod)
        XCTAssertEqual(s.extraTerms, "Kubernetes")
    }

    func testAutoLanguageInProfileMeansDetect() {
        let st = store()
        st.profiles = [AppProfile(bundleID: "x", name: "X", language: "auto")]
        XCTAssertNil(st.effective(for: "x", pause: 0.8, language: "en").language)
    }

    func testStripTrailingPeriod() {
        XCTAssertEqual(TextPostProcessing.stripTrailingPeriod("Sounds good."), "Sounds good")
        XCTAssertEqual(TextPostProcessing.stripTrailingPeriod("Really?"), "Really?")
        XCTAssertEqual(TextPostProcessing.stripTrailingPeriod("Well..."), "Well...")
    }
}

final class CleanupPromptTests: XCTestCase {
    func testPromptReflectsToneAndLanguage() {
        let p = CleanupPrompts.cleanup(level: .polish, tone: .casual, outputLanguage: "Spanish", extraTerms: "Kubernetes")
        XCTAssertTrue(p.contains("informal"))
        XCTAssertTrue(p.contains("Spanish"))
        XCTAssertTrue(p.contains("Kubernetes"))
        XCTAssertTrue(p.contains("tidy awkward wording"))
        XCTAssertFalse(CleanupPrompts.cleanup(level: .light, tone: .standard, outputLanguage: nil).contains("tidy awkward"))
    }

    func testTidyStripsReasoningWrappersAndPreface() {
        XCTAssertEqual(CleanupPrompts.tidy("<think>hmm</think>\nHello there."), "Hello there.")
        XCTAssertEqual(CleanupPrompts.tidy("<transcript>\nHi.\n</transcript>"), "Hi.")
        XCTAssertEqual(CleanupPrompts.tidy("Here is the cleaned text:\nSee you at ten."), "See you at ten.")
        XCTAssertEqual(CleanupPrompts.tidy("Here is the plan for tomorrow"), "Here is the plan for tomorrow")
    }

    func testSanityCheck() {
        XCTAssertTrue(CleanupPrompts.isSane(output: "Send the report today.", input: "um send the report like today", translating: false))
        XCTAssertFalse(CleanupPrompts.isSane(output: "", input: "hello there friend", translating: false))
        XCTAssertFalse(CleanupPrompts.isSane(output: String(repeating: "blah ", count: 60), input: "hello there friend", translating: false))
        XCTAssertTrue(CleanupPrompts.isSane(output: "Hola a todos los presentes", input: "hello all", translating: true))
    }
}

final class AutomationTests: XCTestCase {
    private func parse(_ s: String) -> AutomationCommand? { AutomationCommand.parse(URL(string: s)!) }

    func testParsesCommands() {
        XCTAssertEqual(parse("saytype://dictation/toggle"), .dictation(.toggle))
        XCTAssertEqual(parse("saytype://dictation/off"), .dictation(.off))
        XCTAssertEqual(parse("saytype://dictation"), .dictation(.toggle))
        XCTAssertEqual(parse("saytype://record/start"), .record(.start))
        XCTAssertEqual(parse("saytype://meeting/stop"), .meeting(.stop))
        XCTAssertEqual(parse("saytype://edit"), .editSelection)
        XCTAssertEqual(parse("saytype://history/copy-last"), .copyLast)
        XCTAssertEqual(parse("saytype://settings"), .settings)
    }

    func testSpeakAndTranscribeArguments() {
        XCTAssertEqual(parse("saytype://speak?text=Hello%20world"), .speak("Hello world"))
        XCTAssertEqual(parse("saytype://speak"), .speak(nil))
        XCTAssertEqual(parse("saytype://transcribe?file=/tmp/a%20b.m4a"), .transcribe(URL(fileURLWithPath: "/tmp/a b.m4a")))
        XCTAssertNil(parse("saytype://transcribe"))
    }

    func testRejectsUnknown() {
        XCTAssertNil(parse("saytype://nope"))
        XCTAssertNil(parse("saytype://dictation/explode"))
        XCTAssertNil(parse("https://example.com"))
    }
}
