import SwiftUI
import AppKit

/// 🔥 Linus式简化标签管理器
/// 合并原来的 TagManager + TagColorManager + TagStorage 功能
/// 目标：删掉90%的抽象层，保留100%的功能
class CoreTagManager: ObservableObject {
    
    // MARK: - Published Properties (与旧版本完全相同，确保UI兼容性)
    @Published var allTags: Set<String> = []
    @Published var hiddenTags: Set<String> = []
    @Published var tagColors: [String: Color] = [:]
    
    // MARK: - Storage (直接处理，不需要额外的Storage类)
    private let appSupportURL: URL
    private let tagsFileName = "tags.json"
    private let tagColorsFileName = "tag_colors.json" 
    private let hiddenTagsFileName = "hidden_tags.json"
    
    // MARK: - Cache (简化缓存逻辑)
    private var tagUsageCache: [String: Int] = [:]
    private var cacheNeedsUpdate = true
    
    // MARK: - 初始化
    init() {
        // 设置存储路径
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        appSupportURL = paths[0].appendingPathComponent("com.projectmanager")
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        
        // 加载所有数据
        loadAllData()
    }
    
    // MARK: - 数据加载 (合并所有加载逻辑)
    private func loadAllData() {
        allTags = loadTags()
        hiddenTags = loadHiddenTags() 
        tagColors = loadTagColors()
        
        // 确保所有标签都有颜色
        initializeTagColors()
        
        print("CoreTagManager 初始化完成: \(allTags.count) 个标签")
    }
    
    private func loadTags() -> Set<String> {
        let url = appSupportURL.appendingPathComponent(tagsFileName)
        do {
            let data = try Data(contentsOf: url)
            let tags = try JSONDecoder().decode([String].self, from: data)
            return Set(tags)
        } catch {
            return []
        }
    }
    
    private func loadHiddenTags() -> Set<String> {
        let url = appSupportURL.appendingPathComponent(hiddenTagsFileName)
        do {
            let data = try Data(contentsOf: url)
            let tags = try JSONDecoder().decode([String].self, from: data)
            return Set(tags)
        } catch {
            return []
        }
    }
    
    private struct ColorComponents: Codable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }
    
    private func loadTagColors() -> [String: Color] {
        let url = appSupportURL.appendingPathComponent(tagColorsFileName)
        do {
            let data = try Data(contentsOf: url)
            let colorData = try JSONDecoder().decode([String: ColorComponents].self, from: data)
            return colorData.mapValues { components in
                Color(.sRGB,
                      red: components.red,
                      green: components.green,
                      blue: components.blue,
                      opacity: components.alpha)
            }
        } catch {
            return [:]
        }
    }
    
    private func initializeTagColors() {
        for tag in allTags {
            if tagColors[tag] == nil {
                let hash = abs(tag.hashValue)
                let colorIndex = hash % AppTheme.tagPresetColors.count
                tagColors[tag] = AppTheme.tagPresetColors[colorIndex].color
            }
        }
    }
    
    // MARK: - 数据保存 (合并所有保存逻辑)
    func saveAll() {
        saveTags()
        saveHiddenTags()
        saveTagColors()
    }
    
    private func saveTags() {
        let url = appSupportURL.appendingPathComponent(tagsFileName)
        do {
            let data = try JSONEncoder().encode(Array(allTags))
            try data.write(to: url)
        } catch {
            print("保存标签失败: \(error)")
        }
    }
    
    private func saveHiddenTags() {
        let url = appSupportURL.appendingPathComponent(hiddenTagsFileName)
        do {
            let data = try JSONEncoder().encode(Array(hiddenTags))
            try data.write(to: url)
        } catch {
            print("保存隐藏标签失败: \(error)")
        }
    }
    
    private func saveTagColors() {
        let url = appSupportURL.appendingPathComponent(tagColorsFileName)
        do {
            let colorData = tagColors.mapValues { color -> ColorComponents in
                let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
                return ColorComponents(
                    red: nsColor.redComponent,
                    green: nsColor.greenComponent,
                    blue: nsColor.blueComponent,
                    alpha: nsColor.alphaComponent
                )
            }
            let data = try JSONEncoder().encode(colorData)
            try data.write(to: url)
        } catch {
            print("保存标签颜色失败: \(error)")
        }
    }
    
    // MARK: - 标签操作 (完全兼容旧版本API)
    
    func addTag(_ tag: String, color: Color) {
        if !allTags.contains(tag) {
            allTags.insert(tag)
            tagColors[tag] = color
            cacheNeedsUpdate = true
            saveAll()
        }
    }
    
    func removeTag(_ tag: String) {
        allTags.remove(tag)
        tagColors.removeValue(forKey: tag)
        hiddenTags.remove(tag)
        cacheNeedsUpdate = true
        saveAll()
    }
    
    func renameTag(_ oldName: String, to newName: String, color: Color) {
        if allTags.contains(oldName) && !allTags.contains(newName) {
            allTags.remove(oldName)
            allTags.insert(newName)
            
            tagColors.removeValue(forKey: oldName)
            tagColors[newName] = color
            
            if hiddenTags.contains(oldName) {
                hiddenTags.remove(oldName)
                hiddenTags.insert(newName)
            }
            
            cacheNeedsUpdate = true
            saveAll()
            
            // TODO: 需要项目管理器配合更新项目中的标签名
        }
    }
    
    func getColor(for tag: String) -> Color {
        // 特殊标签的固定颜色
        if tag == "全部" { return AppTheme.accent }
        if tag == "没有标签" { return AppTheme.accent.opacity(0.7) }
        
        // 返回存储的颜色，如果没有则生成新的
        if let color = tagColors[tag] {
            return color
        }
        
        let hash = abs(tag.hashValue)
        let colorIndex = hash % AppTheme.tagPresetColors.count
        let color = AppTheme.tagPresetColors[colorIndex].color
        tagColors[tag] = color
        return color
    }
    
    func setColor(_ color: Color, for tag: String) {
        if tagColors[tag] != color {
            tagColors[tag] = color
            saveTagColors()
        }
    }
    
    // MARK: - 标签隐藏管理
    
    func toggleTagVisibility(_ tag: String) {
        if hiddenTags.contains(tag) {
            hiddenTags.remove(tag)
        } else {
            hiddenTags.insert(tag)
        }
        saveHiddenTags()
    }
    
    func isTagHidden(_ tag: String) -> Bool {
        return hiddenTags.contains(tag)
    }
    
    // MARK: - 标签统计 (简化缓存逻辑)
    
    func updateTagUsage(from projects: [UUID: Project]) {
        var counts: [String: Int] = [:]
        for project in projects.values {
            for tag in project.tags {
                counts[tag, default: 0] += 1
            }
        }
        tagUsageCache = counts
        cacheNeedsUpdate = false
    }
    
    func getUsageCount(for tag: String) -> Int {
        return tagUsageCache[tag] ?? 0
    }
    
    func invalidateTagUsageCache() {
        cacheNeedsUpdate = true
    }
}

// MARK: - 功能对比验证扩展
extension CoreTagManager {
    
    /// 验证与旧版本功能一致性的方法
    func validateFunctionality() -> [String] {
        var results: [String] = []
        
        // 检查基本功能
        let testTag = "TestTag_\(UUID().uuidString.prefix(8))"
        let testColor = Color.red
        
        // 测试添加标签
        let initialCount = allTags.count
        addTag(testTag, color: testColor)
        if allTags.count == initialCount + 1 && allTags.contains(testTag) {
            results.append("✅ 添加标签功能正常")
        } else {
            results.append("❌ 添加标签功能异常")
        }
        
        // 测试颜色设置
        if getColor(for: testTag) == testColor {
            results.append("✅ 标签颜色功能正常")
        } else {
            results.append("❌ 标签颜色功能异常")
        }
        
        // 测试隐藏功能
        toggleTagVisibility(testTag)
        if isTagHidden(testTag) {
            results.append("✅ 标签隐藏功能正常")
        } else {
            results.append("❌ 标签隐藏功能异常")
        }
        
        // 清理测试数据
        removeTag(testTag)
        if !allTags.contains(testTag) {
            results.append("✅ 删除标签功能正常")
        } else {
            results.append("❌ 删除标签功能异常")
        }
        
        return results
    }
}