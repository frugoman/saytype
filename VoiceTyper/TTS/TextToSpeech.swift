import AVFoundation
import Foundation
import TTSKit

/// A text-to-speech backend. Implement this to add a new kind of voice model.
protocol TextToSpeechEngine: AnyObject {
    var displayName: String { get }
    func prepare(progress: @escaping (Double, String) -> Void) async throws
    /// Speaks and returns when finished (or throws on cancellation).
    func speak(_ text: String, language: String?) async throws
    func stop()
}

// MARK: - macOS voices

/// Built-in macOS voices. No download; install nicer "Premium" voices in
/// System Settings → Accessibility → Spoken Content → System Voice → Manage Voices.
final class SystemTTSEngine: NSObject, TextToSpeechEngine, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private let voiceID: String
    private let rate: Double
    private var continuation: CheckedContinuation<Void, Never>?

    var displayName: String { "macOS voice" }

    init(voiceID: String, rate: Double) {
        self.voiceID = voiceID
        self.rate = rate
        super.init()
        synth.delegate = self
    }

    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted {
            ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name)
        }
    }

    func prepare(progress: @escaping (Double, String) -> Void) async throws { progress(1, "Ready") }

    func speak(_ text: String, language: String?) async throws {
        let utterance = AVSpeechUtterance(string: text)
        if !voiceID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else if let language, let voice = AVSpeechSynthesisVoice(language: language) {
            utterance.voice = voice
        }
        utterance.rate = Float(Double(AVSpeechUtteranceDefaultSpeechRate) * rate)
        await withCheckedContinuation { cont in
            continuation = cont
            synth.speak(utterance)
        }
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { resume() }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { resume() }
    private func resume() {
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - Qwen3-TTS (on-device neural)

final class QwenTTSEngine: TextToSpeechEngine {
    private let variant: TTSModelVariant
    private let speaker: Qwen3Speaker
    private var tts: TTSKit?
    private var task: Task<Void, Error>?

    var displayName: String { "Qwen3-TTS \(variant.rawValue) · \(speaker.rawValue)" }

    init(variant: String, speaker: String) {
        self.variant = TTSModelVariant(rawValue: variant) ?? .qwen3TTS_0_6b
        self.speaker = Qwen3Speaker(rawValue: speaker) ?? .ryan
    }

    func prepare(progress: @escaping (Double, String) -> Void) async throws {
        progress(0.1, "Downloading Qwen3-TTS \(variant.rawValue) (first time only)…")
        let config = TTSKitConfig(model: variant, downloadBase: AppPaths.models, verbose: false, logLevel: .error)
        let kit = try await TTSKit(config)
        progress(0.7, "Loading voice model…")
        try await kit.loadModels()
        tts = kit
        progress(1, "Ready")
    }

    func speak(_ text: String, language: String?) async throws {
        guard let tts else { return }
        let lang = Self.language(for: language)
        let speaker = speaker
        let t = Task {
            _ = try await tts.play(text: text, speaker: speaker, language: lang)
        }
        task = t
        try await t.value
    }

    func stop() { task?.cancel() }

    private static func language(for code: String?) -> Qwen3Language {
        switch code {
        case "es": return .spanish
        case "pt": return .portuguese
        case "fr": return .french
        case "de": return .german
        case "it": return .italian
        case "ja": return .japanese
        case "zh": return .chinese
        case "ko": return .korean
        case "ru": return .russian
        default: return .english
        }
    }
}

// MARK: - Local server

/// Any OpenAI-compatible speech server on this Mac (`POST {base}/v1/audio/speech`),
/// e.g. Kokoro-FastAPI, speaches, LocalAI, mlx-audio.
final class LocalServerTTSEngine: TextToSpeechEngine {
    let baseURL: URL
    let model: String
    let voice: String
    let rate: Double
    private var player: AVAudioPlayer?
    private var finished: CheckedContinuation<Void, Never>?
    private var delegate: PlayerDelegate?

    var displayName: String { "Server · \(model) · \(voice)" }

    init(baseURL: URL, model: String, voice: String, rate: Double) {
        self.baseURL = baseURL
        self.model = model
        self.voice = voice
        self.rate = rate
    }

    func prepare(progress: @escaping (Double, String) -> Void) async throws { progress(1, "Ready") }

    func speak(_ text: String, language: String?) async throws {
        let url = baseURL.path.hasSuffix("/speech") ? baseURL : baseURL.appendingPathComponent("v1/audio/speech")
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "input": text, "voice": voice, "response_format": "wav", "speed": rate,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "VoiceTyper", code: 4, userInfo: [NSLocalizedDescriptionKey: "Speech server error"])
        }
        let player = try AVAudioPlayer(data: data)
        self.player = player
        await withCheckedContinuation { cont in
            finished = cont
            let d = PlayerDelegate { [weak self] in
                self?.finished?.resume()
                self?.finished = nil
            }
            delegate = d
            player.delegate = d
            player.play()
        }
    }

    func stop() {
        player?.stop()
        finished?.resume()
        finished = nil
    }

    private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully: Bool) { onFinish() }
    }
}
