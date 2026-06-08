import XCTest
@testable import Nook

final class SpeechLineComposerTests: XCTestCase {
    let c = HeuristicLineComposer()
    func event(_ kind: String, _ payload: String?) -> SessionActivityEvent {
        SessionActivityEvent(agentName: "Radion", sessionId: "s1", kind: kind, payload: payload, seq: 1)
    }

    func test_task_line() {
        let result = c.line(for: event("task", "refactor auth"), session: nil)
        XCTAssertNotNil(result)
        let valid = ["On it: refactor auth", "New mission — refactor auth",
                     "Alright, let's go.", "Reading the brief: refactor auth"]
        XCTAssertTrue(valid.contains(result!), "Unexpected task line: \(result!)")
    }
    func test_file_line() {
        let result = c.line(for: event("file", "Moment.swift"), session: nil)
        XCTAssertNotNil(result)
        let valid = ["Deep in Moment.swift", "I see Moment.swift",
                     "Oh, Moment.swift…", "Opening Moment.swift"]
        XCTAssertTrue(valid.contains(result!), "Unexpected file line: \(result!)")
    }
    func test_testing_line() {
        let result = c.line(for: event("testing", "swift"), session: nil)
        XCTAssertNotNil(result)
        let valid = ["Love a good test run.", "Tests time?", "Red or green?", "Running the suite."]
        XCTAssertTrue(valid.contains(result!), "Unexpected testing line: \(result!)")
    }
    func test_committing_line() {
        let result = c.line(for: event("committing", "git commit"), session: nil)
        XCTAssertNotNil(result)
        let valid = ["Committing?", "Checkpoint.", "Good call.", "Git commit incoming."]
        XCTAssertTrue(valid.contains(result!), "Unexpected committing line: \(result!)")
    }
    func test_deepwork_line() {
        let result = c.line(for: event("deepWork", "Nook"), session: nil)
        XCTAssertNotNil(result)
        let valid = ["Heavy session on Nook", "We're really in it.", "Long run on Nook.", "Nice progress."]
        XCTAssertTrue(valid.contains(result!), "Unexpected deepWork line: \(result!)")
    }
    func test_unknown_kind_returns_nil() {
        XCTAssertNil(c.line(for: event("mystery", nil), session: nil))
    }
    func test_missing_payload_returns_nil_where_payload_required() {
        XCTAssertNil(c.line(for: event("file", nil), session: nil))
    }
}
