import SwiftUI

struct MenuView: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var focus: FocusMonitor
    @EnvironmentObject var history: HistoryStore
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var theme = Theme.shared

    var body: some View {
        VStack(spacing: theme.space(14)) {
            header
            statusCard
            if !controller.lastTranscript.isEmpty { lastTyped }
            if history.entries.count > 1 { recent }
            shortcuts
            footer
        }
        .padding(theme.space(16))
        .frame(width: 320)
        .background(PlayBackdrop())
        .playStyle()
        .playAnimation(value: controller.lastTranscript)
        .playAnimation(value: history.entries.count)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("SayType").font(.system(size: 17, weight: .heavy))
            Spacer()
            Toggle("", isOn: $controller.enabled)
                .labelsHidden()
                .help("Turn dictation on or off (\(ShortcutAction.toggleDictation.shortcut.label))")
        }
    }

    // MARK: Status

    private var look: StatusLook {
        switch controller.status {
        case .listening, .hearing: return StatusLook(tint: .mint, symbol: "mic.fill", live: true)
        case .transcribing, .loading, .speaking:
            return StatusLook(tint: .blue, symbol: transcribingSymbol, live: false)
        case .disabled: return StatusLook(tint: nil, symbol: "mic.slash.fill", live: false)
        case .needsAccessibility, .needsMicPermission, .error:
            return StatusLook(tint: .peach, symbol: "exclamationmark", live: false)
        case .idle: return StatusLook(tint: focus.state == .secure ? .peach : nil,
                                      symbol: focus.state == .secure ? "lock.fill" : "mic", live: false)
        }
    }

    private var transcribingSymbol: String {
        switch controller.status {
        case .speaking: return "speaker.wave.2.fill"
        case .loading: return "arrow.triangle.2.circlepath"
        default: return "text.cursor"
        }
    }

    private var statusCard: some View {
        PlaySection(tint: look.tint ?? .lavender) {
            HStack(spacing: theme.space(14)) {
                StatusOrb(look: look, level: controller.micLevelDB, active: controller.status == .hearing)
                VStack(alignment: .leading, spacing: 4) { statusBody }
                Spacer(minLength: 0)
            }
        }
        .playAnimation(value: statusKey)
    }

    private var statusKey: String { "\(controller.status)" + (focus.state == .secure ? "s" : "") }

    @ViewBuilder private var statusBody: some View {
        switch controller.status {
        case .loading(let fraction, let message):
            Text("Warming up").font(.system(size: 15, weight: .bold))
            Text(message).font(.system(size: 12)).foregroundStyle(theme.inkSoft).lineLimit(2)
            ProgressView(value: fraction).tint(theme.bold(.blue))
        case .needsAccessibility:
            Text("One more step").font(.system(size: 15, weight: .bold))
            Text("SayType needs Accessibility access to type into the focused text field.")
                .font(.system(size: 12)).foregroundStyle(theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            Button("Finish Setup…") { OnboardingWindow.shared.show() }.buttonStyle(.playPrimary)
        case .needsMicPermission:
            Text("One more step").font(.system(size: 15, weight: .bold))
            Text("SayType needs microphone access.").font(.system(size: 12)).foregroundStyle(theme.inkSoft)
            Button("Finish Setup…") { OnboardingWindow.shared.show() }.buttonStyle(.playPrimary)
        case .error(let message):
            Text("Something went wrong").font(.system(size: 15, weight: .bold))
            Text(message).font(.system(size: 12)).foregroundStyle(theme.bold(.peach)).lineLimit(3)
            Button("Retry") { Task { await controller.reloadSpeechToText() } }
        default:
            Text(headline).font(.system(size: 15, weight: .bold))
            Text(statusText).font(.system(size: 12)).foregroundStyle(theme.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headline: String {
        switch controller.status {
        case .listening: return "Ready when you are"
        case .hearing: return "I hear you"
        case .transcribing: return "Typing…"
        case .speaking: return "Reading aloud"
        case .disabled: return "Taking a nap"
        default: return focus.state == .secure ? "Password field" : "Standing by"
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

    // MARK: Text

    private var lastTyped: some View {
        PlaySection("Last typed", tint: .butter) {
            Text(controller.lastTranscript)
                .font(.system(size: 13.5))
                .lineLimit(4)
                .textSelection(.enabled)
        }
    }

    private var recent: some View {
        PlaySection("Recent", tint: .blue) {
            VStack(spacing: 6) {
                ForEach(history.entries.dropFirst().prefix(3)) { entry in
                    RecentRow(text: entry.text) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                    }
                }
            }
        }
    }

    // MARK: Shortcuts and info

    private var shortcuts: some View {
        PlaySection(tint: .lavender) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").foregroundStyle(theme.bold(.lavender))
                Text(controller.sttName).font(.system(size: 12.5, weight: .semibold))
                Spacer()
            }
            if !controller.ttsStatus.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2").foregroundStyle(theme.bold(.lavender))
                    Text(controller.ttsStatus).font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                }
            }
            VStack(spacing: 7) {
                shortcutRow(ShortcutAction.toggleDictation.shortcut.label, "on / off")
                shortcutRow(ShortcutAction.pushToTalk.shortcut.label, "push to talk")
                shortcutRow(ShortcutAction.speakSelection.shortcut.label, "read aloud")
                shortcutRow(ShortcutAction.editSelection.shortcut.label, "edit by voice")
            }
        }
    }

    private func shortcutRow(_ keys: String, _ label: String) -> some View {
        HStack {
            Keycap(text: keys)
            Text(label).font(.system(size: 12.5)).foregroundStyle(theme.inkSoft)
            Spacer()
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Menu {
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
            } label: {
                Text("More")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule(style: .continuous).fill(theme.ink.opacity(0.07)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}

// MARK: - Pieces

struct StatusLook {
    let tint: PlayTint?   // nil = neutral grey
    let symbol: String
    let live: Bool        // breathes and reacts to the microphone
}

/// A friendly status circle: breathes while listening, its ring grows with your voice.
private struct StatusOrb: View {
    @ObservedObject private var theme = Theme.shared
    let look: StatusLook
    let level: Float
    let active: Bool
    @State private var breathe = false

    private var color: Color { look.tint.map { theme.bold($0) } ?? theme.inkSoft }
    private var normalized: Double { max(0, min(1, (Double(level) + 60) / 35)) }

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.14))
                .scaleEffect(look.live ? (breathe ? 1.12 : 0.96) : 1)
            Circle().strokeBorder(color.opacity(look.live ? 0.55 : 0.25), lineWidth: 2.5)
                .scaleEffect(1 + (active ? normalized * 0.2 : 0))
                .animation(.easeOut(duration: 0.1), value: normalized)
            Circle().fill(look.tint.map { theme.soft($0) } ?? theme.ink.opacity(0.08))
                .padding(10)
            Image(systemName: look.symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 64, height: 64)
        .onAppear { startBreathing() }
        .onChange(of: look.live) { _, _ in startBreathing() }
    }

    private func startBreathing() {
        guard look.live, theme.animations, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { breathe = false; return }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
    }
}

struct Keycap: View {
    @ObservedObject private var theme = Theme.shared
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: theme.radius(7), style: .continuous).fill(theme.card))
            .overlay(RoundedRectangle(cornerRadius: theme.radius(7), style: .continuous).strokeBorder(theme.ink.opacity(0.18)))
            .shadow(color: theme.ink.opacity(0.18), radius: 0, y: 1.5)
    }
}

private struct RecentRow: View {
    @ObservedObject private var theme = Theme.shared
    let text: String
    let action: () -> Void
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button {
            action()
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            HStack(spacing: 8) {
                Text(text).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(copied ? theme.bold(.mint) : theme.inkSoft)
                    .contentTransition(.symbolEffect(.replace))
            }
            .font(.system(size: 13))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: theme.radius(11), style: .continuous)
                .fill(theme.ink.opacity(hovering ? 0.10 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(theme.spring, value: copied)
        .help("Click to copy")
    }
}
