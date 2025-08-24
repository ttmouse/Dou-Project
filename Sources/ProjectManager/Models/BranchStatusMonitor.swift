import Foundation
import Combine

// MARK: - Branch Status Monitor
// 分支状态监控器 - 实时监控分支状态变化

@MainActor
class BranchStatusMonitor: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var branchStatuses: [String: BranchStatus] = [:]
    @Published var branchChangeCounts: [String: Int] = [:]
    @Published var isMonitoring = false
    
    // MARK: - Private Properties
    
    private var monitoringTasks: [String: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let updateInterval: TimeInterval = 30.0 // 30秒更新一次
    private let quickUpdateInterval: TimeInterval = 5.0 // 快速更新间隔
    
    // 监控配置
    struct MonitoringConfig {
        let projectPath: String
        let branches: Set<String>
        let quickUpdateBranches: Set<String> // 需要快速更新的分支（如有未提交更改的）
        
        static let empty = MonitoringConfig(
            projectPath: "",
            branches: [],
            quickUpdateBranches: []
        )
    }
    
    private var currentConfig = MonitoringConfig.empty
    
    // MARK: - Public Methods
    
    /// 开始监控指定项目的分支状态
    /// - Parameters:
    ///   - projectPath: 项目路径
    ///   - branches: 需要监控的分支路径列表
    func startMonitoring(projectPath: String, branches: [BranchInfo]) {
        stopMonitoring()
        
        let branchPaths = Set(branches.map { $0.path })
        let quickUpdateBranches = Set(branches.filter { $0.hasUncommittedChanges }.map { $0.path })
        
        currentConfig = MonitoringConfig(
            projectPath: projectPath,
            branches: branchPaths,
            quickUpdateBranches: quickUpdateBranches
        )
        
        isMonitoring = true
        
        // 立即进行一次状态检查
        performImmediateStatusCheck()
        
        // 启动定期监控
        startPeriodicMonitoring()
        
        print("🔍 开始监控 \(branches.count) 个分支的状态")
    }
    
    /// 停止监控
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        // 取消所有监控任务
        for (_, task) in monitoringTasks {
            task.cancel()
        }
        monitoringTasks.removeAll()
        
        // 取消订阅
        cancellables.removeAll()
        
        isMonitoring = false
        currentConfig = .empty
        
        print("🛑 停止分支状态监控")
    }
    
    /// 强制刷新所有分支状态
    func refreshAllStatuses() {
        guard isMonitoring else { return }
        performImmediateStatusCheck()
    }
    
    /// 刷新单个分支状态
    /// - Parameter branchPath: 分支路径
    func refreshBranchStatus(_ branchPath: String) {
        guard isMonitoring, currentConfig.branches.contains(branchPath) else { return }
        
        Task {
            await updateBranchStatus(branchPath)
        }
    }
    
    /// 添加分支到监控列表
    /// - Parameter branchInfo: 分支信息
    func addBranchToMonitoring(_ branchInfo: BranchInfo) {
        guard isMonitoring else { return }
        
        var newBranches = currentConfig.branches
        var newQuickUpdate = currentConfig.quickUpdateBranches
        
        newBranches.insert(branchInfo.path)
        
        if branchInfo.hasUncommittedChanges {
            newQuickUpdate.insert(branchInfo.path)
        }
        
        currentConfig = MonitoringConfig(
            projectPath: currentConfig.projectPath,
            branches: newBranches,
            quickUpdateBranches: newQuickUpdate
        )
        
        // 立即检查新分支状态
        Task {
            await updateBranchStatus(branchInfo.path)
        }
        
        // 启动对新分支的监控
        startMonitoringForBranch(branchInfo.path)
    }
    
    /// 从监控列表移除分支
    /// - Parameter branchPath: 分支路径
    func removeBranchFromMonitoring(_ branchPath: String) {
        guard isMonitoring else { return }
        
        // 停止该分支的监控任务
        monitoringTasks[branchPath]?.cancel()
        monitoringTasks.removeValue(forKey: branchPath)
        
        // 从状态记录中移除
        branchStatuses.removeValue(forKey: branchPath)
        branchChangeCounts.removeValue(forKey: branchPath)
        
        // 更新配置
        var newBranches = currentConfig.branches
        var newQuickUpdate = currentConfig.quickUpdateBranches
        
        newBranches.remove(branchPath)
        newQuickUpdate.remove(branchPath)
        
        currentConfig = MonitoringConfig(
            projectPath: currentConfig.projectPath,
            branches: newBranches,
            quickUpdateBranches: newQuickUpdate
        )
    }
    
    // MARK: - Private Methods
    
    private func performImmediateStatusCheck() {
        for branchPath in currentConfig.branches {
            Task {
                await updateBranchStatus(branchPath)
            }
        }
    }
    
    private func startPeriodicMonitoring() {
        for branchPath in currentConfig.branches {
            startMonitoringForBranch(branchPath)
        }
    }
    
    private func startMonitoringForBranch(_ branchPath: String) {
        // 如果已经在监控，先取消
        monitoringTasks[branchPath]?.cancel()
        
        let interval = currentConfig.quickUpdateBranches.contains(branchPath) 
            ? quickUpdateInterval 
            : updateInterval
        
        let task = Task {
            while !Task.isCancelled {
                await updateBranchStatus(branchPath)
                
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
        
        monitoringTasks[branchPath] = task
    }
    
    private func updateBranchStatus(_ branchPath: String) async {
        guard !Task.isCancelled else { return }
        
        // 在后台线程执行Git状态检查
        let result = await Task.detached {
            return ShellExecutor.getGitStatus(path: branchPath)
        }.value
        
        guard !Task.isCancelled else { return }
        
        // 更新状态
        let newStatus: BranchStatus = result.clean ? .clean : .hasChanges
        let changeCount = result.changes
        
        let statusChanged = branchStatuses[branchPath] != newStatus
        let countChanged = branchChangeCounts[branchPath] != changeCount
        
        if statusChanged || countChanged {
            branchStatuses[branchPath] = newStatus
            branchChangeCounts[branchPath] = changeCount
            
            // 如果状态发生变化，发送通知
            if statusChanged {
                NotificationCenter.default.post(
                    name: .branchStatusChanged,
                    object: nil,
                    userInfo: [
                        "branchPath": branchPath,
                        "newStatus": newStatus,
                        "changeCount": changeCount
                    ]
                )
                
                print("📊 分支状态变化: \(URL(fileURLWithPath: branchPath).lastPathComponent) -> \(newStatus.displayName)")
            }
            
            // 动态调整监控频率
            adjustMonitoringFrequency(for: branchPath, status: newStatus)
        }
    }
    
    private func adjustMonitoringFrequency(for branchPath: String, status: BranchStatus) {
        let needsQuickUpdate = status == .hasChanges
        let currentlyQuickUpdate = currentConfig.quickUpdateBranches.contains(branchPath)
        
        if needsQuickUpdate != currentlyQuickUpdate {
            var newQuickUpdate = currentConfig.quickUpdateBranches
            
            if needsQuickUpdate {
                newQuickUpdate.insert(branchPath)
            } else {
                newQuickUpdate.remove(branchPath)
            }
            
            currentConfig = MonitoringConfig(
                projectPath: currentConfig.projectPath,
                branches: currentConfig.branches,
                quickUpdateBranches: newQuickUpdate
            )
            
            // 重新启动该分支的监控以使用新的更新间隔
            startMonitoringForBranch(branchPath)
        }
    }
    
    /// 获取分支当前状态
    /// - Parameter branchPath: 分支路径
    /// - Returns: 分支状态，如果未监控则返回nil
    func getBranchStatus(_ branchPath: String) -> BranchStatus? {
        return branchStatuses[branchPath]
    }
    
    /// 获取分支未提交更改数量
    /// - Parameter branchPath: 分支路径
    /// - Returns: 更改数量，如果未监控则返回nil
    func getBranchChangeCount(_ branchPath: String) -> Int? {
        return branchChangeCounts[branchPath]
    }
    
    /// 检查是否正在监控指定分支
    /// - Parameter branchPath: 分支路径
    /// - Returns: 是否正在监控
    func isMonitoringBranch(_ branchPath: String) -> Bool {
        return isMonitoring && currentConfig.branches.contains(branchPath)
    }
    
    /// 获取监控统计信息
    var monitoringStats: MonitoringStats {
        let totalBranches = currentConfig.branches.count
        let cleanBranches = branchStatuses.values.filter { $0 == .clean }.count
        let branchesWithChanges = branchStatuses.values.filter { $0 == .hasChanges }.count
        let unknownBranches = totalBranches - cleanBranches - branchesWithChanges
        let quickUpdateCount = currentConfig.quickUpdateBranches.count
        
        return MonitoringStats(
            totalBranches: totalBranches,
            cleanBranches: cleanBranches,
            branchesWithChanges: branchesWithChanges,
            unknownBranches: unknownBranches,
            quickUpdateBranches: quickUpdateCount,
            isActive: isMonitoring
        )
    }
}

// MARK: - Supporting Types

/// 监控统计信息
struct MonitoringStats {
    let totalBranches: Int
    let cleanBranches: Int
    let branchesWithChanges: Int
    let unknownBranches: Int
    let quickUpdateBranches: Int
    let isActive: Bool
    
    var summary: String {
        if !isActive {
            return "监控已停止"
        }
        
        return "监控 \(totalBranches) 个分支：\(cleanBranches) 干净，\(branchesWithChanges) 有更改"
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let branchStatusChanged = Notification.Name("branchStatusChanged")
}