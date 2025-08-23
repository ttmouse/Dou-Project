import Foundation
import SwiftUI

// MARK: - 纯数据模型层
// 遵循"数据与逻辑分离"原则，这些结构只包含数据，不包含业务逻辑

/// 项目数据模型 - 纯数据，无业务逻辑
struct ProjectData: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let path: String
    let lastModified: Date
    let tags: Set<String>
    let gitInfo: GitInfoData?
    let fileSystemInfo: FileSystemInfoData
    
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