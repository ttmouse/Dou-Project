import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ProjectRowAction: Equatable {
    case activate(NSEvent.ModifierFlags)
    case tag(String)
    case removeTag(String)
    case run, editor, finder, terminal, editTags, refresh, rename
}

/// 与原 SwiftUI 表头使用同一组列宽和间距。
struct ProjectRowLayout {
    let name: NSRect
    let tags: NSRect
    let activity: NSRect
    let commits: NSRect
    let actions: NSRect

    init(width: CGFloat) {
        let nameWidth = max(0, width - 578)
        name = NSRect(x: 14, y: 0, width: nameWidth, height: 42)
        tags = NSRect(x: name.maxX + 12, y: 9, width: 180, height: 24)
        activity = NSRect(x: tags.maxX + 12, y: 0, width: 150, height: 42)
        commits = NSRect(x: activity.maxX + 12, y: 0, width: 60, height: 42)
        actions = NSRect(x: commits.maxX + 12, y: 0, width: 112, height: 42)
    }
}

final class NativeProjectListRow: NSTableCellView, NSDraggingSource {
    private(set) var project: Project?
    private var selected = false
    private var hovered = false
    private var mouseStart: NSPoint?
    private var isDragging = false
    var onAction: (Project, ProjectRowAction) -> Void = { _, _ in }
    var selectedIDs: () -> Set<UUID> = { [] }
    private var displayedTags: [TagDisplayData] = []
    private let tagScroll = NSScrollView()
    private let tagDocument = FlippedProjectTagsView()
    private var tagButtons: [NativeProjectTagButton] = []
    private var actionButtons: [NSButton] = []
    private var activityText = ""
    private var commitsText = ""

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        tagScroll.drawsBackground = false
        tagScroll.hasHorizontalScroller = false
        tagScroll.hasVerticalScroller = false
        tagScroll.documentView = tagDocument
        addSubview(tagScroll)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { nil }

    func update(project: Project, selected: Bool, tags: [TagDisplayData]) {
        let changedIdentity = self.project?.id != project.id
        let changedRunButton = self.project?.startupCommand != project.startupCommand
        if changedIdentity {
            hovered = false
            mouseStart = nil
            isDragging = false
            tagScroll.contentView.scroll(to: .zero)
        }
        self.project = project
        self.selected = selected
        activityText = Self.dateFormatter.string(from: project.mtime)
        commitsText = project.gitInfo.map { String($0.commitCount) } ?? "—"
        toolTip = "\(project.name)\n\(project.path)"
        setAccessibilityLabel("\(project.name)，修改日期 \(activityText)，提交 \(commitsText)")
        setAccessibilityValue(selected ? "已选中" : "未选中")
        setAccessibilitySelected(selected)
        if changedIdentity || displayedTags != tags {
            displayedTags = tags
            updateTags()
        }
        if changedIdentity || changedRunButton { updateButtons() }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let columns = ProjectRowLayout(width: bounds.width)
        tagScroll.frame = columns.tags
        layoutTags()
        var x = columns.actions.maxX - 16
        for button in actionButtons.reversed() {
            button.frame = NSRect(x: x, y: 12, width: 16, height: 18)
            x -= 24
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = selected ? NSColor(AppTheme.cardSelectedBackground)
            : (hovered ? NSColor.white.withAlphaComponent(0.012) : NSColor(AppTheme.cardBackground))
        background.setFill()
        bounds.fill()
        guard let project else { return }
        let columns = ProjectRowLayout(width: bounds.width)
        drawText(project.name, in: columns.name, size: 13, weight: .medium, color: NSColor(AppTheme.text))
        drawText(activityText, in: columns.activity, size: 11, color: NSColor(AppTheme.secondaryText))
        drawText(commitsText, in: columns.commits, size: 13, weight: .medium,
                 color: NSColor(project.gitInfo == nil ? AppTheme.secondaryText : AppTheme.accent), alignment: .right)
        if displayedTags.isEmpty {
            drawText("无标签", in: columns.tags, size: 11, color: NSColor(AppTheme.secondaryText))
        }
    }

    private func drawText(_ text: String, in rect: NSRect, size: CGFloat,
                          weight: NSFont.Weight = .regular, color: NSColor,
                          alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = alignment
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let height = ceil(font.ascender - font.descender + font.leading)
        (text as NSString).draw(in: NSRect(x: rect.minX, y: rect.midY - height / 2,
                                         width: rect.width, height: height), withAttributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph
        ])
    }

    private func updateTags() {
        tagButtons.forEach { $0.removeFromSuperview() }
        tagButtons = displayedTags.map { data in
            let button = NativeProjectTagButton(tag: data)
            button.onClick = { [weak self] in self?.perform(.tag(data.name)) }
            button.onRemove = { [weak self] in self?.perform(.removeTag(data.name)) }
            button.onWidthChanged = { [weak self] in self?.layoutTags() }
            tagDocument.addSubview(button)
            return button
        }
        tagScroll.isHidden = tagButtons.isEmpty
        layoutTags()
    }

    private func layoutTags() {
        var x: CGFloat = 0
        for button in tagButtons {
            button.frame = NSRect(x: x, y: 1, width: button.tagWidth, height: 22)
            x = button.frame.maxX + 4
        }
        tagDocument.frame.size = NSSize(width: max(tagScroll.contentSize.width, x - 4), height: 24)
    }

    private func updateButtons() {
        actionButtons.forEach { $0.removeFromSuperview() }
        actionButtons = []
        if project?.startupCommand != nil {
            addButton("play.fill", title: "运行项目", color: .systemGreen, action: .run)
        }
        addButton("cursorarrow.rays", title: "在默认编辑器中打开", color: NSColor(AppTheme.accent), action: .editor)
        addButton("folder", title: "在访达中显示", color: NSColor(AppTheme.folderIcon), action: .finder)
    }

    private func addButton(_ symbol: String, title: String, color: NSColor, action: ProjectRowAction) {
        let button = ProjectRowButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = color
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.onClick = { [weak self] in self?.perform(action) }
        addSubview(button)
        actionButtons.append(button)
    }

    func perform(_ action: ProjectRowAction) {
        guard let project else { return }
        onAction(project, action)
    }

    override func accessibilityPerformPress() -> Bool {
        guard project != nil else { return false }
        perform(.activate([]))
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        mouseStart = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseStart = nil; isDragging = false }
        guard mouseStart != nil, !isDragging, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        perform(.activate(event.modifierFlags))
    }

    func dragData() -> Data? {
        guard let project else { return nil }
        let selected = selectedIDs()
        let ids = selected.count > 1 ? selected : [project.id]
        return try? JSONEncoder().encode(ids)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let mouseStart, let data = dragData() else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - mouseStart.x, point.y - mouseStart.y) >= 4 else { return }
        let pasteboard = NSPasteboardItem()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(UTType.data.identifier))
        let item = NSDraggingItem(pasteboardWriter: pasteboard)
        let image = NSImage(size: NSSize(width: 200, height: 28))
        image.lockFocus()
        drawText(project?.name ?? "", in: NSRect(x: 4, y: 0, width: 192, height: 28),
                 size: 13, color: NSColor(AppTheme.text))
        image.unlockFocus()
        item.setDraggingFrame(NSRect(origin: point, size: image.size), contents: image)
        isDragging = true
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let project else { return nil }
        let menu = NSMenu()
        let entries: [(String, ProjectRowAction)] = [
            ("在默认编辑器中打开", .editor), ("在终端打开", .terminal),
            ("编辑标签", .editTags), ("刷新项目", .refresh), ("重命名项目", .rename)
        ]
        for (title, action) in entries {
            let item = ProjectRowMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: "")
            // 菜单打开后列表可能重排；操作必须针对打开菜单时的项目。
            item.onInvoke = { [onAction, project] in onAction(project, action) }
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menu(for: event) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func menuAction(_ item: ProjectRowMenuItem) { item.onInvoke() }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

/// NSTableView 会接管行上的右键事件，需按点击位置转交给对应的行菜单。
final class NativeProjectRowsTableView: NSTableView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0,
              let cell = view(atColumn: 0, row: index, makeIfNecessary: false) as? NativeProjectListRow else { return nil }
        return cell.menu(for: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menu(for: event) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

private final class FlippedProjectTagsView: NSView {
    override var isFlipped: Bool { true }
}

private final class ProjectRowMenuItem: NSMenuItem {
    var onInvoke: () -> Void = {}
}

private class ProjectRowButton: NSButton {
    var onClick: () -> Void = {}
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(clicked)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func clicked() { onClick() }
}

/// 使用原生按钮响应键盘与辅助功能，外观绘制沿用原 TagView 的字号、内边距和颜色。
final class NativeProjectTagButton: NSButton {
    let tagData: TagDisplayData
    var onClick: () -> Void = {}
    var onRemove: () -> Void = {}
    var onWidthChanged: () -> Void = {}
    private var hovered = false
    private let removeButton = ProjectRowButton()
    private let textWidth: CGFloat
    var tagWidth: CGFloat { textWidth + 16 + (hovered ? 16 : 0) }

    init(tag: TagDisplayData) {
        self.tagData = tag
        textWidth = ceil((tag.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width)
        super.init(frame: .zero)
        isBordered = false
        title = tag.name
        target = self
        action = #selector(clicked)
        setAccessibilityLabel("标签 \(tag.name)")
        removeButton.isBordered = false
        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "移除标签 \(tag.name)")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        removeButton.contentTintColor = NSColor(tag.color).withAlphaComponent(0.72)
        removeButton.setAccessibilityLabel("移除标签 \(tag.name)")
        removeButton.toolTip = "移除标签 \(tag.name)"
        removeButton.onClick = { [weak self] in self?.onRemove() }
        removeButton.isHidden = true
        addSubview(removeButton)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(tagData.color).withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        (tagData.name as NSString).draw(at: NSPoint(x: 8, y: 4), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(tagData.color).withAlphaComponent(0.9)
        ])
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).stroke()
        }
    }

    override func layout() {
        super.layout()
        removeButton.frame = NSRect(x: bounds.width - 20, y: 4, width: 12, height: 14)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        removeButton.isHidden = !value
        onWidthChanged()
        needsLayout = true
        needsDisplay = true
    }
    @objc private func clicked() { onClick() }
}
