import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProjectListRowsView: View {
    let filteredProjects: [Project]
    @Binding var selectedProjects: Set<UUID>
    @Binding var sortOption: SortOption
    @ObservedObject var editorManager: EditorManager
    @EnvironmentObject var tagManager: TagManager
    let onShowProjectDetail: (Project) -> Void
    let onTagSelected: (String) -> Void
    @ObservedObject var tagDisplayCache: ProjectTagDisplayCache

    @State private var editingTagsProject: Project?
    @State private var renamingProject: Project?
    @State private var portConflict: PortConflict?

    private struct PortConflict: Identifiable {
        let id = UUID()
        let project: Project
        let port: Int
    }

    var body: some View {
        VStack(spacing: 1) {
            listHeader
                .padding(.horizontal, AppTheme.cardGridPadding)
                .padding(.top, 8)
                .zIndex(1)

            ProjectRowsTable(
                projects: filteredProjects,
                selectedIDs: selectedProjects,
                displayTags: { tagDisplayCache.displayTags(for: $0, tagManager: tagManager) },
                onAction: handleAction
            )
            .padding(.horizontal, AppTheme.cardGridPadding)
            .padding(.bottom, 8)
        }
        .sheet(item: $editingTagsProject) { project in
            TagEditorView(project: project, tagManager: tagManager)
                .dismissibleSheet(isPresented: Binding(get: { editingTagsProject != nil }, set: { if !$0 { editingTagsProject = nil } }))
        }
        .sheet(item: $renamingProject) { project in
            ProjectRenameDialog(
                project: project,
                isPresented: Binding(get: { renamingProject != nil }, set: { if !$0 { renamingProject = nil } }),
                tagManager: tagManager
            ) { _ in }
            .dismissibleSheet(isPresented: Binding(get: { renamingProject != nil }, set: { if !$0 { renamingProject = nil } }))
        }
        .alert("端口冲突", isPresented: Binding(
            get: { portConflict != nil }, set: { if !$0 { portConflict = nil } }
        ), presenting: portConflict) { request in
            Button("终止占用进程并启动", role: .destructive) {
                _ = ProjectRunner.killProcessAndRun(request.project)
            }
            Button("使用随机端口启动") {
                _ = ProjectRunner.run(request.project, useRandomPort: true)
            }
            Button("取消", role: .cancel) { }
        } message: { request in
            Text("端口 \(request.port) 正在被使用。")
        }
    }

    private func handleAction(_ project: Project, _ action: ProjectRowAction) {
        switch action {
        case .activate(let flags):
            if flags.contains(.shift) || flags.contains(.command) {
                if selectedProjects.contains(project.id) {
                    selectedProjects.remove(project.id)
                } else {
                    selectedProjects.insert(project.id)
                }
            } else {
                onShowProjectDetail(project)
            }
        case .tag(let name): onTagSelected(name)
        case .removeTag(let name): tagManager.removeTagFromProject(projectId: project.id, tag: name)
        case .editor: AppOpenHelper.openInDefaultEditor(path: project.path)
        case .finder: AppOpenHelper.openInFinder(path: project.path)
        case .terminal: AppOpenHelper.performSystemAction(.openInTerminal, path: project.path)
        case .editTags: editingTagsProject = project
        case .rename: renamingProject = project
        case .refresh: tagManager.refreshSingleProject(project.id)
        case .run:
            switch ProjectRunner.run(project) {
            case .success: break
            case .failure(let error): print("启动失败: \(error)")
            case .portBusy(let port, _): portConflict = PortConflict(project: project, port: port)
            }
        }
    }

    private var listHeader: some View {
        HStack(spacing: 12) {
            sortableHeader("项目", column: .name, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("标签")
                .frame(width: 180, alignment: .leading)
            sortableHeader("修改日期", column: .activity, alignment: .leading)
                .frame(width: 150, alignment: .leading)
            sortableHeader("提交", column: .commits, alignment: .trailing)
                .frame(width: 60, alignment: .trailing)
            Text("操作")
                .frame(width: 112, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .foregroundColor(AppTheme.secondaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func sortableHeader(
        _ title: String,
        column: ProjectListSortColumn,
        alignment: Alignment
    ) -> some View {
        Button {
            sortOption = sortOption.toggled(for: column)
        } label: {
            HStack(spacing: 4) {
                Text(title)

                if sortOption.column == column {
                    Image(systemName: sortOption.isAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("按\(title)\(sortOption.toggled(for: column).isAscending ? "升序" : "降序")排列")
        .accessibilityLabel("按\(title)排序")
        .accessibilityValue(
            sortOption.column == column
                ? (sortOption.isAscending ? "升序" : "降序")
                : "未选中"
        )
    }

}

/// 表格只创建可见原生行，不再为每行建立 SwiftUI 视图树。
struct ProjectRowsTable: NSViewRepresentable {
    @AppStorage(TagAppearance.preferenceKey) private var tagAppearance: TagAppearance = .colorful
    let projects: [Project]
    var selectedIDs: Set<UUID> = []
    var displayTags: (Project) -> [TagDisplayData] = { _ in [] }
    var onAction: (Project, ProjectRowAction) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        makeScrollView(coordinator: context.coordinator)
    }

    func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.configureProjectScrollIndicators()

        let table = NativeProjectRowsTableView()
        table.headerView = nil
        table.rowHeight = 42
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAutomaticRowHeights = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("projectRow"))
        column.minWidth = 0
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.delegate = coordinator
        table.dataSource = coordinator
        scrollView.documentView = table
        coordinator.table = table
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.configureProjectScrollIndicators()
        context.coordinator.update(self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private(set) var parent: ProjectRowsTable
        weak var table: NSTableView?
        private var displayedIDs: [UUID] = []

        init(_ parent: ProjectRowsTable) {
            self.parent = parent
        }

        func update(_ parent: ProjectRowsTable) {
            self.parent = parent
            guard let table else { return }
            let ids = parent.projects.map(\.id)
            if ids != displayedIDs {
                displayedIDs = ids
                table.reloadData()
            } else {
                // 选中、标签颜色和 Git 元数据变化时只更新已创建的可见行。
                let visible = table.rows(in: table.visibleRect)
                guard visible.location != NSNotFound, visible.length > 0 else { return }
                for row in visible.location..<NSMaxRange(visible) {
                    guard row < parent.projects.count,
                          let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false)
                            as? NativeProjectListRow else { continue }
                    configure(cell, project: parent.projects[row])
                }
            }
        }

        private func configure(_ cell: NativeProjectListRow, project: Project) {
            cell.onAction = { [weak self] project, action in self?.parent.onAction(project, action) }
            cell.selectedIDs = { [weak self] in self?.parent.selectedIDs ?? [] }
            cell.update(project: project, selected: parent.selectedIDs.contains(project.id), tags: parent.displayTags(project), appearance: parent.tagAppearance)
        }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.projects.count }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            // 继续由原行处理单击详情、Command/Shift 多选，不让原生选择抢走事件。
            false
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.projects.indices.contains(row) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("projectRowCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil)
                as? NativeProjectListRow ?? NativeProjectListRow()
            cell.identifier = identifier
            let project = parent.projects[row]
            configure(cell, project: project)
            return cell
        }
    }
}
