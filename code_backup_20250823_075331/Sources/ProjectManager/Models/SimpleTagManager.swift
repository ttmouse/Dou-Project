// Linus风格简化TagManager
// 遵循极简协议，每个方法都简单到5岁小孩能理解

import Foundation
import SwiftUI
import Combine

// AIDEV-NOTE: 这是TagManager的Linus风格重构版本
// 遵循简单协议，去除复杂方法和参数
// 保持完整功能，但接口更简洁

class SimpleTagManagerImpl: ObservableObject {
    // MARK: - 基础数据
    @Published private(set) var allTags: [String] = []
    @Published private(set) var allProjects: [Project] = []
    @Published private(set) var watchingPaths: [String] = []
    
    // MARK: - 依赖组件
    private let storage: TagStorage
    private let colorManager: TagColorManager
    private let projectOperations: ProjectOperationManager
    private let directoryWatcher: DirectoryWatcher
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    init(storage: TagStorage) {
        self.storage = storage
        self.colorManager = TagColorManager(storage: storage)
        
        // 创建其他组件时使用弱引用避免循环
        let tempManager = TagManager() // 临时使用，后续需要重构
        self.projectOperations = ProjectOperationManager(tagManager: tempManager, storage: storage)
        self.directoryWatcher = DirectoryWatcher(tagManager: tempManager, storage: storage)
        
        setupBindings()
        load()
    }
    
    private func setupBindings() {
        colorManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}

// MARK: - Tags协议实现

extension SimpleTagManagerImpl: Tags {
    func add(_ name: String) {
        guard !allTags.contains(name) else { return }
        allTags.append(name)
        allTags.sort()
        save()
    }
    
    func remove(_ name: String) {
        allTags.removeAll { $0 == name }
        
        // 从所有项目中移除该标签
        for project in allProjects {
            if project.tags.contains(name) {
                untag(project.id, name)
            }
        }
        save()
    }
    
    func all() -> [String] {
        return allTags
    }
}

// MARK: - TagColors协议实现

extension SimpleTagManagerImpl: TagColors {
    func get(_ tag: String) -> Color {
        return colorManager.getColor(for: tag) ?? generateColor(for: tag)
    }
    
    func set(_ tag: String, _ color: Color) {
        colorManager.setColor(color, for: tag)
        objectWillChange.send()
        save()
    }
    
    private func generateColor(for tag: String) -> Color {
        let hash = abs(tag.hashValue)
        let colorIndex = hash % AppTheme.tagPresetColors.count
        let color = AppTheme.tagPresetColors[colorIndex].color
        set(tag, color)
        return color
    }
}

// MARK: - Projects协议实现

extension SimpleTagManagerImpl: Projects {
    func add(_ project: Project) {
        // 避免重复添加
        if !allProjects.contains(where: { $0.id == project.id }) {
            allProjects.append(project)
            save()
        }
    }
    
    func remove(_ id: UUID) {
        allProjects.removeAll { $0.id == id }
        save()
    }
    
    func all() -> [Project] {
        return allProjects
    }
}

// MARK: - ProjectTags协议实现

extension SimpleTagManagerImpl: ProjectTags {
    func tag(_ projectId: UUID, _ tag: String) {
        guard let index = allProjects.firstIndex(where: { $0.id == projectId }) else { return }
        
        var project = allProjects[index]
        if !project.tags.contains(tag) {
            project.addTag(tag)
            allProjects[index] = project
            
            // 确保标签存在于全局标签列表中
            if !allTags.contains(tag) {
                add(tag)
            }
            
            // 保存到系统
            project.saveTagsToSystem()
            save()
        }
    }
    
    func untag(_ projectId: UUID, _ tag: String) {
        guard let index = allProjects.firstIndex(where: { $0.id == projectId }) else { return }
        
        var project = allProjects[index]
        project.removeTag(tag)
        allProjects[index] = project
        
        // 保存到系统
        project.saveTagsToSystem()
        save()
    }
}

// MARK: - DataStorage协议实现

extension SimpleTagManagerImpl: DataStorage {
    func load() {
        allTags = Array(storage.loadTags()).sorted()
        loadProjects()
        loadWatchedDirectories()
    }
    
    func save() {
        storage.saveTags(Set(allTags))
        saveProjects()
        saveWatchedDirectories()
    }
    
    private func loadProjects() {
        // 简化的项目加载逻辑
        let cacheURL = storage.appSupportURL.appendingPathComponent("projects.json")
        do {
            let data = try Foundation.Data(contentsOf: cacheURL)
            let projects = try JSONDecoder().decode([Project].self, from: data)
            allProjects = projects
        } catch {
            print("加载项目失败: \(error)")
            allProjects = []
        }
    }
    
    private func saveProjects() {
        let cacheURL = storage.appSupportURL.appendingPathComponent("projects.json")
        do {
            let data = try JSONEncoder().encode(allProjects)
            try data.write(to: cacheURL)
        } catch {
            print("保存项目失败: \(error)")
        }
    }
    
    private func loadWatchedDirectories() {
        // 从UserDefaults加载监视目录
        let paths = UserDefaults.standard.stringArray(forKey: "WatchedDirectories") ?? []
        watchingPaths = paths
    }
    
    private func saveWatchedDirectories() {
        UserDefaults.standard.set(watchingPaths, forKey: "WatchedDirectories")
    }
}

// MARK: - WatchOps协议实现

extension SimpleTagManagerImpl: WatchOps {
    func watch(_ path: String) {
        guard !watchingPaths.contains(path) else { return }
        watchingPaths.append(path)
        save()
        refresh()
    }
    
    func unwatch(_ path: String) {
        watchingPaths.removeAll { $0 == path }
        
        // 移除该路径下的所有项目
        allProjects.removeAll { $0.path.hasPrefix(path) }
        save()
    }
    
    func watching() -> [String] {
        return watchingPaths
    }
    
    func refresh() {
        // 简化的项目刷新逻辑
        var newProjects: [Project] = []
        
        for path in watchingPaths {
            let projects = scanDirectory(path)
            newProjects.append(contentsOf: projects)
        }
        
        allProjects = newProjects
        save()
    }
    
    private func scanDirectory(_ path: String) -> [Project] {
        // 简化的目录扫描逻辑
        var projects: [Project] = []
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: path),
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) else {
            return projects
        }
        
        for case let url as URL in enumerator {
            guard url.hasDirectoryPath else { continue }
            
            // 检查是否是项目目录（包含特定文件）
            if isProjectDirectory(url) {
                let project = createProject(from: url)
                projects.append(project)
            }
        }
        
        return projects
    }
    
    private func isProjectDirectory(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        let projectFiles = [".git", "package.json", "Cargo.toml", "go.mod", "pom.xml", 
                           "Package.swift", "requirements.txt", "Gemfile"]
        
        return projectFiles.contains { file in
            fileManager.fileExists(atPath: url.appendingPathComponent(file).path)
        }
    }
    
    private func createProject(from url: URL) -> Project {
        let name = url.lastPathComponent
        let path = url.path
        
        // 获取修改时间
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modificationDate = attributes?[.modificationDate] as? Date ?? Date()
        
        // 加载系统标签
        let systemTags = Project.loadTagsFromSystem(path: path)
        
        return Project(
            id: UUID(),
            name: name,
            path: path,
            lastModified: modificationDate,
            tags: systemTags
        )
    }
}

// MARK: - 便利方法

extension SimpleTagManagerImpl {
    /// 查找项目
    func find(_ text: String) -> [Project] {
        return allProjects.filter { project in
            project.name.localizedCaseInsensitiveContains(text) ||
            project.path.localizedCaseInsensitiveContains(text)
        }
    }
    
    /// 按标签筛选项目
    func projects(with tag: String) -> [Project] {
        return allProjects.filter { $0.tags.contains(tag) }
    }
    
    /// 无标签的项目
    func untaggedProjects() -> [Project] {
        return allProjects.filter { $0.tags.isEmpty }
    }
}

// AIDEV-NOTE: 这个简化版本遵循所有Linus协议
// 每个方法都简单易懂，参数不超过3个
// 功能完整但接口清晰，易于测试和维护