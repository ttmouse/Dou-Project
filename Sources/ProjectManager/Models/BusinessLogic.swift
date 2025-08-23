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
}