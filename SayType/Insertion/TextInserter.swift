import AppKit
import ApplicationServices
import os

/// Puts text into whatever field has focus.
///
/// Strategy (automatic mode): insert through the Accessibility API and verify the field changed;
/// if the app doesn't support that (common in browsers/Electron), fall back to a clipboard paste
/// that restores the previous clipboard contents afterwards.
@MainActor
final class TextInserter {
    private var lastInsert: (app: String, date: Date)?
    /// Characters the most recent `insert` typed, including a leading space it added.
    private(set) var lastInsertedCount = 0
    private let log = Logger(subsystem: "SayType", category: "insert")

    @discardableResult
    func insert(_ rawText: String, into element: AXUIElement?, appName: String, method: InsertionMethod,
                replacingSelection: Bool = false) -> Bool {
        lastInsertedCount = 0
        var text = rawText
        if !replacingSelection, needsLeadingSpace(before: text, element: element, appName: appName) {
            text = " " + text
        }

        var done = false
        if method != .paste, let element {
            done = insertViaAccessibility(text, element: element)
        }
        if done { log.notice("inserted via accessibility into \(appName, privacy: .public)") }
        if !done && method != .accessibility {
            paste(text)
            log.notice("inserted via paste into \(appName, privacy: .public) (element: \(element != nil, privacy: .public))")
            done = true
        }
        if done { lastInsert = (appName, Date()); lastInsertedCount = text.count }
        return done
    }

    // MARK: - Spacing

    /// After a new line, Enter, select-all or scratch-that, the next dictation starts fresh: no leading space.
    func resetSpacing() { lastInsert = nil }

    private func needsLeadingSpace(before text: String, element: AXUIElement?, appName: String) -> Bool {
        guard let first = text.first, !first.isPunctuation, !first.isWhitespace else { return false }

        if let element, let (value, range) = valueAndSelection(element) {
            guard range.location > 0 else { return false }
            let ns = value as NSString
            guard range.location <= ns.length else { return false }
            let prev = ns.substring(with: NSRange(location: range.location - 1, length: 1))
            return !(prev.first?.isWhitespace ?? true) && prev != "(" && prev != "[" && prev != "\"" && prev != "/"
        }
        // Can't read the field: add a space if we just dictated into the same app.
        if let last = lastInsert, last.app == appName, Date().timeIntervalSince(last.date) < 120 {
            return true
        }
        return false
    }

    private func valueAndSelection(_ element: AXUIElement) -> (String, CFRange)? {
        var valueRef: CFTypeRef?
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) else { return nil }
        return (value, range)
    }

    // MARK: - Accessibility insertion

    private func insertViaAccessibility(_ text: String, element: AXUIElement) -> Bool {
        // Only trust AX insertion when we can verify it; some apps report success and do nothing.
        guard let (before, _) = valueAndSelection(element) else { return false }
        let err = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        guard err == .success else { return false }
        guard let (after, _) = valueAndSelection(element) else { return false }
        return after != before
    }

    // MARK: - Paste fallback

    /// The user's clipboard, saved before our first paste and not yet put back. Several pastes in a row
    /// (text, new line, text) share it, so the user's own clipboard is what comes back at the end.
    private var pendingRestore: (saved: [[NSPasteboard.PasteboardType: Data]], work: DispatchWorkItem)?

    private func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]]
        if let pending = pendingRestore {
            pending.work.cancel()
            saved = pending.saved
        } else {
            saved = Self.snapshot(pb)
        }

        pb.clearContents()
        pb.setString(text, forType: .string)
        // Tell clipboard managers not to record this.
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let changeCount = pb.changeCount

        Self.postKey(9, flags: .maskCommand) // ⌘V

        let work = DispatchWorkItem { [weak self] in
            self?.pendingRestore = nil
            // Only restore if nobody else changed the clipboard in the meantime.
            guard pb.changeCount == changeCount else { return }
            Self.restore(saved, to: pb)
        }
        pendingRestore = (saved, work)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private static func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        pb.pasteboardItems?.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let d = item.data(forType: type) { dict[type] = d } }
            return dict
        } ?? []
    }

    private static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pb: NSPasteboard) {
        pb.clearContents()
        let items = saved.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }

    static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Reads the user's current selection (for "read selection aloud").
    static func selectedText() async -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID(),
           let text = FocusMonitor.string(focused as! AXUIElement, kAXSelectedTextAttribute),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        // Fallback: copy the selection and read the clipboard, then restore it.
        // Saves every item and type (images, files, rich text), not just plain text.
        let pb = NSPasteboard.general
        let previous = snapshot(pb)
        let before = pb.changeCount
        postKey(8, flags: .maskCommand) // ⌘C
        try? await Task.sleep(for: .milliseconds(200))
        guard pb.changeCount != before else { return nil }
        let copied = pb.string(forType: .string)
        restore(previous, to: pb)
        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return copied
    }
}
