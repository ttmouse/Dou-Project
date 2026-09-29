import XCTest
@testable import ProjectManager

/// 项目注册：git 采集不得阻塞调用线程（P0-2 回归护栏）
///
/// 症状背景：`registerProjects` 原先在调用者线程同步跑 `git log`/`rev-parse`，
/// 而调用方多在主线程（`DispatchQueue.main.async`、通知回调、工具栏命令）——
/// 上百个仓库会直接冻住界面。现在：注册立即返回，git 数据在后台补齐后回主线程更新。
///
/// 本文件只依赖注入的临时存储（`TagStorage(appSupportURL:)`），不碰真实用户数据。
final class ProjectRegistrationTests: XCTestCase {

    // MARK: - 测试替身

    private final class FakeStore: ProjectOperationDelegate {
        var projects: [UUID: Project] = [:]
        var allTags: Set<String> = []
        private(set) var invalidateCount = 0
        private(set) var notifyCount = 0

        func invalidateTagUsageCache() { invalidateCount += 1 }
        func notifyProjectsChanged() { notifyCount += 1 }
    }

    private final class FakeSortStore: SortManagerDelegate {
        private(set) var inserted: [Project] = []
        private(set) var updated: [Project] = []
        private(set) var removed: [Project] = []
        func updateSortedProjects(_ projects: [Project]) {}
        func insertProject(_ project: Project) { inserted.append(project) }
        func updateProject(_ project: Project) { updated.append(project) }
        func removeProject(_ project: Project) { removed.append(project) }
    }

    // MARK: - 夹具

    private var tempDirs: [URL] = []
    private var storage: TagStorage!
    private var store: FakeStore!
    private var sortStore: FakeSortStore!
    private var manager: ProjectOperationManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let supportDir = TestHelper.createTempDirectory()
        tempDirs.append(supportDir)
        storage = TagStorage(appSupportURL: supportDir)
        // HEAD 缓存路径写死真实目录且不经过 TagStorage，也要改到临时目录
        GitDailyCollector.gitHeadCacheURLOverride = supportDir.appendingPathComponent("git_heads.json")
        store = FakeStore()
        sortStore = FakeSortStore()
        manager = ProjectOperationManager(delegate: store, sortDelegate: sortStore, storage: storage)
    }

    override func tearDown() {
        GitDailyCollector.gitHeadCacheURLOverride = nil
        tempDirs.forEach(TestHelper.cleanupTempDirectory)
        tempDirs.removeAll()
        super.tearDown()
    }

    /// 造一个真实 git 仓库（有 HEAD、有一条提交），用于验证 git_daily 真的被采集到
    private func makeGitRepo(name: String) throws -> URL {
        let dir = TestHelper.createTempDirectory()
        tempDirs.append(dir)
        try runGit(["init", "-q"], in: dir)
        try runGit(["config", "user.email", "tests@example.com"], in: dir)
        try runGit(["config", "user.name", "Tests"], in: dir)
        try runGit(["commit", "-q", "--allow-empty", "-m", "init"], in: dir)
        return dir
    }

    private func runGit(_ args: [String], in dir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = dir
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(args.joined(separator: " ")) 执行失败")
    }

    private func project(at url: URL) -> Project {
        ProjectFixtures.make(name: url.lastPathComponent, path: url.path)
    }

    // MARK: - 注册不阻塞 + 异步补齐

    func testRegisterReturnsBeforeGitCollectionRuns() throws {
        let repo = try makeGitRepo(name: "repo-a")
        let project = project(at: repo)
        XCTAssertNil(project.git_daily, "前提：入库时还没有 git 数据")

        manager.registerProjects([project])

        // 关键断言：调用返回时（同一轮主线程），项目已可见但 git 采集尚未发生。
        // 同步实现下这里必然已经有 git_daily。
        XCTAssertEqual(store.projects.count, 1, "项目应立即注册可见，不必等 git")
        XCTAssertNil(store.projects[project.id]?.git_daily, "git 采集不应在注册调用内同步完成")
        XCTAssertEqual(sortStore.inserted.count, 1, "排序索引应同步更新")
    }

    func testGitDailyIsFilledInAsynchronously() throws {
        let repo = try makeGitRepo(name: "repo-b")
        let project = project(at: repo)

        manager.registerProjects([project])

        // 后台队列 → 主队列回填，等它出现
        assertAsync({ self.store.projects[project.id]?.git_daily?.isEmpty == false }, timeout: 30)

        let gitDaily = try XCTUnwrap(store.projects[project.id]?.git_daily)
        let parsed = GitDailyCollector.parseGitDaily(gitDaily)
        XCTAssertEqual(parsed.values.reduce(0, +), 1, "仓库只有一条提交，应采集到 1 次")
        XCTAssertEqual(sortStore.updated.count, 1, "回填后应通知排序索引更新")
        XCTAssertGreaterThanOrEqual(store.notifyCount, 2, "注册一次 + 回填一次，都该通知 UI")
    }

    func testNonGitProjectNeverGetsGitDaily() throws {
        let plainDir = TestHelper.createTempDirectory()
        tempDirs.append(plainDir)
        let project = project(at: plainDir)

        manager.registerProjects([project])
        XCTAssertTrue(TestHelper.waitFor({ self.store.projects[project.id]?.git_daily != nil }, timeout: 0.4) == false,
                      "非 git 目录不应产生 git_daily")
    }

    func testUpdateGitDailyFalseSkipsBackgroundCollection() throws {
        let repo = try makeGitRepo(name: "repo-c")
        let project = project(at: repo)

        manager.registerProjects([project], updateGitDaily: false)

        XCTAssertEqual(store.projects.count, 1)
        XCTAssertFalse(TestHelper.waitFor({ self.store.projects[project.id]?.git_daily != nil }, timeout: 0.4),
                       "updateGitDaily=false 时不应触发后台采集")
    }

    /// 已存在的项目会被跳过（既有语义）。同时确认不会为被跳过的项目做无用采集。
    func testAlreadyRegisteredProjectsAreSkipped() throws {
        let repo = try makeGitRepo(name: "repo-d")
        let project = project(at: repo)

        manager.registerProjects([project])
        let notifyAfterFirst = store.notifyCount

        manager.registerProjects([project])

        XCTAssertEqual(store.projects.count, 1)
        XCTAssertEqual(store.notifyCount, notifyAfterFirst + 1, "重复注册只应触发一次变更通知（且不再补 git）")
    }

    func testRemoveProjectAlsoRemovesItFromSortedList() {
        let project = ProjectFixtures.make(name: ".claude", path: "/tmp/.claude")
        store.projects[project.id] = project

        manager.removeProject(project.id)

        XCTAssertNil(store.projects[project.id])
        XCTAssertEqual(sortStore.removed.map(\.id), [project.id], "UI 排序列表必须同步移除项目")
    }

    func testRegisterProjectsRejectsDotPrefixedDirectory() {
        let hiddenProject = ProjectFixtures.make(name: ".venv", path: "/tmp/.venv")

        manager.registerProjects([hiddenProject], updateGitDaily: false)

        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertTrue(sortStore.inserted.isEmpty)
    }

    // MARK: - 存储隔离

    func testWritesGoToInjectedStorageOnly() {
        let project = ProjectFixtures.make(name: "隔离项目", path: "/tmp/isolated")
        manager.registerProjects([project], updateGitDaily: false)

        // 写盘现在走 2s 合并去抖 + 串行 I/O 队列（2026-09-29 主线程同步写盘修复），
        // 同步断言改为轮询等待异步落盘（上限 4s，实际 2s 内完成）。
        let written = storage.appSupportURL.appendingPathComponent("projects.json")
        let deadline = Date().addingTimeInterval(4)
        var writtenExists = false
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: written.path) {
                writtenExists = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(writtenExists,
                      "数据应写入注入的临时目录，而不是真实用户目录")
    }
}
