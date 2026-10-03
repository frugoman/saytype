import AVFoundation
import ServiceManagement
import SwiftUI

// MARK: - Shared pieces

/// A label on the left and a control on the right.
private struct PlayRow<Control: View>: View {
    @ObservedObject private var theme = Theme.shared
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(theme.inkSoft) }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

/// A slider with a title and a live value chip.
private struct PlaySliderRow: View {
    @ObservedObject private var theme = Theme.shared
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let chip: String
    var tint: PlayTint = .blue
    var low: String?
    var high: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Spacer()
                PlayChip(text: chip, tint: tint).contentTransition(.numericText()).animation(theme.spring, value: chip)
            }
            if let step { Slider(value: $value, in: range, step: step) } else { Slider(value: $value, in: range) }
            if low != nil || high != nil {
                HStack {
                    Text(low ?? ""); Spacer(); Text(high ?? "")
                }
                .font(.system(size: 11.5)).foregroundStyle(theme.inkSoft)
            }
        }
    }
}

/// Briefly lights up a row when `trigger` changes.
private struct PlayFlash<T: Equatable>: ViewModifier {
    @ObservedObject private var theme = Theme.shared
    let trigger: T
    var tint: PlayTint = .butter
    @State private var lit = false

    func body(content: Content) -> some View {
        content
            .padding(8)
            .background(RoundedRectangle(cornerRadius: theme.radius(14), style: .continuous)
                .fill(lit ? theme.soft(tint) : .clear))
            .padding(-8)
            .animation(theme.spring, value: lit)
            .onChange(of: trigger) {
                lit = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { lit = false }
            }
    }
}

private extension View {
    func playFlash<T: Equatable>(_ trigger: T, tint: PlayTint = .butter) -> some View { modifier(PlayFlash(trigger: trigger, tint: tint)) }
}

// MARK: - General

struct GeneralSettings: View {
    @EnvironmentObject var controller: AppController
    @ObservedObject private var theme = Theme.shared
    @AppStorage(Pref.sensitivity) private var sensitivity = 0.5
    @AppStorage(Pref.pauseToCommit) private var pause = 0.8
    @AppStorage(Pref.insertionMethod) private var insertion = InsertionMethod.auto.rawValue
    @AppStorage(Pref.pauseWhileMediaPlays) private var pauseForMedia = false
    @AppStorage(Pref.listenMode) private var listenMode = ListenMode.auto.rawValue
    @AppStorage(Pref.soundFeedback) private var sounds = false
    @AppStorage(Pref.showOverlay) private var overlay = true
    @AppStorage(Pref.showCaretIndicator) private var caretIndicator = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var alwaysListen: [String] = Pref.defaults.stringArray(forKey: Pref.alwaysListenApps) ?? []

    var body: some View {
        PlayPage {
            PlaySection(tint: .mint) {
                Toggle("Dictation on", isOn: $controller.enabled)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch { launchAtLogin = !on }
                    }
            }

            PlaySection(tint: .pink) {
                PlayChoiceGroup(selection: $listenMode, options: [
                    (value: ListenMode.auto.rawValue, title: "Hands-free", subtitle: "Listen whenever a text field has focus", icon: "sparkles", tint: PlayTint.butter),
                    (value: ListenMode.pushToTalk.rawValue, title: "Push to talk", subtitle: "Hold the shortcut while you speak", icon: "hand.tap.fill", tint: PlayTint.pink),
                    (value: ListenMode.toggle.rawValue, title: "Toggle", subtitle: "Press the shortcut to start and again to stop", icon: "switch.2", tint: PlayTint.blue),
                ])
                Toggle("Show a mic badge next to the text cursor", isOn: $caretIndicator)
                Toggle("Show a recording pill on screen", isOn: $overlay)
                Toggle("Play a sound when recording starts and stops", isOn: $sounds)
            } header: {
                Text("Mode")
            } footer: {
                Text("The push-to-talk shortcut also works in hands-free mode, for apps that don't report their text fields.")
            }
            .onChange(of: listenMode) { controller.listenModeChanged() }

            PlaySection("Shortcuts", tint: .lavender) {
                ForEach(ShortcutAction.allCases) { ShortcutRow(action: $0) }
            }

            PlaySection("Listening", tint: .blue) {
                PlaySliderRow(title: "Sensitivity", value: $sensitivity, range: 0...1,
                              chip: "\(Int(sensitivity * 100))%", tint: .blue, low: "Loud only", high: "Whispers")
                PlaySliderRow(title: "Type after a pause of", value: $pause, range: 0.4...2.0, step: 0.1,
                              chip: String(format: "%.1fs", pause), tint: .butter)
                Toggle("Pause while other audio is playing (videos, calls)", isOn: $pauseForMedia)
            }
            .onChange(of: sensitivity) { controller.applyVADSettings() }
            .onChange(of: pause) { controller.applyVADSettings() }

            PlaySection("Typing", tint: .peach) {
                PlayRow(title: "Insert text using") {
                    Picker("Insert text using", selection: $insertion) {
                        ForEach(InsertionMethod.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .labelsHidden().fixedSize()
                }
            }

            PlaySection(tint: .mint) {
                if alwaysListen.isEmpty {
                    Text("No apps yet.").font(.system(size: 13)).foregroundStyle(theme.inkSoft)
                }
                ForEach(alwaysListen, id: \.self) { id in
                    HStack(spacing: 10) {
                        Image(systemName: "app.dashed").foregroundStyle(theme.bold(.mint))
                        Text(appName(for: id)).font(.system(size: 13.5, weight: .semibold))
                        Spacer()
                        Button(role: .destructive) {
                            withAnimation(theme.spring) { alwaysListen.removeAll { $0 == id } }
                        } label: { Image(systemName: "minus") }
                            .accessibilityLabel("Remove \(appName(for: id))")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: theme.radius(14), style: .continuous).fill(theme.soft(.mint)))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                Menu {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                            if let id = app.bundleIdentifier, !alwaysListen.contains(id) {
                                withAnimation(theme.spring) { alwaysListen.append(id) }
                            }
                        }
                    }
                } label: {
                    Label("Add running app", systemImage: "plus")
                }
                .menuStyle(.button).buttonStyle(PlayButtonStyle()).fixedSize()
            } header: {
                Text("Always listen in these apps")
            } footer: {
                Text("For apps that don't report their text fields to macOS (some games, terminals, Electron apps).")
            }
            .onChange(of: alwaysListen) { _, list in Pref.defaults.set(list, forKey: Pref.alwaysListenApps) }
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func appName(for bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName ?? bundleID
    }
}

// MARK: - Speech to text

struct SpeechToTextSettings: View {
    @EnvironmentObject var controller: AppController
    @ObservedObject private var theme = Theme.shared
    @AppStorage(Pref.sttEngine) private var engine = STTEngineKind.whisperKit.rawValue
    @AppStorage(Pref.whisperModel) private var model = WhisperModelOption.defaultID
    @AppStorage(Pref.whisperRepo) private var repo = "argmaxinc/whisperkit-coreml"
    @AppStorage(Pref.language) private var language = "en"
    @AppStorage(Pref.codeContextPrompt) private var codeContext = true
    @AppStorage(Pref.translateToEnglish) private var translate = false
    @AppStorage(Pref.sttServerURL) private var serverURL = "http://127.0.0.1:8080"
    @AppStorage(Pref.sttServerModel) private var serverModel = "whisper-1"

    var body: some View {
        PlayPage {
            PlaySection(tint: .blue) {
                PlayRow(title: "Engine") {
                    Picker("Engine", selection: $engine) {
                        ForEach(STTEngineKind.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .labelsHidden().fixedSize()
                }
                .playFlash(engine, tint: .blue)
                PlayRow(title: "Language") {
                    Picker("Language", selection: $language) {
                        ForEach(speechLanguages(for: STTEngineKind(rawValue: engine) ?? .whisperKit), id: \.code) { Text($0.name).tag($0.code) }
                    }
                    .labelsHidden().fixedSize()
                }
                .playFlash(language, tint: .butter)
                Toggle("Tuned for developers (knows common code terms)", isOn: $codeContext)
                if engine != STTEngineKind.parakeet.rawValue {
                    Toggle("Translate everything to English", isOn: $translate)
                        .transition(.opacity)
                }
            } footer: {
                Text(engine == STTEngineKind.parakeet.rawValue
                     ? "Parakeet covers these 25 European languages and detects which one you speak. For Japanese, Chinese, Korean, Arabic, Hindi and others, switch the engine to Whisper."
                     : "Translation needs a multilingual Whisper model (not the English-only ones).")
            }
            .onChange(of: engine) { fixLanguageForEngine() }
            .onAppear(perform: fixLanguageForEngine)
            .playAnimation(value: engine)

            VStack(alignment: .leading, spacing: theme.space(18)) {
                if engine == STTEngineKind.parakeet.rawValue {
                    PlaySection(tint: .mint) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "bolt.fill").foregroundStyle(theme.bold(.mint))
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: theme.radius(11), style: .continuous).fill(theme.soft(.mint)))
                            Text("Parakeet v3 downloads once (about 470 MB) and runs on the Neural Engine. It's several times faster than Whisper for European languages.")
                                .font(.system(size: 13)).foregroundStyle(theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else if engine == STTEngineKind.whisperKit.rawValue {
                    PlaySection(tint: .lavender) {
                        PlayRow(title: "Model") {
                            Picker("Model", selection: $model) {
                                ForEach(WhisperModelOption.recommended) { Text($0.label).tag($0.id) }
                                if !WhisperModelOption.recommended.contains(where: { $0.id == model }) {
                                    Text("Custom: \(model)").tag(model)
                                }
                            }
                            .labelsHidden().fixedSize()
                        }
                        TextField("Model name", text: $model)
                            .font(.system(.body, design: .monospaced))
                        TextField("Hugging Face repo", text: $repo)
                            .font(.system(.body, design: .monospaced))
                    } header: {
                        Text("Whisper model")
                    } footer: {
                        Text("Any Whisper model converted to WhisperKit's Core ML format works — pick one above, or paste a model name and repo you found on Hugging Face. Models are downloaded once and run fully offline.")
                    }
                } else {
                    PlaySection(tint: .peach) {
                        TextField("Server URL", text: $serverURL)
                        TextField("Model", text: $serverModel)
                    } header: {
                        Text("Local server")
                    } footer: {
                        Text("Use any model you like by running it as a local server that speaks the OpenAI transcription API (POST /v1/audio/transcriptions) — e.g. whisper.cpp server, speaches, LocalAI, or a Parakeet/MLX server.")
                    }
                }
            }
            .playAnimation(value: engine)

            PlaySection(tint: .mint) {
                HStack(spacing: 12) {
                    Button("Load model") { Task { await controller.reloadSpeechToText() } }
                        .buttonStyle(.playPrimary)
                    loadStatus
                    Spacer(minLength: 0)
                }
                if case .loading(let fraction, _) = controller.status {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(theme.bold(.mint))
                        .transition(.opacity)
                }
            }
            .playAnimation(value: controller.status)
        }
    }

    /// Parakeet can't do every language; if the saved one isn't offered any more, fall back to English.
    private func fixLanguageForEngine() {
        let allowed = speechLanguages(for: STTEngineKind(rawValue: engine) ?? .whisperKit)
        if !allowed.contains(where: { $0.code == language }) { language = "en" }
        if engine == STTEngineKind.parakeet.rawValue { translate = false }
    }

    @ViewBuilder private var loadStatus: some View {
        switch controller.status {
        case .loading(let fraction, let message):
            HStack(spacing: 8) {
                PlayChip(text: "\(Int(fraction * 100))%", tint: .butter, icon: "arrow.down.circle.fill")
                Text(message).font(.system(size: 12)).foregroundStyle(theme.inkSoft).lineLimit(1)
            }
        case .error(let message):
            HStack(spacing: 8) {
                PlayChip(text: "Error", tint: .pink, icon: "exclamationmark.triangle.fill")
                Text(message).font(.system(size: 12)).foregroundStyle(theme.bold(.pink)).lineLimit(2)
            }
        default:
            PlayChip(text: "Using \(controller.sttName)", tint: .mint, icon: "checkmark.circle.fill")
        }
    }
}

// MARK: - Vocabulary

/// "Teach" button that pulses while it is listening.
private struct TeachButton: View {
    @ObservedObject private var theme = Theme.shared
    let listening: Bool
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: listening ? "waveform" : "mic.fill")
                    .symbolEffect(.variableColor.iterative, isActive: listening)
                Text(listening ? "Listening…" : "Teach")
            }
        }
        .buttonStyle(.playPrimary)
        .scaleEffect(listening && pulse ? 1.06 : 1)
        .shadow(color: theme.accent.opacity(listening ? (pulse ? 0.5 : 0.1) : 0), radius: 10)
        .onChange(of: listening) { _, on in
            if on {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { pulse = false }
            }
        }
    }
}

struct VocabularySettings: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var vocabulary: VocabularyStore
    @ObservedObject private var theme = Theme.shared
    @State private var newTerm = ""
    @State private var teaching: VocabularyEntry.ID?
    @State private var teachMessage = ""
    @State private var testInput = ""

    var body: some View {
        PlayPage {
            PlaySection(tint: .butter) {
                HStack(spacing: 10) {
                    TextField("Add a word, name or term (e.g. gira-planner, kubectl, Supabase)", text: $newTerm)
                        .onSubmit(add)
                    Button("Add", action: add).buttonStyle(.playPrimary)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Words here are hinted to the model and auto-corrected after transcription. Use “Teach” and say the word a few times: SayType learns how the model mishears it and fixes it from then on.")
            }

            PlaySection("Your words", tint: .pink) {
                if vocabulary.entries.isEmpty {
                    Text("No words yet.").font(.system(size: 13)).foregroundStyle(theme.inkSoft)
                }
                ForEach($vocabulary.entries) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            TextField("Term", text: $entry.term).font(.body.weight(.semibold))
                            TeachButton(listening: teaching == entry.id) { teach(entry) }
                                .disabled(teaching != nil)
                            Button(role: .destructive) {
                                withAnimation(theme.spring) { vocabulary.entries.removeAll { $0.id == entry.id } }
                            } label: { Image(systemName: "trash") }
                                .accessibilityLabel("Delete \(entry.term)")
                        }
                        if !entry.soundsLike.isEmpty {
                            HStack(spacing: 6) {
                                Text("Heard as").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(theme.inkSoft)
                                ForEach(entry.soundsLike, id: \.self) { PlayChip(text: $0, tint: .lavender) }
                            }
                            .transition(.opacity)
                        }
                        TextField("Also heard as (comma separated)", text: Binding(
                            get: { entry.soundsLike.joined(separator: ", ") },
                            set: { entry.soundsLike = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                        ))
                        .font(.caption)
                        if teaching == entry.id || (!teachMessage.isEmpty && lastTaught == entry.id) {
                            Text(teachMessage).font(.system(size: 12)).foregroundStyle(theme.inkSoft)
                                .transition(.opacity)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous).fill(theme.ink.opacity(0.045)))
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
            .playAnimation(value: vocabulary.entries.count)

            PlaySection("Try corrections", tint: .mint) {
                TextField("Type a sentence as the model might hear it", text: $testInput)
                if !testInput.isEmpty {
                    Text(vocabulary.apply(to: testInput))
                        .font(.system(size: 14)).textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: theme.radius(14), style: .continuous).fill(theme.soft(.mint)))
                        .transition(.opacity)
                }
            }
            .playAnimation(value: testInput.isEmpty)
        }
    }

    @State private var lastTaught: VocabularyEntry.ID?

    private func add() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        vocabulary.entries.insert(VocabularyEntry(term: term), at: 0)
        newTerm = ""
    }

    private func teach(_ entry: VocabularyEntry) {
        teaching = entry.id
        lastTaught = entry.id
        Task {
            var heard: [String] = []
            for i in 1...3 {
                teachMessage = "Say “\(entry.term)” (\(i) of 3)…"
                guard let text = await controller.captureOnce() else {
                    teachMessage = "Didn't hear anything. Is the microphone working?"
                    break
                }
                let cleaned = text.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                heard.append(cleaned)
            }
            let newAliases = heard.filter {
                !$0.isEmpty && $0.caseInsensitiveCompare(entry.term) != .orderedSame
            }
            if let idx = vocabulary.entries.firstIndex(where: { $0.id == entry.id }) {
                var set = vocabulary.entries[idx].soundsLike
                for a in newAliases where !set.contains(where: { $0.caseInsensitiveCompare(a) == .orderedSame }) { set.append(a) }
                vocabulary.entries[idx].soundsLike = set
            }
            if !heard.isEmpty {
                teachMessage = newAliases.isEmpty
                    ? "The model already hears it right."
                    : "Learned: \(Set(newAliases).joined(separator: ", ")) → \(entry.term)"
            }
            teaching = nil
        }
    }
}

// MARK: - Text to speech

struct TextToSpeechSettings: View {
    @EnvironmentObject var controller: AppController
    @ObservedObject private var theme = Theme.shared
    @AppStorage(Pref.ttsEngine) private var engine = TTSEngineKind.system.rawValue
    @AppStorage(Pref.systemVoice) private var systemVoice = ""
    @AppStorage(Pref.qwenModel) private var qwenModel = "0.6b"
    @AppStorage(Pref.qwenSpeaker) private var qwenSpeaker = "ryan"
    @AppStorage(Pref.ttsServerURL) private var serverURL = "http://127.0.0.1:8880"
    @AppStorage(Pref.ttsServerModel) private var serverModel = "kokoro"
    @AppStorage(Pref.ttsServerVoice) private var serverVoice = "af_heart"
    @AppStorage(Pref.speechRate) private var rate = 1.0
    @State private var sample = "Hi! This is how I sound. Select any text and press Control Option S to hear it."
    @State private var spoke = 0

    var body: some View {
        PlayPage {
            PlaySection(tint: .lavender) {
                PlayRow(title: "Engine") {
                    Picker("Engine", selection: $engine) {
                        ForEach(TTSEngineKind.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .labelsHidden().fixedSize()
                }
                .playFlash(engine, tint: .lavender)
                PlaySliderRow(title: "Speed", value: $rate, range: 0.5...2.0, step: 0.1,
                              chip: String(format: "%.1f×", rate), tint: .peach, low: "Slower", high: "Faster")
            } footer: {
                Text("Select text anywhere and press \(ShortcutAction.speakSelection.shortcut.label) to hear it. Press again to stop.")
            }

            VStack(alignment: .leading, spacing: theme.space(18)) {
                switch TTSEngineKind(rawValue: engine) ?? .system {
                case .system:
                    PlaySection(tint: .blue) {
                        PlayRow(title: "Voice") {
                            Picker("Voice", selection: $systemVoice) {
                                Text("Default for language").tag("")
                                ForEach(SystemTTSEngine.availableVoices, id: \.identifier) { voice in
                                    Text("\(voice.name) (\(voice.language))\(voice.quality == .premium ? " · Premium" : voice.quality == .enhanced ? " · Enhanced" : "")")
                                        .tag(voice.identifier)
                                }
                            }
                            .labelsHidden().fixedSize()
                        }
                    } footer: {
                        Text("Get nicer free voices in System Settings → Accessibility → Spoken Content → System Voice → Manage Voices.")
                    }
                case .qwen:
                    PlaySection(tint: .pink) {
                        PlayRow(title: "Model") {
                            Picker("Model", selection: $qwenModel) {
                                Text("0.6B (faster, ~1 GB)").tag("0.6b")
                                Text("1.7B (better, ~3 GB)").tag("1.7b")
                            }
                            .labelsHidden().fixedSize()
                        }
                        PlayRow(title: "Voice") {
                            Picker("Voice", selection: $qwenSpeaker) {
                                ForEach(["ryan", "aiden", "eric", "dylan", "serena", "vivian", "ono-anna", "sohee", "uncle-fu"], id: \.self) {
                                    Text($0.capitalized).tag($0)
                                }
                            }
                            .labelsHidden().fixedSize()
                        }
                    } footer: {
                        Text("Natural neural voice that runs on your Mac. Downloads once on first use.")
                    }
                case .localServer:
                    PlaySection(tint: .peach) {
                        TextField("Server URL", text: $serverURL)
                        TextField("Model", text: $serverModel)
                        TextField("Voice", text: $serverVoice)
                    } footer: {
                        Text("Any local server that speaks the OpenAI speech API (POST /v1/audio/speech), e.g. Kokoro-FastAPI, speaches, LocalAI.")
                    }
                }
            }
            .playAnimation(value: engine)

            PlaySection("Try it", tint: .mint) {
                TextField("Text", text: $sample, axis: .vertical).lineLimit(2...4)
                HStack(spacing: 12) {
                    Button {
                        spoke += 1
                        Task { await controller.speak(sample) }
                    } label: {
                        Label("Speak", systemImage: "speaker.wave.3.fill")
                            .symbolEffect(.bounce, value: spoke)
                    }
                    .buttonStyle(.playPrimary)
                    if !controller.ttsStatus.isEmpty {
                        PlayChip(text: controller.ttsStatus, tint: .butter)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }
                .playAnimation(value: controller.ttsStatus)
            }
        }
        .onChange(of: engine) { controller.resetTextToSpeech() }
        .onChange(of: systemVoice) { controller.resetTextToSpeech() }
        .onChange(of: qwenModel) { controller.resetTextToSpeech() }
        .onChange(of: qwenSpeaker) { controller.resetTextToSpeech() }
        .onChange(of: serverURL) { controller.resetTextToSpeech() }
        .onChange(of: serverModel) { controller.resetTextToSpeech() }
        .onChange(of: serverVoice) { controller.resetTextToSpeech() }
        .onChange(of: rate) { controller.resetTextToSpeech() }
    }
}

// MARK: - About

struct AboutSettings: View {
    @ObservedObject private var theme = Theme.shared
    @State private var copied = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        PlayPage {
            PlaySection(tint: .pink) {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(theme.accent)
                        .symbolEffect(.pulse)
                    Text("SayType").font(.system(size: 26, weight: .bold))
                    if !version.isEmpty { PlayChip(text: "Version \(version)", tint: .lavender) }
                    Text("SayType is free.").font(.system(size: 17, weight: .semibold)).padding(.top, 4)
                    Text("No trial, no account, no subscription. If it saves you some typing, you can buy me a coffee. It keeps the app going.")
                        .font(.system(size: 13.5)).foregroundStyle(theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380)
                    Button { NSWorkspace.shared.open(Links.coffee) } label: {
                        Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
                    }
                    .buttonStyle(.playPrimary).padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            PlaySection("Updates", tint: .mint) {
                Text("Update with Homebrew").font(.system(size: 13.5, weight: .semibold))
                HStack(spacing: 10) {
                    Text(Links.upgradeCommand)
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: theme.radius(12), style: .continuous).fill(theme.ink.opacity(0.06)))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Links.upgradeCommand, forType: .string)
                        withAnimation(theme.spring) { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation(theme.spring) { copied = false } }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(copied ? theme.bold(.mint) : theme.ink)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 18)
                    }
                    .accessibilityLabel("Copy update command")
                }
            }

            PlaySection(tint: .blue) {
                PlayRow(title: "Website", subtitle: Links.website.host) {
                    Button { NSWorkspace.shared.open(Links.website) } label: {
                        Label("Open", systemImage: "arrow.up.right")
                    }
                }
            }
        }
    }
}
