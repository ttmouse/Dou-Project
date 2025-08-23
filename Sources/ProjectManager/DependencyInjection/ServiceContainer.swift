import SwiftUI
import Combine

/// ServiceContainer - Linus式依赖注入容器
/// 
/// 这个容器负责管理所有应用级依赖，彻底消除单例癌症
/// 
/// 核心原则：
/// 1. 所有依赖都通过构造器注入
/// 2. 容器本身是有作用域的（不是全局单例）
/// 3. 支持懒加载以避免循环依赖
/// 4. 可测试 - 容器可以被替换为测试版本
class ServiceContainer: ObservableObject {
    
    // MARK: - Core Services
    private var _tagManagerCore: TagManagerCore?
    private var _tagOperations: TagOperations?
    private var _tagEventHandling: TagEventHandling?
    private var _selectAllHandler: SelectAllHandler?
    
    // MARK: - Service Access
    
    var tagManagerCore: TagManagerCore {
        if let existing = _tagManagerCore {
            return existing
        }
        
        let core = TagManagerCore()
        _tagManagerCore = core
        
        // 初始化依赖的其他服务
        _ = tagOperations // 触发懒加载
        _ = tagEventHandling // 触发懒加载
        
        return core
    }
    
    var tagOperations: TagOperations {
        if let existing = _tagOperations {
            return existing
        }
        
        let operations = TagOperations(core: tagManagerCore)
        _tagOperations = operations
        return operations
    }
    
    var tagEventHandling: TagEventHandling {
        if let existing = _tagEventHandling {
            return existing
        }
        
        let events = TagEventHandling(core: tagManagerCore)
        _tagEventHandling = events
        return events
    }
    
    func createSelectAllHandler(action: @escaping () -> Void) -> SelectAllHandler {
        if let existing = _selectAllHandler {
            return existing
        }
        
        let handler = SelectAllHandler(action: action)
        _selectAllHandler = handler
        return handler
    }
    
    // MARK: - 旧接口兼容层
    
    /// 创建兼容TagManager接口的适配器
    /// 这允许现有代码逐步迁移，而不是一次性破坏所有东西
    func createTagManagerAdapter() -> TagManagerAdapter {
        // 使用新的模块化TagManager
        return TagManagerAdapter(modularTagManager: TagManagerModular())
    }
    
    // MARK: - 测试支持
    
    /// 用于测试的构造器，允许注入mock对象
    init(
        tagManagerCore: TagManagerCore? = nil,
        tagOperations: TagOperations? = nil,
        tagEventHandling: TagEventHandling? = nil,
        selectAllHandler: SelectAllHandler? = nil
    ) {
        self._tagManagerCore = tagManagerCore
        self._tagOperations = tagOperations
        self._tagEventHandling = tagEventHandling
        self._selectAllHandler = selectAllHandler
    }
    
    // MARK: - 清理
    
    deinit {
        print("ServiceContainer: 清理依赖注入容器")
    }
}

// MARK: - TagManager适配器

/// TagManagerAdapter - 让新架构兼容旧的TagManager接口
/// 
/// 这个适配器模式让我们可以：
/// 1. 保持旧代码工作
/// 2. 逐步迁移到新架构
/// 3. 避免大爆炸式重写
class TagManagerAdapter: ObservableObject {
    private let tagManager: TagManager?
    private let modularTagManager: TagManagerModular?
    private var cancellables = Set<AnyCancellable>()
    
    // 新构造器：使用模块化TagManager
    init(modularTagManager: TagManagerModular) {
        self.modularTagManager = modularTagManager
        self.tagManager = nil
        
        // 转发模块化TagManager的变化通知
        modularTagManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // 旧构造器：直接使用原始TagManager（向后兼容）
    init(originalTagManager: TagManager) {
        self.tagManager = originalTagManager
        self.modularTagManager = nil
        
        // 转发TagManager的变化通知
        originalTagManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // 保留旧构造器以防兼容性问题 (废弃)
    init(core: TagManagerCore, operations: TagOperations, events: TagEventHandling) {
        // 创建一个新的TagManager实例作为后备方案
        let fallbackManager = TagManager()
        self.tagManager = fallbackManager
        self.modularTagManager = nil
        
        // 转发变化通知
        fallbackManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - TagManager兼容接口
    
    // 色彩管理器适配
    var colorManager: TagColorManagerAdapter {
        if let modular = modularTagManager {
            return TagColorManagerAdapter(modularTagManager: modular)
        } else if let original = tagManager {
            return TagColorManagerAdapter(tagManager: original)
        } else {
            fatalError("No TagManager available")
        }
    }
    
    // 基本数据访问
    var allTags: Set<String> { 
        get { 
            if let modular = modularTagManager {
                return modular.allTags
            } else if let original = tagManager {
                return original.allTags
            } else {
                return []
            }
        }
        set { 
            if let modular = modularTagManager {
                modular.allTags = newValue
            } else if let original = tagManager {
                original.allTags = newValue
            }
        }
    }
    
    var projects: [UUID: Project] {
        get { 
            if let modular = modularTagManager {
                return modular.projects
            } else if let original = tagManager {
                return original.projects
            } else {
                return [:]
            }
        }
        set { 
            if let modular = modularTagManager {
                modular.projects = newValue
            } else if let original = tagManager {
                original.projects = newValue
            }
        }
    }
    
    var watchedDirectories: Set<String> {
        get { 
            if let modular = modularTagManager {
                return modular.watchedDirectories
            } else if let original = tagManager {
                return original.watchedDirectories
            } else {
                return []
            }
        }
        set { 
            if let modular = modularTagManager {
                modular.watchedDirectories = newValue
            } else if let original = tagManager {
                original.watchedDirectories = newValue
            }
        }
    }
    
    var selectedTag: String? {
        get { 
            if let modular = modularTagManager {
                return modular.selectedTag
            } else if let original = tagManager {
                return original.selectedTag
            } else {
                return nil
            }
        }
        set { 
            if let modular = modularTagManager {
                modular.selectedTag = newValue
            } else if let original = tagManager {
                original.selectedTag = newValue
            }
        }
    }
    
    // 方法转发
    func getColor(for tag: String) -> Color {
        if let modular = modularTagManager {
            return modular.getColor(for: tag)
        } else if let original = tagManager {
            return original.getColor(for: tag)
        } else {
            return AppTheme.accent
        }
    }
    
    func setColor(_ color: Color, for tag: String) {
        if let modular = modularTagManager {
            modular.setColor(color, for: tag)
        } else if let original = tagManager {
            original.setColor(color, for: tag)
        }
    }
    
    func getUsageCount(for tag: String) -> Int {
        if let modular = modularTagManager {
            return modular.getUsageCount(for: tag)
        } else if let original = tagManager {
            return original.getUsageCount(for: tag)
        } else {
            return 0
        }
    }
    
    func invalidateTagUsageCache() {
        if let modular = modularTagManager {
            modular.invalidateTagUsageCache()
        } else if let original = tagManager {
            original.invalidateTagUsageCache()
        }
    }
    
    func getSortedProjects() -> [Project] {
        if let modular = modularTagManager {
            return modular.getSortedProjects()
        } else if let original = tagManager {
            return original.getSortedProjects()
        } else {
            return []
        }
    }
    
    func getFilteredProjects(withTags tags: Set<String>, searchText: String = "") -> [Project] {
        if let modular = modularTagManager {
            return modular.getFilteredProjects(withTags: tags, searchText: searchText)
        } else if let original = tagManager {
            return original.getFilteredProjects(withTags: tags, searchText: searchText)
        } else {
            return []
        }
    }
    
    func setSortCriteria(_ criteria: TagManager.SortCriteria, ascending: Bool) {
        if let modular = modularTagManager {
            let modularCriteria: TagManagerModular.SortCriteria
            switch criteria {
            case .name:
                modularCriteria = .name
            case .lastModified:
                modularCriteria = .lastModified
            case .gitCommits:
                modularCriteria = .gitCommits
            }
            modular.setSortCriteria(modularCriteria, ascending: ascending)
        } else if let original = tagManager {
            original.setSortCriteria(criteria, ascending: ascending)
        }
    }
    
    // 标签操作
    func addTag(_ tag: String, color: Color) {
        if let modular = modularTagManager {
            modular.addTag(tag, color: color)
        } else if let original = tagManager {
            original.addTag(tag, color: color)
        }
    }
    
    func removeTag(_ tag: String) {
        if let modular = modularTagManager {
            modular.removeTag(tag)
        } else if let original = tagManager {
            original.removeTag(tag)
        }
    }
    
    func renameTag(_ oldName: String, to newName: String, color: Color) {
        if let modular = modularTagManager {
            modular.renameTag(oldName, to: newName, color: color)
        } else if let original = tagManager {
            original.renameTag(oldName, to: newName, color: color)
        }
    }
    
    func addTagToProject(projectId: UUID, tag: String) {
        if let modular = modularTagManager {
            modular.addTagToProject(projectId: projectId, tag: tag)
        } else if let original = tagManager {
            original.addTagToProject(projectId: projectId, tag: tag)
        }
    }
    
    func removeTagFromProject(projectId: UUID, tag: String) {
        if let modular = modularTagManager {
            modular.removeTagFromProject(projectId: projectId, tag: tag)
        } else if let original = tagManager {
            original.removeTagFromProject(projectId: projectId, tag: tag)
        }
    }
    
    func addTagToProjects(projectIds: Set<UUID>, tag: String) {
        if let modular = modularTagManager {
            modular.addTagToProjects(projectIds: projectIds, tag: tag)
        } else if let original = tagManager {
            original.addTagToProjects(projectIds: projectIds, tag: tag)
        }
    }
    
    // 标签隐藏功能
    func toggleTagVisibility(_ tag: String) {
        if let modular = modularTagManager {
            modular.toggleTagVisibility(tag)
        } else if let original = tagManager {
            original.toggleTagVisibility(tag)
        }
    }
    
    func isTagHidden(_ tag: String) -> Bool {
        if let modular = modularTagManager {
            return modular.isTagHidden(tag)
        } else if let original = tagManager {
            return original.isTagHidden(tag)
        } else {
            return false
        }
    }
    
    var hiddenTags: Set<String> {
        get { 
            if let modular = modularTagManager {
                return modular.hiddenTags
            } else if let original = tagManager {
                return original.hiddenTags
            } else {
                return []
            }
        }
        set { 
            if let modular = modularTagManager {
                modular.hiddenTags = newValue
            } else if let original = tagManager {
                original.hiddenTags = newValue
            }
        }
    }
    
    // 项目和目录管理
    func registerProject(_ project: Project) {
        if let modular = modularTagManager {
            modular.registerProject(project)
        } else if let original = tagManager {
            original.registerProject(project)
        }
    }
    
    func removeProject(_ id: UUID) {
        if let modular = modularTagManager {
            modular.removeProject(id)
        } else if let original = tagManager {
            original.removeProject(id)
        }
    }
    
    func addWatchedDirectory(_ path: String) {
        if let modular = modularTagManager {
            modular.addWatchedDirectory(path)
        } else if let original = tagManager {
            original.addWatchedDirectory(path)
        }
    }
    
    func removeWatchedDirectory(_ path: String) {
        if let modular = modularTagManager {
            modular.removeWatchedDirectory(path)
        } else if let original = tagManager {
            original.removeWatchedDirectory(path)
        }
    }
    
    func reloadProjects() {
        if let modular = modularTagManager {
            modular.reloadProjects()
        } else if let original = tagManager {
            original.reloadProjects()
        }
    }
    
    func clearCacheAndReloadProjects() {
        if let modular = modularTagManager {
            modular.clearCacheAndReloadProjects()
        } else if let original = tagManager {
            original.clearCacheAndReloadProjects()
        }
    }
    
    func saveAll(force: Bool = false) {
        if let modular = modularTagManager {
            modular.saveAll(force: force)
        } else if let original = tagManager {
            original.saveAll(force: force)
        }
    }
    
    /// 增量更新项目列表 - 不会清空现有项目，只在后台检查变化
    func incrementalRefreshProjects() {
        if let modular = modularTagManager {
            modular.manualIncrementalUpdate()
        } else if let original = tagManager {
            // 检查是否启用了自动增量更新
            if original.enableAutoIncrementalUpdate {
                original.directoryWatcher.incrementallyReloadProjects()
            } else {
                print("自动增量更新已关闭")
            }
        }
    }
    
    /// 手动触发增量更新 - 忽略自动更新设置
    func manualIncrementalRefresh() {
        print("手动触发增量更新")
        if let modular = modularTagManager {
            modular.manualIncrementalUpdate()
        } else if let original = tagManager {
            original.directoryWatcher.incrementallyReloadProjects()
        }
    }
    
    /// 导入数据的公共接口
    func importData(
        from fileURL: URL,
        strategy: String = "merge",
        conflictResolution: String = "mergeData"
    ) -> String {
        if let modular = modularTagManager {
            return modular.importData(
                from: fileURL,
                strategy: strategy,
                conflictResolution: conflictResolution
            )
        } else if let original = tagManager {
            return original.importData(
                from: fileURL,
                strategy: strategy,
                conflictResolution: conflictResolution
            )
        } else {
            return "未实现"
        }
    }
}

// MARK: - TagColorManager适配器

/// TagColorManagerAdapter - 色彩管理器的适配器
class TagColorManagerAdapter {
    private let tagManager: TagManager?
    private let modularTagManager: TagManagerModular?
    
    init(modularTagManager: TagManagerModular) {
        self.modularTagManager = modularTagManager
        self.tagManager = nil
    }
    
    init(tagManager: TagManager) {
        self.tagManager = tagManager
        self.modularTagManager = nil
    }
    
    func getColor(for tag: String) -> Color? {
        if let modular = modularTagManager {
            return modular.getColor(for: tag)
        } else if let original = tagManager {
            return original.colorManager.getColor(for: tag)
        } else {
            return nil
        }
    }
    
    func setColor(_ color: Color, for tag: String) {
        if let modular = modularTagManager {
            modular.setColor(color, for: tag)
        } else if let original = tagManager {
            original.colorManager.setColor(color, for: tag)
        }
    }
}