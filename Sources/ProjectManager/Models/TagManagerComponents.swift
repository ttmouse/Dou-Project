import Foundation
import SwiftUI

// MARK: - 项目排序组件
class ProjectSortManager: SortManagerDelegate {
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
        // 先移除旧版本
        if let index = sortedProjects.firstIndex(where: { $0.id == project.id }) {
            sortedProjects.remove(at: index)
        }
        // 插入新版本
        insertProject(project)
    }

    func removeProject(_ project: Project) {
        if let index = sortedProjects.firstIndex(where: { $0.id == project.id }) {
            sortedProjects.remove(at: index)
        }
    }

    func getSortedProjects() -> [Project] {
        return sortedProjects
    }

    private func sortProjects() {
        sortedProjects.sort { (project1: Project, project2: Project) in
            let result: Bool
            switch sortCriteria {
            case .name:
                result = project1.name.localizedCaseInsensitiveCompare(project2.name) == .orderedAscending
            case .lastModified:
                result = project1.lastModified < project2.lastModified
            case .gitCommits:
                result = (project1.gitInfo?.commitCount ?? 0) < (project2.gitInfo?.commitCount ?? 0)
            }
            return isAscending ? result : !result
        }
    }

    private func binarySearchInsertionIndex(for project: Project) -> Int {
        var left = 0
        var right = sortedProjects.count
        
        while left < right {
            let mid = (left + right) / 2
            
            let shouldInsertBefore: Bool
            switch sortCriteria {
            case .name:
                let comparison = project.name.localizedCaseInsensitiveCompare(sortedProjects[mid].name)
                shouldInsertBefore = isAscending ? comparison == .orderedAscending : comparison == .orderedDescending
            case .lastModified:
                shouldInsertBefore = isAscending ? project.lastModified < sortedProjects[mid].lastModified : project.lastModified > sortedProjects[mid].lastModified
            case .gitCommits:
                shouldInsertBefore = isAscending ? (project.gitInfo?.commitCount ?? 0) < (sortedProjects[mid].gitInfo?.commitCount ?? 0) : (project.gitInfo?.commitCount ?? 0) > (sortedProjects[mid].gitInfo?.commitCount ?? 0)
            }
            
            if shouldInsertBefore {
                right = mid
            } else {
                left = mid + 1
            }
        }
        
        return left
    }
}

// MARK: - 协议定义 - 打破循环依赖

protocol ProjectOperationDelegate: AnyObject {
    var projects: [UUID: Project] { get set }
    var allTags: Set<String> { get set }

    func invalidateTagUsageCache()
    func notifyProjectsChanged()
}

protocol DirectoryWatcherDelegate: AnyObject {
    var watchedDirectories: Set<String> { get set }
    var projects: [UUID: Project] { get set }
    
    func notifyProjectsChanged()
}

protocol SortManagerDelegate: AnyObject {
    func updateSortedProjects(_ projects: [Project])
    func insertProject(_ project: Project)
    func updateProject(_ project: Project)
}

// MARK: - 项目操作管理器 - 无循环依赖版本

class ProjectOperationManager {
    weak var delegate: ProjectOperationDelegate?
    weak var sortDelegate: SortManagerDelegate?
    private let storage: TagStorage
    
    init(delegate: ProjectOperationDelegate?, sortDelegate: SortManagerDelegate?, storage: TagStorage) {
        self.delegate = delegate
        self.sortDelegate = sortDelegate
        self.storage = storage
    }
    
    func registerProject(_ project: Project, batchMode: Bool = false) {
        guard let delegate = delegate else { return }
        
        // 检查项目是否已存在
        if Project.isProjectExists(path: project.path, in: delegate.projects) {
            print("项目已存在，跳过注册: \(project.name)")
            return
        }

        print("注册项目: \(project.name), 标签: \(project.tags)")
        delegate.projects[project.id] = project

        // 处理新标签
        let newTags = project.tags.subtracting(delegate.allTags)
        if !newTags.isEmpty {
            delegate.allTags.formUnion(newTags)
            // 在批量模式下延迟系统标签同步
            if !batchMode {
                let systemTags = TagSystemSync.loadSystemTags()
                var updatedTags = systemTags
                updatedTags.formUnion(newTags)
                if updatedTags != systemTags {
                    TagSystemSync.syncTagsToSystem(updatedTags)
                }
            }
        }

        // 使用委托更新排序
        sortDelegate?.insertProject(project)

        // 使标签统计缓存失效
        delegate.invalidateTagUsageCache()

        // 只在非批量模式下立即保存
        if !batchMode {
            saveToCache()
        }
    }
    
    func registerProjects(_ projects: [Project]) {
        guard let delegate = delegate else { return }

        print("🔄 开始注册 \(projects.count) 个项目")
        print("📋 当前项目数: \(delegate.projects.count)")

        // 批量更新项目的git_daily数据
        let projectsWithGitDaily = GitDailyCollector.updateProjectsWithGitDaily(projects, days: 365)
        print("✅ 已更新git_daily数据: \(projectsWithGitDaily.count) 个")

        var allNewTags = Set<String>()
        var registeredCount = 0
        var skippedCount = 0

        // 批量注册，不触发单独的保存和系统同步
        for project in projectsWithGitDaily {
            // 检查项目是否已存在
            if Project.isProjectExists(path: project.path, in: delegate.projects) {
                print("   ⏭️ 跳过已存在: \(project.name)")
                skippedCount += 1
                continue
            }

            print("   ✅ 注册新项目: \(project.name) (ID: \(project.id))")
            delegate.projects[project.id] = project

            // 收集新标签
            let newTags = project.tags.subtracting(delegate.allTags)
            allNewTags.formUnion(newTags)
            delegate.allTags.formUnion(newTags)

            // 使用委托更新排序
            sortDelegate?.insertProject(project)
            registeredCount += 1
        }
        
        // 统一处理系统标签同步
        if !allNewTags.isEmpty {
            let systemTags = TagSystemSync.loadSystemTags()
            var updatedTags = systemTags
            updatedTags.formUnion(allNewTags)
            if updatedTags != systemTags {
                TagSystemSync.syncTagsToSystem(updatedTags)
            }
        }
        
        // 使标签统计缓存失效
        delegate.invalidateTagUsageCache()
        
        // 统一保存一次
        saveToCache()
        
        // 通知变更
        delegate.notifyProjectsChanged()
        
        print("批量注册完成：成功注册 \(registeredCount) 个项目，发现新标签 \(allNewTags.count) 个")
    }
    
    func removeProject(_ id: UUID) {
        guard let delegate = delegate,
              let project = delegate.projects[id] else { return }
        
        delegate.projects.removeValue(forKey: id)
        delegate.invalidateTagUsageCache()
        delegate.notifyProjectsChanged()
        
        saveToCache()
    }
    
    func saveAllToCache() {
        saveToCache()
    }
    
    private func saveToCache() {
        guard let delegate = delegate else { return }
        
        let cacheURL = storage.appSupportURL.appendingPathComponent("projects.json")
        do {
            let encoder = JSONEncoder()
            let projectsArray = Array(delegate.projects.values)
            let data = try encoder.encode(projectsArray)
            try data.write(to: cacheURL)
            print("项目数据已保存到缓存")
        } catch {
            print("保存项目缓存失败: \(error)")
        }
    }
}

// MARK: - 目录监视器 - 无循环依赖版本

class DirectoryWatcher {
    weak var delegate: DirectoryWatcherDelegate?
    weak var operationManager: ProjectOperationManager?
    
    private let storage: TagStorage
    private let projectIndex: ProjectIndex
    private let queue = DispatchQueue(label: "com.example.DirectoryWatcherQueue", attributes: [])
    
    init(delegate: DirectoryWatcherDelegate?, operationManager: ProjectOperationManager?, storage: TagStorage) {
        self.delegate = delegate
        self.operationManager = operationManager
        self.storage = storage
        self.projectIndex = ProjectIndex(storage: storage)
    }
    
    // 扫描目录并收集项目
    private func scanAndCollectProjects(_ path: String, force: Bool = false) -> [Project] {
        guard let delegate = delegate else { return [] }
        
        print("扫描目录: \(path)")
        
        // 执行二级扫描，处理父目录和子目录
        self.projectIndex.scanDirectoryTwoLevels(path, force: force)
        
        // 加载项目
        let newProjects = self.projectIndex.loadProjects(
            existingProjects: delegate.projects,
            fromWatchedDirectories: [path]
        )
        
        print("在目录 \(path) 中找到 \(newProjects.count) 个项目")
        
        return newProjects
    }
    
    // 批量扫描多个目录并收集项目，优化索引保存
    private func scanAndCollectProjectsBatch(_ paths: [String], force: Bool = false) -> [Project] {
        guard let delegate = delegate else { return [] }
        
        return PerformanceTimer.measure("Batch scan and collect projects (\(paths.count) paths)") {
            print("批量扫描目录: \(paths)")
            
            // 使用优化的项目加载器
            let optimizedLoader = ProjectLoaderOptimized()
            
            if force {
                // 强制重新扫描
                PerformanceTimer.logMemoryUsage("Before force scan")
                self.projectIndex.scanDirectoriesTwoLevelsBatch(paths, force: true)
                
                let allProjectPaths = optimizedLoader.discoverProjectsSmart(from: paths)
                let newProjects = optimizedLoader.createProjectsBatch(
                    paths: allProjectPaths,
                    existingProjects: delegate.projects
                )
                
                PerformanceTimer.logMemoryUsage("After force scan")
                print("强制扫描完成: 在 \(paths.count) 个目录中找到 \(newProjects.count) 个项目")
                return newProjects
            } else {
                // 增量更新
                let newProjects = optimizedLoader.updateProjectsIncremental(
                    currentProjects: delegate.projects,
                    watchedDirectories: paths
                )
                
                print("增量扫描完成: 在 \(paths.count) 个目录中找到 \(newProjects.count) 个项目")
                return newProjects
            }
        }
    }
    
    func loadWatchedDirectories() {
        if let savedDirectories = loadSavedDirectories() {
            delegate?.watchedDirectories = Set(savedDirectories)
            print("从文件加载监视目录: \(savedDirectories)")
            print("监视目录已设置，等待手动加载项目")
            return
        }
        
        print("没有找到保存的目录配置，设置默认目录...")
        setupDefaultDirectories()
    }
    
    func addWatchedDirectory(_ path: String) {
        guard let delegate = delegate else { return }
        
        if !delegate.watchedDirectories.contains(path) {
            delegate.watchedDirectories.insert(path)
            saveWatchedDirectories()
            
            // 加载新目录的项目
            queue.async {
                let newProjects = self.scanAndCollectProjects(path, force: true)
                
                DispatchQueue.main.async {
                    self.operationManager?.registerProjects(newProjects)
                    print("已添加目录并加载 \(newProjects.count) 个新项目")
                }
            }
        }
    }
    
    func removeWatchedDirectory(_ path: String) {
        guard let delegate = delegate else { return }
        
        if delegate.watchedDirectories.contains(path) {
            delegate.watchedDirectories.remove(path)
            saveWatchedDirectories()
            removeProjectsInDirectory(path)
        }
    }
    
    private func removeProjectsInDirectory(_ path: String) {
        guard let delegate = delegate else { return }
        
        // 删除该目录下的所有项目
        let projectsToRemove = delegate.projects.values.filter { $0.path.hasPrefix(path) }
        for project in projectsToRemove {
            operationManager?.removeProject(project.id)
        }
    }
    
    func clearCacheAndReloadProjects() {
        guard let delegate = delegate else { return }
        
        queue.async {
            print("开始清除缓存并重新加载...")
            
            // 清除项目数据缓存
            let projectsCacheURL = self.storage.appSupportURL.appendingPathComponent("projects.json")
            try? FileManager.default.removeItem(at: projectsCacheURL)
            
            // 清除项目索引缓存
            self.projectIndex.clearIndexCache()
            
            // 过滤出存在的目录
            let existingDirectories = delegate.watchedDirectories.filter {
                FileManager.default.fileExists(atPath: $0)
            }
            
            if existingDirectories.isEmpty {
                print("没有可用的监视目录")
                DispatchQueue.main.async {
                    delegate.notifyProjectsChanged()
                }
                return
            }
            
            // 批量扫描所有目录，只保存一次索引
            print("开始批量扫描 \(existingDirectories.count) 个目录")
            self.projectIndex.scanDirectoriesTwoLevelsBatch(Array(existingDirectories), force: true)
            
            // 一次性加载所有项目
            let allProjects = self.projectIndex.loadProjects(
                existingProjects: delegate.projects,
                fromWatchedDirectories: Set(existingDirectories)
            )
            
            print("缓存清理和重新加载完成，共找到 \(allProjects.count) 个项目")
            
            // 一次性更新UI
            DispatchQueue.main.async {
                // 清空现有项目
                delegate.projects.removeAll()
                
                // 为每个项目从系统恢复标签
                var projectsWithTags: [Project] = []
                for var project in allProjects {
                    let systemTags = TagSystemSync.loadTagsFromFile(at: project.path)
                    if !systemTags.isEmpty {
                        // 使用新的标签创建项目副本
                        let projectWithTags = Project(
                            id: project.id,
                            name: project.name,
                            path: project.path,
                            lastModified: project.lastModified,
                            tags: systemTags
                        )
                        projectsWithTags.append(projectWithTags)
                        print("恢复项目 '\(project.name)' 的标签: \(systemTags)")
                    } else {
                        projectsWithTags.append(project)
                    }
                }
                
                // 批量注册所有项目（已恢复标签）
                self.operationManager?.registerProjects(projectsWithTags)
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
        guard let delegate = delegate else { return }
        
        let fileManager = FileManager.default
        var defaultDirectories = Set<String>()
        
        // 添加用户主目录作为监视目录
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            defaultDirectories.insert(home)
        }
        
        // 更新监视目录
        delegate.watchedDirectories = defaultDirectories
        
        // 保存默认目录配置
        saveWatchedDirectories()
        print("已设置默认监视目录: \(defaultDirectories)")
        print("默认监视目录已设置，等待手动加载项目")
    }
    
    func saveWatchedDirectories() {
        guard let delegate = delegate else { return }
        
        let directoriesURL = storage.appSupportURL.appendingPathComponent("directories.json")
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(Array(delegate.watchedDirectories))
            try data.write(to: directoriesURL)
            print("保存监视目录到文件: \(Array(delegate.watchedDirectories))")
        } catch {
            print("保存监视目录失败: \(error)")
        }
    }
    
    func incrementallyReloadProjects() {
        guard let delegate = delegate else { return }
        
        queue.async {
            print("开始后台增量更新项目...")
            
            // 获取所有监视目录
            let directories = Array(delegate.watchedDirectories)
            
            // 保存当前项目的快照（用于比较变化）
            let existingProjects = delegate.projects
            let existingPaths = Set(existingProjects.values.map { $0.path })
            
            // 批量收集所有目录中的项目，优化索引保存
            let allProjects = self.scanAndCollectProjectsBatch(directories, force: false)
            
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
                            self.operationManager?.removeProject(project.id)
                        }
                    }
                    
                    // 2. 收集需要注册/更新的项目
                    var projectsToRegister: [Project] = []
                    for project in allProjects {
                        if addedPaths.contains(project.path) {
                            // 新项目
                            projectsToRegister.append(project)
                        } else {
                            // 检查是否需要更新现有项目（比如修改时间或标签变化）
                            if let existingProject = existingProjects.values.first(where: { $0.path == project.path }),
                               (existingProject.lastModified != project.lastModified || 
                                existingProject.tags != project.tags) {
                                projectsToRegister.append(project)
                            }
                        }
                    }
                    
                    // 3. 批量注册/更新项目
                    if !projectsToRegister.isEmpty {
                        self.operationManager?.registerProjects(projectsToRegister)
                    }
                    
                    if addedPaths.count > 0 || removedPaths.count > 0 {
                        print("项目增量更新完成: +\(addedPaths.count) -\(removedPaths.count)")
                    }
                }
            } else {
                print("没有项目添加或删除，检查是否有项目内容更新...")
                
                // 检查是否有项目内容更新（如修改时间或标签变化）
                var updatedProjects: [Project] = []
                
                for project in allProjects {
                    if let existingProject = existingProjects.values.first(where: { $0.path == project.path }),
                       (existingProject.lastModified != project.lastModified || 
                        existingProject.tags != project.tags) {
                        updatedProjects.append(project)
                    }
                }
                
                if !updatedProjects.isEmpty {
                    DispatchQueue.main.async {
                        // 批量更新项目
                        self.operationManager?.registerProjects(updatedProjects)
                        print("项目内容更新完成：已更新 \(updatedProjects.count) 个项目内容")
                    }
                }
            }
        }
    }
}
