import Foundation
import SwiftUI

class TagStorage {
    let appSupportURL: URL
    private let tagsFileName = "tags.json"
    private let tagColorsFileName = "tag_colors.json"
    private let hiddenTagsFileName = "hidden_tags.json"

    init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        appSupportURL = paths[0].appendingPathComponent("com.projectmanager")
        // 确保目录存在
        try? FileManager.default.createDirectory(
            at: appSupportURL, withIntermediateDirectories: true)
    }

    private var tagsFileURL: URL {
        return appSupportURL.appendingPathComponent(tagsFileName)
    }

    private var tagColorsFileURL: URL {
        return appSupportURL.appendingPathComponent(tagColorsFileName)
    }
    
    private var hiddenTagsFileURL: URL {
        return appSupportURL.appendingPathComponent(hiddenTagsFileName)
    }

    func loadTags() -> Set<String> {
        do {
            let data = try Data(contentsOf: tagsFileURL)
            let decoder = JSONDecoder()
            let savedTags = try decoder.decode([String].self, from: data)
            print("从文件加载标签列表: \(savedTags)")
            return Set(savedTags)
        } catch {
            print("加载标签列表失败（可能是首次运行）: \(error)")
            return []
        }
    }

    func saveTags(_ tags: Set<String>) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(Array(tags))
            try data.write(to: tagsFileURL)
            print("保存标签列表到文件: \(Array(tags))")
        } catch {
            print("保存标签列表失败: \(error)")
        }
    }

    // 用于保存颜色组件的结构
    private struct ColorComponents: Codable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    func loadTagColors() -> [String: Color] {
        do {
            let data = try Data(contentsOf: tagColorsFileURL)
            let decoder = JSONDecoder()
            let decodedColors = try decoder.decode([String: ColorComponents].self, from: data)
            print("成功解码标签颜色")
            return decodedColors.mapValues { components in
                Color(.sRGB,
                      red: components.red,
                      green: components.green,
                      blue: components.blue,
                      opacity: components.alpha)
            }
        } catch {
            print("加载标签颜色失败（可能是首次运行）: \(error)")
            return [:]
        }
    }

    func saveTagColors(_ colors: [String: Color]) {
        do {
            let colorData = colors.mapValues { color -> ColorComponents in
                let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
                return ColorComponents(
                    red: nsColor.redComponent,
                    green: nsColor.greenComponent,
                    blue: nsColor.blueComponent,
                    alpha: nsColor.alphaComponent
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(colorData)
            try data.write(to: tagColorsFileURL)
            print("保存标签颜色成功")
        } catch {
            print("保存标签颜色失败: \(error)")
        }
    }
    
    func loadHiddenTags() -> Set<String> {
        do {
            let data = try Data(contentsOf: hiddenTagsFileURL)
            let decoder = JSONDecoder()
            let hiddenTags = try decoder.decode([String].self, from: data)
            print("从文件加载隐藏标签列表: \(hiddenTags)")
            return Set(hiddenTags)
        } catch {
            print("加载隐藏标签列表失败（可能是首次运行）: \(error)")
            return []
        }
    }
    
    func saveHiddenTags(_ hiddenTags: Set<String>) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(Array(hiddenTags))
            try data.write(to: hiddenTagsFileURL)
            print("保存隐藏标签列表到文件: \(Array(hiddenTags))")
        } catch {
            print("保存隐藏标签列表失败: \(error)")
        }
    }
}
