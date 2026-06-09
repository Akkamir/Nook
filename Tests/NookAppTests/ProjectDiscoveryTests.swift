import XCTest
@testable import Nook

final class ProjectDiscoveryTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectDiscoveryTests\(suffix)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_decode_claude_project_directory_name_to_real_path() {
        XCTAssertEqual(
            ProjectDiscovery.decodeProjectPath(fromClaudeDirectoryName: "-Users-mchau-Desktop-Code-Nook"),
            "/Users/mchau/Desktop/Code/Nook"
        )
        XCTAssertNil(ProjectDiscovery.decodeProjectPath(fromClaudeDirectoryName: "not-encoded"))
    }

    func test_discover_filters_missing_projects_and_sorts_by_recent_activity() throws {
        let projectsURL = tempDir.appendingPathComponent(".claude/projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)

        let realA = tempDir.appendingPathComponent("RealA", isDirectory: true)
        let realB = tempDir.appendingPathComponent("RealB", isDirectory: true)
        try FileManager.default.createDirectory(at: realA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: realB, withIntermediateDirectories: true)

        let claudeA = projectsURL.appendingPathComponent(ProjectDiscovery.encodeProjectPathForTests(realA.path), isDirectory: true)
        let claudeB = projectsURL.appendingPathComponent(ProjectDiscovery.encodeProjectPathForTests(realB.path), isDirectory: true)
        let missing = projectsURL.appendingPathComponent("-tmp-this-path-does-not-exist", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeB, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)

        try "{}".write(to: claudeA.appendingPathComponent("old.jsonl"), atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 0.02)
        try "{}".write(to: claudeB.appendingPathComponent("new.jsonl"), atomically: true, encoding: .utf8)

        let discovered = ProjectDiscovery(projectsURL: projectsURL).discover()

        XCTAssertEqual(discovered.map(\.path), [realB.path, realA.path])
        XCTAssertEqual(discovered[0].displayName, "RealB")
        XCTAssertGreaterThan(discovered[0].lastActivityAt, discovered[1].lastActivityAt)
    }
}
