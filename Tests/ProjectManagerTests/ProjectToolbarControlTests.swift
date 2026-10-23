import AppKit
import SwiftUI
import XCTest
@testable import ProjectManager

final class ProjectToolbarControlTests: XCTestCase {
    @MainActor
    func testDateFilterHasToolbarHeightForEveryFilter() {
        _ = NSApplication.shared
        for filter in DateFilter.allCases {
            let control = NSHostingView(rootView: DateFilterMenu(dateFilter: .constant(filter)))
            XCTAssertEqual(control.fittingSize.height, AppTheme.searchBarControlHeight, accuracy: 0.5)
            XCTAssertEqual(control.fittingSize.width, 62, accuracy: 0.5)
        }
    }

    @MainActor
    func testSortButtonHasToolbarHeight() {
        _ = NSApplication.shared
        let control = NSHostingView(rootView: SortButtons(sortOption: .constant(.timeDescending)))
        XCTAssertEqual(control.fittingSize.height, AppTheme.searchBarControlHeight, accuracy: 0.5)
        XCTAssertEqual(control.fittingSize.width, AppTheme.searchBarControlHeight, accuracy: 0.5)
    }
}
