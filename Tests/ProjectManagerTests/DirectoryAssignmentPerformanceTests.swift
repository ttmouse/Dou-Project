import XCTest
import Foundation
@testable import ProjectManager

/// 目录归属计算的回归护栏（P1 性能修复）
///
/// 症状背景：侧边栏 `DirectoryListView.body` 每次求值都调用
/// `tagManager.directoryAssignment()`，而旧实现对**每个项目**都
/// 收集全部匹配目录再取最深的一个，且每次比较都要重新规范化路径。
/// 项目数上去后，单次 body 求值就要几十毫秒，搜索时整页重绘被它拖住。
///
/// 现实现把目录预先按深度排序，命中最深目录即可停止。
/// 本文件锁住两件事：
///   1. 归属语义完全不变（互斥归属、组件边界匹配、Σ目录 + 未分类 == 全部）
///   2. 计算成本回到毫秒级（否则说明有人改回了逐项目收集全部候选）
final class DirectoryAssignmentPerformanceTests: XCTestCase {

    // MARK: - 语义护栏

    /// 深度优先：先命中的目录必须是最深的匹配目录
    func testDeepestDirectoryWinsRegardlessOfInputOrder() {
        let directories = [
            "/Users/d/Projects",
            "/Users/d/Projects/deep",
            "/Users/d/Projects/deep/deeper",
        ]
        let paths = [
            "/Users/d/Projects/a",
            "/Users/d/Projects/deep/b",
            "/Users/d/Projects/deep/deeper/c",
        ]

        // 打乱输入顺序，结果必须一致（实现内部按深度排序，不依赖入参顺序）
        let forwards = DirectoryLogic.assign(paths: paths, directories: directories)
        let backwards = DirectoryLogic.assign(paths: paths, directories: directories.reversed())

        XCTAssertEqual(forwards.byDirectory, backwards.byDirectory)
        XCTAssertEqual(forwards.unassigned, backwards.unassigned)
        XCTAssertEqual(forwards.count(for: "/Users/d/Projects"), 1)
        XCTAssertEqual(forwards.count(for: "/Users/d/Projects/deep"), 1)
        XCTAssertEqual(forwards.count(for: "/Users/d/Projects/deep/deeper"), 1)
    }

    /// 同长度目录不可能互相包含，归属必须稳定可复现
    func testSameLengthDirectoriesResolveDeterministically() {
        let paths = ["/a/x", "/b/y"]
        let first = DirectoryLogic.assign(paths: paths, directories: ["/a", "/b"])
        let second = DirectoryLogic.assign(paths: paths, directories: ["/b", "/a"])
        XCTAssertEqual(first.byDirectory, second.byDirectory)
    }

    /// 根目录吃掉一切
    func testRootDirectoryTakesEverything() {
        let assignment = DirectoryLogic.assign(
            paths: ["/x", "/y/z", "/a/b/c"],
            directories: ["/"]
        )
        XCTAssertEqual(assignment.count(for: "/"), 3)
        XCTAssertTrue(assignment.unassigned.isEmpty)
    }

    /// 组件边界：前缀相似的目录不能误吞项目
    func testPrefixLookalikeDirectoriesStaySeparate() {
        let assignment = DirectoryLogic.assign(
            paths: ["/Users/d/ProjectsFoo/x", "/Users/d/Projects/y"],
            directories: ["/Users/d/Projects"]
        )
        XCTAssertEqual(assignment.count(for: "/Users/d/Projects"), 1)
        XCTAssertEqual(assignment.unassigned, Set(["/Users/d/ProjectsFoo/x"]))
    }

    /// 尾部斜杠与 ~ 展开不能影响归属
    func testNormalizationStillAppliesToTildeAndTrailingSlash() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let assignment = DirectoryLogic.assign(
            paths: [home + "/Work/x"],
            directories: ["~/Work/"]
        )
        XCTAssertEqual(assignment.count(for: home + "/Work"), 1)
        XCTAssertTrue(assignment.unassigned.isEmpty)
    }

    // MARK: - 成本护栏

    /// 归属计算必须保持在毫秒级。
    /// 旧实现在 2,000 个项目上是 ~49 ms；这里留足余量，仍能在退化时立刻失败。
    func testAssignmentStaysMillisecondScaleForTwoThousandProjects() {
        let directories = [
            "/Users/d/Projects",
            "/Users/d/Projects/deep",
            "/Users/d/Desktop",
            "/Users/d/Documents",
        ]
        let paths = (0..<2_000).map { index in
            let root = directories[index % directories.count]
            return "\(root)/sub\(index % 50)/project\(index)"
        }

        let start = ProcessInfo.processInfo.systemUptime
        let assignment = DirectoryLogic.assign(paths: paths, directories: directories)
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000

        XCTAssertEqual(assignment.unassigned.count, 0)
        let total = assignment.byDirectory.values.reduce(0) { $0 + $1.count }
            + assignment.unassigned.count
        XCTAssertEqual(total, paths.count, "Σ目录 + 未分类 必须等于全部项目数")

        FileHandle.standardError.write(
            Data("PERF directoryAssignment 2000 projects: \(elapsed) ms\n".utf8)
        )
        XCTAssertLessThan(elapsed, 20, "目录归属计算退化了（本次 \(elapsed) ms）")
    }

    /// 大量目录时同样要保持线性级别的成本
    func testAssignmentStaysFastWithManyDirectories() {
        let directories = (0..<40).map { "/Users/d/Dir\($0)" }
        let paths = (0..<1_000).map { "/Users/d/Dir\($0 % 40)/project\($0)" }

        let start = ProcessInfo.processInfo.systemUptime
        let assignment = DirectoryLogic.assign(paths: paths, directories: directories)
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000

        XCTAssertEqual(assignment.unassigned.count, 0)
        FileHandle.standardError.write(
            Data("PERF directoryAssignment 1000 projects x 40 dirs: \(elapsed) ms\n".utf8)
        )
        XCTAssertLessThan(elapsed, 50, "目录归属计算退化了（本次 \(elapsed) ms）")
    }
}
