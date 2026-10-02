import Foundation

/// A speech-to-text backend. Implement this to add a new kind of model.
/// A stretch of transcribed speech with its position in the audio, in seconds.
struct TimedSegment: Equatable {
    var start: Double
    var end: Double
    var text: String
}

protocol SpeechToTextEngine: AnyObject {
    /// When true, speech in any language is translated to English instead of transcribed (Whisper only).
    var translate: Bool { get set }
    /// Human-readable name shown in the menu.
    var displayName: String { get }
    /// Download / load whatever the engine needs. `progress` is 0…1 when known.
    func prepare(progress: @escaping (Double, String) -> Void) async throws
    /// Transcribe 16 kHz mono audio. `prompt` biases the vocabulary, `language` is a Whisper code or nil for auto.
    func transcribe(_ audio: [Float], prompt: String?, language: String?) async throws -> String
    /// Transcribe long audio (a file or a meeting) with timestamps. 16 kHz mono.
    func transcribeSegments(_ audio: [Float], language: String?) async throws -> [TimedSegment]
}

extension SpeechToTextEngine {
    /// Engines without timestamps return the whole text as one segment.
    func transcribeSegments(_ audio: [Float], language: String?) async throws -> [TimedSegment] {
        let text = try await transcribe(audio, prompt: nil, language: language)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return [TimedSegment(start: 0, end: Double(audio.count) / 16_000, text: text)]
    }
}

enum TranscriptFilter {
    /// Phrases Whisper is known to invent on silence or noise.
    private static let hallucinations: Set<String> = [
        "thank you", "thanks for watching", "thank you for watching", "thanks for watching!",
        "you", "bye", "bye bye", "the end", "subtitles by the amara.org community",
        "please subscribe", "[blank_audio]", "[music]", "(music)", "[silence]", "(silence)",
        "gracias", "gracias por ver el video", "¡gracias por ver!", "subtítulos realizados por la comunidad de amara.org",
    ]

    static func clean(_ raw: String, prompt: String?) -> String? {
        var text = raw
            .replacingOccurrences(of: #"\[[A-Z_ ]+\]|\([a-z ]+\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        guard !text.isEmpty else { return nil }

        let normalized = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        if normalized.isEmpty || hallucinations.contains(normalized) { return nil }
        // Whisper sometimes parrots its prompt back when it hears nothing useful.
        if let prompt, text.count > 12, prompt.localizedCaseInsensitiveContains(text) { return nil }
        return text
    }
}

enum WAV {
    /// 16-bit PCM WAV for sending audio to local servers.
    static func encode(_ samples: [Float], sampleRate: Int = 16_000) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = samples.count * 2
        data.append("RIFF".data(using: .ascii)!); append(UInt32(36 + byteCount))
        data.append("WAVEfmt ".data(using: .ascii)!); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append("data".data(using: .ascii)!); append(UInt32(byteCount))
        for s in samples { append(Int16(max(-1, min(1, s)) * Float(Int16.max))) }
        return data
    }
}
