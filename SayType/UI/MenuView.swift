import SwiftUI

struct MenuView: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var focus: FocusMonitor
    @EnvironmentObject var history: HistoryStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SayType").font(.headline)
                Spacer()
                Toggle("", isOn: $controller.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Turn dictation on or off (\(ShortcutAction.toggleDictation.shortcut.label))")
            }

            statusRow

            if !controller.lastTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last typed").font(.caption).foregroundStyle(.secondary)
                    Text(controller.lastTranscript)
                        .font(.callout)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }

            if history.entries.count > 1 {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent").font(.caption).foregroundStyle(.secondary)
                    ForEach(history.entries.dropFirst().prefix(3)) { entry in
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                        } label: {
                            Text(entry.text).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .help("Click to copy")
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Label(controller.sttName, systemImage: "waveform").font(.caption)
                if !controller.ttsStatus.isEmpty {
                    Label(controller.ttsStatus, systemImage: "speaker.wave.2").font(.caption)
                }
                Text("\(ShortcutAction.toggleDictation.shortcut.label) on/off  ·  \(ShortcutAction.pushToTalk.shortcut.label) push to talk  ·  \(ShortcutAction.speakSelection.shortcut.label) read aloud  ·  \(ShortcutAction.editSelection.shortcut.label) edit by voice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Menu("More") {
                    Button("Transcribe a file…") { TranscribeWindow.shared.show() }
                    Button(TranscribeWindow.shared.isRecordingMeeting ? "Stop recording meeting" : "Record a meeting…") {
                        TranscribeWindow.shared.toggleMeeting()
                    }
                    Button("Copy last transcript") { controller.copyLastTranscript() }
                    Divider()
                    Button("Setup…") { OnboardingWindow.shared.show() }
                    Button("Website") { NSWorkspace.shared.open(Links.website) }
                    Divider()
                    Button("Buy Me a Coffee…") { NSWorkspace.shared.open(Links.coffee) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    @ViewBuilder private var statusRow: some View {
        switch controller.status {
        case .loading(let fraction, let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.callout)
                ProgressView(value: fraction)
            }
        case .needsAccessibility:
            VStack(alignment: .leading, spacing: 6) {
                Text("SayType needs Accessibility access to see which text field is focused and type into it.")
                    .font(.callout)
                Button("Finish Setup…") { OnboardingWindow.shared.show() }
            }
        case .needsMicPermission:
            VStack(alignment: .leading, spacing: 6) {
                Text("SayType needs microphone access.").font(.callout)
                Button("Finish Setup…") { OnboardingWindow.shared.show() }
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.callout).foregroundStyle(.red)
                Button("Retry") { Task { await controller.reloadSpeechToText() } }
            }
        default:
            Label(statusText, systemImage: statusSymbol)
                .font(.callout)
                .foregroundStyle(statusColor)
        }
    }

    private var statusText: String {
        switch controller.status {
        case .idle: return focus.state == .secure ? "Password field — not listening" : "Waiting for a text field"
        case .listening: return "Listening in \(focus.frontAppName)"
        case .hearing: return "Hearing you…"
        case .transcribing: return "Typing…"
        case .speaking: return "Reading aloud (\(ShortcutAction.speakSelection.shortcut.label) to stop)"
        case .disabled: return "Off"
        default: return ""
        }
    }

    private var statusSymbol: String {
        switch controller.status {
        case .listening, .hearing: return "mic.fill"
        case .transcribing: return "text.cursor"
        case .speaking: return "speaker.wave.2.fill"
        case .disabled: return "mic.slash"
        default: return "mic"
        }
    }

    private var statusColor: Color {
        switch controller.status {
        case .listening, .hearing, .transcribing: return .green
        case .disabled: return .secondary
        default: return .primary
        }
    }
}
