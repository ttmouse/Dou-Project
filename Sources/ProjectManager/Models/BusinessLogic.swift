import Foundation
import SwiftUI

// MARK: - 业务逻辑层
// 遵循"数据与逻辑分离"原则，所有业务逻辑都是纯函数，无副作用

/// 项目业务逻辑 - 纯函数集合
enum ProjectLogic {
    
    /// 根据标签筛选项目
    static func filterProjects(
        _ projects: [ProjectData], 
        by tags: Set<String>
    ) -> [ProjectData] {
        if tags.isEmpty || tags.contains("全部") {
            return projects
        }
        
        if tags.contains("没有标签") {
            return projects.filter { $0.tags.isEmpty }
        }
        
        return projects.filter { project in
            !project.tags.isDisjoint(with: tags)
        }
    }
    
    /// 根据搜索文本筛选项目
    static func filterProjects(
        _ projects: [ProjectData],
        by searchText: String
    ) -> [ProjectData] {
        if searchText.isEmpty {
            return projects
        }
        
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(searchText) ||
            project.path.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// 综合筛选项目
    static func filterProjects(
        _ projects: [ProjectData],
        with filter: FilterData
    ) -> [ProjectData] {
        let tagFiltered = filterProjects(projects, by: filter.selectedTags)
        let searchFiltered = filterProjects(tagFiltered, by: filter.searchText)
        let hiddenTagsFiltered = filterProjectsByHiddenTags(searchFiltered, hiddenTags: filter.hiddenTags)
        return hiddenTagsFiltered
    }
    
    /// 根据特定标签过滤项目 - 排除包含"隐藏标签"的项目
    static func filterProjectsByHiddenTags(
        _ projects: [ProjectData],
        hiddenTags: Set<String> = [] // 保留参数兼容性，但不使用
    ) -> [ProjectData] {
        return projects.filter { project in
            // 只检查项目是否包含"隐藏标签"这个特定标签
            return !project.tags.contains("隐藏标签")
        }
    }
    
    /// 排序项目
    static func sortProjects(
        _ projects: [ProjectData],
        by criteria: SortCriteriaData,
        ascending: Bool
    ) -> [ProjectData] {
        return projects.sorted { project1, project2 in
            let result: Bool
            switch criteria {
            case .name:
                result = project1.name.localizedCaseInsensitiveCompare(project2.name) == .orderedAscending
            case .lastModified:
                result = project1.lastModified < project2.lastModified
            case .gitCommits:
                let count1 = project1.gitInfo?.commitCount ?? 0
                let count2 = project2.gitInfo?.commitCount ?? 0
                result = count1 < count2
            }
            return ascending ? result : !result
        }
    }
    
    /// 综合处理：筛选 + 排序
    static func processProjects(
        _ projects: [ProjectData],
        with filter: FilterData
    ) -> [ProjectData] {
        let filtered = filterProjects(projects, with: filter)
        return sortProjects(filtered, by: filter.sortCriteria, ascending: filter.isAscending)
    }
    
    /// 检查项目是否需要更新
    static func needsUpdate(_ project: ProjectData) -> Bool {
        let timeSinceCheck = Date().timeIntervalSince(project.fileSystemInfo.lastCheckTime)
        return timeSinceCheck >= ProjectData.FileSystemInfoData.checkInterval
    }
}

// MARK: - 热力图业务逻辑 (Linus式：简单直接)
enum HeatmapLogic {
    
    /// 热力图数据点 - 保持简单
    struct HeatmapData {
        let date: Date
        let commitCount: Int
        let projects: [ProjectData] // 当天有提交的项目
        
        var intensity: Double {
            // 简单的强度计算：commitCount / 10.0，最大1.0
            min(Double(commitCount) / 10.0, 1.0)
        }
    }
    
    /// 获取最近N天的热力图数据 - Linus式：直接计算，不搞缓存
    static func generateHeatmapData(
        from projects: [ProjectData],
        days: Int = 30
    ) -> [HeatmapData] {
        let calendar = Calendar.current
        let today = Date()
        var heatmapData: [HeatmapData] = []
        
        // 简单直接：遍历每一天
        for dayOffset in 0..<days {
            guard let targetDate = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                continue
            }
            
            // 获取当天开始和结束时间
            let startOfDay = calendar.startOfDay(for: targetDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            
            // 找出当天有提交的项目
            var dailyCommitCount = 0
            var dailyProjects: [ProjectData] = []
            
            for project in projects {
                if let lastCommitDate = project.gitInfo?.lastCommitDate,
                   lastCommitDate >= startOfDay && lastCommitDate < endOfDay {
                    dailyCommitCount += 1 // 简化：每个项目当天算1个提交
                    dailyProjects.append(project)
                }
            }
            
            heatmapData.append(HeatmapData(
                date: startOfDay,
                commitCount: dailyCommitCount,
                projects: dailyProjects
            ))
        }
        
        return heatmapData.reversed() // 最早的日期在前
    }
    
    /// 获取某天的项目列表 - Linus式：简单查找
    static func getProjectsForDate(
        _ targetDate: Date,
        from heatmapData: [HeatmapData]
    ) -> [ProjectData] {
        let calendar = Calendar.current
        for data in heatmapData {
            if calendar.isDate(data.date, inSameDayAs: targetDate) {
                return data.projects
            }
        }
        return []
    }
    
    /// 检查项目是否存在
    static func projectExists(path: String, in projects: [UUID: ProjectData]) -> Bool {
        return projects.values.contains { $0.path == path }
    }
    
    /// 创建项目数据
    static func createProjectData(
        name: String,
        path: String,
        lastModified: Date,
        tags: Set<String> = [],
        gitInfo: ProjectData.GitInfoData? = nil
    ) -> ProjectData {
        return ProjectData(
            id: UUID(),
            name: name,
            path: path,
            lastModified: lastModified,
            tags: tags,
            gitInfo: gitInfo,
            fileSystemInfo: createFileSystemInfo(for: path)
        )
    }
    
    private static func createFileSystemInfo(for path: String) -> ProjectData.FileSystemInfoData {
        let url = URL(fileURLWithPath: path)
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .contentModificationDateKey, .fileSizeKey
            ])
            let modDate = resourceValues.contentModificationDate ?? Date()
            let size = UInt64(resourceValues.fileSize ?? 0)
            let checksum = "\(modDate.timeIntervalSince1970)_\(size)"
            return ProjectData.FileSystemInfoData(
                modificationDate: modDate,
                size: size,
                checksum: checksum,
                lastCheckTime: Date()
            )
        } catch {
            return ProjectData.FileSystemInfoData(
                modificationDate: Date(),
                size: 0,
                checksum: "",
                lastCheckTime: Date()
            )
        }
    }
}

/// 标签业务逻辑 - 纯函数集合
enum TagLogic {
    
    /// 计算标签使用次数
    static func calculateTagUsage(_ projects: [ProjectData]) -> [String: Int] {
        var usage: [String: Int] = [:]
        for project in projects {
            for tag in project.tags {
                usage[tag, default: 0] += 1
            }
        }
        return usage
    }
    
    /// 获取所有标签（包括隐式标签）
    static func getAllTags(from projects: [ProjectData]) -> Set<String> {
        var allTags = Set<String>()
        for project in projects {
            allTags.formUnion(project.tags)
        }
        return allTags
    }
    
    /// 创建标签数据
    static func createTagData(
        name: String,
        color: TagColorData,
        projects: [ProjectData],
        isHidden: Bool = false
    ) -> TagData {
        let usageCount = projects.filter { $0.tags.contains(name) }.count
        return TagData(
            id: name,
            name: name,
            color: color,
            usageCount: usageCount,
            isHidden: isHidden,
            isSystemTag: isSystemTag(name)
        )
    }
    
    /// 更新标签数据
    static func updateTagData(
        _ tagData: TagData,
        projects: [ProjectData],
        newColor: TagColorData? = nil,
        newHidden: Bool? = nil
    ) -> TagData {
        let usageCount = projects.filter { $0.tags.contains(tagData.name) }.count
        return TagData(
            id: tagData.id,
            name: tagData.name,
            color: newColor ?? tagData.color,
            usageCount: usageCount,
            isHidden: newHidden ?? tagData.isHidden,
            isSystemTag: tagData.isSystemTag
        )
    }
    
    /// 生成标签到项目的映射
    static func createTagToProjectsMapping(_ projects: [ProjectData]) -> [String: [ProjectData]] {
        var mapping: [String: [ProjectData]] = [:]
        for project in projects {
            for tag in project.tags {
                mapping[tag, default: []].append(project)
            }
        }
        return mapping
    }
    
    /// 检查是否为系统标签
    static func isSystemTag(_ tagName: String) -> Bool {
        let systemTags = ["绿色", "红色", "橙色", "黄色", "蓝色", "紫色", "灰色"]
        return systemTags.contains(tagName)
    }
    
    /// 为项目添加标签
    static func addTagToProject(_ project: ProjectData, tag: String) -> ProjectData {
        var updatedTags = project.tags
        updatedTags.insert(tag)
        return ProjectData(
            id: project.id,
            name: project.name,
            path: project.path,
            lastModified: project.lastModified,
            tags: updatedTags,
            gitInfo: project.gitInfo,
            fileSystemInfo: project.fileSystemInfo
        )
    }
    
    /// 从项目中移除标签
    static func removeTagFromProject(_ project: ProjectData, tag: String) -> ProjectData {
        var updatedTags = project.tags
        updatedTags.remove(tag)
        return ProjectData(
            id: project.id,
            name: project.name,
            path: project.path,
            lastModified: project.lastModified,
            tags: updatedTags,
            gitInfo: project.gitInfo,
            fileSystemInfo: project.fileSystemInfo
        )
    }
}

/// 筛选业务逻辑 - 纯函数集合
enum FilterLogic {
    
    /// 创建新的筛选条件
    static func createFilter(
        selectedTags: Set<String> = [],
        searchText: String = "",
        sortCriteria: SortCriteriaData = .lastModified,
        isAscending: Bool = false,
        hiddenTags: Set<String> = []
    ) -> FilterData {
        return FilterData(
            selectedTags: selectedTags,
            searchText: searchText,
            sortCriteria: sortCriteria,
            isAscending: isAscending,
            hiddenTags: hiddenTags
        )
    }
    
    /// 更新筛选条件
    static func updateFilter(
        _ filter: FilterData,
        selectedTags: Set<String>? = nil,
        searchText: String? = nil,
        sortCriteria: SortCriteriaData? = nil,
        isAscending: Bool? = nil,
        hiddenTags: Set<String>? = nil
    ) -> FilterData {
        return FilterData(
            selectedTags: selectedTags ?? filter.selectedTags,
            searchText: searchText ?? filter.searchText,
            sortCriteria: sortCriteria ?? filter.sortCriteria,
            isAscending: isAscending ?? filter.isAscending,
            hiddenTags: hiddenTags ?? filter.hiddenTags
        )
    }
    
    /// 切换标签选择状态
    static func toggleTagSelection(_ filter: FilterData, tag: String) -> FilterData {
        var selectedTags = filter.selectedTags
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
        return updateFilter(filter, selectedTags: selectedTags)
    }
    
    /// 切换标签隐藏状态
    static func toggleTagVisibility(_ filter: FilterData, tag: String) -> FilterData {
        var hiddenTags = filter.hiddenTags
        if hiddenTags.contains(tag) {
            hiddenTags.remove(tag)
        } else {
            hiddenTags.insert(tag)
        }
        return updateFilter(filter, hiddenTags: hiddenTags)
    }
    
    /// 获取可见标签
    static func getVisibleTags(_ allTags: Set<String>, hiddenTags: Set<String>) -> Set<String> {
        return allTags.subtracting(hiddenTags)
    }
}

/// 项目操作业务逻辑 - 纯函数集合
/// Linus式设计：你要的ProjectOperations来了，全是纯函数，无副作用
enum ProjectOperations {
    
    /// 更新项目标签
    static func updateProject(_ project: ProjectData, with tags: Set<String>) -> ProjectData {
        return ProjectData(
            id: project.id,
            name: project.name,
            path: project.path,
            lastModified: project.lastModified,
            tags: tags,
            gitInfo: project.gitInfo,
            fileSystemInfo: project.fileSystemInfo
        )
    }
    
    /// 批量更新标签 - 给多个项目添加同一个标签
    static func batchUpdateTags(_ projects: [ProjectData], addTag: String) -> [ProjectData] {
        return projects.map { project in
            var updatedTags = project.tags
            updatedTags.insert(addTag)
            return updateProject(project, with: updatedTags)
        }
    }
    
    /// 批量移除标签 - 从多个项目移除同一个标签
    static func batchRemoveTags(_ projects: [ProjectData], removeTag: String) -> [ProjectData] {
        return projects.map { project in
            var updatedTags = project.tags
            updatedTags.remove(removeTag)
            return updateProject(project, with: updatedTags)
        }
    }
    
    /// 批量替换标签 - 将多个项目的某个标签替换为新标签
    static func batchReplaceTags(
        _ projects: [ProjectData], 
        oldTag: String, 
        newTag: String
    ) -> [ProjectData] {
        return projects.map { project in
            var updatedTags = project.tags
            if updatedTags.contains(oldTag) {
                updatedTags.remove(oldTag)
                updatedTags.insert(newTag)
            }
            return updateProject(project, with: updatedTags)
        }
    }
    
    /// 为项目设置完整的标签集合
    static func setProjectTags(_ project: ProjectData, tags: Set<String>) -> ProjectData {
        return updateProject(project, with: tags)
    }
    
    /// 检查项目是否需要更新文件系统信息
    static func needsFileSystemUpdate(_ project: ProjectData) -> Bool {
        let timeSinceCheck = Date().timeIntervalSince(project.fileSystemInfo.lastCheckTime)
        return timeSinceCheck >= ProjectData.FileSystemInfoData.checkInterval
    }
    
    /// 合并两个项目数据（以第二个为准，但保留ID）
    static func mergeProject(_ existing: ProjectData, with updated: ProjectData) -> ProjectData {
        return ProjectData(
            id: existing.id, // 保持原有ID
            name: updated.name,
            path: updated.path,
            lastModified: updated.lastModified,
            tags: updated.tags,
            gitInfo: updated.gitInfo,
            fileSystemInfo: updated.fileSystemInfo
        )
    }
    
    /// 刷新单个项目数据（重新扫描文件系统和Git信息）
    /// - Parameters:
    ///   - project: 要刷新的项目数据
    /// - Returns: 刷新后的项目数据，如果刷新失败则返回原始数据
    static func refreshSingleProject(_ project: ProjectData) -> ProjectData {
        // 检查项目路径是否存在
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: project.path) else {
            print("⚠️ 项目路径不存在，无法刷新: \(project.path)")
            return project
        }
        
        // 获取新的文件系统信息
        var updatedProject = project
        
        // 更新最后修改时间和文件系统信息
        if let attributes = try? fileManager.attributesOfItem(atPath: project.path),
           let modificationDate = attributes[.modificationDate] as? Date {
            let size = UInt64(attributes[.size] as? NSNumber ?? 0)
            let checksum = "\(modificationDate.timeIntervalSince1970)_\(size)"
            updatedProject = ProjectData(
                id: project.id,
                name: URL(fileURLWithPath: project.path).lastPathComponent, // 更新可能变化的目录名
                path: project.path,
                lastModified: modificationDate,
                tags: project.tags, // 标签将由外部同步
                gitInfo: project.gitInfo, // Git信息将被重新获取
                fileSystemInfo: ProjectData.FileSystemInfoData(
                    modificationDate: modificationDate,
                    size: size,
                    checksum: checksum,
                    lastCheckTime: Date()
                )
            )
        }
        
        // 重新获取Git信息
        updatedProject = updateGitInfo(updatedProject)
        
        return updatedProject
    }
    
    /// 更新项目的Git信息
    /// - Parameter project: 项目数据
    /// - Returns: 更新Git信息后的项目数据
    private static func updateGitInfo(_ project: ProjectData) -> ProjectData {
        let gitInfoData = loadGitInfoData(from: project.path)
        return ProjectData(
            id: project.id,
            name: project.name,
            path: project.path,
            lastModified: project.lastModified,
            tags: project.tags,
            gitInfo: gitInfoData,
            fileSystemInfo: project.fileSystemInfo
        )
    }
    
    /// 从指定路径加载Git信息数据
    /// - Parameter path: 项目路径
    /// - Returns: Git信息数据，如果不是Git仓库则返回nil
    private static func loadGitInfoData(from path: String) -> ProjectData.GitInfoData? {
        // 检查是否是 Git 仓库
        let gitPath = "\(path)/.git"
        guard FileManager.default.fileExists(atPath: gitPath) else {
            return nil
        }

        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")

        // 获取提交次数和最后提交时间
        let pipe = Pipe()
        process.standardOutput = pipe
        process.arguments = ["log", "--format=%ct", "-n", "1"]

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let timestamp = Double(
                String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "0")
            {
                let lastCommitDate = Date(timeIntervalSince1970: timestamp)

                // 获取提交次数
                let countProcess = Process()
                countProcess.currentDirectoryURL = URL(fileURLWithPath: path)
                countProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                countProcess.arguments = ["rev-list", "--count", "HEAD"]

                let countPipe = Pipe()
                countProcess.standardOutput = countPipe
                try countProcess.run()
                countProcess.waitUntilExit()

                let countData = countPipe.fileHandleForReading.readDataToEndOfFile()
                if let commitCount = Int(
                    String(data: countData, encoding: .utf8)?.trimmingCharacters(
                        in: .whitespacesAndNewlines) ?? "0")
                {
                    return ProjectData.GitInfoData(commitCount: commitCount, lastCommitDate: lastCommitDate)
                }
            }
        } catch {
            print("获取 Git 信息失败: \(error)")
        }
        return nil
    }
    
    /// 重命名项目文件夹
    /// - Parameters:
    ///   - project: 要重命名的项目数据
    ///   - newName: 新的文件夹名称
    /// - Returns: 重命名结果，成功时返回更新后的项目数据，失败时返回错误
    static func renameProject(_ project: ProjectData, newName: String) -> Result<ProjectData, RenameError> {
        let oldPath = project.path
        let parentDir = URL(fileURLWithPath: oldPath).deletingLastPathComponent()
        let newPath = parentDir.appendingPathComponent(newName).path
        
        // 1. 验证新名称
        guard isValidFileName(newName) else {
            return .failure(.invalidName)
        }
        
        // 2. 检查目标路径是否已存在
        guard !FileManager.default.fileExists(atPath: newPath) else {
            return .failure(.targetExists)
        }
        
        // 3. 执行文件系统重命名
        do {
            try FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
            print("✅ 文件系统重命名成功: \(oldPath) → \(newPath)")
        } catch {
            print("❌ 文件系统重命名失败: \(error)")
            return .failure(.systemError(error))
        }
        
        // 4. 更新项目数据
        let updatedProject = ProjectData(
            id: project.id, // 保持原ID
            name: newName,
            path: newPath,
            lastModified: Date(),
            tags: project.tags,
            gitInfo: project.gitInfo,
            fileSystemInfo: ProjectData.FileSystemInfoData(
                modificationDate: Date(),
                size: project.fileSystemInfo.size,
                checksum: "\(Date().timeIntervalSince1970)_\(project.fileSystemInfo.size)",
                lastCheckTime: Date()
            )
        )
        
        return .success(updatedProject)
    }
    
    /// 验证文件名是否合法
    /// - Parameter fileName: 要验证的文件名
    /// - Returns: 是否合法
    private static func isValidFileName(_ fileName: String) -> Bool {
        // 检查是否为空或只包含空白字符
        guard !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        // 检查是否包含非法字符
        let invalidCharacters = CharacterSet(charactersIn: ":<>|*?\"\\")
        guard fileName.rangeOfCharacter(from: invalidCharacters) == nil else {
            return false
        }
        
        // 检查是否为系统保留名称
        let reservedNames = [".", "..", "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]
        guard !reservedNames.contains(fileName.uppercased()) else {
            return false
        }
        
        return true
    }
}

/// 项目重命名错误类型
enum RenameError: LocalizedError {
    case invalidName
    case targetExists
    case systemError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "项目名称包含非法字符或为空"
        case .targetExists:
            return "目标路径已存在同名文件夹"
        case .systemError(let error):
            return "系统错误: \(error.localizedDescription)"
        }
    }
}

/// 分支管理业务逻辑 - 纯函数集合
/// 遵循Linus式设计原则：简洁、直接、无副作用
enum BranchLogic {
    
    /// 创建分支
    /// - Parameters:
    ///   - params: 分支创建参数
    /// - Returns: 分支操作结果
    static func createBranch(params: BranchCreationParams) -> BranchOperationResult {
        // 验证分支名称
        if !params.isValidName {
            return BranchOperationResult.failure(
                operation: .create,
                message: "分支名称无效：\(params.name)",
                branchName: params.name
            )
        }
        
        // 检查项目路径是否为有效Git仓库
        if !ShellExecutor.isValidGitRepository(path: params.projectPath) {
            return BranchOperationResult.failure(
                operation: .create,
                message: "路径不是有效的Git仓库：\(params.projectPath)",
                branchName: params.name
            )
        }
        
        // 委托给ShellExecutor执行实际创建
        return ShellExecutor.createWorktree(
            branchName: params.name,
            targetPath: params.targetPath,
            basePath: params.projectPath,
            description: params.description
        )
    }
    
    /// 删除分支
    /// - Parameters:
    ///   - name: 分支名称
    ///   - path: 分支路径
    ///   - projectPath: 项目路径
    ///   - force: 是否强制删除
    /// - Returns: 分支操作结果
    static func deleteBranch(
        name: String, 
        path: String, 
        projectPath: String, 
        force: Bool = false
    ) -> BranchOperationResult {
        // 安全检查：不允许删除主分支
        if isMainBranch(name: name) {
            return BranchOperationResult.failure(
                operation: .delete,
                message: "不能删除主分支",
                branchName: name
            )
        }
        
        // 委托给ShellExecutor执行实际删除
        return ShellExecutor.removeWorktree(
            path: path,
            branchName: name,
            basePath: projectPath,
            force: force
        )
    }
    
    /// 获取分支状态
    /// - Parameter path: 分支路径
    /// - Returns: 分支状态
    static func getBranchStatus(path: String) -> BranchStatus {
        guard ShellExecutor.isValidGitRepository(path: path) else {
            return .unknown
        }
        
        let status = ShellExecutor.getGitStatus(path: path)
        return status.clean ? .clean : .hasChanges
    }
    
    /// 列出所有worktree
    /// - Parameter projectPath: 项目路径
    /// - Returns: worktree信息列表
    static func listWorktrees(projectPath: String) -> [WorktreeInfo] {
        guard ShellExecutor.isValidGitRepository(path: projectPath) else {
            return []
        }
        
        return ShellExecutor.getWorktreeList(basePath: projectPath)
    }
    
    /// 获取分支信息
    /// - Parameter path: 分支路径
    /// - Returns: 分支信息，如果获取失败返回nil
    static func getBranchInfo(path: String) -> BranchInfo? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        
        // 从路径中提取分支名称
        let branchName = URL(fileURLWithPath: path).lastPathComponent
        
        // 读取分支描述
        let description = ShellExecutor.readBranchInfo(branchPath: path)
        
        // 获取分支状态
        let status = getBranchStatus(path: path)
        
        // 获取Git状态详情
        let gitStatus = ShellExecutor.getGitStatus(path: path)
        
        // 获取创建时间和最后修改时间
        let (createdAt, lastUsed) = getBranchDates(path: path)
        
        // 获取磁盘使用量
        let diskSize = ShellExecutor.getDiskUsage(path: path)
        
        // 检查是否为主分支
        let isMain = isMainBranch(name: branchName)
        
        return BranchInfo(
            name: branchName,
            path: path,
            description: description,
            status: status,
            createdAt: createdAt,
            lastUsed: lastUsed,
            uncommittedChanges: gitStatus.changes,
            diskSize: diskSize,
            isMain: isMain
        )
    }
    
    /// 合并分支
    /// - Parameters:
    ///   - source: 源分支名称
    ///   - target: 目标分支名称
    ///   - projectPath: 项目路径
    ///   - strategy: 合并策略
    /// - Returns: 操作结果
    static func mergeBranch(
        source: String, 
        target: String = "main", 
        projectPath: String,
        strategy: MergeStrategy = .recursive
    ) -> BranchOperationResult {
        // 安全检查：不允许合并主分支
        if isMainBranch(name: source) {
            return BranchOperationResult.failure(
                operation: .merge,
                message: "不能合并主分支",
                branchName: source
            )
        }
        
        // 委托给ShellExecutor执行实际合并
        return ShellExecutor.mergeBranch(
            sourceBranch: source,
            targetBranch: target,
            projectPath: projectPath,
            strategy: strategy
        )
    }
    
    /// 检查分支合并可行性
    /// - Parameters:
    ///   - source: 源分支名称
    ///   - target: 目标分支名称
    ///   - projectPath: 项目路径
    /// - Returns: 合并可行性检查结果
    static func checkMergeability(
        source: String,
        target: String = "main",
        projectPath: String
    ) -> MergeabilityCheck {
        return ShellExecutor.checkMergeability(
            sourceBranch: source,
            targetBranch: target,
            projectPath: projectPath
        )
    }
    
    /// 获取分支差异统计
    /// - Parameters:
    ///   - source: 源分支名称
    ///   - target: 目标分支名称
    ///   - projectPath: 项目路径
    /// - Returns: 差异统计信息
    static func getBranchDiff(
        source: String,
        target: String = "main",
        projectPath: String
    ) -> BranchDiffStats? {
        return ShellExecutor.getBranchDiff(
            sourceBranch: source,
            targetBranch: target,
            projectPath: projectPath
        )
    }
    
    /// 验证分支名称
    /// - Parameter name: 分支名称
    /// - Returns: 是否有效
    static func validateBranchName(_ name: String) -> Bool {
        let params = BranchCreationParams(name: name, projectPath: "")
        return params.isValidName
    }
    
    /// 检查是否为主分支
    /// - Parameter name: 分支名称
    /// - Returns: 是否为主分支
    static func isMainBranch(name: String) -> Bool {
        let mainBranches = ["main", "master", "develop"]
        return mainBranches.contains(name.lowercased())
    }
    
    /// 生成分支统计信息
    /// - Parameter branches: 分支列表
    /// - Returns: 统计信息
    static func generateStatistics(_ branches: [BranchInfo]) -> BranchStatistics {
        return BranchStatistics(branches: branches)
    }
    
    /// 根据条件过滤分支
    /// - Parameters:
    ///   - branches: 分支列表
    ///   - showMain: 是否显示主分支
    ///   - statusFilter: 状态过滤器
    /// - Returns: 过滤后的分支列表
    static func filterBranches(
        _ branches: [BranchInfo],
        showMain: Bool = true,
        statusFilter: Set<BranchStatus>? = nil
    ) -> [BranchInfo] {
        var filtered = branches
        
        // 主分支过滤
        if !showMain {
            filtered = filtered.filter { !$0.isMain }
        }
        
        // 状态过滤
        if let statusFilter = statusFilter, !statusFilter.isEmpty {
            filtered = filtered.filter { statusFilter.contains($0.status) }
        }
        
        return filtered
    }
    
    /// 按条件排序分支
    /// - Parameters:
    ///   - branches: 分支列表
    ///   - criteria: 排序条件
    ///   - ascending: 是否升序
    /// - Returns: 排序后的分支列表
    static func sortBranches(
        _ branches: [BranchInfo],
        by criteria: BranchSortCriteria = .lastUsed,
        ascending: Bool = false
    ) -> [BranchInfo] {
        return branches.sorted { branch1, branch2 in
            let result: Bool
            
            switch criteria {
            case .name:
                result = branch1.name.localizedCaseInsensitiveCompare(branch2.name) == .orderedAscending
            case .createdAt:
                result = branch1.createdAt < branch2.createdAt
            case .lastUsed:
                let date1 = branch1.lastUsed ?? Date.distantPast
                let date2 = branch2.lastUsed ?? Date.distantPast
                result = date1 < date2
            case .status:
                result = branch1.status.rawValue < branch2.status.rawValue
            case .changes:
                result = branch1.uncommittedChanges < branch2.uncommittedChanges
            case .diskSize:
                let size1 = branch1.diskSize ?? 0
                let size2 = branch2.diskSize ?? 0
                result = size1 < size2
            }
            
            return ascending ? result : !result
        }
    }
    
    // MARK: - Private Helper Functions
    
    /// 获取分支的创建和最后使用时间
    private static func getBranchDates(path: String) -> (createdAt: Date, lastUsed: Date?) {
        let branchInfoPath = "\(path)/.branch_info"
        var createdAt: Date = Date()
        
        // 尝试从.branch_info文件读取创建时间
        if let content = try? String(contentsOfFile: branchInfoPath, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                if line.hasPrefix("CREATED_AT=") {
                    let dateString = String(line.dropFirst("CREATED_AT=".count))
                    if let date = ISO8601DateFormatter().date(from: dateString) {
                        createdAt = date
                        break
                    }
                }
            }
        } else {
            // 回退到文件系统创建时间
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: path)
                createdAt = attributes[.creationDate] as? Date ?? Date()
            } catch {
                createdAt = Date()
            }
        }
        
        // 最后使用时间使用文件系统修改时间
        let lastUsed: Date?
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            lastUsed = attributes[.modificationDate] as? Date
        } catch {
            lastUsed = nil
        }
        
        return (createdAt: createdAt, lastUsed: lastUsed)
    }
}

/// 分支排序条件
enum BranchSortCriteria: CaseIterable {
    case name
    case createdAt
    case lastUsed
    case status
    case changes
    case diskSize
    
    var displayName: String {
        switch self {
        case .name: return "名称"
        case .createdAt: return "创建时间"
        case .lastUsed: return "最后使用"
        case .status: return "状态"
        case .changes: return "更改数量"
        case .diskSize: return "大小"
        }
    }
}

/// 应用状态业务逻辑 - 纯函数集合
enum AppStateLogic {
    
    /// 创建初始应用状态
    static func createInitialState() -> AppStateData {
        return AppStateData.empty
    }
    
    /// 更新应用状态
    static func updateState(
        _ state: AppStateData,
        projects: [UUID: ProjectData]? = nil,
        tags: [String: TagData]? = nil,
        watchedDirectories: Set<String>? = nil,
        filter: FilterData? = nil,
        selectedProjectIds: Set<UUID>? = nil
    ) -> AppStateData {
        return AppStateData(
            projects: projects ?? state.projects,
            tags: tags ?? state.tags,
            watchedDirectories: watchedDirectories ?? state.watchedDirectories,
            filter: filter ?? state.filter,
            selectedProjectIds: selectedProjectIds ?? state.selectedProjectIds
        )
    }
    
    /// 获取处理后的项目列表
    static func getProcessedProjects(_ state: AppStateData) -> [ProjectData] {
        let projectList = Array(state.projects.values)
        return ProjectLogic.processProjects(projectList, with: state.filter)
    }
    
    /// 获取标签统计信息
    static func getTagStatistics(_ state: AppStateData) -> [String: Int] {
        let projectList = Array(state.projects.values)
        return TagLogic.calculateTagUsage(projectList)
    }
    
    /// 添加项目到状态
    static func addProject(_ state: AppStateData, project: ProjectData) -> AppStateData {
        var updatedProjects = state.projects
        updatedProjects[project.id] = project
        return updateState(state, projects: updatedProjects)
    }
    
    /// 批量添加项目到状态
    static func addProjects(_ state: AppStateData, projects: [ProjectData]) -> AppStateData {
        var updatedProjects = state.projects
        for project in projects {
            updatedProjects[project.id] = project
        }
        return updateState(state, projects: updatedProjects)
    }
    
    /// 移除项目从状态
    static func removeProject(_ state: AppStateData, projectId: UUID) -> AppStateData {
        var updatedProjects = state.projects
        updatedProjects.removeValue(forKey: projectId)
        return updateState(state, projects: updatedProjects)
    }
}

// MARK: - Dashboard Logic


/// Dashboard 业务逻辑 - 最简单可工作的实现
enum DashboardLogic {
    
    /// 生成每日活动数据 - 基于实际项目数据，修正提交数计算逻辑
    static func generateDailyActivities(from projects: [ProjectData], days: Int = 90) -> [DailyActivity] {
        let calendar = Calendar.current
        let today = Date()
        var activities: [DailyActivity] = []
        
        // 创建日期到活跃项目数的映射（更合理的统计方式）
        var dailyActiveProjects: [Date: Set<UUID>] = [:]
        
        // 统计每个项目的最后活跃日期
        for project in projects {
            guard let gitInfo = project.gitInfo else { continue }
            
            let lastCommitDate = gitInfo.lastCommitDate
            let dayStart = calendar.startOfDay(for: lastCommitDate)
            
            // 如果这个日期在我们的统计范围内，记录这个项目在这一天是活跃的
            if let daysAgo = calendar.dateComponents([.day], from: dayStart, to: calendar.startOfDay(for: today)).day,
               daysAgo >= 0 && daysAgo < days {
                dailyActiveProjects[dayStart, default: Set<UUID>()].insert(project.id)
            }
        }
        
        // 生成指定天数的活动数据
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            
            // 使用当天活跃的项目数作为活动强度指标
            let activeProjectCount = dailyActiveProjects[dayStart]?.count ?? 0
            activities.append(DailyActivity(date: date, commitCount: activeProjectCount))
        }
        
        return activities.reversed() // 按时间顺序
    }
    
    /// 获取热力图网格数据 - 修正的实现
    static func getHeatmapGrid(activities: [DailyActivity], config: Dashboard.HeatmapConfig = .default) -> [[DailyActivity?]] {
        let calendar = Calendar.current
        let today = Date()
        let startDate = calendar.date(byAdding: .day, value: -(config.daysToShow - 1), to: today)!
        
        // 创建activities字典便于查找
        let activitiesDict = Dictionary(grouping: activities) { activity in
            calendar.startOfDay(for: activity.date)
        }.compactMapValues { $0.first }
        
        var grid: [[DailyActivity?]] = []
        var currentWeek: [DailyActivity?] = Array(repeating: nil, count: 7)
        
        // 从开始日期遍历每一天
        for dayOffset in 0..<config.daysToShow {
            guard let currentDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            let weekday = calendar.component(.weekday, from: currentDate) - 1 // 0=周日, 1=周一, ..., 6=周六
            
            // 查找当天的活动数据
            let dayStart = calendar.startOfDay(for: currentDate)
            currentWeek[weekday] = activitiesDict[dayStart]
            
            // 如果是周六或者是最后一天，完成当前周并开始新周
            if weekday == 6 || dayOffset == config.daysToShow - 1 {
                grid.append(currentWeek)
                currentWeek = Array(repeating: nil, count: 7)
            }
        }
        
        return grid
    }
    
    /// 计算热力图统计信息 - 修正总提交数计算
    static func calculateHeatmapStats(from activities: [DailyActivity], projects: [ProjectData]) -> Dashboard.HeatmapStats {
        let totalDays = activities.count
        let activeDays = activities.filter { $0.commitCount > 0 }.count
        
        // 正确计算总提交次数：从项目的实际Git信息中获取
        let totalCommits = projects.compactMap { $0.gitInfo?.commitCount }.reduce(0, +)
        
        let maxActiveProjectsInDay = activities.map { $0.commitCount }.max() ?? 0
        let averageActiveProjectsPerDay = totalDays > 0 ? Double(activities.reduce(0) { $0 + $1.commitCount }) / Double(totalDays) : 0
        
        return Dashboard.HeatmapStats(
            totalDays: totalDays,
            activeDays: activeDays,
            totalCommits: totalCommits,
            maxCommitsInDay: maxActiveProjectsInDay,
            averageCommitsPerDay: averageActiveProjectsPerDay,
            activityRate: totalDays > 0 ? Double(activeDays) / Double(totalDays) : 0
        )
    }
    
    /// 获取最近提交的项目（按最后提交时间排序）
    static func getRecentCommitProjects(from projects: [ProjectData], limit: Int = 10) -> [ProjectData] {
        return projects
            .filter { $0.gitInfo != nil }
            .sorted { project1, project2 in
                let date1 = project1.gitInfo?.lastCommitDate ?? Date.distantPast
                let date2 = project2.gitInfo?.lastCommitDate ?? Date.distantPast
                return date1 > date2
            }
            .prefix(limit)
            .map { $0 }
    }
    
    /// 获取最活跃的项目（保留原方法以兼容）
    static func getMostActiveProjects(from projects: [ProjectData], limit: Int = 10) -> [ProjectData] {
        return getRecentCommitProjects(from: projects, limit: limit)
    }
    
    /// 计算项目活跃度分数
    static func calculateActivityScore(_ project: ProjectData) -> Double {
        guard let gitInfo = project.gitInfo else { return 0 }
        return Double(gitInfo.commitCount) // 简单实现
    }
}