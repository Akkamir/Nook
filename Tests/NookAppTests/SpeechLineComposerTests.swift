import XCTest
@testable import Nook

final class SpeechLineComposerTests: XCTestCase {
    let c = HeuristicLineComposer()
    func event(_ kind: String, _ payload: String?) -> SessionActivityEvent {
        SessionActivityEvent(agentName: "Radion", sessionId: "s1", kind: kind, payload: payload, seq: 1)
    }

    func test_task_line() {
        XCTAssertEqual(c.line(for: event("task", "refactor auth"), session: nil), "On attaque : refactor auth")
    }
    func test_file_line() {
        XCTAssertEqual(c.line(for: event("file", "Moment.swift"), session: nil), "Plongé dans Moment.swift")
    }
    func test_testing_line() {
        XCTAssertEqual(c.line(for: event("testing", "swift"), session: nil), "TDD, j'aime ça")
    }
    func test_committing_line() {
        XCTAssertEqual(c.line(for: event("committing", "git commit"), session: nil), "On commit ?")
    }
    func test_deepwork_line() {
        XCTAssertEqual(c.line(for: event("deepWork", "Nook"), session: nil), "Grosse session sur Nook")
    }
    func test_unknown_kind_returns_nil() {
        XCTAssertNil(c.line(for: event("mystery", nil), session: nil))
    }
    func test_missing_payload_returns_nil_where_payload_required() {
        XCTAssertNil(c.line(for: event("file", nil), session: nil))
    }
}
