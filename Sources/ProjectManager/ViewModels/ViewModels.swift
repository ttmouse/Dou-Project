import Foundation
import SwiftUI
import Combine

// MARK: - 视图模型层
// 遵循"数据与逻辑分离"原则，ViewModel只负责UI状态管理，业务逻辑委托给Logic层

/// 项目列表视图模型
class ProjectListViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var displayedProjects: [ProjectData] = []
    @Published var selectedProjectIds: Set<UUID> = []
    @Published var isLoading: Bool = false
    @Published var searchText: String = ""
    @Published var selectedTags: Set<String> = []
    @Published var sortCriteria: SortCriteriaData = .lastModified
    @Published var isAscending: Bool = false
    
    // MARK: - Dependencies
    private let appStateManager: AppStateManager
    private var cancellables = Set<AnyCancellable>()
    
    init(appStateManager: AppStateManager) {
        self.appStateManager = appStateManager
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    func loadProjects() {
        isLoading = true
        // 实际的加载逻辑委托给AppStateManager
        // 这里只更新UI状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isLoading = false
        }
    }
    
    func selectProject(_ projectId: UUID) {
        if selectedProjectIds.contains(projectId) {
            selectedProjectIds.remove(projectId)
        } else {
            selectedProjectIds.insert(projectId)
        }
    }
    
    func selectAllProjects() {
        selectedProjectIds = Set(displayedProjects.map { $0.id })
    }
    
    func clearSelection() {
        selectedProjectIds.removeAll()
    }
    
    func addTagToSelectedProjects(_ tag: String) {
        for projectId in selectedProjectIds {
            appStateManager.addTagToProject(projectId: projectId, tagName: tag)
        }
        clearSelection()
    }
    
    func updateSearchText(_ text: String) {
        searchText = text
        appStateManager.setSearchText(text)
    }
    
    func updateSelectedTags(_ tags: Set<String>) {
        selectedTags = tags
        appStateManager.setSelectedTags(tags)
    }
    
    func updateSortCriteria(_ criteria: SortCriteriaData, ascending: Bool) {
        sortCriteria = criteria
        isAscending = ascending
        appStateManager.setSortCriteria(criteria, ascending: ascending)
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // 监听AppStateManager的变化
        appStateManager.$processedProjects
            .receive(on: DispatchQueue.main)
            .assign(to: \.displayedProjects, on: self)
            .store(in: &cancellables)
        
        // 同步筛选状态
        appStateManager.$appState
            .map { $0.filter.searchText }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.searchText, on: self)
            .store(in: &cancellables)
        
        appStateManager.$appState
            .map { $0.filter.selectedTags }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.selectedTags, on: self)
            .store(in: &cancellables)
        
        appStateManager.$appState
            .map { $0.filter.sortCriteria }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.sortCriteria, on: self)
            .store(in: &cancellables)
        
        appStateManager.$appState
            .map { $0.filter.isAscending }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.isAscending, on: self)
            .store(in: &cancellables)
    }
}

/// 侧边栏视图模型
class SidebarViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var displayedTags: [TagData] = []
    @Published var selectedTag: String? = nil
    @Published var tagStatistics: [String: Int] = [:]
    @Published var watchedDirectories: Set<String> = []
    @Published var showingTagEditor: Bool = false
    @Published var editingTag: TagData? = nil
    
    // MARK: - Dependencies
    private let appStateManager: AppStateManager
    private var cancellables = Set<AnyCancellable>()
    
    init(appStateManager: AppStateManager) {
        self.appStateManager = appStateManager
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    func selectTag(_ tagName: String?) {
        selectedTag = tagName
        
        if let tagName = tagName {
            let currentTags = appStateManager.currentFilter.selectedTags
            let newTags: Set<String>
            
            if tagName == "全部" {
                newTags = []
            } else if tagName == "没有标签" {
                newTags = ["没有标签"]
            } else {
                // 切换标签选择状态
                if currentTags.contains(tagName) {
                    newTags = currentTags.subtracting([tagName])
                } else {
                    newTags = currentTags.union([tagName])
                }
            }
            
            appStateManager.setSelectedTags(newTags)
        }
    }
    
    func toggleTagVisibility(_ tagName: String) {
        appStateManager.toggleTagVisibility(tagName: tagName)
    }
    
    func addWatchedDirectory(_ path: String) {
        appStateManager.addWatchedDirectory(path)
    }
    
    func removeWatchedDirectory(_ path: String) {
        appStateManager.removeWatchedDirectory(path)
    }
    
    func showTagEditor(for tag: TagData? = nil) {
        editingTag = tag
        showingTagEditor = true
    }
    
    func hideTagEditor() {
        showingTagEditor = false
        editingTag = nil
    }
    
    // MARK: - Computed Properties
    
    var systemTags: [TagData] {
        return [
            TagData(id: "全部", name: "全部", color: TagColorData(red: 0.4, green: 0.6, blue: 0.9), usageCount: appStateManager.allProjects.count, isHidden: false, isSystemTag: true),
            TagData(id: "没有标签", name: "没有标签", color: TagColorData(red: 0.5, green: 0.5, blue: 0.5), usageCount: noTagProjectsCount, isHidden: false, isSystemTag: true)
        ]
    }
    
    private var noTagProjectsCount: Int {
        return appStateManager.allProjects.filter { $0.tags.isEmpty }.count
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // 监听标签变化
        appStateManager.$appState
            .map { state in
                Array(state.tags.values).filter { !state.filter.hiddenTags.contains($0.name) }
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.displayedTags, on: self)
            .store(in: &cancellables)
        
        // 监听统计信息变化
        appStateManager.$appState
            .map { state in
                TagLogic.calculateTagUsage(Array(state.projects.values))
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.tagStatistics, on: self)
            .store(in: &cancellables)
        
        // 监听监视目录变化
        appStateManager.$appState
            .map { $0.watchedDirectories }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.watchedDirectories, on: self)
            .store(in: &cancellables)
        
        // 监听选中标签变化
        appStateManager.$appState
            .map { state in
                if state.filter.selectedTags.isEmpty {
                    return "全部"
                } else if state.filter.selectedTags.contains("没有标签") {
                    return "没有标签"
                } else {
                    return state.filter.selectedTags.first
                }
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.selectedTag, on: self)
            .store(in: &cancellables)
    }
}

/// 搜索栏视图模型
class SearchBarViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var searchText: String = ""
    @Published var isSearching: Bool = false
    @Published var sortCriteria: SortCriteriaData = .lastModified
    @Published var isAscending: Bool = false
    
    // MARK: - Dependencies
    private let appStateManager: AppStateManager
    private var cancellables = Set<AnyCancellable>()
    
    init(appStateManager: AppStateManager) {
        self.appStateManager = appStateManager
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    func updateSearchText(_ text: String) {
        searchText = text
        isSearching = !text.isEmpty
        appStateManager.setSearchText(text)
    }
    
    func clearSearch() {
        updateSearchText("")
    }
    
    func updateSortCriteria(_ criteria: SortCriteriaData) {
        sortCriteria = criteria
        appStateManager.setSortCriteria(criteria, ascending: isAscending)
    }
    
    func toggleSortDirection() {
        isAscending.toggle()
        appStateManager.setSortCriteria(sortCriteria, ascending: isAscending)
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // 同步搜索文本
        appStateManager.$appState
            .map { $0.filter.searchText }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                if self?.searchText != text {
                    self?.searchText = text
                    self?.isSearching = !text.isEmpty
                }
            }
            .store(in: &cancellables)
        
        // 同步排序设置
        appStateManager.$appState
            .map { $0.filter.sortCriteria }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.sortCriteria, on: self)
            .store(in: &cancellables)
        
        appStateManager.$appState
            .map { $0.filter.isAscending }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.isAscending, on: self)
            .store(in: &cancellables)
    }
}

/// 标签编辑器视图模型
class TagEditorViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var tagName: String = ""
    @Published var selectedColor: TagColorData = TagColorData(red: 0.4, green: 0.6, blue: 0.9)
    @Published var isEditing: Bool = false
    @Published var originalTagName: String = ""
    
    // MARK: - Dependencies
    private let appStateManager: AppStateManager
    
    init(appStateManager: AppStateManager) {
        self.appStateManager = appStateManager
    }
    
    // MARK: - Public Methods
    
    func startEditing(_ tag: TagData? = nil) {
        if let tag = tag {
            // 编辑现有标签
            isEditing = true
            originalTagName = tag.name
            tagName = tag.name
            selectedColor = tag.color
        } else {
            // 创建新标签
            isEditing = false
            originalTagName = ""
            tagName = ""
            selectedColor = TagColorData(red: 0.4, green: 0.6, blue: 0.9)
        }
    }
    
    func save() -> Bool {
        guard !tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        let trimmedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if isEditing {
            // 编辑现有标签 - 这里需要实现重命名逻辑
            // appStateManager.renameTag(from: originalTagName, to: trimmedName, color: selectedColor)
        } else {
            // 创建新标签
            appStateManager.setTagColor(tagName: trimmedName, color: selectedColor)
        }
        
        return true
    }
    
    func reset() {
        tagName = ""
        selectedColor = TagColorData(red: 0.4, green: 0.6, blue: 0.9)
        isEditing = false
        originalTagName = ""
    }
    
    // MARK: - Computed Properties
    
    var availableColors: [TagColorData] {
        return AppTheme.tagPresetColors.map { TagColorData(from: $0.color) }
    }
    
    var canSave: Bool {
        return !tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 项目卡片视图模型
struct ProjectCardViewModel {
    
    let project: ProjectData
    let isSelected: Bool
    let tagColors: [String: TagColorData]
    
    // MARK: - Computed Properties
    
    var displayName: String {
        project.name
    }
    
    var displayPath: String {
        // 简化路径显示
        let url = URL(fileURLWithPath: project.path)
        return "~/" + url.lastPathComponent
    }
    
    var lastModifiedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: project.lastModified, relativeTo: Date())
    }
    
    var gitInfoText: String? {
        guard let gitInfo = project.gitInfo else { return nil }
        return "\(gitInfo.commitCount) 次提交"
    }
    
    var displayTags: [TagDisplayData] {
        return project.tags.map { tagName in
            TagDisplayData(
                name: tagName,
                color: tagColors[tagName] ?? TagColorData(red: 0.5, green: 0.5, blue: 0.8)
            )
        }.sorted { $0.name < $1.name }
    }
    
    struct TagDisplayData {
        let name: String
        let color: TagColorData
    }
}

/// 主内容视图模型
class MainContentViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var showingTagEditor: Bool = false
    @Published var selectedProjectsForTagging: Set<UUID> = []
    
    // MARK: - Dependencies
    private let projectListViewModel: ProjectListViewModel
    private let appStateManager: AppStateManager
    
    init(projectListViewModel: ProjectListViewModel, appStateManager: AppStateManager) {
        self.projectListViewModel = projectListViewModel
        self.appStateManager = appStateManager
    }
    
    // MARK: - Public Methods
    
    func showTagEditor(for projectIds: Set<UUID>) {
        selectedProjectsForTagging = projectIds
        showingTagEditor = true
    }
    
    func hideTagEditor() {
        showingTagEditor = false
        selectedProjectsForTagging.removeAll()
    }
    
    func addTagToProjects(_ tag: String) {
        for projectId in selectedProjectsForTagging {
            appStateManager.addTagToProject(projectId: projectId, tagName: tag)
        }
        hideTagEditor()
    }
    
    // MARK: - Computed Properties
    
    var hasSelectedProjects: Bool {
        return !projectListViewModel.selectedProjectIds.isEmpty
    }
    
    var selectedProjectsCount: Int {
        return projectListViewModel.selectedProjectIds.count
    }
}