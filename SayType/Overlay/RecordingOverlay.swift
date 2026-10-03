import AppKit
import SwiftUI

/// A small floating pill that shows what SayType is doing while you hold the shortcut or edit by voice.
@MainActor
final class RecordingOverlay: ObservableObject {
    static let shared = RecordingOverlay()

    enum Mode: Equatable { case recording(String), working(String), message(String) }

    @Published private(set) var mode: Mode = .message("")
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ mode: Mode, hideAfter: TimeInterval? = nil) {
        guard Pref.defaults.bool(forKey: Pref.showOverlay) else { return }
        self.mode = mode
        hideWork?.cancel()
        if panel == nil { panel = makePanel() }
        position()
        panel?.orderFrontRegardless()
        if let hideAfter {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + hideAfter, execute: work)
        }
    }

    /// Sets the mode without showing the panel (used to render screenshots).
    func preview(_ mode: Mode) { self.mode = mode }

    func hide() {
        hideWork?.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 44),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: OverlayView(overlay: self))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 44)
        p.contentView = host
        return p
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 56))
    }
}

struct OverlayView: View {
    @ObservedObject var overlay: RecordingOverlay
    @ObservedObject private var theme = Theme.shared
    @State private var pulse = false
    @State private var shown = false

    private var tint: PlayTint {
        switch overlay.mode {
        case .recording: return .pink
        case .working: return .blue
        case .message: return .mint
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            switch overlay.mode {
            case .recording(let text):
                ZStack {
                    Circle().fill(theme.bold(.pink).opacity(0.35)).frame(width: 12, height: 12)
                        .scaleEffect(pulse ? 2.1 : 1).opacity(pulse ? 0 : 1)
                    Circle().fill(theme.bold(.pink)).frame(width: 12, height: 12)
                }
                .frame(width: 20, height: 20)
                .onAppear {
                    guard theme.animations, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                    withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { pulse = true }
                }
                Text(text)
            case .working(let text):
                ProgressView().controlSize(.small).tint(theme.bold(.blue))
                Text(text)
            case .message(let text):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.bold(.mint))
                    .symbolEffect(.bounce, value: overlay.mode)
                Text(text)
            }
        }
        .font(.system(size: 14, weight: .semibold, design: theme.font))
        .foregroundStyle(theme.ink)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(height: 40)
        .background(Capsule().fill(.regularMaterial))
        .background(Capsule().fill(theme.soft(tint).opacity(0.8)))
        .overlay(Capsule().strokeBorder(theme.bold(tint).opacity(0.35), lineWidth: 1.5))
        .shadow(color: theme.shadow, radius: 8, y: 3)
        .scaleEffect(shown ? 1 : 0.8)
        .opacity(shown ? 1 : 0)
        .animation(theme.spring, value: overlay.mode)
        .animation(theme.spring, value: shown)
        .onAppear { shown = true }
        .frame(width: 300, height: 44)
    }
}
