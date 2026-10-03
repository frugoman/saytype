import XCTest

final class CommandAliasTests: XCTestCase {
    private var dir: URL!
    private var script: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("alias-\(UUID())")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let res = dir.appendingPathComponent("SayType.app/Contents/Resources/CLI")
        try fm.createDirectory(at: res, withIntermediateDirectories: true)
        script = res.appendingPathComponent("saytype")
        try "#!/bin/bash\n".write(to: script, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    func testSanitize() {
        XCTAssertEqual(CommandAlias.sanitize("Alfred"), "alfred")
        XCTAssertEqual(CommandAlias.sanitize("Hey Alfred!"), "hey-alfred")
        XCTAssertEqual(CommandAlias.sanitize("  my  cool__tool  "), "my-cool__tool")
        XCTAssertEqual(CommandAlias.sanitize("é/ü"), "")
        XCTAssertEqual(CommandAlias.sanitize("---x---"), "x")
    }

    func testProblems() {
        XCTAssertNotNil(CommandAlias.problem(with: ""))
        XCTAssertNotNil(CommandAlias.problem(with: "9lives"))
        XCTAssertNotNil(CommandAlias.problem(with: String(repeating: "a", count: 40)))
        XCTAssertNil(CommandAlias.problem(with: "alfred"))
    }

    func testInstallCreatesLinkAndIsIdempotent() throws {
        let bin = dir.appendingPathComponent("bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let first = try CommandAlias.install(name: "alfredtest", script: script, folders: [bin])
        XCTAssertFalse(first.alreadyThere)
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: first.url.path), script.path)
        let second = try CommandAlias.install(name: "alfredtest", script: script, folders: [bin])
        XCTAssertTrue(second.alreadyThere)
    }

    func testNeverOverwritesSomeoneElsesCommand() throws {
        let bin = dir.appendingPathComponent("bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try "echo hi".write(to: bin.appendingPathComponent("mine"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try CommandAlias.install(name: "mine", script: script, folders: [bin]))
        XCTAssertEqual(try String(contentsOf: bin.appendingPathComponent("mine")), "echo hi")
    }

    func testRefusesSystemCommandNames() {
        XCTAssertThrowsError(try CommandAlias.install(name: "ls", script: script, folders: [dir]))
    }

    func testRemoveOnlyRemovesOurLinks() throws {
        let bin = dir.appendingPathComponent("bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try CommandAlias.install(name: "alfredtest", script: script, folders: [bin])
        try "x".write(to: bin.appendingPathComponent("other"), atomically: true, encoding: .utf8)
        CommandAlias.remove(name: "alfredtest", folders: [bin], script: script)
        CommandAlias.remove(name: "other", folders: [bin], script: script)
        XCTAssertFalse(fm.fileExists(atPath: bin.appendingPathComponent("alfredtest").path))
        XCTAssertTrue(fm.fileExists(atPath: bin.appendingPathComponent("other").path))
    }
}
