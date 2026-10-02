import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            SpeechToTextSettings().tabItem { Label("Voice → Text", systemImage: "waveform") }
            VocabularySettings().tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
            TextToSpeechSettings().tabItem { Label("Text → Voice", systemImage: "speaker.wave.2") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @EnvironmentObject var controller: AppController
    @AppStorage(Pref.sensitivity) private var sensitivity = 0.5
    @AppStorage(Pref.pauseToCommit) private var pause = 0.8
    @AppStorage(Pref.insertionMethod) private var insertion = InsertionMethod.auto.rawValue
    @AppStorage(Pref.pauseWhileMediaPlays) private var pauseForMedia = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var alwaysListen: [String] = Pref.defaults.stringArray(forKey: Pref.alwaysListenApps) ?? []

    var body: some View {
        Form {
            Section {
                Toggle("Dictation on", isOn: $controller.enabled)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch { launchAtLogin = !on }
                    }
            }
            Section("Listening") {
                LabeledContent("Sensitivity") {
                    Slider(value: $sensitivity, in: 0...1) {
                        EmptyView()
                    } minimumValueLabel: { Text("Loud only").font(.caption) } maximumValueLabel: { Text("Whispers").font(.caption) }
                }
                LabeledContent("Type after a pause of") {
                    HStack {
                        Slider(value: $pause, in: 0.4...2.0, step: 0.1)
                        Text(String(format: "%.1fs", pause)).monospacedDigit().frame(width: 36)
                    }
                }
                Toggle("Pause while other audio is playing (videos, calls)", isOn: $pauseForMedia)
            }
            .onChange(of: sensitivity) { controller.applyVADSettings() }
            .onChange(of: pause) { controller.applyVADSettings() }

            Section("Typing") {
                Picker("Insert text using", selection: $insertion) {
                    ForEach(InsertionMethod.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section {
                ForEach(alwaysListen, id: \.self) { id in
                    HStack {
                        Text(appName(for: id))
                        Spacer()
                        Button(role: .destructive) { alwaysListen.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Menu("Add running app…") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                            if let id = app.bundleIdentifier, !alwaysListen.contains(id) { alwaysListen.append(id) }
                        }
                    }
                }
            } header: {
                Text("Always listen in these apps")
            } footer: {
                Text("For apps that don't report their text fields to macOS (some games, terminals, Electron apps).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: alwaysListen) { _, list in Pref.defaults.set(list, forKey: Pref.alwaysListenApps) }
        }
        .formStyle(.grouped)
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
    @AppStorage(Pref.sttEngine) private var engine = STTEngineKind.whisperKit.rawValue
    @AppStorage(Pref.whisperModel) private var model = WhisperModelOption.defaultID
    @AppStorage(Pref.whisperRepo) private var repo = "argmaxinc/whisperkit-coreml"
    @AppStorage(Pref.language) private var language = "en"
    @AppStorage(Pref.codeContextPrompt) private var codeContext = true
    @AppStorage(Pref.sttServerURL) private var serverURL = "http://127.0.0.1:8080"
    @AppStorage(Pref.sttServerModel) private var serverModel = "whisper-1"

    var body: some View {
        Form {
            Section {
                Picker("Engine", selection: $engine) {
                    ForEach(STTEngineKind.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Language", selection: $language) {
                    ForEach(supportedLanguages, id: \.code) { Text($0.name).tag($0.code) }
                }
                Toggle("Tuned for developers (knows common code terms)", isOn: $codeContext)
            }

            if engine == STTEngineKind.whisperKit.rawValue {
                Section {
                    Picker("Model", selection: $model) {
                        ForEach(WhisperModelOption.recommended) { Text($0.label).tag($0.id) }
                        if !WhisperModelOption.recommended.contains(where: { $0.id == model }) {
                            Text("Custom: \(model)").tag(model)
                        }
                    }
                    TextField("Model name", text: $model)
                        .font(.system(.body, design: .monospaced))
                    TextField("Hugging Face repo", text: $repo)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Whisper model")
                } footer: {
                    Text("Any Whisper model converted to WhisperKit's Core ML format works — pick one above, or paste a model name and repo you found on Hugging Face. Models are downloaded once and run fully offline.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    TextField("Server URL", text: $serverURL)
                    TextField("Model", text: $serverModel)
                } header: {
                    Text("Local server")
                } footer: {
                    Text("Use any model you like by running it as a local server that speaks the OpenAI transcription API (POST /v1/audio/transcriptions) — e.g. whisper.cpp server, speaches, LocalAI, or a Parakeet/MLX server.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Button("Load model") { Task { await controller.reloadSpeechToText() } }
                    Spacer()
                    loadStatus
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var loadStatus: some View {
        switch controller.status {
        case .loading(let fraction, let message):
            HStack { ProgressView(value: fraction).frame(width: 120); Text(message).font(.caption).lineLimit(1) }
        case .error(let message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
        default:
            Label("Using \(controller.sttName)", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Vocabulary

struct VocabularySettings: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var vocabulary: VocabularyStore
    @State private var newTerm = ""
    @State private var teaching: VocabularyEntry.ID?
    @State private var teachMessage = ""
    @State private var testInput = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Add a word, name or term (e.g. gira-planner, kubectl, Supabase)", text: $newTerm)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Words here are hinted to the model and auto-corrected after transcription. Use “Teach” and say the word a few times: SayType learns how the model mishears it and fixes it from then on.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Your words") {
                if vocabulary.entries.isEmpty {
                    Text("No words yet.").foregroundStyle(.secondary)
                }
                ForEach($vocabulary.entries) { $entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Term", text: $entry.term).font(.body.weight(.medium))
                            Button(teaching == entry.id ? "Listening…" : "Teach") { teach(entry) }
                                .disabled(teaching != nil)
                            Button(role: .destructive) {
                                vocabulary.entries.removeAll { $0.id == entry.id }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                        TextField("Also heard as (comma separated)", text: Binding(
                            get: { entry.soundsLike.joined(separator: ", ") },
                            set: { entry.soundsLike = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                        ))
                        .font(.caption)
                        if teaching == entry.id || (!teachMessage.isEmpty && lastTaught == entry.id) {
                            Text(teachMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Try corrections") {
                TextField("Type a sentence as the model might hear it", text: $testInput)
                if !testInput.isEmpty {
                    Text(vocabulary.apply(to: testInput)).font(.callout).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
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
    @AppStorage(Pref.ttsEngine) private var engine = TTSEngineKind.system.rawValue
    @AppStorage(Pref.systemVoice) private var systemVoice = ""
    @AppStorage(Pref.qwenModel) private var qwenModel = "0.6b"
    @AppStorage(Pref.qwenSpeaker) private var qwenSpeaker = "ryan"
    @AppStorage(Pref.ttsServerURL) private var serverURL = "http://127.0.0.1:8880"
    @AppStorage(Pref.ttsServerModel) private var serverModel = "kokoro"
    @AppStorage(Pref.ttsServerVoice) private var serverVoice = "af_heart"
    @AppStorage(Pref.speechRate) private var rate = 1.0
    @State private var sample = "Hi! This is how I sound. Select any text and press Control Option S to hear it."

    var body: some View {
        Form {
            Section {
                Picker("Engine", selection: $engine) {
                    ForEach(TTSEngineKind.allCases) { Text($0.label).tag($0.rawValue) }
                }
                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $rate, in: 0.5...2.0, step: 0.1)
                        Text(String(format: "%.1f×", rate)).monospacedDigit().frame(width: 36)
                    }
                }
            } footer: {
                Text("Select text anywhere and press \(HotKeys.speakSelection.label) to hear it. Press again to stop.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            switch TTSEngineKind(rawValue: engine) ?? .system {
            case .system:
                Section {
                    Picker("Voice", selection: $systemVoice) {
                        Text("Default for language").tag("")
                        ForEach(SystemTTSEngine.availableVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))\(voice.quality == .premium ? " · Premium" : voice.quality == .enhanced ? " · Enhanced" : "")")
                                .tag(voice.identifier)
                        }
                    }
                } footer: {
                    Text("Get nicer free voices in System Settings → Accessibility → Spoken Content → System Voice → Manage Voices.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .qwen:
                Section {
                    Picker("Model", selection: $qwenModel) {
                        Text("0.6B (faster, ~1 GB)").tag("0.6b")
                        Text("1.7B (better, ~3 GB)").tag("1.7b")
                    }
                    Picker("Voice", selection: $qwenSpeaker) {
                        ForEach(["ryan", "aiden", "eric", "dylan", "serena", "vivian", "ono-anna", "sohee", "uncle-fu"], id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                } footer: {
                    Text("Natural neural voice that runs on your Mac. Downloads once on first use.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .localServer:
                Section {
                    TextField("Server URL", text: $serverURL)
                    TextField("Model", text: $serverModel)
                    TextField("Voice", text: $serverVoice)
                } footer: {
                    Text("Any local server that speaks the OpenAI speech API (POST /v1/audio/speech), e.g. Kokoro-FastAPI, speaches, LocalAI.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Try it") {
                TextField("Text", text: $sample, axis: .vertical).lineLimit(2...4)
                HStack {
                    Button("Speak") { Task { await controller.speak(sample) } }
                    if !controller.ttsStatus.isEmpty {
                        Text(controller.ttsStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SayType is free.").font(.headline)
                    Text("No trial, no account, no subscription. If it saves you some typing, you can buy me a coffee. It keeps the app going.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Buy Me a Coffee…") { NSWorkspace.shared.open(Links.coffee) }
            }
            Section("Updates") {
                LabeledContent("Version", value: version)
                LabeledContent("Update with Homebrew") {
                    Text(Links.upgradeCommand)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
                Button("Copy Update Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Links.upgradeCommand, forType: .string)
                }
            }
            Section {
                Button("Website") { NSWorkspace.shared.open(Links.website) }
            }
        }
        .formStyle(.grouped)
    }
}
