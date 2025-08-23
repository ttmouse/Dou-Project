import Foundation
import SwiftUI

/// DataImporter - 数据导入器
/// 
/// 负责从备份文件导入项目数据，支持多种导入策略和冲突处理
class DataImporter {
    
    // MARK: - 导入选项
    
    enum ImportStrategy {
        case merge          // 合并：保留现有数据，添加新数据
        case replace        // 替换：完全替换现有数据
        case skipExisting   // 跳过：仅添加不存在的项目
    }
    
    enum ConflictResolution {
        case keepExisting   // 保留现有数据
        case useImported    // 使用导入数据
        case mergeData      // 合并数据（标签合并，其他字段使用最新）
    }
    
    // MARK: - 导入结果
    
    struct ImportResult {
        let totalProjects: Int
        let importedProjects: Int
        let skippedProjects: Int
        let conflictedProjects: Int
        let newTags: Set<String>
        let errors: [ImportError]
        
        var isSuccessful: Bool {
            return errors.isEmpty && importedProjects > 0
        }
    }
    
    struct ImportError: Error {
        let projectId: String?
        let projectName: String?
        let message: String
        
        var localizedDescription: String {
            if let name = projectName {
                return "项目 '\(name)': \(message)"
            } else if let id = projectId {
                return "项目 ID '\(id)': \(message)"
            }
            return message
        }
    }
    
    // MARK: - 备份数据结构
    
    private struct BackupProject: Codable {
        let id: String
        let name: String
        let path: String
        let tags: [String]
        let mtime: TimeInterval?
        let size: Int64?
        let created: TimeInterval
        let git_commits: Int?
        let git_last_commit: TimeInterval?
        let checksum: String?
        let checked: TimeInterval?
    }
    
    // MARK: - 属性
    
    private let tagManager: TagManager
    private let storage: TagStorage
    
    // MARK: - 初始化
    
    init(tagManager: TagManager, storage: TagStorage) {
        self.tagManager = tagManager
        self.storage = storage
    }
    
    // MARK: - 公共方法
    
    /// 从文件导入数据
    func importFromFile(
        _ fileURL: URL,
        strategy: ImportStrategy = .merge,
        conflictResolution: ConflictResolution = .mergeData
    ) -> ImportResult {
        do {
            // 读取文件数据
            let data = try Data(contentsOf: fileURL)
            return importFromData(data, strategy: strategy, conflictResolution: conflictResolution)
        } catch {
            return ImportResult(
                totalProjects: 0,
                importedProjects: 0,
                skippedProjects: 0,
                conflictedProjects: 0,
                newTags: [],
                errors: [ImportError(
                    projectId: nil,
                    projectName: nil,
                    message: "无法读取文件: \(error.localizedDescription)"
                )]
            )
        }
    }
    
    /// 从数据导入
    func importFromData(
        _ data: Data,
        strategy: ImportStrategy = .merge,
        conflictResolution: ConflictResolution = .mergeData
    ) -> ImportResult {
        var errors: [ImportError] = []
        var importedCount = 0
        var skippedCount = 0
        var conflictCount = 0
        var newTags: Set<String> = []
        
        do {
            // 解析JSON数据
            let backupProjects = try JSONDecoder().decode([BackupProject].self, from: data)
            print("解析到 \(backupProjects.count) 个备份项目")
            
            // 如果是替换策略，先清空现有数据
            if strategy == .replace {
                clearExistingData()
            }
            
            // 处理每个项目
            for backupProject in backupProjects {
                let result = processProject(
                    backupProject,
                    strategy: strategy,
                    conflictResolution: conflictResolution
                )
                
                switch result {
                case .imported(let tags):
                    importedCount += 1
                    newTags.formUnion(tags)
                case .skipped:
                    skippedCount += 1
                case .conflicted(let tags):
                    conflictCount += 1
                    newTags.formUnion(tags)
                case .error(let error):
                    errors.append(error)
                }
            }
            
            // 保存导入的数据
            if importedCount > 0 || conflictCount > 0 {
                saveImportedData()
                print("导入完成: \(importedCount) 个项目，\(skippedCount) 个跳过，\(conflictCount) 个冲突")
            }
            
        } catch {
            errors.append(ImportError(
                projectId: nil,
                projectName: nil,
                message: "JSON解析失败: \(error.localizedDescription)"
            ))
        }
        
        return ImportResult(
            totalProjects: errors.isEmpty ? importedCount + skippedCount + conflictCount : 0,
            importedProjects: importedCount,
            skippedProjects: skippedCount,
            conflictedProjects: conflictCount,
            newTags: newTags,
            errors: errors
        )
    }
    
    // MARK: - 私有方法
    
    /// 处理单个项目的导入结果
    private enum ProjectImportResult {
        case imported(tags: Set<String>)
        case skipped
        case conflicted(tags: Set<String>)
        case error(ImportError)
    }
    
    private func processProject(
        _ backupProject: BackupProject,
        strategy: ImportStrategy,
        conflictResolution: ConflictResolution
    ) -> ProjectImportResult {
        // 验证数据
        guard let projectId = UUID(uuidString: backupProject.id) else {
            return .error(ImportError(
                projectId: backupProject.id,
                projectName: backupProject.name,
                message: "无效的项目ID格式"
            ))
        }
        
        guard !backupProject.name.isEmpty else {
            return .error(ImportError(
                projectId: backupProject.id,
                projectName: nil,
                message: "项目名称为空"
            ))
        }
        
        guard !backupProject.path.isEmpty else {
            return .error(ImportError(
                projectId: backupProject.id,
                projectName: backupProject.name,
                message: "项目路径为空"
            ))
        }
        
        // 检查是否已存在
        let existingProject = tagManager.projects[projectId]
        
        if let existing = existingProject {
            // 处理冲突
            switch strategy {
            case .skipExisting:
                return .skipped
            case .merge, .replace:
                return handleConflict(
                    existing: existing,
                    backup: backupProject,
                    resolution: conflictResolution
                )
            }
        } else {
            // 新项目，直接导入
            return importNewProject(backupProject, projectId: projectId)
        }
    }
    
    private func handleConflict(
        existing: Project,
        backup: BackupProject,
        resolution: ConflictResolution
    ) -> ProjectImportResult {
        let backupTags = Set(backup.tags)
        
        switch resolution {
        case .keepExisting:
            return .skipped
            
        case .useImported:
            let updatedProject = createProjectFromBackup(backup, projectId: existing.id)
            tagManager.projects[existing.id] = updatedProject
            return .conflicted(tags: backupTags)
            
        case .mergeData:
            // 合并标签
            let mergedTags = existing.tags.union(backupTags)
            
            // 创建合并后的项目（保留现有项目的基本信息，但更新标签和Git信息）
            var mergedProject = existing
            mergedProject.tags = mergedTags
            
            // Git信息通过gitInfo获取，这里不需要特殊处理
            // 因为Project的gitInfo是在初始化时从文件系统加载的
            
            tagManager.projects[existing.id] = mergedProject
            return .conflicted(tags: backupTags)
        }
    }
    
    private func importNewProject(_ backup: BackupProject, projectId: UUID) -> ProjectImportResult {
        let project = createProjectFromBackup(backup, projectId: projectId)
        tagManager.projects[projectId] = project
        
        let projectTags = Set(backup.tags)
        return .imported(tags: projectTags)
    }
    
    private func createProjectFromBackup(_ backup: BackupProject, projectId: UUID) -> Project {        
        return Project(
            id: projectId,
            name: backup.name,
            path: backup.path,
            lastModified: convertTimestamp(backup.mtime) ?? convertTimestamp(backup.created) ?? Date(),
            tags: Set(backup.tags)
        )
    }
    
    /// 智能转换时间戳，自动判断是Unix时间戳还是Mac纪元时间戳
    private func convertTimestamp(_ timestamp: TimeInterval?) -> Date? {
        guard let timestamp = timestamp, timestamp > 0 else { return nil }
        
        // 使用978307200作为分界点（2001年1月1日的Unix时间戳）
        // 大于此值的认为是Unix时间戳，小于的认为是Mac纪元时间戳
        if timestamp > 978307200 {
            return Date(timeIntervalSince1970: timestamp)
        } else {
            return Date(timeIntervalSinceReferenceDate: timestamp)
        }
    }
    
    private func clearExistingData() {
        tagManager.projects.removeAll()
        tagManager.allTags.removeAll()
        print("已清空现有数据")
    }
    
    private func saveImportedData() {
        // 更新标签集合
        var allTags: Set<String> = tagManager.allTags
        for project in tagManager.projects.values {
            allTags.formUnion(project.tags)
        }
        tagManager.allTags = allTags
        
        // 初始化新标签的颜色 - 通过私有方法调用
        tagManager.objectWillChange.send()
        
        // 为新标签分配颜色
        for tag in allTags {
            if tagManager.colorManager.getColor(for: tag) == nil {
                let hash = abs(tag.hashValue)
                let colorIndex = hash % AppTheme.tagPresetColors.count
                let color = AppTheme.tagPresetColors[colorIndex].color
                tagManager.colorManager.setColor(color, for: tag)
            }
        }
        
        // 保存到存储
        tagManager.saveAll(force: true)
        
        print("数据导入完成并保存")
    }
}

// MARK: - TagManager 扩展

extension TagManager {
    /// 导入数据的公共接口
    func importData(
        from fileURL: URL,
        strategy: DataImporter.ImportStrategy = .merge,
        conflictResolution: DataImporter.ConflictResolution = .mergeData
    ) -> DataImporter.ImportResult {
        let importer = DataImporter(tagManager: self, storage: storage)
        let result = importer.importFromFile(
            fileURL,
            strategy: strategy,
            conflictResolution: conflictResolution
        )
        
        // 导入成功后刷新UI
        if result.isSuccessful {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
        
        return result
    }
}