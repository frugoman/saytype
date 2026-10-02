import Foundation

/// Parakeet TDT v3 on the Neural Engine. Placeholder until the engine is implemented.
final class ParakeetEngine: SpeechToTextEngine {
    var translate = false
    var displayName: String { "Parakeet v3" }

    func prepare(progress: @escaping (Double, String) -> Void) async throws {
        throw NSError(domain: "SayType", code: 20, userInfo: [NSLocalizedDescriptionKey: "Parakeet isn't available yet."])
    }

    func transcribe(_ audio: [Float], prompt: String?, language: String?) async throws -> String { "" }
}
