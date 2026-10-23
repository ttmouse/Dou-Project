import Foundation
import AppKit

/// 编辑器管理器 - 负责编辑器配置和操作
class EditorManager: ObservableObject {
    @Published var editors: [EditorConfig] = []
    @Published var systemActions: [SystemAction] = [.openInTerminal, .showInFinder, .copyPath, .copyProjectInfo, .editTags]
    
    private let userDefaultsKey = "EditorConfigurations"
    
    init() {
        loadEditors()
    }
    
    /// 从UserDefaults加载编辑器配置
    private func loadEditors() {
        print("🔄 加载编辑器配置...")
        
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decodedEditors = try? JSONDecoder().decode([EditorConfig].self, from: data) {
            print("📥 从UserDefaults加载了 \(decodedEditors.count) 个编辑器配置")
            editors = decodedEditors.sorted { $0.displayOrder < $1.displayOrder }
            
            // 打印加载的编辑器列表
            for editor in editors {
                print("  - \(editor.name) (启用: \(editor.isEnabled), 顺序: \(editor.displayOrder), command: \(editor.commandPath ?? "nil"), bundle: \(editor.bundleId ?? "nil"))")
            }
            
            // 检查是否需要添加新的默认编辑器或更新现有编辑器
            let existingNames = Set(editors.map { $0.name })
            let defaultNames = Set(EditorConfig.defaultEditors.map { $0.name })
            let missingEditors = EditorConfig.defaultEditors.filter { !existingNames.contains($0.name) }
            
            var needsUpdate = false
            
            // 添加缺失的编辑器
            if !missingEditors.isEmpty {
                print("🆕 发现新的默认编辑器，添加: \(missingEditors.map { $0.name })")
                editors.append(contentsOf: missingEditors)
                needsUpdate = true
            }
            
            // 更新现有编辑器的配置（如果默认配置有更新的字段）
            for defaultEditor in EditorConfig.defaultEditors {
                if let existingIndex = editors.firstIndex(where: { $0.name == defaultEditor.name }) {
                    let existingEditor = editors[existingIndex]
                    
                    // 检查需要更新的字段
                    var shouldUpdate = false
                    
                    // 如果 commandPath 从 nil 变为有值，需要更新
                    if existingEditor.commandPath == nil && defaultEditor.commandPath != nil {
                        shouldUpdate = true
                        print("🔄 更新 \(defaultEditor.name) 的 commandPath: \(defaultEditor.commandPath!)")
                    }
                    
                    // 如果 arguments 有变化，需要更新
                    if existingEditor.arguments != defaultEditor.arguments {
                        shouldUpdate = true
                        print("🔄 更新 \(defaultEditor.name) 的 arguments: \(defaultEditor.arguments)")
                    }
                    
                    // 如果 bundleId 有变化，需要更新
                    if existingEditor.bundleId != defaultEditor.bundleId {
                        shouldUpdate = true
                        print("🔄 更新 \(defaultEditor.name) 的 bundleId: \(defaultEditor.bundleId ?? "nil")")
                    }
                    
                    if shouldUpdate {
                        editors[existingIndex] = EditorConfig(
                            name: defaultEditor.name,
                            bundleId: defaultEditor.bundleId,
                            commandPath: defaultEditor.commandPath,
                            arguments: defaultEditor.arguments,
                            isEnabled: existingEditor.isEnabled, // 保留启用状态
                            displayOrder: existingEditor.displayOrder, // 保留显示顺序
                            isDefault: existingEditor.isDefault // 保留默认状态
                        )
                        needsUpdate = true
                        print("✅ 已更新编辑器配置: \(defaultEditor.name)")
                    }
                }
            }
            
            if needsUpdate {
                editors.sort { $0.displayOrder < $1.displayOrder }
                saveEditors()
            }
            
            // 去除重复编辑器
            removeDuplicateEditors()
        } else {
            // 首次启动，使用默认配置
            print("🆕 首次启动，使用默认编辑器配置")
            editors = EditorConfig.defaultEditors
            print("📝 默认编辑器列表: \(editors.map { $0.name })")
            saveEditors()
        }
        
        print("✅ 编辑器配置加载完成，共 \(editors.count) 个编辑器")
    }
    
    /// 移除重复的编辑器配置
    private func removeDuplicateEditors() {
        let originalCount = editors.count
        var uniqueEditors: [EditorConfig] = []
        var seenNames = Set<String>()
        
        for editor in editors {
            if !seenNames.contains(editor.name) {
                seenNames.insert(editor.name)
                uniqueEditors.append(editor)
            } else {
                print("🗑️ 移除重复编辑器: \(editor.name)")
            }
        }
        
        editors = uniqueEditors.sorted { $0.displayOrder < $1.displayOrder }
        
        if originalCount != editors.count {
            print("🧹 去重完成，从 \(originalCount) 个减少到 \(editors.count) 个编辑器")
            saveEditors()
        }
    }
    
    /// 保存编辑器配置到UserDefaults
    func saveEditors() {
        if let data = try? JSONEncoder().encode(editors) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            print("💾 编辑器配置已保存到UserDefaults")
            
            // 显式触发UI更新通知
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    /// 获取启用的编辑器列表
    var enabledEditors: [EditorConfig] {
        return editors.filter { $0.isEnabled }.sorted { $0.displayOrder < $1.displayOrder }
    }
    
    /// 获取可用的编辑器列表（已安装且启用）
    var availableEditors: [EditorConfig] {
        return enabledEditors.filter { $0.isAvailable }
    }
    
    /// 获取默认编辑器
    var defaultEditor: EditorConfig? {
        return enabledEditors.first { $0.isDefault } ?? enabledEditors.first
    }
    
    /// 在指定编辑器中打开路径
    func openInEditor(_ editor: EditorConfig, path: String) {
        print("🚀 尝试用 \(editor.name) 打开: \(path)")
        print("📍 编辑器配置: Bundle ID=\(editor.bundleId ?? "nil"), Command=\(editor.commandPath ?? "nil")")
        
        var success = false
        
        // 首先尝试 open -a 命令（推荐的macOS方式）
        if let bundleId = editor.bundleId {
            print("🔧 尝试 open -a 命令: \(bundleId)")
            success = openWithOpenCommand(appName: editor.name, path: path)
            if success {
                print("✅ open -a 启动成功")
                return
            }
        }
        
        // 然后尝试命令行工具
        if !success, let commandPath = editor.commandPath, !commandPath.isEmpty {
            print("🔧 尝试命令行: \(commandPath) \(editor.arguments + [path])")
            success = openWithCommand(commandPath: commandPath, arguments: editor.arguments + [path])
            if success {
                print("✅ 命令行启动成功")
                return
            }
        }
        
        // 最后尝试Bundle ID方式
        if !success, let bundleId = editor.bundleId {
            print("🔧 尝试Bundle ID: \(bundleId)")
            success = openWithBundleId(bundleId: bundleId, path: path)
            if success {
                print("✅ Bundle ID启动成功")
                return
            }
        }
        
        if !success {
            print("❌ 打开失败: \(path) in \(editor.name)")
        }
    }
    
    /// 使用 open -a 命令打开应用（macOS推荐方式）
    private func openWithOpenCommand(appName: String, path: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", appName, path]
        
        do {
            try task.run()
            print("✅ open -a 命令执行成功: open -a \"\(appName)\" \"\(path)\"")
            return true
        } catch {
            print("❌ open -a 命令执行失败: \(error)")
            return false
        }
    }
    
    /// 使用命令行工具打开
    private func openWithCommand(commandPath: String, arguments: [String]) -> Bool {
        let task = Process()
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: commandPath) else {
            print("❌ 命令不存在: \(commandPath)")
            return false
        }
        
        task.executableURL = URL(fileURLWithPath: commandPath)
        task.arguments = arguments
        
        // 对于应用包中的可执行文件，需要设置环境
        if commandPath.contains(".app/Contents/MacOS/") {
            task.environment = ProcessInfo.processInfo.environment
        }
        
        do {
            try task.run()
            print("✅ 命令执行成功: \(commandPath) \(arguments)")
            return true
        } catch {
            print("❌ 命令执行失败 \(commandPath): \(error)")
            return false
        }
    }
    
    /// 使用Bundle ID打开应用
    private func openWithBundleId(bundleId: String, path: String) -> Bool {
        let workspace = NSWorkspace.shared
        
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) else {
            print("❌ 找不到应用: \(bundleId)")
            return false
        }
        
        print("📱 找到应用: \(appURL.path)")
        let fileURL = URL(fileURLWithPath: path)
        
        do {
            try workspace.open([fileURL], withApplicationAt: appURL, options: [], configuration: [:])
            print("✅ Bundle ID启动成功: \(bundleId)")
            return true
        } catch {
            print("❌ Bundle ID启动失败 \(bundleId): \(error)")
            return false
        }
    }
    
    /// 执行系统操作
    func performSystemAction(_ action: SystemAction, path: String) {
        switch action {
        case .openInTerminal:
            openInTerminal(path: path)
        case .showInFinder:
            showInFinder(path: path)
        case .copyPath:
            copyToClipboard(path)
        case .copyProjectInfo:
            copyProjectInfo(path: path)
        case .editTags:
            // 这个会在右键菜单中处理
            break
        }
    }
    
    /// 在终端中打开
    private func openInTerminal(path: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(path)'"
        end tell
        """
        
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(nil)
        }
    }
    
    /// 在Finder中显示
    private func showInFinder(path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
    
    /// 复制路径到剪贴板
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
    }
    
    /// 复制项目信息到剪贴板
    private func copyProjectInfo(path: String) {
        let projectName = URL(fileURLWithPath: path).lastPathComponent
        let info = "项目名称: \(projectName)\n路径: \(path)"
        copyToClipboard(info)
    }
    
    /// 添加自定义编辑器
    func addCustomEditor(name: String, bundleId: String?, commandPath: String?, arguments: [String] = []) {
        let maxOrder = editors.map { $0.displayOrder }.max() ?? 0
        let newEditor = EditorConfig(
            name: name,
            bundleId: bundleId,
            commandPath: commandPath,
            arguments: arguments,
            displayOrder: maxOrder + 1
        )
        editors.append(newEditor)
        saveEditors()
    }
    
    /// 更新编辑器配置
    func updateEditor(_ editor: EditorConfig) {
        if let index = editors.firstIndex(where: { $0.id == editor.id }) {
            editors[index] = editor
            print("🔄 更新编辑器配置: \(editor.name)")
            saveEditors()
        }
    }
    
    /// 删除编辑器
    func deleteEditor(_ editor: EditorConfig) {
        editors.removeAll { $0.id == editor.id }
        saveEditors()
    }
    
    /// 移动编辑器顺序
    func moveEditors(from source: IndexSet, to destination: Int) {
        editors.move(fromOffsets: source, toOffset: destination)
        updateDisplayOrder()
        saveEditors()
    }
    
    /// 更新显示顺序
    private func updateDisplayOrder() {
        for (index, editor) in editors.enumerated() {
            editors[index].displayOrder = index
        }
    }
    
    /// 设置默认编辑器
    func setDefaultEditor(_ editor: EditorConfig) {
        for index in editors.indices {
            editors[index].isDefault = (editors[index].id == editor.id)
            if editors[index].id == editor.id {
                editors[index].isEnabled = true
            }
        }
        print("⭐ 设置默认编辑器: \(editor.name)")
        saveEditors()
    }
    
    /// 重置指定编辑器的配置为默认值
    func resetEditorToDefault(_ editorName: String) {
        if let defaultConfig = EditorConfig.defaultEditors.first(where: { $0.name == editorName }) {
            if let index = editors.firstIndex(where: { $0.name == editorName }) {
                editors[index] = EditorConfig(
                    name: defaultConfig.name,
                    bundleId: defaultConfig.bundleId,
                    commandPath: defaultConfig.commandPath,
                    arguments: defaultConfig.arguments,
                    isEnabled: editors[index].isEnabled, // 保留启用状态
                    displayOrder: editors[index].displayOrder, // 保留显示顺序
                    isDefault: editors[index].isDefault // 保留默认状态
                )
                print("🔄 重置编辑器配置: \(editorName)")
                saveEditors()
            }
        }
    }
    
    /// 检测系统中可用的编辑器
    func detectAvailableEditors() {
        for index in editors.indices {
            // 这里可以添加更精确的检测逻辑
            // 目前使用EditorConfig的isAvailable属性
        }
        print("🔍 检测可用编辑器完成")
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}
