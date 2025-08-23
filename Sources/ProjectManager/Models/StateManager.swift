import Foundation
import SwiftUI
import Combine

// MARK: - 轻量级状态管理器
// 遵循"数据与逻辑分离"原则，只负责状态管理，业务逻辑委托给Logic层

/// 应用状态管理器 - 只负责状态管理，不包含业务逻辑
class AppStateManager: ObservableObject {
    
    // MARK: - Published State
    @Published private(set) var appState: AppStateData
    @Published private(set) var processedProjects: [ProjectData] = []
    @Published private(set) var tagStatistics: [String: Int] = [:]
    
    // MARK: - Services
    private let storage: TagStorage
    private let persistenceService: PersistenceService
    private let projectService: ProjectService
    private let tagService: TagService
    
    // MARK: - Private State
    private var cancellables = Set<AnyCancellable>()
    private var saveDebounceTimer: Timer?
    
    init(storage: TagStorage = TagStorage()) {
        self.storage = storage
        self.persistenceService = PersistenceService(storage: storage)
        self.projectService = ProjectService(storage: storage)
        self.tagService = TagService(storage: storage)
        self.appState = AppStateLogic.createInitialState()
        
        setupObservers()
        loadInitialData()
    }
    
    // MARK: - State Updates
    
    /// 更新筛选条件
    func updateFilter(_ newFilter: FilterData) {
        appState = AppStateLogic.updateState(appState, filter: newFilter)
        updateDerivedState()
    }
    
    /// 添加/移除项目
    func addProject(_ projectData: ProjectData) {
        var projects = appState.projects
        projects[projectData.id] = projectData
        
        // 更新标签信息
        let allTags = TagLogic.getAllTags(from: Array(projects.values))
        var tags = appState.tags
        for tagName in allTags {
            if tags[tagName] == nil {
                let color = generateColorForTag(tagName)
                tags[tagName] = TagLogic.createTagData(
                    name: tagName,
                    color: color,
                    projects: Array(projects.values)
                )
            } else {
                // 更新现有标签的使用统计
                tags[tagName] = TagLogic.updateTagData(
                    tags[tagName]!,
                    projects: Array(projects.values)
                )
            }
        }
        
        appState = AppStateLogic.updateState(appState, projects: projects, tags: tags)
        updateDerivedState()
        scheduleSave()
    }
    
    func removeProject(_ projectId: UUID) {
        var projects = appState.projects
        projects.removeValue(forKey: projectId)
        
        // 更新标签统计
        var tags = appState.tags
        for (tagName, tagData) in tags {
            tags[tagName] = TagLogic.updateTagData(
                tagData,
                projects: Array(projects.values)
            )
        }
        
        appState = AppStateLogic.updateState(appState, projects: projects, tags: tags)
        updateDerivedState()
        scheduleSave()
    }
    
    /// 批量添加项目
    func addProjects(_ projectDataList: [ProjectData]) {
        var projects = appState.projects
        for projectData in projectDataList {
            projects[projectData.id] = projectData
        }
        
        // 批量更新标签信息
        let allTags = TagLogic.getAllTags(from: Array(projects.values))
        var tags = appState.tags
        
        for tagName in allTags {
            let color = tags[tagName]?.color ?? generateColorForTag(tagName)
            tags[tagName] = TagLogic.createTagData(
                name: tagName,
                color: color,
                projects: Array(projects.values),
                isHidden: tags[tagName]?.isHidden ?? false
            )
        }
        
        appState = AppStateLogic.updateState(appState, projects: projects, tags: tags)
        updateDerivedState()
        scheduleSave()
    }
    
    /// 标签操作
    func addTagToProject(projectId: UUID, tagName: String) {
        guard let project = appState.projects[projectId] else { return }
        
        let updatedProject = TagLogic.addTagToProject(project, tag: tagName)
        var projects = appState.projects
        projects[projectId] = updatedProject
        
        // 更新或创建标签
        var tags = appState.tags
        if tags[tagName] == nil {
            let color = generateColorForTag(tagName)
            tags[tagName] = TagLogic.createTagData(
                name: tagName,
                color: color,
                projects: Array(projects.values)
            )
        } else {
            tags[tagName] = TagLogic.updateTagData(
                tags[tagName]!,
                projects: Array(projects.values)
            )
        }
        
        appState = AppStateLogic.updateState(appState, projects: projects, tags: tags)
        updateDerivedState()
        scheduleSave()
    }
    
    func removeTagFromProject(projectId: UUID, tagName: String) {
        guard let project = appState.projects[projectId] else { return }
        
        let updatedProject = TagLogic.removeTagFromProject(project, tag: tagName)
        var projects = appState.projects
        projects[projectId] = updatedProject
        
        // 更新标签统计
        var tags = appState.tags
        if let tagData = tags[tagName] {
            tags[tagName] = TagLogic.updateTagData(
                tagData,
                projects: Array(projects.values)
            )
        }
        
        appState = AppStateLogic.updateState(appState, projects: projects, tags: tags)
        updateDerivedState()
        scheduleSave()
    }
    
    /// 标签管理
    func setTagColor(tagName: String, color: TagColorData) {
        var tags = appState.tags
        if let tagData = tags[tagName] {
            tags[tagName] = TagLogic.updateTagData(
                tagData,
                projects: Array(appState.projects.values),
                newColor: color
            )
        } else {
            tags[tagName] = TagLogic.createTagData(
                name: tagName,
                color: color,
                projects: Array(appState.projects.values)
            )
        }
        
        appState = AppStateLogic.updateState(appState, tags: tags)
        updateDerivedState()
        scheduleSave()
    }
    
    func toggleTagVisibility(tagName: String) {
        let newFilter = FilterLogic.toggleTagVisibility(appState.filter, tag: tagName)
        
        // 同时更新标签数据中的隐藏状态
        var tags = appState.tags
        if let tagData = tags[tagName] {
            tags[tagName] = TagLogic.updateTagData(
                tagData,
                projects: Array(appState.projects.values),
                newHidden: !tagData.isHidden
            )
        }
        
        appState = AppStateLogic.updateState(appState, tags: tags, filter: newFilter)
        updateDerivedState()
        scheduleSave()
    }
    
    /// 筛选操作
    func setSelectedTags(_ tags: Set<String>) {
        let newFilter = FilterLogic.updateFilter(appState.filter, selectedTags: tags)
        updateFilter(newFilter)
    }
    
    func setSearchText(_ text: String) {
        let newFilter = FilterLogic.updateFilter(appState.filter, searchText: text)
        updateFilter(newFilter)
    }
    
    func setSortCriteria(_ criteria: SortCriteriaData, ascending: Bool) {
        let newFilter = FilterLogic.updateFilter(
            appState.filter, 
            sortCriteria: criteria, 
            isAscending: ascending
        )
        updateFilter(newFilter)
    }
    
    /// 目录管理
    func addWatchedDirectory(_ path: String) {
        var directories = appState.watchedDirectories
        directories.insert(path)
        appState = AppStateLogic.updateState(appState, watchedDirectories: directories)
        scheduleSave()
    }
    
    func removeWatchedDirectory(_ path: String) {
        var directories = appState.watchedDirectories
        directories.remove(path)
        appState = AppStateLogic.updateState(appState, watchedDirectories: directories)
        scheduleSave()
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // 监听状态变化，更新派生状态
        $appState
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDerivedState()
            }
            .store(in: &cancellables)
    }
    
    private func updateDerivedState() {
        processedProjects = AppStateLogic.getProcessedProjects(appState)
        tagStatistics = AppStateLogic.getTagStatistics(appState)
    }
    
    private func loadInitialData() {
        Task { @MainActor in
            do {
                let loadedState = try await persistenceService.loadAppState()
                self.appState = loadedState
                self.updateDerivedState()
            } catch {
                print("加载初始数据失败: \(error)")
                // 使用默认状态
            }
        }
    }
    
    private func scheduleSave() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.saveState()
        }
    }
    
    private func saveState() {
        Task {
            do {
                try await persistenceService.saveAppState(appState)
            } catch {
                print("保存状态失败: \(error)")
            }
        }
    }
    
    private func generateColorForTag(_ tagName: String) -> TagColorData {
        // 使用标签名的哈希值生成确定性颜色
        let hash = abs(tagName.hashValue)
        let presetColors = AppTheme.tagPresetColors
        let colorIndex = hash % presetColors.count
        let color = presetColors[colorIndex].color
        
        // 将SwiftUI Color转换为TagColorData
        return TagColorData(from: color)
    }
    
    // MARK: - Public Computed Properties
    
    var allProjects: [ProjectData] {
        Array(appState.projects.values)
    }
    
    var allTags: [TagData] {
        Array(appState.tags.values).filter { !appState.filter.hiddenTags.contains($0.name) }
    }
    
    var watchedDirectories: Set<String> {
        appState.watchedDirectories
    }
    
    var currentFilter: FilterData {
        appState.filter
    }
}

// MARK: - 服务层

/// 持久化服务
class PersistenceService {
    private let storage: TagStorage
    
    init(storage: TagStorage) {
        self.storage = storage
    }
    
    func loadAppState() async throws -> AppStateData {
        // 这里简化实现，实际应该异步加载
        let projects = loadProjects()
        let tags = loadTags(from: projects)
        let watchedDirectories = loadWatchedDirectories()
        let filter = loadFilter()
        
        return AppStateData(
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            tags: Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) }),
            watchedDirectories: watchedDirectories,
            filter: filter,
            selectedProjectIds: []
        )
    }
    
    func saveAppState(_ state: AppStateData) async throws {
        // 保存到存储
        // 实际实现应该异步保存各个组件
        print("保存应用状态...")
    }
    
    private func loadProjects() -> [ProjectData] {
        // 从现有的TagStorage加载项目
        // 这里需要适配现有的加载逻辑
        return []
    }
    
    private func loadTags(from projects: [ProjectData]) -> [TagData] {
        let allTags = TagLogic.getAllTags(from: projects)
        return allTags.map { tagName in
            TagLogic.createTagData(
                name: tagName,
                color: TagColorData(red: 0.5, green: 0.5, blue: 0.8),
                projects: projects
            )
        }
    }
    
    private func loadWatchedDirectories() -> Set<String> {
        // 从现有存储加载
        return []
    }
    
    private func loadFilter() -> FilterData {
        return FilterData.empty
    }
}

/// 项目服务
class ProjectService {
    private let storage: TagStorage
    
    init(storage: TagStorage) {
        self.storage = storage
    }
    
    func scanDirectories(_ directories: Set<String>) async -> [ProjectData] {
        // 实现目录扫描逻辑
        return []
    }
    
    func updateProject(_ projectData: ProjectData) async throws {
        // 更新单个项目
    }
}

/// 标签服务
class TagService {
    private let storage: TagStorage
    
    init(storage: TagStorage) {
        self.storage = storage
    }
    
    func syncTagsToSystem(_ tags: Set<String>) async throws {
        // 同步标签到系统
    }
    
    func loadTagsFromSystem(path: String) async -> Set<String> {
        // 从系统加载标签
        return []
    }
}