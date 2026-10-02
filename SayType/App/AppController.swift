import AppKit
import AVFoundation
import Combine
import CoreAudio
import os

/// Coordinates focus → microphone → voice detection → transcription → typing.
@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()

    enum Status: Equatable {
        case loading(Double, String)
        case idle                 // ready, waiting for a text field
        case listening            // text field focused, mic on
        case hearing              // speech detected
        case transcribing
        case speaking
        case disabled
        case needsMicPermission
        case needsAccessibility
        case error(String)
    }

    @Published private(set) var status: Status = .loading(0, "Starting…") {
        didSet {
            if case .loading = status, case .loading = oldValue { return } // don't log every progress tick
            if status != oldValue { log.notice("status: \(String(describing: self.status), privacy: .public)") }
        }
    }
    @Published private(set) var lastTranscript = ""
    @Published private(set) var sttName = ""
    @Published private(set) var ttsName = ""
    @Published private(set) var ttsStatus = ""
    @Published var enabled: Bool {
        didSet {
            Pref.defaults.set(enabled, forKey: Pref.enabled)
            refresh()
        }
    }

    let focus = FocusMonitor()
    let vocabulary = VocabularyStore()

    private let audio = AudioCapture()
    private let vad = VoiceActivityDetector()
    private let vadQueue = DispatchQueue(label: "SayType.vad", qos: .userInitiated)
    private let inserter = TextInserter()
    private let hotKeys = HotKeys()
    private let log = Logger(subsystem: "SayType", category: "app")

    private var stt: SpeechToTextEngine?
    private var sttReady = false
    private var tts: TextToSpeechEngine?
    private var ttsReady = false
    private var isSpeaking = false
    private var micPermission = false
    /// Where the user was typing when they started speaking; text goes there, not wherever focus is later.
    struct Target {
        let element: AXUIElement?
        let appName: String
        let pid: pid_t
    }
    private var utterances: AsyncStream<([Float], Target?)>.Continuation?
    private var speechTarget: Target?
    private var cancellables = Set<AnyCancellable>()
    private var stopMicWork: DispatchWorkItem?
    private var mediaTimer: Timer?
    private var mediaPlaying = false

    /// When set, captured utterances go here instead of being typed (used by "Teach by voice").
    private var teachHandler: ((String) -> Void)?

    private init() {
        Pref.registerDefaults()
        enabled = Pref.defaults.bool(forKey: Pref.enabled)
    }

    // MARK: - Lifecycle

    func start() {
        wireAudio()
        startTranscriptionLoop()

        focus.$state
            .removeDuplicates()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        focus.start()

        hotKeys.register(HotKeys.toggleListening) { [weak self] in self?.enabled.toggle() }
        hotKeys.register(HotKeys.speakSelection) { [weak self] in self?.speakSelection() }

        mediaTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkMedia() }
        }

        // Download/load the model while the user answers the permission prompts.
        Task { await reloadSpeechToText() }
        // Permission prompts are shown from the setup window, when the user asks for them.
        micPermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func wireAudio() {
        audio.onSamples = { [weak self] samples in
            guard let self else { return }
            self.vadQueue.async { self.vad.process(samples) }
        }
        vad.onSpeechStart = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.speechTarget = self.currentTarget()
                if self.status == .listening { self.status = .hearing }
            }
        }
        vad.onDebug = { [log] message in log.notice("vad: \(message, privacy: .public)") }
        vad.onUtterance = { [weak self] samples in
            DispatchQueue.main.async {
                guard let self else { return }
                // A forced split mid-sentence has no new speech start, so it keeps the same target.
                self.utterances?.yield((samples, self.speechTarget ?? self.currentTarget()))
            }
        }
        applyVADSettings()
    }

    func applyVADSettings() {
        let sensitivity = Pref.defaults.double(forKey: Pref.sensitivity)
        let pause = Pref.defaults.double(forKey: Pref.pauseToCommit)
        vadQueue.async { [vad] in
            vad.config.sensitivity = sensitivity
            vad.config.pauseToCommit = pause
        }
    }

    var isModelReady: Bool { sttReady }

    /// True when a permission is missing and the setup window should be shown.
    var needsSetup: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) != .authorized || !FocusMonitor.isTrusted
    }

    func permissionsChanged() {
        micPermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        refresh()
    }

    // MARK: - Mic on/off

    /// Decide whether the mic should be running right now.
    func refresh() {
        if case .loading = status, !sttReady { return }

        let wantsMic: Bool
        if teachHandler != nil {
            wantsMic = sttReady && micPermission
        } else {
            wantsMic = enabled && sttReady && micPermission && focus.state.canDictate && !isSpeaking && !mediaPlaying
        }

        if wantsMic {
            stopMicWork?.cancel()
            stopMicWork = nil
            if !audio.isRunning {
                vadQueue.async { [vad] in vad.reset() }
                do { try audio.start() } catch {
                    status = .error(error.localizedDescription)
                    return
                }
            }
        } else if audio.isRunning, stopMicWork == nil {
            // Short grace period so focus flicker (switching tabs, popovers) doesn't drop your words.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.stopMicWork = nil
                self.audio.stop()
                self.vadQueue.async { [vad = self.vad] in vad.reset() }
                self.updateStatus()
            }
            stopMicWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
        updateStatus()
    }

    private func updateStatus() {
        if case .loading = status, !sttReady { return }
        if case .error = status, !sttReady { return }
        if status == .transcribing || status == .hearing { return }
        if isSpeaking { status = .speaking; return }
        if !micPermission { status = .needsMicPermission; return }
        if focus.state == .noPermission { status = .needsAccessibility; return }
        if !enabled && teachHandler == nil { status = .disabled; return }
        status = audio.isRunning ? .listening : .idle
    }

    private func checkMedia() {
        // Pick up a microphone permission granted later in System Settings.
        if !micPermission, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            micPermission = true
            refresh()
        }
        guard Pref.defaults.bool(forKey: Pref.pauseWhileMediaPlays), !isSpeaking else {
            if mediaPlaying { mediaPlaying = false; refresh() }
            return
        }
        let playing = Self.isOutputDeviceBusy()
        if playing != mediaPlaying {
            mediaPlaying = playing
            refresh()
        }
    }

    /// True when any app is playing through the default output device (video, music, calls).
    private static func isOutputDeviceBusy() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr
        else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    // MARK: - Transcription

    private func startTranscriptionLoop() {
        let (stream, continuation) = AsyncStream<([Float], Target?)>.makeStream()
        utterances = continuation
        Task { [weak self] in
            for await (samples, target) in stream {
                await self?.handle(samples, target: target)
            }
        }
    }

    private func currentTarget() -> Target? {
        guard focus.state.canDictate else { return nil }
        let pid = focus.focusedElement.map(FocusMonitor.pid) ?? NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        return Target(element: focus.focusedElement, appName: focus.frontAppName, pid: pid)
    }

    private func handle(_ samples: [Float], target: Target?) async {
        guard let stt, sttReady else { return }
        status = .transcribing
        defer {
            status = .idle
            updateStatus()
        }

        let language = Pref.defaults.string(forKey: Pref.language).flatMap { $0 == "auto" ? nil : $0 }
        let teaching = teachHandler != nil
        // While teaching, transcribe without hints so we learn what the model hears on its own.
        let prompt = teaching ? nil : vocabulary.prompt(includeCodeContext: Pref.defaults.bool(forKey: Pref.codeContextPrompt))

        do {
            let start = Date()
            let raw = try await stt.transcribe(samples, prompt: prompt, language: language)
            log.notice("stt: \(raw.count, privacy: .public) chars in \(String(format: "%.1f", Date().timeIntervalSince(start)), privacy: .public)s: \(raw, privacy: .private)")
            guard let cleaned = TranscriptFilter.clean(raw, prompt: prompt) else {
                log.notice("stt: dropped as noise/hallucination")
                return
            }

            if let teachHandler {
                teachHandler(cleaned)
                return
            }
            let text = vocabulary.apply(to: cleaned)
            guard let target else {
                log.notice("insert: skipped, no text field was focused when speech started")
                return
            }
            let method = InsertionMethod(rawValue: Pref.defaults.string(forKey: Pref.insertionMethod) ?? "") ?? .auto
            let stillThere = focus.state.canDictate
                && (currentTarget()?.pid == target.pid)
                && (target.element == nil || focus.focusedElement.map { CFEqual($0, target.element!) } ?? false)
            if stillThere {
                inserter.insert(text, into: target.element, appName: target.appName, method: method)
            } else if let element = target.element,
                      inserter.insert(text, into: element, appName: target.appName, method: .accessibility) {
                log.notice("insert: focus moved, typed into the original field in \(target.appName, privacy: .public)")
            } else {
                // Never paste into whatever happens to be focused now; that's how text ends up in the wrong app.
                log.notice("insert: focus moved away from \(target.appName, privacy: .public), dropped")
                lastTranscript = text + "  (not typed: you switched away)"
                return
            }
            lastTranscript = text
        } catch {
            log.error("Transcription failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Engines

    func reloadSpeechToText() async {
        sttReady = false
        audio.stop()
        let kind = STTEngineKind(rawValue: Pref.defaults.string(forKey: Pref.sttEngine) ?? "") ?? .whisperKit
        let engine: SpeechToTextEngine
        switch kind {
        case .whisperKit:
            engine = WhisperKitEngine(
                variant: Pref.defaults.string(forKey: Pref.whisperModel) ?? WhisperModelOption.defaultID,
                repo: Pref.defaults.string(forKey: Pref.whisperRepo) ?? "argmaxinc/whisperkit-coreml")
        case .localServer:
            guard let url = URL(string: Pref.defaults.string(forKey: Pref.sttServerURL) ?? "") else {
                status = .error("Invalid server URL")
                return
            }
            engine = LocalServerSTTEngine(baseURL: url, model: Pref.defaults.string(forKey: Pref.sttServerModel) ?? "")
        }
        stt = engine
        sttName = engine.displayName
        status = .loading(0, "Loading \(engine.displayName)…")
        do {
            try await engine.prepare { [weak self] fraction, message in
                Task { @MainActor in
                    guard let self, self.stt === engine, !self.sttReady else { return }
                    self.status = .loading(fraction, message)
                }
            }
            guard stt === engine else { return } // a newer reload superseded this one
            sttReady = true
            status = .idle
            refresh()
        } catch {
            guard stt === engine else { return }
            log.error("STT load failed: \(String(describing: error), privacy: .public)")
            status = .error("Couldn't load \(engine.displayName): \(error.localizedDescription)")
        }
    }

    private func makeTTS() -> TextToSpeechEngine? {
        let kind = TTSEngineKind(rawValue: Pref.defaults.string(forKey: Pref.ttsEngine) ?? "") ?? .system
        let rate = Pref.defaults.double(forKey: Pref.speechRate)
        switch kind {
        case .system:
            return SystemTTSEngine(voiceID: Pref.defaults.string(forKey: Pref.systemVoice) ?? "", rate: rate)
        case .qwen:
            return QwenTTSEngine(variant: Pref.defaults.string(forKey: Pref.qwenModel) ?? "0.6b",
                                 speaker: Pref.defaults.string(forKey: Pref.qwenSpeaker) ?? "ryan")
        case .localServer:
            guard let url = URL(string: Pref.defaults.string(forKey: Pref.ttsServerURL) ?? "") else { return nil }
            return LocalServerTTSEngine(baseURL: url,
                                        model: Pref.defaults.string(forKey: Pref.ttsServerModel) ?? "",
                                        voice: Pref.defaults.string(forKey: Pref.ttsServerVoice) ?? "",
                                        rate: rate)
        }
    }

    /// Call after changing text-to-speech settings; the engine is (re)loaded on next use.
    func resetTextToSpeech() {
        tts?.stop()
        tts = nil
        ttsReady = false
        ttsStatus = ""
    }

    // MARK: - Text to speech

    func speakSelection() {
        if isSpeaking {
            tts?.stop()
            return
        }
        Task {
            guard let text = await TextInserter.selectedText() else {
                NSSound.beep()
                return
            }
            await speak(text)
        }
    }

    func speak(_ text: String) async {
        if tts == nil { tts = makeTTS() }
        guard let tts else { return }
        ttsName = tts.displayName
        if !ttsReady {
            do {
                try await tts.prepare { [weak self] _, message in
                    Task { @MainActor in self?.ttsStatus = message }
                }
                ttsReady = true
                ttsStatus = ""
            } catch {
                ttsStatus = "Voice failed to load: \(error.localizedDescription)"
                self.tts = nil
                return
            }
        }
        // Stop listening while talking so we don't transcribe ourselves.
        isSpeaking = true
        audio.stop()
        refresh()
        let language = Pref.defaults.string(forKey: Pref.language).flatMap { $0 == "auto" ? nil : $0 }
        do { try await tts.speak(text, language: language) } catch { log.info("Speech stopped: \(error.localizedDescription)") }
        isSpeaking = false
        refresh()
    }

    // MARK: - Teach by voice

    /// Listens for one utterance (regardless of focus) and returns what the model heard, unbiased.
    func captureOnce(timeout: TimeInterval = 8) async -> String? {
        guard sttReady else { return nil }
        return await withCheckedContinuation { cont in
            var resumed = false
            let finish: (String?) -> Void = { [weak self] text in
                guard !resumed else { return }
                resumed = true
                self?.teachHandler = nil
                self?.refresh()
                cont.resume(returning: text)
            }
            teachHandler = { finish($0) }
            refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}
