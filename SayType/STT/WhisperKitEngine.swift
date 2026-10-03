import Foundation
import WhisperKit

/// On-device Whisper via WhisperKit (Core ML, runs on the Neural Engine).
/// Any model in WhisperKit's Core ML format works, from Argmax's repo or your own Hugging Face repo.
final class WhisperKitEngine: SpeechToTextEngine {
    let variant: String
    let repo: String
    var translate = false
    private var whisper: WhisperKit?

    var displayName: String { "Whisper · \(variant.replacingOccurrences(of: "openai_whisper-", with: ""))" }

    init(variant: String, repo: String) {
        self.variant = variant
        self.repo = repo
    }

    func prepare(progress: @escaping (Double, String) -> Void) async throws {
        progress(0, "Downloading \(variant)…")
        let folder = try await WhisperKit.download(
            variant: variant,
            downloadBase: AppPaths.models,
            from: repo,
            progressCallback: { p in progress(p.fractionCompleted * 0.9, "Downloading model…") }
        )
        progress(0.9, "Optimizing model for this Mac (first time can take a few minutes)…")
        let config = WhisperKitConfig(
            modelFolder: folder.path,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        whisper = try await WhisperKit(config)
        progress(1, "Ready")
    }

    func transcribe(_ audio: [Float], prompt: String?, language: String?) async throws -> String {
        guard let whisper else { throw NSError(domain: "SayType", code: 2,
                                               userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]) }
        var promptTokens: [Int]?
        if let prompt, let tokenizer = whisper.tokenizer {
            promptTokens = tokenizer.encode(text: " " + prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        let options = DecodingOptions(
            task: translate ? .translate : .transcribe,
            language: language,
            temperatureFallbackCount: 2,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens,
            suppressBlank: true,
            noSpeechThreshold: 0.6
        )
        let results = try await whisper.transcribe(audioArray: audio, decodeOptions: options)
        return results
            .flatMap(\.segments)
            .filter { !($0.noSpeechProb > 0.6 && $0.avgLogprob < -1.0) }
            .map(\.text)
            .joined()
    }

    func transcribeSegments(_ audio: [Float], language: String?) async throws -> [TimedSegment] {
        guard let whisper else { throw NSError(domain: "SayType", code: 2,
                                               userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]) }
        let options = DecodingOptions(
            task: translate ? .translate : .transcribe,
            language: language,
            temperatureFallbackCount: 2,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            suppressBlank: true,
            noSpeechThreshold: 0.6,
            chunkingStrategy: .vad
        )
        let results = try await whisper.transcribe(audioArray: audio, decodeOptions: options)
        return results.flatMap(\.segments)
            .filter { !($0.noSpeechProb > 0.6 && $0.avgLogprob < -1.0) }
            .compactMap { segment in
                let text = segment.text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return TimedSegment(start: Double(segment.start), end: Double(segment.end), text: text)
            }
    }
}
