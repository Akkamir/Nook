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
        let moments = Moment.forAgent(s, currentBond: 2, totalTokens: 12_000, now: iso("2026-06-03T10:00:00Z"))
        XCTAssertTrue(kinds(moments).contains(.bondPromotion(level: 2)))
    }

    func test_incomplete_history_shows_current_bond_without_intermediate_promotions() {
        let s = [
            session("a", input: 6_000, start: "2026-06-01T10:00:00Z"),
            session("b", input: 6_000, start: "2026-06-02T10:00:00Z"),
        ]
        let moments = Moment.forAgent(s, currentBond: 5, totalTokens: 75_000, now: iso("2026-06-03T10:00:00Z"))
        XCTAssertTrue(kinds(moments).contains(.bondPromotion(level: 5)))
        XCTAssertFalse(kinds(moments).contains(.bondPromotion(level: 2)))
        XCTAssertEqual(
            moments.first { $0.kind == .bondPromotion(level: 5) }?.date,
            iso("2026-06-01T10:00:00Z")
        )
    }

    func test_display_date_uses_month_day_and_year() {
        XCTAssertEqual(Moment.displayDate(iso("2026-06-07T12:00:00Z")), "Jun 7, 2026")
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

    func test_token_milestone_does_not_duplicate_bond_at_1M() {
        // 1.2M tokens crosses both bond level 5 and the 1M token milestone — expect bond only.
        let s = [session("a", input: 1_200_000, start: "2026-06-01T10:00:00Z")]
        let k = kinds(Moment.forAgent(s, currentBond: 11, totalTokens: 1_200_000, now: iso("2026-06-02T10:00:00Z")))
        XCTAssertTrue(k.contains(.bondPromotion(level: 11)))
        XCTAssertFalse(k.contains(.tokenMilestone(1_000_000)))
        // 100k milestone (no bond there) still emitted
        XCTAssertTrue(k.contains(.tokenMilestone(100_000)))
    }

    func test_session_count_milestone_at_ten() {
        let s = (1...10).map { session("s\($0)", input: 10, start: "2026-06-\(String(format: "%02d", $0))T10:00:00Z") }
        let k = kinds(Moment.forAgent(s, now: iso("2026-07-01T10:00:00Z")))
        XCTAssertTrue(k.contains(.sessionMilestone(10)))
    }

    func test_longest_session_record() {
        let s = [
            session("a", start: "2026-06-01T10:00:00Z", end: "2026-06-01T10:30:00Z"),
            session("b", start: "2026-06-02T10:00:00Z", end: "2026-06-02T14:00:00Z"), // 4h
        ]
        let k = kinds(Moment.forAgent(s, now: iso("2026-06-03T10:00:00Z")))
        XCTAssertTrue(k.contains(.longestSession(seconds: 4 * 3600)))
    }

    func test_night_session_detected() {
        let s = [session("a", start: "2026-06-01T02:30:00Z", end: "2026-06-01T03:00:00Z")] // 02:30 local-ish
        // Force a UTC calendar so the fixture's hour is the local hour under test.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let k = Moment.forAgent(s, now: iso("2026-06-02T10:00:00Z"), calendar: cal).map(\.kind)
        XCTAssertTrue(k.contains(.nightSession))
    }

    func test_return_after_absence() {
        let s = [
            session("a", input: 10, start: "2026-06-01T10:00:00Z"),
            session("b", input: 10, start: "2026-06-20T10:00:00Z"), // 19 days later
        ]
        let k = kinds(Moment.forAgent(s, now: iso("2026-06-21T10:00:00Z")))
        XCTAssertTrue(k.contains(.returnAfterAbsence(days: 19)))
    }

    func test_summary_current_streak_and_longest() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let s = [
            session("a", start: "2026-06-01T10:00:00Z", end: "2026-06-01T11:00:00Z"),
            session("b", start: "2026-06-02T10:00:00Z", end: "2026-06-02T10:30:00Z"),
        ]
        let summary = Moment.summary(s, now: iso("2026-06-02T20:00:00Z"), calendar: cal)
        XCTAssertEqual(summary.currentStreakDays, 2)
        XCTAssertEqual(summary.longestSessionSeconds, 3600)
    }

    func test_streak_record_dates_to_record_end_day_not_latest_session() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let s = [
            session("a", start: "2026-01-01T10:00:00Z"),
            session("b", start: "2026-01-02T10:00:00Z"),
            session("c", start: "2026-01-03T10:00:00Z"),
            session("d", start: "2026-06-01T10:00:00Z"),
        ]
        let moment = Moment.forAgent(s, now: iso("2026-06-02T10:00:00Z"), calendar: cal)
            .first { $0.kind == .streakRecord(days: 3) }
        XCTAssertEqual(moment?.date, cal.startOfDay(for: iso("2026-01-03T10:00:00Z")))
    }

    func test_night_session_detected_when_session_crosses_midnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let s = [session("a", start: "2026-06-01T23:30:00Z", end: "2026-06-02T01:00:00Z")]
        let k = Moment.forAgent(s, now: iso("2026-06-02T10:00:00Z"), calendar: cal).map(\.kind)
        XCTAssertTrue(k.contains(.nightSession))
    }
}
