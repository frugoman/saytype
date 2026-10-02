import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The "Transcribe" window: drop a file or record a meeting, then copy, save or summarize the result.
@MainActor
final class TranscribeWindow {
    static let shared = TranscribeWindow()
    private let model = TranscribeModel()
    private var window: NSWindow?

    var isRecordingMeeting: Bool { model.recorder.isRecording }

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

    private static let summaryInstruction = "Summarize this transcript in a few bullet points, then list any action items. Use the transcript's language."

    var isBusy: Bool { phase != .idle && phase != .done }

    func transcribe(file url: URL) {
        guard !isBusy else { return }
        begin(.decoding)
        task = Task {
            do {
                let samples = try await AudioDecoder.samples(from: url)
                try Task.checkCancellation()
                phase = .transcribing
                let segments = try await Self.transcribe(samples)
                try Task.checkCancellation()
                let name = url.deletingPathExtension().lastPathComponent
                finish(Transcript(segments: segments.map { TranscriptSegment(start: $0.start, end: $0.end, text: $0.text, speaker: nil) },
                                  title: name, date: Date()))
            } catch is CancellationError {
                phase = .idle
            } catch {
                fail(error)
            }
        }
    }

    func toggleMeeting() {
        if phase == .recording { stopMeeting(); return }
        guard !isBusy else { return }
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
        task = Task {
            let tracks = await recorder.stop()
            do {
                phase = .transcribing
                var mic: [TimedSegment] = [], system: [TimedSegment] = []
                if Self.hasSpeech(tracks.mic) { mic = try await Self.transcribe(tracks.mic) }
                try Task.checkCancellation()
                if Self.hasSpeech(tracks.system) { system = try await Self.transcribe(tracks.system) }
                try Task.checkCancellation()
                let merged = Transcript.merge(mic: mic, system: system)
                if merged.isEmpty { throw NSError(domain: "SayType", code: 12, userInfo: [NSLocalizedDescriptionKey: "No speech was detected in the recording."]) }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH.mm"
                finish(Transcript(segments: merged, title: "Meeting \(formatter.string(from: Date()))", date: Date()))
            } catch is CancellationError {
                phase = .idle
            } catch {
                fail(error)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .recording {
            Task { _ = await recorder.stop(); phase = .idle }
        } else {
            phase = .idle
        }
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

private struct TranscribeView: View {
    @ObservedObject var model: TranscribeModel
    @ObservedObject private var controller = AppController.shared
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 14) {
            switch model.phase {
            case .idle: idle
            case .recording: RecordingView(model: model, recorder: model.recorder)
            case .decoding, .transcribing: working
            case .done: result
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 440)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard let provider = providers.first, !model.isBusy else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in model.transcribe(file: url) } }
            }
            return true
        }
    }

    private var idle: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: "waveform.badge.plus").font(.system(size: 34)).foregroundStyle(.secondary)
                Text("Drop an audio or video file here").font(.headline)
                Text("mp3, m4a, wav, mp4, mov and more. It's transcribed on your Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Choose file…", action: chooseFile).controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6])))

            Button { model.toggleMeeting() } label: {
                Label("Record a meeting", systemImage: "record.circle")
            }
            .controlSize(.large)
            Text("Records your microphone and the sound playing on your Mac, then labels who said what.")
                .font(.caption).foregroundStyle(.secondary)
            if !controller.isModelReady {
                Text("The speech model is still loading…").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var working: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(model.phase == .decoding ? "Reading audio…" : "Transcribing… long recordings can take a few minutes")
                .foregroundStyle(.secondary)
            Button("Cancel") { model.cancel() }
            Spacer()
        }
    }

    private var result: some View {
        VStack(spacing: 10) {
            HStack {
                Text(model.transcript?.title ?? "").font(.headline).lineLimit(1)
                Spacer()
                Button("New") { model.reset() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let summary = model.summary {
                        Text("Summary").font(.subheadline.bold())
                        Text(summary).textSelection(.enabled)
                        Divider()
                        Text("Transcript").font(.subheadline.bold())
                    }
                    let text = model.transcript?.plainText() ?? ""
                    Text(text.isEmpty ? "No speech was detected." : text)
                        .textSelection(.enabled)
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Button("Copy", action: copy)
                Button("Save as…", action: save)
                if controller.aiAvailable {
                    Button(model.summary == nil ? "Summarize" : "Summarize again") { model.summarize() }
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

private struct RecordingView: View {
    @ObservedObject var model: TranscribeModel
    @ObservedObject var recorder: MeetingRecorder

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "record.circle.fill").font(.system(size: 40)).foregroundStyle(.red)
            Text(Transcript.clock(recorder.elapsed)).font(.system(size: 34, weight: .light, design: .monospaced))
            HStack(spacing: 8) {
                Image(systemName: "mic.fill").foregroundStyle(.secondary)
                ProgressView(value: min(1, Double(recorder.micLevel) * 8))
                    .frame(width: 160)
            }
            if let warning = recorder.warning {
                Text(warning).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            HStack {
                Button("Stop and transcribe") { model.stopMeeting() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button("Discard") { model.cancel() }.controlSize(.large)
            }
            Text("Live dictation is paused while recording.").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
