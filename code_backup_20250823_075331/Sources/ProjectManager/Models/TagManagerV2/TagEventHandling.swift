import Foundation
import Combine
import SwiftUI

/// TagEventHandling - 处理标签系统的事件和通知
class TagEventHandling {
    weak var core: TagManagerCore?
    private var cancellables = Set<AnyCancellable>()
    
    init(core: TagManagerCore) {
        self.core = core
        setupEventHandlers()
    }
    
    // MARK: - 事件处理设置
    private func setupEventHandlers() {
        setupColorUpdateNotifications()
        setupFileSystemNotifications()
        setupAppLifecycleEvents()
    }
    
    // MARK: - 颜色更新通知
    private func setupColorUpdateNotifications() {
        NotificationCenter.default
            .publisher(for: NSNotification.Name("UpdateTagColor"))
            .sink { [weak self] notification in
                self?.handleTagColorUpdate(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleTagColorUpdate(_ notification: Notification) {
        guard let core = core,
              let userInfo = notification.userInfo,
              let tag = userInfo["tag"] as? String,
              let color = userInfo["color"] as? Color else { return }
        
        core.setColor(color, for: tag)
        print("TagEventHandling: 更新标签颜色 \(tag)")
    }
    
    // MARK: - 文件系统通知
    private func setupFileSystemNotifications() {
        NotificationCenter.default
            .publisher(for: NSNotification.Name("ProjectTagsChanged"))
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] notification in
                self?.handleProjectTagsChanged(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleProjectTagsChanged(_ notification: Notification) {
        guard let core = core,
              let userInfo = notification.userInfo,
              let projectId = userInfo["projectId"] as? UUID else { return }
        
        core.invalidateTagUsageCache()
        print("TagEventHandling: 项目标签变化 \(projectId)")
    }
    
    // MARK: - 应用生命周期事件
    private func setupAppLifecycleEvents() {
        NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.handleAppWillTerminate()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppDidBecomeActive()
            }
            .store(in: &cancellables)
    }
    
    private func handleAppWillTerminate() {
        guard let core = core else { return }
        
        print("TagEventHandling: 应用即将终止，保存所有数据")
        core.saveAll(force: true)
    }
    
    private func handleAppDidBecomeActive() {
        guard let core = core else { return }
        
        print("TagEventHandling: 应用激活，检查数据更新")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let systemTags = TagSystemSync.loadSystemTags()
            core.allTags.formUnion(systemTags)
        }
    }
    
    // MARK: - 自定义事件发送
    func sendTagAddedEvent(_ tag: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("TagAdded"),
            object: nil,
            userInfo: ["tag": tag]
        )
    }
    
    func sendTagRemovedEvent(_ tag: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("TagRemoved"),
            object: nil,
            userInfo: ["tag": tag]
        )
    }
    
    func sendTagRenamedEvent(from oldTag: String, to newTag: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("TagRenamed"),
            object: nil,
            userInfo: ["oldTag": oldTag, "newTag": newTag]
        )
    }
    
    func sendProjectTagsUpdatedEvent(projectId: UUID, tags: Set<String>) {
        NotificationCenter.default.post(
            name: NSNotification.Name("ProjectTagsUpdated"),
            object: nil,
            userInfo: ["projectId": projectId, "tags": tags]
        )
    }
    
    // MARK: - 清理
    deinit {
        cancellables.removeAll()
    }
}