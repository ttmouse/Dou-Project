import Foundation
import SwiftUI

/// 本地 JSON 落盘的失败原因。
///
/// 定时/防抖保存发生在目录可能已经被删掉之后（测试收尾、用户清理缓存、
/// 外置盘被拔掉）。这类失败必须能被调用方看见并安静收场：
/// 不能抛未捕获错误，也不能顺手在别处重建目录再把问题掩盖过去。
enum LocalPersistenceError: Error, Equatable, LocalizedError {
    case directoryUnavailable(URL)
    case encodingFailed(URL, String)
    case writeFailed(URL, String)

    var errorDescription: String? {
        switch self {
        case .directoryUnavailable(let url):
            return "目标目录不存在，已跳过写入: \(url.path)"
        case .encodingFailed(let url, let reason):
            return "编码失败: \(url.path)（\(reason)）"
        case .writeFailed(let url, let reason):
            return "写入失败: \(url.path)（\(reason)）"
        }
    }
}

/// 统一的本地 JSON 写入入口：先确认目标目录还在，再原子写入。
///
/// 这里刻意不调用 `createDirectory`：目录消失意味着这次保存已经失去目标，
/// 悄悄重建只会把数据写到用户/测试都不期望的位置（临时目录尤其明显）。
/// 目标不存在时返回 `.failure(.directoryUnavailable)`，由调用方决定是记日志还是重试。
enum LocalJSONFile {
    static func save<T: Encodable>(
        _ value: T,
        to url: URL,
        formatting: JSONEncoder.OutputFormatting = []
    ) -> Result<Void, LocalPersistenceError> {
        // 统一成无尾斜杠的标准化路径：目录比较和日志里才不会出现两种写法。
        let directoryPath = url.deletingLastPathComponent().standardizedFileURL.path
        let directory = URL(fileURLWithPath: directoryPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .failure(.directoryUnavailable(directory))
        }

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = formatting
            data = try encoder.encode(value)
        } catch {
            return .failure(.encodingFailed(url, error.localizedDescription))
        }

        do {
            try data.write(to: url, options: .atomic)
            return .success(())
        } catch {
            // 检查与写入之间目录可能刚被删掉（定时保存最常见的时序），
            // 这种情况仍按「目标目录不存在」上报，调用方看到的原因才稳定。
            var stillDirectory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: directoryPath, isDirectory: &stillDirectory) {
                return .failure(.directoryUnavailable(directory))
            }
            return .failure(.writeFailed(url, error.localizedDescription))
        }
    }
}

/// 管理标签数据的存储（旧版）
/// - Warning: 已废弃。仅用于从旧版本数据结构迁移。
/// 请使用 `AppStateStorage` 进行所有新的开发。
class TagStorage {
    let appSupportURL: URL
    private let tagsFileName = "tags.json"
    private let tagColorsFileName = "tag_colors.json"
    private let hiddenTagsFileName = "hidden_tags.json"
    private let autoTaggingFileName = "auto_tagging.json"

    init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        appSupportURL = paths[0].appendingPathComponent("com.projectmanager")
        try? FileManager.default.createDirectory(
            at: appSupportURL, withIntermediateDirectories: true)
    }

    /// 测试/隔离用：把存储指向任意目录
    /// 背景：`appSupportURL` 是 `let` 且类非 open，测试无法继承覆盖它，
    /// 于是任何涉及存储的测试都会读写真实用户数据（曾经污染过 projects.json）。
    init(appSupportURL: URL) {
        self.appSupportURL = appSupportURL
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

    private var autoTaggingFileURL: URL {
        return appSupportURL.appendingPathComponent(autoTaggingFileName)
    }

    private var projectsFileURL: URL {
        return appSupportURL.appendingPathComponent("projects.json")
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

    func saveProjects(_ projects: [Project]) {
        saveProjectsReportingResult(projects)
    }

    /// 保存项目列表并把失败原因交给调用方。
    ///
    /// 异步保存（定时器 / 串行 I/O 队列）用它拿明确的失败路径：目录被删后
    /// 返回 `.failure(.directoryUnavailable)`，调用方记一条日志即可，不再有
    /// 只在控制台出现、无人处理的错误文本。
    @discardableResult
    func saveProjectsReportingResult(_ projects: [Project]) -> Result<Void, LocalPersistenceError> {
        let result = LocalJSONFile.save(projects, to: projectsFileURL)
        if case .failure(let error) = result {
            Log.error("保存项目数据失败: \(error.localizedDescription)")
        }
        return result
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

    func loadAutoTaggingEnabled() -> Bool {
        do {
            let data = try Data(contentsOf: autoTaggingFileURL)
            let enabled = try JSONDecoder().decode(Bool.self, from: data)
            print("从文件加载自动标签设置: \(enabled)")
            return enabled
        } catch {
            print("加载自动标签设置失败（默认启用）: \(error)")
            return true
        }
    }

    func saveAutoTaggingEnabled(_ enabled: Bool) {
        do {
            let data = try JSONEncoder().encode(enabled)
            try data.write(to: autoTaggingFileURL)
            print("保存自动标签设置: \(enabled)")
        } catch {
            print("保存自动标签设置失败: \(error)")
        }
    }
}
