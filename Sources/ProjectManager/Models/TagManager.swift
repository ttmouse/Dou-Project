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
    
    // 状态指示
    @Published var isRunningTaggingRules: Bool = false
    @Published var lastTaggingRuleMessage: String? = nil

    /// 倒排索引：标签 -> 项目ID集合 (O(1) 检索受影响项目)
    private var tagToProjectMap: [String: Set<UUID>] = [:]
    
    /// I/O 专用串行队列，确保磁盘操作不阻塞 UI
    private let ioQueue = DispatchQueue(label: "com.projectmanager.tagmanager.io", qos: .background)

    // MARK: - 组件

    /// 统一数据存储（新架构）
    let unifiedStorage: AppStateStorage
    
    let storage: TagStorage  // 保留用于兼容
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

        // 初始化统一存储（新架构）
        unifiedStorage = AppStateStorage()
        
        // 初始化基础组件（保留用于兼容）
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
        
        // 1. 从统一存储加载标签和目录（新架构，自动处理迁移）
        let appStateFile = unifiedStorage.load()
        
        // 2. 加载标签数据
        allTags = Set(appStateFile.tags.map { $0.name })
        hiddenTags = Set(appStateFile.tags.filter { $0.hidden }.map { $0.name })
        print("已加载标签: \(allTags.count) 个, 隐藏: \(hiddenTags.count) 个")
        
        // 3. 同步颜色到 colorManager（兼容现有代码）
        for tagData in appStateFile.tags {
            colorManager.setColor(tagData.color.toColor(), for: tagData.name)
        }
        
        // 4. 加载监视目录
        watchedDirectories = Set(appStateFile.directories)
        print("已加载目录: \(watchedDirectories.count) 个")

        // 5. 加载项目缓存并同步到状态系统
        if let cachedProjects = loadProjectsFromCache() {
            print("从缓存加载了 \(cachedProjects.count) 个项目")
            
            for project in cachedProjects {
                projects[project.id] = project
            }
            sortManager.updateSortedProjects(cachedProjects)
            
            let projectDataDict = cachedProjects.toProjectDataArray()
                .reduce(into: [UUID: ProjectData]()) { dict, projectData in
                    dict[projectData.id] = projectData
                }
            
            appState = AppStateLogic.updateState(appState, projects: projectDataDict)
            
            // 将项目标签添加到全部标签集合中
            for project in cachedProjects {
                allTags.formUnion(project.tags)
            }
            
            projectOperations.saveAllToCache()
        }
        
        print("启动加载完成，等待用户手动操作...")
        
        // 6. 重建索引
        rebuildTagIndex()
    }
    
    /// 重建倒排索引 (标签 -> 项目ID) - 仅在初始化时使用
    private func rebuildTagIndex() {
        var newMap: [String: Set<UUID>] = [:]
        for (id, project) in projects {
            for tag in project.tags {
                newMap[tag, default: []].insert(id)
            }
        }
        self.tagToProjectMap = newMap
        print("倒排索引重建完成: \(newMap.count) 个标签")
    }

    /// 增量更新倒排索引 (O(1) 性能)
    private func updateTagIndex(for id: UUID, oldTags: Set<String>?, newTags: Set<String>) {
        // 1. 移除旧标签关联
        if let old = oldTags {
            for tag in old {
                tagToProjectMap[tag]?.remove(id)
                if tagToProjectMap[tag]?.isEmpty == true {
                    tagToProjectMap.removeValue(forKey: tag)
                }
            }
        }
        
        // 2. 添加新标签关联
        for tag in newTags {
            tagToProjectMap[tag, default: []].insert(id)
        }
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

    /// 立即对所有项目运行自动打标规则（仅使用用户在面板中配置的 BusinessTagger 规则）
    func applyTaggingRulesToAllProjects() {
        print("开始对所有项目运行自动打标规则...")
        
        isRunningTaggingRules = true
        lastTaggingRuleMessage = "正在扫描项目..."
        
        let projectsSnapshot = Array(projects.values)
        let total = projectsSnapshot.count
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var modifiedProjects: [Project] = []
            
            for (index, project) in projectsSnapshot.enumerated() {
                // 仅应用用户在面板中配置的业务标签规则 (BusinessTagger)
                // 移除了写死的 AutoTagger 技术栈规则
                var updatedProject = BusinessTagger.applyBusinessTags(to: project)
                
                if updatedProject.tags != project.tags {
                    modifiedProjects.append(updatedProject)
                }
                
                if (index + 1) % 10 == 0 || index == total - 1 {
                    print("  自动打标进度: \(index + 1)/\(total)")
                }
            }
            
            if !modifiedProjects.isEmpty {
                DispatchQueue.main.async {
                    print("  正在同步 \(modifiedProjects.count) 个项目的更新...")
                    
                    var updatedAppStateProjects = self.appState.projects
                    var newTagsDiscovered = Set<String>()
                    
                    for updatedProject in modifiedProjects {
                        let id = updatedProject.id
                        if self.projects[id] != nil {
                            let oldTags = self.projects[id]?.tags
                            self.projects[id] = updatedProject
                            
                            // 同步到 AppState
                            updatedAppStateProjects[id] = updatedProject.toProjectData()
                            
                            // 收集新发现的标签
                            for tag in updatedProject.tags {
                                if !self.allTags.contains(tag) {
                                    newTagsDiscovered.insert(tag)
                                }
                            }
                            
                            self.updateTagIndex(for: id, oldTags: oldTags, newTags: updatedProject.tags)
                            self.sortManager.updateProject(updatedProject)
                        }
                    }
                    
                    // 将新发现的标签合并到全局标签列表
                    if !newTagsDiscovered.isEmpty {
                        print("  发现了 \(newTagsDiscovered.count) 个新标签: \(newTagsDiscovered.joined(separator: ", "))")
                        self.allTags.formUnion(newTagsDiscovered)
                        
                        // 确保新标签有颜色
                        for tag in newTagsDiscovered {
                            if self.colorManager.getColor(for: tag) == nil {
                                let hash = abs(tag.hashValue)
                                let colorIndex = hash % AppTheme.tagPresetColors.count
                                let color = AppTheme.tagPresetColors[colorIndex].color
                                self.colorManager.setColor(color, for: tag)
                            }
                        }
                    }
                    
                    // 更新 AppState
                    self.appState = AppStateLogic.updateState(self.appState, projects: updatedAppStateProjects)
                    
                    self.invalidateTagUsageCache()
                    self.needsSave = true
                    self.saveAll()
                    
                    self.objectWillChange.send()
                    self.isRunningTaggingRules = false
                    self.lastTaggingRuleMessage = "打标完成：更新了 \(modifiedProjects.count) 个项目"
                    print("✅ 自动打标规则运行完成，更新了 \(modifiedProjects.count) 个项目")
                }
            } else {
                DispatchQueue.main.async {
                    self.isRunningTaggingRules = false
                    self.lastTaggingRuleMessage = "打标完成：未发现新标签"
                }
                print("✅ 自动打标规则运行完成，无项目更新")
            }
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
        guard allTags.contains(tag) else { return }

        // --- 乐观 UI: 视觉先行 ---
        // 1. 立即从全局标签列表移除 (左侧菜单瞬时刷新)
        allTags.remove(tag)
        
        // 2. 如果当前选中了该标签，立即取消选中 (右侧列表清空/重置)
        if selectedTag == tag {
            selectedTag = nil
        }
        
        // 3. 立即清理颜色和同步 UI 状态
        colorManager.removeColor(for: tag)
        objectWillChange.send()
        
        // --- 后台处理: 逻辑落后 ---
        let affectedIds = tagToProjectMap[tag] ?? []
        
        // 如果没有项目使用该标签，直接清理索引并保存
        if affectedIds.isEmpty {
            tagToProjectMap.removeValue(forKey: tag)
            saveAll()
            return
        }

        print("乐观 UI 已生效，后台开始静默更新 \(affectedIds.count) 个项目")

        // 捕获主线程数据快照，确保后台计算的线程安全
        let projectsSnapshot = self.projects

        // 异步计算更新，避免阻塞 UI 线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 仅存储实际发生变化的项目，避免覆盖整个字典导致的 Race Condition
            var modifiedProjects: [UUID: Project] = [:]
            for id in affectedIds {
                if let project = projectsSnapshot[id] {
                    modifiedProjects[id] = project.withRemovedTag(tag)
                }
            }
            
            // 在主线程执行增量更新
            DispatchQueue.main.async {
                // 1. 增量更新项目和索引 (右侧列表此时会再次刷新以反映真实数据)
                var updatedAppStateProjects = self.appState.projects
                
                for (id, updatedProject) in modifiedProjects {
                    if self.projects[id] != nil {
                        let oldTags = self.projects[id]?.tags
                        self.projects[id] = updatedProject
                        
                        // 同步到 AppState
                        updatedAppStateProjects[id] = updatedProject.toProjectData()
                        
                        self.updateTagIndex(for: id, oldTags: oldTags, newTags: updatedProject.tags)
                        self.sortManager.updateProject(updatedProject)
                    }
                }
                
                // 更新 AppState
                self.appState = AppStateLogic.updateState(self.appState, projects: updatedAppStateProjects)
                
                // 2. 最终清理索引并落盘
                self.tagToProjectMap.removeValue(forKey: tag)
                self.invalidateTagUsageCache()
                self.needsSave = true
                self.saveAll()
                
                print("✅ 标签 '\(tag)' 后台清理完成，同步了 \(modifiedProjects.count) 个项目")
            }
        }
    }

    func updateProjectNotes(projectId: UUID, notes: String) {
        print("更新项目备注: \(projectId) -> \(notes)")

        guard var project = projects[projectId] else {
            print("⚠️ 项目不存在: \(projectId)")
            return
        }

        let updatedProject = Project(
            id: project.id,
            name: project.name,
            path: project.path,
            tags: project.tags,
            mtime: project.mtime,
            size: project.size,
            checksum: project.checksum,
            git_commits: project.git_commits,
            git_last_commit: project.git_last_commit,
            git_daily: project.git_daily,
            startupCommand: project.startupCommand,
            customPort: project.customPort,
            created: project.created,
            checked: Date()
        )

        projects[projectId] = updatedProject
        sortManager.updateProject(updatedProject)
        needsSave = true
        saveAll()
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
        let oldTags = projects[projectId]?.tags
        projects[projectId] = updatedProject
        updateTagIndex(for: projectId, oldTags: oldTags, newTags: updatedProject.tags)
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
        let oldTags = projects[projectId]?.tags
        projects[projectId] = updatedProject
        updateTagIndex(for: projectId, oldTags: oldTags, newTags: updatedProject.tags)
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
            let oldTags = projects[updatedProjectData.id]?.tags
            projects[updatedProjectData.id] = updatedProject
            updateTagIndex(for: updatedProjectData.id, oldTags: oldTags, newTags: updatedProject.tags)
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
        // 捕获当前状态快照
        let tagsSnapshot = allTags
        let hiddenTagsSnapshot = hiddenTags
        let directoriesSnapshot = watchedDirectories
        let projectsSnapshot = Array(projects.values)
        
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. 构建统一的标签数据
            var tagDataArray: [AppStateStorage.TagData] = []
            for tag in tagsSnapshot {
                let color = self.colorManager.getColor(for: tag) ?? Color.gray
                let hidden = hiddenTagsSnapshot.contains(tag)
                tagDataArray.append(AppStateStorage.TagData(name: tag, color: color, hidden: hidden))
            }
            
            // 2. 保存到统一存储
            let appStateFile = AppStateStorage.AppStateFile(
                version: 2,
                tags: tagDataArray,
                directories: Array(directoriesSnapshot)
            )
            self.unifiedStorage.save(appStateFile)
            
            // 3. 保存项目数据（暂时保留独立文件）
            self.storage.saveProjects(projectsSnapshot)
            
            // 4. 同步到系统标签
            TagSystemSync.syncTagsToSystem(tagsSnapshot)
            for project in projectsSnapshot {
                project.saveTagsToSystem()
            }
            
            DispatchQueue.main.async {
                self.needsSave = false
                print("✅ 所有数据已成功后台同步至磁盘")
            }
        }
    }

    // MARK: - 项目管理

    func registerProject(_ project: Project) {
        let oldTags = projects[project.id]?.tags
        projectOperations.registerProject(project)
        updateTagIndex(for: project.id, oldTags: oldTags, newTags: project.tags)
    }

    func removeProject(_ id: UUID) {
        if let project = projects[id] {
            updateTagIndex(for: id, oldTags: project.tags, newTags: [])
        }
        projectOperations.removeProject(id)
    }
    
    func updateProject(_ project: Project) {
        print("更新项目: \(project.name)")
        let oldTags = projects[project.id]?.tags
        projects[project.id] = project
        updateTagIndex(for: project.id, oldTags: oldTags, newTags: project.tags)
        sortManager.updateProject(project)
        
        // 更新 AppState
        var updatedProjects = appState.projects
        updatedProjects[project.id] = project.toProjectData()
        appState = AppStateLogic.updateState(appState, projects: updatedProjects)
        
        saveAll()
    }

    // MARK: - 标签操作

    func renameTag(_ oldName: String, to newName: String, color: Color) {
        print("重命名标签: \(oldName) -> \(newName)")
        guard allTags.contains(oldName) && !allTags.contains(newName) else { return }
        
        // --- 乐观 UI: 视觉先行 ---
        // 1. 立即更新全局标签列表 (左侧菜单瞬时刷新)
        allTags.remove(oldName)
        allTags.insert(newName)
        
        // 2. 如果当前选中了旧标签，立即切换到新标签 (保持右侧列表状态)
        if selectedTag == oldName {
            selectedTag = newName
        }
        
        // 3. 立即更新颜色和同步 UI 状态
        colorManager.removeColor(for: oldName)
        colorManager.setColor(color, for: newName)
        objectWillChange.send()

        // --- 后台处理: 逻辑落后 ---
        let affectedIds = tagToProjectMap[oldName] ?? []
        
        if affectedIds.isEmpty {
            tagToProjectMap.removeValue(forKey: oldName)
            tagToProjectMap[newName] = []
            saveAll()
            return
        }

        print("乐观 UI 已生效，后台开始静默重命名 \(affectedIds.count) 个项目")

        let projectsSnapshot = self.projects

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var modifiedProjects: [UUID: Project] = [:]
            for id in affectedIds {
                if let project = projectsSnapshot[id] {
                    modifiedProjects[id] = project.withRemovedTag(oldName).withAddedTag(newName)
                }
            }
            
            DispatchQueue.main.async {
                // 1. 增量更新项目和索引 (右侧列表此时会再次刷新以反映真实数据)
                var updatedAppStateProjects = self.appState.projects

                for (id, updatedProject) in modifiedProjects {
                    if self.projects[id] != nil {
                        let oldTags = self.projects[id]?.tags
                        self.projects[id] = updatedProject
                        
                        // 同步到 AppState
                        updatedAppStateProjects[id] = updatedProject.toProjectData()
                        
                        self.updateTagIndex(for: id, oldTags: oldTags, newTags: updatedProject.tags)
                        self.sortManager.updateProject(updatedProject)
                    }
                }
                
                // 更新 AppState
                self.appState = AppStateLogic.updateState(self.appState, projects: updatedAppStateProjects)
                
                // 2. 最终清理旧索引并落盘
                self.tagToProjectMap.removeValue(forKey: oldName)
                self.invalidateTagUsageCache()
                self.saveAll()
                
                print("✅ 标签 '\(oldName)' -> '\(newName)' 后台重命名完成")
            }
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
        // 批量更新后重建索引确保一致性
        rebuildTagIndex()
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
    
    /// 快速备份标签数据到桌面
    func quickBackupTagsToDesktop() -> URL? {
        print("⚠️ 备份功能已禁用")
        return nil
    }

    /// 备份标签数据到指定位置
    func backupTagsToFile(at url: URL) throws {
        print("⚠️ 备份功能已禁用")
    }
    
    /// 生成标签数据报告
    func generateTagsReport() -> String {
        return "标签报告功能已禁用"
    }
    
    /// 从备份文件导入标签数据
    func importTagsFromBackup(at url: URL, strategy: TagDataBackup.ImportStrategy) throws -> TagDataBackup.ImportResult {
        let backupManager = TagDataBackup(storage: storage, tagManager: self)
        return try backupManager.importBackupFromFile(at: url, strategy: strategy)
    }

    // MARK: - 单目录刷新功能
    
    /// 刷新单个工作目录的项目（完整版 - 支持增加和删除）
    /// - Parameter directoryPath: 要刷新的目录路径
    func refreshSingleDirectory(_ directoryPath: String) {
        Task {
            print("🔄 开始完整刷新单个目录: \(directoryPath)")
            
            // 🛡️ 安全检查：验证目录是否存在且被监视
            guard watchedDirectories.contains(directoryPath),
                  FileManager.default.fileExists(atPath: directoryPath) else {
                print("❌ 目录不存在或未被监视: \(directoryPath)")
                await MainActor.run {
                    showRefreshErrorAlert(message: "目录不存在或未被监视：\n\(directoryPath)")
                }
                return
            }
            
            // 显示进度提示并启动进度动画
            await MainActor.run {
                startProgressAnimation(directoryName: (directoryPath as NSString).lastPathComponent, initialStatus: "扫描中...")
            }
            
            // 获取该目录下现有的所有项目
            let existingProjectsInDir = projects.values.filter { $0.path.hasPrefix(directoryPath) }
            let existingProjectPaths = Set(existingProjectsInDir.map { $0.path })
            print("🛡️ 该目录现有 \(existingProjectPaths.count) 个项目")
            
            // 扫描目录，获取实际存在的项目
            let discoveredProjects = await scanDirectoryForAllProjects(directoryPath)
            let discoveredProjectPaths = Set(discoveredProjects.map { $0.path })
            
            // 计算变化
            let newProjectPaths = discoveredProjectPaths.subtracting(existingProjectPaths)
            let deletedProjectPaths = existingProjectPaths.subtracting(discoveredProjectPaths)
            let newProjects = discoveredProjects.filter { newProjectPaths.contains($0.path) }
            
            await MainActor.run {
                // 更新进度到60%：分析变化
                setProgress(0.6, directoryName: (directoryPath as NSString).lastPathComponent, 
                           status: "发现 \(newProjects.count) 个新项目，\(deletedProjectPaths.count) 个已删除")
                
                // 处理删除的项目
                var deletedCount = 0
                for deletedPath in deletedProjectPaths {
                    if let project = projects.values.first(where: { $0.path == deletedPath }) {
                        projects.removeValue(forKey: project.id)
                        sortManager.removeProject(project)
                        deletedCount += 1
                        print("🗑️ 删除不存在的项目: \(project.name)")
                    }
                }
                
                // 更新进度到80%：处理变化
                setProgress(0.8, directoryName: (directoryPath as NSString).lastPathComponent, 
                           status: "正在更新项目列表...")
                
                // 添加新项目
                var updatedProjects = projects
                var updatedTags = allTags
                
                for newProject in newProjects {
                    updatedProjects[newProject.id] = newProject
                    updatedTags.formUnion(newProject.tags)
                    sortManager.insertProject(newProject)
                    print("➕ 添加新项目: \(newProject.name)")
                }
                
                // 更新数据
                projects = updatedProjects
                allTags = updatedTags
                
                // 使标签统计缓存失效
                invalidateTagUsageCache()
                
                // 保存缓存
                projectOperations.saveAllToCache()
                
                // 设置进度为100%
                setProgress(1.0, directoryName: (directoryPath as NSString).lastPathComponent, status: "完成！")
                
                // 短暂延迟后显示最终结果
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.showRefreshSuccessAlert(
                        directoryName: (directoryPath as NSString).lastPathComponent,
                        addedCount: newProjects.count,
                        syncedCount: deletedCount,
                        totalCount: existingProjectPaths.count + newProjects.count - deletedCount
                    )
                }
                
                // 后台收集新项目的Git信息
                if !newProjects.isEmpty {
                    Task {
                        await collectGitDataForNewProjects(newProjects)
                    }
                }
            }
        }
    }
    
    /// 扫描目录获取新项目（快速版本，不包含Git数据收集）
    private func scanDirectoryForNewProjects(_ directoryPath: String, existingPaths: Set<String>) async -> [Project] {
        return await withTaskGroup(of: [Project].self) { group in
            group.addTask {
                // 在后台线程执行扫描
                var discoveredProjects: [Project] = []
                
                do {
                    let fileManager = FileManager.default
                    let contents = try fileManager.contentsOfDirectory(atPath: directoryPath)
                    
                    for item in contents {
                        let itemPath = (directoryPath as NSString).appendingPathComponent(item)
                        var isDirectory: ObjCBool = false
                        
                        if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory),
                           isDirectory.boolValue {
                            
                            // 快速创建项目（不收集Git信息）
                            let project = Project(
                                name: item,
                                path: itemPath,
                                lastModified: self.getModificationDate(itemPath),
                                tags: Set<String>() // 暂时不加载标签
                            )
                            discoveredProjects.append(project)
                        }
                    }
                } catch {
                    print("❌ 扫描目录失败: \(error)")
                }
                
                return discoveredProjects
            }
            
            var allProjects: [Project] = []
            for await projects in group {
                allProjects.append(contentsOf: projects)
            }
            return allProjects
        }
    }
    
    /// 扫描目录获取所有项目（完整版本，用于检测删除）
    private func scanDirectoryForAllProjects(_ directoryPath: String) async -> [Project] {
        return await withTaskGroup(of: [Project].self) { group in
            group.addTask {
                var discoveredProjects: [Project] = []
                
                do {
                    let fileManager = FileManager.default
                    let contents = try fileManager.contentsOfDirectory(atPath: directoryPath)
                    
                    for item in contents {
                        let itemPath = (directoryPath as NSString).appendingPathComponent(item)
                        var isDirectory: ObjCBool = false
                        
                        if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory),
                           isDirectory.boolValue {
                            
                            // 快速创建项目（不收集Git信息）
                            let project = Project(
                                name: item,
                                path: itemPath,
                                lastModified: self.getModificationDate(itemPath),
                                tags: Set<String>() // 暂时不加载标签
                            )
                            discoveredProjects.append(project)
                        }
                    }
                } catch {
                    print("❌ 扫描目录失败: \(error)")
                }
                
                return discoveredProjects
            }
            
            var allProjects: [Project] = []
            for await projects in group {
                allProjects.append(contentsOf: projects)
            }
            return allProjects
        }
    }
    
    /// 后台收集新项目的Git信息
    private func collectGitDataForNewProjects(_ newProjects: [Project]) async {
        print("📊 开始后台收集 \(newProjects.count) 个新项目的Git信息...")
        
        // 只为新项目收集Git数据
        let projectsWithGitData = GitDailyCollector.updateProjectsWithGitDaily(newProjects, days: 365)
        
        await MainActor.run {
            var updatedCount = 0
            for updatedProject in projectsWithGitData {
                if let _ = projects[updatedProject.id] {
                    projects[updatedProject.id] = updatedProject
                    sortManager.updateProject(updatedProject)
                    updatedCount += 1
                }
            }
            
            if updatedCount > 0 {
                projectOperations.saveAllToCache()
                print("✅ 后台更新完成，为 \(updatedCount) 个新项目收集了Git信息")
            }
        }
    }
    
    // MARK: - 刷新提示功能
    
    /// 当前显示的进度对话框引用
    private var currentProgressAlert: NSAlert?
    /// 自动关闭定时器
    private var autoCloseTimer: Timer?
    /// 进度更新定时器
    private var progressUpdateTimer: Timer?
    /// 当前进度值 (0.0 - 1.0)
    private var currentProgress: Double = 0.0
    /// 是否为进度状态（true）还是完成状态（false）
    private var isProgressState = true
    
    /// 创建进度条显示
    private func createProgressBar(_ progress: Double) -> String {
        let totalBars = 10
        let filledBars = Int(progress * Double(totalBars))
        // 尝试使用等宽字符组合
        let filledPart = String(repeating: "●", count: filledBars)
        let emptyPart = String(repeating: "○", count: totalBars - filledBars)
        let percentage = Int(progress * 100)
        return "\(filledPart)\(emptyPart) \(percentage)%"
    }
    
    /// 更新进度值并刷新显示
    private func updateProgress(_ progress: Double, directoryName: String, status: String) {
        currentProgress = progress
        let progressBar = createProgressBar(progress)
        let fullStatus = "\(status) \(progressBar)"
        updateRefreshAlert(directoryName: directoryName, status: fullStatus, isProgress: true)
    }
    
    /// 启动进度动画
    private func startProgressAnimation(directoryName: String, initialStatus: String) {
        currentProgress = 0.0
        updateProgress(0.1, directoryName: directoryName, status: initialStatus)
        
        // 启动定时器，每0.3秒更新一次进度
        progressUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 缓慢增加进度到30%（扫描阶段）
            if self.currentProgress < 0.3 {
                self.currentProgress += 0.05
                let progressBar = self.createProgressBar(self.currentProgress)
                let fullStatus = "\(initialStatus) \(progressBar)"
                self.updateRefreshAlert(directoryName: directoryName, status: fullStatus, isProgress: true)
            }
        }
    }
    
    /// 设置进度到特定值
    private func setProgress(_ progress: Double, directoryName: String, status: String) {
        // 停止自动进度动画
        progressUpdateTimer?.invalidate()
        progressUpdateTimer = nil
        
        // 直接设置进度
        updateProgress(progress, directoryName: directoryName, status: status)
    }
    
    /// 停止进度更新
    private func stopProgressUpdates() {
        progressUpdateTimer?.invalidate()
        progressUpdateTimer = nil
    }
    
    /// 显示或更新刷新对话框
    private func updateRefreshAlert(directoryName: String, status: String, isProgress: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let existingAlert = self.currentProgressAlert {
                // 更新现有对话框
                existingAlert.messageText = isProgress ? "刷新目录" : "刷新完成"
                existingAlert.informativeText = status
                
                // 更新按钮
                if !isProgress && self.isProgressState {
                    // 从进度状态切换到完成状态，更改按钮文本
                    existingAlert.buttons.first?.title = "确定"
                    self.isProgressState = false
                    
                    // 启动3秒自动关闭定时器
                    self.startAutoCloseTimer()
                }
            } else {
                // 创建新对话框
                self.createNewRefreshAlert(directoryName: directoryName, status: status, isProgress: isProgress)
            }
        }
    }
    
    /// 创建新的刷新对话框
    private func createNewRefreshAlert(directoryName: String, status: String, isProgress: Bool) {
        let alert = NSAlert()
        alert.messageText = isProgress ? "刷新目录" : "刷新完成"
        alert.informativeText = status
        alert.alertStyle = .informational
        alert.addButton(withTitle: isProgress ? "取消" : "确定")
        
        self.currentProgressAlert = alert
        self.isProgressState = isProgress
        
        // 在主线程上显示
        if let window = NSApp.mainWindow {
            alert.beginSheetModal(for: window) { [weak self] response in
                self?.handleAlertResponse(response, isProgress: isProgress)
            }
        } else {
            let response = alert.runModal()
            self.handleAlertResponse(response, isProgress: isProgress)
        }
        
        // 如果是完成状态，启动自动关闭定时器
        if !isProgress {
            self.startAutoCloseTimer()
        }
    }
    
    /// 处理对话框响应
    private func handleAlertResponse(_ response: NSApplication.ModalResponse, isProgress: Bool) {
        if response == .alertFirstButtonReturn {
            if isProgress {
                print("🚫 用户取消了刷新操作")
            } else {
                print("✅ 用户确认了刷新结果")
            }
        }
        self.cleanupAlert()
    }
    
    /// 启动3秒自动关闭定时器
    private func startAutoCloseTimer() {
        // 清除现有定时器
        autoCloseTimer?.invalidate()
        
        // 启动新的3秒定时器
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.dismissRefreshAlert()
            }
        }
    }
    
    /// 关闭刷新对话框
    private func dismissRefreshAlert() {
        DispatchQueue.main.async { [weak self] in
            if let alert = self?.currentProgressAlert {
                alert.window.orderOut(nil)
            }
            self?.cleanupAlert()
        }
    }
    
    /// 清理对话框相关资源
    private func cleanupAlert() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        progressUpdateTimer?.invalidate()
        progressUpdateTimer = nil
        currentProgressAlert = nil
        isProgressState = true
        currentProgress = 0.0
    }
    
    /// 显示刷新进度（兼容旧接口）
    private func showRefreshProgressAlert(directoryName: String, status: String) {
        updateRefreshAlert(directoryName: directoryName, status: status, isProgress: true)
    }
    
    /// 关闭进度对话框（兼容旧接口，现在改为更新状态）
    private func dismissRefreshProgressAlert() {
        // 不再关闭对话框，保留给最终结果使用
        // 这个方法现在变成空实现，保持向后兼容
    }
    
    /// 显示刷新成功提示（修改为更新现有对话框）
    private func showRefreshSuccessAlert(directoryName: String, addedCount: Int, syncedCount: Int, totalCount: Int) {
        var infoText = "当前项目：\(totalCount) 个"
        
        if addedCount > 0 {
            infoText += "\n✅ 新增：\(addedCount) 个"
        }
        if syncedCount > 0 {
            infoText += "\n🗑️ 已移除：\(syncedCount) 个"
        }
        if addedCount == 0 && syncedCount == 0 {
            infoText += "\n📝 无变化"
        }
        
        // 更新现有对话框为完成状态
        updateRefreshAlert(directoryName: directoryName, status: infoText, isProgress: false)
    }
    
    /// 显示刷新错误提示
    private func showRefreshErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "目录刷新失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        
        // 在主线程上显示
        DispatchQueue.main.async {
            alert.runModal()
        }
    }
}
