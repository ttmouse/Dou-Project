import XCTest
@testable import ProjectManager

final class DetailPanelPresentationTests: XCTestCase {
    func testOpeningUsesSelectedProjectWhenNoDetailWasPreviouslyShown() {
        let selectedID = UUID()

        XCTAssertEqual(
            DetailPanelPresentationLogic.targetProjectID(
                isPanelVisible: true,
                currentProjectID: nil,
                selectedProjectIDs: [selectedID],
                visibleProjectIDs: [selectedID]
            ),
            selectedID
        )
    }

    func testOpeningUsesFirstVisibleProjectWhenNothingIsSelected() {
        let firstVisibleID = UUID()
        let secondVisibleID = UUID()

        XCTAssertEqual(
            DetailPanelPresentationLogic.targetProjectID(
                isPanelVisible: true,
                currentProjectID: nil,
                selectedProjectIDs: [],
                visibleProjectIDs: [firstVisibleID, secondVisibleID]
            ),
            firstVisibleID
        )
    }

    func testCurrentDetailProjectTakesPriorityWhileItRemainsVisible() {
        let currentID = UUID()
        let selectedID = UUID()

        XCTAssertEqual(
            DetailPanelPresentationLogic.targetProjectID(
                isPanelVisible: true,
                currentProjectID: currentID,
                selectedProjectIDs: [selectedID],
                visibleProjectIDs: [currentID, selectedID]
            ),
            currentID
        )
    }

    func testClosedPanelDoesNotResolveAnyDetailProject() {
        let currentID = UUID()
        let selectedID = UUID()

        XCTAssertNil(
            DetailPanelPresentationLogic.targetProjectID(
                isPanelVisible: false,
                currentProjectID: currentID,
                selectedProjectIDs: [selectedID],
                visibleProjectIDs: [currentID, selectedID]
            )
        )
    }
}
