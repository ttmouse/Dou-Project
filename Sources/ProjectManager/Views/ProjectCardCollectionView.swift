import AppKit
import SwiftUI

/// 卡片模式的滚动与复用容器。
///
/// 背景：卡片网格原本是 `ScrollView` + `LazyVGrid`，每一项都是一棵 SwiftUI
/// 视图树。`LazyVGrid` 在「集合整体替换」时会让 SwiftUI 重算 view graph、
/// 窗口 `minSize`、AutoLayout，再做 diff —— 实测（同一套采样方法）网格模式
/// 输入到画面中位 136 ms，而同数据量的列表模式是 48.5 ms。
///
/// 这里只把**容器**换成 AppKit：`NSCollectionView` 负责布局、滚动和复用，
/// 每张卡片的内容仍然是原来的 `ProjectCard`，视觉、悬停、拖拽、右键菜单、
/// 标签点击、按钮全部沿用，不重写。
///
/// 关键收益不是"少画了东西"，而是卡片数量不再等于 SwiftUI 视图树的数量：
/// 屏幕上放得下多少张卡就只实例化多少棵，滚动时复用而不是重建。
///
/// 为什么不是 `NSTableView`：表格是一维的，卡片是二维网格。硬用表格只能
/// 「一行塞 N 张卡」，复用粒度从"一张卡"退化成"一整行"，滚动一行就要重建
/// N 棵视图树，正好抵消掉换容器的收益。
struct ProjectCardCollectionView: NSViewRepresentable {
    let projects: [Project]
    let selectedIDs: Set<UUID>
    @Binding var searchBarRef: SearchBar?
    let tagManager: TagManager
    let tagDisplayCache: ProjectTagDisplayCache
    @ObservedObject var editorManager: EditorManager
    let onShowProjectDetail: (Project) -> Void
    let onTagSelected: (String) -> Void
    let onSelect: (Project, Bool) -> Void
    let onRequestEditTags: (Project) -> Void
    let onRequestRename: (Project) -> Void
    let onPortConflict: (Project, Int) -> Void
    let onClearSelection: () -> Void
    let onSelectionChange: (Set<UUID>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // 自己算布局，不用 `NSCollectionViewFlowLayout`。
        //
        // 原因：flow layout 会缓存每个 item 的尺寸，而网格的卡片宽度依赖容器宽度。
        // 用 flow layout 时窗口变宽不会让缓存失效，卡片停在旧宽度、右侧留出越来越大的
        // 空洞 —— 实测真实窗口就是这么错的。自定义 layout 在每次
        // `prepare()` 里按当前宽度重算，宽度一变尺寸跟着变。
        let layout = ProjectGridLayout()

        let collectionView = ProjectSelectableCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.isSelectable = false      // 选择由卡片自身的点击语义处理
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            ProjectCardItem.self,
            forItemWithIdentifier: ProjectCardItem.identifier
        )
        let selectionOverlay = SelectionOverlayView(frame: collectionView.bounds)
        selectionOverlay.autoresizingMask = [.width, .height]
        collectionView.addSubview(selectionOverlay, positioned: .above, relativeTo: nil)
        collectionView.selectionOverlay = selectionOverlay

        collectionView.onClearSelection = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onClearSelection()
        }
        collectionView.onSelectionChange = { [weak coordinator = context.coordinator] ids in
            coordinator?.parent.onSelectionChange(ids)
        }
        collectionView.currentSelection = { [weak coordinator = context.coordinator] in
            coordinator?.parent.selectedIDs ?? []
        }

        let scrollView = ProjectGridScrollView()
        scrollView.drawsBackground = false
        scrollView.configureProjectScrollIndicators()
        layout.scrollView = scrollView
        scrollView.documentView = collectionView

        context.coordinator.collectionView = collectionView
        context.coordinator.apply(animated: false)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.configureProjectScrollIndicators()
        context.coordinator.parent = self
        context.coordinator.apply(animated: true)
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: ProjectCardCollectionView
        weak var collectionView: NSCollectionView?
        private var displayedIDs: [UUID] = []

        init(_ parent: ProjectCardCollectionView) {
            self.parent = parent
        }

        func apply(animated: Bool) {
            guard let collectionView else { return }
            let ids = parent.projects.map(\.id)

            if ids != displayedIDs {
                // 结果集变了：重算布局并重新加载。动作上等价于原来的
                // 「`filteredProjects` 变了，整块重建」，但只重建可见项。
                displayedIDs = ids
                if animated {
                    collectionView.reloadData()
                } else {
                    collectionView.reloadData()
                }
            } else {
                // 只是选中态 / 标签颜色 / Git 元数据变化：就地更新可见卡片。
                for indexPath in collectionView.indexPathsForVisibleItems() {
                    guard parent.projects.indices.contains(indexPath.item),
                          let item = collectionView.item(at: indexPath) as? ProjectCardItem
                    else { continue }
                    configure(item, at: indexPath.item)
                }
            }
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            numberOfItemsInSection section: Int
        ) -> Int {
            parent.projects.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let item = collectionView.makeItem(
                withIdentifier: ProjectCardItem.identifier,
                for: indexPath
            ) as! ProjectCardItem
            configure(item, at: indexPath.item)
            return item
        }

        private func configure(_ item: ProjectCardItem, at index: Int) {
            guard parent.projects.indices.contains(index) else { return }
            let project = parent.projects[index]
            item.configure(
                project: project,
                isSelected: parent.selectedIDs.contains(project.id),
                displayTags: parent.tagDisplayCache.displayTags(for: project, tagManager: parent.tagManager),
                tagManager: parent.tagManager,
                editorManager: parent.editorManager,
                getSelectedProjects: { [weak self] in self?.parent.selectedIDs ?? [] },
                onTagSelected: { [weak self] in self?.parent.onTagSelected($0) },
                onSelect: { [weak self] usesModifier in
                    self?.parent.onSelect(project, usesModifier)
                },
                onShowDetail: { [weak self] in self?.parent.onShowProjectDetail(project) },
                onRequestEditTags: { [weak self] in self?.parent.onRequestEditTags(project) },
                onRequestRename: { [weak self] in self?.parent.onRequestRename(project) },
                onPortConflict: { [weak self] port in self?.parent.onPortConflict(project, port) }
            )
        }
    }
}

/// 一张卡片的宿主：内容仍然是原来的 `ProjectCard`。
///
/// 用 `NSHostingView` 而不是自绘，是为了不改任何交互与视觉 —— 卡片里的
/// 按钮、标签删除、拖拽、右键菜单、`.onTapGesture` 都还是原实现。
/// 换容器的目的只是让卡片数量与 SwiftUI 视图树数量解耦。
final class ProjectCardItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ProjectCardItem")

    private var hostingView: NSHostingView<AnyView>?
    private var projectID: UUID?
    var representedProjectID: UUID? { projectID }

    override func loadView() {
        view = CardContainerView()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        projectID = nil
    }

    /// 不让 AppKit 反算卡片的「理想尺寸」。
    ///
    /// 1ms 主线程采样（本轮）显示：输入到画面的时间里有 11.4% 花在
    /// `_createPreparedCellForItemAtIndexPath` → `preferredLayoutAttributesFittingAttributes`
    /// → `systemLayoutSizeFittingSize` → `updateConstraintsForSubtreeIfNeeded`
    /// → `NSHostingView.minSize()` → `AG::Graph::UpdateStack::update()`。
    /// 也就是说每复用一张卡，SwiftUI 就被要求重算一次整张卡的布局图，
    /// 而尺寸其实由 `ProjectGridLayout` 早就确定好了。
    ///
    /// 布局是自定义的、尺寸是算出来的、卡片高度是固定的，所以这里直接原样返回。
    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: NSCollectionViewLayoutAttributes
    ) -> NSCollectionViewLayoutAttributes {
        layoutAttributes
    }

    func configure(
        project: Project,
        isSelected: Bool,
        displayTags: [TagDisplayData],
        tagManager: TagManager,
        editorManager: EditorManager,
        getSelectedProjects: @escaping () -> Set<UUID>,
        onTagSelected: @escaping (String) -> Void,
        onSelect: @escaping (Bool) -> Void,
        onShowDetail: @escaping () -> Void,
        onRequestEditTags: @escaping () -> Void,
        onRequestRename: @escaping () -> Void,
        onPortConflict: @escaping (Int) -> Void
    ) {
        let card = ProjectCard(
            project: project,
            isSelected: isSelected,
            getSelectedProjects: getSelectedProjects,
            tagManager: tagManager,
            displayTags: displayTags,
            editorManager: editorManager,
            onTagSelected: onTagSelected,
            onSelect: onSelect,
            onShowDetail: onShowDetail,
            onRequestEditTags: { _ in onRequestEditTags() },
            onRequestRename: { _ in onRequestRename() },
            onPortConflict: { _, port in onPortConflict(port) }
        )

        if let hostingView {
            hostingView.rootView = AnyView(card)
        } else {
            let host = NSHostingView(rootView: AnyView(card))
            // 用 frame + autoresizing 而不是约束。
            //
            // 约束版每张卡都会向窗口级 AutoLayout 引擎登记 4 条约束，
            // 窗口布局时要遍历整棵树（采样里 24.8% 的
            // `NSWindow layoutIfNeeded → _layoutViewTree` 正是这条路径）；
            // 卡片的尺寸本来就是已知的，约束只是纯开销。
            host.translatesAutoresizingMaskIntoConstraints = true
            host.autoresizingMask = [.width, .height]
            if #available(macOS 13.0, *) {
                // 不向父视图推荐 intrinsic 尺寸：尺寸由布局对象决定。
                host.sizingOptions = []
            }
            view.addSubview(host)
            hostingView = host
        }
        projectID = project.id
    }
}

/// Keep the collection document view aligned with the visible width as an HSplitView resizes.
private final class ProjectGridScrollView: NSScrollView {
    override func layout() {
        super.layout()

        guard let collectionView = documentView as? NSCollectionView else { return }
        let visibleWidth = contentView.bounds.width
        guard abs(collectionView.frame.width - visibleWidth) > 0.5 else { return }

        collectionView.setFrameSize(
            NSSize(width: visibleWidth, height: collectionView.frame.height)
        )
        collectionView.collectionViewLayout?.invalidateLayout()
    }
}

/// 卡片容器的根视图：只负责承载一张卡片，不做自适布局。
private final class CardContainerView: NSView {
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        subviews.first?.frame = bounds
    }
}

/// 由网格本身接收空白区域的鼠标事件，避免 backgroundView 命中测试绕过手势。
private final class ProjectSelectableCollectionView: NSCollectionView {
    var onClearSelection: (() -> Void)?
    var onSelectionChange: ((Set<UUID>) -> Void)?
    var currentSelection: (() -> Set<UUID>)?
    private var dragOrigin: NSPoint?
    private var selectionRect: NSRect?
    private var startingSelection: Set<UUID> = []
    weak var selectionOverlay: SelectionOverlayView?

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard indexPathForItem(at: point) == nil else {
            super.mouseDown(with: event)
            return
        }
        dragOrigin = point
        selectionRect = nil
        let additive = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
        startingSelection = additive ? (currentSelection?() ?? []) : []
        window?.makeFirstResponder(nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let rect = NSRect(x: min(dragOrigin.x, point.x), y: min(dragOrigin.y, point.y),
                          width: abs(point.x - dragOrigin.x), height: abs(point.y - dragOrigin.y))
        selectionRect = rect
        selectionOverlay?.selectionRect = rect
        updateSelection(rect)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragOrigin != nil else {
            super.mouseUp(with: event)
            return
        }
        if selectionRect == nil { onClearSelection?() }
        dragOrigin = nil
        selectionRect = nil
        selectionOverlay?.selectionRect = nil
    }

    private func updateSelection(_ rect: NSRect) {
        var ids = startingSelection
        for index in 0..<numberOfItems(inSection: 0) {
            let indexPath = IndexPath(item: index, section: 0)
            guard let attributes = collectionViewLayout?.layoutAttributesForItem(at: indexPath),
                  attributes.frame.intersects(rect),
                  let item = item(at: indexPath) as? ProjectCardItem,
                  let id = item.representedProjectID else { continue }
            ids.insert(id)
        }
        onSelectionChange?(ids)
    }
}

private final class SelectionOverlayView: NSView {
    var selectionRect: NSRect? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let selectionRect else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(rect: selectionRect).fill()
        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        let border = NSBezierPath(rect: selectionRect)
        border.lineWidth = 1
        border.stroke()
    }
}

/// 卡片网格的自定义布局。
///
/// 每次 `prepare()` 都按 collection view 的当前宽度重算列数、卡片宽度和位置，
/// 所以窗口缩放时卡片会立即跟着变宽变窄。这是 `NSCollectionViewFlowLayout` 做不到的：
/// 它会把尺寸缓存住，除非显式 `invalidateLayout`，而宽度变化不会自动触发。
///
/// 布局数学在 `ProjectGridMetrics` 里，是可断言的纯函数。
final class ProjectGridLayout: NSCollectionViewLayout {
    private var metrics = ProjectGridMetrics.compute(containerWidth: 0, itemCount: 0)
    private var cachedAttributes: [NSCollectionViewLayoutAttributes] = []
    weak var scrollView: NSScrollView?
    private var preparedWidth: CGFloat = 0

    override func prepare() {
        super.prepare()
        guard let collectionView else {
            metrics = ProjectGridMetrics.compute(containerWidth: 0, itemCount: 0)
            cachedAttributes = []
            return
        }
        let count = collectionView.numberOfItems(inSection: 0)
        // The collection view is the actual layout container. NSScrollView's frame
        // can still report its old width during a split-view resize, which leaves
        // cached card frames extending underneath the detail panel.
        let layoutWidth = collectionView.bounds.width
        preparedWidth = layoutWidth
        metrics = ProjectGridMetrics.compute(
            containerWidth: layoutWidth,
            itemCount: count
        )

        cachedAttributes = (0..<count).map { index in
            let attributes = NSCollectionViewLayoutAttributes(
                forItemWith: IndexPath(item: index, section: 0)
            )
            attributes.frame = metrics.frame(at: index)
            return attributes
        }
    }

    /// 宽度变化必须让布局失效，否则尺寸会被缓存住。
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return abs(newBounds.width - preparedWidth) > 0.5
    }

    override var collectionViewContentSize: NSSize {
        NSSize(width: preparedWidth, height: metrics.contentHeight)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        cachedAttributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard cachedAttributes.indices.contains(indexPath.item) else { return nil }
        return cachedAttributes[indexPath.item]
    }
}
