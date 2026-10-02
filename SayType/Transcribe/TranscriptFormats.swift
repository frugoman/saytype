import Foundation

struct TranscriptSegment: Equatable {
    var start: Double
    var end: Double
    var text: String
    var speaker: String?
}

/// A finished transcript and its export formats. Pure logic, no UI.
struct Transcript {
    var segments: [TranscriptSegment]
    var title: String
    var date: Date

    private struct Paragraph {
        var start: Double
        var speaker: String?
        var text: String
    }

    /// Consecutive segments from the same speaker become one paragraph (also split on long pauses).
    private func paragraphs() -> [Paragraph] {
        var result: [Paragraph] = []
        var lastEnd = 0.0
        for seg in segments {
            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if var last = result.last, last.speaker == seg.speaker, seg.start - lastEnd < 3 {
                last.text += " " + text
                result[result.count - 1] = last
            } else {
                result.append(Paragraph(start: seg.start, speaker: seg.speaker, text: text))
            }
            lastEnd = seg.end
        }
        return result
    }

    private func line(_ p: Paragraph) -> String {
        p.speaker.map { "\($0): \(p.text)" } ?? p.text
    }

    func plainText() -> String {
        paragraphs().map(line).joined(separator: "\n\n")
    }

    func srt() -> String {
        cues().enumerated().map { i, cue in
            "\(i + 1)\n\(Self.timestamp(cue.start, srt: true)) --> \(Self.timestamp(cue.end, srt: true))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    func vtt() -> String {
        let body = cues().map { cue in
            "\(Self.timestamp(cue.start, srt: false)) --> \(Self.timestamp(cue.end, srt: false))\n\(cue.text)\n"
        }.joined(separator: "\n")
        return "WEBVTT\n\n" + body
    }

    func markdown(timestamps: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        var out = "# \(title)\n\n*\(formatter.string(from: date))*\n\n"
        out += paragraphs().map { p in
            let stamp = timestamps ? "[\(Self.clock(p.start))] " : ""
            return stamp + (p.speaker.map { "**\($0):** \(p.text)" } ?? p.text)
        }.joined(separator: "\n\n")
        return out + "\n"
    }

    private func cues() -> [(start: Double, end: Double, text: String)] {
        segments.compactMap { seg in
            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return (seg.start, max(seg.end, seg.start), seg.speaker.map { "\($0): \(text)" } ?? text)
        }
    }

    /// `00:01:02,500` (SRT) or `00:01:02.500` (WebVTT). Rounds to the nearest millisecond.
    static func timestamp(_ seconds: Double, srt: Bool) -> String {
        let total = Int((max(0, seconds) * 1000).rounded())
        let (h, m, s, ms) = (total / 3_600_000, total / 60_000 % 60, total / 1000 % 60, total % 1000)
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, srt ? "," : ".", ms)
    }

    /// `12:05`, or `1:02:05` past an hour.
    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Interleaves the two tracks by time: your microphone is "You", what the Mac played is "Others".
    static func merge(mic: [TimedSegment], system: [TimedSegment]) -> [TranscriptSegment] {
        let you = mic.map { TranscriptSegment(start: $0.start, end: $0.end, text: $0.text, speaker: "You") }
        let others = system.map { TranscriptSegment(start: $0.start, end: $0.end, text: $0.text, speaker: "Others") }
        return (you + others).enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
    }
}
