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

    @EnvironmentObject var tagManager: TagManager

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
        
        // 标签筛选
        if !selectedTags.isEmpty {
            if selectedTags.contains("没有标签") {
                projects = projects.filter { $0.tags.isEmpty }
            } else {
                projects = projects.filter { project in
                    selectedTags.isSubset(of: project.tags)
                }
            }
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
                filteredProjects: filteredProjects
            )
        }
        .onAppear {
            loadProjects()
            setupSelectAllMenuCommand()
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
    private func loadProjects() {
        // 立即加载缓存的项目数据
        print("立即加载已缓存的项目数据")
        
        // 使用防抖动延迟加载
        let debounceTime: TimeInterval = 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceTime) {
            // 触发目录重新扫描和项目加载（后台进行）
            tagManager.directoryWatcher.incrementallyReloadProjects()
        }
    }

    // 设置全选菜单命令（通过主菜单实现⌘A）
    private func setupSelectAllMenuCommand() {
        DispatchQueue.main.async {
            // 1. 检查是否已经有我们自己的全局监听器处理了
            if SelectAllHandler.shared != nil {
                return // 已经设置过了
            }
            
            // 2. 创建全局事件监听器（不依赖于菜单项）
            let handler = SelectAllHandler { [self] in
                // 检查当前第一响应者
                if let firstResponder = NSApp.mainWindow?.firstResponder {
                    let className = String(describing: type(of: firstResponder))
                    
                    // 如果焦点在文本控件上，不执行我们的全选
                    if className.contains("Text") || className.contains("Field") || 
                       className.contains("SearchField") || className.contains("TextView") ||
                       className.contains("Input") || className.contains("Editor") {
                        // 不处理，让系统默认行为生效
                        return
                    }
                }
                
                // 执行我们的卡片全选功能
                selectAllProjects()
            }
            
            // 保存到全局变量
            SelectAllHandler.shared = handler
            
            // 3. 添加全局事件监听
            handler.setupGlobalKeyMonitor()
            
            // 4. 检查菜单项（作为备用方案）
            if let editMenu = NSApp.mainMenu?.item(withTitle: "Edit")?.submenu ?? 
                              NSApp.mainMenu?.item(withTitle: "编辑")?.submenu {
                
                // 检查是否有全选菜单项
                let selectAllTitle = "全选"
                let englishTitle = "Select All"
                
                if let selectAllItem = editMenu.item(withTitle: selectAllTitle) ?? editMenu.item(withTitle: englishTitle) {
                    print("找到全选菜单项: \(selectAllItem.title)")
                    
                    // 保存原始动作
                    handler.originalSelector = selectAllItem.action
                    
                    // 添加我们自己的动作作为菜单项的备选
                    let newAction = #selector(SelectAllHandler.menuItemPerformSelectAll(_:))
                    
                    // 替换动作
                    selectAllItem.action = newAction
                    selectAllItem.target = handler
                }
            }
        }
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
                .environmentObject(TagManager())
        }
    }
#endif
