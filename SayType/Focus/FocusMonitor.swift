import AppKit
import ApplicationServices
import os

/// What currently has keyboard focus, as far as dictation is concerned.
enum FocusState: Equatable {
    case none                 // nothing typeable
    case editable(app: String)
    case secure               // password field: never listen
    case noPermission

    var canDictate: Bool { if case .editable = self { return true } else { return false } }
}

/// Polls the Accessibility API to learn whether the focused UI element accepts text.
@MainActor
final class FocusMonitor: ObservableObject {
    @Published private(set) var state: FocusState = .none
    @Published private(set) var frontAppName: String = ""
    @Published private(set) var frontBundleID: String?
    private(set) var focusedElement: AXUIElement?

    private var timer: Timer?
    private let systemWide = AXUIElementCreateSystemWide()
    private var appsWithAccessibilityEnabled = Set<pid_t>()
    private let log = Logger(subsystem: "SayType", category: "focus")
    private var lastError: AXError = .success

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func start() {
        AXUIElementSetMessagingTimeout(systemWide, 0.25) // never hang on an unresponsive app
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard FocusMonitor.isTrusted else {
            update(.noPermission, element: nil)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            update(.none, element: nil)
            return
        }
        frontAppName = app.localizedName ?? ""
        frontBundleID = app.bundleIdentifier
        let pid = app.processIdentifier
        enableAccessibilityTree(for: pid)

        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        if err != lastError {
            lastError = err
            log.notice("focus: AX focused element error \(err.rawValue, privacy: .public) trusted=\(FocusMonitor.isTrusted, privacy: .public)")
        }
        guard err == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            // Some apps don't expose focus; honour the user's "always listen in this app" list.
            if isAlwaysListenApp(app) {
                update(.editable(app: frontAppName), element: nil)
            } else {
                update(.none, element: nil)
            }
            return
        }
        let element = value as! AXUIElement

        if Self.isSecure(element) {
            update(.secure, element: nil)
        } else if Self.isEditable(element) || isAlwaysListenApp(app) {
            update(.editable(app: frontAppName), element: element)
        } else {
            update(.none, element: nil)
        }
    }

    private func update(_ newState: FocusState, element: AXUIElement?) {
        focusedElement = element
        if state != newState {
            let role = element.flatMap { Self.string($0, kAXRoleAttribute) } ?? "-"
            log.notice("focus: \(String(describing: newState), privacy: .public) front=\(self.frontAppName, privacy: .public) role=\(role, privacy: .public) pid=\(element.map(Self.pid) ?? 0, privacy: .public)")
            state = newState
        }
    }

    static func pid(_ element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    private func isAlwaysListenApp(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        let list = Pref.defaults.stringArray(forKey: Pref.alwaysListenApps) ?? []
        return list.contains(id)
    }

    /// Electron and Chromium apps only build their accessibility tree when asked.
    private func enableAccessibilityTree(for pid: pid_t) {
        guard !appsWithAccessibilityEnabled.contains(pid) else { return }
        appsWithAccessibilityEnabled.insert(pid)
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // MARK: - Element inspection

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func isSecure(_ element: AXUIElement) -> Bool {
        let role = string(element, kAXRoleAttribute) ?? ""
        let subrole = string(element, kAXSubroleAttribute) ?? ""
        return role == "AXSecureTextField" || subrole == "AXSecureTextField"
    }

    static func isEditable(_ element: AXUIElement) -> Bool {
        let role = string(element, kAXRoleAttribute) ?? ""
        let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        if editableRoles.contains(role) { return true }

        // Web content: contenteditable regions report an editable ancestor.
        var ancestor: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXEditableAncestor" as CFString, &ancestor) == .success,
           ancestor != nil {
            return true
        }

        // Anything whose value can be set is typeable.
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue, role != "AXSlider", role != "AXCheckBox", role != "AXScrollBar" {
            return true
        }
        return false
    }
}
