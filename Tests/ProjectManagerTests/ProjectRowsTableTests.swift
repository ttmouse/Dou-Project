import AppKit
import SwiftUI
import XCTest
@testable import ProjectManager

final class ProjectRowsTableTests: XCTestCase {
    private func project(_ name: String, id: UUID = UUID(), command: String? = nil) -> Project {
        Project(id: id, name: name, path: "/fixture/" + name, mtime: Date(timeIntervalSince1970: 100),
                size: 0, checksum: "fixture", git_commits: 3, git_last_commit: .distantPast, startupCommand: command)
    }

    @MainActor
    func testFilteringReorderingClearingAndRestoringUseCurrentProjects() throws {
        _ = NSApplication.shared
        let projects = (0..<3).map { project("project\($0)") }
        let original = ProjectRowsTable(projects: projects)
        let coordinator = original.makeCoordinator()
        let scroll = original.makeScrollView(coordinator: coordinator)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        coordinator.update(original)
        XCTAssertEqual(table.numberOfRows, 3)
        XCTAssertEqual(table.rowHeight, 42)
        XCTAssertFalse(table.usesAutomaticRowHeights)

        coordinator.update(ProjectRowsTable(projects: [projects[2], projects[0]]))
        XCTAssertEqual(table.numberOfRows, 2)
        let first = try XCTUnwrap(coordinator.tableView(table, viewFor: table.tableColumns[0], row: 0) as? NativeProjectListRow)
        XCTAssertEqual(first.project?.id, projects[2].id)
        let second = try XCTUnwrap(coordinator.tableView(table, viewFor: table.tableColumns[0], row: 1) as? NativeProjectListRow)
        XCTAssertEqual(second.project?.id, projects[0].id)
        XCTAssertNil(coordinator.tableView(table, viewFor: table.tableColumns[0], row: 2))
        coordinator.update(ProjectRowsTable(projects: []))
        XCTAssertEqual(table.numberOfRows, 0)
        coordinator.update(original)
        XCTAssertEqual(table.numberOfRows, 3)
    }

    @MainActor
    func testMetadataAndSelectionUpdateWithoutReplacingCells() throws {
        _ = NSApplication.shared
        let initial = project("original")
        let original = ProjectRowsTable(projects: [initial])
        let coordinator = original.makeCoordinator()
        let scroll = original.makeScrollView(coordinator: coordinator)
        scroll.frame = NSRect(x: 0, y: 0, width: 900, height: 200)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        coordinator.update(original)
        scroll.layoutSubtreeIfNeeded()
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NativeProjectListRow)
        let renamed = project("renamed", id: initial.id)
        coordinator.update(ProjectRowsTable(projects: [renamed], selectedIDs: [initial.id]))
        XCTAssertEqual(cell.project?.name, "renamed")
        XCTAssertEqual(cell.accessibilityValue() as? String, "已选中")
        XCTAssertTrue(cell.isAccessibilitySelected())
        XCTAssertTrue(table.view(atColumn: 0, row: 0, makeIfNecessary: false) === cell)
        XCTAssertFalse(coordinator.tableView(table, shouldSelectRow: 0))
    }

    @MainActor
    func testReusedRowButtonsMenusAndTagsTargetNewProject() throws {
        _ = NSApplication.shared
        let row = NativeProjectListRow(frame: NSRect(x: 0, y: 0, width: 1000, height: 42))
        let first = project("first", command: "echo fixture")
        let second = project("second")
        var received: [(UUID, ProjectRowAction)] = []
        row.onAction = { received.append(($0.id, $1)) }
        row.update(project: first, selected: false, tags: [TagDisplayData(name: "old", color: .red)])
        row.update(project: second, selected: false, tags: [TagDisplayData(name: "new", color: .blue)])
        row.layoutSubtreeIfNeeded()
        let buttons = descendants(row).compactMap { $0 as? NSButton }
        XCTAssertFalse(buttons.contains { $0.toolTip == "运行项目" })
        try XCTUnwrap(buttons.first { $0.toolTip == "在访达中显示" }).performClick(nil)
        XCTAssertEqual(received.last?.0, second.id)
        XCTAssertEqual(received.last?.1, .finder)
        let tag = try XCTUnwrap(buttons.compactMap { $0 as? NativeProjectTagButton }.first)
        XCTAssertEqual(tag.tagData.name, "new")
        tag.performClick(nil)
        XCTAssertEqual(received.last?.1, .tag("new"))
        tag.onRemove()
        XCTAssertEqual(received.last?.1, .removeTag("new"))
        XCTAssertEqual(received.last?.0, second.id)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(row.menu(for: event))
        XCTAssertEqual(menu.items.map(\.title), ["在默认编辑器中打开", "在终端打开", "编辑标签", "刷新项目", "重命名项目"])
        row.update(project: first, selected: false, tags: [])
        menu.performActionForItem(at: 4)
        XCTAssertEqual(received.last?.0, second.id)
        XCTAssertEqual(received.last?.1, .rename)
    }

    @MainActor
    func testTableRoutesContextMenuToClickedRow() throws {
        _ = NSApplication.shared
        let first = project("first")
        let second = project("second")
        var target: UUID?
        let content = ProjectRowsTable(projects: [first, second], onAction: { target = $0.id; _ = $1 })
        let coordinator = content.makeCoordinator()
        let scroll = content.makeScrollView(coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = scroll
        coordinator.update(content)
        scroll.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(scroll.documentView as? NativeProjectRowsTableView)
        _ = table.view(atColumn: 0, row: 1, makeIfNecessary: true)
        let point = table.convert(NSPoint(x: 50, y: table.rect(ofRow: 1).midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: point,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(table.menu(for: event))
        menu.performActionForItem(at: 0)
        XCTAssertEqual(target, second.id)
    }

    @MainActor
    func testDragPayloadPreservesBatchIDsAndSingleProjectFallback() throws {
        let row = NativeProjectListRow()
        let current = project("current")
        row.update(project: current, selected: false, tags: [])
        let other = UUID()
        row.selectedIDs = { [current.id, other] }
        let batch = try JSONDecoder().decode(Set<UUID>.self, from: XCTUnwrap(row.dragData()))
        XCTAssertEqual(batch, [current.id, other])
        row.selectedIDs = { [other] }
        let single = try JSONDecoder().decode(Set<UUID>.self, from: XCTUnwrap(row.dragData()))
        XCTAssertEqual(single, [current.id])
    }

    @MainActor
    func testNativeRowDrawsWithoutSwiftUIHostingAndUsesOriginalColumnGeometry() throws {
        _ = NSApplication.shared
        let row = NativeProjectListRow(frame: NSRect(x: 0, y: 0, width: 1000, height: 42))
        row.update(project: project("Drawn title"), selected: true, tags: [TagDisplayData(name: "swift", color: .orange)])
        row.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(row.bitmapImageRepForCachingDisplay(in: row.bounds))
        row.cacheDisplay(in: row.bounds, to: image)
        XCTAssertFalse(descendants(row).contains { String(describing: type(of: $0)).contains("Hosting") })
        let columns = ProjectRowLayout(width: 1000)
        XCTAssertEqual(columns.name.minX, 14)
        XCTAssertEqual(columns.tags.width, 180)
        XCTAssertEqual(columns.activity.width, 150)
        XCTAssertEqual(columns.commits.width, 60)
        XCTAssertEqual(columns.actions.width, 112)
        XCTAssertEqual(columns.actions.maxX, 986)
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
