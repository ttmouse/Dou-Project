import AppKit
import XCTest
@testable import ProjectManager

final class ProjectPathClipboardTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("ProjectPathClipboardTests"))
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    func testCopyWritesFullPathWithoutTildeAbbreviation() {
        let path = NSHomeDirectory() + "/Projects/project-list"

        XCTAssertTrue(ProjectPathClipboard.copy(path: path, pasteboard: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), path)
    }

    func testCopyReplacesPreviousContents() {
        pasteboard.setString("stale", forType: .string)

        ProjectPathClipboard.copy(path: "/Volumes/Work/example", pasteboard: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "/Volumes/Work/example")
    }

    func testToastMessageIsTheSharedCopyFeedback() {
        XCTAssertEqual(ProjectPathClipboard.toastMessage, "已复制路径")
    }
}
