import CoreGraphics
import Foundation

/// 卡片网格的布局计算。
///
/// 语义必须与原来的 `LazyVGrid(.adaptive(minimum:maximum:))` 一致，否则换容器
/// 就等于偷偷改了视觉：
/// - 列数 = 可用宽度能放下多少个「最小卡片宽度」；
/// - 每列等宽，宽度上限 `maximum`；
/// - 只有一列时铺满可用宽度（否则窄窗口右侧留空洞）；
/// - 卡片间距固定，四周留出内边距。
///
/// 抽成纯函数的原因：容器换成了 `NSCollectionView` 自定义 layout，
/// 这套数学一旦算错就表现为「卡片重叠 / 右侧空洞 / 点不中」，
/// 必须有可以直接断言的入口。
struct ProjectGridMetrics: Equatable {
    var columnCount: Int
    var cardWidth: CGFloat
    var rowCount: Int
    var contentHeight: CGFloat

    static let padding: CGFloat = AppTheme.cardGridPadding
    static let spacingH: CGFloat = AppTheme.cardGridSpacingH
    static let spacingV: CGFloat = AppTheme.cardGridSpacingV
    static let cardHeight: CGFloat = AppTheme.cardHeight
    static let minCardWidth: CGFloat = AppTheme.cardMinWidth
    static let maxCardWidth: CGFloat = AppTheme.cardMaxWidth

    /// 给定容器宽度与卡片数量，算出网格度量。
    static func compute(containerWidth: CGFloat, itemCount: Int) -> ProjectGridMetrics {
        let usable = containerWidth - padding * 2

        // 宽度不足时退化为单列，宽度至少 1，避免负数尺寸。
        guard usable > 0 else {
            return ProjectGridMetrics(
                columnCount: 1,
                cardWidth: max(containerWidth - padding * 2, 1),
                rowCount: itemCount,
                contentHeight: contentHeight(rows: itemCount)
            )
        }

        let fit = Int(((usable + spacingH) / (minCardWidth + spacingH)).rounded(.down))
        let columnCount = max(1, fit)

        let cardWidth: CGFloat
        if columnCount == 1 {
            // 单列：铺满，不再受 maxCardWidth 限制。
            cardWidth = usable
        } else {
            let raw = (usable - spacingH * CGFloat(columnCount - 1)) / CGFloat(columnCount)
            cardWidth = min(max(raw, minCardWidth), maxCardWidth)
        }

        let rowCount = itemCount <= 0
            ? 0
            : Int(ceil(Double(itemCount) / Double(columnCount)))

        return ProjectGridMetrics(
            columnCount: columnCount,
            cardWidth: cardWidth,
            rowCount: rowCount,
            contentHeight: contentHeight(rows: rowCount)
        )
    }

    private static func contentHeight(rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return padding * 2
            + CGFloat(rows) * cardHeight
            + CGFloat(rows - 1) * spacingV
    }

    /// 第 `index` 张卡在内容坐标系（原点左上、y 向下）中的位置。
    func frame(at index: Int) -> CGRect {
        guard columnCount > 0, index >= 0 else { return .zero }
        let row = index / columnCount
        let column = index % columnCount
        return CGRect(
            x: Self.padding + CGFloat(column) * (cardWidth + Self.spacingH),
            y: Self.padding + CGFloat(row) * (Self.cardHeight + Self.spacingV),
            width: cardWidth,
            height: Self.cardHeight
        )
    }

    /// 命中测试：落在卡片之间的间距里不算命中。
    func index(at point: CGPoint, itemCount: Int) -> Int? {
        guard itemCount > 0, columnCount > 0 else { return nil }
        let x = point.x - Self.padding
        let y = point.y - Self.padding
        guard x >= 0, y >= 0 else { return nil }

        let columnStride = cardWidth + Self.spacingH
        let rowStride = Self.cardHeight + Self.spacingV
        let column = Int(x / columnStride)
        let row = Int(y / rowStride)
        guard column >= 0, column < columnCount else { return nil }

        if x - CGFloat(column) * columnStride > cardWidth { return nil }
        if y - CGFloat(row) * rowStride > Self.cardHeight { return nil }

        let index = row * columnCount + column
        guard index < itemCount else { return nil }
        return index
    }
}
