import Foundation

/// A request from outside the app: the `saytype://` URL scheme, the `saytype` command-line tool,
/// Raycast and Shortcuts all end up here.
enum AutomationCommand: Equatable {
    enum Switch: String { case on, off, toggle }
    enum Recording: String { case start, stop, toggle }

    case dictation(Switch)
    case record(Recording)
    case speak(String?)
    case editSelection
    case transcribe(URL)
    case meeting(Recording)
    case copyLast
    case settings

    /// `saytype://dictation/toggle`, `saytype://speak?text=Hello`, …
    static func parse(_ url: URL) -> AutomationCommand? {
        guard url.scheme?.lowercased() == "saytype", let host = url.host?.lowercased() else { return nil }
        let action = url.pathComponents.dropFirst().first?.lowercased()
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }

        switch host {
        case "dictation":
            return Switch(rawValue: action ?? "toggle").map(Self.dictation)
        case "record":
            return Recording(rawValue: action ?? "toggle").map(Self.record)
        case "meeting":
            return Recording(rawValue: action ?? "toggle").map(Self.meeting)
        case "speak":
            let text = value("text")?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .speak(text?.isEmpty == false ? text : nil)
        case "edit":
            return .editSelection
        case "transcribe":
            guard let path = value("file"), !path.isEmpty else { return nil }
            return .transcribe(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        case "history":
            return action == "copy-last" ? .copyLast : nil
        case "settings":
            return .settings
        default:
            return nil
        }
    }
}
