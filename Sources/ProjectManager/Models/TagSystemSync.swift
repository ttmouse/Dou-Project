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
/// - `loadSystemTags()`: 从系统加载所有标签
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

    static func loadSystemTags() -> Set<String> {
        let workspace = NSWorkspace.shared
        return Set(workspace.fileLabels)
    }

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

        // 创建临时文件
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_tag")
        try? "".write(to: tempURL, atomically: true, encoding: .utf8)

        // 创建 plist 文件
        let plistURL = tempURL.deletingPathExtension().appendingPathExtension("plist")
        let binaryPlistURL = plistURL.deletingPathExtension().appendingPathExtension("binary.plist")

        // 生成包含所有标签的 plist
        let tagsArray = tags.map { "\($0)\n6" }.joined(separator: "</string>\n<string>")
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <array>
                <string>\(tagsArray)</string>
            </array>
            </plist>
            """

        try? plist.write(to: plistURL, atomically: true, encoding: .utf8)

        do {
            // 转换为二进制 plist
            let plutilProcess = Process()
            plutilProcess.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
            plutilProcess.arguments = [
                "-convert", "binary1", "-o", binaryPlistURL.path, plistURL.path,
            ]
            try plutilProcess.run()
            plutilProcess.waitUntilExit()

            if plutilProcess.terminationStatus == 0 {
                // 设置系统标签
                let xattrProcess = Process()
                xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xattrProcess.arguments = [
                    "-wx", "com.apple.metadata:_kMDItemUserTags", "@\(binaryPlistURL.path)",
                    tempURL.path,
                ]
                try xattrProcess.run()
                xattrProcess.waitUntilExit()

                if xattrProcess.terminationStatus == 0 {
                    print("系统标签保存成功: \(tags)")
                    lastSyncTags = tags
                    lastSyncTime = Date()
                }
            }
        } catch {
            print("同步系统标签失败: \(error)")
        }

        // 清理临时文件
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: plistURL)
        try? FileManager.default.removeItem(at: binaryPlistURL)
    }
}
