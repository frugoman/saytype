import Foundation

/// Settings that apply only while a particular app is in front.
struct AppProfile: Codable, Identifiable, Hashable {
    var bundleID: String
    var name: String
    var tone: ToneStyle = .standard
    /// Seconds of silence that end a sentence; nil uses the general setting.
    var pauseToCommit: Double?
    /// Whisper language code; nil uses the general setting.
    var language: String?
    var stripTrailingPeriod = false
    /// Extra words for this app only, comma separated.
    var extraTerms = ""

    var id: String { bundleID }
}

/// The settings in force for one utterance after the app's profile is applied.
struct EffectiveSettings: Equatable {
    var pauseToCommit: Double
    var language: String?
    var tone: ToneStyle
    var stripTrailingPeriod: Bool
    var extraTerms: String
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [AppProfile] = [] {
        didSet { if loaded { save() } }
    }
    private let file: URL
    private var loaded = false

    init(file: URL = AppPaths.profilesFile) {
        self.file = file
        if let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode([AppProfile].self, from: data) {
            profiles = decoded
        }
        loaded = true
    }

    func profile(for bundleID: String?) -> AppProfile? {
        guard let bundleID else { return nil }
        return profiles.first { $0.bundleID == bundleID }
    }

    func effective(for bundleID: String?, pause: Double, language: String?) -> EffectiveSettings {
        guard let p = profile(for: bundleID) else {
            return EffectiveSettings(pauseToCommit: pause, language: language, tone: .standard, stripTrailingPeriod: false, extraTerms: "")
        }
        return EffectiveSettings(pauseToCommit: p.pauseToCommit ?? pause,
                                 language: p.language.map { $0 == "auto" ? nil : $0 } ?? language,
                                 tone: p.tone, stripTrailingPeriod: p.stripTrailingPeriod, extraTerms: p.extraTerms)
    }

    /// Ready-made profiles for apps people dictate into, offered when the app is installed.
    static let suggestions: [AppProfile] = [
        AppProfile(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", tone: .casual, pauseToCommit: 0.7, stripTrailingPeriod: true),
        AppProfile(bundleID: "com.apple.MobileSMS", name: "Messages", tone: .casual, pauseToCommit: 0.7, stripTrailingPeriod: true),
        AppProfile(bundleID: "com.hnc.Discord", name: "Discord", tone: .casual, pauseToCommit: 0.7, stripTrailingPeriod: true),
        AppProfile(bundleID: "ru.keepcoder.Telegram", name: "Telegram", tone: .casual, pauseToCommit: 0.7, stripTrailingPeriod: true),
        AppProfile(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp", tone: .casual, pauseToCommit: 0.7, stripTrailingPeriod: true),
        AppProfile(bundleID: "com.apple.mail", name: "Mail", tone: .professional, pauseToCommit: 1.0),
        AppProfile(bundleID: "com.microsoft.Outlook", name: "Outlook", tone: .professional, pauseToCommit: 1.0),
        AppProfile(bundleID: "com.apple.Terminal", name: "Terminal", tone: .code, pauseToCommit: 1.0, stripTrailingPeriod: true),
        AppProfile(bundleID: "com.googlecode.iterm2", name: "iTerm", tone: .code, pauseToCommit: 1.0, stripTrailingPeriod: true),
        AppProfile(bundleID: "com.apple.dt.Xcode", name: "Xcode", tone: .code, pauseToCommit: 1.0),
        AppProfile(bundleID: "com.microsoft.VSCode", name: "VS Code", tone: .code, pauseToCommit: 1.0),
        AppProfile(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor", tone: .code, pauseToCommit: 1.0),
        AppProfile(bundleID: "dev.zed.Zed", name: "Zed", tone: .code, pauseToCommit: 1.0),
    ]

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

enum TextPostProcessing {
    /// Removes a final period (but not "?" or "!" or an ellipsis), the way chat messages read.
    static func stripTrailingPeriod(_ text: String) -> String {
        var t = text
        if t.hasSuffix(".") && !t.hasSuffix("..") { t.removeLast() }
        return t
    }
}
