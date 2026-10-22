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

    /// Git 每日历史不改变任何排序键，直接替换原位置即可。
    func updateProjectMetadata(_ projects: [Project]) {
        let updates = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        for index in sortedProjects.indices {
            if let updated = updates[sortedProjects[index].id] {
                sortedProjects[index] = updated
            }
        }
    }

    /// 批次更新排序键（活动时间等）：先按 id 建一次索引，避免每项都线性查找，
    /// 全部替换完只做一次整体重排。
    func updateProjectsMetadata(_ projects: [Project]) {
        guard !projects.isEmpty, !sortedProjects.isEmpty else { return }
        let updates = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        for index in sortedProjects.indices {
            if let updated = updates[sortedProjects[index].id] {
                sortedProjects[index] = updated
            }
        }
        sortProjects()
    }

    /// 批次移除：一次过滤代替多次 remove(at:)，避免数组反复搬移。
    func removeProjects(_ projects: [Project]) {
        guard !projects.isEmpty, !sortedProjects.isEmpty else { return }
        let removedIDs = Set(projects.map(\.id))
        sortedProjects.removeAll { removedIDs.contains($0.id) }
    }

    /// 批次插入：一次性并入后统一重排，避免逐项二分插入的数组搬移。
    func insertProjects(_ projects: [Project]) {
        guard !projects.isEmpty else { return }
        var knownIDs = Set(sortedProjects.map(\.id))
        var added: [Project] = []
        for project in projects where knownIDs.insert(project.id).inserted {
            added.append(project)
        }
        guard !added.isEmpty else { return }
        sortedProjects.append(contentsOf: added)
        sortProjects()
    }

    private func sortProjects() {
        sortedProjects.sort(by: comesBefore)
    }

    private func binarySearchInsertionIndex(for project: Project) -> Int {
        var left = 0
        var right = sortedProjects.count
        
        while left < right {
            let mid = (left + right) / 2
            
            let shouldInsertBefore = comesBefore(project, sortedProjects[mid])
            
            if shouldInsertBefore {
                right = mid
            } else {
                left = mid + 1
            }
        }
        
        return left
    }

    private func comesBefore(_ lhs: Project, _ rhs: Project) -> Bool {
        let primaryComparison: ComparisonResult
        switch sortCriteria {
        case .name:
            primaryComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        case .lastModified:
            primaryComparison = compare(lhs.activityAt, rhs.activityAt)
        case .gitCommits:
            primaryComparison = compare(lhs.git_commits, rhs.git_commits)
        }

        if primaryComparison == .orderedSame {
            let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return isAscending
            ? primaryComparison == .orderedAscending
            : primaryComparison == .orderedDescending
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }
}

// MARK: - 协议定义 - 打破循环依赖

/// 一批项目状态变更。整批只发布一次，相同内容不发布。
struct ProjectBatchChange {
    var updates: [UUID: Project] = [:]
    var removals: Set<UUID> = []
    /// 批次是否动到标签。活动时间、Git 历史这类只动元数据的批次可跳过标签索引重建。
    var affectsTags: Bool = true
}

protocol ProjectOperationDelegate: AnyObject {
    var projects: [UUID: Project] { get set }
    var allTags: Set<String> { get set }

    func invalidateTagUsageCache()
    func notifyProjectsChanged()
    func applyGitDailyUpdates(_ updates: [UUID: Project])
    @discardableResult
    func applyProjectBatch(_ change: ProjectBatchChange) -> Int
}

extension ProjectOperationDelegate {
    func applyGitDailyUpdates(_ updates: [UUID: Project]) {
        var snapshot = projects
        for (id, project) in updates { snapshot[id] = project }
        projects = snapshot
        notifyProjectsChanged()
    }

    /// 批次快照发布：整批只写一次 `projects`，内容与当前状态相同则完全不发布。
    /// 返回值是实际变化的条数（0 表示没有发布），调用方据此决定是否落盘。
    @discardableResult
    func applyProjectBatch(_ change: ProjectBatchChange) -> Int {
        var snapshot = projects
        let changed = ProjectBatchMerge.apply(into: &snapshot, change: change)
        guard changed > 0 else { return 0 }
        projects = snapshot
        notifyProjectsChanged()
        return changed
    }
}

/// 批次合并的纯函数部分：只改传入的快照，不碰发布通道。
///
/// 单独抽出来是为了让「逐项发布」和「整批发布」的差异可被测试直接测量，
/// 也避免接入方各自复制一份合并规则（漏掉「不复活已删项目」这类边界）。
enum ProjectBatchMerge {
    /// - Returns: 实际变化的条数；0 表示快照与批次内容一致，不需要发布。
    static func apply(into snapshot: inout [UUID: Project], change: ProjectBatchChange) -> Int {
        var changed = 0

        // 同一批次里既更新又删除的项目按删除处理：先算变化一次，再统一移除，
        // 否则会先写回再删掉，白白多一次发布和一次数组复制。
        for (id, project) in change.updates
        where !change.removals.contains(id) && snapshot[id] != project {
            snapshot[id] = project
            changed += 1
        }

        // 删除只作用于当前仍存在的项目；批次里附带的新建不会被这里复活。
        for id in change.removals where snapshot.removeValue(forKey: id) != nil {
            changed += 1
        }

        return changed
    }
}

/// 标签倒排索引的纯函数维护。
///
/// 从 `TagManager` 抽出来，是为了让「一批项目改了标签」的索引变更能在不构造
/// TagManager（会读写真实用户目录）的前提下被测试覆盖。
enum ProjectTagIndexLogic {
    /// 把一批变更增量合并进索引，只动标签真正变化的项目。
    /// - Parameters:
    ///   - index: 标签 → 项目 ID 集合的倒排索引，原地修改。
    ///   - previous: 变更前的项目（用于取旧标签），缺省视为没有旧标签。
    static func apply(
        to index: inout [String: Set<UUID>],
        change: ProjectBatchChange,
        previous: [UUID: Project]
    ) {
        for id in change.removals {
            remove(id, tags: previous[id]?.tags ?? [], from: &index)
        }

        for (id, project) in change.updates {
            let oldTags = previous[id]?.tags ?? []
            guard oldTags != project.tags else { continue }
            remove(id, tags: oldTags, from: &index)
            for tag in project.tags {
                index[tag, default: []].insert(id)
            }
        }
    }

    private static func remove(_ id: UUID, tags: Set<String>, from index: inout [String: Set<UUID>]) {
        for tag in tags {
            index[tag]?.remove(id)
            if index[tag]?.isEmpty == true {
                index.removeValue(forKey: tag)
            }
        }
    }
}

protocol DirectoryWatcherDelegate: AnyObject {
    var watchedDirectories: Set<String> { get set }
    var projects: [UUID: Project] { get set }

    func notifyProjectsChanged()
    func scanDidStart(directory: String)
    func scanDidFinish(directory: String, discovered: Int)
    func scanDidFail(directory: String, message: String)
}

protocol SortManagerDelegate: AnyObject {
    func updateSortedProjects(_ projects: [Project])
    func insertProject(_ project: Project)
    func updateProject(_ project: Project)
    func removeProject(_ project: Project)
    func updateProjectMetadata(_ projects: [Project])
    func updateProjectsMetadata(_ projects: [Project])
    func insertProjects(_ projects: [Project])
    func removeProjects(_ projects: [Project])
}

extension SortManagerDelegate {
    func updateProjectMetadata(_ projects: [Project]) {
        for project in projects { updateProject(project) }
    }

    func updateProjectsMetadata(_ projects: [Project]) {
        for project in projects { updateProject(project) }
    }

    func insertProjects(_ projects: [Project]) {
        for project in projects { insertProject(project) }
    }

    func removeProjects(_ projects: [Project]) {
        for project in projects { removeProject(project) }
    }
}

// MARK: - 项目操作管理器 - 无循环依赖版本

class ProjectOperationManager {

    /// git 采集专用串行队列：git 进程本身是主要开销，串行避免多路刷新互相抢进程
    private let gitQueue = DispatchQueue(label: "com.projectmanager.gitdaily", qos: .utility)
    /// projects.json 落盘走低优先级串行队列，主线程只做快照
    let ioQueue = DispatchQueue(label: "com.projectmanager.cache-writes", qos: .utility)
    private let savePendingLock = NSLock()
    private var saveDebounceTimer: Timer?
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
        guard ProjectDiscoveryPolicy.isEligibleProjectPath(project.path) else {
            Log.debug("忽略点号项目目录: \(project.path)")
            return
        }
        
        // 检查项目是否已存在
        if Project.isProjectExists(path: project.path, in: delegate.projects) {
            Log.debug("项目已存在，跳过注册: \(project.name)")
            return
        }

        Log.debug("注册项目: \(project.name), 标签: \(project.tags)")
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
    
    func registerProjects(_ projects: [Project], updateGitDaily: Bool = true) {
        guard let delegate = delegate else { return }

        Log.info("开始注册 \(projects.count) 个项目（当前 \(delegate.projects.count)）")

        var allNewTags = Set<String>()
        var newlyRegistered: [Project] = []

        // 只做内存合并，不逐项发布：整批写回放在最后一次性完成。
        // 注意：git 采集已移到后台（见 refreshGitDailyInBackground）
        for project in projects {
            guard ProjectDiscoveryPolicy.isEligibleProjectPath(project.path) else {
                Log.debug("   ⏭️ 忽略点号项目目录: \(project.path)")
                continue
            }

            // 检查项目是否已存在
            if Project.isProjectExists(path: project.path, in: delegate.projects) {
                Log.debug("   ⏭️ 跳过已存在: \(project.name)")
                continue
            }

            Log.debug("   ✅ 注册新项目: \(project.name) (ID: \(project.id))")
            newlyRegistered.append(project)
        }

        guard !newlyRegistered.isEmpty else {
            Log.info("批量注册完成：没有新项目")
            return
        }

        let changed = delegate.applyProjectBatch(
            ProjectBatchChange(updates: Dictionary(uniqueKeysWithValues: newlyRegistered.map { ($0.id, $0) }))
        )
        guard changed > 0 else {
            Log.info("批量注册完成：没有新项目")
            return
        }

        sortDelegate?.insertProjects(newlyRegistered)
        // 新标签以发布后的项目集合为准，避免同一批次内重复计算。
        for project in newlyRegistered {
            allNewTags.formUnion(project.tags)
        }
        allNewTags.subtract(delegate.allTags)
        delegate.allTags.formUnion(allNewTags)
        delegate.invalidateTagUsageCache()

        // 统一处理系统标签同步（整批一次）
        if !allNewTags.isEmpty {
            let systemTags = TagSystemSync.loadSystemTags()
            var updatedTags = systemTags
            updatedTags.formUnion(allNewTags)
            if updatedTags != systemTags {
                TagSystemSync.syncTagsToSystem(updatedTags)
            }
        }

        // 统一保存一次
        saveToCache()

        // git_daily 交给后台：只为本次真正入库的项目补数据，
        // 已在库中的项目（skipped）本方法不会更新它们，因此不做无用采集。
        if updateGitDaily {
            refreshGitDailyInBackground(for: newlyRegistered)
        }

        Log.info("批量注册完成：成功注册 \(newlyRegistered.count) 个项目，发现新标签 \(allNewTags.count) 个")
    }

    /// 文件事件风暴的批量落点：整批只发布一次 `projects`，内容无变化则完全不发布。
    ///
    /// 症状（本方法要解决的问题）：`registerProject`/`updateProjects`/`removeProject`
    /// 各自逐项写 `projects`，每个 `@Published` 字典写入都会复制一次并同步通知观察者；
    /// FSEvents 一批事件命中多个项目时，列表因此收到成倍通知、重复重建索引与筛选。
    /// 现在先合并成批次，再一次性写回快照。
    ///
    /// - Returns: 实际变化并发布的条数；0 表示批次内容与当前状态一致。
    @discardableResult
    func applyProjectBatch(updates: [Project], removals: Set<UUID> = []) -> Int {
        guard let delegate = delegate else { return 0 }

        // 以当前字典为准：只更新仍存在的项目，不复活批次排队期间被删掉的项目。
        var changedUpdates: [UUID: Project] = [:]
        for project in updates {
            guard let current = delegate.projects[project.id], current != project else { continue }
            changedUpdates[project.id] = project
        }
        // 排序缓存要先拿到旧值，发布之后字典里就没有了。
        let removedProjects = removals.compactMap { delegate.projects[$0] }
        let existingRemovals = Set(removedProjects.map(\.id))
        guard !changedUpdates.isEmpty || !existingRemovals.isEmpty else { return 0 }

        let published = delegate.applyProjectBatch(
            ProjectBatchChange(updates: changedUpdates, removals: existingRemovals)
        )
        guard published > 0 else { return 0 }

        // 排序缓存与发布在同一轮内完成：订阅方收到发布后立刻读排序列表，
        // 读到的是同一批数据（顺序与 Git 回填路径一致）。
        if !changedUpdates.isEmpty {
            sortDelegate?.updateProjectsMetadata(Array(changedUpdates.values))
        }
        if !removedProjects.isEmpty {
            sortDelegate?.removeProjects(removedProjects)
        }
        delegate.invalidateTagUsageCache()
        saveToCache()
        return published
    }

    /// 后台补齐 git_daily，完成后回主线程逐项目更新
    ///
    /// 症状（本方法要解决的问题）：git 采集原先在 registerProjects 里同步执行，
    /// 而多数调用方在主线程（`DispatchQueue.main.async`、通知回调、工具栏命令），
    /// 193 个仓库的 `git log`/`rev-parse` 会把 UI 阻塞数秒。
    /// 现在：注册立即返回（项目马上可见），git 数据随后补齐。
    func refreshGitDailyInBackground(for projects: [Project], days: Int = 365) {
        gitQueue.async { [weak self] in
            let updated = GitDailyCollector.updateProjectsWithGitDaily(projects, days: days)
            let changes = Dictionary(uniqueKeysWithValues: updated.compactMap { project in
                project.git_daily.map { (project.id, $0) }
            })

            DispatchQueue.main.async {
                self?.applyGitDaily(changes)
            }
        }
    }

    /// 合并时重新读取当前项目，只替换历史字段，不复活已删除的项目。
    func applyGitDaily(_ values: [UUID: String]) {
        guard let delegate = delegate else { return }
        var changes: [UUID: Project] = [:]
        for (id, gitDaily) in values {
            guard let current = delegate.projects[id], current.git_daily != gitDaily else { continue }
            changes[id] = current.copyWith(gitDaily: gitDaily)
        }
        guard !changes.isEmpty else { return }
        sortDelegate?.updateProjectMetadata(Array(changes.values))
        delegate.applyGitDailyUpdates(changes)
        saveToCache()
        Log.debug("后台补齐 git_daily：\(changes.count) 个项目")
    }
    
    /// 批量更新项目属性（标签/端口等整条快照路径）。
    ///
    /// 文件事件风暴会一次送来几十上百个项目：逐项写 `projects` 会让每个
    /// `@Published` 字典都复制一次并同步通知观察者，列表随后又整体重算一遍。
    /// 这里先在字典外合并、过滤掉相同值，再整批发布一次。
    func updateProjects(_ updates: [Project]) {
        _ = applyProjectBatch(updates: updates)
    }

    /// 文件事件专用：整批只提升 `activityAt`，整批发布一次。
    ///
    /// 与 `updateProjects` 的差别是合并时重新读取当前项目，只改活动时间一个字段；
    /// 事件排队期间用户改过的标签、端口、启动命令都保留，
    /// 期间被删除的项目也不会被这批旧快照复活。
    @discardableResult
    func applyActivityBatch(_ projectIDs: Set<UUID>, at activityAt: Date) -> Int {
        guard let delegate = delegate, !projectIDs.isEmpty else { return 0 }

        var changes: [UUID: Project] = [:]
        for id in projectIDs {
            guard let current = delegate.projects[id], activityAt > current.activityAt else { continue }
            changes[id] = current.copyWith(activityAt: activityAt)
        }
        guard !changes.isEmpty else { return 0 }

        let changed = delegate.applyProjectBatch(
            ProjectBatchChange(updates: changes, removals: [], affectsTags: false)
        )
        guard changed > 0 else { return 0 }

        // 活动时间就是排序键，排序缓存必须跟着换位置（不能只原位替换）。
        sortDelegate?.updateProjectsMetadata(Array(changes.values))
        // 活动时间不影响标签归属，跳过标签索引重建。
        saveToCache()
        return changed
    }

    func removeProject(_ id: UUID) {
        guard let delegate = delegate,
              let project = delegate.projects[id] else { return }

        sortDelegate?.removeProject(project)
        delegate.applyProjectBatch(ProjectBatchChange(removals: [id]))
        delegate.invalidateTagUsageCache()

        saveToCache()
    }
    
    func saveAllToCache() {
        saveToCache()
    }

    private func saveToCache() {
        guard let delegate = delegate else { return }

        // 主线程只做轻量快照，编码与写盘全部挪到串行 I/O 队列；
        // 合并去抖：活动高峰（如 FSEvents 每 0.8s 一批）不再逐拍落盘，
        // 待写定时器未触发就先重置，磁盘写频率从「每批次一次」降为「静默 2s 后一次」。
        let projectsArray = Array(delegate.projects.values)
        let cacheURL = storage.appSupportURL.appendingPathComponent("projects.json")

        savePendingLock.lock()
        saveDebounceTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.savePendingLock.lock()
            self?.saveDebounceTimer = nil
            self?.savePendingLock.unlock()
            self?.ioQueue.async { [weak self] in
                self?.writeProjectsSnapshot(projectsArray, to: cacheURL)
            }
        }
        saveDebounceTimer = timer
        savePendingLock.unlock()
    }

    private func writeProjectsSnapshot(_ projectsArray: [Project], to cacheURL: URL) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(projectsArray)
            try data.write(to: cacheURL, options: .atomic)
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
    private lazy var eventMonitor = FileSystemEventMonitor { [weak self] changedPaths in
        self?.updateActivity(for: changedPaths)
        self?.incrementallyReloadProjects(showStatus: false)
    }
    private var reloadInProgress = false
    private var reloadPending = false

    init(delegate: DirectoryWatcherDelegate?, operationManager: ProjectOperationManager?, storage: TagStorage) {
        self.delegate = delegate
        self.operationManager = operationManager
        self.storage = storage
        self.projectIndex = ProjectIndex(storage: storage)
    }

    /// 用 FSEvents 的变更路径增量更新活动时间，不递归扫描项目内容。
    ///
    /// 一批事件可能命中几十个项目。旧实现为每个命中的项目复制一次快照、逐项写
    /// `projects` 让 `@Published` 每次都通知观察者；现在只传命中的项目 ID，
    /// 由 `applyActivityBatch` 重新读取当前值后整批发布一次。
    private func updateActivity(for changedPaths: Set<String>) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let delegate = self.delegate else { return }

            let changedIDs = Set(delegate.projects.values.compactMap { project -> UUID? in
                changedPaths.contains { changedPath in
                    changedPath == project.path || changedPath.hasPrefix(project.path + "/")
                } ? project.id : nil
            })
            guard !changedIDs.isEmpty else { return }

            self.operationManager?.applyActivityBatch(changedIDs, at: Date())
        }
    }

    func startMonitoring(paths: Set<String>) {
        eventMonitor.start(paths: paths)
    }

    func stopMonitoring() {
        eventMonitor.stop()
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
            eventMonitor.start(paths: delegate.watchedDirectories)
            delegate.scanDidStart(directory: path)

            // 加载新目录的项目
            queue.async {
                guard FileManager.default.fileExists(atPath: path) else {
                    DispatchQueue.main.async {
                        delegate.scanDidFail(directory: path, message: "目录不存在或无法访问")
                    }
                    return
                }

                let newProjects = self.scanAndCollectProjects(path, force: true)

                DispatchQueue.main.async {
                    self.operationManager?.registerProjects(newProjects)
                    delegate.scanDidFinish(directory: path, discovered: newProjects.count)
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
            eventMonitor.start(paths: delegate.watchedDirectories)
            removeProjectsInDirectory(path)
        }
    }
    
    private func removeProjectsInDirectory(_ path: String) {
        guard let delegate = delegate else { return }

        // 删除该目录下的所有项目：整批一次发布，不逐项移除再逐项通知。
        let idsToRemove = Set(delegate.projects.values
            .filter { $0.path.hasPrefix(path) }
            .map(\.id))
        guard !idsToRemove.isEmpty else { return }
        _ = operationManager?.applyProjectBatch(updates: [], removals: idsToRemove)
    }
    
    func clearCacheAndReloadProjects() {
        guard let delegate = delegate else { return }

        DispatchQueue.main.async {
            delegate.scanDidStart(directory: "全部监视目录")
        }

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
                    delegate.scanDidFail(directory: "全部监视目录", message: "没有可用的监视目录")
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
            
            // 在后台恢复标签并采集 Git 数据，避免主线程长时间无响应。
            var projectsWithTags: [Project] = []
            for project in allProjects {
                let systemTags = TagSystemSync.loadTagsFromFile(at: project.path)
                if systemTags.isEmpty {
                    projectsWithTags.append(project)
                } else {
                    // copyWith 保留已有 Git/文件系统数据，避免重新执行 Git 查询。
                    projectsWithTags.append(project.copyWith(tags: systemTags))
                    Log.debug("恢复项目 '\(project.name)' 的标签: \(systemTags)")
                }
            }
            let projectsWithGitDaily = GitDailyCollector.updateProjectsWithGitDaily(
                projectsWithTags,
                days: 365
            )

            // 一次性更新 UI，跳过重复的 Git 采集。
            DispatchQueue.main.async {
                delegate.projects.removeAll()
                self.operationManager?.registerProjects(
                    projectsWithGitDaily,
                    updateGitDaily: false
                )
                delegate.scanDidFinish(
                    directory: "全部监视目录",
                    discovered: projectsWithGitDaily.count
                )
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
            try data.write(to: directoriesURL, options: .atomic)
            print("保存监视目录到文件: \(Array(delegate.watchedDirectories))")
        } catch {
            print("保存监视目录失败: \(error)")
        }
    }
    
    func incrementallyReloadProjects() {
        incrementallyReloadProjects(showStatus: true)
    }

    private func incrementallyReloadProjects(showStatus: Bool) {
        guard let delegate = delegate else { return }

        queue.async {
            if self.reloadInProgress {
                self.reloadPending = true
                return
            }
            self.reloadInProgress = true
            defer {
                self.reloadInProgress = false
                if self.reloadPending {
                    self.reloadPending = false
                    self.incrementallyReloadProjects(showStatus: false)
                }
            }

            if showStatus {
                DispatchQueue.main.async {
                    delegate.scanDidStart(directory: "全部监视目录")
                }
            }

            print("开始后台增量更新项目...")

            // 获取所有监视目录
            let directories = Array(delegate.watchedDirectories)
            if directories.isEmpty {
                if showStatus {
                    DispatchQueue.main.async {
                        delegate.scanDidFail(directory: "全部监视目录", message: "没有可用的监视目录")
                    }
                }
                return
            }
            
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
                if showStatus {
                    DispatchQueue.main.async {
                        delegate.scanDidFinish(directory: "全部监视目录", discovered: allProjects.count)
                    }
                }
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
                    // 1. 删除已移除的项目：整批一次发布，不逐项通知。
                    let removedIDs = Set(existingProjects.values
                        .filter { removedPaths.contains($0.path) }
                        .map(\.id))
                    if !removedIDs.isEmpty {
                        self.operationManager?.applyProjectBatch(updates: [], removals: removedIDs)
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
                    if showStatus {
                        delegate.scanDidFinish(directory: "全部监视目录", discovered: allProjects.count)
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
                        if showStatus {
                            delegate.scanDidFinish(directory: "全部监视目录", discovered: allProjects.count)
                        }
                    }
                } else if showStatus {
                    DispatchQueue.main.async {
                        delegate.scanDidFinish(directory: "全部监视目录", discovered: allProjects.count)
                    }
                }
            }
        }
    }
}
