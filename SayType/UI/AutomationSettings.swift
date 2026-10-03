import AppKit
import SwiftUI

/// The command-line tool: choose what to call it, install it, and see what it can do.
struct AutomationSettings: View {
    @ObservedObject private var theme = Theme.shared
    @AppStorage(Pref.cliCommandName) private var savedName = CommandAlias.defaultName
    @State private var input = ""
    @State private var result: Result<CommandAlias.Installed, CommandAlias.AliasError>?
    @State private var copied: String?

    private var cleaned: String { CommandAlias.sanitize(input) }
    private var problem: String? { cleaned.isEmpty && input.isEmpty ? nil : CommandAlias.problem(with: cleaned) }
    private var shown: String { cleaned.isEmpty ? savedName : cleaned }
    private var script: URL? { Bundle.main.resourceURL?.appendingPathComponent("CLI/saytype") }

    private let commands: [(String, String, String)] = [
        ("toggle", "Turn dictation on or off", "switch.2"),
        ("on / off", "Turn dictation on, or off", "power"),
        ("record", "Start or stop manual recording", "record.circle"),
        ("speak \"Hello\"", "Read text aloud (or the selection)", "speaker.wave.2.fill"),
        ("edit", "Voice-edit the selected text", "wand.and.stars"),
        ("transcribe file.m4a", "Transcribe an audio or video file", "waveform"),
        ("meeting start", "Start (or stop) recording a meeting", "person.2.wave.2.fill"),
        ("last", "Print the last thing you dictated", "text.quote"),
        ("status", "Print what SayType is doing", "info.circle"),
    ]

    var body: some View {
        PlayPage {
            PlaySection("Name your command", tint: .lavender) {
                Text("Call it whatever you like. With the name below you'd type:")
                    .foregroundStyle(theme.inkSoft)
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right.circle.fill").foregroundStyle(theme.accent).font(.system(size: 20))
                    TextField("saytype", text: $input)
                        .font(.system(size: 17, weight: .semibold)).fontDesign(.monospaced)
                        .onSubmit(install)
                }
                preview
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.bold(.peach))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if !input.isEmpty, cleaned != input {
                    Label("Saved as “\(cleaned)”. Commands are one word, so spaces become hyphens.", systemImage: "info.circle")
                        .font(.system(size: 12.5)).foregroundStyle(theme.inkSoft)
                        .transition(.opacity)
                }
                HStack {
                    Button(action: install) {
                        Label(cleaned == savedName && savedName != CommandAlias.defaultName ? "Update command" : "Install command",
                              systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.playPrimary)
                    .disabled(problem != nil || cleaned.isEmpty)
                    if savedName != CommandAlias.defaultName {
                        Button("Back to “saytype”", action: reset)
                    }
                    Spacer()
                    PlayChip(text: "Now: \(savedName)", tint: .lavender, icon: "terminal")
                }
                outcome
            } footer: {
                Text("SayType adds a small link with that name to a folder on your PATH. “saytype” keeps working too. Open a new terminal window after installing.")
            }
            .playAnimation(value: problem)
            .playAnimation(value: result?.isSuccess)

            PlaySection("What you can run", tint: .blue) {
                ForEach(commands, id: \.0) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.2).font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.bold(.blue)).frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: theme.radius(10), style: .continuous).fill(theme.soft(.blue)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(shown) \(item.0)").font(.system(size: 13.5, weight: .semibold)).fontDesign(.monospaced)
                            Text(item.1).font(.system(size: 12)).foregroundStyle(theme.inkSoft)
                        }
                        Spacer()
                        Button { copy("\(shown) \(item.0)") } label: {
                            Image(systemName: copied == "\(shown) \(item.0)" ? "checkmark" : "doc.on.doc")
                                .symbolEffect(.bounce, value: copied)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy")
                    }
                }
            }

            PlaySection("Other ways in", tint: .mint) {
                Label("Shortcuts app: search “SayType” for Toggle Dictation, Speak Text, Transcribe Audio File and more.", systemImage: "square.stack.3d.up.fill")
                Label("Links: saytype://dictation/toggle works from anywhere, including scripts and Raycast. The link prefix stays “saytype”.", systemImage: "link")
                Label("Raycast: ready-made script commands are in the project's integrations folder.", systemImage: "bolt.fill")
            }
            .font(.system(size: 13))
        }
        .onAppear { if input.isEmpty { input = savedName } }
    }

    // MARK: Pieces

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(["toggle", "speak \"Build finished\"", "last | pbcopy"], id: \.self) { example in
                Text("\(shown) \(example)")
                    .font(.system(size: 13, weight: .medium)).fontDesign(.monospaced)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: theme.radius(11), style: .continuous).fill(theme.ink.opacity(0.07)))
                    .contentTransition(.opacity)
            }
        }
        .playAnimation(value: shown)
    }

    @ViewBuilder private var outcome: some View {
        switch result {
        case .success(let installed):
            VStack(alignment: .leading, spacing: 8) {
                Label(installed.alreadyThere ? "Already installed" : "Installed", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(theme.bold(.mint))
                Text(installed.url.path).font(.system(size: 12)).fontDesign(.monospaced).foregroundStyle(theme.inkSoft)
                if !installed.onPath {
                    Text("That folder usually isn't on your PATH. Add this line to your ~/.zshrc, then open a new terminal:")
                        .font(.system(size: 12.5)).foregroundStyle(theme.bold(.peach))
                    HStack {
                        Text(pathLine(for: installed.url)).font(.system(size: 12)).fontDesign(.monospaced).textSelection(.enabled)
                        Spacer()
                        Button("Copy") { copy(pathLine(for: installed.url)) }
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: theme.radius(14), style: .continuous).fill(theme.soft(.mint).opacity(0.8)))
            .transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
        case .failure(let error):
            Label(error.localizedDescription, systemImage: "xmark.octagon.fill")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.bold(.pink))
                .transition(.opacity)
        case nil:
            EmptyView()
        }
    }

    // MARK: Actions

    private func install() {
        let name = cleaned
        guard problem == nil, !name.isEmpty, let script else { return }
        let folders = CommandAlias.candidateFolders()
        do {
            if savedName != name, savedName != CommandAlias.defaultName {
                CommandAlias.remove(name: savedName, folders: folders, script: script)
            }
            let installed = try CommandAlias.install(name: name, script: script, folders: folders)
            savedName = name
            Pref.defaults.set(installed.url.deletingLastPathComponent().path, forKey: Pref.cliCommandFolder)
            withAnimation(theme.spring) { result = .success(installed) }
        } catch let error as CommandAlias.AliasError {
            withAnimation(theme.spring) { result = .failure(error) }
        } catch {
            withAnimation(theme.spring) { result = .failure(.failed(error.localizedDescription)) }
        }
    }

    private func reset() {
        if let script { CommandAlias.remove(name: savedName, folders: CommandAlias.candidateFolders(), script: script) }
        savedName = CommandAlias.defaultName
        input = CommandAlias.defaultName
        withAnimation(theme.spring) { result = nil }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { if copied == text { copied = nil } }
    }

    private func pathLine(for url: URL) -> String {
        "export PATH=\"\(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "$HOME")):$PATH\""
    }
}

private extension Result {
    var isSuccess: Bool { if case .success = self { return true } else { return false } }
}
