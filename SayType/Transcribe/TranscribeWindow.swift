import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The "Transcribe" window: drop a file or record a meeting, then copy, save or summarize the result.
@MainActor
final class TranscribeWindow {
    static let shared = TranscribeWindow()
    private let model = TranscribeModel()
    private var window: NSWindow?

    var isRecordingMeeting: Bool { model.recorder.isRecording || model.recorder.isStarting }

    /// Opens the window; with a file, starts transcribing it right away.
    func show(file: URL? = nil) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: TranscribeView(model: model)))
            w.title = "Transcribe"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 640, height: 560))
            w.minSize = NSSize(width: 520, height: 440)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if let file { model.transcribe(file: file) }
    }

    /// Starts a meeting recording, or stops and transcribes the one in progress.
    func toggleMeeting() {
        show()
        model.toggleMeeting()
    }
}

// MARK: - Model

@MainActor
final class TranscribeModel: ObservableObject {
    enum Phase: Equatable {
        case idle, recording, decoding, transcribing, done
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript: Transcript?
    @Published private(set) var summary: String?
    @Published private(set) var summarizing = false
    @Published var error: String?

    let recorder = MeetingRecorder()
    private var task: Task<Void, Never>?
    /// Bumped on every new job and on cancel, so a cancelled job that finishes late can't overwrite a newer one.
    private var generation = 0

    private static let summaryInstruction = "Summarize this transcript in a few bullet points, then list any action items. Use the transcript's language."

    var isBusy: Bool { phase != .idle && phase != .done }

    func transcribe(file url: URL) {
        guard !isBusy else { return }
        begin(.decoding)
        generation += 1
        let gen = generation
        task = Task {
            do {
                let samples = try await AudioDecoder.samples(from: url)
                try self.check(gen)
                phase = .transcribing
                let segments = try await Self.transcribe(samples)
                try self.check(gen)
                let name = url.deletingPathExtension().lastPathComponent
                finish(Transcript(segments: segments.map { TranscriptSegment(start: $0.start, end: $0.end, text: $0.text, speaker: nil) },
                                  title: name, date: Date()))
            } catch is CancellationError {
                if gen == generation { phase = .idle }
            } catch {
                if gen == generation { fail(error) }
            }
        }
    }

    private func check(_ gen: Int) throws {
        try Task.checkCancellation()
        if gen != generation { throw CancellationError() }
    }

    func toggleMeeting() {
        if phase == .recording { stopMeeting(); return }
        guard !isBusy, !recorder.isStarting else { return }
        guard AppController.shared.isModelReady else {
            error = "The speech model is still loading. Try again in a moment."
            return
        }
        error = nil
        task = Task {
            do {
                try await recorder.start()
                phase = .recording
            } catch {
                fail(error)
            }
        }
    }

    func stopMeeting() {
        guard phase == .recording else { return }
        phase = .decoding // brief: while the streams shut down
        generation += 1
        let gen = generation
        task = Task {
            let tracks = await recorder.stop()
            do {
                phase = .transcribing
                var mic: [TimedSegment] = [], system: [TimedSegment] = []
                if Self.hasSpeech(tracks.mic) { mic = try await Self.transcribe(tracks.mic) }
                try self.check(gen)
                if Self.hasSpeech(tracks.system) { system = try await Self.transcribe(tracks.system) }
                try self.check(gen)
                let merged = Transcript.merge(mic: mic, system: system)
                if merged.isEmpty { throw NSError(domain: "SayType", code: 12, userInfo: [NSLocalizedDescriptionKey: "No speech was detected in the recording."]) }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH.mm"
                finish(Transcript(segments: merged, title: "Meeting \(formatter.string(from: Date()))", date: Date()))
            } catch is CancellationError {
                if gen == generation { phase = .idle }
            } catch {
                if gen == generation { fail(error) }
            }
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        if phase == .recording {
            Task { _ = await recorder.stop(); phase = .idle }
        } else {
            phase = .idle
        }
    }

    /// Puts the model in a given state (used to render screenshots of each state).
    func preview(phase: Phase, transcript: Transcript? = nil, summary: String? = nil, error: String? = nil) {
        self.phase = phase; self.transcript = transcript; self.summary = summary; self.error = error
    }

    func reset() {
        transcript = nil
        summary = nil
        error = nil
        phase = .idle
    }

    func summarize() {
        guard let transcript, !summarizing else { return }
        summarizing = true
        error = nil
        Task {
            do {
                summary = try await AppController.shared.runAI(instruction: Self.summaryInstruction, input: transcript.plainText())
            } catch {
                self.error = error.localizedDescription
            }
            summarizing = false
        }
    }

    // MARK: Private

    private func begin(_ phase: Phase) {
        error = nil
        transcript = nil
        summary = nil
        self.phase = phase
    }

    private func finish(_ transcript: Transcript) {
        self.transcript = transcript
        phase = .done
    }

    private func fail(_ error: Error) {
        self.error = error.localizedDescription
        phase = transcript == nil ? .idle : .done
    }

    private static func transcribe(_ samples: [Float]) async throws -> [TimedSegment] {
        let controller = AppController.shared
        return try await controller.transcribeSegments(samples).compactMap { seg in
            guard let text = TranscriptFilter.clean(seg.text, prompt: nil) else { return nil }
            return TimedSegment(start: seg.start, end: seg.end, text: controller.vocabulary.apply(to: text))
        }
    }

    /// False for a track that is silence or faint noise (e.g. nobody spoke, or nothing played).
    private static func hasSpeech(_ samples: [Float]) -> Bool {
        let window = 8000 // 0.5 s
        var start = 0
        while start < samples.count {
            let end = min(start + window, samples.count)
            if MeetingRecorder.rms(Array(samples[start..<end])) > 0.004 { return true }
            start = end
        }
        return false
    }
}

// MARK: - View

struct TranscribeView: View {
    @ObservedObject var model: TranscribeModel
    @ObservedObject private var controller = AppController.shared
    @ObservedObject private var theme = Theme.shared
    @State private var targeted = false

    var body: some View {
        ZStack {
            PlayBackdrop()
            VStack(spacing: theme.space(14)) {
                Group {
                    switch model.phase {
                    case .idle: idle
                    case .recording: RecordingView(model: model, recorder: model.recorder)
                    case .decoding, .transcribing: working
                    case .done: result
                    }
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.bold(.peach))
                        .padding(theme.space(12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: theme.radius(14), style: .continuous).fill(theme.soft(.peach)))
                        .textSelection(.enabled)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(theme.space(22))
        }
        .frame(minWidth: 520, minHeight: 440)
        .playStyle()
        .playAnimation(value: model.phase)
        .playAnimation(value: model.error)
        .playAnimation(value: model.summary)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard let provider = providers.first, !model.isBusy else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in model.transcribe(file: url) } }
            }
            return true
        }
    }

    private var idle: some View {
        VStack(spacing: theme.space(16)) {
            VStack(spacing: theme.space(10)) {
                Image(systemName: targeted ? "arrow.down.circle.fill" : "waveform.badge.plus")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(targeted ? theme.accent : theme.bold(.blue))
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(targeted ? theme.accent.opacity(0.15) : theme.soft(.blue)))
                    .contentTransition(.symbolEffect(.replace))
                    .offset(y: targeted ? -4 : 0)
                Text(targeted ? "Drop it!" : "Drop an audio or video file here")
                    .font(.system(size: 19, weight: .heavy))
                Text("mp3, m4a, wav, mp4, mov and more. It's transcribed on your Mac.")
                    .font(.system(size: 13.5)).foregroundStyle(theme.inkSoft)
                Button("Choose file…", action: chooseFile).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: theme.radius(26), style: .continuous)
                .fill(targeted ? theme.accent.opacity(0.10) : theme.card))
            .overlay(RoundedRectangle(cornerRadius: theme.radius(26), style: .continuous)
                .strokeBorder(targeted ? theme.accent : theme.ink.opacity(0.22),
                              style: StrokeStyle(lineWidth: targeted ? 3 : 2, dash: [9, 7])))
            .scaleEffect(targeted ? 1.02 : 1)
            .shadow(color: theme.shadow, radius: targeted ? 22 : 12, y: 6)
            .animation(theme.spring, value: targeted)

            PlaySection(tint: .pink) {
                HStack(spacing: theme.space(14)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Record a meeting").font(.system(size: 15, weight: .bold))
                        Text("Records your microphone and the sound playing on your Mac, then labels who said what.")
                            .font(.system(size: 12.5)).foregroundStyle(theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button { model.toggleMeeting() } label: {
                        HStack(spacing: 7) {
                            PulsingDot(size: 10, color: .white)
                            Text("Record")
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                    }
                    .buttonStyle(RecordButtonStyle())
                }
                if !controller.isModelReady {
                    PlayChip(text: "The speech model is still loading…", tint: .butter, icon: "hourglass")
                }
            }
        }
    }

    private var working: some View {
        VStack(spacing: theme.space(16)) {
            Spacer()
            ProgressView().controlSize(.large)
                .frame(width: 88, height: 88)
                .background(Circle().fill(theme.soft(.blue)))
            Text(model.phase == .decoding ? "Reading audio…" : "Transcribing…")
                .font(.system(size: 20, weight: .heavy))
            if model.phase == .transcribing {
                Text("Long recordings can take a few minutes.").font(.system(size: 13.5)).foregroundStyle(theme.inkSoft)
            }
            Button("Cancel") { model.cancel() }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var result: some View {
        VStack(spacing: theme.space(12)) {
            HStack {
                Text(model.transcript?.title ?? "").font(.system(size: 19, weight: .heavy)).lineLimit(1)
                Spacer()
                Button("New") { model.reset() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: theme.space(14)) {
                    if let summary = model.summary {
                        PlaySection("Summary", tint: .butter) {
                            Text(summary).font(.system(size: 14)).textSelection(.enabled)
                        }
                    }
                    let text = model.transcript?.plainText() ?? ""
                    PlaySection("Transcript", tint: .blue) {
                        Text(text.isEmpty ? "No speech was detected." : text)
                            .font(.system(size: 14))
                            .textSelection(.enabled)
                            .foregroundStyle(text.isEmpty ? theme.inkSoft : theme.ink)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            HStack(spacing: 8) {
                Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button { save() } label: { Label("Save as…", systemImage: "square.and.arrow.down") }
                if controller.aiAvailable {
                    Button { model.summarize() } label: {
                        Label(model.summary == nil ? "Summarize" : "Summarize again", systemImage: "sparkles")
                    }
                    .disabled(model.summarizing)
                    if model.summarizing { ProgressView().controlSize(.small) }
                }
                Spacer()
            }
        }
    }

    // MARK: Actions

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.transcribe(file: url) }
    }

    private func copy() {
        guard let transcript = model.transcript else { return }
        var text = transcript.plainText()
        if let summary = model.summary { text = summary + "\n\n" + text }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func save() {
        guard let transcript = model.transcript else { return }
        let formats = ["txt", "srt", "vtt", "md"]
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.addItems(withTitles: ["Text (.txt)", "Subtitles (.srt)", "WebVTT (.vtt)", "Markdown (.md)"])
        let panel = NSSavePanel()
        panel.accessoryView = picker
        panel.nameFieldStringValue = "\(transcript.title).txt"
        let handler = FormatPicker { index in
            panel.nameFieldStringValue = (panel.nameFieldStringValue as NSString).deletingPathExtension + "." + formats[index]
        }
        picker.target = handler
        picker.action = #selector(FormatPicker.changed(_:))
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = handler // keep alive for the modal
        var body: String
        switch url.pathExtension.lowercased() {
        case "srt": body = transcript.srt()
        case "vtt": body = transcript.vtt()
        case "md": body = transcript.markdown()
        default: body = transcript.plainText()
        }
        if let summary = model.summary, ["txt", "md"].contains(url.pathExtension.lowercased()) {
            body = "Summary\n\n\(summary)\n\nTranscript\n\n" + body
        }
        do { try body.write(to: url, atomically: true, encoding: .utf8) } catch {
            model.error = "Couldn't save the file: \(error.localizedDescription)"
        }
    }
}

private final class FormatPicker: NSObject {
    let onChange: (Int) -> Void
    init(onChange: @escaping (Int) -> Void) { self.onChange = onChange }
    @objc func changed(_ sender: NSPopUpButton) { onChange(sender.indexOfSelectedItem) }
}

private struct RecordButtonStyle: ButtonStyle {
    @ObservedObject private var theme = Theme.shared
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(theme.bold(.pink)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A red dot that pulses gently (still when animations are off).
private struct PulsingDot: View {
    @ObservedObject private var theme = Theme.shared
    var size: CGFloat = 12
    var color: Color = .red
    @State private var on = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35)).frame(width: size, height: size)
                .scaleEffect(on ? 2.4 : 1).opacity(on ? 0 : 1)
            Circle().fill(color).frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard theme.animations, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { on = true }
        }
    }
}

private struct RecordingView: View {
    @ObservedObject var model: TranscribeModel
    @ObservedObject var recorder: MeetingRecorder
    @ObservedObject private var theme = Theme.shared

    var body: some View {
        VStack(spacing: theme.space(16)) {
            Spacer()
            ZStack {
                Circle().fill(theme.soft(.pink)).frame(width: 96, height: 96)
                PulsingDot(size: 28, color: Color(hex: 0xFF4D5E))
            }
            Text(Transcript.clock(recorder.elapsed))
                .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
            HStack(spacing: 10) {
                Image(systemName: "mic.fill").foregroundStyle(theme.bold(.pink))
                LevelBar(level: min(1, Double(recorder.micLevel) * 8)).frame(width: 180, height: 10)
            }
            if let warning = recorder.warning {
                Text(warning).font(.callout).foregroundStyle(theme.bold(.peach)).multilineTextAlignment(.center)
            }
            HStack {
                Button { model.stopMeeting() } label: {
                    Text("Stop and transcribe").padding(.horizontal, 8).padding(.vertical, 3)
                }
                .buttonStyle(.playPrimary)
                Button("Discard") { model.cancel() }
            }
            Text("Live dictation is paused while recording.").font(.caption).foregroundStyle(theme.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LevelBar: View {
    @ObservedObject private var theme = Theme.shared
    let level: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.ink.opacity(0.1))
                Capsule().fill(theme.bold(.pink)).frame(width: max(10, geo.size.width * level))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }
}
