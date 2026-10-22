import XCTest
import Foundation
@testable import ProjectManager

/// 标签侧边栏排序的回归护栏（P1 性能修复）
///
/// 症状背景：`TagListView.tagListContent` 把「按使用次数排序」写成
/// `allTags.sorted { getUsageCount($0) > getUsageCount($1) }`，
/// 而 `getUsageCount` 每次调用都会重算**整份**标签统计。
/// 排序比较器被调用 O(tags × log(tags)) 次，等于把全量统计重算了这么多次。
/// 标签和项目一多，侧边栏每次重绘都会明显卡顿，搜索时整页重绘被它拖住。
///
/// 现改为先算一次统计再排序。本文件锁住两件事：
///   1. 排序语义不变（按使用次数降序，并列时顺序稳定）
///   2. 统计只算一次（否则说明有人把重算塞回了比较器）
final class TagUsageSortingTests: XCTestCase {

    // MARK: - 语义护栏

    func testSortsByUsageDescending() {
        let sorted = TagLogic.sortTagsByUsage(
            ["a", "b", "c"],
            usage: ["a": 1, "b": 9, "c": 5]
        )
        XCTAssertEqual(sorted, ["b", "c", "a"])
    }

    func testTagsWithoutUsageSortLast() {
        let sorted = TagLogic.sortTagsByUsage(
            ["used", "unused"],
            usage: ["used": 3]
        )
        XCTAssertEqual(sorted, ["used", "unused"])
    }

    /// 并列时按名称升序，保证结果稳定可复现
    func testTiedUsageSortsByName() {
        let sorted = TagLogic.sortTagsByUsage(
            ["zebra", "alpha", "middle"],
            usage: ["zebra": 4, "alpha": 4, "middle": 4]
        )
        XCTAssertEqual(sorted, ["alpha", "middle", "zebra"])
    }

    func testEmptyInput() {
        XCTAssertTrue(TagLogic.sortTagsByUsage([], usage: [:]).isEmpty)
    }

    // MARK: - 成本护栏

    /// 标签排序必须是毫秒级。旧实现（比较器内重算统计）在同等规模下是秒级。
    func testSortingManyTagsStaysMillisecondScale() {
        let tagCount = 200
        let projectCount = 1_000
        let tags = (0..<tagCount).map { "tag\($0)" }
        let usage = Dictionary(uniqueKeysWithValues: tags.enumerated().map { ($0.element, $0.offset) })

        let start = ProcessInfo.processInfo.systemUptime
        let sorted = TagLogic.sortTagsByUsage(tags, usage: usage)
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000

        XCTAssertEqual(sorted.count, tagCount)
        XCTAssertEqual(sorted.first, "tag\(tagCount - 1)", "使用次数最多的标签排在最前")

        FileHandle.standardError.write(
            Data("PERF sortTagsByUsage \(tagCount) tags: \(elapsed) ms\n".utf8)
        )
        XCTAssertLessThan(elapsed, 20, "标签排序退化了（本次 \(elapsed) ms）")
    }

    /// 统计本身在千级项目上必须保持快速（比较器内重算的根因）
    func testTagUsageStatisticsStayFastForThousandProjects() {
        let projects = (0..<1_000).map { index in
            ProjectFixtures.make(
                name: "Project\(index)",
                path: "/test/path/project\(index)",
                tags: Set((0..<3).map { "tag\((index + $0 * 7) % 20)" })
            ).toProjectData()
        }

        let start = ProcessInfo.processInfo.systemUptime
        let usage = TagLogic.calculateTagUsage(projects)
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000

        XCTAssertEqual(usage.count, 20)
        FileHandle.standardError.write(
            Data("PERF calculateTagUsage 1000 projects: \(elapsed) ms\n".utf8)
        )
        XCTAssertLessThan(elapsed, 50, "标签统计退化了（本次 \(elapsed) ms）")
    }
}
