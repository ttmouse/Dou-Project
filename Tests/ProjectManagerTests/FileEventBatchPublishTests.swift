import XCTest
@testable import ProjectManager

/// 文件事件状态发布的回归护栏（审计后续 #2：合并文件事件的状态发布）
///
/// 症状背景：FSEvents 每 0.8s 会把一批变更路径交给 `DirectoryWatcher`，
/// 旧实现命中的每个项目都单独写一次 `@Published var projects` —— 每次写入
/// 都会复制整本字典并同步通知观察者，列表随后按项目数重复重建索引与筛选。
///
/// 本文件锁住三件事：
///   1. 一批事件只有一次发布，相同批次重复到达不发布；
///   2. 合并以「当前字典」为准 —— 保留事件排队期间用户改过的字段，不复活已删项目；
///   3. 排序缓存跟着批次一次更新，活动时间仍落在正确位置。
///
/// 只使用注入的临时存储（`TagStorage(appSupportURL:)`），不碰真实用户数据。
final class FileEventBatchPublishTests: XCTestCase {

    // MARK: - 测试替身

    private final class CountingStore: ProjectOperationDelegate {
        var projects: [UUID: Project] = [:] {
            didSet { publicationCount += 1 }
        }
        private(set) var publicationCount = 0
        var allTags: Set<String> = []
        private(set) var invalidateCount = 0
        private(set) var notifyCount = 0

        func invalidateTagUsageCache() { invalidateCount += 1 }
        func notifyProjectsChanged() { notifyCount += 1 }
    }

    // MARK: - 夹具

    private var tempDirs: [URL] = []
    private var storage: TagStorage!
    private var store: CountingStore!
    private var sorter: ProjectSortManager!
    private var manager: ProjectOperationManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let supportDir = TestHelper.createTempDirectory()
        tempDirs.append(supportDir)
        storage = TagStorage(appSupportURL: supportDir)
        store = CountingStore()
        sorter = ProjectSortManager()
        manager = ProjectOperationManager(delegate: store, sortDelegate: sorter, storage: storage)
    }

    override func tearDown() {
        tempDirs.forEach(TestHelper.cleanupTempDirectory)
        tempDirs.removeAll()
        super.tearDown()
    }

    /// 事件风暴的核心场景：一批事件命中很多项目，期间用户还改了一个、删了一个。
    func testFileEventStormPublishesOnceAndKeepsLiveEdits() {
        var projects = (0..<200).map { index in
            makeProject(name: "storm\(index)", path: "/tmp/storm/storm\(index)")
        }
        // 用户此前配置过的启动命令，事件批次不得覆盖。
        projects[0] = makeProject(
            name: "storm0", path: "/tmp/storm/storm0", startupCommand: "npm run dev"
        )
        store.projects = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        sorter.updateSortedProjects(projects)

        // 事件已排队但还没落到主线程：用户此时改标签、删项目。
        let edited = projects[0]
        let editedLive = edited.copyWith(tags: ["用户刚改的标签"])
        store.projects[edited.id] = editedLive
        let deleted = projects[1]
        store.projects.removeValue(forKey: deleted.id)

        let hitIDs = Set(projects.map(\.id))
        let publicationsBefore = store.publicationCount
        let notifyBefore = store.notifyCount
        let activityAt = Date()

        let start = ProcessInfo.processInfo.systemUptime
        let changed = manager.applyActivityBatch(hitIDs, at: activityAt)
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        FileHandle.standardError.write(
            Data("PERF file-event batch 200 projects: \(elapsed) ms, published \(changed)\n".utf8)
        )

        XCTAssertEqual(store.publicationCount - publicationsBefore, 1, "一批事件只能发布一次项目状态")
        XCTAssertEqual(store.notifyCount - notifyBefore, 1, "整批只有一次变更通知，不随项目数增长")
        XCTAssertEqual(changed, 199, "被删掉的项目不计入本批；其余 199 个都应更新活动时间")

        // 保留用户在事件排队期间改过的字段，而不是覆盖成事件发生前的快照。
        XCTAssertEqual(store.projects[edited.id]?.tags, ["用户刚改的标签"])
        XCTAssertEqual(store.projects[edited.id]?.startupCommand, "npm run dev")
        XCTAssertEqual(store.projects[edited.id]?.activityAt, activityAt)

        // 不复活已删项目。
        XCTAssertNil(store.projects[deleted.id], "已删除的项目不能被事件批次的旧快照复活")
        XCTAssertEqual(store.projects.count, 199)
    }

    func testRepeatedIdenticalActivityBatchPublishesNothing() {
        let project = makeProject(name: "quiet", path: "/tmp/quiet")
        store.projects = [project.id: project]
        sorter.updateSortedProjects([project])

        let activityAt = Date()
        XCTAssertEqual(manager.applyActivityBatch([project.id], at: activityAt), 1)

        let publicationsAfterFirst = store.publicationCount
        XCTAssertEqual(manager.applyActivityBatch([project.id], at: activityAt), 0,
                       "相同活动时间不应再发布")
        XCTAssertEqual(store.publicationCount, publicationsAfterFirst, "相同批次不发布，视图不重算")
    }

    /// 对照：旧的逐项写字典方式在同一批数据上会发布 N 次。
    /// 这条测试记录「为什么要批处理」，防止有人把批量路径改回逐项赋值。
    func testPerProjectWritesPublishOncePerItemSoBatchingIsRequired() {
        let projects = (0..<20).map { index in
            makeProject(name: "legacy\(index)", path: "/tmp/legacy/legacy\(index)")
        }
        store.projects = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        sorter.updateSortedProjects(projects)

        let before = store.publicationCount
        for var project in projects {
            project.activityAt = Date()
            store.projects[project.id] = project
        }
        XCTAssertEqual(store.publicationCount - before, projects.count,
                       "逐项写字典必然按项目数发布 —— 这正是本卡要消除的成本")

        let batchStore = CountingStore()
        batchStore.projects = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let batchSorter = ProjectSortManager()
        batchSorter.updateSortedProjects(projects)
        let batchManager = ProjectOperationManager(
            delegate: batchStore, sortDelegate: batchSorter, storage: storage
        )
        let batchBefore = batchStore.publicationCount
        batchManager.applyActivityBatch(Set(projects.map(\.id)), at: Date())
        XCTAssertEqual(batchStore.publicationCount - batchBefore, 1, "批量路径整批只发布一次")
    }

    func testActivityBatchSkipsTagIndexRebuild() {
        let project = makeProject(name: "tagless", path: "/tmp/tagless", tags: ["a"])
        store.projects = [project.id: project]
        sorter.updateSortedProjects([project])

        let invalidatesBefore = store.invalidateCount
        manager.applyActivityBatch([project.id], at: Date())
        XCTAssertEqual(store.invalidateCount, invalidatesBefore,
                       "活动时间不影响标签归属，不应触发标签索引失效")
    }

    func testSortedOrderReflectsBatchedActivityOnce() {
        let old = makeProject(
            name: "old", path: "/tmp/old", activityAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeProject(
            name: "newer", path: "/tmp/newer", activityAt: Date(timeIntervalSince1970: 200)
        )
        store.projects = [old.id: old, newer.id: newer]
        sorter.updateSortedProjects([old, newer])
        sorter.setSortCriteria(.lastModified, ascending: false)
        XCTAssertEqual(sorter.getSortedProjects().map(\.name), ["newer", "old"])

        let bump = Date(timeIntervalSince1970: 300)
        manager.applyActivityBatch([old.id], at: bump)

        XCTAssertEqual(sorter.getSortedProjects().map(\.name), ["old", "newer"],
                       "活动时间是排序键，批次发布后排序缓存必须落在正确位置")
        XCTAssertEqual(store.projects[old.id]?.activityAt, bump)
    }

    func testIdenticalBatchUpdatePublishesNothing() {
        let project = makeProject(name: "same", path: "/tmp/same")
        store.projects = [project.id: project]
        sorter.updateSortedProjects([project])

        let before = store.publicationCount
        manager.updateProjects([project])
        XCTAssertEqual(store.publicationCount, before, "内容相同的批次不应发布")
    }

    func testBatchRemovalPublishesOnceAndClearsSortedList() {
        let a = makeProject(name: "a", path: "/tmp/dir/a")
        let b = makeProject(name: "b", path: "/tmp/dir/b")
        store.projects = [a.id: a, b.id: b]
        sorter.updateSortedProjects([a, b])

        let before = store.publicationCount
        let removed = manager.applyProjectBatch(updates: [], removals: [a.id, UUID()])

        XCTAssertEqual(removed, 1, "只有仍存在的项目算一次变化")
        XCTAssertEqual(store.publicationCount - before, 1, "整批删除只发布一次")
        XCTAssertNil(store.projects[a.id])
        XCTAssertEqual(sorter.getSortedProjects().map(\.id), [b.id], "排序缓存同步移除")
    }

    // MARK: - 纯合并语义

    func testMergeDropsRemovalsForMissingProjectsAndKeepsOthers() {
        let kept = makeProject(name: "kept", path: "/tmp/kept")
        var snapshot: [UUID: Project] = [kept.id: kept]
        let ghost = UUID()
        let edited = kept.copyWith(tags: ["x"])

        let changed = ProjectBatchMerge.apply(
            into: &snapshot,
            change: ProjectBatchChange(updates: [kept.id: edited], removals: [ghost])
        )

        XCTAssertEqual(changed, 1)
        XCTAssertEqual(snapshot[kept.id]?.tags, ["x"])
        XCTAssertEqual(snapshot.count, 1, "不存在的项目不会被批次重新加入")
    }

    func testMergeCountsRemovalAndUpdateOfSameProjectOnce() {
        let project = makeProject(name: "both", path: "/tmp/both")
        var snapshot: [UUID: Project] = [project.id: project]

        let changed = ProjectBatchMerge.apply(
            into: &snapshot,
            change: ProjectBatchChange(updates: [project.id: project], removals: [project.id])
        )

        XCTAssertEqual(changed, 1, "先删后写只算一次变化，避免重复发布")
        XCTAssertNil(snapshot[project.id], "同一批次里删除优先于更新")
    }

    // MARK: - 标签倒排索引的批次维护

    func testTagIndexMovesProjectsBetweenTagsInOneBatch() {
        let a = makeProject(name: "a", path: "/tmp/a", tags: ["old"])
        let b = makeProject(name: "b", path: "/tmp/b", tags: ["old"])
        let unchanged = makeProject(name: "c", path: "/tmp/c", tags: ["keep"])
        var index: [String: Set<UUID>] = [
            "old": [a.id, b.id],
            "keep": [unchanged.id],
        ]

        ProjectTagIndexLogic.apply(
            to: &index,
            change: ProjectBatchChange(updates: [
                a.id: a.copyWith(tags: ["new"]),
                b.id: b.copyWith(tags: ["new"]),
                unchanged.id: unchanged,
            ]),
            previous: [a.id: a, b.id: b, unchanged.id: unchanged]
        )

        XCTAssertEqual(index["old"], nil, "最后一个使用者离开后标签键应清掉，不留空集合")
        XCTAssertEqual(index["new"], [a.id, b.id], "整批换标签只写一次")
        XCTAssertEqual(index["keep"], [unchanged.id], "标签没变的项目不参与索引写入")
    }

    func testTagIndexRemovesDeletedProjects() {
        let a = makeProject(name: "a", path: "/tmp/a", tags: ["x", "y"])
        var index: [String: Set<UUID>] = ["x": [a.id], "y": [a.id]]

        ProjectTagIndexLogic.apply(
            to: &index,
            change: ProjectBatchChange(removals: [a.id]),
            previous: [a.id: a]
        )

        XCTAssertTrue(index.isEmpty, "删除项目必须清掉它在所有标签下的引用")
    }

    func testTagIndexIgnoresMetadataOnlyBatch() {
        let project = makeProject(name: "meta", path: "/tmp/meta", tags: ["t"])
        var index: [String: Set<UUID>] = ["t": [project.id]]
        let bumped = project.copyWith(activityAt: Date(timeIntervalSince1970: 42))

        ProjectTagIndexLogic.apply(
            to: &index,
            change: ProjectBatchChange(updates: [project.id: bumped], removals: [], affectsTags: false),
            previous: [project.id: project]
        )

        XCTAssertEqual(index["t"], [project.id], "仅元数据变化不改索引")
    }

    // MARK: - 辅助

    private func makeProject(
        name: String,
        path: String,
        tags: Set<String> = [],
        startupCommand: String? = nil,
        activityAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Project {
        Project(
            id: UUID(),
            name: name,
            path: path,
            tags: tags,
            mtime: activityAt,
            activityAt: activityAt,
            size: 0,
            checksum: "sha256:test",
            git_commits: 0,
            git_last_commit: .distantPast,
            git_daily: nil,
            startupCommand: startupCommand,
            customPort: nil,
            created: activityAt,
            checked: activityAt
        )
    }
}
