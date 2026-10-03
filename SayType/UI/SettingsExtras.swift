import AppKit
import SwiftUI

// MARK: - Shared bits

/// Lays chips out in rows, wrapping to the next line.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.maxX).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(bounds.width, subviews) {
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row { var y: CGFloat = 0; var height: CGFloat = 0; var maxX: CGFloat = 0; var items: [(index: Int, x: CGFloat)] = [] }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        var x: CGFloat = 0
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                let prev = rows[rows.count - 1]
                rows.append(Row(y: prev.y + prev.height + spacing))
                x = 0
            }
            rows[rows.count - 1].items.append((i, x))
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += size.width
            rows[rows.count - 1].maxX = x
            x += spacing
        }
        return rows
    }
}

/// A small round icon button used on cards.
private struct PlayIconButton: View {
    @ObservedObject private var theme = Theme.shared
    let icon: String
    var tint: PlayTint = .blue
    var help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.bold(tint))
                .frame(width: 30, height: 30)
                .background(Circle().fill(theme.soft(tint).opacity(hover ? 1 : 0.8)))
                .scaleEffect(hover ? 1.08 : 1)
                .animation(theme.spring, value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: - Shortcuts

/// Click, then press the key combination you want.
struct ShortcutRow: View {
    let action: ShortcutAction
    @EnvironmentObject var controller: AppController
    @ObservedObject private var theme = Theme.shared
    @State private var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    init(action: ShortcutAction) {
        self.action = action
        _shortcut = State(initialValue: action.shortcut)
    }

    private var conflicted: Bool { controller.shortcutConflicts.contains(action) }

    var body: some View {
        HStack(spacing: 10) {
            Text(action.title).font(.system(size: 13.5, weight: .semibold))
            Spacer(minLength: 8)
            if conflicted {
                PlayChip(text: "In use", tint: .peach, icon: "exclamationmark.triangle.fill")
                    .help("Another app, or another SayType action, already uses this shortcut. Pick a different one.")
                    .transition(.scale.combined(with: .opacity))
            }
            keycap
            Button("Reset") {
                action.save(nil)
                shortcut = action.defaultShortcut
                controller.registerHotKeys()
            }
            .disabled(shortcut == action.defaultShortcut)
        }
        .playAnimation(value: conflicted)
        .playAnimation(value: recording)
        .onDisappear(perform: stop)
    }

    private var keycap: some View {
        let pulseOK = theme.animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !(recording && pulseOK))) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = recording && pulseOK ? (sin(t * 5) + 1) / 2 : 0
            Button { recording ? stop() : start() } label: {
                Text(recording ? "Press keys…" : shortcut.label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(recording ? Color.white : theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .frame(minWidth: 96)
                    .background(
                        RoundedRectangle(cornerRadius: theme.radius(11), style: .continuous)
                            .fill(recording ? theme.accent : theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.radius(11), style: .continuous)
                            .strokeBorder(recording ? theme.accent.opacity(0.4 + 0.4 * pulse)
                                          : conflicted ? theme.bold(.peach) : theme.ink.opacity(0.16), lineWidth: 1.5)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: theme.radius(11), style: .continuous)
                            .fill(theme.ink.opacity(0.12)).offset(y: recording ? 1 : 3)
                    )
                    .shadow(color: recording ? theme.accent.opacity(0.35 + 0.3 * pulse) : theme.shadow, radius: recording ? 8 + 6 * pulse : 5, y: 2)
                    .scaleEffect(recording ? 1 + 0.04 * pulse : 1)
                    .offset(y: recording ? 1 : 0)
            }
            .buttonStyle(.plain)
        }
        .help(recording ? "Press the new shortcut, or Escape to cancel" : "Click, then press the keys you want")
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
    @ObservedObject private var theme = Theme.shared
    @AppStorage(Pref.voiceCommands) private var commands = true
    @AppStorage(Pref.spokenPunctuation) private var punctuation = false

    private let inSentence = ["new line", "new paragraph", "scratch that"]
    private let onTheirOwn = ["undo that", "select all", "press enter"]
    private let symbols = ["comma", "period", "question mark", "open paren", "quote"]

    var body: some View {
        PlayPage {
            PlaySection(tint: .mint) {
                Toggle("Voice commands", isOn: $commands)
                Toggle("Spoken punctuation", isOn: $punctuation)

                VStack(alignment: .leading, spacing: theme.space(8)) {
                    reference("Anywhere in a sentence", inSentence, .blue)
                    reference("On their own", onTheirOwn, .lavender)
                    reference("Spoken punctuation", symbols, .butter)
                }
                .padding(.top, 2)
                .opacity(commands || punctuation ? 1 : 0.5)
            } header: {
                Text("Commands")
            } footer: {
                Text("Say “new line”, “new paragraph” or “scratch that” (deletes what was just typed) anywhere in a sentence. On their own: “undo that”, “select all”, “press enter”. Spoken punctuation turns “comma”, “period”, “question mark”, “open paren”, “quote” and so on into symbols.")
            }

            PlaySection(tint: .pink) {
                Button {
                    withAnimation(theme.spring) { snippets.entries.insert(Snippet(trigger: "", expansion: ""), at: 0) }
                } label: {
                    Label("Add snippet", systemImage: "plus")
                }
                .buttonStyle(.playPrimary)

                VStack(spacing: theme.space(10)) {
                    ForEach($snippets.entries) { $snippet in
                        snippetCard($snippet)
                            .transition(.asymmetric(insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                                                    removal: .scale(scale: 0.9).combined(with: .opacity)))
                    }
                }
                .playAnimation(value: snippets.entries.count)

                if snippets.entries.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "text.badge.plus").foregroundStyle(theme.bold(.pink))
                        Text("No snippets yet. Add one to type longer text with a short phrase.")
                            .font(.system(size: 12.5)).foregroundStyle(theme.inkSoft)
                    }
                }
            } header: {
                Text("Snippets")
            } footer: {
                Text("Pick a phrase you wouldn't say by accident, like “sign off snippet”. Use {date}, {time} and {clipboard} inside the text.")
            }
        }
    }

    private func reference(_ title: String, _ items: [String], _ tint: PlayTint) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11.5, weight: .bold)).foregroundStyle(theme.inkSoft)
            FlowLayout(spacing: 6) {
                ForEach(items, id: \.self) { PlayChip(text: "“\($0)”", tint: tint) }
            }
        }
    }

    private func snippetCard(_ snippet: Binding<Snippet>) -> some View {
        let id = snippet.wrappedValue.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(theme.bold(.pink))
                    .frame(width: 24, height: 24).background(Circle().fill(theme.soft(.pink)))
                TextField("When I say", text: snippet.trigger).font(.system(size: 13.5, weight: .bold))
                PlayIconButton(icon: "trash", tint: .pink, help: "Delete snippet") {
                    withAnimation(theme.spring) { snippets.entries.removeAll { $0.id == id } }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.turn.down.right").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.inkSoft).frame(width: 24, height: 24)
                TextField("Type this", text: snippet.expansion, axis: .vertical)
                    .lineLimit(1...6)
                    .font(.system(size: 13))
            }
        }
        .padding(theme.space(11))
        .background(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous).fill(theme.ink.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous).strokeBorder(theme.cardStroke))
    }
}

// MARK: - Per-app profiles

private extension ToneStyle {
    var tint: PlayTint {
        switch self {
        case .standard: return .blue
        case .casual: return .pink
        case .professional: return .lavender
        case .code: return .mint
        case .literal: return .butter
        }
    }
}

struct ProfileSettings: View {
    @EnvironmentObject var profiles: ProfileStore
    @ObservedObject private var theme = Theme.shared
    @AppStorage(Pref.pauseToCommit) private var globalPause = 0.8
    @State private var open: Set<String> = []

    var body: some View {
        PlayPage {
            PlaySection(tint: .lavender) {
                VStack(spacing: theme.space(10)) {
                    ForEach($profiles.profiles) { $profile in
                        profileCard($profile)
                            .transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
                    }
                }
                .playAnimation(value: profiles.profiles.count)

                if profiles.profiles.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "app.dashed").foregroundStyle(theme.bold(.lavender))
                        Text("No profiles yet.").foregroundStyle(theme.inkSoft)
                    }
                }
            } header: {
                Text("Apps")
            } footer: {
                Text("A profile changes how SayType behaves while that app is in front: how long it waits after you pause, the language, the tone used by AI cleanup, and more. Tone needs AI cleanup turned on.")
            }

            PlaySection(tint: .butter) {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                                guard let id = app.bundleIdentifier, profiles.profile(for: id) == nil else { return }
                                withAnimation(theme.spring) {
                                    profiles.profiles.append(AppProfile(bundleID: id, name: app.localizedName ?? id))
                                }
                            }
                        }
                    } label: {
                        Label("Add running app…", systemImage: "plus.app")
                    }
                    .menuStyle(.button).menuIndicator(.hidden).fixedSize()
                    Button {
                        withAnimation(theme.spring) {
                            for suggestion in ProfileStore.suggestions
                            where profiles.profile(for: suggestion.bundleID) == nil
                                && NSWorkspace.shared.urlForApplication(withBundleIdentifier: suggestion.bundleID) != nil {
                                profiles.profiles.append(suggestion)
                            }
                        }
                    } label: {
                        Label("Add suggested profiles for my apps", systemImage: "sparkles")
                    }
                    .buttonStyle(.playPrimary)
                }
            } footer: {
                Text("Suggestions cover chat apps (casual, no final period), mail (professional) and terminals and editors (code).")
            }
        }
    }

    private func profileCard(_ profile: Binding<AppProfile>) -> some View {
        let p = profile.wrappedValue
        let isOpen = open.contains(p.bundleID)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(theme.spring) {
                    if isOpen { open.remove(p.bundleID) } else { open.insert(p.bundleID) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(theme.inkSoft)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 14)
                    Text(p.name).font(.system(size: 14, weight: .bold))
                    Spacer()
                    PlayChip(text: p.tone.label, tint: p.tone.tint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: theme.space(12)) {
                    Picker("Tone", selection: profile.tone) {
                        ForEach(ToneStyle.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Custom pause", isOn: Binding(
                        get: { profile.wrappedValue.pauseToCommit != nil },
                        set: { profile.wrappedValue.pauseToCommit = $0 ? globalPause : nil }))
                    if let pause = p.pauseToCommit {
                        HStack {
                            Slider(value: Binding(get: { pause }, set: { profile.wrappedValue.pauseToCommit = $0 }), in: 0.4...2.0, step: 0.1)
                            Text(String(format: "%.1fs", pause)).monospacedDigit().frame(width: 36)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Picker("Language", selection: Binding(get: { profile.wrappedValue.language ?? "" }, set: { profile.wrappedValue.language = $0.isEmpty ? nil : $0 })) {
                        Text("Same as general").tag("")
                        ForEach(speechLanguages(for: STTEngineKind(rawValue: Pref.defaults.string(forKey: Pref.sttEngine) ?? "") ?? .whisperKit), id: \.code) { Text($0.name).tag($0.code) }
                    }
                    Toggle("Remove the final period", isOn: profile.stripTrailingPeriod)
                    TextField("Extra words for this app", text: profile.extraTerms)
                    Button("Remove profile", role: .destructive) {
                        withAnimation(theme.spring) {
                            profiles.profiles.removeAll { $0.bundleID == p.bundleID }
                            open.remove(p.bundleID)
                        }
                    }
                }
                .padding(.top, theme.space(14))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
        .padding(theme.space(13))
        .background(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous)
            .fill(isOpen ? p.tone.tint.softFill(theme) : theme.ink.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous)
            .strokeBorder(isOpen ? theme.bold(p.tone.tint).opacity(0.35) : theme.cardStroke))
        .playAnimation(value: p.pauseToCommit != nil)
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

private extension PlayTint {
    @MainActor func softFill(_ theme: Theme) -> Color { theme.soft(self).opacity(0.6) }
}

// MARK: - AI

struct AISettings: View {
    @ObservedObject private var theme = Theme.shared
    @AppStorage(Pref.cleanupLevel) private var cleanup = CleanupLevel.off.rawValue
    @AppStorage(Pref.aiBackend) private var backend = AIBackendKind.apple.rawValue
    @AppStorage(Pref.aiServerURL) private var serverURL = "http://127.0.0.1:11434"
    @AppStorage(Pref.aiServerModel) private var serverModel = "llama3.2"
    @AppStorage(Pref.outputLanguage) private var outputLanguage = ""
    @State private var testResult = ""
    @State private var testing = false
    @State private var testOK: Bool?

    /// Only languages the selected AI backend can really write in.
    private var writable: [(name: String, code: String)] { AIService.current.writableLanguages }

    var body: some View {
        PlayPage {
            PlaySection(tint: .blue) {
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
            }

            PlaySection(tint: .lavender) {
                Picker("AI model", selection: $backend) {
                    ForEach(AIBackendKind.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if backend == AIBackendKind.server.rawValue {
                    VStack(alignment: .leading, spacing: theme.space(10)) {
                        TextField("Server URL", text: $serverURL)
                        TextField("Model", text: $serverModel)
                    }
                    .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                }
                HStack(spacing: 10) {
                    Button { test() } label: {
                        Label(testing ? "Testing…" : "Test", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.playPrimary)
                    .disabled(testing)
                    statusChips
                }
                .playAnimation(value: testing)
                .playAnimation(value: testOK)
            } header: {
                Text("Where the AI runs")
            } footer: {
                Text("Always on your Mac. For a server, run Ollama (`ollama serve`, then `ollama pull llama3.2`) and keep the address above, or point it at LM Studio, llama.cpp or mlx_lm.server.")
            }

            PlaySection(tint: .peach) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(theme.bold(.peach))
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: theme.radius(12), style: .continuous).fill(theme.soft(.peach)))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Select text, then press").font(.system(size: 13)).foregroundStyle(theme.inkSoft)
                            Text(ShortcutAction.editSelection.shortcut.label)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: theme.radius(8), style: .continuous).fill(theme.card))
                                .overlay(RoundedRectangle(cornerRadius: theme.radius(8), style: .continuous).strokeBorder(theme.ink.opacity(0.16)))
                        }
                        Text("Select text in any app, press \(ShortcutAction.editSelection.shortcut.label) and say what to change: “make this shorter”, “fix the grammar”, “translate to Spanish”. The selection is replaced.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Edit by voice")
            }
        }
        .playAnimation(value: backend)
        .onChange(of: backend) { resetUnsupportedLanguage() }
        .onAppear(perform: resetUnsupportedLanguage)
    }

    @ViewBuilder private var statusChips: some View {
        if let reason = AIService.current.unavailableReason {
            PlayChip(text: reason, tint: .peach, icon: "exclamationmark.circle.fill")
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        } else if testing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Asking the model…").font(.system(size: 11.5, weight: .bold))
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(theme.soft(.butter)))
            .transition(.scale.combined(with: .opacity))
        } else if testResult.isEmpty {
            PlayChip(text: "Ready", tint: .mint, icon: "checkmark.circle.fill")
        } else {
            PlayChip(text: testResult, tint: testOK == true ? .mint : .pink,
                     icon: testOK == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                .symbolEffect(.bounce, value: testResult)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
        }
    }

    private func resetUnsupportedLanguage() {
        if !outputLanguage.isEmpty, !writable.contains(where: { $0.name == outputLanguage }) { outputLanguage = "" }
    }

    private func test() {
        testing = true
        testOK = nil
        testResult = ""
        Task {
            let start = Date()
            do {
                let reply = try await AIService.current.complete(system: "Reply with the single word OK.", user: "Ping", timeout: 30)
                testResult = "Working (\(String(format: "%.1f", Date().timeIntervalSince(start)))s): \(reply.prefix(40))"
                testOK = true
            } catch {
                testResult = error.localizedDescription
                testOK = false
            }
            testing = false
        }
    }
}

// MARK: - History

struct HistorySettings: View {
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var controller: AppController
    @ObservedObject private var theme = Theme.shared
    @AppStorage(Pref.historyEnabled) private var enabled = true
    @AppStorage(Pref.historyLimit) private var limit = 10
    @State private var query = ""
    @State private var confirmClear = false
    @State private var copied: UUID?

    var body: some View {
        PlayPage {
            PlaySection(tint: .mint) {
                Toggle("Keep a history of what I dictate", isOn: $enabled)
                    .onChange(of: enabled) { _, on in if !on { history.clear() } }
                if enabled {
                    Picker("Items to keep", selection: $limit) {
                        ForEach([5, 10, 25, 50, 100, 500, 1000], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .onChange(of: limit) { _, _ in history.applyLimit() }
                }
            } footer: {
                Text("Text only, never audio. It stays on this Mac in SayType's folder and is never uploaded. Only the most recent items are kept; lowering the number deletes the older ones. Turning this off also deletes it.")
            }

            PlaySection(tint: .blue) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.inkSoft)
                    TextField("Search", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(theme.inkSoft)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: theme.radius(12), style: .continuous).fill(theme.ink.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: theme.radius(12), style: .continuous).strokeBorder(theme.cardStroke))
                .playAnimation(value: query.isEmpty)

                let results = history.search(query)
                if results.isEmpty {
                    emptyState(noEntries: history.entries.isEmpty)
                }
                VStack(spacing: theme.space(10)) {
                    ForEach(results.prefix(200)) { entry in
                        entryCard(entry)
                            .transition(.asymmetric(insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity),
                                                    removal: .scale(scale: 0.9).combined(with: .opacity)))
                    }
                }
                .playAnimation(value: results.count)
            }

            if !history.entries.isEmpty {
                PlaySection(tint: .pink) {
                    Button("Clear history…", role: .destructive) { confirmClear = true }
                        .confirmationDialog("Delete all \(history.entries.count) items?", isPresented: $confirmClear) {
                            Button("Delete history", role: .destructive) { history.clear() }
                        }
                }
            }
        }
    }

    private func entryCard(_ entry: HistoryEntry) -> some View {
        let isCopied = copied == entry.id
        return VStack(alignment: .leading, spacing: 9) {
            Text(entry.text).font(.system(size: 13.5)).lineLimit(4).textSelection(.enabled)
            HStack(spacing: 8) {
                PlayChip(text: entry.app, tint: PlayTint.auto(for: entry.app))
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11.5)).foregroundStyle(theme.inkSoft)
                Spacer()
                if isCopied {
                    PlayChip(text: "Copied", tint: .mint, icon: "checkmark")
                        .transition(.scale(scale: 0.5, anchor: .trailing).combined(with: .opacity))
                }
                PlayIconButton(icon: isCopied ? "checkmark" : "doc.on.doc", tint: .mint, help: "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                    withAnimation(theme.spring) { copied = entry.id }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        if copied == entry.id { withAnimation(theme.spring) { copied = nil } }
                    }
                }
                PlayIconButton(icon: "keyboard", tint: .blue, help: "Type again") { controller.typeAgain(entry.text) }
                PlayIconButton(icon: "trash", tint: .pink, help: "Delete") {
                    withAnimation(theme.spring) { history.remove(entry.id) }
                }
            }
        }
        .padding(theme.space(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous).fill(theme.ink.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous).strokeBorder(theme.cardStroke))
    }

    private func emptyState(noEntries: Bool) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(theme.soft(.butter)).frame(width: 74, height: 74).offset(x: -34, y: 8)
                RoundedRectangle(cornerRadius: theme.radius(14), style: .continuous)
                    .fill(theme.soft(.lavender)).frame(width: 58, height: 58).rotationEffect(.degrees(12)).offset(x: 40, y: 14)
                Circle().strokeBorder(theme.bold(.pink).opacity(0.5), lineWidth: 5).frame(width: 30, height: 30).offset(x: 52, y: -26)
                Image(systemName: "triangle.fill").font(.system(size: 14)).foregroundStyle(theme.bold(.mint)).offset(x: -56, y: -26)
                Image(systemName: "bubble.left.fill").font(.system(size: 54)).foregroundStyle(theme.card)
                    .shadow(color: theme.shadow, radius: 8, y: 3)
                Image(systemName: noEntries ? "mic.fill" : "magnifyingglass")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(theme.accent).offset(y: -3)
                Image(systemName: "sparkle").font(.system(size: 14, weight: .bold)).foregroundStyle(theme.bold(.butter)).offset(x: 24, y: -34)
            }
            .frame(height: 104)
            Text(noEntries ? "Nothing yet" : "No matches").font(.system(size: 14, weight: .bold))
            Text(noEntries ? "Things you dictate will show up here." : "Try a different word.")
                .font(.system(size: 12.5)).foregroundStyle(theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, theme.space(10))
    }
}
