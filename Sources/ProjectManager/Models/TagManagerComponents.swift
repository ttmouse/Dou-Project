import Foundation
import SwiftUI

// MARK: - 项目排序组件
class ProjectSortManager {
    private var sortedProjects: [Project] = []
    private var sortCriteria: TagManager.SortCriteria = .lastModified
    private var isAscending: Bool = false

    func setSortCriteria(_ criteria: TagManager.SortCriteria, ascending: Bool) {
        sortCriteria = criteria
        isAscending = ascending
        sortProjects()
    }

    func updateSortedProjects(_ projects: [Project]) {
        sortedProjects = projects
        sortProjects()
    }

    func insertProject(_ project: Project) {
        let index = binarySearchInsertionIndex(for: project)
        sortedProjects.insert(project, at: index)
    }

    func updateProject(_ project: Project) {
        // 先移除旧的项目
        if let index = sortedProjects.firstIndex(where: { $0.id == project.id }) {
            sortedProjects.remove(at: index)
        }
        // 使用二分查找插入更新后的项目
        insertProject(project)
    }

    func getSortedProjects() -> [Project] {
        return sortedProjects
    }

    private func sortProjects() {
        sortedProjects.sort { p1, p2 in
            switch sortCriteria {
            case .lastModified:
                return isAscending
                    ? p1.lastModified < p2.lastModified : p1.lastModified > p2.lastModified
            case .name:
                return isAscending ? p1.name < p2.name : p1.name > p2.name
            case .gitCommits:
                let count1 = p1.gitInfo?.commitCount ?? 0
                let count2 = p2.gitInfo?.commitCount ?? 0
                return isAscending ? count1 < count2 : count1 > count2
            }
        }
    }

    private func binarySearchInsertionIndex(for project: Project) -> Int {
        var left = 0
        var right = sortedProjects.count

        while left < right {
            let mid = (left + right) / 2
            if shouldInsertBefore(project, sortedProjects[mid]) {
                right = mid
            } else {
                left = mid + 1
            }
        }

        return left
    }

    private func shouldInsertBefore(_ p1: Project, _ p2: Project) -> Bool {
        switch sortCriteria {
        case .lastModified:
            return isAscending
                ? p1.lastModified < p2.lastModified : p1.lastModified > p2.lastModified
        case .name:
            return isAscending ? p1.name < p2.name : p1.name > p2.name
        case .gitCommits:
            let count1 = p1.gitInfo?.commitCount ?? 0
            let count2 = p2.gitInfo?.commitCount ?? 0
            return isAscending ? count1 < count2 : count1 > count2
        }
    }
}

// MARK: - 项目操作组件
class ProjectOperationManager {
    private unowned let tagManager: TagManager
    private let storage: TagStorage

    init(tagManager: TagManager, storage: TagStorage) {
        self.tagManager = tagManager
        self.storage = storage
    }

    func registerProject(_ project: Project) {
        print("注册项目: \(project.name), 标签: \(project.tags)")
        tagManager.projects[project.id] = project

        // 批量处理标签
        var newTags = Set<String>()
        project.tags.forEach { tag in
            if !tagManager.allTags.contains(tag) {
                newTags.insert(tag)
            }
            tagManager.usageTracker.incrementUsage(for: tag)
        }

        // 只在有新标签时同步到系统
        if !newTags.isEmpty {
            tagManager.allTags.formUnion(newTags)
            // 同步到系统标签
            let systemTags = TagSystemSync.loadSystemTags()
            var updatedTags = systemTags
            updatedTags.formUnion(newTags)
            if updatedTags != systemTags {
                TagSystemSync.syncTagsToSystem(updatedTags)
            }
        }

        // 使用二分查找插入新项目
        tagManager.sortManager.insertProject(project)

        // 保存更改
        saveToCache()
    }

    func removeProject(_ id: UUID) {
        guard let project = tagManager.projects[id] else { return }

        project.tags.forEach { tag in
            tagManager.usageTracker.decrementUsage(for: tag)
        }
        tagManager.projects.removeValue(forKey: id)
        saveToCache()
    }

    private func saveToCache() {
        let cacheURL = storage.appSupportURL.appendingPathComponent("projects.json")
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(Array(tagManager.projects.values))
            try data.write(to: cacheURL)
            print("项目数据保存成功")
        } catch {
            print("保存项目数据失败: \(error)")
        }
    }
}

// MARK: - 目录监视组件
class DirectoryWatcher {
    private unowned let tagManager: TagManager
    private let storage: TagStorage

    init(tagManager: TagManager, storage: TagStorage) {
        self.tagManager = tagManager
        self.storage = storage
    }

    func loadWatchedDirectories() {
        let directoriesURL = storage.appSupportURL.appendingPathComponent("directories.json")
        do {
            let data = try Data(contentsOf: directoriesURL)
            let decoder = JSONDecoder()
            let directories = try decoder.decode([String].self, from: data)
            tagManager.watchedDirectories = Set(directories)
            print("从文件加载监视目录: \(directories)")
        } catch {
            print("加载监视目录失败（可能是首次运行）: \(error)")
            // 设置默认目录为桌面
            if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
                .first?.path
            {
                tagManager.watchedDirectories.insert(desktop)
            }
        }
    }

    func saveWatchedDirectories() {
        let directoriesURL = storage.appSupportURL.appendingPathComponent("directories.json")
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(Array(tagManager.watchedDirectories))
            try data.write(to: directoriesURL)
            print("保存监视目录列表: \(Array(tagManager.watchedDirectories))")
        } catch {
            print("保存监视目录失败: \(error)")
        }
    }

    func addWatchedDirectory(_ path: String) {
        if !tagManager.watchedDirectories.contains(path) {
            tagManager.watchedDirectories.insert(path)
            saveWatchedDirectories()
            loadProjectsFromDirectory(path)
        }
    }

    func removeWatchedDirectory(_ path: String) {
        if tagManager.watchedDirectories.contains(path) {
            tagManager.watchedDirectories.remove(path)
            saveWatchedDirectories()
            removeProjectsInDirectory(path)
        }
    }

    private func removeProjectsInDirectory(_ path: String) {
        let projectsToRemove = tagManager.projects.values.filter { $0.path.hasPrefix(path) }
        for project in projectsToRemove {
            tagManager.projectOperations.removeProject(project.id)
        }
    }

    private func loadProjectsFromDirectory(_ path: String) {
        let loadedProjects = Project.loadProjects(from: path, existingProjects: tagManager.projects)
        for project in loadedProjects {
            tagManager.projectOperations.registerProject(project)
        }
    }
}
