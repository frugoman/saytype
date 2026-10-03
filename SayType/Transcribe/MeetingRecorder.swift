import AVFoundation
import CoreGraphics
import ScreenCaptureKit

/// Records a meeting as two separate 16 kHz mono tracks: system audio (the other people) and the microphone (you).
@MainActor
final class MeetingRecorder: ObservableObject {
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isRecording = false
    @Published private(set) var micLevel: Float = 0
    /// Set if system audio capture stopped by itself mid-meeting.
    @Published private(set) var warning: String?

    /// Per-track cap (4 hours at 16 kHz) so a forgotten recording can't eat all memory.
    static let maxSamples = 4 * 3600 * 16_000

    private let mic = SampleBuffer(limit: maxSamples)
    private let system = SampleBuffer(limit: maxSamples)
    private let engine = AVAudioEngine()
    private var stream: SCStream?
    private var sink: SystemAudioSink?
    private var timer: Timer?
    private var startedAt = Date()

    struct RecorderError: LocalizedError {
        let errorDescription: String?
    }

    func start() async throws {
        guard !isRecording else { return }

        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw RecorderError(errorDescription: "Microphone access is off. Turn on SayType in System Settings → Privacy & Security → Microphone.")
        }
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            throw RecorderError(errorDescription: "To record the other side of the call, allow SayType in System Settings → Privacy & Security → Screen & System Audio Recording, then try again.")
        }

        mic.reset()
        system.reset()
        warning = nil
        AppController.shared.meetingActive = true
        do {
            try await startSystemCapture()
            try startMic()
        } catch {
            await teardown()
            AppController.shared.meetingActive = false
            if (error as NSError).domain == SCStreamErrorDomain {
                throw RecorderError(errorDescription: "Couldn't capture system audio. Check that SayType is allowed under Screen & System Audio Recording in System Settings, then try again.")
            }
            throw error
        }

        startedAt = Date()
        elapsed = 0
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsed = Date().timeIntervalSince(self.startedAt)
            }
        }
    }

    func stop() async -> (mic: [Float], system: [Float]) {
        guard isRecording else { return ([], []) }
        isRecording = false
        timer?.invalidate()
        timer = nil
        await teardown()
        micLevel = 0
        AppController.shared.meetingActive = false
        return (mic.take(), system.take())
    }

    // MARK: - Capture

    private func startSystemCapture() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw RecorderError(errorDescription: "No display found to capture system audio from.")
        }
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // Video is required by the API but unused: the smallest, slowest frames possible.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 3

        let sink = SystemAudioSink(buffer: system) { [weak self] error in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.warning = "System audio capture stopped (\(error.localizedDescription)). Your microphone is still recording."
            }
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: sink)
        try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue) // discarded; avoids "no output" warnings
        try await stream.startCapture()
        self.stream = stream
        self.sink = sink
    }

    private func startMic() throws {
        let input = engine.inputNode
        let resampler = Resampler()
        let buffer = mic
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] pcm, _ in
            // Audio thread: only this closure touches `resampler`.
            let samples = resampler.convert(pcm)
            guard !samples.isEmpty else { return }
            buffer.append(samples)
            let level = Self.rms(samples)
            Task { @MainActor in self?.micLevel = level }
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    private func teardown() async {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        if let stream { try? await stream.stopCapture() }
        stream = nil
        sink = nil
    }

    nonisolated static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }
}

// MARK: - Helpers

/// Thread-safe, size-capped sample store (written from audio threads, read on stop).
final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    func append(_ new: [Float]) {
        lock.lock(); defer { lock.unlock() }
        let room = limit - samples.count
        guard room > 0 else { return }
        samples.append(contentsOf: new.prefix(room))
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        samples = []
    }

    func take() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        defer { samples = [] }
        return samples
    }
}

/// Converts PCM buffers of any format to 16 kHz mono Float32. Not thread-safe: use from one thread.
final class Resampler {
    private static let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard buffer.frameLength > 0 else { return [] }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: Self.target)
        }
        guard let converter else { return [] }
        let ratio = Self.target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.target, frameCapacity: capacity) else { return [] }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData, out.frameLength > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }
}

/// Receives ScreenCaptureKit audio on its own queue and appends it, resampled, to a buffer.
final class SystemAudioSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "SayType.meeting.system", qos: .userInitiated)
    private let buffer: SampleBuffer
    private let onStop: (Error) -> Void
    private let resampler = Resampler() // only used on `queue`

    init(buffer: SampleBuffer, onStop: @escaping (Error) -> Void) {
        self.buffer = buffer
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer),
              let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        let samples = resampler.convert(pcm)
        if !samples.isEmpty { buffer.append(samples) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { onStop(error) }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else { return nil }
        var streamDesc = asbd.pointee
        guard let format = AVAudioFormat(streamDescription: &streamDesc) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames),
                                                                  into: pcm.mutableAudioBufferList)
        return status == noErr ? pcm : nil
    }
}
