import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine

class TagManager: ObservableObject {
    // MARK: - 类型定义

    enum SortCriteria {
        case name
        case lastModified
        case gitCommits
    }

    // MARK: - 静态实例
    
    static weak var shared: TagManager?

    // MARK: - 公共属性

    @Published var allTags: Set<String> = []
    @Published var projects: [UUID: Project] = [:]
    @Published var watchedDirectories: Set<String> = []

    // MARK: - 组件

    let storage: TagStorage
    let colorManager: TagColorManager
    let sortManager: ProjectSortManager
    private let projectIndex: ProjectIndex
    private var cancellables = Set<AnyCancellable>()
    lazy var projectOperations: ProjectOperationManager = {
        return ProjectOperationManager(tagManager: self, storage: storage)
    }()
    lazy var directoryWatcher: DirectoryWatcher = {
        return DirectoryWatcher(tagManager: self, storage: storage)
    }()

    // MARK: - 标签统计缓存
    private var cachedTagUsageCount: [String: Int]?
    private var lastProjectUpdateTime: Date?

    // MARK: - 标签选择
    
    @Published var selectedTag: String?

    // MARK: - 初始化

    init() {
        print("TagManager 初始化...")

        // 初始化基础组件
        storage = TagStorage()
        colorManager = TagColorManager(storage: storage)
        sortManager = ProjectSortManager()
        projectIndex = ProjectIndex(storage: storage)
        
        // 设置静态实例
        Self.shared = self

        // 监听 colorManager 的变化
        colorManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // 加载数据
        loadAllData()
        
        // 确保所有标签都有颜色
        initializeTagColors()
    }
    
    // 初始化标签颜色
    private func initializeTagColors() {
        for tag in allTags {
            if colorManager.getColor(for: tag) == nil {
                // 使用标签名称的哈希值来确定性地选择颜色
                let hash = abs(tag.hashValue)
                let colorIndex = hash % AppTheme.tagPresetColors.count
                let color = AppTheme.tagPresetColors[colorIndex].color
                colorManager.setColor(color, for: tag)
            }
        }
        // 保存颜色
        saveAll(force: true)
    }

    // MARK: - 标签统计

    private var tagUsageCount: [String: Int] {
        // 如果项目数据没有更新，直接返回缓存
        if let cached = cachedTagUsageCount,
            let lastUpdate = lastProjectUpdateTime,
            Date().timeIntervalSince(lastUpdate) < 1.0
        {
            return cached
        }

        // 重新计算并缓存
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

    func getUsageCount(for tag: String) -> Int {
        return tagUsageCount[tag] ?? 0
    }

    func invalidateTagUsageCache() {
        cachedTagUsageCount = nil
        lastProjectUpdateTime = nil
    }

    // MARK: - 数据加载

    private func loadAllData() {
        print("开始加载所有数据...")
        
        // 1. 加载标签
        allTags = storage.loadTags()
        print("已加载标签: \(allTags)")

        // 2. 加载系统标签并合并
        let systemTags = TagSystemSync.loadSystemTags()
        allTags.formUnion(systemTags)
        print("合并系统标签后: \(allTags)")

        // 3. 加载项目缓存
        if let cachedProjects = loadProjectsFromCache() {
            print("从缓存加载了 \(cachedProjects.count) 个项目")
            for project in cachedProjects {
                projects[project.id] = project
            }
            sortManager.updateSortedProjects(cachedProjects)
            
            // 将项目标签添加到全部标签集合中
            for project in cachedProjects {
                allTags.formUnion(project.tags)
            }
            
            // 保存到缓存，确保数据一致性
            projectOperations.saveAllToCache()
        }

        // 4. 加载监视目录
        directoryWatcher.loadWatchedDirectories()
        
        // 5. 后台更新（而不是立即重新加载，避免清空UI）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.backgroundRefreshProjects()
        }
    }
    
    // 后台刷新项目，不清空现有UI
    private func backgroundRefreshProjects() {
        directoryWatcher.incrementallyReloadProjects()
    }

    private func loadProjectsFromCache() -> [Project]? {
        let cacheURL = storage.appSupportURL.appendingPathComponent("projects.json")
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            let projects = try decoder.decode([Project].self, from: data)
            print("成功从缓存加载项目数据")
            return projects
        } catch {
            print("加载项目缓存失败（可能是首次运行）: \(error)")
            return nil
        }
    }

    func reloadProjects() {
        print("开始重新加载项目...")
        
        // 保存现有的项目数据
        let existingProjects = projects
        
        // 清空当前项目列表
        projects.removeAll()
        sortManager.updateSortedProjects([])
        invalidateTagUsageCache()

        // 扫描所有监视目录
        for directory in watchedDirectories {
            projectIndex.scanDirectory(directory)
        }

        // 从索引加载项目，使用现有的项目数据作为参考
        let loadedProjects = projectIndex.loadProjects(existingProjects: existingProjects)
        
        // 注册新项目
        for var project in loadedProjects {
            // 检查是否有系统标签
            let systemTags = Project.loadTagsFromSystem(path: project.path)
            if !systemTags.isEmpty {
                project = Project(
                    id: project.id,
                    name: project.name,
                    path: project.path,
                    lastModified: project.lastModified,
                    tags: systemTags
                )
            }
            projectOperations.registerProject(project)
        }
        
        print("完成重新加载，现有 \(projects.count) 个项目")
    }

    // MARK: - 公共接口

    func setSortCriteria(_ criteria: SortCriteria, ascending: Bool) {
        sortManager.setSortCriteria(criteria, ascending: ascending)
    }

    func getColor(for tag: String) -> Color {
        // 为"全部"标签返回固定颜色
        if tag == "全部" {
            return AppTheme.accent
        }
        
        // 为"没有标签"返回固定颜色
        if tag == "没有标签" {
            return AppTheme.accent.opacity(0.7)
        }
        
        // 直接使用 colorManager 的颜色，如果没有则生成新的
        if let color = colorManager.getColor(for: tag) {
            return color
        }
        
        // 如果没有颜色，使用标签名称的哈希值来确定性地选择颜色
        let hash = abs(tag.hashValue)
        let colorIndex = hash % AppTheme.tagPresetColors.count
        let color = AppTheme.tagPresetColors[colorIndex].color
        
        // 保存颜色以便后续使用
        colorManager.setColor(color, for: tag)
        
        return color
    }

    func setColor(_ color: Color, for tag: String) {
        colorManager.setColor(color, for: tag)
        // 通知观察者有更新
        objectWillChange.send()
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

    // MARK: - 标签操作

    func addTag(_ tag: String, color: Color) {
        print("添加标签: \(tag)")
        if !allTags.contains(tag) {
            allTags.insert(tag)
            colorManager.setColor(color, for: tag)
            needsSave = true
            saveAll()
        }
    }

    func removeTag(_ tag: String) {
        print("移除标签: \(tag)")
        if allTags.contains(tag) {
            allTags.remove(tag)
            colorManager.removeColor(for: tag)

            // 从所有项目中移除该标签
            for (id, project) in projects {
                if project.tags.contains(tag) {
                    var updatedProject = project
                    updatedProject.removeTag(tag)
                    projects[id] = updatedProject
                    sortManager.updateProject(updatedProject)
                }
            }

            invalidateTagUsageCache()
            needsSave = true
            saveAll()
        }
    }

    func addTagToProject(projectId: UUID, tag: String) {
        print("添加标签 '\(tag)' 到项目 \(projectId)")
        if var project = projects[projectId] {
            if !project.tags.contains(tag) {
                project.addTag(tag)
                projects[projectId] = project
                sortManager.updateProject(project)
                invalidateTagUsageCache()

                // 保存到系统
                project.saveTagsToSystem()
                saveAll(force: true)  // 强制保存
            }
        }
    }

    func removeTagFromProject(projectId: UUID, tag: String) {
        print("从项目 \(projectId) 移除标签 '\(tag)'")
        if var project = projects[projectId] {
            project.removeTag(tag)
            projects[projectId] = project
            sortManager.updateProject(project)
            invalidateTagUsageCache()

            // 保存到系统
            project.saveTagsToSystem()
            saveAll(force: true)  // 强制保存
        }
    }

    // MARK: - 批量操作

    func addTagToProjects(projectIds: Set<UUID>, tag: String) {
        print("批量添加标签 '\(tag)' 到 \(projectIds.count) 个项目")

        // 如果标签不存在，先添加标签
        if !allTags.contains(tag) {
            addTag(tag, color: getColor(for: tag))
        }

        // 批量处理项目
        for projectId in projectIds {
            if var project = projects[projectId] {
                project.addTag(tag)
                projects[projectId] = project
                sortManager.updateProject(project)
            }
        }

        // 统一处理缓存和保存
        invalidateTagUsageCache()
        saveAll(force: true)  // 强制保存

        // 批量保存系统标签
        for projectId in projectIds {
            if let project = projects[projectId] {
                project.saveTagsToSystem()
            }
        }
    }

    // MARK: - 数据保存

    private var needsSave = false
    private var saveDebounceTimer: Timer?

    func saveAll(force: Bool = false) {
        // 如果强制保存，立即执行
        if force {
            performSave()
            return
        }

        // 如果已经有定时器在运行，取消它
        saveDebounceTimer?.invalidate()

        // 设置新的定时器，延迟1秒执行保存
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) {
            [weak self] _ in
            self?.performSave()
        }
    }

    private func performSave() {
        // 保存标签
        storage.saveTags(allTags)
        
        // 保存监视目录
        directoryWatcher.saveWatchedDirectories()
        
        // 保存项目数据
        projectOperations.saveAllToCache()
        
        // 同步系统标签
        TagSystemSync.syncTagsToSystem(allTags)
        
        // 保存所有项目的系统标签
        for project in projects.values {
            project.saveTagsToSystem()
        }
        
        needsSave = false
        print("所有数据保存完成")
    }

    // MARK: - 项目管理

    func registerProject(_ project: Project) {
        projectOperations.registerProject(project)
    }

    func removeProject(_ id: UUID) {
        projectOperations.removeProject(id)
    }

    // MARK: - 标签操作

    func renameTag(_ oldName: String, to newName: String, color: Color) {
        print("重命名标签: \(oldName) -> \(newName)")
        if allTags.contains(oldName) && !allTags.contains(newName) {
            allTags.remove(oldName)
            allTags.insert(newName)
            
            // 更新颜色
            colorManager.removeColor(for: oldName)
            colorManager.setColor(color, for: newName)

            // 更新所有项目中的标签
            for (id, project) in projects {
                if project.tags.contains(oldName) {
                    var updatedProject = project
                    updatedProject.removeTag(oldName)
                    updatedProject.addTag(newName)
                    projects[id] = updatedProject
                    sortManager.updateProject(updatedProject)
                }
            }

            invalidateTagUsageCache()
            needsSave = true
            saveAll()
        }
    }

    // MARK: - 目录管理

    func addWatchedDirectory(_ path: String) {
        directoryWatcher.addWatchedDirectory(path)
    }

    func removeWatchedDirectory(_ path: String) {
        directoryWatcher.removeWatchedDirectory(path)
    }

    // 清除缓存并重新加载所有项目
    func clearCacheAndReloadProjects() {
        directoryWatcher.clearCacheAndReloadProjects()
    }
}
