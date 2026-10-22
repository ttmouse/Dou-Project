import XCTest
@testable import ProjectManager

final class DateFilterTests: XCTestCase {
    func testCompactLabelsKeepTheToolbarFilterNarrow() {
        XCTAssertEqual(DateFilter.all.compactLabel, "全部")
        XCTAssertEqual(DateFilter.lastDay.compactLabel, "1天")
        XCTAssertEqual(DateFilter.lastWeek.compactLabel, "7天")
    }

    func testFullTitlesRemainAvailableForMenusAndAccessibility() {
        XCTAssertEqual(DateFilter.all.title, "全部日期")
        XCTAssertEqual(DateFilter.lastDay.title, "最近一天")
        XCTAssertEqual(DateFilter.lastWeek.title, "最近一周")
    }
}
