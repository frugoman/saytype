import SwiftUI

/// Extra screens to render in `--snapshot` mode (setup walkthrough, Transcribe window, overlays…).
@MainActor
enum ExtraSnapshots {
    static func items() -> [(name: String, view: AnyView, size: CGSize)] {
        var items: [(name: String, view: AnyView, size: CGSize)] = []

        for step in OnboardingView.Step.allCases {
            items.append((name: "onboarding-\(step.rawValue)-\(step)",
                          view: AnyView(OnboardingView(initialStep: step, onFinish: {})),
                          size: CGSize(width: 560, height: 540)))
        }

        let transcript = Transcript(
            segments: [
                TranscriptSegment(start: 0, end: 4, text: "Thanks everyone for joining. Let's start with the launch checklist.", speaker: "You"),
                TranscriptSegment(start: 4, end: 9, text: "The website is ready and the installer is signed. We only need to publish the release notes.", speaker: "Others"),
                TranscriptSegment(start: 9, end: 12, text: "Great, I'll write those today.", speaker: "You"),
            ],
            title: "Meeting 2026-10-03 14.30", date: Date())
        let states: [(String, (TranscribeModel) -> Void)] = [
            ("idle", { $0.preview(phase: .idle) }),
            ("recording", { $0.preview(phase: .recording) }),
            ("working", { $0.preview(phase: .transcribing) }),
            ("done", { $0.preview(phase: .done, transcript: transcript) }),
            ("summary", { $0.preview(phase: .done, transcript: transcript,
                                     summary: "• Launch checklist reviewed\n• Website ready, installer signed\n\nAction items: write the release notes (you, today).") }),
            ("error", { $0.preview(phase: .idle, error: "The speech model is still loading. Try again in a moment.") }),
        ]
        for (name, apply) in states {
            let model = TranscribeModel()
            apply(model)
            items.append((name: "transcribe-\(name)", view: AnyView(TranscribeView(model: model)), size: CGSize(width: 640, height: 560)))
        }

        let overlays: [(String, RecordingOverlay.Mode)] = [
            ("recording", .recording("Listening… release to type")),
            ("working", .working("Thinking…")),
            ("message", .message("Copied to clipboard")),
        ]
        var rows: [AnyView] = []
        for (_, mode) in overlays {
            let overlay = RecordingOverlay()
            overlay.preview(mode)
            rows.append(AnyView(OverlayView(overlay: overlay)))
        }
        items.append((name: "overlay-pills", view: AnyView(
            VStack(spacing: 6) { ForEach(0..<rows.count, id: \.self) { rows[$0] } }
                .padding(20).background(Color.gray.opacity(0.35))), size: CGSize(width: 340, height: 190)))

        let kinds: [CaretIndicator.Kind] = [.listening, .hearing, .working, .paused, .speaking, .off, .problem]
        let badges = kinds.map { kind -> CaretBadgeModel in
            let m = CaretBadgeModel(); m.kind = kind; m.level = 0.7; return m
        }
        items.append((name: "caret-badges", view: AnyView(
            HStack(spacing: 8) { ForEach(0..<badges.count, id: \.self) { CaretBadge(model: badges[$0]) } }
                .padding(16).background(Color.white.opacity(0.9))), size: CGSize(width: 290, height: 64)))
        return items
    }
}
