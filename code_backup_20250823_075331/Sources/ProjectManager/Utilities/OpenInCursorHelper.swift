import AppKit
import Foundation

/// 提供了与外部应用程序交互的辅助函数
enum AppOpenHelper {
    /// 在Cursor编辑器中打开指定路径的文件或目录
    /// - Parameter path: 要打开的文件或目录路径
    static func openInCursor(path: String) {
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
    
    /// 在Finder中显示指定路径的文件或目录
    /// - Parameter path: 要显示的文件或目录路径
    static func openInFinder(path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
} 