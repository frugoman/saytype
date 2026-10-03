import Foundation

/// Lets you call the command-line tool anything you like ("alfred toggle" instead of "saytype toggle")
/// by linking the bundled script under your chosen name.
enum CommandAlias {
    static let defaultName = "saytype"

    enum AliasError: LocalizedError {
        case invalid(String)
        case taken(String)
        case noWritableFolder
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let why): return why
            case .taken(let path): return "There's already a different command at \(path). Pick another name."
            case .noWritableFolder: return "Couldn't find a folder to put the command in."
            case .failed(let why): return "Couldn't install the command: \(why)"
            }
        }
    }

    struct Installed: Equatable {
        var url: URL
        /// False when the folder usually isn't on your shell's PATH and you'll need to add it.
        var onPath: Bool
        var alreadyThere: Bool
    }

    /// Turns what you typed into a usable command name: lower case, spaces and odd characters become hyphens.
    /// "Hey Alfred!" becomes "hey-alfred".
    static func sanitize(_ input: String) -> String {
        var out = ""
        for scalar in input.lowercased().unicodeScalars {
            if (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57) || scalar == "_" {
                out.unicodeScalars.append(scalar)
            } else if scalar == "-" || scalar == " " || scalar == "." {
                if !out.hasSuffix("-") { out += "-" }
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Why a name can't be used, or nil when it's fine.
    static func problem(with name: String) -> String? {
        if name.isEmpty { return "Type a name." }
        if name.count > 32 { return "Keep it under 32 characters." }
        if name.first!.isNumber { return "Start with a letter." }
        return nil
    }

    /// Folders the command can live in, best first. `/opt/homebrew/bin` and `/usr/local/bin` are already on the PATH.
    static func candidateFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                 fileManager fm: FileManager = .default) -> [URL] {
        var folders: [URL] = []
        for path in ["/opt/homebrew/bin", "/usr/local/bin"] {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue, fm.isWritableFile(atPath: path) {
                folders.append(URL(fileURLWithPath: path))
            }
        }
        folders.append(home.appendingPathComponent(".local/bin"))
        return folders
    }

    private static let systemFolders = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    /// Creates (or refreshes) the link. Never overwrites a command that isn't ours.
    @discardableResult
    static func install(name: String, script: URL, folders: [URL], fileManager fm: FileManager = .default) throws -> Installed {
        if let why = problem(with: name) { throw AliasError.invalid(why) }
        for folder in systemFolders where fm.fileExists(atPath: folder + "/" + name) {
            throw AliasError.taken(folder + "/" + name)
        }
        guard let folder = folders.first else { throw AliasError.noWritableFolder }
        // A same-named command in another PATH folder would shadow or be shadowed; refuse rather than surprise.
        for other in folders.dropFirst() + [URL(fileURLWithPath: "/opt/homebrew/bin"), URL(fileURLWithPath: "/usr/local/bin")] {
            let candidate = other.appendingPathComponent(name)
            if candidate.path != folder.appendingPathComponent(name).path, fm.fileExists(atPath: candidate.path),
               !isLink(candidate, to: script, fileManager: fm), !isOurs(candidate, fileManager: fm) {
                throw AliasError.taken(candidate.path)
            }
        }

        let link = folder.appendingPathComponent(name)
        var alreadyThere = false
        if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil || fm.fileExists(atPath: link.path) {
            guard isLink(link, to: script, fileManager: fm) || isOurs(link, fileManager: fm) else { throw AliasError.taken(link.path) }
            if isLink(link, to: script, fileManager: fm) { alreadyThere = true } else { try? fm.removeItem(at: link) }
        }
        if !alreadyThere {
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try? fm.removeItem(at: link)
                try fm.createSymbolicLink(at: link, withDestinationURL: script)
            } catch {
                throw AliasError.failed(error.localizedDescription)
            }
        }
        let onPath = folder.path == "/opt/homebrew/bin" || folder.path == "/usr/local/bin"
        return Installed(url: link, onPath: onPath, alreadyThere: alreadyThere)
    }

    /// Removes a link we made earlier. Leaves anything else alone.
    static func remove(name: String, folders: [URL], script: URL, fileManager fm: FileManager = .default) {
        for folder in folders {
            let link = folder.appendingPathComponent(name)
            if isOurs(link, fileManager: fm) { try? fm.removeItem(at: link) }
        }
    }

    /// A symlink whose target is the SayType script, in this or any earlier install location.
    private static func isOurs(_ url: URL, fileManager fm: FileManager) -> Bool {
        guard let target = try? fm.destinationOfSymbolicLink(atPath: url.path) else { return false }
        return target.hasSuffix("/Contents/Resources/CLI/saytype")
    }

    private static func isLink(_ url: URL, to script: URL, fileManager fm: FileManager) -> Bool {
        (try? fm.destinationOfSymbolicLink(atPath: url.path)) == script.path
    }
}
