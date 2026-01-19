import SwiftUI

struct MainContentView: View {
    @Binding var searchText: String
    @Binding var sortOption: SortOption
    @Binding var dateFilter: DateFilter
    @Binding var selectedProjects: Set<UUID>
    @Binding var searchBarRef: SearchBar?
    @EnvironmentObject var tagManager: TagManager
    @ObservedObject var editorManager: EditorManager
    
    let filteredProjects: [Project]
    let onShowProjectDetail: (Project) -> Void
    let onTagSelected: (String) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            SearchSortBar(
                searchText: $searchText,
                sortOption: $sortOption,
                dateFilter: $dateFilter,
                searchBarRef: $searchBarRef
            )
            
            if filteredProjects.isEmpty {
                EmptyStateView()
            } else {
                ProjectGridView(
                    filteredProjects: filteredProjects,
                    selectedProjects: $selectedProjects,
                    searchBarRef: $searchBarRef,
                    editorManager: editorManager,
                    onShowProjectDetail: onShowProjectDetail,
                    onTagSelected: onTagSelected
                )
            }
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }

            _ = provider.loadObject(ofClass: NSURL.self) { (url, error) in
                if let fileURL = url as? URL {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(
                        atPath: fileURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
                    {
                        DispatchQueue.main.async {
                            // 获取文件的修改时间
                            let modDate =
                                (try? URL(fileURLWithPath: fileURL.path).resourceValues(
                                    forKeys: [.contentModificationDateKey]
                                ).contentModificationDate) ?? Date()

                            let project = Project(
                                name: fileURL.lastPathComponent,
                                path: fileURL.path,
                                lastModified: modDate
                            )
                            tagManager.registerProject(project)
                        }
                    }
                }
            }
            return true
        }
    }
}

// MARK: - 空状态视图
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            Text("没有匹配的项目")
                .font(.headline)

            Text("尝试修改搜索条件或清除标签筛选")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 项目网格视图
struct ProjectGridView: View {
    let filteredProjects: [Project]
    @Binding var selectedProjects: Set<UUID>
    @Binding var searchBarRef: SearchBar?
    @EnvironmentObject var tagManager: TagManager
    @ObservedObject var editorManager: EditorManager
    let onShowProjectDetail: (Project) -> Void
    let onTagSelected: (String) -> Void
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: AppTheme.cardMinWidth,
                            maximum: AppTheme.cardMaxWidth
                        ),
                        spacing: AppTheme.cardGridSpacingH
                    )
                ],
                spacing: AppTheme.cardGridSpacingV
            ) {
                ForEach(filteredProjects) { project in
                    ProjectCard(
                        project: project,
                        isSelected: selectedProjects.contains(project.id),
                        selectedCount: selectedProjects.count,
                        selectedProjects: selectedProjects,
                        tagManager: tagManager,
                        editorManager: editorManager,
                        onTagSelected: { tag in
                            print("🏷️ MainContentView onTagSelected: \(tag)")
                            onTagSelected(tag)
                        },
                        onSelect: { isShiftPressed in
                            handleProjectSelection(project, isShiftPressed: isShiftPressed)
                        },
                        onShowDetail: { onShowProjectDetail(project) }
                    )
                }
            }
            .padding(AppTheme.cardGridPadding)
            .contentShape(Rectangle())
            .onTapGesture {
                // 确保在点击空白区域时，移除现有焦点
                NSApp.keyWindow?.makeFirstResponder(nil)
                // 清除搜索框焦点
                searchBarRef?.clearFocus()
                selectedProjects.removeAll()
            }
        }
        .overlay(alignment: .trailing) {
            ScrollIndicatorView()
        }
    }
    
    
    private func handleProjectSelection(_ project: Project, isShiftPressed: Bool) {
        // 确保在点击卡片时，移除现有焦点
        NSApp.keyWindow?.makeFirstResponder(nil)
        
        // 获取当前的修饰键状态
        let flags = NSEvent.modifierFlags
        let isCommandPressed = flags.contains(.command)
        
        if isShiftPressed || isCommandPressed {
            // Shift 或 Command 键按下时，切换选中状态
            if selectedProjects.contains(project.id) {
                selectedProjects.remove(project.id)
            } else {
                selectedProjects.insert(project.id)
            }
        } else {
            // 没有按下修饰键时，单选
            selectedProjects = [project.id]
        }
    }
}

#if DEBUG
struct MainContentView_Previews: PreviewProvider {
    static var previews: some View {
        MainContentView(
            searchText: .constant(""),
            sortOption: .constant(.timeDesc),
            dateFilter: .constant(.all),
            selectedProjects: .constant([]),
            searchBarRef: .constant(nil),
            editorManager: EditorManager(),
            filteredProjects: [],
            onShowProjectDetail: { _ in },
            onTagSelected: { _ in }
        )
        .environmentObject({
            let container = TagManager()
            return TagManager()
        }())
    }
}
#endif 
