import Foundation
import AppKit

/// 编辑器配置模型
struct EditorConfig: Codable, Identifiable, Equatable, Hashable {
    let id = UUID()
    var name: String
    var bundleId: String?
    var commandPath: String?
    var arguments: [String]
    var isEnabled: Bool
    var displayOrder: Int
    var isDefault: Bool
    
    init(
        name: String,
        bundleId: String? = nil,
        commandPath: String? = nil,
        arguments: [String] = [],
        isEnabled: Bool = true,
        displayOrder: Int = 0,
        isDefault: Bool = false
    ) {
        self.name = name
        self.bundleId = bundleId
        self.commandPath = commandPath
        self.arguments = arguments
        self.isEnabled = isEnabled
        self.displayOrder = displayOrder
        self.isDefault = isDefault
    }
    
    /// 检查编辑器是否可用
    var isAvailable: Bool {
        if let bundleId = bundleId {
            let workspace = NSWorkspace.shared
            if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) {
                return FileManager.default.fileExists(atPath: appURL.path)
            }
        }
        
        if let commandPath = commandPath {
            return FileManager.default.fileExists(atPath: commandPath)
        }
        
        return false
    }
    
    /// 实现Hashable协议
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    /// 预定义的常见编辑器配置
    static let defaultEditors: [EditorConfig] = [
        EditorConfig(
            name: "Cursor",
            bundleId: "com.todesktop.230313mzl4w4u92",
            commandPath: "/usr/local/bin/cursor",
            arguments: [],
            displayOrder: 1,
            isDefault: true
        ),
        EditorConfig(
            name: "Visual Studio Code",
            bundleId: "com.microsoft.VSCode",
            commandPath: "/usr/local/bin/code",
            arguments: [],
            displayOrder: 2
        ),
        EditorConfig(
            name: "Sublime Text",
            bundleId: "com.sublimetext.4",
            commandPath: "/usr/local/bin/subl",
            arguments: [],
            displayOrder: 4
        ),
        EditorConfig(
            name: "Ghostty",
            bundleId: "com.mitchellh.ghostty",
            commandPath: nil,
            arguments: [],
            displayOrder: 7
        )
    ]
}

/// 系统操作类型
enum SystemAction {
    case openInTerminal
    case showInFinder
    case copyPath
    case copyProjectInfo
    case editTags
}