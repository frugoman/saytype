import XCTest
import AVFoundation
@testable import SayType

/// Network + model download; opt in with SAYTYPE_PARAKEET_TEST=1.
final class ParakeetEngineTests: XCTestCase {
    func testTranscribesSpeech() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SAYTYPE_PARAKEET_TEST"] != nil)
        let path = "/tmp/saytype-parakeet-test.aiff"
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", path, "The quick brown fox jumps over the lazy dog"]
        try say.run(); say.waitUntilExit()

        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let conv = AVAudioConverter(from: file.processingFormat, to: fmt)!
        let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inBuf)
        let outBuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 1024)!
        var fed = false
        var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, st in
            if fed { st.pointee = .endOfStream; return nil }
            fed = true; st.pointee = .haveData; return inBuf
        }
        XCTAssertNil(err)
        let samples = Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength)))

        let engine = ParakeetEngine()
        var t = Date()
        try await engine.prepare { p, m in print("prepare \(Int(p * 100))% \(m)") }
        print("PREPARE_SECONDS", Date().timeIntervalSince(t))
        for i in 1...3 {
            t = Date()
            let text = try await engine.transcribe(samples, prompt: nil, language: nil)
            print("TRANSCRIPT[\(i)]", text, "in", Date().timeIntervalSince(t), "s for", Double(samples.count) / 16_000, "s audio")
            if i == 1 { XCTAssertTrue(text.lowercased().contains("quick brown fox")) }
        }
        print("SEGMENTS", try await engine.transcribeSegments(samples, language: nil))
        print("SHORT", try await engine.transcribe([Float](repeating: 0, count: 800), prompt: nil, language: nil).debugDescription)
        print("EMPTY", try await engine.transcribe([], prompt: nil, language: nil).debugDescription)
    }
}
