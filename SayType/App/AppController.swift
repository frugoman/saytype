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
            if status != oldValue {
                log.notice("status: \(String(describing: self.status), privacy: .public)")
                writeStatus()
            }
        }
    }
    @Published private(set) var lastTranscript = ""
    /// True while push-to-talk / toggle recording is capturing.
    @Published private(set) var manualRecording = false {
        didSet { if manualRecording != oldValue { writeStatus() } }
    }
    /// Shortcuts another app already owns.
    @Published private(set) var shortcutConflicts: [ShortcutAction] = []
    @Published private(set) var sttName = ""
    @Published private(set) var ttsName = ""
    @Published private(set) var ttsStatus = ""
    @Published var enabled: Bool {
        didSet {
            Pref.defaults.set(enabled, forKey: Pref.enabled)
            refresh()
        }
    }

    /// True while a meeting is being recorded; live dictation pauses so it doesn't type the meeting.
    var meetingActive = false { didSet { refresh() } }

    let focus = FocusMonitor()
    let vocabulary = VocabularyStore()
    let snippets = SnippetStore()
    let profiles = ProfileStore()
    let history = HistoryStore()

    private let audio = AudioCapture()
    private let caretIndicator = CaretIndicator()

    /// Live microphone level for the caret badge; very low when the mic isn't running.
    var micLevelDB: Float { audio.isRunning ? audio.levelDB : -90 }
    /// True when the mic is supposed to be on but no audio is arriving.
    var micStalled: Bool { audio.isStalled }
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
        /// Push-to-talk targets whatever is in front, even when the app doesn't report text fields.
        var forced = false
        var bundleID: String? { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }
    }
    /// One piece of speech to transcribe. `teach` is the voice-edit / teach capture that was active when
    /// it was recorded: where it goes is decided then, not when transcription finishes.
    private struct Utterance {
        let samples: [Float]
        let target: Target?
        var teach: ((String) -> Void)? = nil
    }
    private var utterances: AsyncStream<Utterance>.Continuation?
    private var manualFlush: (work: DispatchWorkItem, target: Target?)?
    private var speakBusy = false
    private var speechTarget: Target?
    private var cancellables = Set<AnyCancellable>()
    private var stopMicWork: DispatchWorkItem?
    private var mediaTimer: Timer?
    private var mediaPlaying = false
    private var manualTail = false
    private var manualTarget: Target?
    private var editing = false
    private var lastExternalApp: NSRunningApplication?
    private var lastTyped: (count: Int, pid: pid_t, date: Date)?
    /// The voice detector is inside a stretch of speech right now.
    private var vadSpeaking = false
    /// Utterances being transcribed (they can overlap with new speech).
    private var transcribing = 0

    /// Where microphone samples go. Only touched on `vadQueue`.
    private enum Route { case vad, manual, drop }
    private final class Capture {
        var route = Route.vad
        var buffer: [Float] = []
    }
    private let capture = Capture()

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

        focus.$frontBundleID
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyVADSettings() }
            .store(in: &cancellables)
        registerHotKeys()
        trackFrontmostApp()
        caretIndicator.start(controller: self)

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
            self.vadQueue.async {
                switch self.capture.route {
                case .vad: self.vad.process(samples)
                case .manual:
                    // About 10 minutes at 16 kHz; longer than anyone holds a key.
                    if self.capture.buffer.count < 9_600_000 { self.capture.buffer.append(contentsOf: samples) }
                case .drop: break
                }
            }
        }
        vad.onSpeechStart = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.speechTarget = self.currentTarget()
                self.vadSpeaking = true
                self.updateStatus()
            }
        }
        vad.onSpeechEnd = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.vadSpeaking else { return }
                self.vadSpeaking = false
                self.updateStatus()
            }
        }
        vad.onDebug = { [log] message in log.notice("vad: \(message, privacy: .public)") }
        vad.onUtterance = { [weak self] samples in
            DispatchQueue.main.async {
                guard let self else { return }
                // A forced split mid-sentence has no new speech start, so it keeps the same target.
                self.utterances?.yield(Utterance(samples: samples, target: self.speechTarget ?? self.currentTarget(),
                                                 teach: self.teachHandler))
            }
        }
        applyVADSettings()
    }

    func applyVADSettings() {
        let sensitivity = Pref.defaults.double(forKey: Pref.sensitivity)
        let pause = profiles.effective(for: focus.frontBundleID,
                                       pause: Pref.defaults.double(forKey: Pref.pauseToCommit),
                                       language: nil).pauseToCommit
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
        if teachHandler != nil || manualRecording || manualTail {
            wantsMic = sttReady && micPermission && !isSpeaking
        } else if listenMode != .auto {
            wantsMic = false
        } else {
            wantsMic = enabled && !meetingActive && sttReady && micPermission && focus.state.canDictate && !isSpeaking && !mediaPlaying
        }

        syncRoute()
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
            DispatchQueue.main.asyncAfter(deadline: .now() + (listenMode == .auto ? 1.0 : 0), execute: work)
        }
        updateStatus()
    }

    /// Derives the status from the real state (mic running, speech in progress, transcribing), so the
    /// menu, the caret badge and `saytype status` never show a state the mic isn't actually in.
    private func updateStatus() {
        if case .loading = status, !sttReady { return }
        if case .error = status, !sttReady { return }
        if isSpeaking { status = .speaking; return }
        if !micPermission { status = .needsMicPermission; return }
        if focus.state == .noPermission { status = .needsAccessibility; return }
        if audio.isRunning && vadSpeaking { status = .hearing; return }
        if transcribing > 0 { status = .transcribing; return }
        if !enabled && teachHandler == nil && !manualRecording { status = .disabled; return }
        status = audio.isRunning ? .listening : .idle
    }

    /// Why the mic is off while a text field has focus, for the caret badge and the menu.
    var pauseReason: String? {
        guard status == .idle else { return nil }
        if meetingActive { return "Paused while a meeting is recorded" }
        if listenMode != .auto {
            let keys = ShortcutAction.pushToTalk.shortcut.label
            return listenMode == .toggle ? "Press \(keys) to talk" : "Hold \(keys) to talk"
        }
        if mediaPlaying { return "Paused while other audio plays" }
        if !sttReady { return "The speech model isn't ready yet" }
        return nil
    }

    private func checkMedia() {
        // The engine can die without telling us (device switch, sleep). Restart it, or retry if the
        // microphone isn't available yet, so "Listening" always means the mic is really on.
        if audio.isStalled {
            log.notice("mic: no audio for 2s, restarting")
            audio.restart()
            updateStatus()
        } else if !audio.isRunning, stopMicWork == nil {
            refresh()
        }

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
        let (stream, continuation) = AsyncStream<Utterance>.makeStream()
        utterances = continuation
        Task { [weak self] in
            for await utterance in stream {
                await self?.handle(utterance)
            }
        }
    }

    private func currentTarget() -> Target? {
        guard focus.state.canDictate else { return nil }
        let pid = focus.focusedElement.map(FocusMonitor.pid) ?? NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        return Target(element: focus.focusedElement, appName: focus.frontAppName, pid: pid)
    }

    /// Push-to-talk target: whatever is in front, unless it's a password field.
    private func forcedTarget() -> Target? {
        if focus.state == .secure { return nil }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        return Target(element: focus.focusedElement, appName: focus.frontAppName, pid: pid, forced: true)
    }

    private func isStillThere(_ target: Target) -> Bool {
        let elementMatches = target.element == nil
            || (focus.focusedElement.map { CFEqual($0, target.element!) } ?? false)
        if target.forced {
            return NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid && elementMatches
        }
        return focus.state.canDictate && currentTarget()?.pid == target.pid && elementMatches
    }

    private var language: String? {
        Pref.defaults.string(forKey: Pref.language).flatMap { $0 == "auto" ? nil : $0 }
    }

    private func handle(_ utterance: Utterance) async {
        let target = utterance.target
        guard let stt, sttReady else {
            // The model is reloading; don't leave "Transcribing…" on screen.
            if target?.forced == true { RecordingOverlay.shared.hide() }
            return
        }
        let samples = utterance.samples
        let teachHandler = utterance.teach
        // Said before a voice edit started: typing it now would overwrite the selection being edited.
        if teachHandler == nil, editing, target?.forced != true {
            log.notice("stt: dropped speech from before the voice edit")
            return
        }
        transcribing += 1
        updateStatus()
        defer {
            transcribing -= 1
            updateStatus()
            if target?.forced == true { RecordingOverlay.shared.hide() }
        }

        let settings = profiles.effective(for: target?.bundleID,
                                          pause: Pref.defaults.double(forKey: Pref.pauseToCommit), language: language)
        let teaching = teachHandler != nil
        // While teaching, transcribe without hints so we learn what the model hears on its own.
        var prompt: String?
        if !teaching {
            prompt = vocabulary.prompt(includeCodeContext: Pref.defaults.bool(forKey: Pref.codeContextPrompt) || settings.tone == .code)
            let extra = settings.extraTerms.trimmingCharacters(in: .whitespacesAndNewlines)
            if !extra.isEmpty { prompt = (prompt.map { $0 + " " } ?? "") + "Also: " + extra + "." }
        }
        stt.translate = Pref.defaults.bool(forKey: Pref.translateToEnglish) && !teaching

        do {
            let start = Date()
            let raw = try await stt.transcribe(samples, prompt: prompt, language: teaching ? language : settings.language)
            log.notice("stt: \(raw.count, privacy: .public) chars in \(String(format: "%.1f", Date().timeIntervalSince(start)), privacy: .public)s: \(raw, privacy: .private)")
            guard let cleaned = TranscriptFilter.clean(raw, prompt: prompt) else {
                log.notice("stt: dropped as noise/hallucination")
                return
            }

            if let teachHandler {
                teachHandler(cleaned)
                return
            }
            guard let target else {
                log.notice("insert: skipped, no text field was focused when speech started")
                return
            }
            let actions = await buildActions(from: vocabulary.apply(to: cleaned), settings: settings)
            guard !actions.isEmpty else { return }
            await perform(actions, target: target)
        } catch {
            log.error("Transcription failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Voice commands, snippets, cleanup and per-app tweaks, in that order.
    private func buildActions(from text: String, settings: EffectiveSettings) async -> [DictationAction] {
        let options = VoiceCommandOptions(commands: Pref.defaults.bool(forKey: Pref.voiceCommands),
                                          spokenPunctuation: Pref.defaults.bool(forKey: Pref.spokenPunctuation))
        var actions = VoiceCommands.parse(text, options: options)
        let level = CleanupLevel(rawValue: Pref.defaults.string(forKey: Pref.cleanupLevel) ?? "") ?? .off
        let outputLanguage = Pref.defaults.string(forKey: Pref.outputLanguage)
        let cleaner = TextCleaner()
        let clipboard = snippets.entries.contains { $0.expansion.contains("{clipboard}") }
            ? NSPasteboard.general.string(forType: .string) : nil

        for index in actions.indices {
            guard case .text(let chunk) = actions[index] else { continue }
            let expanded = snippets.expand(chunk, clipboard: clipboard)
            if expanded != chunk {
                actions[index] = .text(expanded)
                continue
            }
            let cleanedChunk = await cleaner.clean(chunk, level: level, tone: settings.tone,
                                                    outputLanguage: outputLanguage, extraTerms: settings.extraTerms)
            actions[index] = .text(cleanedChunk)
        }
        if settings.stripTrailingPeriod, let last = actions.indices.last, case .text(let t) = actions[last] {
            actions[last] = .text(TextPostProcessing.stripTrailingPeriod(t))
        }
        return actions
    }

    private func perform(_ actions: [DictationAction], target: Target) async {
        let method = InsertionMethod(rawValue: Pref.defaults.string(forKey: Pref.insertionMethod) ?? "") ?? .auto
        let typedText = actions.compactMap { action -> String? in
            if case .text(let t) = action { return t } else { return nil }
        }.joined(separator: " ")
        let stillThere = isStillThere(target)

        if !stillThere {
            lastTyped = nil // it went to another field (or nowhere); "scratch that" must not backspace here
            // Never paste into whatever happens to be focused now; that's how text ends up in the wrong app.
            let original = target.element.flatMap { element in
                actions.allSatisfy({ if case .text = $0 { return true } else { return false } })
                    ? inserter.insert(typedText, into: element, appName: target.appName, method: .accessibility) : nil
            }
            if original == true {
                log.notice("insert: focus moved, typed into the original field in \(target.appName, privacy: .public)")
            } else {
                log.notice("insert: focus moved away from \(target.appName, privacy: .public), dropped")
                lastTranscript = typedText + "  (not typed: you switched away)"
                return
            }
        } else {
            var typedCount = 0
            for (index, action) in actions.enumerated() {
                if index > 0 { try? await Task.sleep(for: .milliseconds(90)) }
                switch action {
                case .text(let t):
                    if inserter.insert(t, into: target.element, appName: target.appName, method: method) {
                        typedCount += inserter.lastInsertedCount
                    }
                case .newLine:
                    TextInserter.postKey(36, flags: .maskShift); typedCount += 1
                    inserter.resetSpacing()
                case .newParagraph:
                    TextInserter.postKey(36, flags: .maskShift)
                    TextInserter.postKey(36, flags: .maskShift); typedCount += 2
                    inserter.resetSpacing()
                case .pressEnter:
                    TextInserter.postKey(36, flags: [])
                    inserter.resetSpacing()
                    lastTyped = nil; typedCount = 0 // the message was sent; nothing left to scratch
                    RecordingOverlay.shared.show(.message("↩ Enter"), hideAfter: 1.4)
                case .undo:
                    TextInserter.postKey(6, flags: .maskCommand)
                    inserter.resetSpacing()
                    lastTyped = nil; typedCount = 0
                    RecordingOverlay.shared.show(.message("↶ Undo"), hideAfter: 1.4)
                case .selectAll:
                    TextInserter.postKey(0, flags: .maskCommand)
                    inserter.resetSpacing()
                    lastTyped = nil; typedCount = 0
                    RecordingOverlay.shared.show(.message("Selected all"), hideAfter: 1.4)
                case .deleteLast:
                    if let last = lastTyped, last.pid == target.pid, Date().timeIntervalSince(last.date) < 120, last.count > 0 {
                        for _ in 0..<min(last.count, 2000) { TextInserter.postKey(51, flags: []) }
                        lastTyped = nil
                        inserter.resetSpacing()
                        RecordingOverlay.shared.show(.message("Scratched that"), hideAfter: 1.4)
                    } else {
                        NSSound.beep()
                    }
                }
            }
            if typedCount > 0 { lastTyped = (typedCount, target.pid, Date()) }
        }
        if !typedText.isEmpty {
            lastTranscript = typedText
            history.add(typedText, app: target.appName)
        }
    }

    // MARK: - Push to talk

    var listenMode: ListenMode { ListenMode(rawValue: Pref.defaults.string(forKey: Pref.listenMode) ?? "") ?? .auto }

    /// Called when the listening mode changes in Settings.
    func listenModeChanged() {
        if manualRecording { cancelManualRecording() }
        refresh()
    }

    private func pushToTalkPressed() {
        if listenMode == .toggle {
            manualRecording ? finishManualRecording() : startManualRecording()
        } else {
            startManualRecording()
        }
    }

    private func pushToTalkReleased() {
        if listenMode != .toggle { finishManualRecording() }
    }

    func startManualRecording() {
        guard !manualRecording else { return }
        // Pressed again before the last recording's tail was collected: send that one off first, so the
        // two recordings don't get mixed together.
        if let pending = manualFlush {
            pending.work.cancel()
            flushManualRecording(target: pending.target)
        }
        guard sttReady, micPermission, !isSpeaking, let target = forcedTarget() else {
            NSSound.beep()
            return
        }
        manualTarget = target
        manualRecording = true
        refresh()
        playSound("Tink")
        let label = ShortcutAction.pushToTalk.shortcut.label
        RecordingOverlay.shared.show(.recording(listenMode == .toggle ? "Listening… \(label) to stop" : "Listening… release to type"))
    }

    func finishManualRecording() {
        guard manualRecording else { return }
        manualRecording = false
        manualTail = true
        let target = manualTarget
        manualTarget = nil
        playSound("Pop")
        RecordingOverlay.shared.show(.working("Transcribing…"))
        // Keep the mic open a moment so the last syllable isn't clipped.
        let work = DispatchWorkItem { [weak self] in self?.flushManualRecording(target: target) }
        manualFlush = (work, target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func flushManualRecording(target: Target?) {
        manualFlush = nil
        let samples: [Float] = vadQueue.sync {
            let s = capture.buffer
            capture.buffer = []
            return s
        }
        manualTail = false
        refresh()
        // Under a third of a second is a key bump, not speech.
        if samples.count < 5_000 {
            RecordingOverlay.shared.hide()
        } else {
            utterances?.yield(Utterance(samples: samples, target: target))
        }
    }

    private func cancelManualRecording() {
        manualFlush?.work.cancel()
        manualFlush = nil
        manualRecording = false
        manualTail = false
        manualTarget = nil
        vadQueue.async { [capture] in capture.buffer = [] }
        RecordingOverlay.shared.hide()
    }

    func toggleManualRecording() {
        manualRecording ? finishManualRecording() : startManualRecording()
    }

    /// Chooses where microphone samples go: voice detection, the push-to-talk buffer, or nowhere.
    private func syncRoute() {
        let route: Route
        if manualRecording || manualTail { route = .manual }
        else if teachHandler != nil || listenMode == .auto { route = .vad }
        else { route = .drop }
        vadQueue.async { [capture, vad] in
            if capture.route != route {
                if route == .manual { capture.buffer = [] }
                vad.reset()
                capture.route = route
            }
        }
    }

    private func playSound(_ name: String) {
        guard Pref.defaults.bool(forKey: Pref.soundFeedback) else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: - Shortcuts

    func registerHotKeys() {
        hotKeys.unregisterAll()
        var conflicts: [ShortcutAction] = []
        var used: [Shortcut] = []
        func bind(_ action: ShortcutAction, press: @escaping () -> Void, release: (() -> Void)? = nil) {
            // The same keys on two SayType actions: only the first would ever fire, so flag the second.
            if used.contains(action.shortcut) { conflicts.append(action); return }
            used.append(action.shortcut)
            if !hotKeys.register(action.shortcut, onPress: press, onRelease: release) { conflicts.append(action) }
        }
        bind(.toggleDictation) { [weak self] in self?.enabled.toggle() }
        bind(.pushToTalk, press: { [weak self] in self?.pushToTalkPressed() },
             release: { [weak self] in self?.pushToTalkReleased() })
        bind(.speakSelection) { [weak self] in self?.speakSelection() }
        bind(.editSelection) { [weak self] in self?.editSelectionByVoice() }
        shortcutConflicts = conflicts
    }

    // MARK: - Voice edit

    /// Select text, press the shortcut, say what to change; the selection is replaced.
    func editSelectionByVoice() {
        guard !editing else { return }
        let ai = AIService.current
        if let reason = ai.unavailableReason {
            NSSound.beep()
            RecordingOverlay.shared.show(.message(reason), hideAfter: 4)
            return
        }
        guard sttReady, micPermission else { NSSound.beep(); return }
        editing = true
        Task {
            defer { editing = false }
            guard let selected = await TextInserter.selectedText() else {
                NSSound.beep()
                RecordingOverlay.shared.show(.message("Select some text first"), hideAfter: 2.5)
                return
            }
            let target = forcedTarget()
            playSound("Tink")
            RecordingOverlay.shared.show(.recording("Say how to change it…"))
            let instruction = await captureOnce(timeout: 12)
            playSound("Pop")
            guard let instruction, let target else {
                RecordingOverlay.shared.show(.message("Didn't catch that"), hideAfter: 2.5)
                return
            }
            RecordingOverlay.shared.show(.working("Editing…"))
            do {
                let result = try await TextCleaner(service: ai).edit(selected, instruction: instruction)
                guard isStillThere(target) else {
                    RecordingOverlay.shared.show(.message("You switched away, nothing changed"), hideAfter: 3)
                    return
                }
                inserter.insert(result, into: target.element, appName: target.appName,
                                method: InsertionMethod(rawValue: Pref.defaults.string(forKey: Pref.insertionMethod) ?? "") ?? .auto,
                                replacingSelection: true)
                history.add(result, app: target.appName)
                lastTranscript = result
                RecordingOverlay.shared.show(.message("Done. ⌘Z undoes it"), hideAfter: 2.5)
            } catch {
                RecordingOverlay.shared.show(.message(error.localizedDescription), hideAfter: 4)
            }
        }
    }

    // MARK: - Automation

    func run(_ command: AutomationCommand) {
        log.notice("automation: \(String(describing: command).prefix(40), privacy: .public)")
        switch command {
        case .dictation(let mode):
            switch mode {
            case .on: enabled = true
            case .off: enabled = false
            case .toggle: enabled.toggle()
            }
        case .record(let mode):
            switch mode {
            case .start: startManualRecording()
            case .stop: finishManualRecording()
            case .toggle: toggleManualRecording()
            }
        case .speak(let text):
            if let text { Task { await speak(text) } } else { speakSelection() }
        case .editSelection:
            editSelectionByVoice()
        case .transcribe(let url):
            TranscribeWindow.shared.show(file: url)
        case .meeting(let mode):
            let recording = TranscribeWindow.shared.isRecordingMeeting
            switch mode {
            case .start: if !recording { TranscribeWindow.shared.toggleMeeting() }
            case .stop: if recording { TranscribeWindow.shared.toggleMeeting() }
            case .toggle: TranscribeWindow.shared.toggleMeeting()
            }
        case .copyLast:
            copyLastTranscript()
        case .settings:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func copyLastTranscript() {
        guard let text = history.last?.text ?? (lastTranscript.isEmpty ? nil : lastTranscript) else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Switches back to the app you were using and types `text` there again.
    func typeAgain(_ text: String) {
        guard let app = lastExternalApp, !app.isTerminated else { NSSound.beep(); return }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.inserter.insert(text, into: nil, appName: app.localizedName ?? "", method: .paste, replacingSelection: true)
        }
    }

    private func trackFrontmostApp() {
        let mine = Bundle.main.bundleIdentifier
        if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != mine { lastExternalApp = app }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != mine else { return }
            MainActor.assumeIsolated { self?.lastExternalApp = app }
        }
    }

    /// One word the `saytype status` command prints.
    private func writeStatus() {
        let word: String
        if manualRecording { word = "recording" } else {
            switch status {
            case .loading: word = "loading"
            case .idle, .needsMicPermission, .needsAccessibility, .error: word = "idle"
            case .listening, .hearing: word = "listening"
            case .transcribing: word = "transcribing"
            case .speaking: word = "speaking"
            case .disabled: word = "off"
            }
        }
        try? word.write(to: AppPaths.statusFile, atomically: true, encoding: .utf8)
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
        case .parakeet:
            engine = ParakeetEngine()
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

    /// Forces a state for `--check-menu`, which checks the menu's height never changes. Nothing else calls it.
    func applyMenuCheckState(status: Status, lastTranscript: String, ttsStatus: String) {
        guard UISnapshot.checkingMenu else { return }
        sttName = "Whisper · Large v3 Turbo"
        self.status = status
        self.lastTranscript = lastTranscript
        self.ttsStatus = ttsStatus
    }

    /// Puts the controller in a "ready and listening" look for screenshots. Only used by `--snapshot`.
    func prepareForSnapshot() {
        guard UISnapshot.active else { return }
        focus.prepareForSnapshot(appName: "Slack")
        sttName = "Whisper · Large v3 Turbo"
        sttReady = true
        status = .listening
    }

    // MARK: - Shared services (used by the file/meeting transcriber)

    /// Transcribes long audio with timestamps using the loaded speech engine.
    func transcribeSegments(_ samples: [Float]) async throws -> [TimedSegment] {
        guard let stt, sttReady else {
            throw NSError(domain: "SayType", code: 10, userInfo: [NSLocalizedDescriptionKey: "The speech model isn't ready yet."])
        }
        stt.translate = Pref.defaults.bool(forKey: Pref.translateToEnglish)
        return try await stt.transcribeSegments(samples, language: language)
    }

    /// True when an AI text backend (Apple on-device or a local server) is configured and usable.
    var aiAvailable: Bool { AIService.current.isAvailable }

    /// Runs `instruction` over `input` with the configured AI backend. Throws when none is available.
    func runAI(instruction: String, input: String) async throws -> String {
        try await AIService.current.complete(system: instruction, user: CleanupPrompts.wrap(input), timeout: 120)
    }

    // MARK: - Text to speech

    func speakSelection() {
        if isSpeaking || speakBusy {
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
        // One at a time: a second request while the first is loading or talking used to turn the mic back on
        // while the voice was still speaking, and SayType then typed its own voice.
        guard !speakBusy else { return }
        speakBusy = true
        defer { speakBusy = false }
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
