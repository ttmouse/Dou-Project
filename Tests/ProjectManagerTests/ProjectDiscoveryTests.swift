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

        XCTAssertFalse(
            discoveredPaths.contains(root.path),
            "监视目录根不应被识别为项目"
        )
        XCTAssertTrue(discoveredPaths.contains(visibleProject.path))
        for name in excludedNames {
            XCTAssertFalse(
                discoveredPaths.contains(root.appendingPathComponent(name).path),
                "\(name) 不应被识别为项目"
            )
        }
    }

    func testProjectIndexLoadProjectsSkipsWatchedRoot() throws {
        let supportDir = TestHelper.createTempDirectory()
        tempDirectories.append(supportDir)
        let root = TestHelper.createTempDirectory()
        tempDirectories.append(root)

        let childA = root.appendingPathComponent("alpha")
        let childB = root.appendingPathComponent("beta")
        try FileManager.default.createDirectory(at: childA, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: childB, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".hidden-tool"),
            withIntermediateDirectories: false
        )

        let index = ProjectIndex(storage: TagStorage(appSupportURL: supportDir))
        index.scanDirectoryTwoLevels(root.path, force: true)
        let loaded = index.loadProjects(fromWatchedDirectories: [root.path])
        // URL.path 可能带 /private 前缀，和 FileManager 临时路径不一致，按标准化后比较
        let normalize: (String) -> String = {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
        }
        let paths = Set(loaded.map { normalize($0.path) })
        let rootPath = normalize(root.path)

        XCTAssertFalse(paths.contains(rootPath), "监视目录根不应进入项目列表")
        XCTAssertTrue(paths.contains(normalize(childA.path)))
        XCTAssertTrue(paths.contains(normalize(childB.path)))
        XCTAssertFalse(paths.contains(normalize(root.appendingPathComponent(".hidden-tool").path)))
    }
}
