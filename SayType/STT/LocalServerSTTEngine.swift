import Foundation

/// Sends audio to an OpenAI-compatible transcription server running on this Mac
/// (`POST {base}/v1/audio/transcriptions`). This is the "bring your own model" escape hatch:
/// whisper.cpp's server, speaches, LocalAI, mlx-audio, Parakeet servers, etc.
final class LocalServerSTTEngine: SpeechToTextEngine {
    let baseURL: URL
    let model: String
    var translate = false

    var displayName: String { "Server · \(model)" }

    init(baseURL: URL, model: String) {
        self.baseURL = baseURL
        self.model = model
    }

    private var endpoint: URL {
        if baseURL.path.hasSuffix("/transcriptions") || baseURL.path.hasSuffix("/translations") { return baseURL }
        return baseURL.appendingPathComponent(translate ? "v1/audio/translations" : "v1/audio/transcriptions")
    }

    func prepare(progress: @escaping (Double, String) -> Void) async throws {
        progress(0.5, "Connecting to \(baseURL.absoluteString)…")
        // A tiny silent clip checks the server is up without guessing a health endpoint.
        _ = try await transcribe([Float](repeating: 0, count: 8000), prompt: nil, language: "en")
        progress(1, "Ready")
    }

    func transcribe(_ audio: [Float], prompt: String?, language: String?) async throws -> String {
        let boundary = "SayType-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("response_format", "json")
        if let prompt { field("prompt", prompt) }
        if let language { field("language", language) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(WAV.encode(audio))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SayType", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Server error: \(msg.prefix(200))"])
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let text = json["text"] as? String {
            return text
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
