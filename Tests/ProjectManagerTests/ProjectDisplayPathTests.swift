import XCTest
@testable import ProjectManager

final class ProjectDisplayPathTests: XCTestCase {
    func testHomeDirectoryIsAbbreviatedWithoutChangingStoredPath() {
        let path = NSHomeDirectory() + "/Projects/dsh-drag"
        let project = ProjectFixtures.make(name: "dsh-drag", path: path)

        XCTAssertEqual(project.displayPath, "~/Projects/dsh-drag")
        XCTAssertEqual(project.path, path)
    }

    func testExternalVolumeKeepsItsAbsolutePath() {
        let project = ProjectFixtures.make(name: "example", path: "/Volumes/Work/example")

        XCTAssertEqual(project.displayPath, "/Volumes/Work/example")
    }

    func testSimilarHomePrefixIsNotAbbreviated() {
        let path = NSHomeDirectory() + "-other/Projects/example"
        let project = ProjectFixtures.make(name: "example", path: path)

        XCTAssertEqual(project.displayPath, path)
    }
}
