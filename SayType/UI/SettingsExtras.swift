import AppKit
import SwiftUI

// MARK: - Shortcuts

/// Click, then press the key combination you want.
struct ShortcutRow: View {
    let action: ShortcutAction
    @EnvironmentObject var controller: AppController
    @State private var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    init(action: ShortcutAction) {
        self.action = action
        _shortcut = State(initialValue: action.shortcut)
    }

    var body: some View {
        LabeledContent(action.title) {
            HStack {
                if controller.shortcutConflicts.contains(action) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help("Another app already uses this shortcut. Pick a different one.")
                }
                Button(recording ? "Press keys…" : shortcut.label) { recording ? stop() : start() }
                    .frame(minWidth: 96)
                Button("Reset") {
                    action.save(nil)
                    shortcut = action.defaultShortcut
                    controller.registerHotKeys()
                }
                .buttonStyle(.borderless)
                .disabled(shortcut == action.defaultShortcut)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Escape cancels
            if let new = Shortcut(event: event) {
                action.save(new)
                shortcut = new
                stop()
                controller.registerHotKeys()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - Commands and snippets

struct CommandsSettings: View {
    @EnvironmentObject var snippets: SnippetStore
    @AppStorage(Pref.voiceCommands) private var commands = true
    @AppStorage(Pref.spokenPunctuation) private var punctuation = false

    var body: some View {
        Form {
            Section {
                Toggle("Voice commands", isOn: $commands)
                Toggle("Spoken punctuation", isOn: $punctuation)
            } header: {
                Text("Commands")
            } footer: {
                Text("Say “new line”, “new paragraph” or “scratch that” (deletes what was just typed) anywhere in a sentence. On their own: “undo that”, “select all”, “press enter”. Spoken punctuation turns “comma”, “period”, “question mark”, “open paren”, “quote” and so on into symbols.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach($snippets.entries) { $snippet in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("When I say", text: $snippet.trigger).font(.body.weight(.medium))
                            Button(role: .destructive) {
                                snippets.entries.removeAll { $0.id == snippet.id }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                        TextField("Type this", text: $snippet.expansion, axis: .vertical)
                            .lineLimit(1...6)
                            .font(.callout)
                    }
                    .padding(.vertical, 2)
                }
                Button("Add snippet") {
                    snippets.entries.insert(Snippet(trigger: "", expansion: ""), at: 0)
                }
            } header: {
                Text("Snippets")
            } footer: {
                Text("Pick a phrase you wouldn't say by accident, like “sign off snippet”. Use {date}, {time} and {clipboard} inside the text.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Per-app profiles

struct ProfileSettings: View {
    @EnvironmentObject var profiles: ProfileStore
    @AppStorage(Pref.pauseToCommit) private var globalPause = 0.8

    var body: some View {
        Form {
            Section {
                ForEach($profiles.profiles) { $profile in
                    DisclosureGroup {
                        Picker("Tone", selection: $profile.tone) {
                            ForEach(ToneStyle.allCases) { Text($0.label).tag($0) }
                        }
                        Toggle("Custom pause", isOn: Binding(
                            get: { profile.pauseToCommit != nil },
                            set: { profile.pauseToCommit = $0 ? globalPause : nil }))
                        if let pause = profile.pauseToCommit {
                            HStack {
                                Slider(value: Binding(get: { pause }, set: { profile.pauseToCommit = $0 }), in: 0.4...2.0, step: 0.1)
                                Text(String(format: "%.1fs", pause)).monospacedDigit().frame(width: 36)
                            }
                        }
                        Picker("Language", selection: Binding(get: { profile.language ?? "" }, set: { profile.language = $0.isEmpty ? nil : $0 })) {
                            Text("Same as general").tag("")
                            ForEach(speechLanguages(for: STTEngineKind(rawValue: Pref.defaults.string(forKey: Pref.sttEngine) ?? "") ?? .whisperKit), id: \.code) { Text($0.name).tag($0.code) }
                        }
                        Toggle("Remove the final period", isOn: $profile.stripTrailingPeriod)
                        TextField("Extra words for this app", text: $profile.extraTerms)
                        Button("Remove profile", role: .destructive) {
                            profiles.profiles.removeAll { $0.bundleID == profile.bundleID }
                        }
                    } label: {
                        HStack {
                            Text(profile.name).font(.body.weight(.medium))
                            Spacer()
                            Text(profile.tone.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if profiles.profiles.isEmpty {
                    Text("No profiles yet.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Apps")
            } footer: {
                Text("A profile changes how SayType behaves while that app is in front: how long it waits after you pause, the language, the tone used by AI cleanup, and more. Tone needs AI cleanup turned on.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Menu("Add running app…") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                            guard let id = app.bundleIdentifier, profiles.profile(for: id) == nil else { return }
                            profiles.profiles.append(AppProfile(bundleID: id, name: app.localizedName ?? id))
                        }
                    }
                }
                Button("Add suggested profiles for my apps") {
                    for suggestion in ProfileStore.suggestions
                    where profiles.profile(for: suggestion.bundleID) == nil
                        && NSWorkspace.shared.urlForApplication(withBundleIdentifier: suggestion.bundleID) != nil {
                        profiles.profiles.append(suggestion)
                    }
                }
            } footer: {
                Text("Suggestions cover chat apps (casual, no final period), mail (professional) and terminals and editors (code).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

// MARK: - AI

struct AISettings: View {
    @AppStorage(Pref.cleanupLevel) private var cleanup = CleanupLevel.off.rawValue
    @AppStorage(Pref.aiBackend) private var backend = AIBackendKind.apple.rawValue
    @AppStorage(Pref.aiServerURL) private var serverURL = "http://127.0.0.1:11434"
    @AppStorage(Pref.aiServerModel) private var serverModel = "llama3.2"
    @AppStorage(Pref.outputLanguage) private var outputLanguage = ""
    @State private var testResult = ""
    @State private var testing = false

    /// Only languages the selected AI backend can really write in.
    private var writable: [(name: String, code: String)] { AIService.current.writableLanguages }

    var body: some View {
        Form {
            Section {
                Picker("Clean up what I say", selection: $cleanup) {
                    ForEach(CleanupLevel.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Write in", selection: $outputLanguage) {
                    Text("The language I speak").tag("")
                    ForEach(writable, id: \.name) { Text($0.name).tag($0.name) }
                }
            } header: {
                Text("Dictation")
            } footer: {
                Text("Cleanup removes “um”s, fixes punctuation and, with Polish, tidies wording. It adds a moment before text appears. Writing in another language translates what you say, and only lists languages the selected AI model supports.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("AI model", selection: $backend) {
                    ForEach(AIBackendKind.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if backend == AIBackendKind.server.rawValue {
                    TextField("Server URL", text: $serverURL)
                    TextField("Model", text: $serverModel)
                }
                HStack {
                    Button(testing ? "Testing…" : "Test") { test() }.disabled(testing)
                    Text(AIService.current.unavailableReason ?? (testResult.isEmpty ? "Ready" : testResult))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            } header: {
                Text("Where the AI runs")
            } footer: {
                Text("Always on your Mac. For a server, run Ollama (`ollama serve`, then `ollama pull llama3.2`) and keep the address above, or point it at LM Studio, llama.cpp or mlx_lm.server.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Text("Select text in any app, press \(ShortcutAction.editSelection.shortcut.label) and say what to change: “make this shorter”, “fix the grammar”, “translate to Spanish”. The selection is replaced.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Edit by voice")
            }
        }
        .formStyle(.grouped)
        .onChange(of: backend) { resetUnsupportedLanguage() }
        .onAppear(perform: resetUnsupportedLanguage)
    }

    private func resetUnsupportedLanguage() {
        if !outputLanguage.isEmpty, !writable.contains(where: { $0.name == outputLanguage }) { outputLanguage = "" }
    }

    private func test() {
        testing = true
        testResult = ""
        Task {
            let start = Date()
            do {
                let reply = try await AIService.current.complete(system: "Reply with the single word OK.", user: "Ping", timeout: 30)
                testResult = "Working (\(String(format: "%.1f", Date().timeIntervalSince(start)))s): \(reply.prefix(40))"
            } catch {
                testResult = error.localizedDescription
            }
            testing = false
        }
    }
}

// MARK: - History

struct HistorySettings: View {
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var controller: AppController
    @AppStorage(Pref.historyEnabled) private var enabled = true
    @State private var query = ""
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Toggle("Keep a history of what I dictate", isOn: $enabled)
                    .onChange(of: enabled) { _, on in if !on { history.clear() } }
            } footer: {
                Text("Text only, never audio. It stays on this Mac in SayType's folder and is never uploaded. Turning this off also deletes it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextField("Search", text: $query)
                let results = history.search(query)
                if results.isEmpty {
                    Text(history.entries.isEmpty ? "Nothing yet." : "No matches.").foregroundStyle(.secondary)
                }
                ForEach(results.prefix(200)) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.text).lineLimit(4).textSelection(.enabled)
                        HStack {
                            Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(entry.app)")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.text, forType: .string)
                            }
                            Button("Type again") { controller.typeAgain(entry.text) }
                            Button(role: .destructive) { history.remove(entry.id) } label: { Image(systemName: "trash") }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    .padding(.vertical, 2)
                }
            }

            if !history.entries.isEmpty {
                Section {
                    Button("Clear history…", role: .destructive) { confirmClear = true }
                        .confirmationDialog("Delete all \(history.entries.count) items?", isPresented: $confirmClear) {
                            Button("Delete history", role: .destructive) { history.clear() }
                        }
                }
            }
        }
        .formStyle(.grouped)
    }
}
