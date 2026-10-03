import AppKit
import AVFoundation
import os

/// Captures microphone audio and delivers 16 kHz mono Float32 samples (what Whisper expects).
final class AudioCapture {
    static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: AudioCapture.sampleRate,
                                             channels: 1, interleaved: false)!
    private let log = Logger(subsystem: "SayType", category: "audio")
    private(set) var isRunning = false
    /// When audio last arrived from the microphone; used to notice a silently stopped engine.
    private var lastSampleAt = Date()
    private var observers: [NSObjectProtocol] = []
    /// Input level of the latest audio, in dBFS, for the on-screen indicator.
    private(set) var levelDB: Float = -90

    /// True when the engine claims to be running but no audio has arrived for a while.
    var isStalled: Bool { isRunning && Date().timeIntervalSince(lastSampleAt) > 2 }

    init() {
        // macOS stops the engine when the input device changes (headset connects, AirPods switch, default
        // mic changes) and after sleep. Without this the app says "Listening" while nothing is recorded.
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.log.notice("Audio device changed; restarting the microphone")
            self?.restart()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.log.notice("Woke from sleep; restarting the microphone")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.restart() }
        })
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    /// Tears the engine down and starts it again against the current input device.
    @discardableResult
    func restart() -> Bool {
        guard isRunning else { return false }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        do {
            try start()
            return true
        } catch {
            // No input device right now (headset still switching). The caller retries on its next tick.
            log.error("Microphone restart failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Called on the audio thread with each converted chunk.
    var onSamples: (([Float]) -> Void)?

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start() throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "SayType", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone available"])
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        lastSampleAt = Date()

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.convert(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
        log.info("Mic started")
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        log.info("Mic stopped")
    }

    private func convert(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData, out.frameLength > 0 else { return }
        lastSampleAt = Date()
        let samples = Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
        let meanSquare = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
        levelDB = 10 * log10(max(meanSquare, 1e-9))
        onSamples?(samples)
    }
}
