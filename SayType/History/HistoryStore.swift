import Foundation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    var app: String
}

/// Everything SayType typed, newest first. Text only (never audio), stored on this Mac, and optional.
@MainActor
final class HistoryStore: ObservableObject {
    static let maxEntries = 1000

    @Published private(set) var entries: [HistoryEntry] = []
    private let file: URL
    private let lastFile: URL?

    init(file: URL = AppPaths.historyFile, lastTranscriptFile: URL? = AppPaths.lastTranscriptFile) {
        self.file = file
        self.lastFile = lastTranscriptFile
        if let data = try? Data(contentsOf: file) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
        }
    }

    var isEnabled: Bool { Pref.defaults.bool(forKey: Pref.historyEnabled) }

    func add(_ text: String, app: String, date: Date = Date()) {
        guard isEnabled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        entries.insert(HistoryEntry(date: date, text: text, app: app), at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        save()
        if let lastFile { try? text.write(to: lastFile, atomically: true, encoding: .utf8) }
    }

    func remove(_ id: HistoryEntry.ID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
        if let lastFile { try? FileManager.default.removeItem(at: lastFile) }
    }

    var last: HistoryEntry? { entries.first }

    func search(_ query: String) -> [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(q) || $0.app.localizedCaseInsensitiveContains(q) }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
