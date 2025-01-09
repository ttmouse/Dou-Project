import AppKit
import SwiftUI

class TagSystemSync {
    static func loadSystemTags() -> Set<String> {
        let workspace = NSWorkspace.shared
        return Set(workspace.fileLabels)
    }

    static func syncTagsToSystem(_ tags: Set<String>) {
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
                    print("系统标签同步成功: \(tags)")
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
