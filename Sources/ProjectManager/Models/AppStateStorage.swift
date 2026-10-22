import Foundation
import SwiftUI

// MARK: - 统一数据存储

/// Linus式单一真相来源 - 所有应用数据存储在一个文件中
class AppStateStorage {
    
    // MARK: - 数据结构
    
    /// 标签数据（包含名称、颜色、隐藏状态）
    struct TagData: Codable, Hashable {
        let name: String
        var color: ColorData
        var hidden: Bool
        
        struct ColorData: Codable, Hashable {
            let r: CGFloat
            let g: CGFloat
            let b: CGFloat
            let a: CGFloat
            
            init(from color: Color) {
                let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
                self.r = nsColor.redComponent
                self.g = nsColor.greenComponent
                self.b = nsColor.blueComponent
                self.a = nsColor.alphaComponent
            }
            
            func toColor() -> Color {
                return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
            }
        }
        
        init(name: String, color: Color, hidden: Bool = false) {
            self.name = name
            self.color = ColorData(from: color)
            self.hidden = hidden
        }
    }
    
    /// 应用状态文件结构
    struct AppStateFile: Codable {
        var version: Int = 2
        var tags: [TagData]
        var directories: [String]
        // projects 暂时保留在单独文件中，因为数据量大
        
        static var empty: AppStateFile {
            return AppStateFile(tags: [], directories: [])
        }
    }
    
    // MARK: - 属性
    
    private let appSupportURL: URL
    private let stateFileName = "app_state.json"
    
    // 旧文件名（用于迁移）
    private let legacyTagsFileName = "tags.json"
    private let legacyTagColorsFileName = "tag_colors.json"
    private let legacyHiddenTagsFileName = "hidden_tags.json"
    private let legacyDirectoriesFileName = "directories.json"
    
    // MARK: - 初始化
    
    init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        appSupportURL = paths[0].appendingPathComponent("com.projectmanager")
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
    }

    /// 测试/隔离用：把状态存储指向任意目录，避免测试写到真实用户数据。
    init(appSupportURL: URL) {
        self.appSupportURL = appSupportURL
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
    }
    
    private var stateFileURL: URL {
        return appSupportURL.appendingPathComponent(stateFileName)
    }
    
    // MARK: - 主要接口
    
    /// 加载应用状态（自动处理迁移）
    func load() -> AppStateFile {
        // 1. 尝试加载新格式
        if let state = loadNewFormat() {
            print("✅ 从 app_state.json 加载数据成功")
            return state
        }
        
        // 2. 尝试从旧格式迁移
        print("📦 未找到 app_state.json，尝试从旧格式迁移...")
        if let migratedState = migrateFromLegacy() {
            // 保存迁移后的数据
            save(migratedState)
            // 备份旧文件
            backupLegacyFiles()
            print("✅ 数据迁移完成")
            return migratedState
        }
        
        // 3. 返回空状态（全新安装）
        print("🆕 首次运行，创建空状态")
        return .empty
    }
    
    /// 保存应用状态
    func save(_ state: AppStateFile) {
        saveReportingResult(state)
    }

    /// 保存应用状态，并把失败原因交给调用方。
    ///
    /// 目录被删（测试收尾、用户清理缓存）时返回 `.failure(.directoryUnavailable)`，
    /// 不重建目录，也不把错误只留在控制台里。
    @discardableResult
    func saveReportingResult(_ state: AppStateFile) -> Result<Void, LocalPersistenceError> {
        let result = LocalJSONFile.save(state, to: stateFileURL, formatting: .prettyPrinted)
        if case .failure(let error) = result {
            Log.error("保存 app_state.json 失败: \(error.localizedDescription)")
        }
        return result
    }
    
    // MARK: - 私有方法
    
    private func loadNewFormat() -> AppStateFile? {
        guard FileManager.default.fileExists(atPath: stateFileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: stateFileURL)
            let decoder = JSONDecoder()
            return try decoder.decode(AppStateFile.self, from: data)
        } catch {
            print("⚠️ 解析 app_state.json 失败: \(error)")
            return nil
        }
    }
    
    /// 从旧格式迁移数据
    private func migrateFromLegacy() -> AppStateFile? {
        // 加载旧的标签列表
        let legacyTags = loadLegacyTags()
        let legacyColors = loadLegacyTagColors()
        let legacyHidden = loadLegacyHiddenTags()
        let legacyDirectories = loadLegacyDirectories()
        
        // 合并标签来源：tags.json + tag_colors.json 的 keys
        var allTagNames = legacyTags
        allTagNames.formUnion(Set(legacyColors.keys))
        
        if allTagNames.isEmpty && legacyDirectories.isEmpty {
            return nil  // 没有可迁移的数据
        }
        
        // 构建新的标签数据
        var tags: [TagData] = []
        for name in allTagNames {
            let color = legacyColors[name] ?? generateDefaultColor(for: name)
            let hidden = legacyHidden.contains(name)
            tags.append(TagData(name: name, color: color, hidden: hidden))
        }
        
        print("📊 迁移统计: \(tags.count) 个标签, \(legacyDirectories.count) 个目录")
        
        return AppStateFile(
            version: 2,
            tags: tags,
            directories: Array(legacyDirectories)
        )
    }
    
    private func loadLegacyTags() -> Set<String> {
        let url = appSupportURL.appendingPathComponent(legacyTagsFileName)
        guard let data = try? Data(contentsOf: url),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(tags)
    }
    
    private func loadLegacyTagColors() -> [String: Color] {
        struct ColorComponents: Codable {
            let red: CGFloat
            let green: CGFloat
            let blue: CGFloat
            let alpha: CGFloat
        }
        
        let url = appSupportURL.appendingPathComponent(legacyTagColorsFileName)
        guard let data = try? Data(contentsOf: url),
              let colors = try? JSONDecoder().decode([String: ColorComponents].self, from: data) else {
            return [:]
        }
        
        return colors.mapValues { c in
            Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        }
    }
    
    private func loadLegacyHiddenTags() -> Set<String> {
        let url = appSupportURL.appendingPathComponent(legacyHiddenTagsFileName)
        guard let data = try? Data(contentsOf: url),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(tags)
    }
    
    private func loadLegacyDirectories() -> Set<String> {
        let url = appSupportURL.appendingPathComponent(legacyDirectoriesFileName)
        guard let data = try? Data(contentsOf: url),
              let dirs = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(dirs)
    }
    
    private func backupLegacyFiles() {
        let legacyFiles = [
            legacyTagsFileName,
            legacyTagColorsFileName,
            legacyHiddenTagsFileName,
            legacyDirectoriesFileName
        ]
        
        let fm = FileManager.default
        for fileName in legacyFiles {
            let url = appSupportURL.appendingPathComponent(fileName)
            let backupURL = appSupportURL.appendingPathComponent(fileName + ".bak")
            
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: backupURL)  // 删除旧备份
                try? fm.moveItem(at: url, to: backupURL)
                print("📁 已备份: \(fileName) → \(fileName).bak")
            }
        }
    }
    
    private func generateDefaultColor(for tag: String) -> Color {
        let presetColors: [Color] = [
            Color(red: 0.91, green: 0.30, blue: 0.24),  // 红
            Color(red: 0.95, green: 0.61, blue: 0.07),  // 橙
            Color(red: 0.95, green: 0.77, blue: 0.06),  // 黄
            Color(red: 0.18, green: 0.80, blue: 0.44),  // 绿
            Color(red: 0.20, green: 0.60, blue: 0.86),  // 蓝
            Color(red: 0.61, green: 0.35, blue: 0.71),  // 紫
        ]
        let hash = abs(tag.hashValue)
        let index = hash % presetColors.count
        return presetColors[index]
    }
}
