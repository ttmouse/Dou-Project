import XCTest
@testable import ProjectManager

/// 异步保存生命周期的回归护栏（审计后续 #4）
///
/// 症状背景：两处防抖保存都用 `Timer.scheduledTimer` 挂在调用线程的 RunLoop 上。
/// 从后台队列（目录扫描、Git 回填、测试夹具）触发时，那个线程没有 RunLoop 在跑，
/// 回调永远不会来 —— 保存被静默丢掉。临时目录被删掉之后同理：待写任务照样醒来，
/// 只在控制台留下一行「保存项目缓存失败」，调用方却以为已经保存成功，
/// 测试也会在收尾之后才看到这行噪声。
///
/// 本文件锁住四件事：
///   1. 目录被删后写盘返回明确的失败原因，且不重建目录、不污染真实路径；
///   2. 防抖任务能在任意线程调度，并且真的会触发（不是挂上去就算保存）；
///   3. 连续变更只合并成一次写盘，取消之后不再写盘；
///   4. 删除目录后的调度/收尾不产生未捕获错误、不留下待写任务。
///
/// 只使用注入的临时存储（`TagStorage(appSupportURL:)`），不碰真实用户数据。
final class AsyncSaveLifecycleTests: XCTestCase {

    // MARK: - 测试替身

    private final class FakeStore: ProjectOperationDelegate {
        var projects: [UUID: Project] = [:]
        var allTags: Set<String> = []
        var invalidateCount = 0

        func invalidateTagUsageCache() { invalidateCount += 1 }
        func notifyProjectsChanged() {}
    }

    // MARK: - 夹具

    private var tempDirs: [URL] = []
    /// 本用例创建的管理器：收尾时先取消待写任务，
    /// 避免它们在目录删掉之后才醒来，把失败日志留到用例之外。
    private var managers: [ProjectOperationManager] = []
    private var tagManagers: [TagManager] = []

    override func tearDown() {
        // 收尾顺序很重要：先取消尚未触发的防抖任务，再排空已经进队的写盘，
        // 最后才删目录。否则删除与在途写入会赛跑，失败日志落到用例之外。
        tagManagers.forEach { $0.cancelPendingSave() }
        managers.forEach { $0.cancelPendingSave() }
        tagManagers.forEach { $0.drainPendingWrites() }
        managers.forEach { $0.drainPendingWrites() }
        tagManagers.removeAll()
        managers.removeAll()

        for dir in tempDirs where FileManager.default.fileExists(atPath: dir.path) {
            TestHelper.cleanupTempDirectory(dir)
        }
        tempDirs.removeAll()
        super.tearDown()
    }

    private func makeTempDirectory() -> URL {
        let dir = TestHelper.createTempDirectory()
        tempDirs.append(dir)
        return dir
    }

    private func makeStorage(_ dir: URL) -> TagStorage {
        TagStorage(appSupportURL: dir)
    }

    private func makeManager(_ dir: URL, store: FakeStore) -> ProjectOperationManager {
        let manager = ProjectOperationManager(
            delegate: store,
            sortDelegate: ProjectSortManager(),
            storage: makeStorage(dir)
        )
        managers.append(manager)
        return manager
    }

    private func makeTagManager(_ dir: URL) -> TagManager {
        let manager = TagManager(storageDirectory: dir, startMonitoring: false)
        tagManagers.append(manager)
        // 初始化会补一次颜色保存；这里先等它落定，
        // 用例里读到的 saveAttemptCount 才是干净的基线。
        manager.drainPendingWrites()
        return manager
    }

    private func makeProject(name: String = "alpha", path: String = "/tmp/alpha") -> Project {
        ProjectFixtures.make(name: name, path: path)
    }

    // MARK: - 1. 目录被删后的写盘契约

    func testSaveProjectsReportsDirectoryUnavailableInsteadOfRecreatingIt() throws {
        let dir = makeTempDirectory()
        let storage = makeStorage(dir)
        assertSucceeded(try storage.saveProjectsReportingResult([makeProject()]))

        TestHelper.cleanupTempDirectory(dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path), "前提：目录已删除")

        let result = storage.saveProjectsReportingResult([makeProject()])

        switch result {
        case .failure(.directoryUnavailable(let reported)):
            XCTAssertEqual(reported.standardizedFileURL.path, dir.standardizedFileURL.path,
                           "失败原因要指明是哪个目录没了，便于按路径排查")
        case .failure(let other):
            XCTFail("期望 directoryUnavailable，实际是 \(other)")
        case .success:
            XCTFail("目录已删除，保存不可能成功")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path),
                       "保存失败时不能顺手把目录重建出来")
    }

    func testAppStateSaveReportsDirectoryUnavailableAfterRemoval() {
        let dir = makeTempDirectory()
        let appStateStorage = AppStateStorage(appSupportURL: dir)
        assertSucceeded(
            appStateStorage.saveReportingResult(.empty),
            "目录存在时统一存储应正常写入"
        )

        TestHelper.cleanupTempDirectory(dir)

        XCTAssertEqual(
            appStateStorage.saveReportingResult(.empty).failureError, .directoryUnavailable(dir),
            "目录删除后统一存储同样要返回明确的失败原因"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path),
                       "失败路径不能重建目录")
    }

    // MARK: - 2. 防抖任务在任意线程都能触发

    func testDebouncedSaveSchedulesFromBackgroundThreadAndLands() {
        let dir = makeTempDirectory()
        let store = FakeStore()
        let manager = makeManager(dir, store: store)
        store.projects[UUID()] = makeProject()

        let scheduled = expectation(description: "后台线程调度保存")
        DispatchQueue.global(qos: .utility).async {
            manager.saveAllToCache()
            scheduled.fulfill()
        }
        wait(for: [scheduled], timeout: 5)

        let written = dir.appendingPathComponent("projects.json")
        XCTAssertTrue(
            TestHelper.waitFor({ FileManager.default.fileExists(atPath: written.path) }, timeout: 4),
            "从后台队列调度的防抖保存也必须真的落盘，不能被 RunLoop 静默吞掉"
        )
        XCTAssertNil(manager.lastSaveResult, "成功落盘后不应留下失败记录")
    }

    func testDebouncedSchedulerRunsOnArbitraryThread() {
        let scheduler = DebouncedWorkScheduler(label: "test.debounce.thread")
        let fired = expectation(description: "任务触发")
        let scheduledAt = Date()

        DispatchQueue.global(qos: .utility).async {
            scheduler.schedule(after: 0.2) { fired.fulfill() }
        }

        wait(for: [fired], timeout: 3)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(scheduledAt), 0.2,
                                    "提前触发说明没有真正走延迟")
    }

    func testSimulatedActorWithoutRunLoopStillFires() throws {
        // 直接在一个没有 RunLoop 的 Thread 上调度：旧实现里 Timer 不会触发。
        let scheduler = DebouncedWorkScheduler(label: "test.debounce.bare-thread")
        let fired = expectation(description: "无 RunLoop 线程上的任务触发")
        let thread = Thread {
            scheduler.schedule(after: 0.1) { fired.fulfill() }
        }
        thread.start()
        wait(for: [fired], timeout: 3)
    }

    // MARK: - 3. 合并与取消

    func testRapidChangesCollapseIntoOneWrite() {
        let dir = makeTempDirectory()
        let store = FakeStore()
        let manager = makeManager(dir, store: store)
        store.projects[UUID()] = makeProject()

        for index in 0..<20 {
            store.projects[UUID()] = makeProject(name: "p\(index)", path: "/tmp/p\(index)")
            manager.saveAllToCache()
        }

        XCTAssertTrue(
            TestHelper.waitFor({ manager.saveAttemptCount >= 1 }, timeout: 5),
            "合并窗口结束后至少写一次"
        )
        // 再等一个窗口，确认没有把 20 次调度逐拍写盘。
        _ = TestHelper.waitFor({ false }, timeout: 1)
        XCTAssertEqual(manager.saveAttemptCount, 1, "连续变更应合并成一次写盘")
    }

    func testCancelledSaveDoesNotWrite() {
        let dir = makeTempDirectory()
        let store = FakeStore()
        let manager = makeManager(dir, store: store)
        store.projects[UUID()] = makeProject()

        manager.saveAllToCache()
        manager.cancelPendingSave()

        _ = TestHelper.waitFor({ false }, timeout: 2.6)
        XCTAssertEqual(manager.saveAttemptCount, 0, "取消后不应再写盘")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dir.appendingPathComponent("projects.json").path),
            "取消之后不该留下写盘产物"
        )
    }

    func testFlushWritesImmediatelyWithoutWaitingForDebounce() {
        let dir = makeTempDirectory()
        let store = FakeStore()
        let manager = makeManager(dir, store: store)
        store.projects[UUID()] = makeProject()

        manager.saveAllToCache()
        assertSucceeded(manager.flushPendingSave())

        let written = dir.appendingPathComponent("projects.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path), "flush 应同步落盘")
        XCTAssertEqual(manager.saveAttemptCount, 1, "取消+flush 只写一次")
    }

    // MARK: - 4. 目录删除后的整条生命周期

    /// 本卡的核心回归：先正常保存一次，再删掉临时目录，然后触发一次合并保存。
    /// 约定是「明确失败但安静」：没有未捕获错误、不重建目录、失败原因可查询。
    func testSaveAfterTempDirectoryRemovalFailsQuietly() {
        let dir = makeTempDirectory()
        let store = FakeStore()
        let manager = makeManager(dir, store: store)
        store.projects[UUID()] = makeProject()
        assertSucceeded(manager.flushPendingSave())

        TestHelper.cleanupTempDirectory(dir)

        // 触发合并保存：调度、等待、观察结果，全程不应抛错或崩溃。
        manager.saveAllToCache()
        XCTAssertTrue(
            TestHelper.waitFor({ manager.lastSaveResult != nil }, timeout: 5),
            "目录删除后的保存必须给出明确的失败结果"
        )

        XCTAssertEqual(manager.lastSaveResult, .directoryUnavailable(dir))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path),
                       "失败路径不能重建临时目录，也不能写到别处")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dir.appendingPathComponent("projects.json").path),
            "目录已经没了，不应该再出现 projects.json"
        )
    }

    func testRepeatedSaveAfterRemovalKeepsReportingFailure() {
        let dir = makeTempDirectory()
        let store = FakeStore()
        let manager = makeManager(dir, store: store)
        store.projects[UUID()] = makeProject()
        TestHelper.cleanupTempDirectory(dir)

        for round in 1...3 {
            manager.saveAllToCache()
            XCTAssertTrue(
                TestHelper.waitFor({ manager.lastSaveResult != nil }, timeout: 5),
                "第 \(round) 次失败都应可观察"
            )
            XCTAssertEqual(manager.lastSaveResult, .directoryUnavailable(dir))
            XCTAssertEqual(manager.saveAttemptCount, round, "每次调度都应该真的尝试过落盘")
            manager.cancelPendingSave()
        }
    }

    func testSuccessAfterFailureClearsStaleError() {
        let dir = makeTempDirectory()
        let store = FakeStore()
        let manager = makeManager(dir, store: store)
        store.projects[UUID()] = makeProject()

        TestHelper.cleanupTempDirectory(dir)
        manager.saveAllToCache()
        XCTAssertTrue(TestHelper.waitFor({ manager.lastSaveResult != nil }, timeout: 5))

        // 目录恢复之后，下一次保存应清掉上一次的失败记录。
        XCTAssertNoThrow(try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true))
        assertSucceeded(manager.flushPendingSave())
        XCTAssertNil(manager.lastSaveResult, "成功后必须清掉旧的失败记录")
    }

    func testNoWritesBypassInjectedStorage() throws {
        let dir = makeTempDirectory()
        let store = FakeStore()
        let manager = makeManager(dir, store: store)
        let project = makeProject(name: "isolated", path: "/tmp/isolated")
        store.projects[project.id] = project

        manager.saveAllToCache()
        assertSucceeded(manager.flushPendingSave())

        // 所有写入都必须落在注入目录里；这里只断言该目录拿到了快照，
        // 真实用户目录由「不构造 TagStorage() / TagManager()」保证不被触碰。
        let data = try Data(contentsOf: dir.appendingPathComponent("projects.json"))
        let decoded = try JSONDecoder().decode([Project].self, from: data)
        XCTAssertEqual(decoded.map(\.id), [project.id])
    }

    // MARK: - TagManager 的整条保存链（统一存储 + projects.json）

    func testTagManagerSaveAfterTempDirectoryRemovalFailsQuietly() {
        let dir = makeTempDirectory()
        let manager = makeTagManager(dir)

        assertSucceeded(manager.flushPendingSave(), "前提：目录存在时统一存储能落盘")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("app_state.json").path),
            "flush 应同时写出 app_state.json"
        )

        TestHelper.cleanupTempDirectory(dir)
        let attemptsBefore = manager.saveAttemptCount

        manager.saveAll()
        XCTAssertTrue(
            TestHelper.waitFor({ manager.saveAttemptCount > attemptsBefore }, timeout: 5),
            "删除目录后，1 秒防抖保存必须真的被唤醒一次"
        )
        XCTAssertEqual(manager.lastSaveError, .directoryUnavailable(dir))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path),
                       "失败路径不能重建临时目录")
    }

    func testTagManagerDebouncedSaveSchedulesFromBackgroundThread() {
        let dir = makeTempDirectory()
        let manager = makeTagManager(dir)
        let attemptsBefore = manager.saveAttemptCount

        let scheduled = expectation(description: "后台线程调度 TagManager 保存")
        DispatchQueue.global(qos: .utility).async {
            manager.saveAll()
            scheduled.fulfill()
        }
        wait(for: [scheduled], timeout: 5)

        // 旧实现把 Timer 挂在调用线程的 RunLoop 上：后台线程没有 RunLoop，
        // 防抖回调永远不会来，保存被静默丢掉。这里断言它真的执行过。
        XCTAssertTrue(
            TestHelper.waitFor({ manager.saveAttemptCount > attemptsBefore }, timeout: 5),
            "后台队列调度的 TagManager 防抖保存也必须真的执行"
        )
        XCTAssertNil(manager.lastSaveError, "目录仍存在，这次保存不应失败")
    }

    func testTagManagerRapidSavesCollapseIntoOneWrite() {
        let dir = makeTempDirectory()
        let manager = makeTagManager(dir)
        let attemptsBefore = manager.saveAttemptCount

        for _ in 0..<10 {
            manager.saveAll()
        }
        XCTAssertTrue(
            TestHelper.waitFor({ manager.saveAttemptCount > attemptsBefore }, timeout: 5),
            "合并窗口结束后应落盘一次"
        )
        _ = TestHelper.waitFor({ false }, timeout: 1)
        XCTAssertEqual(manager.saveAttemptCount - attemptsBefore, 1, "连续调用应合并成一次保存")
    }

    func testTagManagerCancelPendingSaveDoesNotWrite() {
        let dir = makeTempDirectory()
        let manager = makeTagManager(dir)
        let attemptsBefore = manager.saveAttemptCount

        manager.saveAll()
        manager.cancelPendingSave()
        manager.drainPendingWrites()

        _ = TestHelper.waitFor({ false }, timeout: 1.6)
        XCTAssertEqual(manager.saveAttemptCount, attemptsBefore, "取消后不应再保存")
    }
}

// MARK: - Result 便捷断言

private extension Result where Failure == LocalPersistenceError {
    var failureError: LocalPersistenceError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

extension XCTestCase {
    /// `Result<Void, _>` 不能直接用 XCTAssertEqual 比较，这里按结果分支断言。
    func assertSucceeded(
        _ result: Result<Void, LocalPersistenceError>,
        _ message: String = "写盘应当成功",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .failure(let error) = result {
            XCTFail("\(message)：\(error.localizedDescription)", file: file, line: line)
        }
    }
}
