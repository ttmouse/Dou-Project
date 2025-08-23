import SwiftUI
import Combine

// MARK: - 模块化TagManager - Linus式精简协调器
class TagManagerModular: ObservableObject, ProjectOperationDelegate, DirectoryWatcherDelegate {
    
    // MARK: - 类型定义 (保持兼容性)
    enum SortCriteria {
        case name
        case lastModified
        case gitCommits
    }
    
    // MARK: - 模块化组件 - 单一职责原则
    private let tagStore: DefaultTagStore
    private let projectStore: DefaultProjectStore
    private let colorManager: TagColorManager
    private var fileWatcher: DirectoryWatcherAdapter
    private let sortManager: ProjectSortManager
    
    // MARK: - 基础存储
    private let storage: TagStorage
    
    // MARK: - 标签选择状态
    @Published var selectedTag: String?
    
    // MARK: - 保存控制
    private var saveDebounceTimer: Timer?
    
    // MARK: - 协议桥接属性 (为了兼容现有协议)
    @Published var allTags: Set<String> = []
    @Published var projects: [UUID: Project] = [:]
    @Published var watchedDirectories: Set<String> = []
    @Published var hiddenTags: Set<String> = []
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化 - 依赖注入模式
    init() {
        // 初始化基础组件
        storage = TagStorage()
        sortManager = ProjectSortManager()
        
        // 初始化模块化组件
        tagStore = DefaultTagStore(storage: storage)
        projectStore = DefaultProjectStore(storage: storage, sortManager: sortManager)
        colorManager = TagColorManager(storage: storage)
        
        // 创建文件监视器适配器 - 先创建一个临时的DirectoryWatcher
        let tempDirectoryWatcher = DirectoryWatcher(
            delegate: nil,
            operationManager: nil,
            storage: storage
        )
        fileWatcher = DirectoryWatcherAdapter(directoryWatcher: tempDirectoryWatcher)
        
        // 在super.init后设置所有委托关系
        setupDependencies()
        
        // 设置观察者 - 监听各模块变化
        setupObservers()
        
        // 同步初始状态
        syncAllStates()
        
        print("TagManagerModular 初始化完成 - Linus式模块化架构")
    }
    
    private func setupDependencies() {
        // 设置组件间引用
        tagStore.setProjectStore(projectStore)
        projectStore.setTagStore(tagStore)
        
        // 重新创建正确配置的DirectoryWatcher
        let projectOperationManager = ProjectOperationManager(
            delegate: self,
            sortDelegate: sortManager,
            storage: storage
        )
        
        let directoryWatcher = DirectoryWatcher(
            delegate: self,
            operationManager: projectOperationManager,
            storage: storage
        )
        
        // 更新fileWatcher的内部DirectoryWatcher
        // 注意：这需要DirectoryWatcherAdapter支持更新内部实例
        fileWatcher = DirectoryWatcherAdapter(directoryWatcher: directoryWatcher)
    }
    
    // MARK: - 观察者设置
    private func setupObservers() {
        // 监听TagStore变化
        tagStore.$allTags
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tags in
                self?.allTags = tags
            }
            .store(in: &cancellables)
        
        tagStore.$hiddenTags
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hidden in
                self?.hiddenTags = hidden
            }
            .store(in: &cancellables)
        
        // 监听ProjectStore变化
        projectStore.$projects
            .receive(on: DispatchQueue.main)
            .sink { [weak self] projects in
                self?.projects = projects
            }
            .store(in: &cancellables)
        
        // 监听FileWatcher变化
        fileWatcher.$watchedDirectories
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dirs in
                self?.watchedDirectories = dirs
            }
            .store(in: &cancellables)
        
        // 监听ColorManager变化
        colorManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 状态同步
    private func syncAllStates() {
        allTags = tagStore.allTags
        hiddenTags = tagStore.hiddenTags
        projects = projectStore.projects
        watchedDirectories = fileWatcher.watchedDirectories
        
        // 初始化颜色
        initializeTagColors()
    }
    
    // MARK: - 公共接口 - 委托给专门模块
    
    // 标签操作
    func addTag(_ tag: String, color: Color) {
        tagStore.addTag(tag)
        colorManager.setColor(color, for: tag)
        debouncedSave()
    }
    
    func removeTag(_ tag: String) {
        tagStore.removeTag(tag)
        colorManager.removeColor(for: tag)
        debouncedSave()
    }
    
    func renameTag(_ oldName: String, to newName: String, color: Color) {
        tagStore.renameTag(from: oldName, to: newName)
        colorManager.removeColor(for: oldName)
        colorManager.setColor(color, for: newName)
        debouncedSave()
    }
    
    // 标签可见性
    func toggleTagVisibility(_ tag: String) {
        tagStore.toggleTagVisibility(tag)
        debouncedSave()
    }
    
    func isTagHidden(_ tag: String) -> Bool {
        return tagStore.isTagHidden(tag)
    }
    
    // 项目操作
    func registerProject(_ project: Project) {
        projectStore.registerProject(project)
    }
    
    func removeProject(_ id: UUID) {
        projectStore.removeProject(id)
    }
    
    func addTagToProject(projectId: UUID, tag: String) {
        projectStore.addTagToProject(projectId: projectId, tag: tag)
        // 确保标签有颜色
        if colorManager.getColor(for: tag) == nil {
            colorManager.setColor(colorManager.getDefaultColor(for: tag), for: tag)
        }
        debouncedSave()
    }
    
    func removeTagFromProject(projectId: UUID, tag: String) {
        projectStore.removeTagFromProject(projectId: projectId, tag: tag)
        debouncedSave()
    }
    
    func addTagToProjects(projectIds: Set<UUID>, tag: String) {
        projectStore.addTagToProjects(projectIds: projectIds, tag: tag)
        // 确保标签有颜色
        if colorManager.getColor(for: tag) == nil {
            colorManager.setColor(colorManager.getDefaultColor(for: tag), for: tag)
        }
        debouncedSave()
    }
    
    // 颜色管理
    func getColor(for tag: String) -> Color {
        if let color = colorManager.getColor(for: tag) {
            return color
        }
        // 如果没有颜色，生成默认颜色并保存
        let defaultColor = colorManager.getDefaultColor(for: tag)
        colorManager.setColor(defaultColor, for: tag)
        return defaultColor
    }
    
    func setColor(_ color: Color, for tag: String) {
        colorManager.setColor(color, for: tag)
        objectWillChange.send()
    }
    
    // 项目查询和排序
    func getSortedProjects() -> [Project] {
        return sortManager.getSortedProjects()
    }
    
    func getFilteredProjects(withTags tags: Set<String>, searchText: String = "") -> [Project] {
        return getSortedProjects().filter { project in
            let matchesTags = tags.isEmpty || !tags.isDisjoint(with: project.tags)
            let matchesSearch = searchText.isEmpty || 
                project.name.localizedCaseInsensitiveContains(searchText) ||
                project.path.localizedCaseInsensitiveContains(searchText)
            return matchesTags && matchesSearch
        }
    }
    
    func setSortCriteria(_ criteria: SortCriteria, ascending: Bool) {
        let originalCriteria: TagManager.SortCriteria
        switch criteria {
        case .name:
            originalCriteria = .name
        case .lastModified:
            originalCriteria = .lastModified
        case .gitCommits:
            originalCriteria = .gitCommits
        }
        sortManager.setSortCriteria(originalCriteria, ascending: ascending)
    }
    
    // 统计功能
    func getUsageCount(for tag: String) -> Int {
        return tagStore.getUsageCount(for: tag)
    }
    
    // 目录管理
    func addWatchedDirectory(_ path: String) {
        fileWatcher.addWatchedDirectory(path)
        debouncedSave()
    }
    
    func removeWatchedDirectory(_ path: String) {
        fileWatcher.removeWatchedDirectory(path)
        debouncedSave()
    }
    
    func reloadProjects() {
        fileWatcher.clearCacheAndReloadProjects()
    }
    
    func manualIncrementalUpdate() {
        fileWatcher.incrementallyReloadProjects()
    }
    
    // MARK: - 协议实现 - ProjectOperationDelegate
    func invalidateTagUsageCache() {
        tagStore.invalidateUsageCache()
    }
    
    func notifyProjectsChanged() {
        objectWillChange.send()
    }
    
    // MARK: - 初始化辅助方法
    private func initializeTagColors() {
        for tag in allTags {
            if colorManager.getColor(for: tag) == nil {
                let defaultColor = colorManager.getDefaultColor(for: tag)
                colorManager.setColor(defaultColor, for: tag)
            }
        }
        debouncedSave()
    }
    
    // MARK: - 数据持久化 - 统一保存控制
    private func debouncedSave() {
        // 取消现有定时器
        saveDebounceTimer?.invalidate()
        
        // 设置新的定时器，延迟1秒执行保存
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.performSave()
        }
    }
    
    func saveAll(force: Bool = false) {
        if force {
            performSave()
        } else {
            debouncedSave()
        }
    }
    
    private func performSave() {
        // 模块化保存已经在各个Store中处理
        // 这里只需要处理系统标签同步
        TagSystemSync.syncTagsToSystem(allTags)
        
        // 保存所有项目的系统标签
        for project in projects.values {
            project.saveTagsToSystem()
        }
        
        print("TagManagerModular: 所有数据保存完成")
    }
    
    // MARK: - 兼容性方法 (临时保留，后续会被View更新替换)
    func clearCacheAndReloadProjects() {
        fileWatcher.clearCacheAndReloadProjects()
    }
    
    // 数据导入功能 (临时占位)
    func importData(
        from fileURL: URL,
        strategy: String = "merge",
        conflictResolution: String = "mergeData"
    ) -> String {
        print("数据导入功能暂未实现")
        return "未实现"
    }
}