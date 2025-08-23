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
        // 检查项目是否已存在
        if Project.isProjectExists(path: project.path, in: tagManager.projects) {
            print("项目已存在，跳过注册: \(project.name)")
            return
        }

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
    
    // 扫描目录并收集项目
    private func scanAndCollectProjects(_ path: String, force: Bool = false) -> [Project] {
        print("扫描目录: \(path)")
        
        // 执行二级扫描，处理父目录和子目录
        self.projectIndex.scanDirectoryTwoLevels(path, force: force)
        
        // 加载项目
        let newProjects = self.projectIndex.loadProjects(
            existingProjects: self.tagManager.projects,
            fromWatchedDirectories: [path]
        )
        
        print("在目录 \(path) 中找到 \(newProjects.count) 个项目")
        
        // 处理系统标签
        var processedProjects: [Project] = []
        for var project in newProjects {
            // 从系统加载标签
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
            processedProjects.append(project)
        }
        
        return processedProjects
    }
    
    func loadWatchedDirectories() {
        let directoriesURL = storage.appSupportURL.appendingPathComponent("directories.json")
        
        // 尝试加载保存的目录
        if let savedDirectories = loadSavedDirectories() {
            tagManager.watchedDirectories = Set(savedDirectories)
            print("从文件加载监视目录: \(savedDirectories)")
            
            // 后台加载所有目录
            loadAllDirectories(savedDirectories)
            return
        }
        
        print("没有找到保存的目录配置，设置默认目录...")
        setupDefaultDirectories()
    }
    
    // 在后台加载所有目录，完成后一次性更新UI
    private func loadAllDirectories(_ directories: [String]) {
        queue.async {
            print("开始后台加载所有目录: \(directories.count) 个")
            
            var allProjects: [Project] = []
            let existingProjectsSnapshot = self.tagManager.projects
            
            // 收集所有目录中的项目
            for directory in directories {
                let projects = self.scanAndCollectProjects(directory)
                allProjects.append(contentsOf: projects)
            }
            
            print("所有目录加载完成，共找到 \(allProjects.count) 个项目")
            
            // 检查是否有变化
            let existingCount = existingProjectsSnapshot.count
            let newPaths = Set(allProjects.map { $0.path })
            let existingPaths = Set(existingProjectsSnapshot.values.map { $0.path })
            
            let hasChanges = existingCount != allProjects.count || newPaths != existingPaths
            
            if !hasChanges && !existingProjectsSnapshot.isEmpty {
                print("项目数据没有变化，保持现有显示")
                return
            }
            
            // 一次性更新UI
            DispatchQueue.main.async {
                // 只有在有变化时才清空和更新
                if hasChanges {
                    // 清空现有项目
                    self.tagManager.projects.removeAll()
                    
                    // 注册所有新项目
                    for project in allProjects {
                        self.tagManager.projectOperations.registerProject(project)
                    }
                    
                    // 保存到缓存
                    self.tagManager.projectOperations.saveAllToCache()
                    
                    print("已更新界面显示 \(allProjects.count) 个项目")
                }
            }
        }
    }
    
    private func loadSavedDirectories() -> [String]? {
        let directoriesURL = storage.appSupportURL.appendingPathComponent("directories.json")
        do {
            let data = try Data(contentsOf: directoriesURL)
            let decoder = JSONDecoder()
            let directories = try decoder.decode([String].self, from: data)
            
            // 验证目录是否存在
            let existingDirectories = directories.filter { path in
                let exists = FileManager.default.fileExists(atPath: path)
                if !exists {
                    print("警告：目录不存在: \(path)")
                }
                return exists
            }
            
            if existingDirectories.isEmpty {
                print("所有保存的目录都不存在")
                return nil
            }
            
            return existingDirectories
        } catch {
            print("加载监视目录失败: \(error)")
            return nil
        }
    }
    
    private func setupDefaultDirectories() {
        let fileManager = FileManager.default
        var defaultDirectories = Set<String>()
        
        // 添加用户主目录作为监视目录
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            defaultDirectories.insert(home)
        }
        
        // 更新监视目录
        tagManager.watchedDirectories = defaultDirectories
        
        // 保存默认目录配置
        saveWatchedDirectories()
        print("已设置默认监视目录: \(defaultDirectories)")
        
        // 加载默认目录
        loadAllDirectories(Array(defaultDirectories))
    }
    
    func saveWatchedDirectories() {
        let directoriesURL = storage.appSupportURL.appendingPathComponent("directories.json")
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(Array(tagManager.watchedDirectories))
            try data.write(to: directoriesURL)
            print("保存监视目录到文件: \(Array(tagManager.watchedDirectories))")
        } catch {
            print("保存监视目录失败: \(error)")
        }
    }
    
    func addWatchedDirectory(_ path: String) {
        if !tagManager.watchedDirectories.contains(path) {
            // 更新监视目录集合
            tagManager.watchedDirectories.insert(path)
            
            // 保存更新后的目录列表
            saveWatchedDirectories()
            
            // 只加载新添加的目录
            queue.async {
                let newProjects = self.scanAndCollectProjects(path, force: true)
                
                // 更新UI
                DispatchQueue.main.async {
                    for project in newProjects {
                        self.tagManager.projectOperations.registerProject(project)
                    }
                    
                    // 保存到缓存
                    self.tagManager.projectOperations.saveAllToCache()
                    
                    print("已添加目录并加载 \(newProjects.count) 个新项目")
                }
            }
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
        // 删除该目录下的所有项目
        let projectsToRemove = tagManager.projects.values.filter { $0.path.hasPrefix(path) }
        DispatchQueue.main.async {
            for project in projectsToRemove {
                self.tagManager.projectOperations.removeProject(project.id)
            }
        }
    }
    
    func reloadAllProjects() {
        queue.async {
            print("开始重新加载所有项目...")
            
            // 获取所有监视目录
            let directories = Array(self.tagManager.watchedDirectories)
            
            var allProjects: [Project] = []
            
            // 清除索引缓存强制重新扫描
            self.projectIndex.clearIndexCache()
            
            // 收集所有目录中的项目
            for directory in directories {
                let projects = self.scanAndCollectProjects(directory, force: true)
                allProjects.append(contentsOf: projects)
            }
            
            print("重新加载完成，共找到 \(allProjects.count) 个项目")
            
            // 一次性更新UI
            DispatchQueue.main.async {
                // 清空现有项目
                self.tagManager.projects.removeAll()
                self.tagManager.sortManager.updateSortedProjects([])
                
                // 注册所有新项目
                for project in allProjects {
                    self.tagManager.projectOperations.registerProject(project)
                }
                
                // 保存到缓存
                self.tagManager.projectOperations.saveAllToCache()
                
                // 显示提示
                NotificationCenter.default.post(
                    name: .init("ShowToast"),
                    object: nil,
                    userInfo: [
                        "message": "已重新加载所有项目",
                        "duration": 2.0
                    ]
                )
            }
        }
    }
    
    func clearCacheAndReloadProjects() {
        queue.async {
            print("开始清除缓存并重新加载...")
            
            // 清除项目数据缓存
            let projectsCacheURL = self.storage.appSupportURL.appendingPathComponent("projects.json")
            try? FileManager.default.removeItem(at: projectsCacheURL)
            
            // 清除项目索引缓存
            self.projectIndex.clearIndexCache()
            
            // 过滤出存在的目录
            let existingDirectories = self.tagManager.watchedDirectories.filter {
                FileManager.default.fileExists(atPath: $0)
            }
            
            if existingDirectories.isEmpty {
                print("没有可用的监视目录")
                DispatchQueue.main.async {
                    // 清空项目列表
                    self.tagManager.projects.removeAll()
                    self.tagManager.sortManager.updateSortedProjects([])
                    
                    let alert = NSAlert()
                    alert.messageText = "没有可用目录"
                    alert.informativeText = "请添加要监视的目录"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
                return
            }
            
            var allProjects: [Project] = []
            
            // 收集所有目录中的项目
            for directory in existingDirectories {
                let projects = self.scanAndCollectProjects(directory, force: true)
                allProjects.append(contentsOf: projects)
            }
            
            print("缓存清理和重新加载完成，共找到 \(allProjects.count) 个项目")
            
            // 一次性更新UI
            DispatchQueue.main.async {
                // 清空现有项目
                self.tagManager.projects.removeAll()
                self.tagManager.sortManager.updateSortedProjects([])
                
                // 注册所有新项目
                for project in allProjects {
                    self.tagManager.projectOperations.registerProject(project)
                }
                
                // 保存到缓存
                self.tagManager.projectOperations.saveAllToCache()
                
                // 显示提示
                NotificationCenter.default.post(
                    name: .init("ShowToast"),
                    object: nil,
                    userInfo: [
                        "message": "已加载 \(allProjects.count) 个项目",
                        "duration": 2.0
                    ]
                )
            }
        }
    }

    // 增量更新项目方法 - 只有检测到变化时才更新UI
    func incrementallyReloadProjects() {
        queue.async {
            print("开始后台增量更新项目...")
            
            // 获取所有监视目录
            let directories = Array(self.tagManager.watchedDirectories)
            
            // 保存当前项目的快照（用于比较变化）
            let existingProjects = self.tagManager.projects
            let existingPaths = Set(existingProjects.values.map { $0.path })
            
            var allProjects: [Project] = []
            
            // 收集所有目录中的项目
            for directory in directories {
                let projects = self.scanAndCollectProjects(directory, force: false)
                allProjects.append(contentsOf: projects)
            }
            
            print("增量更新扫描完成，共找到 \(allProjects.count) 个项目")
            
            // 确定新增、删除和修改的项目
            let newPaths = Set(allProjects.map { $0.path })
            
            // 检查是否有变化
            if newPaths == existingPaths && existingProjects.count == allProjects.count {
                print("项目数据没有变化，保持现有显示")
                return
            }
            
            // 找出已添加、已删除和保持不变的项目
            let addedPaths = newPaths.subtracting(existingPaths)
            let removedPaths = existingPaths.subtracting(newPaths)
            
            // 只有在有变化时才更新UI
            if !addedPaths.isEmpty || !removedPaths.isEmpty {
                print("检测到项目变化，增量更新UI...")
                print("新增项目: \(addedPaths.count) 个, 移除项目: \(removedPaths.count) 个")
                
                DispatchQueue.main.async {
                    // 1. 删除已移除的项目
                    for path in removedPaths {
                        if let project = existingProjects.values.first(where: { $0.path == path }) {
                            self.tagManager.projectOperations.removeProject(project.id)
                        }
                    }
                    
                    // 2. 添加新项目
                    for project in allProjects {
                        if addedPaths.contains(project.path) {
                            self.tagManager.projectOperations.registerProject(project)
                        } else {
                            // 3. 更新可能已修改的现有项目（比如修改时间或标签变化）
                            if let existingProject = existingProjects.values.first(where: { $0.path == project.path }),
                               (existingProject.lastModified != project.lastModified || 
                                existingProject.tags != project.tags) {
                                self.tagManager.projectOperations.registerProject(project)
                            }
                        }
                    }
                    
                    // 保存到缓存
                    self.tagManager.projectOperations.saveAllToCache()
                    
                    if addedPaths.count > 0 || removedPaths.count > 0 {
                        // 显示提示
                        NotificationCenter.default.post(
                            name: .init("ShowToast"),
                            object: nil,
                            userInfo: [
                                "message": "项目已更新: +\(addedPaths.count) -\(removedPaths.count)",
                                "duration": 2.0
                            ]
                        )
                    }
                }
            } else {
                print("没有项目添加或删除，检查是否有项目内容更新...")
                
                // 检查是否有项目内容更新（如修改时间或标签变化）
                var updatedProjectsCount = 0
                
                DispatchQueue.main.async {
                    for project in allProjects {
                        if let existingProject = existingProjects.values.first(where: { $0.path == project.path }),
                           (existingProject.lastModified != project.lastModified || 
                            existingProject.tags != project.tags) {
                            self.tagManager.projectOperations.registerProject(project)
                            updatedProjectsCount += 1
                        }
                    }
                    
                    if updatedProjectsCount > 0 {
                        // 保存到缓存
                        self.tagManager.projectOperations.saveAllToCache()
                        
                        // 显示提示
                        NotificationCenter.default.post(
                            name: .init("ShowToast"),
                            object: nil,
                            userInfo: [
                                "message": "已更新 \(updatedProjectsCount) 个项目内容",
                                "duration": 2.0
                            ]
                        )
                    }
                }
            }
        }
    }
}
