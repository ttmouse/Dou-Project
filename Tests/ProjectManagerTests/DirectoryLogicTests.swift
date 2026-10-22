// 目录归属逻辑测试 - 参照 GitHub 仓库计数最佳实践：
// 互斥归属（一个项目只归一个目录）、计数即结果（徽章数 == 实际展示数）、路径组件边界匹配

import XCTest
import Foundation
@testable import ProjectManager

final class DirectoryLogicTests: XCTestCase {

    // MARK: - 组件边界匹配（旧 hasPrefix 的误匹配 bug 回归测试）

    func testIsSubpathMatchesRealChildren() {
        XCTAssertTrue(DirectoryLogic.isSubpath("/Users/d/Projects/alpha", of: "/Users/d/Projects"))
        XCTAssertTrue(DirectoryLogic.isSubpath("/Users/d/Projects/alpha/deep/leaf", of: "/Users/d/Projects"))
        XCTAssertTrue(DirectoryLogic.isSubpath("/Users/d/Projects", of: "/Users/d/Projects"),
                      "目录自身作为项目也应归属（GitHub 中的嵌套仓库场景）")
    }

    func testIsSubpathRejectsPrefixLookalikes() {
        // 旧实现 `path.hasPrefix(dir)` 会把下面这些误判为目录内项目
        XCTAssertFalse(DirectoryLogic.isSubpath("/Users/d/ProjectsFoo/alpha", of: "/Users/d/Projects"))
        XCTAssertFalse(DirectoryLogic.isSubpath("/Users/d/Projects-archive/alpha", of: "/Users/d/Projects"))
        XCTAssertFalse(DirectoryLogic.isSubpath("/Users/d/ProjectsX", of: "/Users/d/Projects"))
        XCTAssertFalse(DirectoryLogic.isSubpath("/Users/d/Projects2/alpha", of: "/Users/d/Projects"))
    }

    // MARK: - 路径规范化

    func testTrailingSlashNormalization() {
        XCTAssertTrue(DirectoryLogic.isSubpath("/Users/d/Projects/alpha", of: "/Users/d/Projects/"))
        XCTAssertTrue(DirectoryLogic.isSubpath("/Users/d/Projects/alpha", of: "/Users/d/Projects///"))
        XCTAssertEqual(DirectoryLogic.standardizedPath("/a/b///"), "/a/b")
        XCTAssertEqual(DirectoryLogic.standardizedPath("/"), "/", "根路径不能去掉斜杠")
    }

    func testTildeExpansion() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertTrue(DirectoryLogic.isSubpath(home + "/Work/x", of: "~/Work"))
        XCTAssertEqual(DirectoryLogic.standardizedPath("~/Work"), home + "/Work")
    }

    func testRootDirectoryContainsEverything() {
        XCTAssertTrue(DirectoryLogic.isSubpath("/anything/at/all", of: "/"))
    }

    // MARK: - 互斥归属（父子目录不重复计数）

    func testParentChildDirectoriesAreExclusive() {
        let paths = [
            "/Users/d/Projects/a",
            "/Users/d/Projects/deep/b",
            "/Users/d/Projects/deep/deeper/c",
        ]
        let assignment = DirectoryLogic.assign(
            paths: paths,
            directories: ["/Users/d/Projects", "/Users/d/Projects/deep"]
        )

        // 父目录只统计直属项目，子目录项目归到最深匹配
        XCTAssertEqual(assignment.count(for: "/Users/d/Projects"), 1, "父目录仅直属 a")
        XCTAssertEqual(assignment.count(for: "/Users/d/Projects/deep"), 2, "deep 下 b 和 deeper/c 都归 deep")
        XCTAssertTrue(assignment.byDirectory["/Users/d/Projects/deep"]!.contains("/Users/d/Projects/deep/deeper/c"))
    }

    func testCountsAlwaysSumToTotal() {
        // 核心不变量：Σ目录计数 + 未分类 == 全部项目数
        let allPaths = [
            "/Users/d/Projects/a",
            "/Users/d/Projects/deep/b",
            "/Users/d/Own/c",
            "/tmp/scratch/d",
        ]
        let assignment = DirectoryLogic.assign(
            paths: allPaths,
            directories: ["/Users/d/Projects", "/Users/d/Projects/deep", "/Users/d/Own"]
        )

        let sum = assignment.byDirectory.values.reduce(0) { $0 + $1.count } + assignment.unassigned.count
        XCTAssertEqual(sum, allPaths.count, "Σ目录 + 未分类 必须等于全部项目数")
        XCTAssertEqual(assignment.unassigned, Set(["/tmp/scratch/d"]), "无匹配目录的项目进入未分类")
    }

    func testDuplicateDirectoriesAreDeduplicated() {
        let assignment = DirectoryLogic.assign(
            paths: ["/a/x", "/a/y"],
            directories: ["/a", "/a"]
        )
        XCTAssertEqual(assignment.count(for: "/a"), 2, "重复监视目录不重复计数")
    }

    func testEmptyInputs() {
        let empty = DirectoryLogic.assign(paths: [], directories: ["/a"])
        XCTAssertEqual(empty.count(for: "/a"), 0)
        XCTAssertTrue(empty.unassigned.isEmpty)

        let noDirs = DirectoryLogic.assign(paths: ["/a/b"], directories: [])
        XCTAssertEqual(noDirs.unassigned, Set(["/a/b"]))
    }

    func testUnassignedKeyIsStable() {
        XCTAssertEqual(DirectoryLogic.unassignedKey, "__unclassified__")
    }
}

// MARK: - 通过 TagManager 的端到端一致性（侧边栏计数 == 列表筛选结果）

extension DirectoryLogicTests {
    /// ⚠️ 默认跳过：`TagManager()` 是生产组合根，它会
    ///   1) 从真实目录 `~/Library/Application Support/com.projectmanager` 加载 app_state/projects.json
    ///      （本机实测 348 个真实项目，断言因此失真）；
    ///   2) 在 `initializeTagColors()` 里 `saveAll(force: true)` 写回真实用户数据；
    ///   3) 开始监视用户真实目录。
    /// 测试不应构造生产组合根。恢复条件：TagManager 支持注入 storage/appState
    /// （见 docs/performance-report.md「A 阶段：测试基建」），之后就绪后可去掉这个开关。
    func testTagManagerDirectoryCountMatchesFilterResult() throws {
        guard ProcessInfo.processInfo.environment["RUN_TAGMANAGER_E2E"] != nil else {
            throw XCTSkip("需要 TagManager 存储注入点，当前会读写真实用户数据")
        }

        // Given: 监视目录与项目（含前缀相似目录、手动添加项目）
        let manager = TagManager()
        manager.watchedDirectories = [
            "/Users/d/Projects",
            "/Users/d/Projects/deep",
        ]

        func register(_ path: String) {
            let project = Project(
                id: UUID(),
                name: (path as NSString).lastPathComponent,
                path: path,
                lastModified: Date()
            )
            manager.projects[project.id] = project
        }
        register("/Users/d/Projects/a")
        register("/Users/d/Projects/deep/b")
        register("/Users/d/ProjectsFoo/fake")      // 前缀相似，不应计入 Projects
        register("/Users/d/Own/manual")            // 手动添加，未分类

        // When: 侧边栏徽章计数 与 列表筛选 使用同一逻辑
        let assignment = manager.directoryAssignment()
        let projectsDirCount = manager.projects(in: "/Users/d/Projects").count

        // Then: 计数即结果 —— 徽章数 == 点击后展示的行数
        XCTAssertEqual(assignment.count(for: "/Users/d/Projects"), projectsDirCount)
        XCTAssertEqual(assignment.count(for: "/Users/d/Projects"), 1, "Projects 只含 a，ProjectsFoo 不应误计入")
        XCTAssertEqual(assignment.count(for: "/Users/d/Projects/deep"), 1, "deep 只含 b")

        // Then: 未分类由手动添加的项目构成，且全部 == Σ + 未分类
        XCTAssertEqual(assignment.unassigned, Set(["/Users/d/Own/manual"]))
        let total = assignment.byDirectory.values.reduce(0) { $0 + $1.count } + assignment.unassigned.count
        XCTAssertEqual(total, manager.projects.count, "Σ目录 + 未分类 == 全部")
        XCTAssertEqual(manager.unassignedProjects().count, 1)
    }
}