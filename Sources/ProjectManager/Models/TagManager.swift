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
    let usageTracker: TagUsageTracker
    let sortManager: ProjectSortManager
    lazy var projectOperations: ProjectOperationManager = {
        return ProjectOperationManager(tagManager: self, storage: storage)
    }()
    lazy var directoryWatcher: DirectoryWatcher = {
        return DirectoryWatcher(tagManager: self, storage: storage)
    }()

    // MARK: - 初始化

    init() {
        print("TagManager 初始化...")

        // 初始化基础组件
        storage = TagStorage()
        colorManager = TagColorManager(storage: storage)
        usageTracker = TagUsageTracker()
        sortManager = ProjectSortManager()

        // 加载数据
        loadAllData()
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
        return colorManager.getColor(for: tag) ?? AppTheme.tagPresetColors.randomElement()?.color
            ?? AppTheme.accent
    }

    func setColor(_ color: Color, for tag: String) {
        colorManager.setColor(color, for: tag)
    }

    func getUsageCount(for tag: String) -> Int {
        return usageTracker.getUsageCount(for: tag)
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
        for directory in watchedDirectories {
            let loadedProjects = Project.loadProjects(from: directory)
            for project in loadedProjects {
                projectOperations.registerProject(project)
            }
        }
    }

    // MARK: - 标签操作

    func addTag(_ tag: String) {
        print("添加标签: \(tag)")
        allTags.insert(tag)
        saveAll()
    }

    func removeTag(_ tag: String) {
        print("移除标签: \(tag)")
        allTags.remove(tag)
        colorManager.removeColor(for: tag)
        usageTracker.clearUsage(for: tag)

        // 从所有项目中移除该标签
        for (id, project) in projects {
            if project.tags.contains(tag) {
                var updatedProject = project
                updatedProject.removeTag(tag)
                projects[id] = updatedProject
                sortManager.updateProject(updatedProject)
            }
        }

        saveAll()
    }

    func addTagToProject(projectId: UUID, tag: String) {
        print("添加标签 '\(tag)' 到项目 \(projectId)")
        if var project = projects[projectId] {
            project.addTag(tag)
            projects[projectId] = project
            sortManager.updateProject(project)
            usageTracker.incrementUsage(for: tag)
            saveAll()
        }
    }

    func removeTagFromProject(projectId: UUID, tag: String) {
        print("从项目 \(projectId) 移除标签 '\(tag)'")
        if var project = projects[projectId] {
            project.removeTag(tag)
            projects[projectId] = project
            sortManager.updateProject(project)
            usageTracker.decrementUsage(for: tag)
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
            addTagToProject(projectId: projectId, tag: tag)
        }
    }

    // MARK: - 数据保存

    func saveAll() {
        storage.saveTags(allTags)
        directoryWatcher.saveWatchedDirectories()
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

        // 更新使用统计
        let usageCount = usageTracker.getUsageCount(for: oldName)
        usageTracker.clearUsage(for: oldName)
        for _ in 0..<usageCount {
            usageTracker.incrementUsage(for: newName)
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
}
