import XCTest
@testable import ProjectManager

/// Project ↔ ProjectData 转换契约测试
///
/// 背景：审计后续 #1「收敛 Project / ProjectData 双份状态」。在决定唯一状态模型之前，
/// 先用测试把两份模型之间的**可逆性边界**钉死，避免任何一侧悄悄改动字段语义。
///
/// 差异说明见 `docs/project-projectdata-dual-state-2026-10-22.md`：
/// - Project 有 `activityAt`（排序/日期筛选的键），ProjectData 没有；
/// - Project 的 `notes` 是读磁盘的计算属性，ProjectData 的 `notes` 是一份内存快照；
/// - 只有 Project 参与 projects.json 持久化，ProjectData 只在内存中流动。
///
/// 本文件区分两类断言：
/// 1. `契约`：必须永远成立的字段映射；
/// 2. `已知缺口`：当前实现会丢字段，先用测试固定现状，修复时这些断言应随之翻转。
final class ProjectDataConversionContractTests: XCTestCase {

    /// 每个字段都给互不相同的值，便于发现「复制时漏字段/串字段」。
    private func makeFullProject(
        path: String = "/tmp/contract-fixture",
        activityAt: Date = Date(timeIntervalSince1970: 1_700_000_777)
    ) -> Project {
        Project(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "契约项目",
            path: path,
            tags: ["swift", "macos"],
            mtime: Date(timeIntervalSince1970: 1_600_000_001),
            activityAt: activityAt,
            size: 4096,
            checksum: "sha256:deadbeef",
            git_commits: 42,
            git_last_commit: Date(timeIntervalSince1970: 1_650_000_002),
            git_daily: "2026-10-21:3,2026-10-20:5",
            startupCommand: "pnpm dev",
            customPort: 5173,
            created: Date(timeIntervalSince1970: 1_500_000_003),
            checked: Date(timeIntervalSince1970: 1_700_000_004)
        )
    }

    // MARK: - 契约：Project → ProjectData 的字段映射

    func testProjectToProjectDataCopiesAllSharedStoredFields() {
        let project = makeFullProject()
        let data = project.toProjectData()

        XCTAssertEqual(data.id, project.id)
        XCTAssertEqual(data.name, project.name)
        XCTAssertEqual(data.path, project.path)
        XCTAssertEqual(data.tags, project.tags)
        XCTAssertEqual(data.mtime, project.mtime)
        XCTAssertEqual(data.size, project.size)
        XCTAssertEqual(data.checksum, project.checksum)
        XCTAssertEqual(data.git_commits, project.git_commits)
        XCTAssertEqual(data.git_last_commit, project.git_last_commit)
        XCTAssertEqual(data.git_daily, project.git_daily)
        XCTAssertEqual(data.startupCommand, project.startupCommand)
        XCTAssertEqual(data.customPort, project.customPort)
        XCTAssertEqual(data.created, project.created)
        XCTAssertEqual(data.checked, project.checked)
    }

    func testLegacyAccessorsAgreeAcrossBothModels() {
        let project = makeFullProject()
        let data = project.toProjectData()

        XCTAssertEqual(data.lastModified, project.lastModified)
        XCTAssertEqual(data.gitInfo?.commitCount, project.gitInfo?.commitCount)
        XCTAssertEqual(data.gitInfo?.lastCommitDate, project.gitInfo?.lastCommitDate)
        XCTAssertEqual(data.fileSystemInfo.size, project.fileSystemInfo.size)
        XCTAssertEqual(data.fileSystemInfo.checksum, project.fileSystemInfo.checksum)
        XCTAssertEqual(data.fileSystemInfo.lastCheckTime, project.fileSystemInfo.lastCheckTime)
        XCTAssertEqual(data.fileSystemInfo.modificationDate, project.fileSystemInfo.modificationDate)
    }

    func testGitInfoIsNilOnBothSidesWithoutCommits() {
        let project = ProjectFixtures.make(gitCommits: 0)
        let data = project.toProjectData()
        XCTAssertNil(project.gitInfo)
        XCTAssertNil(data.gitInfo)
    }

    // MARK: - 已知缺口 1：activityAt 无对应字段

    /// 当前实现：fromProjectData 无法回填 activityAt，Project 的初始化器退化为 mtime。
    /// 后果：只要走过一次 ProjectData（标签操作、刷新、重命名），列表会按 mtime 重排，
    /// 日期筛选也会把最近有文件活动但 mtime 较旧的项目过滤掉。
    func testRoundTripCollapsesActivityAtToMtime() {
        let mtime = Date(timeIntervalSince1970: 1_600_000_001)
        let activity = Date(timeIntervalSince1970: 1_700_000_777)
        XCTAssertNotEqual(mtime, activity)

        let project = makeFullProject(activityAt: activity)
        let roundTripped = Project.fromProjectData(project.toProjectData())

        XCTAssertEqual(roundTripped.mtime, mtime)
        XCTAssertEqual(roundTripped.activityAt, mtime, "已知缺口：ProjectData 不承载 activityAt")
        XCTAssertNotEqual(roundTripped.activityAt, activity)
        XCTAssertNotEqual(roundTripped, project, "因此往返后对象不再相等")
    }

    // MARK: - 已知缺口 2：notes 的一侧是磁盘、一侧是内存

    /// Project.notes 每次访问都同步读 PROJECT_NOTES.md；ProjectData.notes 是转换瞬间的快照。
    func testProjectDataCapturesNotesSnapshotFromDisk() throws {
        let directory = TestHelper.createTempDirectory()
        defer { TestHelper.cleanupTempDirectory(directory) }
        let notes = "# 备注\n- 契约测试写入"
        XCTAssertTrue(ProjectNotesManager.writeNotes(notes, to: directory.path))

        let project = makeFullProject(path: directory.path)
        let data = project.toProjectData()
        XCTAssertEqual(data.notes, notes)

        // 磁盘变化不会影响已经取到的 ProjectData 快照，但会影响 Project.notes
        XCTAssertTrue(ProjectNotesManager.writeNotes("改过了", to: directory.path))
        XCTAssertEqual(data.notes, notes, "ProjectData 冻结为快照")
        XCTAssertEqual(project.notes, "改过了", "Project 每次读取实时磁盘")
    }

    /// ProjectData → Project → ProjectData 会把 notes 丢掉，除非磁盘上仍有文件。
    func testProjectDataRoundTripDropsInMemoryNotesWithoutFile() {
        let data = ProjectData(
            id: UUID(),
            name: "无备注文件",
            path: "/tmp/does-not-exist-\(UUID().uuidString)",
            tags: [],
            notes: "只在内存里的备注",
            mtime: Date(timeIntervalSince1970: 1_600_000_000),
            size: 1,
            checksum: "c",
            git_commits: 0,
            git_last_commit: .distantPast,
            created: Date(timeIntervalSince1970: 1_500_000_000),
            checked: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let project = Project.fromProjectData(data)
        XCTAssertNil(project.notes, "Project.notes 不读内存，只读磁盘")

        let back = project.toProjectData()
        XCTAssertNil(back.notes, "已知缺口：内存 notes 经一次往返即丢失")
        XCTAssertEqual(back.id, data.id)
        XCTAssertEqual(back.git_commits, 0)
        XCTAssertEqual(back.git_last_commit, .distantPast)
    }

    /// ProjectData 的 Equatable 包含 notes，因此同一项目的相等性依赖磁盘内容；
    /// Project 的 Equatable 明确排除 notes。收敛时必须显式选定其中一种语义。
    func testNotesParticipateInProjectDataEqualityButNotProjectEquality() throws {
        let directory = TestHelper.createTempDirectory()
        defer { TestHelper.cleanupTempDirectory(directory) }

        let project = makeFullProject(path: directory.path)
        XCTAssertEqual(project, project, "Project 相等性不受 notes 影响")

        let withoutNotes = project.toProjectData()
        XCTAssertTrue(ProjectNotesManager.writeNotes("后来的内容", to: directory.path))
        let withNotes = project.toProjectData()

        XCTAssertEqual(withoutNotes.id, withNotes.id)
        XCTAssertNotEqual(withoutNotes, withNotes, "ProjectData 相等性随磁盘备注变化")
    }

    // MARK: - 契约：元数据齐全时转换不得触碰磁盘

    func testConversionDoesNotTouchDiskWhenMetadataComplete() {
        // 路径不存在：一旦转换内部回落到文件系统 / git 探测，就会拿到 Date()/0 而不是夹具值。
        let project = makeFullProject(path: "/tmp/never-created-\(UUID().uuidString)")
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<200 {
            _ = Project.fromProjectData(project.toProjectData())
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print("PERF Project↔ProjectData 往返 200 次: \(elapsed * 1000) ms")

        let roundTripped = Project.fromProjectData(project.toProjectData())
        XCTAssertEqual(roundTripped.size, 4096, "不得因路径不存在而把 size 归零")
        XCTAssertEqual(roundTripped.checksum, "sha256:deadbeef")
        XCTAssertEqual(roundTripped.git_commits, 42, "不得因路径不存在而重新探测 git")
        XCTAssertEqual(roundTripped.startupCommand, "pnpm dev")
        XCTAssertEqual(roundTripped.customPort, 5173)
        XCTAssertEqual(roundTripped.created, project.created)
        XCTAssertEqual(roundTripped.checked, project.checked)
    }

    // MARK: - 已知缺口 3：BusinessLogic 的标签复制走旧嵌套初始化器

    /// TagLogic 增删标签用 `ProjectData(lastModified:tags:notes:gitInfo:fileSystemInfo:)`，
    /// 该初始化器只认旧嵌套结构：git_daily / startupCommand / customPort 被置为 nil，
    /// created 被改写成 checked。经 TagManager 回写 projects.json 后这些值就永久丢失。
    func testAddTagPreservesFieldsOutsideTags() {
        let project = makeFullProject()
        let data = project.toProjectData()

        let tagged = TagLogic.addTagToProject(data, tag: "新标签")

        XCTAssertEqual(tagged.tags, project.tags.union(["新标签"]), "标签本身必须生效")
        XCTAssertEqual(tagged.id, project.id)
        XCTAssertEqual(tagged.name, project.name)
        XCTAssertEqual(tagged.path, project.path)
        XCTAssertEqual(tagged.mtime, project.mtime)
        XCTAssertEqual(tagged.size, project.size)
        XCTAssertEqual(tagged.checksum, project.checksum)
        XCTAssertEqual(tagged.git_commits, project.git_commits)
        XCTAssertEqual(tagged.git_last_commit, project.git_last_commit)
        XCTAssertEqual(tagged.git_daily, project.git_daily, "git_daily 决定热力图，不能被标签操作清空")
        XCTAssertEqual(tagged.startupCommand, project.startupCommand)
        XCTAssertEqual(tagged.customPort, project.customPort)
        XCTAssertEqual(tagged.created, project.created, "首次发现时间不能被改写")
        XCTAssertEqual(tagged.checked, project.checked)
    }

    func testRemoveTagPreservesFieldsOutsideTags() {
        let project = makeFullProject()
        let data = project.toProjectData()

        let untagged = TagLogic.removeTagFromProject(data, tag: "swift")

        XCTAssertEqual(untagged.tags, project.tags.subtracting(["swift"]))
        XCTAssertEqual(untagged.git_daily, project.git_daily)
        XCTAssertEqual(untagged.startupCommand, project.startupCommand)
        XCTAssertEqual(untagged.customPort, project.customPort)
        XCTAssertEqual(untagged.created, project.created)
        XCTAssertEqual(untagged.checked, project.checked)
    }

    func testBatchTagUpdatePreservesFieldsOutsideTags() {
        let project = makeFullProject()
        let data = project.toProjectData()

        let updated = ProjectOperations.batchUpdateTags([data], addTag: "批量")

        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].tags, project.tags.union(["批量"]))
        XCTAssertEqual(updated[0].git_daily, project.git_daily)
        XCTAssertEqual(updated[0].startupCommand, project.startupCommand)
        XCTAssertEqual(updated[0].customPort, project.customPort)
        XCTAssertEqual(updated[0].created, project.created)
    }

    /// 标签操作经 TagManager 的往返路径（ProjectData → Project）后，
    /// 写回 projects.json 的字段必须仍然一致——这是数据安全的最后一道闸门。
    func testTagOperationRoundTripKeepsPersistedFieldsIntact() throws {
        let project = makeFullProject()
        let tagged = Project.fromProjectData(TagLogic.addTagToProject(project.toProjectData(), tag: "往返"))

        XCTAssertEqual(tagged.tags, project.tags.union(["往返"]))
        XCTAssertEqual(tagged.git_daily, project.git_daily)
        XCTAssertEqual(tagged.startupCommand, project.startupCommand)
        XCTAssertEqual(tagged.customPort, project.customPort)
        XCTAssertEqual(tagged.created, project.created)
        XCTAssertEqual(tagged.size, project.size)
        XCTAssertEqual(tagged.checksum, project.checksum)

        let encoded = try JSONEncoder().encode([tagged])
        let decoded = try JSONDecoder().decode([Project].self, from: encoded)
        XCTAssertEqual(decoded.first?.git_daily, project.git_daily, "projects.json 落盘后 git_daily 仍在")
        XCTAssertEqual(decoded.first?.startupCommand, project.startupCommand)
        XCTAssertEqual(decoded.first?.customPort, project.customPort)
        XCTAssertEqual(decoded.first?.created, project.created)
    }
}
