// Linus风格简化项目管理器
// 专注于项目操作，接口简单直接

import Foundation
import SwiftUI

// AIDEV-NOTE: 专门处理项目相关操作的简化管理器
// 遵循单一职责原则，只管理项目，不处理标签或其他复杂逻辑

class SimpleProjectManager: ObservableObject {
    @Published private(set) var projects: [Project] = []
    
    private let storage: TagStorage
    
    init(storage: TagStorage) {
        self.storage = storage
        load()
    }
}

// MARK: - Projects协议实现

extension SimpleProjectManager: Projects {
    func add(_ project: Project) {
        // 避免重复
        guard !projects.contains(where: { $0.id == project.id }) else { return }
        projects.append(project)
        save()
    }
    
    func remove(_ id: UUID) {
        projects.removeAll { $0.id == id }
        save()
    }
    
    func all() -> [Project] {
        return projects
    }
}

// MARK: - DataStorage协议实现

extension SimpleProjectManager: DataStorage {
    func load() {
        let cacheURL = storage.appSupportURL.appendingPathComponent("projects.json")
        do {
            let data = try Foundation.Data(contentsOf: cacheURL)
            let loadedProjects = try JSONDecoder().decode([Project].self, from: data)
            projects = loadedProjects
        } catch {
            print("项目加载失败: \(error)")
            projects = []
        }
    }
    
    func save() {
        let cacheURL = storage.appSupportURL.appendingPathComponent("projects.json")
        do {
            let data = try JSONEncoder().encode(projects)
            try data.write(to: cacheURL)
        } catch {
            print("项目保存失败: \(error)")
        }
    }
}

// MARK: - 项目查找和筛选

extension SimpleProjectManager {
    /// 按名称查找
    func findByName(_ name: String) -> [Project] {
        return projects.filter { $0.name.localizedCaseInsensitiveContains(name) }
    }
    
    /// 按路径查找
    func findByPath(_ path: String) -> [Project] {
        return projects.filter { $0.path.localizedCaseInsensitiveContains(path) }
    }
    
    /// 按标签查找
    func findByTag(_ tag: String) -> [Project] {
        return projects.filter { $0.tags.contains(tag) }
    }
    
    /// 获取单个项目
    func get(_ id: UUID) -> Project? {
        return projects.first { $0.id == id }
    }
    
    /// 更新项目
    func update(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        save()
    }
}

// MARK: - 项目排序

enum ProjectSort {
    case name
    case time
    case size
}

extension SimpleProjectManager {
    func sorted(by: ProjectSort) -> [Project] {
        switch by {
        case .name:
            return projects.sorted { $0.name < $1.name }
        case .time:
            return projects.sorted { $0.lastModified > $1.lastModified }
        case .size:
            return projects.sorted { 
                ($0.fileSystemInfo.size ?? 0) > ($1.fileSystemInfo.size ?? 0) 
            }
        }
    }
}

// MARK: - 项目统计

extension SimpleProjectManager {
    func count() -> Int {
        return projects.count
    }
    
    func gitCount() -> Int {
        return projects.filter { $0.gitInfo?.commitCount ?? 0 > 0 }.count
    }
    
    func taggedCount() -> Int {
        return projects.filter { !$0.tags.isEmpty }.count
    }
}

// AIDEV-NOTE: 这个简化的项目管理器只关注项目本身
// 不处理标签逻辑，不处理UI状态，符合单一职责原则
// 所有方法都简单直接，易于理解和测试