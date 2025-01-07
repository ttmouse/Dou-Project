import SwiftUI

class TagManager: ObservableObject {
    @Published var allTags: Set<String> = []
    @Published var commonTags: [String] = [
        "Swift", "Node.js", "Python", "Web", "工具", "文档",
        "开发中", "已完成", "待处理"
    ]
    
    // 标签使用统计
    @Published private var tagUsageCount: [String: Int] = [:]
    // 标签颜色
    @Published var tagColors: [String: Color] = [:]
    // 标签最后使用时间
    private var tagLastUsed: [String: Date] = [:]
    // 项目管理
    @Published private(set) var projects: [UUID: Project] = [:]
    
    // MARK: - 项目标签管理
    
    func registerProject(_ project: Project) {
        projects[project.id] = project
        project.tags.forEach { addTag($0) }
        objectWillChange.send()
    }
    
    func updateProject(_ project: Project) {
        projects[project.id] = project
        objectWillChange.send()
    }
    
    func addTagToProject(projectId: UUID, tag: String) {
        guard let project = projects[projectId] else { return }
        var updatedTags = project.tags
        updatedTags.insert(tag)
        let updatedProject = project.copyWith(tags: updatedTags)
        projects[projectId] = updatedProject
        addTag(tag)
        incrementUsage(for: tag)
        objectWillChange.send()
    }
    
    func removeTagFromProject(projectId: UUID, tag: String) {
        guard let project = projects[projectId] else { return }
        var updatedTags = project.tags
        updatedTags.remove(tag)
        let updatedProject = project.copyWith(tags: updatedTags)
        projects[projectId] = updatedProject
        objectWillChange.send()
    }
    
    func getProject(by id: UUID) -> Project? {
        return projects[id]
    }
    
    // MARK: - 标签统计
    
    func getUsageCount(for tag: String) -> Int {
        return tagUsageCount[tag] ?? 0
    }
    
    func getColor(for tag: String) -> Color {
        return tagColors[tag] ?? .blue
    }
    
    func setColor(_ color: Color, for tag: String) {
        tagColors[tag] = color
        objectWillChange.send()
    }
    
    // MARK: - 标签管理
    
    func addTag(_ tag: String) {
        allTags.insert(tag)
        incrementUsage(for: tag)
    }
    
    func removeTag(_ tag: String) {
        allTags.remove(tag)
        tagUsageCount.removeValue(forKey: tag)
        tagColors.removeValue(forKey: tag)
        tagLastUsed.removeValue(forKey: tag)
        
        // 从所有项目中移除此标签
        for (id, project) in projects {
            if project.tags.contains(tag) {
                var updatedTags = project.tags
                updatedTags.remove(tag)
                let updatedProject = project.copyWith(tags: updatedTags)
                projects[id] = updatedProject
            }
        }
        
        objectWillChange.send()
    }
    
    func renameTag(from oldName: String, to newName: String) {
        guard oldName != newName else { return }
        
        // 转移统计数据
        if let count = tagUsageCount.removeValue(forKey: oldName) {
            tagUsageCount[newName] = count
        }
        
        // 转移颜色
        if let color = tagColors.removeValue(forKey: oldName) {
            tagColors[newName] = color
        }
        
        // 转移最后使用时间
        if let lastUsed = tagLastUsed.removeValue(forKey: oldName) {
            tagLastUsed[newName] = lastUsed
        }
        
        // 更新所有项目中的标签
        for (id, project) in projects {
            if project.tags.contains(oldName) {
                var updatedTags = project.tags
                updatedTags.remove(oldName)
                updatedTags.insert(newName)
                let updatedProject = project.copyWith(tags: updatedTags)
                projects[id] = updatedProject
            }
        }
        
        // 更新集合
        allTags.remove(oldName)
        allTags.insert(newName)
        
        // 更新常用标签
        if let index = commonTags.firstIndex(of: oldName) {
            commonTags[index] = newName
        }
        
        objectWillChange.send()
    }
    
    func mergeTags(_ source: String, into target: String) {
        guard source != target else { return }
        
        // 合并使用次数
        let sourceCount = tagUsageCount[source] ?? 0
        tagUsageCount[target] = (tagUsageCount[target] ?? 0) + sourceCount
        
        // 保留目标标签的颜色
        tagColors.removeValue(forKey: source)
        
        // 使用最新的最后使用时间
        if let sourceLastUsed = tagLastUsed[source],
           let targetLastUsed = tagLastUsed[target] {
            tagLastUsed[target] = max(sourceLastUsed, targetLastUsed)
        }
        
        // 更新所有项目中的标签
        for (id, project) in projects {
            if project.tags.contains(source) {
                var updatedTags = project.tags
                updatedTags.remove(source)
                updatedTags.insert(target)
                let updatedProject = project.copyWith(tags: updatedTags)
                projects[id] = updatedProject
            }
        }
        
        // 清理源标签
        removeTag(source)
        
        objectWillChange.send()
    }
    
    // MARK: - 常用标签管理
    
    func addCommonTag(_ tag: String) {
        if !commonTags.contains(tag) {
            commonTags.append(tag)
            objectWillChange.send()
        }
    }
    
    func removeCommonTag(_ tag: String) {
        if let index = commonTags.firstIndex(of: tag) {
            commonTags.remove(at: index)
            objectWillChange.send()
        }
    }
    
    // MARK: - 标签统计
    
    func getMostUsedTags(limit: Int = 10) -> [String] {
        return Array(tagUsageCount.sorted { $0.value > $1.value }
            .prefix(limit))
            .map { $0.key }
    }
    
    func getRecentlyUsedTags(limit: Int = 10) -> [String] {
        return Array(tagLastUsed.sorted { $0.value > $1.value }
            .prefix(limit))
            .map { $0.key }
    }
    
    // MARK: - 私有方法
    
    private func incrementUsage(for tag: String) {
        tagUsageCount[tag] = (tagUsageCount[tag] ?? 0) + 1
        tagLastUsed[tag] = Date()
    }
} 