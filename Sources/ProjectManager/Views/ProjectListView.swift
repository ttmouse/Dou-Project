import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - 项目列表视图的枚举定义（共享）
enum SortOption {
    case timeAsc
    case timeDesc
    case commitCount
}

enum DateFilter: CaseIterable {
    case all
    case lastDay
    case lastWeek
    
    var title: String {
        switch self {
        case .all:
            return "全部日期"
        case .lastDay:
            return "最近一天"
        case .lastWeek:
            return "最近一周"
        }
    }
    
    var shortLabel: String {
        switch self {
        case .all:
            return "全部"
        case .lastDay:
            return "最近1天"
        case .lastWeek:
            return "最近7天"
        }
    }
    
    var cutoffDate: Date? {
        switch self {
        case .all:
            return nil
        case .lastDay:
            return Calendar.current.date(byAdding: .day, value: -1, to: Date())
        case .lastWeek:
            return Calendar.current.date(byAdding: .day, value: -7, to: Date())
        }
    }
}

// MARK: - 性能优化：ViewModel 管理状态和防抖
@MainActor
class ProjectListViewModel: ObservableObject {
    // MARK: - 属性
    @Published var filteredProjects: [Project] = []
    @Published var searchText: String = ""
    @Published var selectedTags: Set<String> = []
    @Published var sortOption: SortOption = .timeDesc
    @Published var dateFilter: DateFilter = .all
    @Published var selectedDirectory: String? = nil
    @Published var heatmapFilteredProjectIds: Set<UUID> = []

    private weak var tagManager: TagManager?
    private var debounceWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var isSetup = false

    init() {
        // 延迟设置 tagManager，因为需要从环境对象中获取
    }

    // 设置 tagManager 引用（在视图的 onAppear 中调用）
    func setTagManager(_ tagManager: TagManager) {
        guard !isSetup else { return }  // 只设置一次
        self.tagManager = tagManager
        setupBindings()
        updateFilteredProjects()
        isSetup = true
    }
    
    // MARK: - 绑定监听（带防抖）
    private func setupBindings() {
        guard let tagManager = tagManager else { return }
        
        // 监听 projects 变化，使用防抖
        tagManager.$projects
            .dropFirst()  // 跳过初始值
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)  // 150ms 防抖
            .sink { [weak self] _ in
                self?.updateFilteredProjects()
            }
            .store(in: &cancellables)
        
        // 监听 hiddenTags 变化
        tagManager.$hiddenTags
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFilteredProjects()
            }
            .store(in: &cancellables)
        
        // 监听其他本地状态变化
        $searchText
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)  // 搜索 200ms 防抖
            .sink { [weak self] _ in
                self?.updateFilteredProjects()
            }
            .store(in: &cancellables)
        
        $selectedTags
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)  // 标签选择 100ms 防抖
            .sink { [weak self] _ in
                self?.updateFilteredProjects()
            }
            .store(in: &cancellables)
        
        $sortOption
            .sink { [weak self] _ in
                self?.updateFilteredProjects()
            }
            .store(in: &cancellables)
        
        $dateFilter
            .sink { [weak self] _ in
                self?.updateFilteredProjects()
            }
            .store(in: &cancellables)
        
        $selectedDirectory
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFilteredProjects()
            }
            .store(in: &cancellables)
        
        $heatmapFilteredProjectIds
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFilteredProjects()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 核心过滤逻辑（缓存结果）
    private func updateFilteredProjects() {
        guard let tagManager = tagManager else { return }

        // 1. 获取原始项目数组
        var projects = Array(tagManager.projects.values)
        
        // 2. 目录筛选
        if let selectedDirectory = selectedDirectory {
            projects = projects.filter { $0.path.hasPrefix(selectedDirectory) }
        }
        
        // 3. 隐藏标签过滤
        projects = projects.filter { project in
            let projectHiddenTags = project.tags.filter { tagManager.isTagHidden($0) }
            
            if projectHiddenTags.isEmpty {
                return true
            }
            
            if !selectedTags.isEmpty && !selectedTags.contains("全部") && !selectedTags.contains("没有标签") {
                let currentlyViewingHiddenTag = selectedTags.contains { selectedTag in
                    projectHiddenTags.contains(selectedTag)
                }
                return currentlyViewingHiddenTag
            }
            
            return false
        }
        
        // 4. 热力图筛选 - 最高优先级
        if !heatmapFilteredProjectIds.isEmpty {
            projects = projects.filter { heatmapFilteredProjectIds.contains($0.id) }
        }
        // 5. 标签筛选
        else if !selectedTags.isEmpty {
            if selectedTags.contains("没有标签") {
                projects = projects.filter { $0.tags.isEmpty }
            } else if !selectedTags.contains("全部") {
                projects = projects.filter { project in
                    selectedTags.isSubset(of: project.tags)
                }
            }
        }
        
        // 6. 搜索文本筛选
        if !searchText.isEmpty {
            projects = projects.filter { project in
                project.name.localizedCaseInsensitiveContains(searchText) ||
                project.path.localizedCaseInsensitiveContains(searchText) ||
                (project.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // 7. 日期筛选
        if let cutoff = dateFilter.cutoffDate {
            projects = projects.filter { project in
                project.lastModified >= cutoff
            }
        }
        
        // 8. 排序
        filteredProjects = projects.sorted { (p1: Project, p2: Project) in
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
    
    // MARK: - 手动刷新（用于某些特殊情况）
    func forceRefresh() {
        updateFilteredProjects()
    }
}

// MARK: - 主视图
struct ProjectListView: View {
    // MARK: - 状态变量
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
    @State private var showDetailPanel = false
    @State private var selectedProjectForDetailId: UUID? = nil
    // 临时禁用性能监控功能
    // @State private var showPerformanceMonitor = false

    @EnvironmentObject var tagManager: TagManager
    @ObservedObject private var editorManager = AppOpenHelper.editorManager

    private var selectedProjectForDetail: Project? {
        guard let id = selectedProjectForDetailId else { return nil }
        return tagManager.projects[id]
    }

    // 延迟初始化 ViewModel（需要 tagManager）
    @StateObject private var viewModel = ProjectListViewModel()

    // MARK: - 初始化
    init() {}

    // MARK: - 视图
    var body: some View {
        HSplitView {
            SidebarView(
                selectedTags: $viewModel.selectedTags,
                searchBarRef: $searchBarRef,
                selectedProjects: $selectedProjects,
                isDraggingDirectory: $isDraggingDirectory,
                isShowingNewTagDialog: $isShowingNewTagDialog,
                tagToRename: $tagToRename,
                selectedDirectory: $viewModel.selectedDirectory,
                heatmapFilteredProjectIds: $viewModel.heatmapFilteredProjectIds,
                onTagSelected: handleTagSelection
            )
            
            MainContentView(
                searchText: $viewModel.searchText,
                sortOption: $viewModel.sortOption,
                dateFilter: $viewModel.dateFilter,
                selectedProjects: $selectedProjects,
                searchBarRef: $searchBarRef,
                showDetailPanel: $showDetailPanel,
                editorManager: editorManager,
                filteredProjects: viewModel.filteredProjects,
                onShowProjectDetail: showProjectDetail,
                onTagSelected: handleTagSelection
            )
            
            // 详情面板（条件显示）
            if showDetailPanel, let project = selectedProjectForDetail {
                ProjectDetailView(
                    project: convertToProjectData(project),
                    isVisible: $showDetailPanel,
                    tagManager: tagManager
                )
                .frame(minWidth: 380, maxWidth: 380)
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .environmentObject(tagManager)
        .background(SelectAllResponder(action: selectAllProjects))
        .onAppear {
            // 设置 viewModel 的 tagManager 引用
            viewModel.setTagManager(tagManager)
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
                tagManager.renameTag(identifiableTag.value, to: newName, color: color)
                tagToRename = nil
            }
        }
        .toast()
        // 临时禁用性能监控通知
        // .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("togglePerformanceMonitor"))) { _ in
        //     showPerformanceMonitor.toggle()
        // }
    }

    // MARK: - 私有方法
    
    private func handleTagSelection(_ tag: String) {
        print("🏷️ 标签点击: \(tag)")
        NSApp.keyWindow?.makeFirstResponder(nil)
        searchBarRef?.clearFocus()
        
        if tag == "全部" {
            viewModel.selectedTags.removeAll()
        } else {
            viewModel.selectedTags = [tag]
        }
        print("🏷️ 已选中标签: \(viewModel.selectedTags)")
    }
    
    private func showProjectDetail(_ project: Project) {
        let currentSelectedCount = selectedProjects.count
        
        if currentSelectedCount <= 1 {
            selectedProjectForDetailId = project.id
            selectedProjects = [project.id]
        } else {
            selectedProjectForDetailId = project.id
        }
    }
    
    private func convertToProjectData(_ project: Project) -> ProjectData {
        return ProjectData(from: project)
    }
    
    private func loadProjects() {
        print("立即加载已缓存的项目数据")
        print("自动更新已关闭，如需更新项目列表请手动刷新")
    }

    private func setupSelectAllMenuCommand() {
        print("全选功能简化完成")
    }
    
    private func selectAllProjects() {
        selectedProjects.removeAll()
        
        for project in viewModel.filteredProjects {
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
