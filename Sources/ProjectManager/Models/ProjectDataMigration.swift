import Foundation

/// 项目数据迁移工具
/// 
/// 负责将旧的嵌套结构数据迁移到新的扁平结构
/// 支持自动检测数据格式并进行适当的迁移处理
struct ProjectDataMigration {
    
    /// 旧版本的项目结构定义（用于迁移）
    struct LegacyProject: Codable {
        let id: UUID
        let name: String
        let path: String
        let lastModified: Date
        let tags: Set<String>
        let gitInfo: LegacyGitInfo?
        let fileSystemInfo: LegacyFileSystemInfo
        
        struct LegacyGitInfo: Codable {
            let commitCount: Int
            let lastCommitDate: Date
        }
        
        struct LegacyFileSystemInfo: Codable {
            let modificationDate: Date
            let size: UInt64
            let checksum: String
            let lastCheckTime: Date
        }
    }
    
    /// 迁移单个项目数据
    /// - Parameter legacyProject: 旧版本项目数据
    /// - Returns: 新的扁平结构项目数据
    static func migrate(_ legacyProject: LegacyProject) -> Project {
        return Project(
            id: legacyProject.id,
            name: legacyProject.name,
            path: legacyProject.path,
            tags: legacyProject.tags,
            mtime: legacyProject.lastModified,
            size: Int64(legacyProject.fileSystemInfo.size),
            checksum: legacyProject.fileSystemInfo.checksum,
            git_commits: legacyProject.gitInfo?.commitCount ?? 0,
            git_last_commit: legacyProject.gitInfo?.lastCommitDate ?? Date.distantPast,
            git_daily: nil, // 旧数据没有多天统计
            created: legacyProject.fileSystemInfo.lastCheckTime,
            checked: Date()
        )
    }
    
    /// 批量迁移项目数据
    /// - Parameter legacyProjects: 旧版本项目数组
    /// - Returns: 新的扁平结构项目字典
    static func migrate(_ legacyProjects: [LegacyProject]) -> [UUID: Project] {
        var result: [UUID: Project] = [:]
        
        for legacyProject in legacyProjects {
            let newProject = migrate(legacyProject)
            result[newProject.id] = newProject
        }
        
        return result
    }
    
    /// 从JSON数据迁移项目
    /// - Parameter jsonData: 包含旧格式项目数据的JSON
    /// - Returns: 迁移后的项目字典，如果迁移失败则返回空字典
    static func migrateFromJSON(_ jsonData: Data) -> [UUID: Project] {
        do {
            // 首先尝试解析为旧格式
            let legacyProjects = try JSONDecoder().decode([LegacyProject].self, from: jsonData)
            print("🔄 检测到旧格式数据，正在迁移 \(legacyProjects.count) 个项目...")
            
            let migratedProjects = migrate(legacyProjects)
            print("✅ 成功迁移 \(migratedProjects.count) 个项目到扁平结构")
            
            return migratedProjects
        } catch {
            // 如果旧格式解析失败，尝试新格式
            do {
                let newProjects = try JSONDecoder().decode([Project].self, from: jsonData)
                print("✅ 检测到新格式数据，无需迁移")
                
                var result: [UUID: Project] = [:]
                for project in newProjects {
                    result[project.id] = project
                }
                return result
            } catch {
                print("❌ 数据迁移失败: \(error)")
                return [:]
            }
        }
    }
    
    /// 检查数据格式版本
    /// - Parameter jsonData: JSON数据
    /// - Returns: 数据格式版本描述
    static func detectDataVersion(_ jsonData: Data) -> DataVersion {
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]],
               let firstProject = json.first {
                
                if firstProject.keys.contains("mtime") {
                    return .flatStructure
                } else if firstProject.keys.contains("gitInfo") || firstProject.keys.contains("fileSystemInfo") {
                    return .nestedStructure
                } else {
                    return .unknown
                }
            }
        } catch {
            // JSON解析失败
        }
        
        return .invalid
    }
    
    enum DataVersion {
        case flatStructure    // 新的扁平结构
        case nestedStructure  // 旧的嵌套结构
        case unknown          // 未知格式
        case invalid          // 无效数据
        
        var description: String {
            switch self {
            case .flatStructure:
                return "扁平结构 (v2.0+)"
            case .nestedStructure:
                return "嵌套结构 (v1.x)"
            case .unknown:
                return "未知格式"
            case .invalid:
                return "无效数据"
            }
        }
    }
}