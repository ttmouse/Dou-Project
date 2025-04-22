import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 辅助函数
private func openInCursor(path: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/local/bin/cursor")
    task.arguments = [path]

    do {
        try task.run()
    } catch {
        print("Error opening Cursor: \(error)")

        // 如果直接打开失败，尝试使用 open 命令
        let openTask = Process()
        openTask.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openTask.arguments = ["-a", "Cursor", path]

        do {
            try openTask.run()
        } catch {
            print("Error using open command: \(error)")
        }
    }
}

struct ProjectCard: View {
    let project: Project
    let isSelected: Bool
    let selectedCount: Int  // 添加选中数量
    let selectedProjects: Set<UUID>  // 添加选中的项目集合
    @ObservedObject var tagManager: TagManager
    @State private var isEditingTags = false
    let onTagSelected: (String) -> Void
    let onSelect: (Bool) -> Void

    private var headerView: some View {
        HStack {
            Text(project.name)
                .font(AppTheme.titleFont)
                .foregroundColor(AppTheme.text)
                .lineLimit(1)

            Spacer()

            // 编辑标签按钮
            Button(action: { isEditingTags = true }) {
                Image(systemName: "tag")
                    .foregroundColor(AppTheme.secondaryIcon)
            }
            .buttonStyle(.plain)
            .help("编辑标签")

            // 在 Cursor 中打开按钮
            Button(action: { openInCursor(path: project.path) }) {
                Image(systemName: "cursorarrow.rays")
                    .foregroundColor(AppTheme.secondaryIcon)
            }
            .buttonStyle(.plain)
            .help("在 Cursor 中打开")

            // 打开文件夹按钮
            Button(action: {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
            }) {
                Image(systemName: "folder")
                    .foregroundColor(AppTheme.folderIcon)
            }
            .buttonStyle(.plain)
            .help("打开文件夹")
        }
    }

    private var pathView: some View {
        Text(project.path)
            .font(AppTheme.captionFont)
            .foregroundColor(AppTheme.secondaryText)
            .lineLimit(1)
    }

    private var infoView: some View {
        HStack {
            // 日期信息
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .foregroundColor(AppTheme.secondaryIcon)
                Text(project.lastModified, style: .date)
                    + Text(" ")
                    + Text(project.lastModified, style: .time)
            }
            .font(AppTheme.captionFont)
            .foregroundColor(AppTheme.secondaryText)

            Spacer()

            // Git 提交次数
            if let gitInfo = project.gitInfo {
                HStack(spacing: 4) {
                    Text("\(gitInfo.commitCount)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                    Text("次提交")
                        .font(AppTheme.captionFont)
                        .foregroundColor(AppTheme.secondaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.accent.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }

    private var tagsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(project.tags).sorted(), id: \.self) { tag in
                    TagView(
                        tag: tag,
                        color: tagManager.getColor(for: tag),
                        fontSize: 13,
                        onDelete: {
                            tagManager.removeTagFromProject(projectId: project.id, tag: tag)
                        }
                    )
                    .onTapGesture {
                        onTagSelected(tag)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            pathView
            infoView
            tagsView
            Spacer(minLength: 0)
        }
        .padding(AppTheme.cardPadding)
        .frame(height: AppTheme.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .fill(isSelected ? AppTheme.cardSelectedBackground : AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .strokeBorder(
                    isSelected ? AppTheme.cardSelectedBorder : AppTheme.cardBorder,
                    lineWidth: isSelected
                        ? AppTheme.cardSelectedBorderWidth : AppTheme.cardBorderWidth
                )
        )
        .shadow(
            color: isSelected ? AppTheme.cardSelectedShadow : AppTheme.cardShadow,
            radius: isSelected ? AppTheme.cardSelectedShadowRadius : 4,
            x: 0,
            y: 2
        )
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            onSelect(flags.contains(.shift))
        }
        .onDrag {
            // 确保当前项目被选中
            onSelect(false)
            // 创建包含所有选中项目的数据
            let selectedIds = selectedCount > 1 ? selectedProjects : [project.id]
            let data = try? JSONEncoder().encode(selectedIds)
            return NSItemProvider(item: data as NSData?, typeIdentifier: UTType.data.identifier)
        } preview: {
            // 拖拽预览
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .foregroundColor(AppTheme.folderIcon)
                if selectedCount > 1 {
                    Text("\(selectedCount) 个项目")
                        .foregroundColor(AppTheme.text)
                } else {
                    Text(project.name)
                        .foregroundColor(AppTheme.text)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.cardBackground)
            .cornerRadius(4)
            .frame(maxWidth: 200)
        }
        .sheet(isPresented: $isEditingTags) {
            TagEditorView(project: project, tagManager: tagManager)
        }
    }
}

// MARK: - 标签编辑器视图
struct TagEditorView: View {
    @State private var currentProject: Project
    @ObservedObject var tagManager: TagManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    init(project: Project, tagManager: TagManager) {
        _currentProject = State(initialValue: project)
        self.tagManager = tagManager
    }

    private var filteredTags: [String] {
        let allTags = Array(tagManager.allTags).sorted()
        if searchText.isEmpty {
            return allTags
        }
        return allTags.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HStack {
                // 搜索框
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppTheme.sidebarSecondaryText)
                    TextField("搜索或创建新标签", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(AppTheme.searchBarFont)
                        .foregroundColor(AppTheme.searchBarText)
                        .onSubmit {
                            if !searchText.isEmpty {
                                addNewTag(searchText)
                            }
                        }
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppTheme.sidebarSecondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(AppTheme.sidebarDirectoryBackground)
                .cornerRadius(6)

                // 确认按钮
                Button("确定") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.sidebarDirectoryBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(AppTheme.sidebarDirectoryBorder, lineWidth: 1)
                )
            }
            .padding()
            .background(AppTheme.sidebarBackground)

            // 标签列表
            if #available(macOS 13.0, *) {
                List {
                    ForEach(filteredTags, id: \.self) { tag in
                        HStack {
                            TagView(
                                tag: tag,
                                color: tagManager.getColor(for: tag),
                                fontSize: 13,
                                isSelected: currentProject.tags.contains(tag)
                            )
                            Spacer()
                            if currentProject.tags.contains(tag) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(AppTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                        .listRowBackground(
                            currentProject.tags.contains(tag)
                                ? AppTheme.sidebarSelectedBackground : AppTheme.sidebarBackground
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .onTapGesture {
                            if currentProject.tags.contains(tag) {
                                tagManager.removeTagFromProject(
                                    projectId: currentProject.id, tag: tag)
                            } else {
                                tagManager.addTagToProject(projectId: currentProject.id, tag: tag)
                            }
                            currentProject =
                                tagManager.projects[currentProject.id] ?? currentProject
                        }
                    }
                    .listRowSeparator(.hidden)

                    // 如果搜索的标签不存在，显示创建选项
                    if !searchText.isEmpty
                        && !tagManager.allTags.contains(
                            searchText.trimmingCharacters(in: .whitespaces))
                    {
                        Button(action: { addNewTag(searchText) }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("创建标签「\(searchText)」")
                            }
                            .foregroundColor(AppTheme.accent)
                        }
                        .listRowBackground(AppTheme.sidebarBackground)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AppTheme.sidebarBackground)
            } else {
                // 旧版本 macOS 的实现
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredTags, id: \.self) { tag in
                            HStack {
                                TagView(
                                    tag: tag,
                                    color: tagManager.getColor(for: tag),
                                    fontSize: 13,
                                    isSelected: currentProject.tags.contains(tag)
                                )
                                Spacer()
                                if currentProject.tags.contains(tag) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(AppTheme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                currentProject.tags.contains(tag)
                                    ? AppTheme.sidebarSelectedBackground
                                    : AppTheme.sidebarBackground
                            )
                            .onTapGesture {
                                if currentProject.tags.contains(tag) {
                                    tagManager.removeTagFromProject(
                                        projectId: currentProject.id, tag: tag)
                                } else {
                                    tagManager.addTagToProject(
                                        projectId: currentProject.id, tag: tag)
                                }
                                currentProject =
                                    tagManager.projects[currentProject.id] ?? currentProject
                            }
                        }

                        // 如果搜索的标签不存在，显示创建选项
                        if !searchText.isEmpty
                            && !tagManager.allTags.contains(
                                searchText.trimmingCharacters(in: .whitespaces))
                        {
                            Button(action: { addNewTag(searchText) }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("创建标签「\(searchText)」")
                                }
                                .foregroundColor(AppTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }
                .background(AppTheme.sidebarBackground)
            }
        }
        .frame(width: 300, height: 400)
        .background(AppTheme.sidebarBackground)
    }

    private func addNewTag(_ text: String) {
        let tag = text.trimmingCharacters(in: .whitespaces)
        if !tag.isEmpty {
            // 使用随机预设颜色
            let color = AppTheme.tagPresetColors.randomElement()?.color ?? AppTheme.accent
            tagManager.addTag(tag, color: color)
            tagManager.addTagToProject(projectId: currentProject.id, tag: tag)
            currentProject = tagManager.projects[currentProject.id] ?? currentProject
            searchText = ""
        }
    }
}

#if DEBUG
    struct ProjectCard_Previews: PreviewProvider {
        static var previews: some View {
            ProjectCard(
                project: Project(
                    id: UUID(),
                    name: "示例项目",
                    path: "/Users/example/Projects/demo",
                    lastModified: Date(),
                    tags: ["Swift", "iOS"]
                ),
                isSelected: false,
                selectedCount: 1,
                selectedProjects: Set(),
                tagManager: TagManager(),
                onTagSelected: { _ in },
                onSelect: { _ in }
            )
            .padding()
        }
    }
#endif
