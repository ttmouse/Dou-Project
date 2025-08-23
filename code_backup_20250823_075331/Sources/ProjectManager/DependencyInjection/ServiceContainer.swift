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
        return TagManagerAdapter(
            core: tagManagerCore,
            operations: tagOperations,
            events: tagEventHandling
        )
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
    private let core: TagManagerCore
    private let operations: TagOperations  
    private let events: TagEventHandling
    private var cancellables = Set<AnyCancellable>()
    
    init(core: TagManagerCore, operations: TagOperations, events: TagEventHandling) {
        self.core = core
        self.operations = operations
        self.events = events
        
        // 转发核心对象的变化通知
        core.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - TagManager兼容接口
    
    // 基本数据访问
    var allTags: Set<String> { 
        get { core.allTags }
        set { core.allTags = newValue }
    }
    
    var projects: [UUID: Project] {
        get { core.projects }
        set { core.projects = newValue }
    }
    
    var watchedDirectories: Set<String> {
        get { core.watchedDirectories }
        set { core.watchedDirectories = newValue }
    }
    
    var selectedTag: String? {
        get { core.selectedTag }
        set { core.selectedTag = newValue }
    }
    
    // 方法转发
    func getColor(for tag: String) -> Color {
        return core.getColor(for: tag)
    }
    
    func setColor(_ color: Color, for tag: String) {
        core.setColor(color, for: tag)
    }
    
    func getUsageCount(for tag: String) -> Int {
        return core.getUsageCount(for: tag)
    }
    
    func invalidateTagUsageCache() {
        core.invalidateTagUsageCache()
    }
    
    func getSortedProjects() -> [Project] {
        return core.getSortedProjects()
    }
    
    func getFilteredProjects(withTags tags: Set<String>, searchText: String = "") -> [Project] {
        return core.getFilteredProjects(withTags: tags, searchText: searchText)
    }
    
    func setSortCriteria(_ criteria: TagManager.SortCriteria, ascending: Bool) {
        core.setSortCriteria(criteria, ascending: ascending)
    }
    
    // 标签操作转发到operations
    func addTag(_ tag: String, color: Color) {
        operations.addTag(tag, color: color)
    }
    
    func removeTag(_ tag: String) {
        operations.removeTag(tag)
    }
    
    func renameTag(_ oldName: String, to newName: String, color: Color) {
        operations.renameTag(oldName, to: newName, color: color)
    }
    
    func addTagToProject(projectId: UUID, tag: String) {
        operations.addTagToProject(projectId: projectId, tag: tag)
    }
    
    func removeTagFromProject(projectId: UUID, tag: String) {
        operations.removeTagFromProject(projectId: projectId, tag: tag)
    }
    
    func addTagToProjects(projectIds: Set<UUID>, tag: String) {
        operations.addTagToProjects(projectIds: projectIds, tag: tag)
    }
    
    // 项目和目录管理
    func registerProject(_ project: Project) {
        core.registerProject(project)
    }
    
    func removeProject(_ id: UUID) {
        core.removeProject(id)
    }
    
    func addWatchedDirectory(_ path: String) {
        core.addWatchedDirectory(path)
    }
    
    func removeWatchedDirectory(_ path: String) {
        core.removeWatchedDirectory(path)
    }
    
    func reloadProjects() {
        core.reloadProjects()
    }
    
    func clearCacheAndReloadProjects() {
        core.clearCacheAndReloadProjects()
    }
    
    func saveAll(force: Bool = false) {
        core.saveAll(force: force)
    }
}