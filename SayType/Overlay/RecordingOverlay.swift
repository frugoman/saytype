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

private struct OverlayView: View {
    @ObservedObject var overlay: RecordingOverlay
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            switch overlay.mode {
            case .recording(let text):
                Circle().fill(.red).frame(width: 10, height: 10)
                    .opacity(pulse ? 0.35 : 1)
                    .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever()) { pulse = true } }
                Text(text)
            case .working(let text):
                ProgressView().controlSize(.small)
                Text(text)
            case .message(let text):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(text)
            }
        }
        .font(.system(size: 14, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(height: 40)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
        .frame(width: 300, height: 44)
    }
}
