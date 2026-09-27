import SwiftUI

struct MenuView: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var focus: FocusMonitor
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("VoiceTyper").font(.headline)
                Spacer()
                Toggle("", isOn: $controller.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Turn dictation on or off (\(HotKeys.toggleListening.label))")
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

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Label(controller.sttName, systemImage: "waveform").font(.caption)
                if !controller.ttsStatus.isEmpty {
                    Label(controller.ttsStatus, systemImage: "speaker.wave.2").font(.caption)
                }
                Text("\(HotKeys.toggleListening.label) on/off   ·   \(HotKeys.speakSelection.label) read selection aloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
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
                Text("VoiceTyper needs Accessibility access to see which text field is focused and type into it.")
                    .font(.callout)
                Button("Open Accessibility Settings") { FocusMonitor.openAccessibilitySettings() }
            }
        case .needsMicPermission:
            VStack(alignment: .leading, spacing: 6) {
                Text("Microphone access is off.").font(.callout)
                Button("Open Microphone Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
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
        case .speaking: return "Reading aloud (\(HotKeys.speakSelection.label) to stop)"
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
