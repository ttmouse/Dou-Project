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
        // 暂时使用原始的TagManager直到新架构完全实现
        return TagManagerAdapter(originalTagManager: TagManager())
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
    private let tagManager: TagManager
    private var cancellables = Set<AnyCancellable>()
    
    // 新构造器：直接使用原始TagManager
    init(originalTagManager: TagManager) {
        self.tagManager = originalTagManager
        
        // 转发TagManager的变化通知
        tagManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // 保留旧构造器以防兼容性问题 (废弃)
    init(core: TagManagerCore, operations: TagOperations, events: TagEventHandling) {
        // 创建一个新的TagManager实例作为后备方案
        self.tagManager = TagManager()
        
        // 转发变化通知
        tagManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - TagManager兼容接口
    
    // 色彩管理器适配
    var colorManager: TagColorManagerAdapter {
        return TagColorManagerAdapter(tagManager: tagManager)
    }
    
    // 基本数据访问
    var allTags: Set<String> { 
        get { tagManager.allTags }
        set { tagManager.allTags = newValue }
    }
    
    var projects: [UUID: Project] {
        get { tagManager.projects }
        set { tagManager.projects = newValue }
    }
    
    var watchedDirectories: Set<String> {
        get { tagManager.watchedDirectories }
        set { tagManager.watchedDirectories = newValue }
    }
    
    var selectedTag: String? {
        get { tagManager.selectedTag }
        set { tagManager.selectedTag = newValue }
    }
    
    // 方法转发
    func getColor(for tag: String) -> Color {
        return tagManager.getColor(for: tag)
    }
    
    func setColor(_ color: Color, for tag: String) {
        tagManager.setColor(color, for: tag)
    }
    
    func getUsageCount(for tag: String) -> Int {
        return tagManager.getUsageCount(for: tag)
    }
    
    func invalidateTagUsageCache() {
        tagManager.invalidateTagUsageCache()
    }
    
    func getSortedProjects() -> [Project] {
        return tagManager.getSortedProjects()
    }
    
    func getFilteredProjects(withTags tags: Set<String>, searchText: String = "") -> [Project] {
        return tagManager.getFilteredProjects(withTags: tags, searchText: searchText)
    }
    
    func setSortCriteria(_ criteria: TagManager.SortCriteria, ascending: Bool) {
        tagManager.setSortCriteria(criteria, ascending: ascending)
    }
    
    // 标签操作
    func addTag(_ tag: String, color: Color) {
        tagManager.addTag(tag, color: color)
    }
    
    func removeTag(_ tag: String) {
        tagManager.removeTag(tag)
    }
    
    func renameTag(_ oldName: String, to newName: String, color: Color) {
        tagManager.renameTag(oldName, to: newName, color: color)
    }
    
    func addTagToProject(projectId: UUID, tag: String) {
        tagManager.addTagToProject(projectId: projectId, tag: tag)
    }
    
    func removeTagFromProject(projectId: UUID, tag: String) {
        tagManager.removeTagFromProject(projectId: projectId, tag: tag)
    }
    
    func addTagToProjects(projectIds: Set<UUID>, tag: String) {
        tagManager.addTagToProjects(projectIds: projectIds, tag: tag)
    }
    
    // 标签隐藏功能
    func toggleTagVisibility(_ tag: String) {
        tagManager.toggleTagVisibility(tag)
    }
    
    func isTagHidden(_ tag: String) -> Bool {
        return tagManager.isTagHidden(tag)
    }
    
    var hiddenTags: Set<String> {
        get { tagManager.hiddenTags }
        set { tagManager.hiddenTags = newValue }
    }
    
    // 项目和目录管理
    func registerProject(_ project: Project) {
        tagManager.registerProject(project)
    }
    
    func removeProject(_ id: UUID) {
        tagManager.removeProject(id)
    }
    
    func addWatchedDirectory(_ path: String) {
        tagManager.addWatchedDirectory(path)
    }
    
    func removeWatchedDirectory(_ path: String) {
        tagManager.removeWatchedDirectory(path)
    }
    
    func reloadProjects() {
        tagManager.reloadProjects()
    }
    
    func clearCacheAndReloadProjects() {
        tagManager.clearCacheAndReloadProjects()
    }
    
    func saveAll(force: Bool = false) {
        tagManager.saveAll(force: force)
    }
    
    /// 增量更新项目列表 - 不会清空现有项目，只在后台检查变化
    func incrementalRefreshProjects() {
        // 检查是否启用了自动增量更新
        if tagManager.enableAutoIncrementalUpdate {
            tagManager.directoryWatcher.incrementallyReloadProjects()
        } else {
            print("自动增量更新已关闭")
        }
    }
    
    /// 手动触发增量更新 - 忽略自动更新设置
    func manualIncrementalRefresh() {
        print("手动触发增量更新")
        tagManager.directoryWatcher.incrementallyReloadProjects()
    }
    
    /// 导入数据的公共接口
    func importData(
        from fileURL: URL,
        strategy: DataImporter.ImportStrategy = .merge,
        conflictResolution: DataImporter.ConflictResolution = .mergeData
    ) -> DataImporter.ImportResult {
        return tagManager.importData(
            from: fileURL,
            strategy: strategy,
            conflictResolution: conflictResolution
        )
    }
}

// MARK: - TagColorManager适配器

/// TagColorManagerAdapter - 色彩管理器的适配器
class TagColorManagerAdapter {
    private let tagManager: TagManager
    
    init(tagManager: TagManager) {
        self.tagManager = tagManager
    }
    
    func getColor(for tag: String) -> Color? {
        return tagManager.colorManager.getColor(for: tag)
    }
    
    func setColor(_ color: Color, for tag: String) {
        tagManager.colorManager.setColor(color, for: tag)
    }
}