import SwiftUI
import Combine

class TagManagerCore: ObservableObject {
    // MARK: - 核心状态
    @Published var allTags: Set<String> = []
    @Published var projects: [UUID: Project] = [:]
    @Published var watchedDirectories: Set<String> = []
    @Published var selectedTag: String?
    
    // MARK: - 组件依赖
    let storage: TagStorage
    let colorManager: TagColorManager
    let sortManager: ProjectSortManager
    private let projectIndex: ProjectIndex
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 懒加载组件 (暂时使用原始TagManager)
    lazy var projectOperations: ProjectOperationManager = {
        // FIXME: 需要创建适配器或修改依赖关系
        // 暂时返回nil，稍后修复
        fatalError("projectOperations not implemented in TagManagerCore yet")
    }()
    
    lazy var directoryWatcher: DirectoryWatcher = {
        // FIXME: 需要创建适配器或修改依赖关系
        // 暂时返回nil，稍后修复
        fatalError("directoryWatcher not implemented in TagManagerCore yet")
    }()
    
    // MARK: - 缓存
    private var cachedTagUsageCount: [String: Int]?
    private var lastProjectUpdateTime: Date?
    
    // MARK: - 初始化
    init() {
        print("TagManagerCore 初始化...")
        
        storage = TagStorage()
        colorManager = TagColorManager(storage: storage)
        sortManager = ProjectSortManager()
        projectIndex = ProjectIndex(storage: storage)
        
        setupObservers()
        loadAllData()
        initializeTagColors()
    }
    
    // MARK: - 观察者设置
    private func setupObservers() {
        colorManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 数据加载
    func loadAllData() {
        print("TagManagerCore: 开始加载所有数据...")
        
        allTags = storage.loadTags()
        print("已加载标签: \(allTags)")
        
        let systemTags = TagSystemSync.loadSystemTags()
        allTags.formUnion(systemTags)
        
        if let cachedProjects = loadProjectsFromCache() {
            print("从缓存加载了 \(cachedProjects.count) 个项目")
            for project in cachedProjects {
                projects[project.id] = project
            }
            sortManager.updateSortedProjects(cachedProjects)
            
            for project in cachedProjects {
                allTags.formUnion(project.tags)
            }
            
            // projectOperations.saveAllToCache() // FIXME
        }
        
        // directoryWatcher.loadWatchedDirectories() // FIXME
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // self.backgroundRefreshProjects() // FIXME
        }
    }
    
    private func backgroundRefreshProjects() {
        // directoryWatcher.incrementallyReloadProjects() // FIXME
    }
    
    private func loadProjectsFromCache() -> [Project]? {
        let cacheURL = storage.appSupportURL.appendingPathComponent("projects.json")
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            let projects = try decoder.decode([Project].self, from: data)
            print("TagManagerCore: 成功从缓存加载项目数据")
            return projects
        } catch {
            print("TagManagerCore: 加载项目缓存失败: \(error)")
            return nil
        }
    }
    
    // MARK: - 标签颜色初始化
    private func initializeTagColors() {
        for tag in allTags {
            if colorManager.getColor(for: tag) == nil {
                let hash = abs(tag.hashValue)
                let colorIndex = hash % AppTheme.tagPresetColors.count
                let color = AppTheme.tagPresetColors[colorIndex].color
                colorManager.setColor(color, for: tag)
            }
        }
        saveAll(force: true)
    }
    
    // MARK: - 项目重新加载
    func reloadProjects() {
        print("TagManagerCore: 开始重新加载项目...")
        
        let existingProjects = projects
        projects.removeAll()
        sortManager.updateSortedProjects([])
        invalidateTagUsageCache()
        
        for directory in watchedDirectories {
            projectIndex.scanDirectory(directory)
        }
        
        let loadedProjects = projectIndex.loadProjects(existingProjects: existingProjects)
        
        for project in loadedProjects {
            // Project初始化时已经处理了系统标签，这里不需要重复处理
            // projectOperations.registerProject(project) // FIXME
        }
        
        print("TagManagerCore: 完成重新加载，现有 \(projects.count) 个项目")
    }
    
    // MARK: - 标签统计
    func getUsageCount(for tag: String) -> Int {
        return tagUsageCount[tag] ?? 0
    }
    
    func invalidateTagUsageCache() {
        cachedTagUsageCount = nil
        lastProjectUpdateTime = nil
    }
    
    private var tagUsageCount: [String: Int] {
        if let cached = cachedTagUsageCount,
            let lastUpdate = lastProjectUpdateTime,
            Date().timeIntervalSince(lastUpdate) < 1.0
        {
            return cached
        }
        
        var counts: [String: Int] = [:]
        for project in projects.values {
            for tag in project.tags {
                counts[tag, default: 0] += 1
            }
        }
        
        cachedTagUsageCount = counts
        lastProjectUpdateTime = Date()
        return counts
    }
    
    // MARK: - 颜色管理
    func getColor(for tag: String) -> Color {
        if tag == "全部" {
            return AppTheme.accent
        }
        
        if tag == "没有标签" {
            return AppTheme.accent.opacity(0.7)
        }
        
        if let color = colorManager.getColor(for: tag) {
            return color
        }
        
        let hash = abs(tag.hashValue)
        let colorIndex = hash % AppTheme.tagPresetColors.count
        let color = AppTheme.tagPresetColors[colorIndex].color
        
        colorManager.setColor(color, for: tag)
        return color
    }
    
    func setColor(_ color: Color, for tag: String) {
        colorManager.setColor(color, for: tag)
        objectWillChange.send()
    }
    
    // MARK: - 排序和过滤
    func setSortCriteria(_ criteria: TagManager.SortCriteria, ascending: Bool) {
        sortManager.setSortCriteria(criteria, ascending: ascending)
    }
    
    func getSortedProjects() -> [Project] {
        return sortManager.getSortedProjects()
    }
    
    func getFilteredProjects(withTags tags: Set<String>, searchText: String = "") -> [Project] {
        return sortManager.getSortedProjects().filter { project in
            let matchesTags = tags.isEmpty || !tags.isDisjoint(with: project.tags)
            let matchesSearch =
                searchText.isEmpty || project.name.localizedCaseInsensitiveContains(searchText)
                || project.path.localizedCaseInsensitiveContains(searchText)
            return matchesTags && matchesSearch
        }
    }
    
    // MARK: - 项目管理
    func registerProject(_ project: Project) {
        // projectOperations.registerProject(project) // FIXME
        print("TagManagerCore: registerProject需要实现")
    }
    
    func removeProject(_ id: UUID) {
        // projectOperations.removeProject(id) // FIXME  
        print("TagManagerCore: removeProject需要实现")
    }
    
    // MARK: - 目录管理
    func addWatchedDirectory(_ path: String) {
        // directoryWatcher.addWatchedDirectory(path) // FIXME
        print("TagManagerCore: addWatchedDirectory需要实现")
    }
    
    func removeWatchedDirectory(_ path: String) {
        // directoryWatcher.removeWatchedDirectory(path) // FIXME
        print("TagManagerCore: removeWatchedDirectory需要实现")
    }
    
    func clearCacheAndReloadProjects() {
        // directoryWatcher.clearCacheAndReloadProjects() // FIXME
        print("TagManagerCore: clearCacheAndReloadProjects需要实现")
    }
    
    // MARK: - 数据保存
    private var needsSave = false
    private var saveDebounceTimer: Timer?
    
    func saveAll(force: Bool = false) {
        if force {
            performSave()
            return
        }
        
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) {
            [weak self] _ in
            self?.performSave()
        }
    }
    
    private func performSave() {
        storage.saveTags(allTags)
        // directoryWatcher.saveWatchedDirectories() // FIXME
        // projectOperations.saveAllToCache() // FIXME
        TagSystemSync.syncTagsToSystem(allTags)
        
        for project in projects.values {
            project.saveTagsToSystem()
        }
        
        needsSave = false
        print("TagManagerCore: 数据保存完成 (部分功能待实现)")
    }
}