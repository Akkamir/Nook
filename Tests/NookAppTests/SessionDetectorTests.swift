import XCTest
@testable import Nook

final class SessionDetectorTests: XCTestCase {
    private var tmpRoot: URL!

    override func setUp() {
        super.setUp()
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        tmpRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("NookSessionDetectorTests\(suffix)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpRoot)
        super.tearDown()
    }

    func test_detect_active_counts_counts_multiple_recent_jsonl_sessions_in_same_project() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let projectURL = tmpRoot.appendingPathComponent("Novalis", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try #"{"agent":"Coach"}"#.write(
            to: projectURL.appendingPathComponent(".pixelvillage"),
            atomically: true,
            encoding: .utf8
        )

        let claudeProjectsURL = tmpRoot
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        let claudeProjectURL = claudeProjectsURL
            .appendingPathComponent(claudeProjectDirName(forPath: projectURL.path), isDirectory: true)
        try FileManager.default.createDirectory(at: claudeProjectURL, withIntermediateDirectories: true)

        try writeRecentJSONL(named: "first-session", in: claudeProjectURL, modifiedAt: now)
        try writeRecentJSONL(named: "second-session", in: claudeProjectURL, modifiedAt: now)

        let detector = SessionDetector(
            claudeProjectsURL: claudeProjectsURL,
            now: { now }
        )

        let counts = await detector.detectActiveCounts()

        XCTAssertEqual(counts["Coach"], 2)
    }

    func test_hook_event_maps_cwd_inside_linked_project_to_parent_pixelvillage_agent() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let projectURL = tmpRoot.appendingPathComponent("Novalis", isDirectory: true)
        let nestedURL = projectURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("generated", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try #"{"agent":"Coach"}"#.write(
            to: projectURL.appendingPathComponent(".pixelvillage"),
            atomically: true,
            encoding: .utf8
        )

        let detector = SessionDetector(
            claudeProjectsURL: tmpRoot.appendingPathComponent(".claude/projects", isDirectory: true),
            now: { now }
        )
        let event = ClaudeHookEvent(
            name: "SessionStart",
            sessionId: "nested-session",
            transcriptPath: nil,
            cwd: nestedURL.path,
            source: nil,
            reason: nil,
            notificationType: nil,
            toolName: nil
        )

        let changed = await detector.handleHookEvent(event)
        let counts = await detector.detectActiveCounts()

        XCTAssertTrue(changed)
        XCTAssertEqual(counts["Coach"], 1)
    }

    private func writeRecentJSONL(named name: String, in dir: URL, modifiedAt date: Date) throws {
        let url = dir.appendingPathComponent("\(name).jsonl")
        try #"{"type":"user"}"#.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func claudeProjectDirName(forPath path: String) -> String {
        String(path.map { character in
            guard let scalar = character.unicodeScalars.first else { return "-" }
            let value = scalar.value
            let isASCIIAlphaNumeric = (65...90).contains(value) || (97...122).contains(value) || (48...57).contains(value)
            return isASCIIAlphaNumeric || character == "-" ? character : "-"
        })
    }
}
