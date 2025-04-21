import AppKit
import SwiftUI
import UniformTypeIdentifiers

class TagManager: ObservableObject {
    // MARK: - 类型定义

    enum SortCriteria {
        case name
        case lastModified
        case gitCommits
    }

    // MARK: - 公共属性

    @Published var allTags: Set<String> = []
    @Published var projects: [UUID: Project] = [:]
    @Published var watchedDirectories: Set<String> = []

    // MARK: - 组件

    let storage: TagStorage
    let colorManager: TagColorManager
    let sortManager: ProjectSortManager
    private let projectIndex: ProjectIndex
    lazy var projectOperations: ProjectOperationManager = {
        return ProjectOperationManager(tagManager: self, storage: storage)
    }()
    lazy var directoryWatcher: DirectoryWatcher = {
        return DirectoryWatcher(tagManager: self, storage: storage)
    }()

    // MARK: - 标签统计缓存
    private var cachedTagUsageCount: [String: Int]?
    private var lastProjectUpdateTime: Date?

    // MARK: - 初始化

    init() {
        print("TagManager 初始化...")

        // 初始化基础组件
        storage = TagStorage()
        colorManager = TagColorManager(storage: storage)
        sortManager = ProjectSortManager()
        projectIndex = ProjectIndex(storage: storage)

        // 加载数据
        loadAllData()
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
        // 加载标签
        allTags = storage.loadTags()

        // 加载监视目录
        directoryWatcher.loadWatchedDirectories()

        // 加载系统标签
        let systemTags = TagSystemSync.loadSystemTags()
        for tag in systemTags {
            if !allTags.contains(tag) {
                allTags.insert(tag)
            }
        }

        // 加载所有目录中的项目
        reloadProjects()
    }

    // MARK: - 公共接口

    func setSortCriteria(_ criteria: SortCriteria, ascending: Bool) {
        sortManager.setSortCriteria(criteria, ascending: ascending)
    }

    func getColor(for tag: String) -> Color {
        // 检查是否已有颜色
        if let existingColor = colorManager.getColor(for: tag) {
            return existingColor
        }
        
        // 如果没有颜色，随机分配一个并保存
        let randomColor = AppTheme.tagPresetColors.randomElement()?.color ?? AppTheme.accent
        colorManager.setColor(randomColor, for: tag)
        return randomColor
    }

    func setColor(_ color: Color, for tag: String) {
        colorManager.setColor(color, for: tag)
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

    func reloadProjects() {
        projects.removeAll()
        sortManager.updateSortedProjects([])
        invalidateTagUsageCache()

        // 扫描所有监视目录
        for directory in watchedDirectories {
            projectIndex.scanDirectory(directory)
        }

        // 从索引加载项目
        let loadedProjects = projectIndex.loadProjects(existingProjects: projects)
        for project in loadedProjects {
            projectOperations.registerProject(project)
        }
    }

    // MARK: - 标签操作

    func addTag(_ tag: String) {
        print("添加标签: \(tag)")
        if !allTags.contains(tag) {
            allTags.insert(tag)
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
                needsSave = true
                saveAll()
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
            saveAll()
        }
    }

    // MARK: - 批量操作

    func addTagToProjects(projectIds: Set<UUID>, tag: String) {
        print("批量添加标签 '\(tag)' 到 \(projectIds.count) 个项目")

        // 如果标签不存在，先添加标签
        if !allTags.contains(tag) {
            addTag(tag)
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
        saveAll()

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

    func saveAll() {
        // 如果已经有定时器在运行，取消它
        saveDebounceTimer?.invalidate()

        // 设置新的定时器，延迟1秒执行保存
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) {
            [weak self] _ in
            self?.performSave()
        }
    }

    private func performSave() {
        storage.saveTags(allTags)
        directoryWatcher.saveWatchedDirectories()
        needsSave = false
    }

    // MARK: - 项目管理

    func registerProject(_ project: Project) {
        projectOperations.registerProject(project)
    }

    func removeProject(_ id: UUID) {
        projectOperations.removeProject(id)
    }

    // MARK: - 标签操作

    func renameTag(_ oldName: String, to newName: String) {
        print("重命名标签: \(oldName) -> \(newName)")
        guard oldName != newName else { return }
        guard !allTags.contains(newName) else { return }

        // 从所有项目中更新标签
        for (id, project) in projects {
            if project.tags.contains(oldName) {
                var updatedProject = project
                updatedProject.removeTag(oldName)
                updatedProject.addTag(newName)
                projects[id] = updatedProject
                sortManager.updateProject(updatedProject)
            }
        }

        // 更新标签相关数据
        allTags.remove(oldName)
        allTags.insert(newName)

        // 更新颜色
        if let oldColor = colorManager.getColor(for: oldName) {
            colorManager.setColor(oldColor, for: newName)
            colorManager.removeColor(for: oldName)
        }

        // 保存更改
        saveAll()
    }

    // MARK: - 目录管理

    func addWatchedDirectory(_ path: String) {
        directoryWatcher.addWatchedDirectory(path)
    }

    func removeWatchedDirectory(_ path: String) {
        directoryWatcher.removeWatchedDirectory(path)
    }

    func reloadAllProjects() {
        reloadProjects()
    }
    
    // 清除缓存并重新加载所有项目
    func clearCacheAndReloadProjects() {
        directoryWatcher.clearCacheAndReloadProjects()
    }
}
