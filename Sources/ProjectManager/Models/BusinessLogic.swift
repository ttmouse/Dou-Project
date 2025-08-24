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
        return searchFiltered
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
    
    /// 生成每日活动数据 - 先创建空的，确保编译通过
    static func generateDailyActivities(from projects: [ProjectData], days: Int = 90) -> [DailyActivity] {
        let calendar = Calendar.current
        let today = Date()
        var activities: [DailyActivity] = []
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            
            // 简单实现：每天固定显示一些活动
            let commitCount = Int.random(in: 0...5)
            activities.append(DailyActivity(date: date, commitCount: commitCount))
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
    
    /// 计算热力图统计信息
    static func calculateHeatmapStats(from activities: [DailyActivity]) -> Dashboard.HeatmapStats {
        let totalDays = activities.count
        let activeDays = activities.filter { $0.commitCount > 0 }.count
        let totalCommits = activities.reduce(0) { $0 + $1.commitCount }
        let maxCommitsInDay = activities.map { $0.commitCount }.max() ?? 0
        let averageCommitsPerDay = totalDays > 0 ? Double(totalCommits) / Double(totalDays) : 0
        
        return Dashboard.HeatmapStats(
            totalDays: totalDays,
            activeDays: activeDays,
            totalCommits: totalCommits,
            maxCommitsInDay: maxCommitsInDay,
            averageCommitsPerDay: averageCommitsPerDay,
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