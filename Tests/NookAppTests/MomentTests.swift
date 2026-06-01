import XCTest
@testable import Nook

final class MomentTests: XCTestCase {
    func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func session(_ id: String, project: String = "Nook", path: String = "/n",
                 input: Int = 0, output: Int = 0, start: String, end: String? = nil) -> SessionRecord {
        SessionRecord(sessionId: id, project: project, projectPath: path, agentName: "Radion",
                      startedAt: iso(start), lastActivityAt: iso(end ?? start),
                      inputTokens: input, outputTokens: output, totalBits: 0)
    }

    func kinds(_ moments: [Moment]) -> [Moment.Kind] { moments.map(\.kind) }

    func test_first_session_moment() {
        let s = [session("a", start: "2026-06-01T10:00:00Z")]
        let moments = Moment.forAgent(s, now: iso("2026-06-02T10:00:00Z"))
        XCTAssertTrue(kinds(moments).contains(.firstSession))
    }

    func test_first_day_on_each_project() {
        let s = [
            session("a", project: "Nook", path: "/n", start: "2026-06-01T10:00:00Z"),
            session("b", project: "Radion", path: "/r", start: "2026-06-02T10:00:00Z"),
            session("c", project: "Nook", path: "/n", start: "2026-06-03T10:00:00Z"),
        ]
        let moments = Moment.forAgent(s, now: iso("2026-06-04T10:00:00Z"))
        XCTAssertTrue(kinds(moments).contains(.firstOnProject("Nook")))
        XCTAssertTrue(kinds(moments).contains(.firstOnProject("Radion")))
        XCTAssertEqual(kinds(moments).filter { $0 == .firstOnProject("Nook") }.count, 1)
    }

    func test_bond_promotion_on_crossing_session() {
        let s = [
            session("a", input: 6_000, start: "2026-06-01T10:00:00Z"),
            session("b", input: 6_000, start: "2026-06-02T10:00:00Z"),
        ]
        let moments = Moment.forAgent(s, now: iso("2026-06-03T10:00:00Z"))
        XCTAssertTrue(kinds(moments).contains(.bondPromotion(level: 2)))
    }

    func test_moments_sorted_chronologically() {
        let s = [
            session("a", input: 6_000, start: "2026-06-01T10:00:00Z"),
            session("b", input: 6_000, start: "2026-06-02T10:00:00Z"),
        ]
        let dates = Moment.forAgent(s, now: iso("2026-06-03T10:00:00Z")).map(\.date)
        XCTAssertEqual(dates, dates.sorted())
    }

    func test_anniversary_near_date() {
        let s = [session("a", start: "2025-06-01T10:00:00Z")]
        let k = kinds(Moment.forAgent(s, now: iso("2026-06-02T10:00:00Z")))
        XCTAssertTrue(k.contains(.anniversary(years: 1)))
    }

    func test_anniversary_near_date_before_anniversary() {
        let s = [session("a", start: "2025-06-01T10:00:00Z")]
        let k = kinds(Moment.forAgent(s, now: iso("2026-05-30T10:00:00Z")))
        XCTAssertTrue(k.contains(.anniversary(years: 1)))
    }

    func test_no_anniversary_far_from_date() {
        let s = [session("a", start: "2025-06-01T10:00:00Z")]
        let k = kinds(Moment.forAgent(s, now: iso("2026-09-01T10:00:00Z")))
        XCTAssertFalse(k.contains { if case .anniversary = $0 { return true } else { return false } })
    }
}
