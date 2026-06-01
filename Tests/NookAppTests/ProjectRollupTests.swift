import XCTest
@testable import Nook

final class ProjectRollupTests: XCTestCase {
    private func session(_ id: String, project: String, path: String, tokens: Int, at: String) -> SessionRecord {
        SessionRecord(sessionId: id, project: project, projectPath: path, agentName: "Radion",
                      startedAt: iso(at), lastActivityAt: iso(at), inputTokens: tokens, outputTokens: 0, totalBits: 0)
    }
    private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func test_groups_by_project_path_and_sorts_by_tokens_desc() {
        let sessions = [
            session("a", project: "Nook", path: "/n", tokens: 100, at: "2026-06-01T10:00:00Z"),
            session("b", project: "Radion", path: "/r", tokens: 500, at: "2026-06-02T10:00:00Z"),
            session("c", project: "Nook", path: "/n", tokens: 50, at: "2026-06-03T10:00:00Z"),
        ]
        let rollups = ProjectRollup.forAgent(sessions)
        XCTAssertEqual(rollups.map(\.project), ["Radion", "Nook"])
        XCTAssertEqual(rollups[1].totalTokens, 150)
        XCTAssertEqual(rollups[1].sessionCount, 2)
        XCTAssertEqual(rollups[1].firstSeen, iso("2026-06-01T10:00:00Z"))
        XCTAssertEqual(rollups[1].lastSeen, iso("2026-06-03T10:00:00Z"))
    }

    func test_empty_sessions_produce_no_rollups() {
        XCTAssertTrue(ProjectRollup.forAgent([]).isEmpty)
    }
}
