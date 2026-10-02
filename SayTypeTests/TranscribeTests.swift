import AVFoundation
import XCTest

final class TranscriptFormatsTests: XCTestCase {
    func testTimestamps() {
        XCTAssertEqual(Transcript.timestamp(0, srt: true), "00:00:00,000")
        XCTAssertEqual(Transcript.timestamp(62.5, srt: true), "00:01:02,500")
        XCTAssertEqual(Transcript.timestamp(62.5, srt: false), "00:01:02.500")
        XCTAssertEqual(Transcript.timestamp(3725.25, srt: true), "01:02:05,250")
        XCTAssertEqual(Transcript.timestamp(1.9996, srt: true), "00:00:02,000")
        XCTAssertEqual(Transcript.timestamp(0.0004, srt: false), "00:00:00.000")
    }

    private func sample() -> Transcript {
        Transcript(segments: [
            TranscriptSegment(start: 0, end: 2, text: "Hello there.", speaker: "You"),
            TranscriptSegment(start: 2, end: 4, text: "How are you?", speaker: "You"),
            TranscriptSegment(start: 5, end: 7, text: "Fine, thanks.", speaker: "Others"),
        ], title: "Test", date: Date(timeIntervalSince1970: 0))
    }

    func testPlainTextMergesSameSpeaker() {
        XCTAssertEqual(sample().plainText(), "You: Hello there. How are you?\n\nOthers: Fine, thanks.")
        let plain = Transcript(segments: [TranscriptSegment(start: 0, end: 1, text: "A", speaker: nil),
                                          TranscriptSegment(start: 1, end: 2, text: "B", speaker: nil)], title: "", date: Date())
        XCTAssertEqual(plain.plainText(), "A B")
    }

    func testSRTAndVTT() {
        let srt = sample().srt()
        XCTAssertTrue(srt.hasPrefix("1\n00:00:00,000 --> 00:00:02,000\nYou: Hello there.\n"))
        XCTAssertTrue(srt.contains("3\n00:00:05,000 --> 00:00:07,000\nOthers: Fine, thanks."))
        let vtt = sample().vtt()
        XCTAssertTrue(vtt.hasPrefix("WEBVTT\n\n00:00:00.000 --> 00:00:02.000"))
    }

    func testMarkdown() {
        let md = sample().markdown()
        XCTAssertTrue(md.hasPrefix("# Test\n"))
        XCTAssertTrue(md.contains("[00:00] **You:** Hello there. How are you?"))
        XCTAssertTrue(md.contains("[00:05] **Others:** Fine, thanks."))
        XCTAssertFalse(sample().markdown(timestamps: false).contains("[00:00]"))
    }

    func testMergeOrdersByStart() {
        let merged = Transcript.merge(
            mic: [TimedSegment(start: 0, end: 1, text: "a"), TimedSegment(start: 4, end: 5, text: "c")],
            system: [TimedSegment(start: 2, end: 3, text: "b")])
        XCTAssertEqual(merged.map(\.text), ["a", "b", "c"])
        XCTAssertEqual(merged.map(\.speaker), ["You", "Others", "You"])
    }
}

final class AudioDecoderTests: XCTestCase {
    func testDecodesTo16kMono() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("tone.wav")

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let frames = AVAudioFrameCount(44_100) // 1 second
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for ch in 0..<2 {
            for i in 0..<Int(frames) { buffer.floatChannelData![ch][i] = 0.5 * sinf(Float(i) * 2 * .pi * 440 / 44_100) }
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            ])
            try file.write(from: buffer)
        } // file closes on release

        let samples = try await AudioDecoder.samples(from: url)
        XCTAssertEqual(Double(samples.count), 16_000, accuracy: 400)
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.3)
    }

    func testMissingFileThrows() async {
        do {
            _ = try await AudioDecoder.samples(from: URL(fileURLWithPath: "/nonexistent/file.mp3"))
            XCTFail("expected error")
        } catch {}
    }
}
