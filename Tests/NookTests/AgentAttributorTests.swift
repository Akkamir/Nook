import XCTest
@testable import NookDaemon

final class AgentAttributorTests: XCTestCase {

    var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func test_returns_agent_name_when_config_exists() throws {
        let config = tmpDir.appendingPathComponent(".pixelvillage")
        try """
        { "agent": "Radion" }
        """.write(to: config, atomically: true, encoding: .utf8)

        let name = AgentAttributor.agentName(forProjectPath: tmpDir.path)
        XCTAssertEqual(name, "Radion")
    }

    func test_returns_nil_when_no_config_file() {
        let name = AgentAttributor.agentName(forProjectPath: tmpDir.path)
        XCTAssertNil(name)
    }

    func test_returns_nil_when_config_malformed() throws {
        let config = tmpDir.appendingPathComponent(".pixelvillage")
        try "not json".write(to: config, atomically: true, encoding: .utf8)

        let name = AgentAttributor.agentName(forProjectPath: tmpDir.path)
        XCTAssertNil(name)
    }

    func test_returns_nil_when_agent_key_missing() throws {
        let config = tmpDir.appendingPathComponent(".pixelvillage")
        try """
        { "other": "value" }
        """.write(to: config, atomically: true, encoding: .utf8)

        let name = AgentAttributor.agentName(forProjectPath: tmpDir.path)
        XCTAssertNil(name)
    }
}
