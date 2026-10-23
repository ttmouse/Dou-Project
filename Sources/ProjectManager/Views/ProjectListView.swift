import SwiftUI
import UniformTypeIdentifiers
import Combine

enum ProjectViewMode: String, CaseIterable {
    case grid
    case list

    var title: String {
        switch self {
        case .grid: return "网格视图"
        case .list: return "列表视图"
        }
    }

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
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

    var compactLabel: String {
        switch self {
        case .all:
            return "全部"
        case .lastDay:
            return "1天"
        case .lastWeek:
            return "7天"
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
protocol ProjectListSource: AnyObject {
    var projects: [UUID: Project] { get }
    var listHiddenTags: Set<String> { get }
    var listProjectsChanged: AnyPublisher<Void, Never> { get }
    var listHiddenTagsChanged: AnyPublisher<Set<String>, Never> { get }
    var listGitDailyChanged: AnyPublisher<[UUID: Project], Never> { get }
    func setSortCriteria(_ criteria: TagManager.SortCriteria, ascending: Bool)
    func getSortedProjects() -> [Project]
    func projects(in directory: String) -> [Project]
    func unassignedProjects() -> [Project]
}

extension ProjectListSource {
    var listGitDailyChanged: AnyPublisher<[UUID: Project], Never> {
        Empty().eraseToAnyPublisher()
    }
}

extension TagManager: ProjectListSource {
    var listHiddenTags: Set<String> { appState.filter.hiddenTags }
    var listProjectsChanged: AnyPublisher<Void, Never> {
        $projects.filter { [weak self] _ in self?.isApplyingGitDaily != true }.map { _ in () }
            .merge(with: $watchedDirectories.map { _ in () })
            .eraseToAnyPublisher()
    }
    var listHiddenTagsChanged: AnyPublisher<Set<String>, Never> {
        $appState.map { $0.filter.hiddenTags }.removeDuplicates().eraseToAnyPublisher()
    }
    var listGitDailyChanged: AnyPublisher<[UUID: Project], Never> {
        gitDailyChanges.eraseToAnyPublisher()
    }
}

/// 搜索结果单独持有，只通知列表区域。
///
/// 背景：结果原先挂在页面级 ViewModel 的 `@Published` 上，而页面 body 也读它，
/// 于是每敲一个字都会让整个页面重算 —— 侧边栏的标签统计、目录归属、热力图
/// 区块全部跟着算一遍。结果独立成对象后，页面只持有引用、不订阅变化，
/// 搜索只刷新列表。
final class ProjectResultsStore: ObservableObject {
    @Published private(set) var projects: [Project] = []

    /// 当前生效的查询（已 trim + 小写）。空字符串表示浏览态。
    ///
    /// 用于区分搜索无结果与普通筛选为空的提示，不改变用户选择的视图模式。
    @Published private(set) var query: String = ""

    /// 是否处于搜索态。
    var isSearching: Bool { !query.isEmpty }

    func update(_ projects: [Project], query: String? = nil) {
        if let query, self.query != query {
            self.query = query
        }
        guard self.projects != projects else { return }
        self.projects = projects
    }

    /// Git 历史回填不改变顺序与可见集合，只替换对应位置的元数据。
    func replaceMetadata(_ updates: [UUID: Project]) {
        update(projects.map { updates[$0.id] ?? $0 })
    }
}

@MainActor
class ProjectListViewModel: ObservableObject {
    // MARK: - 属性
    let results = ProjectResultsStore()
    var filteredProjects: [Project] { results.projects }
    let searchInput = ProjectSearchInput()
    var searchText: String {
        get { searchInput.text }
        set { searchInput.text = newValue }
    }
    @Published var selectedTags: Set<String> = []
    @Published var sortOption: SortOption = .timeDescending
    @Published var dateFilter: DateFilter = .all
    @Published var selectedDirectory: String? = nil
    @Published var heatmapFilteredProjectIds: Set<UUID> = []

    /// 稳定的回调闭包宿主。
    ///
    /// 背景：把方法引用（如 `handleTagSelection`）直接传给子视图时，
    /// 每次父视图 body 求值都会产生**新的闭包身份**，SwiftUI 因此判定
    /// 子视图需要重算 —— 搜索时每敲一个字，侧边栏与网格都会整块重绘。
    /// 存进 ViewModel（引用类型）后闭包身份保持不变，子视图只在自己
    /// 关心的状态变化时才重算。
    ///
    /// 动作本身由视图注入，避免 ViewModel 反向依赖视图。
    var tagSelectionHandler: (String) -> Void = { _ in }
    var projectDetailHandler: (Project) -> Void = { _ in }

    private weak var tagManager: ProjectListSource?
    private var cancellables = Set<AnyCancellable>()
    private var orderedProjects: [Project] = []
    private var searchCandidates: [Project] = []
    private var searchIndex: [UUID: String] = [:]
    private var isSetup = false

    init() {
        // 延迟设置 tagManager，因为需要从环境对象中获取
    }

    // 设置 tagManager 引用（在视图的 onAppear 中调用）
    func setTagManager(_ tagManager: ProjectListSource) {
        guard !isSetup else { return }  // 只设置一次
        self.tagManager = tagManager
        rebuildSearchIndex()
        applySortOption()
        setupBindings()
        updateFilteredProjects()
        isSetup = true
    }
    
    // MARK: - 绑定监听（带防抖）
    private func setupBindings() {
        guard let tagManager = tagManager else { return }

        tagManager.listGitDailyChanged
            .sink { [weak self] updates in
                guard let self = self else { return }
                // 历史不影响筛选及排序，保留顺序与可见集合，也不重建搜索索引。
                self.orderedProjects = self.orderedProjects.map { updates[$0.id] ?? $0 }
                self.searchCandidates = self.searchCandidates.map { updates[$0.id] ?? $0 }
                self.results.replaceMetadata(updates)
            }
            .store(in: &cancellables)
        
        // 监听 projects 变化，使用防抖
        tagManager.listProjectsChanged
            .dropFirst()  // 跳过初始值
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)  // 150ms 防抖
            .sink { [weak self] _ in
                self?.rebuildSearchIndex()
                self?.refreshOrderedProjects()
                self?.updateFilteredProjects()
            }
            .store(in: &cancellables)

        // 监听 hiddenTags 变化
        tagManager.listHiddenTagsChanged
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFilteredProjects()
            }
            .store(in: &cancellables)
        
        // 监听其他本地状态变化
        searchInput.$text
            // 本地内存查询无需等待停顿；下一轮主队列读取已写入的最新文字。
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSearchResults()
            }
            .store(in: &cancellables)
        
        $selectedTags
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)  // 标签选择 100ms 防抖
            .sink { [weak self] _ in
                self?.updateFilteredProjects()
            }
            .store(in: &cancellables)
        
        $sortOption
            // @Published 在属性写入前发送；切到下一轮主队列再读取完整状态。
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySortOption()
                self?.updateFilteredProjects()
            }
            .store(in: &cancellables)
        
        $dateFilter
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
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

        // 1. 从已排序的项目源开始。搜索和其他筛选只保留顺序，不重新排序。
        var projects = orderedProjects
        
        // 2. 目录筛选（与侧边栏徽章计数同一逻辑：组件边界匹配 + 未分类哨兵）
        if let selectedDirectory = selectedDirectory {
            let directoryProjects = selectedDirectory == DirectoryLogic.unassignedKey
                ? tagManager.unassignedProjects()
                : tagManager.projects(in: selectedDirectory)
            let directoryProjectIDs = Set(directoryProjects.map(\.id))
            projects = projects.filter { directoryProjectIDs.contains($0.id) }
        }
        
        // 3. 隐藏标签过滤：一次读取隐藏标签集合，避免逐项目调用状态查询并创建临时数组。
        let hiddenTags = tagManager.listHiddenTags
        let canViewHiddenTag = !selectedTags.isEmpty &&
            !selectedTags.contains("全部") &&
            !selectedTags.contains("没有标签")
        if !hiddenTags.isEmpty {
            // 每次筛选只算一次集合；常见的「没有隐藏标签」直接跳过整轮遍历。
            let selectedHiddenTags = canViewHiddenTag ? selectedTags.intersection(hiddenTags) : []
            projects = projects.filter { project in
                project.tags.isDisjoint(with: hiddenTags) ||
                    !project.tags.isDisjoint(with: selectedHiddenTags)
            }
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
        
        searchCandidates = projects
        updateSearchResults()
    }

    /// 输入只查询已有候选，不重复解析目录和标签归属。
    private func updateSearchResults() {
        var projects = searchCandidates
        // 6. 搜索文本筛选
        // 不在这里读取 Project.notes：它会同步访问磁盘，输入每个字符都会触发一次 I/O，
        // 这是搜索“卡住”的主要来源。普通搜索只匹配项目名，不匹配路径和用户名。
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        if !query.isEmpty {
            projects = projects.filter { project in
                searchIndex[project.id]?.contains(query) == true
            }
        }

        // 7. 日期筛选
        if let cutoff = dateFilter.cutoffDate {
            projects = projects.filter { project in
                project.activityAt >= cutoff
            }
        }
        
        // 8. 不在这里排序：orderedProjects 已经按当前排序方式排好，筛选天然保持顺序。
        results.update(projects, query: query)
    }

    private func applySortOption() {
        guard let tagManager = tagManager else { return }

        let criteria: TagManager.SortCriteria
        switch sortOption.column {
        case .name:
            criteria = .name
        case .activity:
            criteria = .lastModified
        case .commits:
            criteria = .gitCommits
        }

        tagManager.setSortCriteria(criteria, ascending: sortOption.isAscending)
        refreshOrderedProjects()
    }

    private func refreshOrderedProjects() {
        orderedProjects = tagManager?.getSortedProjects() ?? []
    }

    private func rebuildSearchIndex() {
        guard let tagManager = tagManager else { return }

        let allProjects = Array(tagManager.projects.values)
        searchIndex = Dictionary(uniqueKeysWithValues: allProjects.map { project in
            (project.id, project.name.localizedLowercase)
        })
    }
    
    // MARK: - 手动刷新（用于某些特殊情况）
    func forceRefresh() {
        updateFilteredProjects()
    }
}

enum DetailPanelPresentationLogic {
    static func targetProjectID(
        isPanelVisible: Bool,
        currentProjectID: UUID?,
        selectedProjectIDs: Set<UUID>,
        visibleProjectIDs: [UUID]
    ) -> UUID? {
        guard isPanelVisible else { return nil }

        if let currentProjectID, visibleProjectIDs.contains(currentProjectID) {
            return currentProjectID
        }

        if let selectedProjectID = visibleProjectIDs.first(where: selectedProjectIDs.contains) {
            return selectedProjectID
        }

        return visibleProjectIDs.first
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
    @State private var projectViewMode: ProjectViewMode = .grid
    @State private var selectedProjectForDetailId: UUID? = nil
    // 临时禁用性能监控功能
    // @State private var showPerformanceMonitor = false

    @EnvironmentObject var tagManager: TagManager
    @ObservedObject private var editorManager = AppOpenHelper.editorManager

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
                searchInput: viewModel.searchInput,
                results: viewModel.results,
                sortOption: $viewModel.sortOption,
                dateFilter: $viewModel.dateFilter,
                selectedProjects: $selectedProjects,
                searchBarRef: $searchBarRef,
                showDetailPanel: $showDetailPanel,
                projectViewMode: $projectViewMode,
                editorManager: editorManager,
                onShowProjectDetail: showProjectDetail,
                onTagSelected: handleTagSelection
            )
            
            // 详情面板（条件显示）。单独持有结果对象，
            // 搜索结果变化只让它自己重算，不牵动侧边栏和网格。
            if showDetailPanel {
                ProjectDetailPanelContainer(
                    results: viewModel.results,
                    selectedProjectIDs: selectedProjects,
                    currentProjectID: $selectedProjectForDetailId,
                    isVisible: $showDetailPanel,
                    tagManager: tagManager
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .environmentObject(tagManager)
        .background {
            Button(action: copySelectedProjectPaths) {
                EmptyView()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
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
            selectedProjects = [project.id]
        }

        // A closed panel is inert: selecting a card must not prepare or present details.
        if showDetailPanel {
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

    private func copySelectedProjectPaths() {
        let paths = selectedProjects.compactMap { tagManager.projects[$0]?.path }.sorted()
        guard !paths.isEmpty else { return }

        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string) else {
            return
        }

        let soundURL = Bundle.main.url(
            forResource: "speech_stop",
            withExtension: "wav",
            subdirectory: "RTC"
        ) ?? Bundle.module.url(
            forResource: "speech_stop",
            withExtension: "wav",
            subdirectory: "Resources/RTC"
        )
        guard let soundURL else {
            return
        }

        if let sound = NSSound(contentsOf: soundURL, byReference: false) {
            sound.volume = 0.6
            sound.play()
        }
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
