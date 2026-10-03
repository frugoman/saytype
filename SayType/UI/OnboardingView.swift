import AVFoundation
import SwiftUI

/// First-run setup: explains SayType and walks through the two permissions it needs.
struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome, microphone, accessibility, model, tryIt }

    @EnvironmentObject var controller: AppController
    @ObservedObject private var theme = Theme.shared
    @State private var step: Step
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axTrusted = FocusMonitor.isTrusted
    @State private var askedForAccessibility = false
    @State private var tryText = ""
    let onFinish: () -> Void

    init(initialStep: Step = .welcome, onFinish: @escaping () -> Void) {
        _step = State(initialValue: initialStep)
        self.onFinish = onFinish
    }

    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            PlayBackdrop()
            VStack(spacing: 0) {
                ProgressDots(count: Step.allCases.count, current: step.rawValue)
                    .padding(.top, theme.space(26))
                ZStack {
                    switch step {
                    case .welcome: welcome
                    case .microphone: microphone
                    case .accessibility: accessibility
                    case .model: model
                    case .tryIt: tryIt
                    }
                }
                .id(step)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, theme.space(44))
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .clipped()
            if step == .tryIt { ConfettiBurst().allowsHitTesting(false) }
        }
        .frame(width: 560, height: 540)
        .playStyle()
        .playAnimation(value: step)
        .onReceive(poll) { _ in
            if UISnapshot.active { return }
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            axTrusted = FocusMonitor.isTrusted
            if step == .microphone, micStatus == .authorized { advance() }
            if step == .accessibility, axTrusted { advance() }
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return onFinish() }
        // Skip steps that are already done.
        if next == .microphone, micStatus == .authorized { step = next; return advance() }
        if next == .accessibility, axTrusted { step = next; return advance() }
        if next == .model, controller.isModelReady { step = next; return advance() }
        step = next
    }

    // MARK: Steps

    private func label(_ text: String, _ symbol: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(text)
            if let symbol { Image(systemName: symbol) }
        }
        .font(.system(size: 15, weight: .bold))
        .padding(.horizontal, 14).padding(.vertical, 4)
    }

    private var welcome: some View {
        StepLayout(
            icon: .app,
            tint: .pink,
            title: "Welcome to SayType",
            text: "Click into any text field and just talk. When you pause, SayType types what you said. No buttons to hold."
        ) {
            VStack(alignment: .leading, spacing: theme.space(8)) {
                Bullet(symbol: "lock.shield.fill", tint: .mint, text: "Runs 100% on your Mac. Your voice never leaves it.")
                Bullet(symbol: "text.cursor", tint: .blue, text: "Works in any app: Slack, Mail, your browser, your editor.")
                Bullet(symbol: "character.book.closed.fill", tint: .butter, text: "Learns your project names and technical terms.")
            }
            Button { advance() } label: { label("Get Started", "arrow.right") }
                .buttonStyle(.playPrimary)
        }
    }

    private var microphone: some View {
        StepLayout(
            icon: .symbol("mic.fill"),
            tint: .blue,
            title: "Allow the microphone",
            text: "SayType only listens while a text field is focused, and never in password fields. Audio is processed on your Mac and then thrown away."
        ) {
            PermissionRow(title: "Microphone", symbol: "mic.fill", tint: .blue, granted: micStatus == .authorized)
            if micStatus == .denied || micStatus == .restricted {
                Text("Microphone access was turned off. Turn on SayType in System Settings → Privacy & Security → Microphone.")
                    .font(.callout).foregroundStyle(theme.inkSoft).multilineTextAlignment(.center)
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                } label: { label("Open Microphone Settings") }
                .buttonStyle(.playPrimary)
            } else {
                Button {
                    Task {
                        _ = await AudioCapture.requestPermission()
                        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                        controller.permissionsChanged()
                    }
                } label: { label("Allow Microphone") }
                .buttonStyle(.playPrimary)
            }
        }
    }

    private var accessibility: some View {
        StepLayout(
            icon: .symbol("accessibility"),
            tint: .lavender,
            title: "Allow Accessibility",
            text: "macOS asks for this so SayType can tell when a text field is focused and type into it. SayType never reads password fields and never records what's on your screen."
        ) {
            PermissionRow(title: "Accessibility", symbol: "accessibility", tint: .lavender, granted: axTrusted)
            Button {
                askedForAccessibility = true
                FocusMonitor.promptForPermission()
                FocusMonitor.openAccessibilitySettings()
            } label: { label(askedForAccessibility ? "Open Accessibility Settings Again" : "Open Accessibility Settings") }
            .buttonStyle(.playPrimary)

            if askedForAccessibility {
                VStack(alignment: .leading, spacing: 6) {
                    Text("In the list, turn on **SayType**.")
                    Text("Don't see it? Click **+** below the list, choose **Applications → SayType**, then turn it on.")
                }
                .font(.callout)
                .foregroundStyle(theme.inkSoft)
                .padding(theme.space(12))
                .background(RoundedRectangle(cornerRadius: theme.radius(14), style: .continuous).fill(theme.soft(.lavender).opacity(0.7)))
                .transition(.scale(scale: 0.95).combined(with: .opacity))

                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for permission…").font(.caption).foregroundStyle(theme.inkSoft)
                }
            }
        }
        .playAnimation(value: askedForAccessibility)
    }

    private var model: some View {
        StepLayout(
            icon: .symbol("cpu"),
            tint: .mint,
            title: "Setting up the speech model",
            text: "SayType downloads its speech model once (about 630 MB) and optimizes it for your Mac. After that it works offline."
        ) {
            switch controller.status {
            case .loading(let fraction, let message):
                VStack(spacing: 8) {
                    ProgressView(value: fraction).tint(theme.bold(.mint)).frame(width: 320)
                    Text(message).font(.caption).foregroundStyle(theme.inkSoft)
                }
            case .error(let message):
                Text(message).font(.callout).foregroundStyle(theme.bold(.peach)).multilineTextAlignment(.center)
                Button("Try Again") { Task { await controller.reloadSpeechToText() } }
            default:
                PermissionRow(title: "Speech model ready", symbol: "cpu", tint: .mint, granted: true)
                Button { advance() } label: { label("Continue", "arrow.right") }
                    .buttonStyle(.playPrimary)
            }
        }
    }

    private var tryIt: some View {
        StepLayout(
            icon: .symbol("party.popper.fill"),
            tint: .butter,
            title: "Try it",
            text: "Click in the box and say something, like “SayType turns my voice into text.” Pause, and it's typed."
        ) {
            TextEditor(text: $tryText)
                .font(.system(size: 15))
                .frame(height: 100)
                .scrollContentBackground(.hidden)
                .padding(theme.space(10))
                .background(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous).fill(theme.card))
                .overlay(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous).strokeBorder(theme.accent.opacity(0.5), lineWidth: 1.5))
                .shadow(color: theme.shadow, radius: 10, y: 4)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Keycap(text: ShortcutAction.toggleDictation.shortcut.label); Text("on / off")
                    Keycap(text: ShortcutAction.pushToTalk.shortcut.label); Text("push to talk")
                    Keycap(text: ShortcutAction.speakSelection.shortcut.label); Text("read aloud")
                }
                Text("SayType lives in your menu bar.")
            }
            .font(.system(size: 12)).foregroundStyle(theme.inkSoft)

            Button { onFinish() } label: { label("Done", "checkmark") }
                .buttonStyle(.playPrimary)
        }
    }
}

// MARK: - Pieces

private enum StepIcon { case app, symbol(String) }

private struct StepLayout<Content: View>: View {
    @ObservedObject private var theme = Theme.shared
    let icon: StepIcon
    let tint: PlayTint
    let title: String
    let text: String
    @ViewBuilder let content: Content
    @State private var float = false

    init(icon: StepIcon, tint: PlayTint, title: String, text: String, @ViewBuilder content: () -> Content) {
        self.icon = icon; self.tint = tint; self.title = title; self.text = text; self.content = content()
    }

    var body: some View {
        VStack(spacing: theme.space(16)) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(theme.soft(tint)).frame(width: 112, height: 112)
                Circle().strokeBorder(theme.bold(tint).opacity(0.25), lineWidth: 2).frame(width: 112, height: 112)
                switch icon {
                case .app:
                    Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 76, height: 76)
                case .symbol(let name):
                    Image(systemName: name).font(.system(size: 46, weight: .bold)).foregroundStyle(theme.bold(tint))
                }
            }
            .shadow(color: theme.bold(tint).opacity(0.3), radius: 18, y: 8)
            .offset(y: float ? -7 : 5)
            .rotationEffect(.degrees(float ? 2.5 : -2.5))
            .onAppear {
                guard theme.animations, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { float = true }
            }

            Text(title).font(.system(size: 28, weight: .heavy)).multilineTextAlignment(.center)
            Text(text).font(.system(size: 15)).foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            content
            Spacer(minLength: 0)
        }
    }
}

private struct Bullet: View {
    @ObservedObject private var theme = Theme.shared
    let symbol: String
    let tint: PlayTint
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(theme.bold(tint))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: theme.radius(10), style: .continuous).fill(theme.soft(tint)))
            Text(text).font(.system(size: 14))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous).strokeBorder(theme.cardStroke))
    }
}

/// A permission line whose check mark pops in when it's granted.
private struct PermissionRow: View {
    @ObservedObject private var theme = Theme.shared
    let title: String, symbol: String
    let tint: PlayTint
    let granted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(theme.bold(tint))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: theme.radius(10), style: .continuous).fill(theme.soft(tint)))
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 16)
            ZStack {
                if granted {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22))
                        .foregroundStyle(theme.bold(.mint))
                        .symbolEffect(.bounce, value: granted)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                } else {
                    Text("Not yet").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.inkSoft)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: theme.radius(18), style: .continuous).fill(granted ? theme.soft(.mint).opacity(0.8) : theme.card))
        .overlay(RoundedRectangle(cornerRadius: theme.radius(18), style: .continuous).strokeBorder(theme.cardStroke))
        .animation(theme.spring, value: granted)
    }
}

/// Progress dots: the current one stretches into a pill.
private struct ProgressDots: View {
    @ObservedObject private var theme = Theme.shared
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i <= current ? theme.accent : theme.ink.opacity(0.15))
                    .frame(width: i == current ? 28 : 9, height: 9)
            }
        }
        .animation(theme.spring, value: current)
    }
}

/// A burst of pastel shapes that flies out and falls away. Plays once.
private struct ConfettiBurst: View {
    @ObservedObject private var theme = Theme.shared
    @State private var go = false

    private struct Piece { let angle: Double, distance: CGFloat, size: CGFloat, spin: Double, tint: PlayTint, kind: Int }
    private static let pieces: [Piece] = (0..<28).map { i in
        let f = Double(i)
        return Piece(angle: f * 0.2243 * .pi + sin(f * 3.1) * 0.3, distance: 130 + CGFloat((i * 37) % 120),
                     size: 9 + CGFloat((i * 13) % 9), spin: 90 + Double((i * 53) % 270),
                     tint: PlayTint.allCases[i % PlayTint.allCases.count], kind: i % 3)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(Self.pieces.enumerated()), id: \.offset) { _, p in
                    shape(p)
                        .frame(width: p.size, height: p.size)
                        .rotationEffect(.degrees(go ? p.spin : 0))
                        .offset(x: go ? CGFloat(cos(p.angle)) * p.distance : 0,
                                y: go ? CGFloat(sin(p.angle)) * p.distance + 60 : 0)
                        .scaleEffect(go ? 1 : 0.2)
                        .opacity(go ? 0 : 1)
                        .animation(.easeOut(duration: 1.6), value: go)
                }
            }
            .position(x: geo.size.width / 2, y: geo.size.height * 0.34)
        }
        .onAppear {
            guard theme.animations, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, !UISnapshot.active else { return }
            go = true
        }
    }

    @ViewBuilder private func shape(_ p: Piece) -> some View {
        let color = theme.bold(p.tint)
        switch p.kind {
        case 0: Circle().fill(color)
        case 1: RoundedRectangle(cornerRadius: 3).fill(color)
        default: Capsule().strokeBorder(color, lineWidth: 3)
        }
    }
}

/// Hosts the onboarding view in a normal window (SayType is otherwise menu-bar only).
@MainActor
final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private var window: NSWindow?

    static var isComplete: Bool {
        get { Pref.defaults.bool(forKey: "onboardingComplete") }
        set { Pref.defaults.set(newValue, forKey: "onboardingComplete") }
    }

    func show() {
        if window == nil {
            let view = OnboardingView { [weak self] in
                OnboardingWindow.isComplete = true
                self?.window?.close()
            }
            .environmentObject(AppController.shared)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "SayType Setup"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
