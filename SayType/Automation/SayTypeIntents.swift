import AppIntents
import Foundation

/// Actions for the Shortcuts app and Spotlight.
struct ToggleDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Dictation"
    static let description = IntentDescription("Turns SayType's dictation on or off.")
    static let openAppWhenRun = false

    @MainActor func perform() async throws -> some IntentResult {
        AppController.shared.run(.dictation(.toggle))
        return .result()
    }
}

struct StartDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Dictation"
    static let description = IntentDescription("Turns SayType's dictation on.")

    @MainActor func perform() async throws -> some IntentResult {
        AppController.shared.run(.dictation(.on))
        return .result()
    }
}

struct StopDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Dictation"
    static let description = IntentDescription("Turns SayType's dictation off.")

    @MainActor func perform() async throws -> some IntentResult {
        AppController.shared.run(.dictation(.off))
        return .result()
    }
}

struct SpeakTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Speak Text"
    static let description = IntentDescription("Reads text aloud with SayType's voice. Leave the text empty to read the current selection.")

    @Parameter(title: "Text") var text: String?

    @MainActor func perform() async throws -> some IntentResult {
        AppController.shared.run(.speak(text))
        return .result()
    }
}

struct GetLastTranscriptIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Last Transcript"
    static let description = IntentDescription("Returns the last text SayType typed. Needs history turned on.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: AppController.shared.history.last?.text ?? "")
    }
}

struct TranscribeFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Transcribe Audio File"
    static let description = IntentDescription("Transcribes an audio or video file on this Mac and returns the text.")

    @Parameter(title: "File") var file: IntentFile

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let url: URL
        if let existing = file.fileURL {
            url = existing
        } else {
            url = FileManager.default.temporaryDirectory.appendingPathComponent(file.filename)
            try file.data.write(to: url)
        }
        let samples = try await AudioDecoder.samples(from: url)
        let segments = try await AppController.shared.transcribeSegments(samples)
        return .result(value: segments.map(\.text).joined(separator: " "))
    }
}

struct SayTypeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ToggleDictationIntent(), phrases: ["Toggle dictation in \(.applicationName)"],
                    shortTitle: "Toggle Dictation", systemImageName: "mic")
        AppShortcut(intent: SpeakTextIntent(), phrases: ["Read aloud with \(.applicationName)"],
                    shortTitle: "Speak Text", systemImageName: "speaker.wave.2")
        AppShortcut(intent: TranscribeFileIntent(), phrases: ["Transcribe a file with \(.applicationName)"],
                    shortTitle: "Transcribe File", systemImageName: "waveform")
    }
}
