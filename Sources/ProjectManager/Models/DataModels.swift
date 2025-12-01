import Foundation
import SwiftUI

// MARK: - 纯数据模型层
// 遵循"数据与逻辑分离"原则，这些结构只包含数据，不包含业务逻辑

/// 项目数据模型 - 扁平结构纯数据，无业务逻辑
struct ProjectData: Identifiable, Equatable, Codable {
    // 核心标识
    let id: UUID
    let name: String
    let path: String
    let tags: Set<String>
    
    // 文件系统信息 (扁平化)
    let mtime: Date              // 修改时间 (统一字段)
    let size: Int64              // 文件大小
    let checksum: String         // SHA256格式: "sha256:deadbeef..."
    
    // Git信息 (扁平化)
    let git_commits: Int         // 总提交数
    let git_last_commit: Date    // 最后提交时间
    let git_daily: String?       // 每日提交统计: "2025-08-25:3,2025-08-24:5"
    
    // 启动配置
    let startupCommand: String?  // 自定义启动命令
    let customPort: Int?         // 自定义端口
    
    // 元数据
    let created: Date            // 首次发现时间
    let checked: Date            // 最后检查时间
    
    // MARK: - 向后兼容属性
    /// 为了向后兼容BusinessLogic层，保留原有字段访问方式
    var lastModified: Date { mtime }
    var gitInfo: GitInfoData? {
        guard git_commits > 0 else { return nil }
        return GitInfoData(commitCount: git_commits, lastCommitDate: git_last_commit)
    }
    var fileSystemInfo: FileSystemInfoData {
        return FileSystemInfoData(
            modificationDate: mtime,
            size: UInt64(size),
            checksum: checksum,
            lastCheckTime: checked
        )
    }
    
    /// 向后兼容的嵌套结构定义
    struct GitInfoData: Codable, Equatable {
        let commitCount: Int
        let lastCommitDate: Date
    }
    
    struct FileSystemInfoData: Codable, Equatable {
        let modificationDate: Date
        let size: UInt64
        let checksum: String
        let lastCheckTime: Date
        
        static let checkInterval: TimeInterval = 300  // 5分钟检查间隔
    }
    
    /// 从Project转换为ProjectData
    init(from project: Project) {
        self.id = project.id
        self.name = project.name
        self.path = project.path
        self.tags = project.tags
        self.mtime = project.mtime
        self.size = project.size
        self.checksum = project.checksum
        self.git_commits = project.git_commits
        self.git_last_commit = project.git_last_commit
        self.git_daily = project.git_daily
        self.startupCommand = project.startupCommand
        self.customPort = project.customPort
        self.created = project.created
        self.checked = project.checked
    }
    
    /// 扁平结构初始化器
    init(
        id: UUID,
        name: String,
        path: String,
        tags: Set<String>,
        mtime: Date,
        size: Int64,
        checksum: String,
        git_commits: Int,
        git_last_commit: Date,
        git_daily: String? = nil,
        startupCommand: String? = nil,
        customPort: Int? = nil,
        created: Date,
        checked: Date
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.tags = tags
        self.mtime = mtime
        self.size = size
        self.checksum = checksum
        self.git_commits = git_commits
        self.git_last_commit = git_last_commit
        self.git_daily = git_daily
        self.startupCommand = startupCommand
        self.customPort = customPort
        self.created = created
        self.checked = checked
    }
    
    /// 向后兼容的初始化器 - 用于BusinessLogic层
    @available(*, deprecated, message: "使用扁平结构的新初始化器")
    init(
        id: UUID,
        name: String,
        path: String,
        lastModified: Date,
        tags: Set<String>,
        gitInfo: GitInfoData? = nil,
        fileSystemInfo: FileSystemInfoData
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.tags = tags
        self.mtime = lastModified
        self.size = Int64(fileSystemInfo.size)
        self.checksum = fileSystemInfo.checksum
        self.git_commits = gitInfo?.commitCount ?? 0
        self.git_last_commit = gitInfo?.lastCommitDate ?? Date.distantPast
        self.git_daily = nil
        self.startupCommand = nil
        self.customPort = nil
        self.created = fileSystemInfo.lastCheckTime
        self.checked = fileSystemInfo.lastCheckTime
    }
}

/// 标签数据模型 - 纯数据
struct TagData: Identifiable, Equatable, Codable {
    let id: String  // 标签名作为ID
    let name: String
    let color: TagColorData
    let usageCount: Int
    let isHidden: Bool
    let isSystemTag: Bool
    
    var displayName: String {
        name
    }
}

/// 标签颜色数据模型
struct TagColorData: Equatable, Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    
    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    // 与SwiftUI Color的转换
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
    
    init(from color: Color) {
        // 简化处理，实际应用中可能需要更复杂的颜色提取
        self.red = 0.5
        self.green = 0.5
        self.blue = 0.8
        self.alpha = 1.0
    }
}

/// 筛选条件数据模型 - 纯数据
struct FilterData: Equatable, Codable {
    let selectedTags: Set<String>
    let searchText: String
    let sortCriteria: SortCriteriaData
    let isAscending: Bool
    let hiddenTags: Set<String>
    
    static let empty = FilterData(
        selectedTags: [],
        searchText: "",
        sortCriteria: .lastModified,
        isAscending: false,
        hiddenTags: []
    )
}

/// 排序条件数据模型
enum SortCriteriaData: String, CaseIterable, Codable {
    case name = "name"
    case lastModified = "lastModified"
    case gitCommits = "gitCommits"
    
    var displayName: String {
        switch self {
        case .name: return "名称"
        case .lastModified: return "修改时间"
        case .gitCommits: return "Git提交数"
        }
    }
}

/// 应用状态数据模型 - 包含所有应用状态的纯数据
struct AppStateData: Equatable, Codable {
    let projects: [UUID: ProjectData]
    let tags: [String: TagData] 
    let watchedDirectories: Set<String>
    let filter: FilterData
    let selectedProjectIds: Set<UUID>
    
    static let empty = AppStateData(
        projects: [:],
        tags: [:],
        watchedDirectories: [],
        filter: .empty,
        selectedProjectIds: []
    )
}

/// 配置数据模型
struct ConfigData: Codable {
    let enableAutoIncrementalUpdate: Bool
    let tagColorPresets: [TagColorData]
    let defaultSortCriteria: SortCriteriaData
    let checkInterval: TimeInterval
    
    static let defaultConfig = ConfigData(
        enableAutoIncrementalUpdate: false,
        tagColorPresets: [],
        defaultSortCriteria: .lastModified,
        checkInterval: 300
    )
}