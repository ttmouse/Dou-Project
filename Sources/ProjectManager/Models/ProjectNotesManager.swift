import Foundation

/// 项目备注文件管理器
/// 负责在项目目录下读写备注文档
///
/// 设计原则：
/// 1. 备注存储在项目目录下的固定文件名
/// 2. 纯文件读写，无复杂缓存
/// 3. 自动处理文件不存在的情况
/// 4. 支持 Markdown 格式的备注文档
enum ProjectNotesManager {

    /// 备注文件名（固定）
    static let notesFileName = "PROJECT_NOTES.md"

    /// 读取项目备注
    /// - Parameter projectPath: 项目目录路径
    /// - Returns: 备注内容，如果文件不存在或为空则返回 nil
    static func readNotes(from projectPath: String) -> String? {
        let notesPath = notesFilePath(for: projectPath)

        guard FileManager.default.fileExists(atPath: notesPath) else {
            return nil
        }

        do {
            let content = try String(contentsOfFile: notesPath, encoding: .utf8)
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : content
        } catch {
            print("⚠️ 读取项目备注失败: \(projectPath) - \(error)")
            return nil
        }
    }

    /// 写入项目备注
    /// - Parameters:
    ///   - notes: 备注内容，如果为 nil 或空字符串则删除备注文件
    ///   - projectPath: 项目目录路径
    /// - Returns: 操作是否成功
    @discardableResult
    static func writeNotes(_ notes: String?, to projectPath: String) -> Bool {
        let notesPath = notesFilePath(for: projectPath)

        if notes == nil || (notes?.isEmpty ?? true) {
            if FileManager.default.fileExists(atPath: notesPath) {
                do {
                    try FileManager.default.removeItem(atPath: notesPath)
                    return true
                } catch {
                    print("⚠️ 删除项目备注文件失败: \(notesPath) - \(error)")
                    return false
                }
            }
            return true
        }

        do {
            let notesDir = (notesPath as NSString).deletingLastPathComponent
            if !FileManager.default.fileExists(atPath: notesDir) {
                try FileManager.default.createDirectory(
                    atPath: notesDir,
                    withIntermediateDirectories: true
                )
            }

            try notes!.write(
                toFile: notesPath,
                atomically: true,
                encoding: .utf8
            )
            return true
        } catch {
            print("⚠️ 写入项目备注失败: \(projectPath) - \(error)")
            return false
        }
    }

    /// 检查项目是否有备注
    /// - Parameter projectPath: 项目目录路径
    /// - Returns: 是否存在非空备注文件
    static func hasNotes(at projectPath: String) -> Bool {
        guard let notes = readNotes(from: projectPath) else {
            return false
        }
        return !notes.isEmpty
    }

    /// 备注文件的完整路径
    /// - Parameter projectPath: 项目目录路径
    /// - Returns: 备注文件完整路径
    private static func notesFilePath(for projectPath: String) -> String {
        return "\(projectPath)/\(notesFileName)"
    }

    /// 批量读取多个项目的备注
    /// - Parameter projectPaths: 项目路径列表
    /// - Returns: 项目路径到备注内容的映射
    static func readNotesBatch(for projectPaths: [String]) -> [String: String?] {
        var notesMap: [String: String?] = [:]
        for path in projectPaths {
            notesMap[path] = readNotes(from: path)
        }
        return notesMap
    }
}
