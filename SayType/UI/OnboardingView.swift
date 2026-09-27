import AVFoundation
import SwiftUI

/// First-run setup: explains SayType and walks through the two permissions it needs.
struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome, microphone, accessibility, model, tryIt }

    @EnvironmentObject var controller: AppController
    @State private var step: Step = .welcome
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axTrusted = FocusMonitor.isTrusted
    @State private var askedForAccessibility = false
    @State private var tryText = ""
    let onFinish: () -> Void

    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ProgressDots(count: Step.allCases.count, current: step.rawValue)
                .padding(.top, 20)
            Group {
                switch step {
                case .welcome: welcome
                case .microphone: microphone
                case .accessibility: accessibility
                case .model: model
                case .tryIt: tryIt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .transition(.opacity)
        }
        .frame(width: 560, height: 520)
        .animation(.easeInOut(duration: 0.2), value: step)
        .onReceive(poll) { _ in
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

    private var welcome: some View {
        StepLayout(
            image: Image(nsImage: NSApp.applicationIconImage),
            title: "Welcome to SayType",
            text: "Click into any text field and just talk. When you pause, SayType types what you said. No buttons to hold."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Bullet(symbol: "lock.shield", text: "Runs 100% on your Mac. Your voice never leaves it.")
                Bullet(symbol: "text.cursor", text: "Works in any app: Slack, Mail, your browser, your editor.")
                Bullet(symbol: "character.book.closed", text: "Learns your project names and technical terms.")
            }
            Button("Get Started") { advance() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var microphone: some View {
        StepLayout(
            image: Image(systemName: "mic.circle.fill"),
            title: "Allow the microphone",
            text: "SayType only listens while a text field is focused, and never in password fields. Audio is processed on your Mac and then thrown away."
        ) {
            if micStatus == .denied || micStatus == .restricted {
                Text("Microphone access was turned off. Turn on SayType in System Settings → Privacy & Security → Microphone.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Open Microphone Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button("Allow Microphone") {
                    Task {
                        _ = await AudioCapture.requestPermission()
                        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                        controller.permissionsChanged()
                    }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }

    private var accessibility: some View {
        StepLayout(
            image: Image(systemName: "accessibility"),
            title: "Allow Accessibility",
            text: "macOS asks for this so SayType can tell when a text field is focused and type into it. SayType never reads password fields and never records what's on your screen."
        ) {
            Button(askedForAccessibility ? "Open Accessibility Settings Again" : "Open Accessibility Settings") {
                askedForAccessibility = true
                FocusMonitor.promptForPermission()
                FocusMonitor.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent).controlSize(.large)

            if askedForAccessibility {
                VStack(alignment: .leading, spacing: 6) {
                    Text("In the list, turn on **SayType**.")
                    Text("Don't see it? Click **+** below the list, choose **Applications → SayType**, then turn it on.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for permission…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var model: some View {
        StepLayout(
            image: Image(systemName: "cpu"),
            title: "Setting up the speech model",
            text: "SayType downloads its speech model once (about 630 MB) and optimizes it for your Mac. After that it works offline."
        ) {
            switch controller.status {
            case .loading(let fraction, let message):
                VStack(spacing: 8) {
                    ProgressView(value: fraction).frame(width: 320)
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            case .error(let message):
                Text(message).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Try Again") { Task { await controller.reloadSpeechToText() } }
            default:
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Continue") { advance() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }

    private var tryIt: some View {
        StepLayout(
            image: nil,
            title: "Try it",
            text: "Click in the box and say something, like “SayType turns my voice into text.” Pause, and it's typed."
        ) {
            TextEditor(text: $tryText)
                .font(.body)
                .frame(height: 110)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            Text("\(HotKeys.toggleListening.label) turns dictation on or off  ·  \(HotKeys.speakSelection.label) reads selected text aloud\nSayType lives in your menu bar.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

            Button("Done") { onFinish() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}

// MARK: - Pieces

private struct StepLayout<Content: View>: View {
    let image: Image?
    let title: String
    let text: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            if let image {
                image.resizable().scaledToFit().frame(width: 84, height: 84)
                    .foregroundStyle(.tint)
            }
            Text(title).font(.title.weight(.semibold))
            Text(text).font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            content
            Spacer(minLength: 0)
        }
    }
}

private struct Bullet: View {
    let symbol: String
    let text: String
    var body: some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22) }
    }
}

private struct ProgressDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i <= current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: i == current ? 22 : 8, height: 8)
            }
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
