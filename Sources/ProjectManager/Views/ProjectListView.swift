import SwiftUI
import UniformTypeIdentifiers

struct ProjectListView: View {
    // MARK: - 状态变量
    @State private var searchText = ""
    @State private var selectedTags: Set<String> = []
    @State private var isShowingDirectoryPicker = false
    @State private var watchedDirectory: String =
        UserDefaults.standard.string(forKey: "WatchedDirectory")
        ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
        ?? NSHomeDirectory() + "/Desktop"
    @State private var selectedProjects: Set<UUID> = []
    @State private var isShowingNewTagDialog = false
    @State private var tagToRename: IdentifiableString? = nil
    @State private var isDraggingDirectory = false
    @State private var searchBarRef: SearchBar? = nil
    @State private var sortOption: SortOption = .timeDesc
    @State private var selectedDirectory: String? = nil
    @State private var showDetailPanel = false
    @State private var selectedProjectForDetail: Project? = nil

    @EnvironmentObject var tagManager: TagManager
    @ObservedObject private var editorManager = AppOpenHelper.editorManager

    // MARK: - 枚举
    enum SortOption {
        case timeAsc
        case timeDesc
        case commitCount
    }

    // MARK: - 计算属性
    private var filteredProjects: [Project] {
        // 将 Dictionary.Values 转换为 Array
        var projects = Array(tagManager.projects.values)
        
        // 目录筛选
        if let selectedDirectory = selectedDirectory {
            projects = projects.filter { $0.path.hasPrefix(selectedDirectory) }
        }
        
        // 隐藏标签过滤 - 在所有视图下生效，除非当前正在查看被隐藏的标签本身
        projects = projects.filter { project in
            // 获取项目中被隐藏的标签
            let projectHiddenTags = project.tags.filter { tagManager.isTagHidden($0) }
            
            // 如果项目没有隐藏标签，直接显示
            if projectHiddenTags.isEmpty {
                return true
            }
            
            // 如果当前选中的标签中包含项目的某个隐藏标签，则显示该项目
            // 这样用户可以在选择隐藏标签时仍然看到相关项目
            if !selectedTags.isEmpty && !selectedTags.contains("全部") && !selectedTags.contains("没有标签") {
                let currentlyViewingHiddenTag = selectedTags.contains { selectedTag in
                    projectHiddenTags.contains(selectedTag)
                }
                if currentlyViewingHiddenTag {
                    return true
                }
            }
            
            // 其他情况下，如果项目有隐藏标签，则隐藏该项目
            return false
        }
        
        // 标签筛选
        if !selectedTags.isEmpty {
            if selectedTags.contains("没有标签") {
                projects = projects.filter { $0.tags.isEmpty }
            } else if !selectedTags.contains("全部") {
                projects = projects.filter { project in
                    selectedTags.isSubset(of: project.tags)
                }
            }
            // 如果选择的是"全部"，则不进行额外的标签筛选
        }
        
        // 搜索文本筛选
        if !searchText.isEmpty {
            projects = projects.filter { project in
                project.name.localizedCaseInsensitiveContains(searchText) ||
                project.path.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // 排序
        return projects.sorted { (p1: Project, p2: Project) in
            switch sortOption {
            case .timeDesc:
                return p1.lastModified > p2.lastModified
            case .timeAsc:
                return p1.lastModified < p2.lastModified
            case .commitCount:
                let count1 = p1.gitInfo?.commitCount ?? 0
                let count2 = p2.gitInfo?.commitCount ?? 0
                return count1 > count2
            }
        }
    }

    // MARK: - 视图
    var body: some View {
        HSplitView {
            SidebarView(
                selectedTags: $selectedTags,
                searchBarRef: $searchBarRef,
                isDraggingDirectory: $isDraggingDirectory,
                isShowingNewTagDialog: $isShowingNewTagDialog,
                tagToRename: $tagToRename,
                selectedDirectory: $selectedDirectory
            )
            
            MainContentView(
                searchText: $searchText,
                sortOption: $sortOption,
                selectedProjects: $selectedProjects,
                searchBarRef: $searchBarRef,
                editorManager: editorManager,
                filteredProjects: filteredProjects,
                onShowProjectDetail: showProjectDetail
            )
            
            // 详情面板（条件显示）
            if showDetailPanel, let project = selectedProjectForDetail {
                ProjectDetailView(
                    project: convertToProjectData(project),
                    isVisible: $showDetailPanel
                )
                .frame(minWidth: 380, maxWidth: 380)
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .onAppear {
            loadProjects()
            setupSelectAllMenuCommand()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("selectAll"))) { _ in
            selectAllProjects()
        }
        .sheet(item: $tagToRename) { identifiableTag in
            TagEditDialog(
                title: "重命名标签",
                originalName: identifiableTag.value,
                isPresented: .init(
                    get: { tagToRename != nil },
                    set: { if !$0 { tagToRename = nil } }
                ),
                tagManager: tagManager
            ) { newName, color in
                DispatchQueue.main.async {
                    tagManager.renameTag(identifiableTag.value, to: newName, color: color)
                    tagToRename = nil
                }
            }
        }
        .toast()
    }

    // MARK: - 私有方法
    
    private func showProjectDetail(_ project: Project) {
        selectedProjectForDetail = project
        withAnimation(.easeInOut(duration: 0.3)) {
            showDetailPanel = true
        }
    }
    
    private func convertToProjectData(_ project: Project) -> ProjectData {
        // 将 Project 转换为 ProjectData
        return ProjectData(
            id: project.id,
            name: project.name,
            path: project.path,
            lastModified: project.lastModified,
            tags: project.tags,
            gitInfo: project.gitInfo.map { gitInfo in
                ProjectData.GitInfoData(
                    commitCount: gitInfo.commitCount,
                    lastCommitDate: gitInfo.lastCommitDate ?? Date()
                )
            },
            fileSystemInfo: ProjectData.FileSystemInfoData(
                modificationDate: project.lastModified,
                size: 0, // 这里可以从文件系统获取实际大小
                checksum: "",
                lastCheckTime: Date()
            )
        )
    }
    
    private func loadProjects() {
        // 立即加载缓存的项目数据
        print("立即加载已缓存的项目数据")
        
        // 不再自动触发增量更新，改为手动控制
        // 如果需要更新项目，用户可以通过菜单或快捷键手动触发
        print("自动更新已关闭，如需更新项目列表请手动刷新")
    }

    // 设置全选菜单命令（通过主菜单实现⌘A）
    private func setupSelectAllMenuCommand() {
        // Linus式简化：删掉所有依赖注入狗屎
        print("全选功能简化完成")
    }
    
    private func selectAllProjects() {
        // 清空当前选择
        selectedProjects.removeAll()
        
        // 选择所有筛选出的项目
        for project in filteredProjects {
            selectedProjects.insert(project.id)
        }
        
        print("已选择 \(selectedProjects.count) 个项目")
    }
}

#if DEBUG
    struct ProjectListView_Previews: PreviewProvider {
        static var previews: some View {
            ProjectListView()
                .environmentObject({
                    let container = TagManager()
                    return TagManager()
                }())
        }
    }
#endif
