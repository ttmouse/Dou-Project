import XCTest
@testable import ProjectManager

final class ProjectDiscoveryTests: XCTestCase {
    private var tempDirectories: [URL] = []

    override func tearDown() {
        tempDirectories.forEach(TestHelper.cleanupTempDirectory)
        tempDirectories.removeAll()
        super.tearDown()
    }

    func testDiscoveryExcludesDotPrefixedToolDirectories() throws {
        let root = TestHelper.createTempDirectory()
        tempDirectories.append(root)

        let visibleProject = root.appendingPathComponent("visible-project")
        try FileManager.default.createDirectory(at: visibleProject, withIntermediateDirectories: false)

        let excludedNames = [".claude", ".phpm-store", ".reasonix", ".venv"]
        for name in excludedNames {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name),
                withIntermediateDirectories: false
            )
        }

        let discoveredPaths = Set(
            ProjectLoaderOptimized().discoverProjectsSmart(from: [root.path])
        )

        XCTAssertTrue(discoveredPaths.contains(root.path))
        XCTAssertTrue(discoveredPaths.contains(visibleProject.path))
        for name in excludedNames {
            XCTAssertFalse(
                discoveredPaths.contains(root.appendingPathComponent(name).path),
                "\(name) 不应被识别为项目"
            )
        }
    }
}
