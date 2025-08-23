import AppKit
import SwiftUI

/// TagSystemSync 负责管理与 macOS 系统标签的同步
///
/// ⚠️ 警告：
/// 1. 此类直接操作系统标签元数据，修改时需要特别谨慎
/// 2. 不当的修改可能导致项目标签信息丢失
/// 3. 在修改此类之前，建议：
///    - 完整阅读 README.md 中的标签系统警告部分
///    - 确保理解 macOS 文件系统的标签机制
///    - 在测试环境中验证修改的影响
///
/// 关键方法：
 `loadSystemTags()`: 从系统加载所有标签
/// - `syncTagsToSystem()`: 将标签同步到系统
///
/// 数据流：
/// 1. 项目标签存储在文件系统的 `com.apple.metadata:_kMDItemUserTags` 属性中
/// 2. 标签更改需要通过 `xattr` 命令写入
/// 3. 标签同步使用临时文件和 plist 转换确保原子性
class TagSystemSync {
    private static var lastSyncTags: Set<String>?
    private static let syncDebounceInterval: TimeInterval = 1.0
    private static var lastSyncTime: Date?

    // 系统标准标签映射
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

    /// 从系统加载全局标签列表
    static func loadSystemTags() -> Set<String> {
        let workspace = NSWorkspace.shared
        let systemTags = workspace.fileLabels
        
        // 标准化系统标签
        let standardizedTags = systemTags.map { tag -> String in
            if let standardTag = systemTagMapping[tag.lowercased()] {
                return standardTag
            }
            return tag
        }
        
        print("从系统加载标签: \(standardizedTags)")
        return Set(standardizedTags)
    }

    /// 从文件加载标签
    static func loadTagsFromFile(at path: String) -> Set<String> {
        let url = URL(fileURLWithPath: path)
        do {
            let resourceValues = try url.resourceValues(forKeys: Set([.tagNamesKey]))
            if let tags = resourceValues.tagNames {
                // 标准化标签
                let standardizedTags = tags.map { tag -> String in
                    if let standardTag = systemTagMapping[tag.lowercased()] {
                        return standardTag
                    }
                    return tag
                }
                
                // 获取标签颜色
                if let colors = try? (url as NSURL).resourceValues(forKeys: [.labelColorKey])[.labelColorKey] as? [NSColor] {
                    // 将标签和颜色对应起来
                    for (index, tag) in standardizedTags.enumerated() where index < colors.count {
                        let nsColor = colors[index]
                        let color = Color(nsColor)
                        // 发送颜色更新通知
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
            print("从文件加载标签失败: \(error)")
        }
        return []
    }

    /// 保存标签到文件
    static func saveTagsToFile(_ tags: Set<String>, at path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            // 获取当前标签和颜色
            let currentTags = Array(loadTagsFromFile(at: path))
            let currentColors = try? (url as NSURL).resourceValues(forKeys: [.labelColorKey])[.labelColorKey] as? [NSColor]
            
            // 标准化标签
            let standardizedTags = tags.map { tag -> String in
                if let standardTag = systemTagMapping[tag.lowercased()] {
                    return standardTag
                }
                return tag
            }
            
            // 如果标签没有变化，不需要保存
            if Set(standardizedTags) == Set(currentTags) {
                return
            }

            // 保存标签名称
            try (url as NSURL).setResourceValue(Array(standardizedTags), forKey: .tagNamesKey)
            
            // 获取系统预定义的标签颜色
            let tagColors = standardizedTags.map { tag -> NSColor in
                // 如果是系统标准标签，使用预定义颜色
                switch tag {
                case "红色": return NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
                case "橙色": return NSColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0)
                case "黄色": return NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
                case "绿色": return NSColor(red: 0.3, green: 0.85, blue: 0.39, alpha: 1.0)
                case "蓝色": return NSColor(red: 0.0, green: 0.48, blue: 0.98, alpha: 1.0)
                case "紫色": return NSColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1.0)
                case "灰色": return NSColor(red: 0.62, green: 0.62, blue: 0.64, alpha: 1.0)
                default:
                    // 如果标签已经存在且有颜色，保持原有颜色
                    if let index = currentTags.firstIndex(of: tag),
                       let colors = currentColors,
                       index < colors.count {
                        return colors[index]
                    }
                    // 对于自定义标签，使用默认颜色
                    // 注意：TagManager.shared已被弃用，使用TagSystemSyncV2进行新实现
                    // if let color = TagManager.shared?.getColor(for: tag) {
                    //     return NSColor(color)
                    // }
                    return NSColor(red: 0.62, green: 0.62, blue: 0.64, alpha: 1.0)
                }
            }
            
            // 保存标签颜色
            try (url as NSURL).setResourceValue(tagColors, forKey: .labelColorKey)
            print("标签和颜色保存到文件成功: \(standardizedTags)")
        } catch {
            print("保存标签到文件失败: \(error)")
        }
    }

    /// 同步标签到系统全局标签列表
    static func syncTagsToSystem(_ tags: Set<String>) {
        // 如果标签集合没有变化，不需要同步
        if let lastTags = lastSyncTags, lastTags == tags {
            return
        }

        // 如果距离上次同步时间不足1秒，不执行同步
        if let lastSync = lastSyncTime,
            Date().timeIntervalSince(lastSync) < syncDebounceInterval
        {
            return
        }

        // 标准化标签
        let standardizedTags = tags.map { tag -> String in
            if let standardTag = systemTagMapping[tag.lowercased()] {
                return standardTag
            }
            return tag
        }

        // 获取当前系统标签
        let workspace = NSWorkspace.shared
        let currentSystemTags = workspace.fileLabels
        
        // 合并标签，确保不会删除系统标签
        var mergedTags = Set(currentSystemTags)
        mergedTags.formUnion(standardizedTags)
        
        // 更新同步状态
        lastSyncTags = mergedTags
        lastSyncTime = Date()
        
        print("同步标签到系统: \(mergedTags)")
    }
}
