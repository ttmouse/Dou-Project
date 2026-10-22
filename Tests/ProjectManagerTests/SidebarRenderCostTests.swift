import Combine
import XCTest
@testable import ProjectManager

/// 侧边栏重绘成本的回归护栏（P1 性能修复）
///
/// 症状背景：搜索时整页重绘，侧边栏的 `DirectoryListView.body` 与
/// `TagListView.tagListContent` 都要重算。两者原本都带
/// O(项目数 × 目录数) / O(标签数 × log 标签数 × 项目数) 的重复计算，
/// 在真实项目规模上单次重绘要几十毫秒。
///
/// 本测试不构造生产 `TagManager`（它会读写真实用户数据），
/// 而是用与生产同构的纯逻辑路径测量：目录归属 + 标签统计 + 标签排序。
final class SidebarRenderCostTests: XCTestCase {

    /// 一次侧边栏重绘要做的全部计算，必须在毫秒级。
    /// 旧实现在同等规模下约 52 ms（3.1 ms 目录归属 + 3.7 ms 标签排序 + 余量）。
    func testSidebarRedrawCostStaysMillisecondScale() {
        let projectCount = 1_000
        let tagCount = 40
        let directories = [
            "/Users/d/Projects",
            "/Users/d/Projects/deep",
            "/Users/d/Desktop",
            "/Users/d/Documents",
        ]
        let paths = (0..<projectCount).map { index in
            let root = directories[index % directories.count]
            return "\(root)/sub\(index % 50)/project\(index)"
        }
        let tags = (0..<tagCount).map { "tag\($0)" }
        let projectData = (0..<projectCount).map { index in
            ProjectFixtures.make(
                name: "Project\(index)",
                path: paths[index],
                tags: Set((0..<3).map { tags[(index + $0 * 7) % tagCount] })
            ).toProjectData()
        }

        let start = ProcessInfo.processInfo.systemUptime

        // 1. DirectoryListView.body -> tagManager.directoryAssignment()
        let assignment = DirectoryLogic.assign(paths: paths, directories: directories)
        // 2. TagListView.tagListContent -> 统计 + 排序
        let statistics = TagLogic.calculateTagUsage(projectData)
        let sorted = TagLogic.sortTagsByUsage(tags, usage: statistics)
        // 3. 侧边栏还要渲染"没有标签"计数
        let untagged = projectData.filter { $0.tags.isEmpty }.count

        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000

        XCTAssertEqual(sorted.count, tagCount)
        XCTAssertEqual(assignment.unassigned.count, 0)
        XCTAssertEqual(untagged, 0)

        FileHandle.standardError.write(
            Data("PERF sidebar redraw cost (\(projectCount) projects, \(tagCount) tags): \(elapsed) ms\n".utf8)
        )
        XCTAssertLessThan(elapsed, 20, "侧边栏重绘成本退化了（本次 \(elapsed) ms）")
    }
}
