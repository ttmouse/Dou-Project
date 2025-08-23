import SwiftUI

/// 标签编辑器视图，用于管理项目的标签
struct TagEditorView: View {
    @State private var currentProject: Project
    @ObservedObject var tagManager: TagManagerAdapter
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    init(project: Project, tagManager: TagManagerAdapter) {
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

            // 标签列表 - 使用条件判断支持不同macOS版本
            tagListView
        }
        .frame(width: 300, height: 400)
        .background(AppTheme.sidebarBackground)
    }
    
    // MARK: - 私有视图
    
    /// macOS 13及以上版本的标签列表
    @ViewBuilder
    private var tagListView: some View {
        if #available(macOS 13.0, *) {
            modernTagList
        } else {
            legacyTagList
        }
    }
    
    /// 现代macOS版本的标签列表（macOS 13+）
    @available(macOS 13.0, *)
    private var modernTagList: some View {
        List {
            ForEach(filteredTags, id: \.self) { tag in
                createTagRow(for: tag)
                    .listRowBackground(
                        currentProject.tags.contains(tag)
                            ? AppTheme.sidebarSelectedBackground : AppTheme.sidebarBackground
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            .listRowSeparator(.hidden)

            // 创建新标签选项
            createNewTagButton
                .listRowBackground(AppTheme.sidebarBackground)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.sidebarBackground)
    }
    
    /// 旧版macOS的标签列表
    private var legacyTagList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredTags, id: \.self) { tag in
                    createTagRow(for: tag)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            currentProject.tags.contains(tag)
                                ? AppTheme.sidebarSelectedBackground
                                : AppTheme.sidebarBackground
                        )
                }

                // 创建新标签选项
                createNewTagButton
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .background(AppTheme.sidebarBackground)
    }
    
    /// 为指定标签创建行视图
    private func createTagRow(for tag: String) -> some View {
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
        .onTapGesture {
            toggleTag(tag)
        }
    }
    
    /// 创建新标签的按钮
    @ViewBuilder
    private var createNewTagButton: some View {
        if !searchText.isEmpty && !tagManager.allTags.contains(searchText.trimmingCharacters(in: .whitespaces)) {
            Button(action: { addNewTag(searchText) }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("创建标签「\(searchText)」")
                }
                .foregroundColor(AppTheme.accent)
            }
        }
    }
    
    // MARK: - 私有方法
    
    /// 切换标签的选中状态
    private func toggleTag(_ tag: String) {
        if currentProject.tags.contains(tag) {
            tagManager.removeTagFromProject(
                projectId: currentProject.id, tag: tag)
        } else {
            tagManager.addTagToProject(projectId: currentProject.id, tag: tag)
        }
        currentProject = tagManager.projects[currentProject.id] ?? currentProject
    }

    /// 添加新标签
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
struct TagEditorView_Previews: PreviewProvider {
    static var previews: some View {
        TagEditorView(
            project: Project(
                id: UUID(),
                name: "示例项目",
                path: "/Users/example/Projects/demo",
                lastModified: Date(),
                tags: ["Swift", "iOS"]
            ),
            tagManager: {
                let container = ServiceContainer()
                return container.createTagManagerAdapter()
            }()
        )
    }
}
#endif 