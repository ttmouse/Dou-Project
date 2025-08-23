import Foundation
import SwiftUI

class TagOperations {
    weak var core: TagManagerCore?
    
    init(core: TagManagerCore) {
        self.core = core
    }
    
    // MARK: - 标签CRUD操作
    
    func addTag(_ tag: String, color: Color) {
        guard let core = core else { return }
        
        print("TagOperations: 添加标签 \(tag)")
        
        if !core.allTags.contains(tag) {
            core.allTags.insert(tag)
            core.colorManager.setColor(color, for: tag)
            core.saveAll()
        }
    }
    
    func removeTag(_ tag: String) {
        guard let core = core else { return }
        
        print("TagOperations: 移除标签 \(tag)")
        
        if core.allTags.contains(tag) {
            core.allTags.remove(tag)
            core.colorManager.removeColor(for: tag)
            
            removeTagFromAllProjects(tag)
            core.invalidateTagUsageCache()
            core.saveAll()
        }
    }
    
    func renameTag(_ oldName: String, to newName: String, color: Color) {
        guard let core = core else { return }
        
        print("TagOperations: 重命名标签 \(oldName) -> \(newName)")
        
        if core.allTags.contains(oldName) && !core.allTags.contains(newName) {
            core.allTags.remove(oldName)
            core.allTags.insert(newName)
            
            core.colorManager.removeColor(for: oldName)
            core.colorManager.setColor(color, for: newName)
            
            updateTagInAllProjects(from: oldName, to: newName)
            core.invalidateTagUsageCache()
            core.saveAll()
        }
    }
    
    // MARK: - 项目标签操作
    
    func addTagToProject(projectId: UUID, tag: String) {
        guard let core = core else { return }
        
        print("TagOperations: 添加标签 '\(tag)' 到项目 \(projectId)")
        
        if var project = core.projects[projectId] {
            if !project.tags.contains(tag) {
                project.addTag(tag)
                core.projects[projectId] = project
                core.sortManager.updateProject(project)
                core.invalidateTagUsageCache()
                
                project.saveTagsToSystem()
                core.saveAll(force: true)
            }
        }
    }
    
    func removeTagFromProject(projectId: UUID, tag: String) {
        guard let core = core else { return }
        
        print("TagOperations: 从项目 \(projectId) 移除标签 '\(tag)'")
        
        if var project = core.projects[projectId] {
            project.removeTag(tag)
            core.projects[projectId] = project
            core.sortManager.updateProject(project)
            core.invalidateTagUsageCache()
            
            project.saveTagsToSystem()
            core.saveAll(force: true)
        }
    }
    
    // MARK: - 批量操作
    
    func addTagToProjects(projectIds: Set<UUID>, tag: String) {
        guard let core = core else { return }
        
        print("TagOperations: 批量添加标签 '\(tag)' 到 \(projectIds.count) 个项目")
        
        if !core.allTags.contains(tag) {
            addTag(tag, color: core.getColor(for: tag))
        }
        
        for projectId in projectIds {
            if var project = core.projects[projectId] {
                project.addTag(tag)
                core.projects[projectId] = project
                core.sortManager.updateProject(project)
            }
        }
        
        core.invalidateTagUsageCache()
        core.saveAll(force: true)
        
        for projectId in projectIds {
            if let project = core.projects[projectId] {
                project.saveTagsToSystem()
            }
        }
    }
    
    func removeTagFromProjects(projectIds: Set<UUID>, tag: String) {
        guard let core = core else { return }
        
        print("TagOperations: 批量从 \(projectIds.count) 个项目移除标签 '\(tag)'")
        
        for projectId in projectIds {
            if var project = core.projects[projectId] {
                project.removeTag(tag)
                core.projects[projectId] = project
                core.sortManager.updateProject(project)
            }
        }
        
        core.invalidateTagUsageCache()
        core.saveAll(force: true)
        
        for projectId in projectIds {
            if let project = core.projects[projectId] {
                project.saveTagsToSystem()
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private func removeTagFromAllProjects(_ tag: String) {
        guard let core = core else { return }
        
        for (id, project) in core.projects {
            if project.tags.contains(tag) {
                var updatedProject = project
                updatedProject.removeTag(tag)
                core.projects[id] = updatedProject
                core.sortManager.updateProject(updatedProject)
                updatedProject.saveTagsToSystem()
            }
        }
    }
    
    private func updateTagInAllProjects(from oldTag: String, to newTag: String) {
        guard let core = core else { return }
        
        for (id, project) in core.projects {
            if project.tags.contains(oldTag) {
                var updatedProject = project
                updatedProject.removeTag(oldTag)
                updatedProject.addTag(newTag)
                core.projects[id] = updatedProject
                core.sortManager.updateProject(updatedProject)
                updatedProject.saveTagsToSystem()
            }
        }
    }
}