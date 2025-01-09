import Foundation
import SwiftUI

class TagStorage {
    let appSupportURL: URL
    private let tagsFileName = "tags.json"
    private let tagColorsFileName = "tag_colors.json"

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

    func loadTagColors() -> [String: Color] {
        do {
            let data = try Data(contentsOf: tagColorsFileURL)
            let decoder = JSONDecoder()
            let decodedColors = try decoder.decode([String: String].self, from: data)
            print("成功解码标签颜色: \(decodedColors)")
            return decodedColors.mapValues { Color(hex: $0) }
        } catch {
            print("加载标签颜色失败（可能是首次运行）: \(error)")
            return [:]
        }
    }

    func saveTagColors(_ colors: [String: Color]) {
        do {
            let colorData = colors.compactMapValues { color -> String? in
                let nsColor = NSColor(color)
                let red = Int(round(nsColor.redComponent * 255))
                let green = Int(round(nsColor.greenComponent * 255))
                let blue = Int(round(nsColor.blueComponent * 255))
                return String(format: "#%02X%02X%02X", red, green, blue)
            }
            let encoder = JSONEncoder()
            let data = try encoder.encode(colorData)
            try data.write(to: tagColorsFileURL)
            print("保存标签颜色成功")
        } catch {
            print("保存标签颜色失败: \(error)")
        }
    }
}
