import Foundation
import SwiftUI

// MARK: - ProjectManager DTO (Data Transfer Objects)
// 统一的数据传输对象定义 - 遵循Vibe Coding最佳实践
// 这个文件包含所有组件间数据传输的标准化定义

// MARK: - 操作结果通用格式

/// 通用操作结果DTO - 标准化所有操作的返回格式
struct OperationResultDTO<T: Codable>: Codable {
    let success: Bool
    let code: Int                    // 0表示成功，其他表示失败
    let message: String
    let data: T?
    let timestamp: Date
    let operation: String
    
    init(success: Bool, code: Int = 0, message: String, data: T? = nil, operation: String = "") {
        self.success = success
        self.code = success ? 0 : (code == 0 ? -1 : code)
        self.message = message
        self.data = data
        self.timestamp = Date()
        self.operation = operation
    }
    
    static func success(data: T? = nil, message: String = "操作成功", operation: String = "") -> OperationResultDTO<T> {
        return OperationResultDTO(success: true, code: 0, message: message, data: data, operation: operation)
    }
    
    static func failure(code: Int = -1, message: String, operation: String = "") -> OperationResultDTO<T> {
        return OperationResultDTO(success: false, code: code, message: message, data: nil, operation: operation)
    }
}

// MARK: - 项目相关DTO

/// 项目基本信息DTO - 用于列表显示和基本操作
struct ProjectBasicDTO: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let path: String
    let lastModified: Date
    let tags: [String]              // 数组形式，保证顺序
    let isGitRepository: Bool
    let hasUncommittedChanges: Bool?
    let fileCount: Int?
    let directorySize: String?      // 格式化后的大小字符串
}

/// 项目详细信息DTO - 用于详情页面展示
struct ProjectDetailDTO: Codable {
    let basic: ProjectBasicDTO
    let git: GitInfoDTO?
    let filesystem: FileSystemInfoDTO
    let branches: [BranchSummaryDTO]
    let statistics: ProjectStatisticsDTO
}

/// Git信息DTO
struct GitInfoDTO: Codable, Equatable {
    let commitCount: Int
    let lastCommitDate: Date?
    let currentBranch: String
    let hasRemote: Bool
    let remoteUrl: String?
    let uncommittedChanges: Int
    let ahead: Int                  // 领先远程多少个提交
    let behind: Int                 // 落后远程多少个提交
}

/// 文件系统信息DTO
struct FileSystemInfoDTO: Codable, Equatable {
    let modificationDate: Date
    let size: UInt64
    let formattedSize: String       // 格式化后的大小显示
    let fileCount: Int
    let directoryCount: Int
    let lastCheckTime: Date
    let checksum: String?
}

/// 项目统计信息DTO
struct ProjectStatisticsDTO: Codable {
    let totalProjects: Int
    let gitProjects: Int
    let activeProjects: Int         // 最近修改的项目数
    let totalSize: String          // 格式化后的总大小
    let mostUsedTags: [String]
    let generatedAt: Date
}

// MARK: - 分支相关DTO

/// 分支摘要信息DTO - 用于分支列表
struct BranchSummaryDTO: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let path: String
    let status: BranchStatusDTO
    let createdAt: Date
    let lastUsed: Date?
    let uncommittedChanges: Int
    let diskSize: String?           // 格式化后的大小
    let isMain: Bool
}

/// 分支详细信息DTO - 用于分支详情和操作
struct BranchDetailDTO: Codable {
    let summary: BranchSummaryDTO
    let description: String
    let commits: [CommitSummaryDTO]
    let files: BranchFileStatsDTO
    let performance: BranchPerformanceDTO
}

/// 分支状态DTO
enum BranchStatusDTO: String, Codable, CaseIterable {
    case clean = "clean"
    case hasChanges = "changes"
    case unknown = "unknown"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .clean: return "干净"
        case .hasChanges: return "有更改"
        case .unknown: return "未知"
        case .error: return "错误"
        }
    }
    
    var color: String {
        switch self {
        case .clean: return "green"
        case .hasChanges: return "orange"
        case .unknown: return "gray"
        case .error: return "red"
        }
    }
}

/// 提交信息摘要DTO
struct CommitSummaryDTO: Identifiable, Codable {
    let id: String                  // commit hash
    let message: String
    let author: String
    let date: Date
    let shortHash: String           // 短hash，用于显示
}

/// 分支文件统计DTO
struct BranchFileStatsDTO: Codable {
    let totalFiles: Int
    let addedFiles: Int
    let modifiedFiles: Int
    let deletedFiles: Int
    let binaryFiles: Int
    let languageDistribution: [String: Int]  // 语言: 文件数
}

/// 分支性能信息DTO
struct BranchPerformanceDTO: Codable {
    let checkoutTime: TimeInterval?  // 切换耗时
    let buildTime: TimeInterval?     // 构建耗时
    let testTime: TimeInterval?      // 测试耗时
    let lastBenchmark: Date?
}

// MARK: - 分支操作DTO

/// 分支创建请求DTO
struct CreateBranchRequestDTO: Codable {
    let name: String
    let description: String
    let baseBranch: String
    let projectPath: String
    let autoSwitch: Bool            // 创建后是否自动切换
    
    var isValid: Bool {
        !name.isEmpty && isValidBranchName && !projectPath.isEmpty
    }
    
    private var isValidBranchName: Bool {
        let pattern = "^[a-zA-Z0-9._/-]+$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: name.utf16.count)
        
        guard let regex = regex else { return false }
        let matches = regex.matches(in: name, range: range)
        
        return !name.hasPrefix("/") && 
               !name.hasSuffix("/") &&
               !name.contains("..") &&
               !name.contains("//") &&
               matches.count > 0 &&
               name.count <= 100
    }
}

/// 分支删除请求DTO
struct DeleteBranchRequestDTO: Codable {
    let branchName: String
    let projectPath: String
    let force: Bool                 // 是否强制删除
    let backupData: Bool           // 是否备份数据
}

/// 分支合并请求DTO
struct MergeBranchRequestDTO: Codable {
    let sourceBranch: String
    let targetBranch: String
    let projectPath: String
    let strategy: MergeStrategyDTO
    let commitMessage: String?
}

/// 合并策略DTO
enum MergeStrategyDTO: String, Codable, CaseIterable {
    case merge = "merge"
    case rebase = "rebase"
    case squash = "squash"
    
    var displayName: String {
        switch self {
        case .merge: return "合并提交"
        case .rebase: return "变基合并"
        case .squash: return "压缩合并"
        }
    }
}

// MARK: - 标签相关DTO

/// 标签信息DTO
struct TagDTO: Identifiable, Codable, Equatable {
    let id: String                  // 标签名作为ID
    let name: String
    let color: TagColorDTO
    let usageCount: Int
    let isHidden: Bool
    let isSystemTag: Bool
    let projects: [UUID]            // 使用此标签的项目ID列表
    let createdAt: Date?
    let lastUsed: Date?
}

/// 标签颜色DTO
struct TagColorDTO: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    let hexString: String           // 十六进制表示，方便传输
    
    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.hexString = String(format: "#%02X%02X%02X", 
                               Int(red * 255), 
                               Int(green * 255), 
                               Int(blue * 255))
    }
    
    init(hexString: String) {
        self.hexString = hexString
        // 简化的hex解析，实际使用时可能需要更完善的实现
        var rgb: UInt64 = 0
        let cleanHex = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        Scanner(string: cleanHex).scanHexInt64(&rgb)
        
        self.red = Double((rgb & 0xFF0000) >> 16) / 255.0
        self.green = Double((rgb & 0x00FF00) >> 8) / 255.0
        self.blue = Double(rgb & 0x0000FF) / 255.0
        self.alpha = 1.0
    }
}

/// 标签操作请求DTO
struct TagOperationRequestDTO: Codable {
    let operation: TagOperationTypeDTO
    let tagName: String
    let projectIds: [UUID]?
    let newColor: TagColorDTO?
    let newName: String?
}

enum TagOperationTypeDTO: String, Codable {
    case add = "add"
    case remove = "remove"
    case rename = "rename"
    case changeColor = "changeColor"
    case hide = "hide"
    case show = "show"
}

// MARK: - 搜索和过滤DTO

/// 搜索请求DTO
struct SearchRequestDTO: Codable {
    let query: String
    let filters: FilterOptionsDTO
    let sort: SortOptionsDTO
    let pagination: PaginationDTO?
}

/// 过滤选项DTO
struct FilterOptionsDTO: Codable, Equatable {
    let selectedTags: [String]
    let excludedTags: [String]
    let hasGit: Bool?
    let hasUncommittedChanges: Bool?
    let sizeRange: SizeRangeDTO?
    let dateRange: DateRangeDTO?
}

/// 大小范围DTO
struct SizeRangeDTO: Codable, Equatable {
    let minSize: UInt64?            // 字节
    let maxSize: UInt64?            // 字节
}

/// 日期范围DTO
struct DateRangeDTO: Codable, Equatable {
    let startDate: Date?
    let endDate: Date?
}

/// 排序选项DTO
struct SortOptionsDTO: Codable, Equatable {
    let criteria: SortCriteriaDTO
    let isAscending: Bool
    let secondaryCriteria: SortCriteriaDTO?
}

/// 排序条件DTO
enum SortCriteriaDTO: String, Codable, CaseIterable {
    case name = "name"
    case lastModified = "lastModified"
    case size = "size"
    case gitCommits = "gitCommits"
    case tagCount = "tagCount"
    case createdAt = "createdAt"
    
    var displayName: String {
        switch self {
        case .name: return "名称"
        case .lastModified: return "修改时间"
        case .size: return "大小"
        case .gitCommits: return "提交数"
        case .tagCount: return "标签数"
        case .createdAt: return "创建时间"
        }
    }
}

/// 分页DTO
struct PaginationDTO: Codable {
    let page: Int
    let pageSize: Int
    let totalCount: Int?
    
    var offset: Int {
        return page * pageSize
    }
}

/// 搜索结果DTO
struct SearchResultDTO: Codable {
    let projects: [ProjectBasicDTO]
    let totalCount: Int
    let pagination: PaginationDTO?
    let searchTime: TimeInterval
    let suggestedFilters: [String]   // 建议的过滤条件
}

// MARK: - 热力图相关DTO

/// 热力图数据点DTO
struct HeatmapDataPointDTO: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let commitCount: Int
    let intensity: Double           // 0.0 - 1.0
    let projects: [UUID]            // 当天有提交的项目ID
    let tooltip: String             // 悬停提示文本
}

/// 热力图请求DTO
struct HeatmapRequestDTO: Codable {
    let projectIds: [UUID]?         // 如果为nil，则显示所有项目
    let dateRange: DateRangeDTO
    let granularity: HeatmapGranularityDTO
}

enum HeatmapGranularityDTO: String, Codable {
    case day = "day"
    case week = "week"
    case month = "month"
    
    var displayName: String {
        switch self {
        case .day: return "按天"
        case .week: return "按周"
        case .month: return "按月"
        }
    }
}

/// 热力图响应DTO
struct HeatmapResponseDTO: Codable {
    let data: [HeatmapDataPointDTO]
    let statistics: HeatmapStatisticsDTO
    let generatedAt: Date
}

/// 热力图统计DTO
struct HeatmapStatisticsDTO: Codable {
    let totalCommits: Int
    let totalProjects: Int
    let mostActiveDay: Date?
    let averageCommitsPerDay: Double
    let streak: Int                 // 连续提交天数
    let longestStreak: Int
}

// MARK: - 配置相关DTO

/// 应用配置DTO
struct AppConfigDTO: Codable {
    let general: GeneralConfigDTO
    let ui: UIConfigDTO
    let performance: PerformanceConfigDTO
    let integrations: IntegrationConfigDTO
    let version: String
    let lastUpdated: Date
}

/// 通用配置DTO
struct GeneralConfigDTO: Codable {
    let enableAutoSave: Bool
    let autoSaveInterval: TimeInterval
    let enableIncrementalUpdate: Bool
    let watchedDirectories: [String]
    let excludePatterns: [String]
    let defaultEditor: String?
}

/// UI配置DTO
struct UIConfigDTO: Codable {
    let theme: ThemeDTO
    let defaultSortCriteria: SortCriteriaDTO
    let itemsPerPage: Int
    let showHiddenFiles: Bool
    let compactMode: Bool
    let animations: Bool
}

enum ThemeDTO: String, Codable {
    case system = "system"
    case light = "light"
    case dark = "dark"
}

/// 性能配置DTO
struct PerformanceConfigDTO: Codable {
    let cacheSize: Int
    let backgroundRefresh: Bool
    let maxConcurrentOperations: Int
    let gitCommandTimeout: TimeInterval
    let fileWatcherEnabled: Bool
}

/// 集成配置DTO
struct IntegrationConfigDTO: Codable {
    let editors: [EditorConfigDTO]
    let exportFormats: [String]
    let backupEnabled: Bool
    let backupLocation: String?
}

/// 编辑器配置DTO
struct EditorConfigDTO: Identifiable, Codable {
    let id: UUID
    let name: String
    let command: String
    let arguments: [String]
    let isDefault: Bool
    let isAvailable: Bool           // 系统中是否可用
}

// MARK: - 系统状态DTO

/// 系统状态DTO
struct SystemStatusDTO: Codable {
    let healthy: Bool
    let components: [ComponentStatusDTO]
    let performance: SystemPerformanceDTO
    let lastCheck: Date
}

/// 组件状态DTO
struct ComponentStatusDTO: Codable {
    let name: String
    let healthy: Bool
    let message: String?
    let details: [String: String]?
}

/// 系统性能DTO
struct SystemPerformanceDTO: Codable {
    let memoryUsage: UInt64
    let cpuUsage: Double
    let diskUsage: DiskUsageDTO
    let cacheHitRate: Double
    let averageResponseTime: TimeInterval
}

/// 磁盘使用DTO
struct DiskUsageDTO: Codable {
    let totalSpace: UInt64
    let usedSpace: UInt64
    let freeSpace: UInt64
    let formattedUsed: String
    let formattedFree: String
    let usagePercentage: Double
}

// MARK: - 导入导出DTO

/// 导出请求DTO
struct ExportRequestDTO: Codable {
    let format: ExportFormatDTO
    let includeData: ExportDataOptionsDTO
    let destination: String?
    let compression: Bool
}

enum ExportFormatDTO: String, Codable {
    case json = "json"
    case csv = "csv"
    case xml = "xml"
}

struct ExportDataOptionsDTO: Codable {
    let projects: Bool
    let tags: Bool
    let configuration: Bool
    let statistics: Bool
}

/// 导入请求DTO
struct ImportRequestDTO: Codable {
    let source: String
    let format: ExportFormatDTO
    let mergeStrategy: ImportMergeStrategyDTO
    let validateData: Bool
}

enum ImportMergeStrategyDTO: String, Codable {
    case replace = "replace"        // 替换现有数据
    case merge = "merge"           // 合并数据
    case skip = "skip"             // 跳过冲突项
}

/// 批量操作DTO
struct BatchOperationRequestDTO: Codable {
    let operation: BatchOperationTypeDTO
    let projectIds: [UUID]
    let parameters: [String: String]?
}

enum BatchOperationTypeDTO: String, Codable {
    case addTag = "addTag"
    case removeTag = "removeTag"
    case move = "move"
    case delete = "delete"
    case refresh = "refresh"
}

// MARK: - 扩展和工具

extension OperationResultDTO {
    /// 创建空数据的成功结果
    static func success(message: String = "操作成功", operation: String = "") -> OperationResultDTO<EmptyDTO> {
        return OperationResultDTO<EmptyDTO>(success: true, code: 0, message: message, data: EmptyDTO(), operation: operation)
    }
}

/// 空数据DTO - 用于不需要返回数据的操作
struct EmptyDTO: Codable {
    // 空结构体，用于类型安全
}

// MARK: - DTO 验证扩展

protocol ValidatableDTO {
    func validate() throws
}

enum DTOValidationError: LocalizedError {
    case invalidField(String)
    case missingRequiredField(String)
    case valueOutOfRange(String, String)
    
    var errorDescription: String? {
        switch self {
        case .invalidField(let field):
            return "字段格式无效: \(field)"
        case .missingRequiredField(let field):
            return "缺少必需字段: \(field)"
        case .valueOutOfRange(let field, let range):
            return "字段值超出范围: \(field), 有效范围: \(range)"
        }
    }
}

// MARK: - DTO 版本管理

/// DTO版本信息
struct DTOVersionInfo {
    static let version = "1.0.0"
    static let compatibleVersions = ["1.0.0"]
    static let lastUpdated = "2024-08-25"
}