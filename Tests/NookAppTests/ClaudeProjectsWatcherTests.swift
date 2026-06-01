import XCTest
@testable import Nook

@MainActor
final class ClaudeProjectsWatcherTests: XCTestCase {
    private var tmpRoot: URL!

    override func setUp() {
        super.setUp()
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        tmpRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("NookClaudeProjectsWatcherTests\(suffix)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpRoot)
        super.tearDown()
    }

    func test_watcher_notifies_when_jsonl_changes_inside_existing_project_dir() throws {
        let projectsURL = tmpRoot
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        let projectURL = projectsURL.appendingPathComponent("-tmp-Novalis", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let expectation = expectation(description: "Claude project JSONL change")
        let watcher = ClaudeProjectsWatcher(projectsURL: projectsURL, debounceInterval: 0.05)
        watcher.onChange = {
            expectation.fulfill()
        }

        watcher.start()
        defer { watcher.stop() }

        let jsonlURL = projectURL.appendingPathComponent("session.jsonl")
        try #"{"type":"user"}"#.write(to: jsonlURL, atomically: true, encoding: .utf8)

        wait(for: [expectation], timeout: 2.0)
    }

    func test_watcher_notifies_when_existing_jsonl_is_appended() throws {
        let projectsURL = tmpRoot
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        let projectURL = projectsURL.appendingPathComponent("-tmp-Novalis", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let jsonlURL = projectURL.appendingPathComponent("session.jsonl")
        try #"{"type":"user"}"#
            .appending("\n")
            .write(to: jsonlURL, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "Claude project JSONL append")
        let watcher = ClaudeProjectsWatcher(projectsURL: projectsURL, debounceInterval: 0.05)
        watcher.onChange = {
            expectation.fulfill()
        }

        watcher.start()
        defer { watcher.stop() }

        let handle = try FileHandle(forWritingTo: jsonlURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"type":"assistant"}"#.utf8))
        try handle.close()

        wait(for: [expectation], timeout: 2.0)
    }
}
