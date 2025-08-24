import Foundation
import SwiftUI

/// 标签数据备份管理器
/// 
/// 功能：
/// 1. 备份所有标签相关数据到指定位置
/// 2. 包含项目标签、颜色配置、隐藏状态等完整信息
/// 3. 支持时间戳和自定义名称的备份文件
/// 4. 生成人类可读的备份报告
class TagDataBackup {
    
    // MARK: - 数据结构定义
    
    /// 导入策略
    enum ImportStrategy {
        case merge      // 合并：新标签添加，已存在标签保持不变
        case replace    // 替换：完全替换现有数据
        case addOnly    // 仅添加：只导入新标签，不修改现有内容
    }
    
    /// 导入结果
    struct ImportResult {
        var addedTags = 0
        var updatedTags = 0
        var skippedTags = 0
        var addedColors = 0
        var importedProjects = 0
        
        var summary: String {
            return """
            导入结果：
            - 新增标签: \(addedTags)
            - 更新标签: \(updatedTags)  
            - 跳过标签: \(skippedTags)
            - 导入颜色: \(addedColors)
            - 导入项目标签: \(importedProjects)
            """
        }
    }
    
    // MARK: - 备份数据结构
    
    /// 完整的标签备份数据结构
    struct BackupData: Codable {
        let version: String = "1.0"
        let backupDate: Date
        let deviceInfo: DeviceInfo
        let tagData: TagData
        let projectData: ProjectData
        let statistics: BackupStatistics
        
        struct DeviceInfo: Codable {
            let machineName: String
            let systemVersion: String
            let appVersion: String
        }
        
        struct TagData: Codable {
            let allTags: [String]
            let tagColors: [String: ColorComponents]
            let hiddenTags: [String]
            let systemTagMapping: [String: String]
        }
        
        struct ProjectData: Codable {
            let totalProjects: Int
            let projectTagMappings: [String: ProjectTagInfo] // projectId -> tag info
        }
        
        struct ProjectTagInfo: Codable {
            let projectName: String
            let projectPath: String
            let tags: [String]
            let lastModified: Date
        }
        
        struct BackupStatistics: Codable {
            let totalTags: Int
            let totalProjects: Int
            let taggedProjects: Int
            let untaggedProjects: Int
            let tagUsageCount: [String: Int]
            let mostUsedTags: [String]
        }
    }
    
    /// 颜色组件结构（复用TagStorage的定义）
    struct ColorComponents: Codable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }
    
    // MARK: - 主要功能
    
    private let storage: TagStorage
    private let tagManager: TagManager
    
    init(storage: TagStorage, tagManager: TagManager) {
        self.storage = storage
        self.tagManager = tagManager
    }
    
    /// 创建完整的标签数据备份
    func createBackup() -> BackupData {
        print("🔄 开始创建标签数据备份...")
        
        // 收集设备信息
        let deviceInfo = BackupData.DeviceInfo(
            machineName: Host.current().localizedName ?? "Unknown",
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        )
        
        // 收集标签数据
        let tagData = BackupData.TagData(
            allTags: Array(tagManager.allTags).sorted(),
            tagColors: convertColorsToComponents(tagManager.colorManager.tagColors),
            hiddenTags: Array(tagManager.hiddenTags).sorted(),
            systemTagMapping: getSystemTagMapping()
        )
        
        // 收集项目数据
        let projectTagMappings = tagManager.projects.mapValues { project in
            BackupData.ProjectTagInfo(
                projectName: project.name,
                projectPath: project.path,
                tags: Array(project.tags).sorted(),
                lastModified: project.lastModified
            )
        }
        
        let projectData = BackupData.ProjectData(
            totalProjects: tagManager.projects.count,
            projectTagMappings: projectTagMappings.mapKeys { $0.uuidString }
        )
        
        // 生成统计信息
        let statistics = generateStatistics()
        
        let backupData = BackupData(
            backupDate: Date(),
            deviceInfo: deviceInfo,
            tagData: tagData,
            projectData: projectData,
            statistics: statistics
        )
        
        print("✅ 备份数据创建完成")
        print("   - 标签总数: \(statistics.totalTags)")
        print("   - 项目总数: \(statistics.totalProjects)")
        print("   - 已标记项目: \(statistics.taggedProjects)")
        
        return backupData
    }
    
    /// 将备份保存到指定文件
    func saveBackupToFile(_ backupData: BackupData, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(backupData)
        try jsonData.write(to: url)
        
        print("💾 备份已保存到: \(url.path)")
    }
    
    /// 从备份文件导入标签数据
    func importBackupFromFile(at url: URL, strategy: ImportStrategy = .merge) throws -> ImportResult {
        print("🔄 开始从备份文件导入数据: \(url.path)")
        
        // 读取备份文件
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let backupData = try decoder.decode(BackupData.self, from: data)
        print("✅ 备份文件解析成功，版本: \(backupData.version)")
        
        // 执行导入
        return try performImport(backupData, strategy: strategy)
    }
    
    /// 执行具体的导入操作
    private func performImport(_ backupData: BackupData, strategy: ImportStrategy) throws -> ImportResult {
        var result = ImportResult()
        
        switch strategy {
        case .merge:
            result = try performMergeImport(backupData)
        case .replace:
            result = try performReplaceImport(backupData)
        case .addOnly:
            result = try performAddOnlyImport(backupData)
        }
        
        // 保存所有更改
        tagManager.saveAll(force: true)
        
        print("✅ 导入完成:")
        print("   - 新增标签: \(result.addedTags)")
        print("   - 更新标签: \(result.updatedTags)")
        print("   - 跳过标签: \(result.skippedTags)")
        print("   - 导入项目标签: \(result.importedProjects)")
        
        return result
    }
    
    /// 合并导入策略 - 新标签添加，已存在标签保持不变 (批量优化版本)
    private func performMergeImport(_ backupData: BackupData) throws -> ImportResult {
        var result = ImportResult()
        
        print("🔄 开始批量合并导入...")
        
        // 1. 批量导入标签 - 使用集合操作
        let existingTags = tagManager.allTags
        let newTags = Set(backupData.tagData.allTags)
        let tagsToAdd = newTags.subtracting(existingTags)
        
        tagManager.allTags.formUnion(tagsToAdd)
        result.addedTags = tagsToAdd.count
        result.skippedTags = newTags.intersection(existingTags).count
        print("✅ 标签批量合并完成: +\(tagsToAdd.count) 个新标签, 跳过 \(result.skippedTags) 个")
        
        // 2. 批量导入标签颜色 - 收集新颜色后批量设置
        var colorsToAdd: [String: Color] = [:]
        for (tag, colorComponents) in backupData.tagData.tagColors {
            if tagManager.colorManager.getColor(for: tag) == nil {
                let color = convertComponentsToColor(colorComponents)
                colorsToAdd[tag] = color
                result.addedColors += 1
            }
        }
        
        // 批量更新颜色
        for (tag, color) in colorsToAdd {
            tagManager.colorManager.setColor(color, for: tag)
        }
        print("✅ 颜色批量合并完成: +\(colorsToAdd.count) 个新颜色")
        
        // 3. 批量导入项目标签 - 构建更新后的项目对象
        print("🔄 开始批量合并项目标签...")
        
        var updatedProjects: [UUID: Project] = [:]
        var projectsToUpdate = 0
        
        for (projectIdString, projectTagInfo) in backupData.projectData.projectTagMappings {
            if let projectId = UUID(uuidString: projectIdString),
               let existingProject = tagManager.projects[projectId] {
                
                let existingTags = existingProject.tags
                let backupTags = Set(projectTagInfo.tags)
                let tagsToAdd = backupTags.subtracting(existingTags)
                
                if !tagsToAdd.isEmpty {
                    // 创建合并标签后的项目对象
                    let mergedTags = existingTags.union(tagsToAdd)
                    let updatedProject = Project(
                        id: existingProject.id,
                        name: existingProject.name,
                        path: existingProject.path,
                        lastModified: existingProject.lastModified,
                        tags: mergedTags
                    )
                    updatedProjects[projectId] = updatedProject
                    projectsToUpdate += 1
                }
            }
        }
        
        // 批量更新TagManager中的项目
        for (projectId, updatedProject) in updatedProjects {
            tagManager.projects[projectId] = updatedProject
        }
        
        // 批量更新排序管理器 - 只有在有更新时才重新排序
        if projectsToUpdate > 0 {
            let allProjects = Array(tagManager.projects.values)
            tagManager.sortManager.updateSortedProjects(allProjects)
        }
        
        result.importedProjects = projectsToUpdate
        print("✅ 项目标签批量合并完成: \(projectsToUpdate) 个项目更新")
        
        print("🎉 批量合并导入完成!")
        return result
    }
    
    /// 替换导入策略 - 完全替换现有数据 (批量优化版本)
    private func performReplaceImport(_ backupData: BackupData) throws -> ImportResult {
        var result = ImportResult()
        
        print("🔄 开始批量替换导入...")
        
        // 1. 批量替换所有标签
        let oldTags = tagManager.allTags
        tagManager.allTags = Set(backupData.tagData.allTags)
        result.addedTags = backupData.tagData.allTags.count - oldTags.count
        result.updatedTags = oldTags.count
        print("✅ 标签批量替换完成: \(oldTags.count) → \(backupData.tagData.allTags.count)")
        
        // 2. 批量替换标签颜色 - 直接替换整个颜色字典
        var newColors: [String: Color] = [:]
        for (tag, colorComponents) in backupData.tagData.tagColors {
            let color = convertComponentsToColor(colorComponents)
            newColors[tag] = color
            result.addedColors += 1
        }
        // 批量更新颜色管理器
        for (tag, color) in newColors {
            tagManager.colorManager.setColor(color, for: tag)
        }
        print("✅ 颜色批量替换完成: \(newColors.count) 个颜色")
        
        // 3. 批量替换隐藏标签状态
        tagManager.hiddenTags = Set(backupData.tagData.hiddenTags)
        print("✅ 隐藏标签状态批量替换完成")
        
        // 4. 批量清空和重建项目标签 - 避免逐个调用TagManager方法
        print("🔄 开始批量重建项目标签...")
        
        // 4.1 批量清空所有项目标签 - 直接修改Project对象
        var clearedProjects: [UUID: Project] = [:]
        for (projectId, project) in tagManager.projects {
            let clearedProject = Project(
                id: project.id,
                name: project.name,
                path: project.path,
                lastModified: project.lastModified,
                tags: [] // 清空标签
            )
            clearedProjects[projectId] = clearedProject
        }
        
        // 4.2 批量导入项目标签 - 构建新的项目对象
        var rebuiltProjects: [UUID: Project] = [:]
        var matchedProjects = 0
        
        for (projectIdString, projectTagInfo) in backupData.projectData.projectTagMappings {
            if let projectId = UUID(uuidString: projectIdString),
               let clearedProject = clearedProjects[projectId] {
                
                // 创建带有备份标签的项目对象
                let rebuiltProject = Project(
                    id: clearedProject.id,
                    name: clearedProject.name,
                    path: clearedProject.path,
                    lastModified: clearedProject.lastModified,
                    tags: Set(projectTagInfo.tags)
                )
                rebuiltProjects[projectId] = rebuiltProject
                matchedProjects += 1
            }
        }
        
        // 4.3 批量更新TagManager中的项目 - 一次性替换
        for (projectId, clearedProject) in clearedProjects {
            if let rebuiltProject = rebuiltProjects[projectId] {
                tagManager.projects[projectId] = rebuiltProject
            } else {
                // 如果备份中没有这个项目，保持清空状态
                tagManager.projects[projectId] = clearedProject
            }
        }
        
        // 4.4 批量更新排序管理器
        let allProjects = Array(tagManager.projects.values)
        tagManager.sortManager.updateSortedProjects(allProjects)
        
        result.importedProjects = matchedProjects
        print("✅ 项目标签批量重建完成: \(matchedProjects) 个项目")
        
        print("🎉 批量替换导入完成!")
        return result
    }
    
    /// 仅添加导入策略 - 只导入新标签，不修改现有内容
    private func performAddOnlyImport(_ backupData: BackupData) throws -> ImportResult {
        var result = ImportResult()
        
        // 只添加不存在的标签
        for tag in backupData.tagData.allTags {
            if !tagManager.allTags.contains(tag) {
                tagManager.allTags.insert(tag)
                
                // 同时导入颜色（如果有的话）
                if let colorComponents = backupData.tagData.tagColors[tag] {
                    let color = convertComponentsToColor(colorComponents)
                    tagManager.colorManager.setColor(color, for: tag)
                    result.addedColors += 1
                }
                
                result.addedTags += 1
            } else {
                result.skippedTags += 1
            }
        }
        
        return result
    }
    
    /// 生成备份报告（人类可读）
    func generateBackupReport(_ backupData: BackupData) -> String {
        var report = """
        📊 标签数据备份报告
        ==================
        
        备份信息：
        - 备份时间: \(formatDate(backupData.backupDate))
        - 设备名称: \(backupData.deviceInfo.machineName)
        - 系统版本: \(backupData.deviceInfo.systemVersion)
        - 应用版本: \(backupData.deviceInfo.appVersion)
        
        数据统计：
        - 标签总数: \(backupData.statistics.totalTags)
        - 项目总数: \(backupData.statistics.totalProjects)
        - 已标记项目: \(backupData.statistics.taggedProjects)
        - 未标记项目: \(backupData.statistics.untaggedProjects)
        - 隐藏标签数: \(backupData.tagData.hiddenTags.count)
        
        """
        
        // 添加最常用标签
        if !backupData.statistics.mostUsedTags.isEmpty {
            report += "最常用标签：\n"
            for (index, tag) in backupData.statistics.mostUsedTags.enumerated() {
                let count = backupData.statistics.tagUsageCount[tag] ?? 0
                report += "  \(index + 1). \(tag) (使用 \(count) 次)\n"
            }
            report += "\n"
        }
        
        // 添加所有标签列表
        report += "所有标签列表：\n"
        for tag in backupData.tagData.allTags {
            let count = backupData.statistics.tagUsageCount[tag] ?? 0
            let isHidden = backupData.tagData.hiddenTags.contains(tag) ? " [隐藏]" : ""
            report += "  - \(tag) (使用 \(count) 次)\(isHidden)\n"
        }
        
        return report
    }
    
    /// 一键备份到桌面（带时间戳）
    func quickBackupToDesktop() -> URL? {
        do {
            let backupData = createBackup()
            
            // 生成带时间戳的文件名
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            let filename = "ProjectManager_TagsBackup_\(timestamp).json"
            
            // 保存到桌面
            let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let backupURL = desktopURL.appendingPathComponent(filename)
            
            try saveBackupToFile(backupData, to: backupURL)
            
            // 同时生成报告文件
            let reportFilename = "ProjectManager_TagsReport_\(timestamp).txt"
            let reportURL = desktopURL.appendingPathComponent(reportFilename)
            let report = generateBackupReport(backupData)
            try report.write(to: reportURL, atomically: true, encoding: .utf8)
            
            print("📋 备份报告已保存到: \(reportURL.path)")
            
            return backupURL
        } catch {
            print("❌ 备份失败: \(error)")
            return nil
        }
    }
    
    // MARK: - 辅助方法
    
    private func convertColorsToComponents(_ colors: [String: Color]) -> [String: ColorComponents] {
        return colors.mapValues { color in
            let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
            return ColorComponents(
                red: nsColor.redComponent,
                green: nsColor.greenComponent,
                blue: nsColor.blueComponent,
                alpha: nsColor.alphaComponent
            )
        }
    }
    
    private func convertComponentsToColor(_ components: ColorComponents) -> Color {
        return Color(.sRGB,
                    red: components.red,
                    green: components.green,
                    blue: components.blue,
                    opacity: components.alpha)
    }
    
    private func getSystemTagMapping() -> [String: String] {
        return [
            "green": "绿色", "绿色": "绿色",
            "red": "红色", "红色": "红色",
            "orange": "橙色", "橙色": "橙色",
            "yellow": "黄色", "黄色": "黄色",
            "blue": "蓝色", "蓝色": "蓝色",
            "purple": "紫色", "紫色": "紫色",
            "gray": "灰色", "grey": "灰色", "灰色": "灰色"
        ]
    }
    
    private func generateStatistics() -> BackupData.BackupStatistics {
        let tagUsageCount = tagManager.getAllTagStatistics()
        let mostUsedTags = tagUsageCount.sorted { $0.value > $1.value }.prefix(10).map { $0.key }
        let taggedProjects = tagManager.projects.values.filter { !$0.tags.isEmpty }.count
        
        return BackupData.BackupStatistics(
            totalTags: tagManager.allTags.count,
            totalProjects: tagManager.projects.count,
            taggedProjects: taggedProjects,
            untaggedProjects: tagManager.projects.count - taggedProjects,
            tagUsageCount: tagUsageCount,
            mostUsedTags: Array(mostUsedTags)
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// MARK: - Dictionary扩展

extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        return Dictionary<T, Value>(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
}