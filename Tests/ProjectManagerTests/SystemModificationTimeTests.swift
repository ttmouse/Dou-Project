import XCTest
@testable import ProjectManager

final class SystemModificationTimeTests: XCTestCase {
    func testIncrementalReloadReadsSystemDateWithoutProjectAdditions() throws {
        let root = TestHelper.createTempDirectory()
        defer { TestHelper.cleanupTempDirectory(root) }
        let directory = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let systemDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: systemDate], ofItemAtPath: directory.path)
        let cached = Project(
            name: "project", path: directory.path, tags: ["keep"],
            mtime: systemDate.addingTimeInterval(1000), activityAt: Date(),
            size: 0, checksum: "stale", git_commits: 7, git_last_commit: systemDate,
            git_daily: "2026-10-23:7", startupCommand: "npm start", customPort: 4321
        )
        let loader = ProjectLoaderOptimized()
        let result = loader.updateProjectsIncremental(
            currentProjects: [cached.id: cached], watchedDirectories: [root.path]
        )
        let refreshed = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        let diskDate = try directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        XCTAssertEqual(refreshed.mtime, diskDate)
        XCTAssertLessThan(refreshed.mtime, cached.mtime, "系统日期回退也必须同步")
        XCTAssertEqual(refreshed.id, cached.id)
        XCTAssertEqual(refreshed.tags, cached.tags)
        XCTAssertEqual(refreshed.git_daily, cached.git_daily)
        XCTAssertEqual(refreshed.git_commits, cached.git_commits)
        XCTAssertEqual(refreshed.startupCommand, cached.startupCommand)
        XCTAssertEqual(refreshed.customPort, cached.customPort)

        let unchanged = loader.updateProjectsIncremental(
            currentProjects: [refreshed.id: refreshed], watchedDirectories: [root.path]
        )
        XCTAssertEqual(unchanged, [refreshed], "重复扫描不能因为检查时间变化反复发布")
    }
}
