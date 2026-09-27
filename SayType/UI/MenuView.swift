import Sparkle
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var focus: FocusMonitor
    @EnvironmentObject var license: LicenseManager
    let updater: SPUUpdater
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SayType").font(.headline)
                Spacer()
                Toggle("", isOn: $controller.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Turn dictation on or off (\(HotKeys.toggleListening.label))")
            }

            statusRow

            if case .trial(let days) = license.state {
                HStack {
                    Text("Free trial: \(days) day\(days == 1 ? "" : "s") left").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Buy SayType") { NSWorkspace.shared.open(LicenseConfig.checkoutURL) }
                        .buttonStyle(.link).font(.caption)
                }
            }

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
                Menu("More") {
                    Button("Setup…") { OnboardingWindow.shared.show() }
                    Button("Check for Updates…") { updater.checkForUpdates() }
                    Button("Website") { NSWorkspace.shared.open(URL(string: "https://frugoman.github.io/saytype-site/")!) }
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
        case .trialExpired:
            VStack(alignment: .leading, spacing: 6) {
                Text("Your free trial has ended. Buy SayType to keep dictating. Your settings and words are saved.")
                    .font(.callout)
                HStack {
                    Button("Buy SayType") { NSWorkspace.shared.open(LicenseConfig.checkoutURL) }
                        .buttonStyle(.borderedProminent)
                    Button("Enter License Key…") {
                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()
                    }
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
