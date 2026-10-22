import XCTest
@testable import ProjectManager

final class ProjectSnapshotTests: XCTestCase {
    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = directory
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testExplicitSnapshotDoesNotReloadGitAndCopiesPreserveFields() throws {
        let directory = TestHelper.createTempDirectory()
        defer { TestHelper.cleanupTempDirectory(directory) }
        try runGit(["init", "-q"], in: directory)
        try runGit(["-c", "user.name=Tests", "-c", "user.email=tests@example.com",
                    "commit", "-q", "--allow-empty", "-m", "fixture"], in: directory)

        let modified = Date(timeIntervalSince1970: 100)
        let activity = modified.addingTimeInterval(500)
        let start = ProcessInfo.processInfo.systemUptime
        var copies: [Project] = []
        for _ in 0..<50 {
            let snapshot = Project(
                name: "snapshot", path: directory.path, tags: ["old"],
                mtime: modified, activityAt: activity, size: 42, checksum: "cached",
                git_commits: 0, git_last_commit: .distantPast,
                startupCommand: "npm start", customPort: 4321,
                created: modified, checked: modified
            )
            copies.append(snapshot.copyWith(tags: ["new"]).copyWith(gitDaily: "2026-10-21:1"))
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print("PERF snapshot + tag copy + git copy, 50 iterations: \(elapsed * 1000) ms")
        for copy in copies {
            XCTAssertEqual(copy.git_commits, 0, "显式零提交必须保留，不能重新扫描磁盘上的仓库")
            XCTAssertEqual(copy.activityAt, activity)
            XCTAssertEqual(copy.startupCommand, "npm start")
            XCTAssertEqual(copy.customPort, 4321)
            XCTAssertEqual(copy.tags, ["new"])
            XCTAssertEqual(copy.size, 42)
            XCTAssertEqual(copy.checksum, "cached")
        }
    }

    func testOmittedMetadataStillDiscoversGit() throws {
        let directory = TestHelper.createTempDirectory()
        defer { TestHelper.cleanupTempDirectory(directory) }
        try runGit(["init", "-q"], in: directory)
        try runGit(["-c", "user.name=Tests", "-c", "user.email=tests@example.com",
                    "commit", "-q", "--allow-empty", "-m", "fixture"], in: directory)
        let project = Project(name: "discovered", path: directory.path)
        XCTAssertEqual(project.git_commits, 1)
        XCTAssertGreaterThan(project.git_last_commit, .distantPast)
    }

    func testLargeGitHistoryDrainsOutputAndRefreshPreservesSnapshot() throws {
        let directory = TestHelper.createTempDirectory()
        defer { TestHelper.cleanupTempDirectory(directory) }
        try runGit(["init", "-q"], in: directory)
        // 输出超过管道容量；先 waitUntilExit 再读取 stdout 会互相等待。
        let count = 12_000
        let input = (0..<count).map { index in
            "commit refs/heads/main\ncommitter Tests <tests@example.com> \(1_700_000_000 + index) +0000\ndata 1\nx\n\n"
        }.joined() + "done\n"
        let inputURL = directory.appendingPathComponent("history.fixture")
        try Data(input.utf8).write(to: inputURL)
        let handle = try FileHandle(forReadingFrom: inputURL)
        defer { try? handle.close() }
        let importer = Process()
        importer.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        importer.currentDirectoryURL = directory
        importer.arguments = ["fast-import", "--quiet"]
        importer.standardInput = handle
        importer.standardOutput = FileHandle.nullDevice
        importer.standardError = FileHandle.nullDevice
        try importer.run()
        importer.waitUntilExit()
        XCTAssertEqual(importer.terminationStatus, 0)
        try runGit(["symbolic-ref", "HEAD", "refs/heads/main"], in: directory)

        let original = Project(
            name: "large", path: directory.path, mtime: .distantPast,
            activityAt: Date(), size: 0, checksum: "cached", git_commits: count,
            git_last_commit: Date(), startupCommand: "npm start", customPort: 4321
        )
        let completion = expectation(description: "大历史输出必须完成，不可堵塞管道")
        DispatchQueue.global().async {
            let refreshed = original.withUpdatedGitDaily()
            XCTAssertEqual(GitDailyCollector.parseGitDaily(refreshed.git_daily).values.reduce(0, +), count)
            XCTAssertEqual(refreshed.activityAt, original.activityAt)
            XCTAssertEqual(refreshed.startupCommand, original.startupCommand)
            XCTAssertEqual(refreshed.customPort, original.customPort)
            completion.fulfill()
        }
        wait(for: [completion], timeout: 10)
    }
}
