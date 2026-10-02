import Foundation
import SwiftUI

/// Which speech-to-text backend to use.
enum STTEngineKind: String, CaseIterable, Identifiable, Codable {
    case whisperKit       // bundled on-device Whisper (Core ML)
    case parakeet         // NVIDIA Parakeet TDT v3 on the Neural Engine (25 European languages, very fast)
    case localServer      // any OpenAI-compatible server on this Mac (whisper.cpp, speaches, mlx…)

    var id: String { rawValue }
    var label: String {
        switch self {
        case .whisperKit: return "Built-in Whisper (on-device)"
        case .parakeet: return "Parakeet v3 (on-device, fastest)"
        case .localServer: return "Local server (OpenAI-compatible)"
        }
    }
}

/// Which text-to-speech backend to use.
enum TTSEngineKind: String, CaseIterable, Identifiable, Codable {
    case system           // macOS voices, no download
    case qwen             // Qwen3-TTS via TTSKit, on-device neural voice
    case localServer      // any OpenAI-compatible /v1/audio/speech server (Kokoro-FastAPI, etc.)

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "macOS voices (no download)"
        case .qwen: return "Qwen3-TTS (on-device neural)"
        case .localServer: return "Local server (OpenAI-compatible)"
        }
    }
}

/// When SayType listens.
enum ListenMode: String, CaseIterable, Identifiable {
    case auto, pushToTalk, toggle

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Hands-free: listen whenever a text field has focus"
        case .pushToTalk: return "Push to talk: hold the shortcut while you speak"
        case .toggle: return "Toggle: press the shortcut to start and again to stop"
        }
    }
}

/// Which engine rewrites text (cleanup, voice-edit, translation, summaries).
enum AIBackendKind: String, CaseIterable, Identifiable {
    case apple, server

    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return "Apple on-device model (macOS 26+, no setup)"
        case .server: return "Local server (Ollama, LM Studio, llama.cpp, mlx_lm)"
        }
    }
}

/// How dictated text gets into the focused field.
enum InsertionMethod: String, CaseIterable, Identifiable, Codable {
    case auto, accessibility, paste

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Automatic"
        case .accessibility: return "Accessibility only (never touches clipboard)"
        case .paste: return "Paste (most compatible)"
        }
    }
}

/// Known WhisperKit Core ML models. Users can also type any other variant/repo.
struct WhisperModelOption: Identifiable, Hashable {
    let id: String      // variant name inside the repo
    let label: String

    static let recommended: [WhisperModelOption] = [
        .init(id: "openai_whisper-large-v3-v20240930_turbo_632MB", label: "Large v3 Turbo (best, 632 MB)"),
        .init(id: "distil-whisper_distil-large-v3_turbo_600MB", label: "Distil Large v3 Turbo (English, fast, 600 MB)"),
        .init(id: "openai_whisper-small.en_217MB", label: "Small English (light, 217 MB)"),
        .init(id: "openai_whisper-small_216MB", label: "Small multilingual (light, 216 MB)"),
        .init(id: "openai_whisper-base.en", label: "Base English (tiny, fastest)"),
    ]
    static let defaultID = recommended[0].id
}

/// All user preferences, stored in UserDefaults.
enum Pref {
    static let enabled = "enabled"
    static let sttEngine = "sttEngine"
    static let whisperModel = "whisperModel"
    static let whisperRepo = "whisperRepo"
    static let language = "language"
    static let sttServerURL = "sttServerURL"
    static let sttServerModel = "sttServerModel"
    static let ttsEngine = "ttsEngine"
    static let systemVoice = "systemVoice"
    static let qwenSpeaker = "qwenSpeaker"
    static let qwenModel = "qwenModel"
    static let ttsServerURL = "ttsServerURL"
    static let ttsServerModel = "ttsServerModel"
    static let ttsServerVoice = "ttsServerVoice"
    static let speechRate = "speechRate"
    static let sensitivity = "sensitivity"
    static let pauseToCommit = "pauseToCommit"
    static let insertionMethod = "insertionMethod"
    static let alwaysListenApps = "alwaysListenApps"
    static let pauseWhileMediaPlays = "pauseWhileMediaPlays"
    static let codeContextPrompt = "codeContextPrompt"
    static let listenMode = "listenMode"
    static let soundFeedback = "soundFeedback"
    static let showOverlay = "showOverlay"
    static let showCaretIndicator = "showCaretIndicator"
    static let historyEnabled = "historyEnabled"
    static let voiceCommands = "voiceCommands"
    static let spokenPunctuation = "spokenPunctuation"
    static let cleanupLevel = "cleanupLevel"
    static let aiBackend = "aiBackend"
    static let aiServerURL = "aiServerURL"
    static let aiServerModel = "aiServerModel"
    static let translateToEnglish = "translateToEnglish"
    static let outputLanguage = "outputLanguage"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            enabled: true,
            sttEngine: STTEngineKind.whisperKit.rawValue,
            whisperModel: WhisperModelOption.defaultID,
            whisperRepo: "argmaxinc/whisperkit-coreml",
            language: "en",
            sttServerURL: "http://127.0.0.1:8080",
            sttServerModel: "whisper-1",
            ttsEngine: TTSEngineKind.system.rawValue,
            systemVoice: "",
            qwenSpeaker: "ryan",
            qwenModel: "0.6b",
            ttsServerURL: "http://127.0.0.1:8880",
            ttsServerModel: "kokoro",
            ttsServerVoice: "af_heart",
            speechRate: 1.0,
            sensitivity: 0.5,
            pauseToCommit: 0.8,
            insertionMethod: InsertionMethod.auto.rawValue,
            alwaysListenApps: [String](),
            pauseWhileMediaPlays: false,
            codeContextPrompt: true,
            listenMode: ListenMode.auto.rawValue,
            soundFeedback: false,
            showOverlay: true,
            showCaretIndicator: true,
            historyEnabled: true,
            voiceCommands: true,
            spokenPunctuation: false,
            cleanupLevel: CleanupLevel.off.rawValue,
            aiBackend: AIBackendKind.apple.rawValue,
            aiServerURL: "http://127.0.0.1:11434",
            aiServerModel: "llama3.2",
            translateToEnglish: false,
            outputLanguage: "",
        ])
    }

    static var defaults: UserDefaults { .standard }
}

/// Where downloaded models and user data live (inside the sandbox container).
enum AppPaths {
    static var support: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SayType", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var models: URL {
        let url = support.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var vocabularyFile: URL { support.appendingPathComponent("vocabulary.json") }
    static var snippetsFile: URL { support.appendingPathComponent("snippets.json") }
    static var profilesFile: URL { support.appendingPathComponent("profiles.json") }
    static var historyFile: URL { support.appendingPathComponent("history.json") }
    /// Plain-text copies read by the `saytype` command-line tool.
    static var lastTranscriptFile: URL { support.appendingPathComponent("last-transcript.txt") }
    static var statusFile: URL { support.appendingPathComponent("status.txt") }
}

/// Whisper language codes offered in the UI.
let supportedLanguages: [(code: String, name: String)] = [
    ("auto", "Auto-detect"), ("en", "English"), ("es", "Spanish"), ("pt", "Portuguese"),
    ("fr", "French"), ("de", "German"), ("it", "Italian"), ("nl", "Dutch"), ("ja", "Japanese"),
    ("zh", "Chinese"), ("ko", "Korean"), ("ru", "Russian"), ("hi", "Hindi"),
    ("ar", "Arabic"), ("bg", "Bulgarian"), ("ca", "Catalan"), ("cs", "Czech"), ("da", "Danish"),
    ("el", "Greek"), ("fi", "Finnish"), ("he", "Hebrew"), ("hr", "Croatian"), ("hu", "Hungarian"),
    ("id", "Indonesian"), ("no", "Norwegian"), ("pl", "Polish"), ("ro", "Romanian"), ("sk", "Slovak"),
    ("sv", "Swedish"), ("th", "Thai"), ("tr", "Turkish"), ("uk", "Ukrainian"), ("vi", "Vietnamese"),
]

/// Languages the AI backend can write in ("Output language"), by English name.
let outputLanguages: [String] = [
    "English", "Spanish", "Portuguese", "French", "German", "Italian", "Dutch", "Japanese", "Chinese",
    "Korean", "Russian", "Hindi", "Arabic", "Polish", "Turkish", "Swedish", "Ukrainian",
]
