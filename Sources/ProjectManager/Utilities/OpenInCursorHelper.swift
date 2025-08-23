import AppKit
import Foundation

/// 提供了与外部应用程序交互的辅助函数
enum AppOpenHelper {
    /// EditorManager单例实例
    static let editorManager = EditorManager()
    
    /// 在默认编辑器中打开指定路径
    /// - Parameter path: 要打开的文件或目录路径
    static func openInDefaultEditor(path: String) {
        if let defaultEditor = editorManager.defaultEditor {
            editorManager.openInEditor(defaultEditor, path: path)
        } else {
            // 回退到系统默认行为
            openInFinder(path: path)
        }
    }
    
    /// 在Cursor编辑器中打开指定路径的文件或目录（保持向后兼容）
    /// - Parameter path: 要打开的文件或目录路径
    static func openInCursor(path: String) {
        let cursorEditor = editorManager.editors.first { $0.name == "Cursor" }
        if let editor = cursorEditor {
            editorManager.openInEditor(editor, path: path)
        } else {
            // 使用旧的硬编码方式作为回退
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/local/bin/cursor")
            task.arguments = [path]

            do {
                try task.run()
            } catch {
                print("Error opening Cursor: \(error)")

                // 如果直接打开失败，尝试使用 open 命令
                let openTask = Process()
                openTask.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                openTask.arguments = ["-a", "Cursor", path]

                do {
                    try openTask.run()
                } catch {
                    print("Error using open command: \(error)")
                }
            }
        }
    }
    
    /// 在指定编辑器中打开
    /// - Parameters:
    ///   - editor: 编辑器配置
    ///   - path: 文件路径
    static func openInEditor(_ editor: EditorConfig, path: String) {
        editorManager.openInEditor(editor, path: path)
    }
    
    /// 执行系统操作
    /// - Parameters:
    ///   - action: 系统操作类型
    ///   - path: 文件路径
    static func performSystemAction(_ action: SystemAction, path: String) {
        editorManager.performSystemAction(action, path: path)
    }
    
    /// 在Finder中显示指定路径的文件或目录
    /// - Parameter path: 要显示的文件或目录路径
    static func openInFinder(path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
} 