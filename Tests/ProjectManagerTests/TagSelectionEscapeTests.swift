import XCTest
@testable import ProjectManager

/// Esc 取消标签筛选的判定护栏。
///
/// 症状背景：点击标签后按 Esc 没有反应。除了缺监听之外，还有一个语义坑：
/// 「全部」本身表示「不筛选」，如果按 Esc 也算一次取消，就会白吃掉 Esc。
/// 本文件锁住「什么状态下 Esc 才应该生效」。
final class TagSelectionEscapeTests: XCTestCase {

    func testEmptySelectionNeedsNoCancel() {
        XCTAssertFalse(TagSelectionEscapeLogic.shouldCancel([]))
    }

    func testUnfilteredTagNeedsNoCancel() {
        XCTAssertFalse(TagSelectionEscapeLogic.shouldCancel(["全部"]))
    }

    func testSingleTagCanBeCancelled() {
        XCTAssertTrue(TagSelectionEscapeLogic.shouldCancel(["工作"]))
    }

    func testUntaggedBucketCanBeCancelled() {
        XCTAssertTrue(TagSelectionEscapeLogic.shouldCancel(["没有标签"]))
    }

    /// 「全部」混进真实标签时仍应可取消（多标签交集筛选）
    func testRealTagAlongsideUnfilteredTagCanBeCancelled() {
        XCTAssertTrue(TagSelectionEscapeLogic.shouldCancel(["全部", "工作"]))
    }
}
