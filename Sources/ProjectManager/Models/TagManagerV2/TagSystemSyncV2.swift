import AppKit
import SwiftUI

/// TagSystemSyncV2 - 重构版本的系统标签同步器
/// 
/// 改进点：
/// 1. 移除对TagManager.shared的依赖
/// 2. 使用依赖注入获取颜色信息
/// 3. 更清晰的职责分离
/// 4. 保留所有原有功能和安全措施
class TagSystemSyncV2 {
    private static var lastSyncTags: Set<String>?
    private static let syncDebounceInterval: TimeInterval = 1.0
    private static var lastSyncTime: Date?
    
    private static let systemTagMapping: [String: String] = [
        "green": "绿色",
        "绿色": "绿色",
        "red": "红色",
        "红色": "红色",
        "orange": "橙色",
        "橙色": "橙色",
        "yellow": "黄色",
        "黄色": "黄色",
        "blue": "蓝色",
        "蓝色": "蓝色",
        "purple": "紫色",
        "紫色": "紫色",
        "gray": "灰色",
        "grey": "灰色",
        "灰色": "灰色"
    ]
    
    // MARK: - 颜色提供协议
    protocol TagColorProvider {
        func getColor(for tag: String) -> Color?
    }
    
    // MARK: - 系统标签加载
    static func loadSystemTags() -> Set<String> {
        let workspace = NSWorkspace.shared
        let systemTags = workspace.fileLabels
        
        let standardizedTags = systemTags.map { tag -> String in
            if let standardTag = systemTagMapping[tag.lowercased()] {
                return standardTag
            }
            return tag
        }
        
        print("TagSystemSyncV2: 从系统加载标签 \(standardizedTags)")
        return Set(standardizedTags)
    }
    
    // MARK: - 文件标签操作
    static func loadTagsFromFile(at path: String, colorProvider: TagColorProvider? = nil) -> Set<String> {
        let url = URL(fileURLWithPath: path)
        do {
            let resourceValues = try url.resourceValues(forKeys: Set([.tagNamesKey]))
            if let tags = resourceValues.tagNames {
                let standardizedTags = tags.map { tag -> String in
                    if let standardTag = systemTagMapping[tag.lowercased()] {
                        return standardTag
                    }
                    return tag
                }
                
                if let colors = try? (url as NSURL).resourceValues(forKeys: [.labelColorKey])[.labelColorKey] as? [NSColor] {
                    for (index, tag) in standardizedTags.enumerated() where index < colors.count {
                        let nsColor = colors[index]
                        let color = Color(nsColor)
                        
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: .init("UpdateTagColor"),
                                object: nil,
                                userInfo: ["tag": tag, "color": color]
                            )
                        }
                    }
                }
                
                return Set(standardizedTags)
            }
        } catch {
            print("TagSystemSyncV2: 从文件加载标签失败 \(error)")
        }
        return []
    }
    
    static func saveTagsToFile(_ tags: Set<String>, at path: String, colorProvider: TagColorProvider? = nil) {
        let url = URL(fileURLWithPath: path)
        do {
            let currentTags = Array(loadTagsFromFile(at: path))
            let currentColors = try? (url as NSURL).resourceValues(forKeys: [.labelColorKey])[.labelColorKey] as? [NSColor]
            
            let standardizedTags = tags.map { tag -> String in
                if let standardTag = systemTagMapping[tag.lowercased()] {
                    return standardTag
                }
                return tag
            }
            
            if Set(standardizedTags) == Set(currentTags) {
                return
            }
            
            try (url as NSURL).setResourceValue(Array(standardizedTags), forKey: .tagNamesKey)
            
            let tagColors = standardizedTags.map { tag -> NSColor in
                return getColorForTag(tag, currentTags: currentTags, currentColors: currentColors, colorProvider: colorProvider)
            }
            
            try (url as NSURL).setResourceValue(tagColors, forKey: .labelColorKey)
            print("TagSystemSyncV2: 标签和颜色保存到文件成功 \(standardizedTags)")
        } catch {
            print("TagSystemSyncV2: 保存标签到文件失败 \(error)")
        }
    }
    
    // MARK: - 系统同步
    static func syncTagsToSystem(_ tags: Set<String>) {
        if let lastTags = lastSyncTags, lastTags == tags {
            return
        }
        
        if let lastSync = lastSyncTime,
            Date().timeIntervalSince(lastSync) < syncDebounceInterval
        {
            return
        }
        
        let standardizedTags = tags.map { tag -> String in
            if let standardTag = systemTagMapping[tag.lowercased()] {
                return standardTag
            }
            return tag
        }
        
        let workspace = NSWorkspace.shared
        let currentSystemTags = workspace.fileLabels
        
        var mergedTags = Set(currentSystemTags)
        mergedTags.formUnion(standardizedTags)
        
        lastSyncTags = mergedTags
        lastSyncTime = Date()
        
        print("TagSystemSyncV2: 同步标签到系统 \(mergedTags)")
    }
    
    // MARK: - 辅助方法
    private static func getColorForTag(_ tag: String, currentTags: [String], currentColors: [NSColor]?, colorProvider: TagColorProvider?) -> NSColor {
        switch tag {
        case "红色": return NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
        case "橙色": return NSColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0)
        case "黄色": return NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
        case "绿色": return NSColor(red: 0.3, green: 0.85, blue: 0.39, alpha: 1.0)
        case "蓝色": return NSColor(red: 0.0, green: 0.48, blue: 0.98, alpha: 1.0)
        case "紫色": return NSColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1.0)
        case "灰色": return NSColor(red: 0.62, green: 0.62, blue: 0.64, alpha: 1.0)
        default:
            if let index = currentTags.firstIndex(of: tag),
               let colors = currentColors,
               index < colors.count {
                return colors[index]
            }
            
            if let colorProvider = colorProvider,
               let color = colorProvider.getColor(for: tag) {
                return NSColor(color)
            }
            
            return NSColor(red: 0.62, green: 0.62, blue: 0.64, alpha: 1.0)
        }
    }
}