import Foundation

// MARK: - Branch Management Data Models
// 分支管理数据模型 - 遵循现有架构的数据与逻辑分离原则

/// 分支状态枚举
enum BranchStatus: String, CaseIterable, Codable {
    case clean = "clean"        // 干净状态，无未提交更改
    case hasChanges = "changes" // 有未提交更改  
    case unknown = "unknown"    // 状态未知
    
    var displayName: String {
        switch self {
        case .clean: return "干净"
        case .hasChanges: return "有更改"
        case .unknown: return "未知"
        }
    }
    
    var color: String {
        switch self {
        case .clean: return "green"
        case .hasChanges: return "orange" 
        case .unknown: return "gray"
        }
    }
}

/// 分支操作类型
enum BranchOperation: String, CaseIterable {
    case create = "create"
    case delete = "delete"
    case merge = "merge"
    case `switch` = "switch"
    case status = "status"
    
    var displayName: String {
        switch self {
        case .create: return "创建分支"
        case .delete: return "删除分支"
        case .merge: return "合并分支"
        case .`switch`: return "切换分支"
        case .status: return "状态检查"
        }
    }
}

/// 分支操作结果
struct BranchOperationResult {
    let success: Bool
    let message: String
    let operation: BranchOperation
    let branchName: String?
    let output: String?
    let timestamp: Date
    
    init(
        success: Bool, 
        message: String, 
        operation: BranchOperation, 
        branchName: String? = nil,
        output: String? = nil
    ) {
        self.success = success
        self.message = message
        self.operation = operation
        self.branchName = branchName
        self.output = output
        self.timestamp = Date()
    }
    
    static func success(
        operation: BranchOperation, 
        message: String, 
        branchName: String? = nil,
        output: String? = nil
    ) -> BranchOperationResult {
        BranchOperationResult(
            success: true, 
            message: message, 
            operation: operation, 
            branchName: branchName,
            output: output
        )
    }
    
    static func failure(
        operation: BranchOperation, 
        message: String, 
        branchName: String? = nil,
        output: String? = nil
    ) -> BranchOperationResult {
        BranchOperationResult(
            success: false, 
            message: message, 
            operation: operation, 
            branchName: branchName,
            output: output
        )
    }
}

/// Git Worktree详细信息
struct WorktreeInfo: Codable, Identifiable {
    let id = UUID()
    let path: String
    let branch: String
    let commit: String
    let isMain: Bool
    let status: BranchStatus
    let lastModified: Date
    
    init(
        path: String, 
        branch: String, 
        commit: String, 
        isMain: Bool = false,
        status: BranchStatus = .unknown,
        lastModified: Date = Date()
    ) {
        self.path = path
        self.branch = branch
        self.commit = commit
        self.isMain = isMain
        self.status = status
        self.lastModified = lastModified
    }
}

/// 分支基本信息
struct BranchInfo: Codable, Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let description: String
    let status: BranchStatus
    let createdAt: Date
    let lastUsed: Date?
    let uncommittedChanges: Int
    let diskSize: UInt64?
    let isMain: Bool
    
    init(
        name: String,
        path: String, 
        description: String = "",
        status: BranchStatus = .unknown,
        createdAt: Date = Date(),
        lastUsed: Date? = nil,
        uncommittedChanges: Int = 0,
        diskSize: UInt64? = nil,
        isMain: Bool = false
    ) {
        self.name = name
        self.path = path
        self.description = description
        self.status = status
        self.createdAt = createdAt
        self.lastUsed = lastUsed
        self.uncommittedChanges = uncommittedChanges
        self.diskSize = diskSize
        self.isMain = isMain
    }
    
    // Hashable 实现
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: BranchInfo, rhs: BranchInfo) -> Bool {
        lhs.id == rhs.id
    }
    
    /// 格式化分支大小显示
    var formattedDiskSize: String {
        guard let size = diskSize else { return "未知" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
    
    /// 格式化最后使用时间
    var formattedLastUsed: String {
        guard let lastUsed = lastUsed else { return "从未使用" }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: lastUsed, relativeTo: Date())
    }
    
    /// 是否有未提交更改
    var hasUncommittedChanges: Bool {
        return uncommittedChanges > 0
    }
}

/// 分支创建参数
struct BranchCreationParams {
    let name: String
    let description: String
    let baseBranch: String
    let projectPath: String
    
    init(name: String, description: String = "", baseBranch: String = "main", projectPath: String) {
        self.name = name
        self.description = description
        self.baseBranch = baseBranch
        self.projectPath = projectPath
    }
    
    /// 验证分支名称
    var isValidName: Bool {
        // Git分支名称验证规则
        let pattern = "^[a-zA-Z0-9._/-]+$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: name.utf16.count)
        
        guard let regex = regex else { return false }
        let matches = regex.matches(in: name, range: range)
        
        return !name.isEmpty && 
               !name.hasPrefix("/") && 
               !name.hasSuffix("/") &&
               !name.contains("..") &&
               !name.contains("//") &&
               matches.count > 0 &&
               name.count <= 100
    }
    
    /// 目标分支路径
    var targetPath: String {
        return "\(projectPath)/.trees/\(name)"
    }
}

/// 分支管理配置
struct BranchConfig {
    let autoCleanup: Bool
    let confirmDeletion: Bool  
    let showHiddenBranches: Bool
    let defaultEditor: String?
    
    static let `default` = BranchConfig(
        autoCleanup: false,
        confirmDeletion: true,
        showHiddenBranches: false,
        defaultEditor: nil
    )
}

/// 分支统计信息
struct BranchStatistics {
    let totalBranches: Int
    let cleanBranches: Int
    let branchesWithChanges: Int
    let unknownStatusBranches: Int
    let totalDiskUsage: UInt64
    let lastUpdated: Date
    
    init(branches: [BranchInfo]) {
        self.totalBranches = branches.count
        self.cleanBranches = branches.filter { $0.status == .clean }.count
        self.branchesWithChanges = branches.filter { $0.status == .hasChanges }.count
        self.unknownStatusBranches = branches.filter { $0.status == .unknown }.count
        self.totalDiskUsage = branches.compactMap { $0.diskSize }.reduce(0, +)
        self.lastUpdated = Date()
    }
    
    var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(totalDiskUsage))
    }
}