import SwiftUI
import AppKit

class TagManager: ObservableObject {
    @Published var allTags: Set<String> = []
    @Published private(set) var projects: [UUID: Project] = [:]
    @Published private var tagUsageCount: [String: Int] = [:]
    @Published var tagColors: [String: Color] = [:]
    private var tagLastUsed: [String: Date] = [:]
    private let cacheFileName = "project_cache.json"
    
    init() {
        loadSystemTags()
        loadFromCache()
    }
    
    // MARK: - 缓存管理
    
    private var cacheFileURL: URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("com.projectmanager").appendingPathComponent(cacheFileName)
    }
    
    private func loadFromCache() {
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            let cachedProjects = try decoder.decode([Project].self, from: data)
            print("从缓存加载 \(cachedProjects.count) 个项目")
            
            cachedProjects.forEach { project in
                projects[project.id] = project
                project.tags.forEach { tag in
                    addTag(tag)
                    incrementUsage(for: tag)
                }
            }
        } catch {
            print("加载缓存失败: \(error)")
        }
    }
    
    private func saveToCache() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(Array(projects.values))
            
            // 确保缓存目录存在
            let cacheDir = cacheFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            
            try data.write(to: cacheFileURL)
            print("项目缓存保存成功")
        } catch {
            print("保存缓存失败: \(error)")
        }
    }
    
    // MARK: - 项目管理
    
    func removeProject(_ id: UUID) {
        if let project = projects[id] {
            project.tags.forEach { tag in
                decrementUsage(for: tag)
            }
            projects.removeValue(forKey: id)
            saveToCache()
            objectWillChange.send()
        }
    }
    
    func clearProjects() {
        projects.removeAll()
        saveToCache()
        objectWillChange.send()
    }
    
    // MARK: - 系统标签管理
    
    func loadSystemTags() {
        let workspace = NSWorkspace.shared
        let labels = workspace.fileLabels
        let colors = workspace.fileLabelColors
        
        for (index, label) in labels.enumerated() {
            allTags.insert(label)
            if index < colors.count {
                tagColors[label] = Color(nsColor: colors[index])
            }
        }
    }
    
    // MARK: - 项目标签管理
    
    func registerProject(_ project: Project) {
        print("注册项目: \(project.name), 标签: \(project.tags)")
        projects[project.id] = project
        project.tags.forEach { tag in
            addTag(tag)
            incrementUsage(for: tag)
        }
        saveToCache()
        objectWillChange.send()
    }
    
    func updateProject(_ project: Project) {
        print("更新项目: \(project.name), 标签: \(project.tags)")
        projects[project.id] = project
        objectWillChange.send()
    }
    
    func addTagToProject(projectId: UUID, tag: String) {
        print("尝试添加标签 '\(tag)' 到项目")
        guard var project = projects[projectId] else {
            print("未找到项目 ID: \(projectId)")
            return
        }
        
        if !project.tags.contains(tag) {
            print("项目原有标签: \(project.tags)")
            project.addTag(tag)
            print("添加标签后: \(project.tags)")
            projects[projectId] = project
            addTag(tag)
            incrementUsage(for: tag)
            objectWillChange.send()
            print("标签添加完成")
        } else {
            print("项目已包含该标签")
        }
    }
    
    func removeTagFromProject(projectId: UUID, tag: String) {
        print("尝试从项目移除标签 '\(tag)'")
        guard var project = projects[projectId] else {
            print("未找到项目 ID: \(projectId)")
            return
        }
        
        if project.tags.contains(tag) {
            print("项目原有标签: \(project.tags)")
            project.removeTag(tag)
            print("移除标签后: \(project.tags)")
            projects[projectId] = project
            decrementUsage(for: tag)
            objectWillChange.send()
            print("标签移除完成")
        } else {
            print("项目不包含该标签")
        }
    }
    
    // MARK: - 标签管理
    
    func addTag(_ tag: String) {
        print("添加标签到全局集合: \(tag)")
        allTags.insert(tag)
        if tagColors[tag] == nil {
            tagColors[tag] = .blue
        }
    }
    
    func getColor(for tag: String) -> Color {
        return tagColors[tag] ?? .blue
    }
    
    func setColor(_ color: Color, for tag: String) {
        tagColors[tag] = color
        objectWillChange.send()
    }
    
    // MARK: - 标签统计
    
    func getUsageCount(for tag: String) -> Int {
        return tagUsageCount[tag] ?? 0
    }
    
    // MARK: - 私有方法
    
    private func incrementUsage(for tag: String) {
        tagUsageCount[tag] = (tagUsageCount[tag] ?? 0) + 1
        tagLastUsed[tag] = Date()
        print("标签 '\(tag)' 使用次数: \(tagUsageCount[tag] ?? 0)")
    }
    
    private func decrementUsage(for tag: String) {
        if let count = tagUsageCount[tag] {
            if count > 1 {
                tagUsageCount[tag] = count - 1
            } else {
                tagUsageCount.removeValue(forKey: tag)
            }
        }
        print("标签 '\(tag)' 使用次数: \(tagUsageCount[tag] ?? 0)")
    }
} 