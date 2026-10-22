import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine

enum ProjectScanState: Equatable {
    case idle
    case scanning(directory: String)
    case completed(directory: String, discovered: Int)
    case failed(directory: String, message: String)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }

    var directory: String? {
        switch self {
        case .idle:
            return nil
        case .scanning(let directory), .completed(let directory, _), .failed(let directory, _):
            return directory
        }
    }
}

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
    private(set) var isApplyingGitDaily = false
    let gitDailyChanges = PassthroughSubject<[UUID: Project], Never>()
    @Published var watchedDirectories: Set<String> = []
    @Published private(set) var scanState: ProjectScanState = .idle
    private var scanStatusResetWorkItem: DispatchWorkItem?
    
    // 增量更新控制
    @Published var enableAutoIncrementalUpdate: Bool = false
    
    // 标签隐藏状态管理
    @Published var hiddenTags: Set<String> = []
    
    // 状态指示
    @Published var isRunningTaggingRules: Bool = false
    @Published var lastTaggingRuleMessage: String? = nil

    /// 倒排索引：标签 -> 项目ID集合 (O(1) 检索受影响项目)
    private var tagToProjectMap: [String: Set<UUID>] = [:]
    
    /// I/O 专用串行队列，确保磁盘操作不阻塞 UI。
    /// 不用 `.background`：最低 QoS 在系统繁忙时会被无限推迟，保存就变成
    /// 「调用了但没写盘」，与本卡要修掉的静默丢保存是同一类缺陷。
    private let ioQueue = DispatchQueue(label: "com.projectmanager.tagmanager.io", qos: .utility)
    /// 标记 ioQueue：flush 从 I/O 队列内部调用时不能再 sync，否则自锁。
    private let ioQueueKey = DispatchSpecificKey<Void>()

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
        ioQueue.setSpecific(key: ioQueueKey, value: ())

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

    /// 测试/隔离用：把所有存储指到同一个临时目录。
    ///
    /// 生产组合根会读写真实用户目录、并开始监视用户目录，测试不该构造它。
    /// 这条入口只换存储位置，仍然走同一套加载与保存链路，
    /// 因此「临时目录被删之后保存怎么收场」可以在不碰真实数据的前提下验证。
    init(storageDirectory: URL, startMonitoring: Bool = false) {
        ioQueue.setSpecific(key: ioQueueKey, value: ())
        unifiedStorage = AppStateStorage(appSupportURL: storageDirectory)
        storage = TagStorage(appSupportURL: storageDirectory)
        colorManager = TagColorManager(storage: storage)
        sortManager = ProjectSortManager()
        projectIndex = ProjectIndex(storage: storage)

        colorManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        loadAllData(startMonitoring: startMonitoring)
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

    private func loadAllData(startMonitoring: Bool = true) {
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
        if startMonitoring {
            directoryWatcher.startMonitoring(paths: watchedDirectories)
        }

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

        // 7. 启动后自动增量扫描监视目录（延迟 1.5s，避免阻塞首屏）
        // 背景：仅从缓存恢复项目时，缓存缺失的目录会显示 0 个项目，
        // 必须手动刷新才出现。此处自动补齐磁盘上的新增/缺失项目。
        guard startMonitoring else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            print("🔄 启动自动增量扫描...")
            self.directoryWatcher.incrementallyReloadProjects()
        }
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
            let projects = try decoder.decode([Project].self, from: data).filter {
                ProjectDiscoveryPolicy.isEligibleProjectPath($0.path)
            }
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
        // 症状：loadProjects 会对每个项目跑 git（rev-list/log）并算 SHA256 校验，
        // 而本方法由通知回调（Cmd+Shift+T）在主线程触发 → 几百个项目时界面冻住。
        // 这里把扫描/加载放到 I/O 队列，回到主线程只做内存合并（registerProjects 已不采 git）。
        ioQueue.async { [weak self] in
            guard let self = self else { return }

            let loadedProjects = self.projectIndex.loadProjects(existingProjects: existingProjects)

            DispatchQueue.main.async {
                // 批量注册新项目（Project初始化时已经处理了系统标签）
                self.projectOperations.registerProjects(loadedProjects)

                print("完成重新加载，现有 \(self.projects.count) 个项目")
            }
        }
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
                    Log.debug("  自动打标进度: \(index + 1)/\(total)")
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
            activityAt: project.activityAt,
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
    private let saveDebouncer = DebouncedWorkScheduler(
        label: "com.projectmanager.app-state-debounce"
    )
    /// 保存观测（失败原因 / 尝试次数）。写盘在 I/O 队列、发布在主队列，
    /// 读写都过这把锁，避免计数器与失败记录出现撕裂读。
    private let saveStateLock = NSLock()
    private var storedLastSaveError: LocalPersistenceError?
    private var storedSaveAttemptCount = 0

    /// 最近一次「保存全部」的失败原因；成功后清空。
    /// `performSave` 里各种失败原本只打到控制台，调用方无法判断数据是否真的落地。
    var lastSaveError: LocalPersistenceError? {
        saveStateLock.lock()
        defer { saveStateLock.unlock() }
        return storedLastSaveError
    }

    /// 已经开始的保存次数（含失败）。用于确认防抖任务真的被唤醒过，
    /// 而不是只看「有没有调度出去」。
    var saveAttemptCount: Int {
        saveStateLock.lock()
        defer { saveStateLock.unlock() }
        return storedSaveAttemptCount
    }

    func saveAll(force: Bool = false) {
        // 如果强制保存，立即执行
        if force {
            saveDebouncer.cancel()
            performSave()
            return
        }

        // 合并去抖：每次调用都重置待写窗口，静默 1 秒后只保存一次。
        // 用不依赖 RunLoop 的调度器：该方法也可能从后台队列（扫描、Git 回填）调用，
        // Timer 挂不到没有 RunLoop 的线程上，保存会被静默丢掉。
        saveDebouncer.schedule(after: 1.0) { [weak self] in
            self?.performSave()
        }
    }

    /// 丢弃尚未触发的防抖保存。应用退出/测试收尾时使用。
    func cancelPendingSave() {
        saveDebouncer.cancel()
        projectOperations.cancelPendingSave()
    }

    /// 等已经排进 I/O 队列的写盘跑完（不再触发新的写入）。
    /// 退出前和测试收尾用：先排空在途写盘再删目录，避免留下竞态噪声。
    func drainPendingWrites() {
        projectOperations.drainPendingWrites()
        guard DispatchQueue.getSpecific(key: ioQueueKey) == nil else { return }
        ioQueue.sync {}
    }

    /// 立即写出当前快照并返回结果（跳过防抖等待）。
    /// 退出前需要「确定落盘」，测试也需要一个不依赖计时的确定性入口。
    @discardableResult
    func flushPendingSave() -> Result<Void, LocalPersistenceError> {
        saveDebouncer.cancel()
        let snapshot = makeSaveSnapshot()

        let failure: LocalPersistenceError?
        if DispatchQueue.getSpecific(key: ioQueueKey) != nil {
            // 已经在 I/O 队列里：直接写，避免 ioQueue.sync 自锁。
            failure = writeAll(snapshot)
        } else {
            var written: LocalPersistenceError?
            ioQueue.sync { written = writeAll(snapshot) }
            failure = written
        }

        recordSaveResult(failure)
        return failure.map { .failure($0) } ?? .success(())
    }

    private struct SaveSnapshot {
        let tags: Set<String>
        let hiddenTags: Set<String>
        let directories: Set<String>
        let projects: [Project]
    }

    private func makeSaveSnapshot() -> SaveSnapshot {
        SaveSnapshot(
            tags: allTags,
            hiddenTags: hiddenTags,
            directories: watchedDirectories,
            projects: Array(projects.values)
        )
    }

    private func recordSaveResult(_ failure: LocalPersistenceError?) {
        saveStateLock.lock()
        storedSaveAttemptCount += 1
        storedLastSaveError = failure
        saveStateLock.unlock()
        needsSave = false
    }

    private func performSave() {
        let snapshot = makeSaveSnapshot()

        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let failure = self.writeAll(snapshot)
            // 观测结果在 I/O 队列上就地记录（有锁保护），这样 drain 之后
            // 计数与失败原因一定已经落定，不必再等一次主队列回合。
            self.recordSaveResult(failure)

            DispatchQueue.main.async {
                self.needsSave = false
                if let failure = failure {
                    Log.error("保存全部数据时部分内容未落盘: \(failure.localizedDescription)")
                } else {
                    Log.debug("所有数据已成功后台同步至磁盘")
                }
            }
        }
    }

    /// 实际写盘。失败只返回原因，不抛出、不重建目录。
    private func writeAll(_ snapshot: SaveSnapshot) -> LocalPersistenceError? {
        // 1. 构建统一的标签数据
        var tagDataArray: [AppStateStorage.TagData] = []
        for tag in snapshot.tags {
            let color = colorManager.getColor(for: tag) ?? Color.gray
            let hidden = snapshot.hiddenTags.contains(tag)
            tagDataArray.append(AppStateStorage.TagData(name: tag, color: color, hidden: hidden))
        }

        // 2. 保存到统一存储
        let appStateFile = AppStateStorage.AppStateFile(
            version: 2,
            tags: tagDataArray,
            directories: Array(snapshot.directories)
        )
        let stateResult = unifiedStorage.saveReportingResult(appStateFile)

        // 3. 保存项目数据（暂时保留独立文件）
        let projectsResult = storage.saveProjectsReportingResult(snapshot.projects)

        // 4. 同步到系统标签
        // 目标目录消失只影响缓存镜像：项目标签写的是各个项目自己的路径，
        // 与缓存目录无关，因此这里照常执行，不当成整体失败。
        TagSystemSync.syncTagsToSystem(snapshot.tags)
        for project in snapshot.projects {
            project.saveTagsToSystem()
        }

        switch (stateResult, projectsResult) {
        case (.failure(let error), _):
            return error
        case (_, .failure(let error)):
            return error
        case (.success, .success):
            return nil
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

    // MARK: - 目录归属（参照 GitHub 仓库计数：互斥归属，计数即结果）

    /// 互斥归属解析：每个项目归入**最深的匹配监视目录**，无匹配进未分类
    /// 保证 Σ目录计数 + 未分类 == "全部"计数，侧边栏与列表筛选共用同一套逻辑
    func directoryAssignment() -> DirectoryLogic.Assignment {
        let paths = projects.values.map { $0.path }
        return DirectoryLogic.assign(paths: paths, directories: Array(watchedDirectories))
    }

    /// 判断项目是否位于某监视目录下（组件边界匹配，不再是 hasPrefix 子串误匹配）
    func isProject(_ project: Project, in directory: String) -> Bool {
        DirectoryLogic.isSubpath(project.path, of: directory)
    }

    /// 某目录下的全部项目（与侧边栏徽章计数使用同一逻辑，保证计数 == 结果）
    func projects(in directory: String) -> [Project] {
        projects.values.filter { DirectoryLogic.isSubpath($0.path, of: directory) }
    }

    /// 未归属任何监视目录的项目（手动添加等）
    func unassignedProjects() -> [Project] {
        let unassignedPaths = directoryAssignment().unassigned
        return projects.values.filter { unassignedPaths.contains(DirectoryLogic.standardizedPath($0.path)) }
    }

    /// 某目录下项目数（侧边栏徽章专用）
    func projectCount(in directory: String) -> Int {
        projects(in: directory).count
    }

    // MARK: - Linus式简化刷新 - 新的智能刷新方法
    
    /// 安全的智能项目刷新：交给后台目录监视器执行，避免阻塞主线程。
    func refreshProjects() {
        print("🔄 开始安全智能刷新...")
        directoryWatcher.incrementallyReloadProjects()

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
        updateAllProjectsGitDaily(days: 365)
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

    /// 批次快照发布：一次写入整批变更。
    ///
    /// `@Published var projects` 的每次赋值都会复制字典并同步通知观察者；文件事件
    /// 一批命中多个项目时，逐项赋值会让列表按项目数重复收到通知、重复重建索引。
    /// 这里只赋值一次，内容与当前状态相同的批次直接返回 0，完全不发布。
    @discardableResult
    func applyProjectBatch(_ change: ProjectBatchChange) -> Int {
        var snapshot = projects
        let changed = ProjectBatchMerge.apply(into: &snapshot, change: change)
        guard changed > 0 else { return 0 }

        // 仅活动时间等元数据变化不重建标签索引，避免整表扫描。
        if change.affectsTags || !change.removals.isEmpty {
            ProjectTagIndexLogic.apply(to: &tagToProjectMap, change: change, previous: projects)
        }

        // @Published 同步发送；这里只发一次。
        projects = snapshot
        return changed
    }

    func applyGitDailyUpdates(_ updates: [UUID: Project]) {
        var snapshot = projects
        for (id, project) in updates { snapshot[id] = project }
        // @Published 同步发送；列表对这种仅历史字段变化使用独立的轻量更新。
        isApplyingGitDaily = true
        projects = snapshot
        isApplyingGitDaily = false
        gitDailyChanges.send(updates)
    }
    
    // Linus式简化：不需要复杂的缓存失效逻辑，BusinessLogic会处理
    func invalidateTagUsageCache() {
        // 在新架构中，标签统计通过纯函数实时计算，无需缓存失效
    }
    
    // MARK: - DirectoryWatcherDelegate 实现

    func scanDidStart(directory: String) {
        scanStatusResetWorkItem?.cancel()
        scanState = .scanning(directory: directory)
    }

    func scanDidFinish(directory: String, discovered: Int) {
        let completedState = ProjectScanState.completed(directory: directory, discovered: discovered)
        scanState = completedState

        let resetWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.scanState == completedState else { return }
            self.scanState = .idle
        }
        scanStatusResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: resetWorkItem)
    }

    func scanDidFail(directory: String, message: String) {
        scanState = .failed(directory: directory, message: message)
    }
    
    // MARK: - Git Daily 数据收集功能
    
    /// 更新所有项目的git_daily数据
    func updateAllProjectsGitDaily(days: Int = 90) {
        // 先在主线程取快照，避免后台读取正在被 UI 修改的字典。
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.projectOperations.refreshGitDailyInBackground(for: Array(self.projects.values), days: days)
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
                    scanDidFail(directory: directoryPath, message: "目录不存在或未被监视")
                }
                return
            }

            // 非阻断状态反馈：用户可以继续使用主界面
            await MainActor.run {
                scanDidStart(directory: directoryPath)
            }
            
            // 获取该目录下现有的所有项目
            let existingProjectsInDir = projects.values.filter { DirectoryLogic.isSubpath($0.path, of: directoryPath) }
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
                // 处理删除的项目
                for deletedPath in deletedProjectPaths {
                    if let project = projects.values.first(where: { $0.path == deletedPath }) {
                        projects.removeValue(forKey: project.id)
                        sortManager.removeProject(project)
                        Log.debug("🗑️ 删除不存在的项目: \(project.name)")
                    }
                }
                
                // 添加新项目
                var updatedProjects = projects
                var updatedTags = allTags
                
                for newProject in newProjects {
                    updatedProjects[newProject.id] = newProject
                    updatedTags.formUnion(newProject.tags)
                    sortManager.insertProject(newProject)
                    Log.debug("➕ 添加新项目: \(newProject.name)")
                }
                
                // 更新数据
                projects = updatedProjects
                allTags = updatedTags
                
                // 使标签统计缓存失效
                invalidateTagUsageCache()
                
                // 保存缓存
                projectOperations.saveAllToCache()
                
                scanDidFinish(directory: directoryPath, discovered: discoveredProjects.count)

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
                        guard ProjectDiscoveryPolicy.isEligibleChildDirectory(named: item) else {
                            continue
                        }

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
                        guard ProjectDiscoveryPolicy.isEligibleChildDirectory(named: item) else {
                            continue
                        }

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
        await MainActor.run {
            projectOperations.refreshGitDailyInBackground(for: newProjects)
        }
    }
    
    // MARK: - 刷新提示功能

    deinit {
        // 对象销毁后不应该再由防抖任务写盘：目录可能已经不在了。
        // 子组件（ProjectOperationManager）自己的 deinit 会取消它那条待写任务。
        saveDebouncer.cancel()
    }
}
