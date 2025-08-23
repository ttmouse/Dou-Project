import SwiftUI
import Combine

// MARK: - TagStore协议
protocol TagStore: ObservableObject {
    var allTags: Set<String> { get }
    var hiddenTags: Set<String> { get }
    
    func addTag(_ tag: String)
    func removeTag(_ tag: String)
    func renameTag(from oldName: String, to newName: String)
    func toggleTagVisibility(_ tag: String)
    func isTagHidden(_ tag: String) -> Bool
    func getUsageCount(for tag: String) -> Int
    func invalidateUsageCache()
}

// MARK: - TagStore实现
class DefaultTagStore: TagStore, ObservableObject {
    
    @Published var allTags: Set<String> = []
    @Published var hiddenTags: Set<String> = []
    
    private let storage: TagStorage
    private var projectStore: (any ProjectStore)?
    
    // 标签统计缓存
    private var cachedTagUsageCount: [String: Int]?
    private var lastProjectUpdateTime: Date?
    
    init(storage: TagStorage) {
        self.storage = storage
        loadTags()
    }
    
    // 设置项目存储引用用于统计
    func setProjectStore(_ projectStore: any ProjectStore) {
        self.projectStore = projectStore
    }
    
    // MARK: - 数据加载
    private func loadTags() {
        allTags = storage.loadTags()
        hiddenTags = storage.loadHiddenTags()
        print("TagStore已加载标签: \(allTags.count)个, 隐藏: \(hiddenTags.count)个")
    }
    
    // MARK: - 标签管理
    func addTag(_ tag: String) {
        if !allTags.contains(tag) {
            allTags.insert(tag)
            saveTags()
            print("TagStore: 添加标签 '\(tag)'")
        }
    }
    
    func removeTag(_ tag: String) {
        if allTags.contains(tag) {
            allTags.remove(tag)
            hiddenTags.remove(tag)
            
            // 通知项目存储移除该标签
            projectStore?.removeTagFromAllProjects(tag)
            
            invalidateUsageCache()
            saveTags()
            print("TagStore: 移除标签 '\(tag)'")
        }
    }
    
    func renameTag(from oldName: String, to newName: String) {
        if allTags.contains(oldName) && !allTags.contains(newName) {
            allTags.remove(oldName)
            allTags.insert(newName)
            
            // 更新隐藏状态
            if hiddenTags.contains(oldName) {
                hiddenTags.remove(oldName)
                hiddenTags.insert(newName)
            }
            
            // 通知项目存储更新标签名称
            projectStore?.renameTagInAllProjects(from: oldName, to: newName)
            
            invalidateUsageCache()
            saveTags()
            print("TagStore: 重命名标签 '\(oldName)' -> '\(newName)'")
        }
    }
    
    // MARK: - 标签可见性管理
    func toggleTagVisibility(_ tag: String) {
        if hiddenTags.contains(tag) {
            hiddenTags.remove(tag)
        } else {
            hiddenTags.insert(tag)
        }
        saveTags()
        print("TagStore: 切换标签 '\(tag)' 可见性")
    }
    
    func isTagHidden(_ tag: String) -> Bool {
        return hiddenTags.contains(tag)
    }
    
    // MARK: - 标签统计
    func getUsageCount(for tag: String) -> Int {
        return tagUsageCount[tag] ?? 0
    }
    
    private var tagUsageCount: [String: Int] {
        // 如果项目数据没有更新，直接返回缓存
        if let cached = cachedTagUsageCount,
           let lastUpdate = lastProjectUpdateTime,
           Date().timeIntervalSince(lastUpdate) < 1.0 {
            return cached
        }
        
        // 重新计算并缓存
        guard let projectStore = projectStore else {
            return [:]
        }
        
        var counts: [String: Int] = [:]
        for project in projectStore.getAllProjects() {
            for tag in project.tags {
                counts[tag, default: 0] += 1
            }
        }
        
        cachedTagUsageCount = counts
        lastProjectUpdateTime = Date()
        return counts
    }
    
    func invalidateUsageCache() {
        cachedTagUsageCount = nil
        lastProjectUpdateTime = nil
    }
    
    // MARK: - 数据持久化
    private func saveTags() {
        storage.saveTags(allTags)
        storage.saveHiddenTags(hiddenTags)
        
        // 同步系统标签
        TagSystemSync.syncTagsToSystem(allTags)
    }
}