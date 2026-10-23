import XCTest
@testable import ProjectManager

final class ProjectCardDateDisplayTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testSameCalendarDayDisplaysToday() {
        XCTAssertEqual(ProjectCardDateDisplay.label(for: date(2026, 10, 23, 1), relativeTo: date(2026, 10, 23, 23), calendar: calendar), "今天")
    }

    func testCrossingMidnightDisplaysYesterday() {
        XCTAssertEqual(ProjectCardDateDisplay.label(for: date(2026, 10, 22, 23), relativeTo: date(2026, 10, 23, 1), calendar: calendar), "昨天")
    }

    func testMultipleDaysAndMonthBoundary() {
        XCTAssertEqual(ProjectCardDateDisplay.label(for: date(2026, 9, 30), relativeTo: date(2026, 10, 3), calendar: calendar), "3 天前")
    }

    func testDaylightSavingDoesNotChangeCalendarDayCount() {
        XCTAssertEqual(ProjectCardDateDisplay.label(for: date(2026, 3, 7), relativeTo: date(2026, 3, 9), calendar: calendar), "2 天前")
    }

    func testFutureDatesAreNotPresentedAsPastDates() {
        XCTAssertEqual(ProjectCardDateDisplay.label(for: date(2026, 10, 24), relativeTo: date(2026, 10, 23), calendar: calendar), "明天")
        XCTAssertEqual(ProjectCardDateDisplay.label(for: date(2026, 10, 26), relativeTo: date(2026, 10, 23), calendar: calendar), "3 天后")
    }
}
