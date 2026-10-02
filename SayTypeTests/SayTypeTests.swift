import XCTest

@MainActor
final class VocabularyTests: XCTestCase {
    private func store(_ entries: [VocabularyEntry]) -> VocabularyStore {
        let s = VocabularyStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("vocab-\(UUID()).json"))
        s.entries = entries
        return s
    }

    func testSpokenFormsAreCorrected() {
        let s = store([VocabularyEntry(term: "Next.js"), VocabularyEntry(term: "gira-planner"), VocabularyEntry(term: "SayType")])
        XCTAssertEqual(s.apply(to: "I deployed the next js app."), "I deployed the Next.js app.")
        XCTAssertEqual(s.apply(to: "open next dot js docs"), "open Next.js docs")
        XCTAssertEqual(s.apply(to: "Push gira planner to main"), "Push gira-planner to main")
        XCTAssertEqual(s.apply(to: "Say Type is running"), "SayType is running")
    }

    func testTaughtMishearingsAreCorrected() {
        let s = store([VocabularyEntry(term: "kubectl", soundsLike: ["cube cuttle", "cube control"])])
        XCTAssertEqual(s.apply(to: "Run cube cuttle get pods."), "Run kubectl get pods.")
        XCTAssertEqual(s.apply(to: "cube control apply"), "kubectl apply")
    }

    func testDoesNotReplaceInsideOtherWords() {
        let s = store([VocabularyEntry(term: "Gira", soundsLike: ["hera"])])
        XCTAssertEqual(s.apply(to: "The chimera is here"), "The chimera is here")
        XCTAssertEqual(s.apply(to: "hera is great"), "Gira is great")
    }

    func testPromptPutsUserTermsLast() {
        let s = store([VocabularyEntry(term: "gira-planner")])
        let prompt = s.prompt(includeCodeContext: true)!
        XCTAssertTrue(prompt.hasSuffix("Also: gira-planner."))
        s.entries = []
    }
}

final class FilterTests: XCTestCase {
    func testDropsHallucinations() {
        XCTAssertNil(TranscriptFilter.clean(" Thank you.", prompt: nil))
        XCTAssertNil(TranscriptFilter.clean("[BLANK_AUDIO]", prompt: nil))
        XCTAssertNil(TranscriptFilter.clean("Terms: GitHub, TypeScript", prompt: "Software dev. Terms: GitHub, TypeScript, JSON"))
        XCTAssertEqual(TranscriptFilter.clean("  Ship it  now. ", prompt: nil), "Ship it now.")
    }
}

final class VADTests: XCTestCase {
    private func tone(seconds: Double, amplitude: Float) -> [Float] {
        let n = Int(seconds * 16_000)
        return (0..<n).map { amplitude * sin(Float($0) * 2 * .pi * 220 / 16_000) }
    }
    private func noise(seconds: Double, amplitude: Float) -> [Float] {
        (0..<Int(seconds * 16_000)).map { _ in Float.random(in: -amplitude...amplitude) }
    }

    func testEmitsOneUtteranceAfterPause() {
        let vad = VoiceActivityDetector()
        var utterances: [[Float]] = []
        vad.onUtterance = { utterances.append($0) }
        vad.process(noise(seconds: 1.0, amplitude: 0.001))
        vad.process(tone(seconds: 1.5, amplitude: 0.2))
        XCTAssertTrue(utterances.isEmpty, "should wait for the pause")
        vad.process(noise(seconds: 1.2, amplitude: 0.001))
        XCTAssertEqual(utterances.count, 1)
        let seconds = Double(utterances[0].count) / 16_000
        XCTAssertGreaterThan(seconds, 1.5)
        XCTAssertLessThan(seconds, 2.3)
    }

    func testIgnoresBackgroundNoiseAndClicks() {
        let vad = VoiceActivityDetector()
        var count = 0
        vad.onUtterance = { _ in count += 1 }
        vad.process(noise(seconds: 3, amplitude: 0.003))
        vad.process(tone(seconds: 0.1, amplitude: 0.3))   // click
        vad.process(noise(seconds: 2, amplitude: 0.003))
        XCTAssertEqual(count, 0)
    }

    func testLongSpeechIsSplit() {
        let vad = VoiceActivityDetector()
        vad.config.maxUtterance = 5
        var count = 0
        vad.onUtterance = { _ in count += 1 }
        vad.process(noise(seconds: 0.5, amplitude: 0.001))
        vad.process(tone(seconds: 11, amplitude: 0.2))
        XCTAssertEqual(count, 2)
    }
}

/// End-to-end: synthesize speech with `say`, transcribe it with a small Whisper model.
final class WhisperIntegrationTests: XCTestCase {
    func testTranscribesSynthesizedSpeech() async throws {
        let dir = FileManager.default.temporaryDirectory
        let aiff = dir.appendingPathComponent("vt-test.wav")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", aiff.path, "--file-format=WAVE", "--data-format=LEF32@16000", "Please open the pull request on GitHub."]
        try say.run(); say.waitUntilExit()

        let file = try AVAudioFile(forReading: aiff)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))

        let engine = WhisperKitEngine(variant: "openai_whisper-base.en", repo: "argmaxinc/whisperkit-coreml")
        try await engine.prepare { _, _ in }
        let text = try await engine.transcribe(samples, prompt: "Software developer dictation: GitHub, PR.", language: "en")
        print("TRANSCRIPT:", text)
        XCTAssertTrue(text.lowercased().contains("request"), text)
        XCTAssertTrue(text.contains("GitHub"), text)

        // A taught mishearing fixes the small model's mistake.
        let vocab = await VocabularyStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("vocab-\(UUID()).json"))
        await MainActor.run { vocab.entries = [VocabularyEntry(term: "pull request", soundsLike: ["poll request"])] }
        let fixed = await vocab.apply(to: text)
        await MainActor.run { vocab.entries = [] }
        XCTAssertTrue(fixed.contains("pull request"), fixed)
    }
}

import AVFoundation
