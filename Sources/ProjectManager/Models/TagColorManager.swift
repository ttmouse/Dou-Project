import SwiftUI

class TagColorManager: ObservableObject {
    @Published private(set) var tagColors: [String: Color] = [:]
    @Published private(set) var lastUpdate = Date()  // 添加更新时间戳
    private let storage: TagStorage

    init(storage: TagStorage) {
        self.storage = storage
        self.tagColors = storage.loadTagColors()
        
        // 监听标签颜色更新通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTagColorUpdate(_:)),
            name: .init("UpdateTagColor"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleTagColorUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let tag = userInfo["tag"] as? String,
              let color = userInfo["color"] as? Color else {
            return
        }
        
        // 如果颜色已存在且相同，不做更新
        if let existingColor = tagColors[tag], existingColor == color {
            return
        }
        
        // 更新颜色
        setColor(color, for: tag)
    }

    func getColor(for tag: String) -> Color? {
        // 为"全部"标签返回固定颜色
        if tag == "全部" {
            return AppTheme.accent
        }
        
        // 为"没有标签"返回固定颜色
        if tag == "没有标签" {
            return AppTheme.accent.opacity(0.7)
        }

        return tagColors[tag]
    }

    func setColor(_ color: Color, for tag: String) {
        // 如果颜色没有变化，不做任何操作
        if tagColors[tag] == color {
            return
        }
        
        // 更新颜色并保存
        tagColors[tag] = color
        lastUpdate = Date()  // 更新时间戳
        saveColors()
        
        // 通知观察者有更新
        objectWillChange.send()
    }

    private func saveColors() {
        storage.saveTagColors(tagColors)
    }

    func removeColor(for tag: String) {
        tagColors.removeValue(forKey: tag)
        lastUpdate = Date()  // 更新时间戳
        saveColors()

        // 通知观察者有更新
        objectWillChange.send()
    }

    func removeColors(for tags: Set<String>) {
        for tag in tags {
            tagColors.removeValue(forKey: tag)
        }
        lastUpdate = Date()
        saveColors()

        // 通知观察者有更新
        objectWillChange.send()
    }
    
    /// 获取所有有颜色记录的标签 - 用于启动时恢复丢失的标签
    func getAllTags() -> Set<String> {
        return Set(tagColors.keys)
    }
}
