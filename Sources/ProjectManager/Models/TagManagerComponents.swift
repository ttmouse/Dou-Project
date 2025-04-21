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

        // 处理新标签
        let newTags = project.tags.subtracting(tagManager.allTags)
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

        // 使标签统计缓存失效
        tagManager.invalidateTagUsageCache()

        // 保存更改
        saveToCache()
    }

    func removeProject(_ id: UUID) {
        guard let project = tagManager.projects[id] else { return }
        tagManager.projects.removeValue(forKey: id)

        // 使标签统计缓存失效
        tagManager.invalidateTagUsageCache()

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
    
    // 强制立即保存所有项目到缓存，不使用防抖动
    func saveAllToCache() {
        let cacheURL = storage.appSupportURL.appendingPathComponent("projects.json")
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(Array(tagManager.projects.values))
            try data.write(to: cacheURL)
            print("所有项目数据保存成功")
        } catch {
            print("保存所有项目数据失败: \(error)")
        }
    }
}

// MARK: - 目录监视组件
class DirectoryWatcher {
    private unowned let tagManager: TagManager
    private let storage: TagStorage
    private let projectIndex: ProjectIndex
    private let queue = DispatchQueue(label: "com.example.DirectoryWatcherQueue", attributes: [])

    init(tagManager: TagManager, storage: TagStorage) {
        self.tagManager = tagManager
        self.storage = storage
        self.projectIndex = ProjectIndex(storage: storage)
    }

    func loadWatchedDirectories() {
        let directoriesURL = storage.appSupportURL.appendingPathComponent("directories.json")
        do {
            let data = try Data(contentsOf: directoriesURL)
            let decoder = JSONDecoder()
            let directories = try decoder.decode([String].self, from: data)
            tagManager.watchedDirectories = Set(directories)
            print("从文件加载监视目录: \(directories)")

            // 初始扫描所有监视目录
            for directory in directories {
                projectIndex.scanDirectory(directory)
            }
        } catch {
            print("加载监视目录失败（可能是首次运行）: \(error)")
            // 设置默认目录
            let fileManager = FileManager.default
            var defaultDirectories = Set<String>()

            // 添加桌面目录
            if let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first?
                .path
            {
                defaultDirectories.insert(desktop)
            }

            // 添加文档目录
            if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
                .path
            {
                defaultDirectories.insert(documents)
            }

            // 添加下载目录
            if let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)
                .first?.path
            {
                defaultDirectories.insert(downloads)
            }

            // 添加用户主目录下的常用开发目录
            if let home = ProcessInfo.processInfo.environment["HOME"] {
                let devDirs = [
                    "Projects",
                    "Developer",
                    "Development",
                    "Code",
                    "Workspace",
                    "Git",
                    "GitHub",
                    "gitlab",
                    "work",
                ]

                for dir in devDirs {
                    let path = (home as NSString).appendingPathComponent(dir)
                    if fileManager.fileExists(atPath: path) {
                        defaultDirectories.insert(path)
                    }
                }
            }

            // 更新监视目录
            tagManager.watchedDirectories = defaultDirectories

            // 初始扫描所有默认目录
            for directory in defaultDirectories {
                projectIndex.scanDirectory(directory)
            }

            // 保存默认目录配置
            saveWatchedDirectories()
            print("已设置默认监视目录: \(defaultDirectories)")
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
            projectIndex.scanDirectory(path)
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
        // 等待扫描完成后再加载项目
        queue.sync {
            let loadedProjects = self.projectIndex.loadProjects(
                existingProjects: self.tagManager.projects,
                fromWatchedDirectories: [path])
            DispatchQueue.main.async {
                for project in loadedProjects {
                    self.tagManager.projectOperations.registerProject(project)
                }
            }
        }
    }

    func reloadAllProjects() {
        queue.async {
            // 强制重新扫描所有目录
            for directory in self.tagManager.watchedDirectories {
                self.projectIndex.scanDirectory(directory, force: true)
            }

            // 加载所有项目
            let allProjects = self.projectIndex.loadProjects(
                existingProjects: self.tagManager.projects,
                fromWatchedDirectories: self.tagManager.watchedDirectories)

            // 更新项目列表
            DispatchQueue.main.async {
                self.tagManager.projects.removeAll()
                for project in allProjects {
                    self.tagManager.projectOperations.registerProject(project)
                }
            }
        }
    }
    
    // 清除缓存并重新加载所有项目
    func clearCacheAndReloadProjects() {
        queue.async {
            print("开始清除缓存并重新加载...")
            
            // 确保清空内存中的项目集合
            DispatchQueue.main.async {
                self.tagManager.projects.removeAll()
                self.tagManager.sortManager.updateSortedProjects([])
                print("已清空内存中的项目集合")
            }
            
            // 清除项目数据缓存
            let projectsCacheURL = self.storage.appSupportURL.appendingPathComponent("projects.json")
            do {
                if FileManager.default.fileExists(atPath: projectsCacheURL.path) {
                    try FileManager.default.removeItem(at: projectsCacheURL)
                    print("已清除项目数据缓存")
                }
            } catch {
                print("清除项目数据缓存失败: \(error)")
            }
            
            // 清除项目索引缓存
            self.projectIndex.clearIndexCache()
            
            // 确保UI更新完成
            Thread.sleep(forTimeInterval: 0.5)
            
            // 如果没有监视目录，不需要继续处理
            if self.tagManager.watchedDirectories.isEmpty {
                print("没有监视目录，加载完成")
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "加载完成"
                    alert.informativeText = "没有设置监视目录，请添加监视目录"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
                return
            }
            
            print("开始重新扫描目录...")
            
            // 同步扫描所有目录（不使用异步队列）
            for directory in self.tagManager.watchedDirectories {
                print("扫描目录: \(directory)")
                if FileManager.default.fileExists(atPath: directory) {
                    // 直接同步扫描
                    self.projectIndex.performScanSync(directory, force: true)
                } else {
                    print("目录不存在，跳过扫描: \(directory)")
                }
            }
            
            print("开始重新加载项目...")
            // 重新加载所有项目，完全不使用任何现有项目
            let allProjects = self.projectIndex.loadProjects(
                existingProjects: [:],
                fromWatchedDirectories: self.tagManager.watchedDirectories)
            
            print("加载了 \(allProjects.count) 个项目")
            
            // 更新项目列表
            DispatchQueue.main.async {
                // 确保列表是空的
                self.tagManager.projects.removeAll()
                self.tagManager.sortManager.updateSortedProjects([])
                
                // 添加新项目
                for project in allProjects {
                    self.tagManager.projectOperations.registerProject(project)
                }
                print("已更新项目列表，现有 \(self.tagManager.projects.count) 个项目")
                
                // 保存到缓存
                self.tagManager.projectOperations.saveAllToCache()
                
                // 显示结果提示
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "重新加载完成"
                    alert.informativeText = "已加载 \(allProjects.count) 个项目"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
            }
        }
    }
}
