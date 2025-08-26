import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine

class TagManager: ObservableObject, ProjectOperationDelegate, DirectoryWatcherDelegate {
    // MARK: - 类型定义

    enum SortCriteria {
        case name
        case lastModified
        case gitCommits
    }

    // MARK: - 静态实例 (⚰️ DEPRECATED - 单例癌症，即将死亡)
    
    @available(*, deprecated, message: "Use dependency injection via ServiceContainer instead. This singleton will be removed in future versions.")
    static weak var shared: TagManager?

    // MARK: - 公共属性

    @Published var allTags: Set<String> = []
    @Published var projects: [UUID: Project] = [:]
    @Published var watchedDirectories: Set<String> = []
    
    // 增量更新控制
    @Published var enableAutoIncrementalUpdate: Bool = false
    
    // 标签隐藏状态管理
    @Published var hiddenTags: Set<String> = []

    // MARK: - 组件

    let storage: TagStorage
    let colorManager: TagColorManager
    let sortManager: ProjectSortManager
    private let projectIndex: ProjectIndex
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Linus式智能刷新状态
    
    /// 目录修改时间缓存 - 用于智能检测变化
    private var directoryModificationTimes: [String: Date] = [:]
    lazy var projectOperations: ProjectOperationManager = {
        let manager = ProjectOperationManager(
            delegate: self, 
            sortDelegate: sortManager,
            storage: storage
        )
        return manager
    }()
    lazy var directoryWatcher: DirectoryWatcher = {
        let watcher = DirectoryWatcher(
            delegate: self,
            operationManager: projectOperations,
            storage: storage
        )
        return watcher
    }()

    // MARK: - Linus式状态管理 - 用纯数据模型替代复杂状态
    @Published var appState: AppStateData = AppStateData.empty
    
    // MARK: - 标签选择（保留UI状态）
    @Published var selectedTag: String?
    
    // MARK: - Linus式业务逻辑调用 - 所有逻辑都在BusinessLogic中
    
    /// 切换标签可见性 - 使用纯函数处理
    func toggleTagVisibility(_ tag: String) {
        let updatedFilter = FilterLogic.toggleTagVisibility(appState.filter, tag: tag)
        appState = AppStateLogic.updateState(appState, filter: updatedFilter)
        saveAll()
    }
    
    /// 检查标签是否隐藏 - 使用纯函数处理
    func isTagHidden(_ tag: String) -> Bool {
        return appState.filter.hiddenTags.contains(tag)
    }

    // MARK: - 初始化

    init() {
        print("TagManager 初始化...")

        // 初始化基础组件
        storage = TagStorage()
        colorManager = TagColorManager(storage: storage)
        sortManager = ProjectSortManager()
        projectIndex = ProjectIndex(storage: storage)
        
        // 设置静态实例 (⚰️ DEPRECATED)
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

    // MARK: - Linus式标签统计 - 使用纯函数，无缓存复杂性

    /// 获取标签使用次数 - 直接使用BusinessLogic计算，无缓存
    func getUsageCount(for tag: String) -> Int {
        let statistics = AppStateLogic.getTagStatistics(appState)
        return statistics[tag] ?? 0
    }
    
    /// 获取所有标签统计 - 直接使用BusinessLogic
    func getAllTagStatistics() -> [String: Int] {
        return AppStateLogic.getTagStatistics(appState)
    }

    // MARK: - 数据加载

    private func loadAllData() {
        print("开始加载所有数据...")
        
        // 1. 加载标签
        allTags = storage.loadTags()
        print("已加载标签: \(allTags)")
        
        // 1.5. 加载隐藏标签状态
        hiddenTags = storage.loadHiddenTags()
        print("已加载隐藏标签: \(hiddenTags)")

        // 2. 暂时注销系统标签加载
        // let systemTags = TagSystemSync.loadSystemTags()
        // allTags.formUnion(systemTags)
        print("已注销系统标签加载，当前标签: \(allTags)")

        // 3. 加载项目缓存并同步到新状态系统
        if let cachedProjects = loadProjectsFromCache() {
            print("从缓存加载了 \(cachedProjects.count) 个项目")
            
            // 同步到旧系统（过渡期间保持兼容）
            for project in cachedProjects {
                projects[project.id] = project
            }
            sortManager.updateSortedProjects(cachedProjects)
            
            // 同步到新的纯数据状态系统
            let projectDataDict = cachedProjects.toProjectDataArray()
                .reduce(into: [UUID: ProjectData]()) { dict, projectData in
                    dict[projectData.id] = projectData
                }
            
            appState = AppStateLogic.updateState(appState, projects: projectDataDict)
            
            // 将项目标签添加到全部标签集合中
            for project in cachedProjects {
                allTags.formUnion(project.tags)
            }
            
            // 保存到缓存，确保数据一致性
            projectOperations.saveAllToCache()
        }

        // 4. 加载监视目录
        directoryWatcher.loadWatchedDirectories()
        
        // 5. 完全取消启动时的自动加载 - Linus式快速启动
        // 不执行任何后台更新，让用户手动控制
        print("启动加载完成，等待用户手动操作...")
    }
    
    // 后台刷新项目，不清空现有UI
    private func backgroundRefreshProjects() {
        directoryWatcher.incrementallyReloadProjects()
    }
    
    // 手动触发增量更新
    func manualIncrementalUpdate() {
        print("手动触发增量更新")
        backgroundRefreshProjects()
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
        
        // 批量注册新项目（Project初始化时已经处理了系统标签）
        projectOperations.registerProjects(loadedProjects)
        
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

    /// Linus式项目筛选 - 使用BusinessLogic的纯函数处理
    func getFilteredProjects(withTags tags: Set<String>, searchText: String = "") -> [Project] {
        // 创建筛选条件
        let filter = FilterLogic.createFilter(
            selectedTags: tags, 
            searchText: searchText,
            sortCriteria: SortCriteriaData.lastModified, // 默认按修改时间排序
            isAscending: false
        )
        
        // 使用BusinessLogic处理
        let projectDataArray = Array(appState.projects.values)
        let filteredProjectData = ProjectLogic.processProjects(projectDataArray, with: filter)
        
        // 转换回Project数组
        return filteredProjectData.toProjectArray()
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
                    let updatedProject = project.withRemovedTag(tag)
                    projects[id] = updatedProject
                    sortManager.updateProject(updatedProject)
                }
            }

            invalidateTagUsageCache()
            needsSave = true
            saveAll()
        }
    }

    /// Linus式标签操作 - 使用BusinessLogic处理，Manager只管状态同步
    func addTagToProject(projectId: UUID, tag: String) {
        print("添加标签 '\(tag)' 到项目 \(projectId)")
        
        guard let currentProjectData = appState.projects[projectId] else { return }
        
        // 使用BusinessLogic处理标签添加
        let updatedProjectData = TagLogic.addTagToProject(currentProjectData, tag: tag)
        
        // 更新应用状态
        var updatedProjects = appState.projects
        updatedProjects[projectId] = updatedProjectData
        appState = AppStateLogic.updateState(appState, projects: updatedProjects)
        
        // 同步到旧的数据结构（过渡期间保持兼容）
        let updatedProject = Project.fromProjectData(updatedProjectData)
        projects[projectId] = updatedProject
        sortManager.updateProject(updatedProject)
        
        // 同步到系统（暂时禁用）
        // updatedProject.saveTagsToSystem()
        saveAll(force: true)
    }

    func removeTagFromProject(projectId: UUID, tag: String) {
        print("从项目 \(projectId) 移除标签 '\(tag)'")
        
        guard let currentProjectData = appState.projects[projectId] else { return }
        
        // 使用BusinessLogic处理标签移除
        let updatedProjectData = TagLogic.removeTagFromProject(currentProjectData, tag: tag)
        
        // 更新应用状态
        var updatedProjects = appState.projects
        updatedProjects[projectId] = updatedProjectData
        appState = AppStateLogic.updateState(appState, projects: updatedProjects)
        
        // 同步到旧的数据结构（过渡期间保持兼容）
        let updatedProject = Project.fromProjectData(updatedProjectData)
        projects[projectId] = updatedProject
        sortManager.updateProject(updatedProject)
        
        // 同步到系统（暂时禁用）
        // updatedProject.saveTagsToSystem()
        saveAll(force: true)
    }

    // MARK: - Linus式批量操作 - 使用BusinessLogic的批量函数

    func addTagToProjects(projectIds: Set<UUID>, tag: String) {
        print("批量添加标签 '\(tag)' 到 \(projectIds.count) 个项目")

        // 收集需要更新的项目数据
        let projectsToUpdate = projectIds.compactMap { appState.projects[$0] }
        
        // 使用BusinessLogic批量处理
        let updatedProjectsData = ProjectOperations.batchUpdateTags(projectsToUpdate, addTag: tag)
        
        // 批量更新应用状态
        var updatedProjects = appState.projects
        for updatedProjectData in updatedProjectsData {
            updatedProjects[updatedProjectData.id] = updatedProjectData
            
            // 同步到旧数据结构（过渡期间）
            let updatedProject = Project.fromProjectData(updatedProjectData)
            projects[updatedProjectData.id] = updatedProject
            sortManager.updateProject(updatedProject)
        }
        
        // 如果标签不存在，添加到全局标签集
        var updatedAllTags = allTags
        updatedAllTags.insert(tag)
        allTags = updatedAllTags
        
        appState = AppStateLogic.updateState(appState, projects: updatedProjects)
        saveAll(force: true)
        
        print("批量添加完成：已为 \(updatedProjectsData.count) 个项目添加标签 '\(tag)'")
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
        
        // 保存隐藏标签状态
        storage.saveHiddenTags(hiddenTags)
        
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
                    let updatedProject = project.withRemovedTag(oldName).withAddedTag(newName)
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

    // MARK: - Linus式简化刷新 - 新的智能刷新方法
    
    /// 安全的智能项目刷新 - 修复版本，绝不清空现有数据
    func refreshProjects() {
        Task {
            print("🔄 开始安全智能刷新...")
            
            // 🛡️ 安全检查：备份现有数据
            let backupProjects = projects
            let backupTags = allTags
            print("🛡️ 已备份 \(backupProjects.count) 个项目和 \(backupTags.count) 个标签")
            
            let existingDirectories = Array(watchedDirectories).filter {
                FileManager.default.fileExists(atPath: $0)
            }
            
            if existingDirectories.isEmpty {
                print("✅ 没有可用的监视目录")
                return
            }
            
            print("📁 安全扫描 \(existingDirectories.count) 个目录")
            
            // 强制重新扫描所有目录
            for directory in existingDirectories {
                projectIndex.scanDirectoryTwoLevels(directory, force: false)
            }
            
            // 使用现有项目作为基础，进行增量更新
            let newProjects = projectIndex.loadProjects(
                existingProjects: backupProjects,
                fromWatchedDirectories: Set(existingDirectories)
            )
            
            // 在主线程安全更新数据
            await MainActor.run {
                let oldCount = projects.count
                
                // 🛡️ 安全更新：绝不清空，只做增量合并
                var updatedProjects = backupProjects
                var updatedTags = backupTags
                var syncedProjectsCount = 0
                
                // 🔄 智能标签同步：为所有项目同步系统标签
                print("🏷️ 开始智能同步系统标签...")
                
                // 安全地合并新项目并同步所有项目的系统标签
                for newProject in newProjects {
                    updatedProjects[newProject.id] = newProject
                    updatedTags.formUnion(newProject.tags)
                }
                
                // 为现有项目同步系统标签（增强功能）
                for (projectId, existingProject) in updatedProjects {
                    let currentSystemTags = TagSystemSync.loadTagsFromFile(at: existingProject.path)
                    
                    if !currentSystemTags.isEmpty {
                        let originalTags = existingProject.tags
                        let mergedTags = originalTags.union(currentSystemTags)
                        
                        if mergedTags.count > originalTags.count {
                            // 发现新的系统标签，更新项目
                            let updatedProject = Project(
                                id: existingProject.id,
                                name: existingProject.name,
                                path: existingProject.path,
                                lastModified: existingProject.lastModified,
                                tags: mergedTags
                            )
                            updatedProjects[projectId] = updatedProject
                            updatedTags.formUnion(currentSystemTags)
                            syncedProjectsCount += 1
                        }
                    }
                }
                
                if syncedProjectsCount > 0 {
                    print("✅ 智能同步完成：\(syncedProjectsCount) 个项目同步了系统标签")
                } else {
                    print("✅ 智能同步完成：无新的系统标签需要同步")
                }
                
                // 🛡️ 双重验证：确保没有数据丢失
                if updatedProjects.count >= backupProjects.count && updatedTags.count >= backupTags.count {
                    // 安全：数据没有减少，可以更新
                    projects = updatedProjects
                    allTags = updatedTags
                    
                    // 更新排序和保存
                    sortManager.updateSortedProjects(Array(projects.values))
                    projectOperations.saveAllToCache()
                    
                    let newCount = projects.count
                    print("✅ 安全刷新成功：\(oldCount) → \(newCount) 个项目，标签从 \(backupTags.count) 到 \(updatedTags.count)")
                } else {
                    // 🚨 危险：检测到数据丢失，恢复备份
                    print("🚨 检测到潜在数据丢失，恢复备份数据")
                    print("   项目数量：\(backupProjects.count) → \(updatedProjects.count)")
                    print("   标签数量：\(backupTags.count) → \(updatedTags.count)")
                    
                    // 恢复备份
                    projects = backupProjects
                    allTags = backupTags
                    
                    print("🛡️ 已恢复备份，数据安全")
                }
            }
        }
    }
    
    
    
    /// 获取文件/目录修改时间
    private func getModificationDate(_ path: String) -> Date {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.modificationDate] as? Date ?? Date.distantPast
        } catch {
            return Date.distantPast
        }
    }
    
    // 清除缓存并重新加载所有项目 (保留作为备用方案)
    func clearCacheAndReloadProjects() {
        print("⚠️ 使用传统全量刷新方式")
        directoryWatcher.clearCacheAndReloadProjects()
    }
    
    /// 批量更新所有项目的git_daily数据
    func updateAllProjectsGitDaily() {
        print("🔄 开始批量更新所有项目的git_daily数据...")
        
        // 临时修复：强制清除现有git_daily数据以确保重新收集
        for (id, project) in projects {
            if project.git_daily == nil {
                let clearedProject = Project(
                    id: project.id,
                    name: project.name,
                    path: project.path,
                    tags: project.tags,
                    mtime: project.mtime,
                    size: project.size,
                    checksum: project.checksum,
                    git_commits: project.git_commits,
                    git_last_commit: project.git_last_commit,
                    git_daily: "", // 设置为空字符串而不是nil，强制更新
                    created: project.created,
                    checked: project.checked
                )
                projects[id] = clearedProject
            }
        }
        
        Task {
            let projectsArray = Array(projects.values)
            let updatedProjects = GitDailyCollector.updateProjectsWithGitDaily(projectsArray, days: 365)
            
            await MainActor.run {
                var updateCount = 0
                for updatedProject in updatedProjects {
                    if let existing = projects[updatedProject.id] {
                        // 检查git_daily是否有变化（处理nil值情况）
                        let existingGitDaily = existing.git_daily ?? ""
                        let updatedGitDaily = updatedProject.git_daily ?? ""
                        
                        if existingGitDaily != updatedGitDaily {
                            projects[updatedProject.id] = updatedProject
                            updateCount += 1
                            print("🔄 更新项目 \(updatedProject.name) 的git_daily: \(updatedGitDaily.prefix(50))...")
                        }
                    } else {
                        // 新项目，直接添加
                        projects[updatedProject.id] = updatedProject
                        updateCount += 1
                        print("➕ 添加新项目 \(updatedProject.name) 的git_daily数据")
                    }
                }
                
                if updateCount > 0 {
                    projectOperations.saveAllToCache()
                    print("✅ 成功更新了 \(updateCount) 个项目的git_daily数据")
                } else {
                    print("ℹ️ 所有项目的git_daily数据都已是最新")
                }
            }
        }
    }
    
    /// 刷新单个项目
    /// - Parameter projectId: 要刷新的项目ID
    func refreshSingleProject(_ projectId: UUID) {
        print("🔄 开始刷新单个项目: \(projectId)")
        
        guard let existingProject = projects[projectId] else {
            print("❌ 未找到要刷新的项目: \(projectId)")
            return
        }
        
        Task {
            // 使用BusinessLogic的纯函数刷新项目数据
            let projectData = existingProject.toProjectData()
            let refreshedData = ProjectOperations.refreshSingleProject(projectData)
            
            // 转换回Project并同步系统标签
            var syncedProject = Project.fromProjectData(refreshedData)
            
            // 更新git_daily数据
            print("🔄 正在更新项目 \(syncedProject.name) 的git_daily数据...")
            syncedProject = syncedProject.withUpdatedGitDaily(days: 365)
            // 加载最新的系统标签并合并
            let systemTags = TagSystemSync.loadTagsFromFile(at: refreshedData.path)
            let mergedTags = refreshedData.tags.union(systemTags)
            let finalProject = syncedProject.copyWith(tags: mergedTags)
            
            // 在主线程更新数据
            await MainActor.run {
                let oldProject = projects[projectId]
                projects[projectId] = finalProject
                
                // 更新排序管理器
                sortManager.updateProject(finalProject)
                
                // 更新标签集合
                allTags.formUnion(finalProject.tags)
                
                // 同步到新的状态系统
                var updatedProjects = appState.projects
                updatedProjects[projectId] = refreshedData
                appState = AppStateLogic.updateState(appState, projects: updatedProjects)
                
                // 保存到缓存
                projectOperations.saveAllToCache()
                
                print("✅ 项目刷新完成: \(finalProject.name)")
                
                // 检查是否有变化
                if let old = oldProject {
                    let nameChanged = old.name != finalProject.name
                    let tagsChanged = old.tags != finalProject.tags
                    let gitChanged = old.gitInfo?.commitCount != finalProject.gitInfo?.commitCount
                    
                    if nameChanged || tagsChanged || gitChanged {
                        print("📝 检测到项目变化:")
                        if nameChanged { print("  • 名称: \(old.name) → \(finalProject.name)") }
                        if tagsChanged { print("  • 标签: \(old.tags) → \(finalProject.tags)") }
                        if gitChanged { 
                            let oldCount = old.gitInfo?.commitCount ?? 0
                            let newCount = finalProject.gitInfo?.commitCount ?? 0
                            print("  • Git提交: \(oldCount) → \(newCount)") 
                        }
                    }
                }
            }
        }
    }
    
    /// 重命名项目
    /// - Parameters:
    ///   - projectId: 要重命名的项目ID
    ///   - newName: 新的项目名称
    func renameProject(_ projectId: UUID, newName: String, completion: @escaping (Result<Void, RenameError>) -> Void) {
        print("🏷️ 开始重命名项目: \(projectId) → \(newName)")
        
        guard let existingProject = projects[projectId] else {
            print("❌ 未找到要重命名的项目: \(projectId)")
            completion(.failure(.systemError(NSError(domain: "ProjectNotFound", code: 404))))
            return
        }
        
        Task {
            // 使用BusinessLogic的纯函数执行重命名
            let projectData = existingProject.toProjectData()
            let result = ProjectOperations.renameProject(projectData, newName: newName)
            
            await MainActor.run {
                switch result {
                case .success(let updatedProjectData):
                    let oldProject = projects[projectId]
                    let updatedProject = Project.fromProjectData(updatedProjectData)
                    
                    // 更新本地数据
                    projects[projectId] = updatedProject
                    sortManager.updateProject(updatedProject)
                    
                    // 更新标签集合
                    allTags.formUnion(updatedProject.tags)
                    
                    // 同步到新的状态系统
                    var updatedProjects = appState.projects
                    updatedProjects[projectId] = updatedProjectData
                    appState = AppStateLogic.updateState(appState, projects: updatedProjects)
                    
                    // 保存到缓存
                    projectOperations.saveAllToCache()
                    
                    print("✅ 项目重命名成功: \(existingProject.name) → \(newName)")
                    
                    // 检查路径变化
                    if let old = oldProject {
                        print("📝 路径更新: \(old.path) → \(updatedProject.path)")
                    }
                    
                    completion(.success(()))
                    
                case .failure(let error):
                    print("❌ 项目重命名失败: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - ProjectOperationDelegate 实现
    
    func notifyProjectsChanged() {
        // 触发 UI 更新
        objectWillChange.send()
    }
    
    // Linus式简化：不需要复杂的缓存失效逻辑，BusinessLogic会处理
    func invalidateTagUsageCache() {
        // 在新架构中，标签统计通过纯函数实时计算，无需缓存失效
    }
    
    // MARK: - DirectoryWatcherDelegate 实现
    
    // 所有必需的属性已经在类中定义了，不需要额外实现
    
    // MARK: - Git Daily 数据收集功能
    
    /// 更新所有项目的git_daily数据
    func updateAllProjectsGitDaily(days: Int = 90) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            print("📊 开始收集所有项目的Git历史数据...")
            let projectList = Array(self.projects.values)
            let updatedProjects = GitDailyCollector.updateProjectsWithGitDaily(projectList, days: days)
            
            DispatchQueue.main.async {
                var updateCount = 0
                for updatedProject in updatedProjects {
                    if let existing = self.projects[updatedProject.id] {
                        // 检查git_daily是否有变化（处理nil值情况）
                        let existingGitDaily = existing.git_daily ?? ""
                        let updatedGitDaily = updatedProject.git_daily ?? ""
                        
                        if existingGitDaily != updatedGitDaily {
                            self.projects[updatedProject.id] = updatedProject
                            updateCount += 1
                            print("🔄 更新项目 \(updatedProject.name) 的git_daily: \(updatedGitDaily.prefix(50))...")
                        }
                    } else {
                        // 新项目，直接添加
                        self.projects[updatedProject.id] = updatedProject
                        updateCount += 1
                        print("➕ 添加新项目 \(updatedProject.name) 的git_daily数据")
                    }
                }
                
                if updateCount > 0 {
                    print("✅ 成功更新 \(updateCount) 个项目的Git历史数据")
                    self.saveAll(force: true)
                    self.sortManager.updateSortedProjects(Array(self.projects.values))
                } else {
                    print("⚠️ 没有项目包含Git历史数据")
                }
            }
        }
    }
    
    // MARK: - 标签数据备份功能
    
    private lazy var backupManager: TagDataBackup = {
        return TagDataBackup(storage: storage, tagManager: self)
    }()
    
    /// 快速备份标签数据到桌面
    func quickBackupTagsToDesktop() -> URL? {
        return backupManager.quickBackupToDesktop()
    }
    
    /// 备份标签数据到指定位置
    func backupTagsToFile(at url: URL) throws {
        let backupData = backupManager.createBackup()
        try backupManager.saveBackupToFile(backupData, to: url)
    }
    
    /// 生成标签数据报告
    func generateTagsReport() -> String {
        let backupData = backupManager.createBackup()
        return backupManager.generateBackupReport(backupData)
    }
    
    /// 从备份文件导入标签数据
    func importTagsFromBackup(at url: URL, strategy: TagDataBackup.ImportStrategy = .merge) throws -> TagDataBackup.ImportResult {
        return try backupManager.importBackupFromFile(at: url, strategy: strategy)
    }
}
