import XCTest
@testable import ProjectManager

/// 卡片网格布局的回归护栏。
///
/// 背景：卡片网格的容器从 `ScrollView` + `LazyVGrid` 换成 `NSCollectionView`
/// 之后，列数与卡片宽度变成自己算。第一版用了 `NSCollectionViewFlowLayout`，
/// 它会缓存 item 尺寸，窗口变宽时不失效，于是卡片停在旧宽度、右侧留出越来越大的
/// 空洞（真实窗口已验证）。修复方式是自定义 layout + 这份纯函数数学。
///
/// 因此这里的断言不是"差不多对"，而是逐条锁死 `LazyVGrid(.adaptive)` 的语义：
/// 搞错了就表现为卡片重叠、右侧空洞或点不中。
final class ProjectGridMetricsTests: XCTestCase {

    // MARK: - 列数与宽度

    /// 单列时必须铺满可用宽度。这是修「右侧空洞」的核心一条。
    func testSingleColumnFillsAvailableWidth() {
        let metrics = ProjectGridMetrics.compute(containerWidth: 400, itemCount: 3)
        XCTAssertEqual(metrics.columnCount, 1)
        XCTAssertEqual(
            metrics.cardWidth,
            400 - ProjectGridMetrics.padding * 2,
            accuracy: 0.01
        )
    }

    /// 多列时每列等宽，且不超过上限。
    func testMultiColumnWidthIsEqualAndCapped() {
        let metrics = ProjectGridMetrics.compute(containerWidth: 2_400, itemCount: 12)
        XCTAssertGreaterThan(metrics.columnCount, 1)
        XCTAssertGreaterThanOrEqual(metrics.cardWidth, ProjectGridMetrics.minCardWidth - 0.01)
        XCTAssertLessThanOrEqual(metrics.cardWidth, ProjectGridMetrics.maxCardWidth + 0.01)
    }

    /// 列数 = 可用宽度能放下的最小卡片宽度个数。
    func testColumnCountMatchesMinimumWidthFit() {
        // 可用 682，最小宽 250，间距 16 → floor((682+16)/(250+16)) = 2
        let width = 682 + ProjectGridMetrics.padding * 2
        let metrics = ProjectGridMetrics.compute(containerWidth: width, itemCount: 4)
        XCTAssertEqual(metrics.columnCount, 2)
    }

    /// 宽度变大时列数不能减少 —— 这是被 flow layout 缓存破坏的性质。
    func testWiderContainerNeverReducesColumns() {
        var previous = 0
        var width: CGFloat = 320
        while width <= 3_000 {
            let metrics = ProjectGridMetrics.compute(containerWidth: width, itemCount: 20)
            XCTAssertGreaterThanOrEqual(metrics.columnCount, previous, "宽度 \(width) 时列数倒退了")
            previous = metrics.columnCount
            width += 37
        }
    }

    /// 极端宽度不能算出 0 列或非正宽度。
    func testDegenerateWidthsStayUsable() {
        for width in [0, 1, 10, 32, 33, 40] as [CGFloat] {
            let metrics = ProjectGridMetrics.compute(containerWidth: width, itemCount: 2)
            XCTAssertGreaterThanOrEqual(metrics.columnCount, 1)
            XCTAssertGreaterThan(metrics.cardWidth, 0)
        }
    }

    // MARK: - 内容高度

    func testContentHeightAccountsForRowsAndSpacing() {
        let width = 682 + ProjectGridMetrics.padding * 2
        let metrics = ProjectGridMetrics.compute(containerWidth: width, itemCount: 4)
        XCTAssertEqual(metrics.columnCount, 2)
        XCTAssertEqual(metrics.rowCount, 2)
        let expected = ProjectGridMetrics.padding * 2
            + ProjectGridMetrics.cardHeight * 2
            + ProjectGridMetrics.spacingV
        XCTAssertEqual(metrics.contentHeight, expected, accuracy: 0.01)
    }

    func testEmptyGridHasNoContentHeight() {
        let metrics = ProjectGridMetrics.compute(containerWidth: 800, itemCount: 0)
        XCTAssertEqual(metrics.contentHeight, 0)
        XCTAssertEqual(metrics.rowCount, 0)
    }

    // MARK: - 坐标与命中测试

    /// 每张卡的中心点必须命中自己。
    func testFrameAndHitTestAreInverse() {
        let width = 682 + ProjectGridMetrics.padding * 2
        let metrics = ProjectGridMetrics.compute(containerWidth: width, itemCount: 9)
        for index in 0..<9 {
            let frame = metrics.frame(at: index)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            XCTAssertEqual(metrics.index(at: center, itemCount: 9), index)
        }
    }

    /// 卡片之间的间距不属于任何卡片。
    func testGutterIsNotAHit() {
        let width = 682 + ProjectGridMetrics.padding * 2
        let metrics = ProjectGridMetrics.compute(containerWidth: width, itemCount: 4)
        let first = metrics.frame(at: 0)
        let gutter = CGPoint(x: first.maxX + ProjectGridMetrics.spacingH / 2, y: first.midY)
        XCTAssertNil(metrics.index(at: gutter, itemCount: 4))
    }

    /// 内容区之外不命中。
    func testPointOutsideContentMisses() {
        let width = 682 + ProjectGridMetrics.padding * 2
        let metrics = ProjectGridMetrics.compute(containerWidth: width, itemCount: 4)
        XCTAssertNil(
            metrics.index(
                at: CGPoint(x: 40, y: metrics.contentHeight + 100),
                itemCount: 4
            )
        )
    }

    /// 末尾空格子不命中（5 张卡、2 列，第 6 格为空）。
    func testTrailingEmptyCellMisses() {
        let width = 682 + ProjectGridMetrics.padding * 2
        let metrics = ProjectGridMetrics.compute(containerWidth: width, itemCount: 5)
        let emptyCell = metrics.frame(at: 5)
        XCTAssertNil(
            metrics.index(
                at: CGPoint(x: emptyCell.midX, y: emptyCell.midY),
                itemCount: 5
            )
        )
    }

    /// 上千张卡片时布局仍是微秒级。
    func testLargeGridStaysFast() {
        let count = 2_000
        let start = ProcessInfo.processInfo.systemUptime
        let metrics = ProjectGridMetrics.compute(containerWidth: 1_200, itemCount: count)
        var hits = 0
        let sampled = Array(stride(from: 0, to: count, by: 7))
        for index in sampled {
            let frame = metrics.frame(at: index)
            if metrics.index(at: CGPoint(x: frame.midX, y: frame.midY), itemCount: count) == index {
                hits += 1
            }
        }
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        XCTAssertEqual(hits, sampled.count)
        XCTAssertLessThan(elapsed, 5, "网格布局退化（本次 \(elapsed) ms）")
    }
}
