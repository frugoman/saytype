import Foundation
import FluidAudio

/// NVIDIA Parakeet TDT v3 (Core ML, Neural Engine) via FluidAudio. 25 European languages,
/// automatic language detection. Prompt, language and translation are ignored.
final class ParakeetEngine: SpeechToTextEngine {
    var translate = false
    var displayName: String { "Parakeet · v3" }

    private static let sampleRate = 16_000
    private static let minSamples = 16_000 / 2   // library minimum is 0.3 s; pad up to 0.5 s
    private static let maxSegmentSeconds = 15.0

    private let manager = AsrManager(config: .default)   // actor: calls are serialized
    private var loaded = false

    /// Models live in <Application Support>/SayType/Models/<FluidAudio repo folder>.
    private var modelsDirectory: URL {
        AppPaths.models.appendingPathComponent(
            AsrModels.defaultCacheDirectory(for: .v3).lastPathComponent, isDirectory: true)
    }

    func prepare(progress: @escaping (Double, String) -> Void) async throws {
        if loaded { return }
        progress(0, "Downloading Parakeet…")
        let handler: ProgressHandler = { p in
            switch p.phase {
            case .listing:
                progress(0, "Downloading Parakeet…")
            case .downloading:
                progress(min(p.fractionCompleted, 1) * 0.9, "Downloading Parakeet…")
            case .compiling:
                progress(0.95, "Optimizing for this Mac…")
            }
        }
        let models = try await AsrModels.downloadAndLoad(
            to: modelsDirectory, version: .v3, progressHandler: handler)
        progress(0.98, "Optimizing for this Mac…")
        try await manager.loadModels(models)
        loaded = true
        progress(1, "Ready")
    }

    func transcribe(_ audio: [Float], prompt: String?, language: String?) async throws -> String {
        try await run(audio)?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func transcribeSegments(_ audio: [Float], language: String?) async throws -> [TimedSegment] {
        guard let result = try await run(audio) else { return [] }
        let fallback = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tokens = result.tokenTimings, !tokens.isEmpty else {
            guard !fallback.isEmpty else { return [] }
            return [TimedSegment(start: 0, end: Double(audio.count) / Double(Self.sampleRate), text: fallback)]
        }

        var segments: [TimedSegment] = []
        var text = ""
        var start: Double?
        var end = 0.0
        func flush() {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let s = start, !t.isEmpty { segments.append(TimedSegment(start: s, end: max(end, s), text: t)) }
            text = ""; start = nil
        }
        for tok in tokens {
            let piece = tok.token.replacingOccurrences(of: "\u{2581}", with: " ")
            if start == nil { start = tok.startTime }
            text += piece
            end = tok.endTime
            let last = piece.trimmingCharacters(in: .whitespaces).last
            let sentenceEnd = last.map { ".?!…。？！".contains($0) } ?? false
            if sentenceEnd || end - (start ?? end) >= Self.maxSegmentSeconds { flush() }
        }
        flush()
        return segments
    }

    private func run(_ audio: [Float]) async throws -> ASRResult? {
        guard loaded else { try await prepare { _, _ in }; return try await run(audio) }
        guard !audio.isEmpty else { return nil }
        var samples = audio
        if samples.count < Self.minSamples {
            samples += [Float](repeating: 0, count: Self.minSamples - samples.count)
        }
        var state = TdtDecoderState.make()
        return try await manager.transcribe(samples, decoderState: &state)
    }
}
