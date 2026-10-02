import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Talks to the text model that powers cleanup, voice-edit, translation and summaries.
/// Everything runs on this Mac: Apple's on-device model, or a server on localhost.
struct AIService {
    enum AIError: LocalizedError {
        case unavailable(String)
        case timedOut
        case badResponse(String)
        var errorDescription: String? {
            switch self {
            case .unavailable(let why): return why
            case .timedOut: return "The AI model took too long to answer."
            case .badResponse(let why): return "The AI server returned something unexpected: \(why)"
            }
        }
    }

    var backend: AIBackendKind
    var serverURL: URL?
    var serverModel: String

    static var current: AIService {
        AIService(backend: AIBackendKind(rawValue: Pref.defaults.string(forKey: Pref.aiBackend) ?? "") ?? .apple,
                  serverURL: URL(string: Pref.defaults.string(forKey: Pref.aiServerURL) ?? ""),
                  serverModel: Pref.defaults.string(forKey: Pref.aiServerModel) ?? "")
    }

    /// Why the backend can't be used right now, or nil when it's ready.
    var unavailableReason: String? {
        switch backend {
        case .apple:
            return Self.appleUnavailableReason()
        case .server:
            if serverURL == nil { return "The AI server address isn't valid." }
            if serverModel.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a model name for the AI server." }
            return nil
        }
    }

    var isAvailable: Bool { unavailableReason == nil }

    func complete(system: String, user: String, timeout: TimeInterval = 10) async throws -> String {
        if let reason = unavailableReason { throw AIError.unavailable(reason) }
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                switch backend {
                case .apple: return try await Self.appleComplete(system: system, user: user)
                case .server: return try await serverComplete(system: system, user: user, timeout: timeout)
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw AIError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw AIError.timedOut }
            return first
        }
    }

    // MARK: - Local server (OpenAI-compatible chat completions)

    private func serverComplete(system: String, user: String, timeout: TimeInterval) async throws -> String {
        guard let serverURL else { throw AIError.unavailable("The AI server address isn't valid.") }
        let endpoint = serverURL.path.hasSuffix("/chat/completions")
            ? serverURL
            : serverURL.appendingPathComponent(serverURL.path.hasSuffix("/v1") ? "chat/completions" : "v1/chat/completions")
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": serverModel,
            "temperature": 0.2,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIError.badResponse(String(data: data, encoding: .utf8)?.prefix(160).description ?? "no body")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.badResponse("missing choices[0].message.content")
        }
        return content
    }

    // MARK: - Apple on-device model

    private static func appleUnavailableReason() -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return "This Mac doesn't support Apple Intelligence. Use a local server instead."
                case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in System Settings, or use a local server."
                case .modelNotReady: return "Apple's on-device model is still downloading. Try again in a few minutes."
                @unknown default: return "Apple's on-device model isn't available."
                }
            }
        }
        #endif
        return "Apple's on-device model needs macOS 26 or later. Use a local server instead."
    }

    private static func appleComplete(system: String, user: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession(instructions: system)
            return try await session.respond(to: user).content
        }
        #endif
        throw AIError.unavailable("Apple's on-device model needs macOS 26 or later.")
    }
}

/// Applies the user's cleanup settings to a transcript. Never blocks typing for long and never loses text:
/// any failure returns the original.
struct TextCleaner {
    var service: AIService = .current

    func clean(_ text: String, level: CleanupLevel, tone: ToneStyle, outputLanguage: String?, extraTerms: String,
               timeout: TimeInterval = 8) async -> String {
        let translating = !(outputLanguage ?? "").isEmpty
        guard tone != .literal, level != .off || translating, service.isAvailable else { return text }
        // Very short utterances ("yes", "okay thanks") gain nothing and aren't worth the delay.
        guard translating || text.split(separator: " ").count >= 3 else { return text }
        let system = CleanupPrompts.cleanup(level: level == .off ? .light : level, tone: tone,
                                            outputLanguage: outputLanguage, extraTerms: extraTerms)
        do {
            let reply = try await service.complete(system: system, user: CleanupPrompts.wrap(text), timeout: timeout)
            let tidy = CleanupPrompts.tidy(reply)
            return CleanupPrompts.isSane(output: tidy, input: text, translating: translating) ? tidy : text
        } catch {
            Logger(subsystem: "SayType", category: "ai").notice("cleanup skipped: \(error.localizedDescription, privacy: .public)")
            return text
        }
    }

    /// Applies a spoken instruction ("make it shorter") to `text`. Throws so the caller can tell the user.
    func edit(_ text: String, instruction: String, timeout: TimeInterval = 20) async throws -> String {
        let reply = try await service.complete(system: CleanupPrompts.edit,
                                               user: CleanupPrompts.wrapEdit(instruction: instruction, text: text),
                                               timeout: timeout)
        let tidy = CleanupPrompts.tidy(reply)
        guard !tidy.isEmpty else { throw AIService.AIError.badResponse("empty answer") }
        return tidy
    }
}
