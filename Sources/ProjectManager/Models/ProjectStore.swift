import SwiftUI
import Combine

// MARK: - ProjectStore协议
protocol ProjectStore: ObservableObject {
    var projects: [UUID: Project] { get }
    
    func getAllProjects() -> [Project]
    func getProject(by id: UUID) -> Project?
    func registerProject(_ project: Project)
    func removeProject(_ id: UUID)
    func addTagToProject(projectId: UUID, tag: String)
    func removeTagFromProject(projectId: UUID, tag: String)
    func addTagToProjects(projectIds: Set<UUID>, tag: String)
    func removeTagFromAllProjects(_ tag: String)
    func renameTagInAllProjects(from oldName: String, to newName: String)
}

// MARK: - ProjectStore实现
class DefaultProjectStore: ProjectStore, ObservableObject {
    
    @Published var projects: [UUID: Project] = [:]
    
    private let storage: TagStorage
    private let sortManager: ProjectSortManager
    private var tagStore: (any TagStore)?
    
    init(storage: TagStorage, sortManager: ProjectSortManager) {
        self.storage = storage
        self.sortManager = sortManager
        loadProjects()
    }
    
    // 设置标签存储引用
    func setTagStore(_ tagStore: any TagStore) {
        self.tagStore = tagStore
    }
    
    // MARK: - 数据加载
    private func loadProjects() {
        if let cachedProjects = loadProjectsFromCache() {
            print("ProjectStore从缓存加载了 \(cachedProjects.count) 个项目")
            for project in cachedProjects {
                projects[project.id] = project
            }
            sortManager.updateSortedProjects(cachedProjects)
        }
    }
    
    private func loadProjectsFromCache() -> [Project]? {
        let cacheURL = storage.appSupportURL.appendingPathComponent("projects.json")
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            let projects = try decoder.decode([Project].self, from: data)
            return projects
        } catch {
            print("ProjectStore: 加载项目缓存失败（可能是首次运行）: \(error)")
            return nil
        }
    }
    
    // MARK: - 项目查询
    func getAllProjects() -> [Project] {
        return Array(projects.values)
    }
    
    func getProject(by id: UUID) -> Project? {
        return projects[id]
    }
    
    // MARK: - 项目管理
    func registerProject(_ project: Project) {
        projects[project.id] = project
        sortManager.updateProject(project)
        
        // 将项目的标签添加到标签存储
        for tag in project.tags {
            tagStore?.addTag(tag)
        }
        
        saveProjectsToCache()
        print("ProjectStore: 注册项目 '\(project.name)'")
    }
    
    func removeProject(_ id: UUID) {
        if let project = projects[id] {
            projects.removeValue(forKey: id)
            sortManager.removeProject(project)
            
            // 使统计缓存失效
            tagStore?.invalidateUsageCache()
            
            saveProjectsToCache()
            print("ProjectStore: 移除项目 '\(project.name)'")
        }
    }
    
    // MARK: - 项目标签操作
    func addTagToProject(projectId: UUID, tag: String) {
        if let project = projects[projectId] {
            if !project.tags.contains(tag) {
                let updatedProject = project.withAddedTag(tag)
                projects[projectId] = updatedProject
                sortManager.updateProject(updatedProject)
                
                // 确保标签存在
                tagStore?.addTag(tag)
                tagStore?.invalidateUsageCache()
                
                // 保存到系统
                updatedProject.saveTagsToSystem()
                saveProjectsToCache()
                
                print("ProjectStore: 添加标签 '\(tag)' 到项目 '\(updatedProject.name)'")
            }
        }
    }
    
    func removeTagFromProject(projectId: UUID, tag: String) {
        if let project = projects[projectId] {
            let updatedProject = project.withRemovedTag(tag)
            projects[projectId] = updatedProject
            sortManager.updateProject(updatedProject)
            
            tagStore?.invalidateUsageCache()
            
            // 保存到系统
            updatedProject.saveTagsToSystem()
            saveProjectsToCache()
            
            print("ProjectStore: 从项目 '\(project.name)' 移除标签 '\(tag)'")
        }
    }
    
    // MARK: - 批量操作
    func addTagToProjects(projectIds: Set<UUID>, tag: String) {
        print("ProjectStore: 批量添加标签 '\(tag)' 到 \(projectIds.count) 个项目")
        
        // 确保标签存在
        tagStore?.addTag(tag)
        
        // 批量处理项目
        for projectId in projectIds {
            if let project = projects[projectId] {
                let updatedProject = project.withAddedTag(tag)
                projects[projectId] = updatedProject
                sortManager.updateProject(updatedProject)
            }
        }
        
        // 统一处理缓存和保存
        tagStore?.invalidateUsageCache()
        saveProjectsToCache()
        
        // 批量保存系统标签
        for projectId in projectIds {
            if let project = projects[projectId] {
                project.saveTagsToSystem()
            }
        }
    }
    
    func removeTagFromAllProjects(_ tag: String) {
        var updatedProjects: [Project] = []
        
        for (id, project) in projects {
            if project.tags.contains(tag) {
                let updatedProject = project.withRemovedTag(tag)
                projects[id] = updatedProject
                updatedProjects.append(updatedProject)
            }
        }
        
        // 批量更新排序管理器
        for project in updatedProjects {
            sortManager.updateProject(project)
            project.saveTagsToSystem()
        }
        
        saveProjectsToCache()
        print("ProjectStore: 从所有项目中移除标签 '\(tag)'")
    }
    
    func renameTagInAllProjects(from oldName: String, to newName: String) {
        var updatedProjects: [Project] = []
        
        for (id, project) in projects {
            if project.tags.contains(oldName) {
                let updatedProject = project.withRemovedTag(oldName).withAddedTag(newName)
                projects[id] = updatedProject
                updatedProjects.append(updatedProject)
            }
        }
        
        // 批量更新排序管理器
        for project in updatedProjects {
            sortManager.updateProject(project)
            project.saveTagsToSystem()
        }
        
        saveProjectsToCache()
        print("ProjectStore: 在所有项目中重命名标签 '\(oldName)' -> '\(newName)'")
    }
    
    // MARK: - 数据持久化
    func saveProjectsToCache() {
        let cacheURL = storage.appSupportURL.appendingPathComponent("projects.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(Array(projects.values))
            try data.write(to: cacheURL)
            print("ProjectStore: 项目数据已保存到缓存")
        } catch {
            print("ProjectStore: 保存项目缓存失败: \(error)")
        }
    }
}