import Foundation

/// Lightweight, adaptive energy-based voice activity detector.
///
/// Tracks the room's noise floor continuously and treats audio that rises clearly above it as
/// speech. When the speaker pauses for `pauseToCommit` seconds the collected utterance is
/// emitted for transcription. Cheap enough to run all the time.
final class VoiceActivityDetector {
    struct Config {
        /// 0 = only loud, close speech; 1 = picks up quiet speech (and more noise).
        var sensitivity: Double = 0.5
        /// Silence (seconds) that ends an utterance.
        var pauseToCommit: Double = 0.8
        /// Utterances are force-emitted at this length so text keeps flowing during long monologues.
        var maxUtterance: Double = 25
        /// Shorter bursts than this (seconds of voiced audio) are ignored as clicks/coughs.
        var minVoiced: Double = 0.25
    }

    var config = Config()
    var onSpeechStart: (() -> Void)?
    var onUtterance: (([Float]) -> Void)?
    var onDebug: ((String) -> Void)?
    /// Current input level in dBFS, for a UI meter.
    private(set) var levelDB: Float = -90

    private let frameSize = Int(AudioCapture.sampleRate * 0.03) // 30 ms
    private var frameDuration: Double { Double(frameSize) / AudioCapture.sampleRate }
    private var pending: [Float] = []
    private var preRoll: [[Float]] = []
    private let preRollFrames = 10 // 300 ms kept from before speech was detected

    private var noiseFloor: Float = -60
    private var speechPeak: Float = -90
    /// How far (dB) below the speaker's recent loudness still counts as speech.
    private var pauseDrop: Float { Float(22 - 8 * config.sensitivity) }
    private var speaking = false
    private var voicedRun = 0
    private var silenceRun = 0
    private var voicedFrames = 0
    private var utterance: [Float] = []

    func reset() {
        pending.removeAll()
        preRoll.removeAll()
        utterance.removeAll()
        speaking = false
        voicedRun = 0
        silenceRun = 0
        voicedFrames = 0
    }

    func process(_ samples: [Float]) {
        pending.append(contentsOf: samples)
        while pending.count >= frameSize {
            let frame = Array(pending.prefix(frameSize))
            pending.removeFirst(frameSize)
            processFrame(frame)
        }
    }

    private var startDelta: Float { Float(18 - 12 * config.sensitivity) }  // 18 dB … 6 dB above floor
    private var keepDelta: Float { max(3, startDelta - 5) }
    private var absoluteMin: Float { Float(-50 - 10 * config.sensitivity) } // never trigger below this

    private func processFrame(_ frame: [Float]) {
        var sum: Float = 0
        for s in frame { sum += s * s }
        let rms = sqrt(sum / Float(frame.count))
        let db = 20 * log10(max(rms, 1e-7))
        levelDB = db

        if !speaking {
            updateNoiseFloor(db)
            preRoll.append(frame)
            if preRoll.count > preRollFrames { preRoll.removeFirst() }

            if db > noiseFloor + startDelta && db > absoluteMin {
                voicedRun += 1
                if voicedRun >= 3 { beginSpeech() }
            } else {
                voicedRun = 0
            }
            return
        }

        utterance.append(contentsOf: frame)
        // Track how loud the speaker is; a clear drop below that counts as a pause even in noisy
        // rooms where background sound never falls back to the pre-speech noise floor.
        speechPeak = max(db, speechPeak - 0.02)
        let voiced = db > noiseFloor + keepDelta && db > absoluteMin && db > speechPeak - pauseDrop
        if voiced {
            silenceRun = 0
            voicedFrames += 1
        } else {
            silenceRun += 1
            // Let the floor follow steady background noise during long speech.
            noiseFloor += (db - noiseFloor) * 0.02
        }

        let silence = Double(silenceRun) * frameDuration
        let length = Double(utterance.count) / AudioCapture.sampleRate
        if silence >= config.pauseToCommit || length >= config.maxUtterance {
            endSpeech(trimSilence: silence >= config.pauseToCommit)
        }
    }

    private func updateNoiseFloor(_ db: Float) {
        if db < noiseFloor {
            noiseFloor = noiseFloor * 0.8 + db * 0.2     // follow quiet rooms quickly
        } else {
            noiseFloor += (db - noiseFloor) * 0.01        // rise slowly with steady noise (fans, AC)
        }
        noiseFloor = min(max(noiseFloor, -85), -25)
    }

    private func beginSpeech() {
        speaking = true
        silenceRun = 0
        voicedFrames = voicedRun
        voicedRun = 0
        utterance = preRoll.flatMap { $0 }
        speechPeak = levelDB
        preRoll.removeAll()
        onSpeechStart?()
    }

    private func endSpeech(trimSilence: Bool) {
        var audio = utterance
        if trimSilence {
            // Drop most of the trailing silence but keep ~200 ms so words aren't clipped.
            let keep = Int(0.2 * AudioCapture.sampleRate)
            let trailing = silenceRun * frameSize
            let drop = max(0, trailing - keep)
            if drop < audio.count { audio.removeLast(drop) }
        }
        let voicedSeconds = Double(voicedFrames) * frameDuration
        let wasForced = !trimSilence

        utterance.removeAll()
        speaking = wasForced   // a forced split keeps listening mid-sentence
        silenceRun = 0
        voicedFrames = 0

        onDebug?("utterance \(String(format: "%.1f", Double(audio.count) / AudioCapture.sampleRate))s voiced \(String(format: "%.1f", voicedSeconds))s forced \(wasForced) floor \(Int(noiseFloor))dB peak \(Int(speechPeak))dB")
        if voicedSeconds >= config.minVoiced {
            onUtterance?(audio)
        }
    }
}
