import AppKit
import ApplicationServices
import os
import SwiftUI

/// Where the text caret (or, failing that, the focused field) is on screen, in AppKit coordinates.
enum CaretLocator {
    struct Location {
        var rect: CGRect       // caret, or the whole field when the app won't report a caret
        var isCaret: Bool
    }

    static func locate(in element: AXUIElement) -> Location? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        if let caret = caretRect(element) { return Location(rect: toAppKit(caret), isCaret: true) }
        if let field = fieldRect(element) { return Location(rect: toAppKit(field), isCaret: false) }
        return nil
    }

    private static func caretRect(_ element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &selection) else { return nil }
        let field = fieldRect(element)

        func bounds(_ location: Int, _ length: Int) -> CGRect? {
            guard location >= 0 else { return nil }
            var range = CFRange(location: location, length: length)
            guard let value = AXValueCreate(.cfRange, &range) else { return nil }
            var out: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                             value, &out) == .success,
                  let out, CFGetTypeID(out) == AXValueGetTypeID() else { return nil }
            var rect = CGRect.zero
            guard AXValueGetValue(out as! AXValue, .cgRect, &rect), rect.height > 2, rect.height < 400,
                  rect.origin.x.isFinite, rect.origin.y.isFinite else { return nil }
            // Reject rectangles that are nowhere near the field (some apps return junk).
            if let field, !field.insetBy(dx: -60, dy: -60).contains(CGPoint(x: rect.midX, y: rect.midY)) { return nil }
            return rect
        }

        let end = selection.location + selection.length
        // An empty range gives the caret itself in most apps; otherwise use the character before it.
        if let r = bounds(end, 0), r.width < 40 { return CGRect(x: r.minX, y: r.minY, width: 0, height: r.height) }
        if let r = bounds(end - 1, 1) { return CGRect(x: r.maxX, y: r.minY, width: 0, height: r.height) }
        if let r = bounds(end, 1) { return CGRect(x: r.minX, y: r.minY, width: 0, height: r.height) }
        return nil
    }

    private static func fieldRect(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &origin), AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Accessibility uses a top-left origin on the primary display; AppKit uses bottom-left.
    private static func toAppKit(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// A small badge that follows the caret and shows what SayType is really doing, with a live microphone level.
@MainActor
final class CaretIndicator {
    enum Kind: Equatable { case listening, hearing, working, paused, speaking, off, problem }

    private let model = CaretBadgeModel()
    private var panel: NSPanel?
    private var timer: Timer?
    private weak var controller: AppController?
    private let size = NSSize(width: 30, height: 30)

    func start(controller: AppController) {
        self.controller = controller
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        model.onTap = { [weak controller] in controller?.enabled.toggle() }
    }

    private func tick() {
        guard let controller, Pref.defaults.bool(forKey: Pref.showCaretIndicator),
              controller.focus.state.canDictate || controller.manualRecording,
              let element = controller.focus.focusedElement,
              let location = CaretLocator.locate(in: element) else {
            if panel?.isVisible == true { panel?.orderOut(nil) }
            return
        }
        // Only publish real changes; assigning the same value still makes SwiftUI lay everything out again.
        let newKind = kind(for: controller)
        if model.kind != newKind { model.kind = newKind; model.hint = hint(for: newKind) }
        let newLevel = max(0, min(1, (Double(controller.micLevelDB) + 60) / 35))
        if abs(model.level - newLevel) > 0.04 { model.level = newLevel }

        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        let origin = position(for: location)
        if origin != panel.frame.origin {
            Logger(subsystem: "SayType", category: "caret").notice("badge at \(Int(origin.x)),\(Int(origin.y)) caret=\(location.isCaret, privacy: .public) rect=\(Int(location.rect.minX)),\(Int(location.rect.minY)),\(Int(location.rect.width)),\(Int(location.rect.height))")
        }
        panel.setFrameOrigin(origin)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func kind(for c: AppController) -> Kind {
        if c.micStalled { return .problem }
        if c.manualRecording { return .hearing }
        switch c.status {
        case .listening: return .listening
        case .hearing: return .hearing
        case .transcribing, .loading: return .working
        case .speaking: return .speaking
        case .disabled: return .off
        case .idle: return .paused
        case .needsMicPermission, .needsAccessibility, .error: return .problem
        }
    }

    private func hint(for kind: Kind) -> String {
        switch kind {
        case .listening: return "SayType is listening. Click to turn off."
        case .hearing: return "Hearing you…"
        case .working: return "Typing…"
        case .paused: return "SayType is paused right now (other audio playing or not ready)."
        case .speaking: return "Reading aloud"
        case .off: return "SayType is off. Click to turn on."
        case .problem: return "The microphone isn't delivering audio. Open SayType from the menu bar."
        }
    }

    /// Just right of the caret, vertically centred on its line; for a whole field, inside its right edge.
    private func position(for location: CaretLocator.Location) -> NSPoint {
        let r = location.rect
        var origin: NSPoint
        if location.isCaret {
            origin = NSPoint(x: r.maxX + 8, y: r.midY - size.height / 2)
        } else if r.height > 70 {
            origin = NSPoint(x: r.maxX - size.width - 8, y: r.minY + 8)
        } else {
            origin = NSPoint(x: r.maxX - size.width - 8, y: r.midY - size.height / 2)
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: r.midX, y: r.midY)) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            origin.x = min(max(origin.x, frame.minX + 2), frame.maxX - size.width - 2)
            origin.y = min(max(origin.y, frame.minY + 2), frame.maxY - size.height - 2)
        }
        return origin
    }

    private func makePanel() -> NSPanel {
        let p = BadgePanel(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Without this macOS fades/zooms the panel every time it is shown or hidden, which looks like flicker.
        p.animationBehavior = .none
        let host = NSHostingView(rootView: CaretBadge(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        p.contentView = host
        return p
    }
}

/// Never takes focus, so clicking the badge doesn't pull you out of the field you're typing in.
private final class BadgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CaretBadgeModel: ObservableObject {
    @Published var kind: CaretIndicator.Kind = .listening
    @Published var level: Double = 0
    @Published var hint = ""
    var onTap: () -> Void = {}
}

struct CaretBadge: View {
    @ObservedObject var model: CaretBadgeModel
    @ObservedObject private var theme = Theme.shared
    @State private var shown = false

    var body: some View {
        Button(action: model.onTap) {
            ZStack {
                Circle().fill(.regularMaterial)
                Circle().fill(tintColor.opacity(0.22))
                // The ring grows with your voice, so you can see the mic really hears you.
                Circle()
                    .strokeBorder(tintColor.opacity(model.kind == .hearing || model.kind == .listening ? 0.95 : 0.45), lineWidth: 2)
                    .scaleEffect(1 + (model.kind == .hearing ? model.level * 0.2 : 0))
                if model.kind == .working {
                    ProgressView().controlSize(.mini).scaleEffect(0.7).tint(tintColor)
                } else {
                    Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(tintColor)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 24, height: 24)
            .shadow(color: tintColor.opacity(0.3), radius: 3, y: 1)
            .scaleEffect(shown ? 1 : 0.4)
            .opacity(shown ? 1 : 0)
            .frame(width: 30, height: 30)
            .animation(.easeOut(duration: 0.08), value: model.level)
            .animation(theme.spring, value: model.kind)
            .animation(theme.spring, value: shown)
        }
        .buttonStyle(.plain)
        .onAppear { shown = true }
        .help(model.hint)
    }

    private var symbol: String {
        switch model.kind {
        case .listening, .hearing: return "mic.fill"
        case .paused: return "mic"
        case .speaking: return "speaker.wave.2.fill"
        case .off: return "mic.slash.fill"
        case .problem: return "exclamationmark.triangle.fill"
        case .working: return "ellipsis"
        }
    }

    private var tintColor: Color {
        switch model.kind {
        case .listening, .hearing: return theme.bold(.mint)
        case .working, .speaking: return theme.bold(.blue)
        case .paused, .off: return theme.inkSoft
        case .problem: return theme.bold(.peach)
        }
    }
}
