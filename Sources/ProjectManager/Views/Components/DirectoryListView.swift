import SwiftUI

// MARK: - 辅助数据类型
struct CreateProjectPath: Identifiable {
    let id = UUID()
    let path: String
}

struct DirectoryListView: View {
    @ObservedObject var tagManager: TagManager
    @Binding var selectedDirectory: String?
    var onDirectorySelected: (() -> Void)? = nil // 添加目录选择的回调
    
    @State private var createProjectPath: CreateProjectPath?
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.tagListSpacing) {
            // 标题栏
            HStack {
                Text("目录")
                    .font(.headline)
                    .foregroundColor(AppTheme.sidebarTitle)
                
                Spacer()
                
                // 添加目录管理菜单
                Menu {
                    Button(action: {
                        DispatchQueue.main.async {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.canCreateDirectories = true
                            panel.prompt = "选择"
                            panel.message = "请选择要添加的工作目录（会自动扫描项目）"
                            panel.level = .modalPanel

                            panel.begin { response in
                                if response == .OK, let url = panel.url {
                                    DispatchQueue.main.async {
                                        tagManager.addWatchedDirectory(url.path)
                                    }
                                }
                            }
                        }
                    }) {
                        Label("添加工作目录", systemImage: "folder.badge.plus")
                    }
                    
                    Button(action: {
                        DispatchQueue.main.async {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = true
                            panel.canCreateDirectories = false
                            panel.prompt = "选择"
                            panel.message = "请选择要添加的项目文件夹（支持多选，批量添加）"
                            panel.level = .modalPanel

                            if panel.runModal() == .OK {
                                var projects: [Project] = []
                                for url in panel.urls {
                                    let project = Project(
                                        name: url.lastPathComponent,
                                        path: url.path,
                                        lastModified: Date()
                                    )
                                    projects.append(project)
                                }
                                
                                // 批量注册项目
                                DispatchQueue.main.async {
                                    tagManager.projectOperations.registerProjects(projects)
                                    
                                    // 显示确认对话框
                                    let alert = NSAlert()
                                    alert.messageText = "导入完成"
                                    alert.informativeText = "已添加 \(projects.count) 个项目"
                                    alert.alertStyle = .informational
                                    alert.addButton(withTitle: "确定")
                                    alert.runModal()
                                }
                            }
                        }
                    }) {
                        Label("直接添加为项目", systemImage: "plus.rectangle.on.folder")
                    }
                    
                    Divider()
                    
                    
                    Button(action: {
                        backupTagsToDesktop()
                    }) {
                        Label("备份标签数据", systemImage: "doc.badge.plus")
                    }
                    
                    Button(action: {
                        backupTagsToCustomLocation()
                    }) {
                        Label("备份到指定位置", systemImage: "folder.badge.plus")
                    }
                    
                    Button(action: {
                        importTagsFromBackup()
                    }) {
                        Label("从备份导入标签", systemImage: "square.and.arrow.down.on.square")
                    }
                    
                    Divider()
                    
                    Button(action: {
                        tagManager.refreshProjects()  // 使用新的智能刷新
                    }) {
                        Label("智能刷新", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    Button(action: {
                        tagManager.clearCacheAndReloadProjects()  // 保留传统全量刷新作为备用
                    }) {
                        Label("完全重新加载", systemImage: "arrow.counterclockwise")
                            .foregroundColor(.orange)
                    }
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .foregroundColor(AppTheme.sidebarSecondaryText)
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24, height: 24)
            }
            .padding(.horizontal, AppTheme.tagListHeaderPaddingH)
            .padding(.vertical, AppTheme.tagListHeaderPaddingV)
            
            // 目录列表
            VStack(alignment: .leading, spacing: AppTheme.tagRowSpacing) {
                // 全部目录选项
                DirectoryRow(
                    name: "全部",
                    path: nil,
                    count: tagManager.projects.count,
                    isSelected: selectedDirectory == nil,
                    action: { 
                        selectedDirectory = nil
                        onDirectorySelected?() // 调用回调
                    }
                )
                
                // 监视的目录列表
                ForEach(Array(tagManager.watchedDirectories), id: \.self) { path in
                    DirectoryRow(
                        name: (path as NSString).lastPathComponent,
                        path: path,
                        count: tagManager.projects.values.filter { $0.path.hasPrefix(path) }.count,
                        isSelected: selectedDirectory == path,
                        action: { 
                            selectedDirectory = path
                            onDirectorySelected?() // 调用回调
                        }
                    )
                    .contextMenu {
                        Button(action: {
                            // 确保在主线程上执行状态更新
                            DispatchQueue.main.async {
                                createProjectPath = CreateProjectPath(path: path)
                            }
                        }) {
                            Label("创建新项目", systemImage: "folder.badge.plus")
                        }
                        
                        Divider()
                        
                        Button(action: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                        }) {
                            Label("在访达中显示", systemImage: "folder")
                        }
                        
                        Button(
                            role: .destructive,
                            action: {
                                tagManager.removeWatchedDirectory(path)
                            }
                        ) {
                            Label("移除目录", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.vertical, AppTheme.tagListContentPaddingV)
        }
        .frame(maxWidth: .infinity)
        .sheet(item: $createProjectPath) { pathItem in
            CreateProjectView(
                parentDirectory: pathItem.path,
                tagManager: tagManager
            )
        }
    }
    
    // MARK: - 标签数据备份功能
    
    /// 备份标签数据到桌面
    private func backupTagsToDesktop() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let backupURL = self.tagManager.quickBackupTagsToDesktop() {
                DispatchQueue.main.async {
                    self.showBackupSuccessAlert(at: backupURL.path)
                }
            } else {
                DispatchQueue.main.async {
                    self.showBackupErrorAlert(message: "备份失败，请检查桌面写入权限")
                }
            }
        }
    }
    
    /// 备份标签数据到自定义位置
    private func backupTagsToCustomLocation() {
        DispatchQueue.main.async {
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.allowedContentTypes = [.json]
            
            // 生成默认文件名
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            savePanel.nameFieldStringValue = "ProjectManager_TagsBackup_\(timestamp).json"
            
            savePanel.title = "保存标签备份文件"
            savePanel.message = "选择备份文件的保存位置"
            savePanel.level = .modalPanel
            
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try self.tagManager.backupTagsToFile(at: url)
                            DispatchQueue.main.async {
                                self.showBackupSuccessAlert(at: url.path)
                            }
                        } catch {
                            DispatchQueue.main.async {
                                self.showBackupErrorAlert(message: "备份失败: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// 显示备份成功提示
    private func showBackupSuccessAlert(at path: String) {
        let alert = NSAlert()
        alert.messageText = "标签数据备份成功"
        alert.informativeText = "备份文件已保存到：\n\(path)\n\n同时生成了人类可读的报告文件。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "在访达中显示")
        alert.addButton(withTitle: "确定")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        }
    }
    
    /// 显示备份错误提示
    private func showBackupErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "标签数据备份失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    // MARK: - 标签数据导入功能
    
    /// 从备份导入标签数据
    private func importTagsFromBackup() {
        DispatchQueue.main.async {
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.canChooseDirectories = false
            openPanel.allowsMultipleSelection = false
            openPanel.allowedContentTypes = [.json]
            openPanel.title = "选择标签备份文件"
            openPanel.message = "选择要导入的标签备份文件"
            openPanel.level = .modalPanel
            
            openPanel.begin { response in
                if response == .OK, let url = openPanel.url {
                    // 显示导入策略选择对话框
                    self.showImportStrategyDialog(for: url)
                }
            }
        }
    }
    
    /// 显示导入策略选择对话框
    private func showImportStrategyDialog(for url: URL) {
        let alert = NSAlert()
        alert.messageText = "选择导入策略"
        alert.informativeText = """
        选择如何处理与现有标签的冲突：
        
        • 合并：添加新标签，保留现有标签
        • 替换：完全替换所有标签数据
        • 仅添加：只导入新标签，不修改现有内容
        """
        alert.alertStyle = .informational
        
        alert.addButton(withTitle: "合并")
        alert.addButton(withTitle: "替换")
        alert.addButton(withTitle: "仅添加")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        
        let strategy: TagDataBackup.ImportStrategy
        switch response {
        case .alertFirstButtonReturn:
            strategy = .merge
        case .alertSecondButtonReturn:
            strategy = .replace
        case .alertThirdButtonReturn:
            strategy = .addOnly
        default:
            return // 用户取消
        }
        
        // 执行导入
        performImport(from: url, strategy: strategy)
    }
    
    /// 执行导入操作
    private func performImport(from url: URL, strategy: TagDataBackup.ImportStrategy) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try self.tagManager.importTagsFromBackup(at: url, strategy: strategy)
                
                DispatchQueue.main.async {
                    self.showImportSuccessAlert(result: result)
                }
            } catch {
                DispatchQueue.main.async {
                    self.showImportErrorAlert(error: error)
                }
            }
        }
    }
    
    /// 显示导入成功提示
    private func showImportSuccessAlert(result: TagDataBackup.ImportResult) {
        let alert = NSAlert()
        alert.messageText = "标签数据导入成功"
        alert.informativeText = result.summary
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    /// 显示导入错误提示
    private func showImportErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "标签数据导入失败"
        alert.informativeText = "导入过程中发生错误：\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}

// MARK: - 目录行视图
struct DirectoryRow: View {
    let name: String
    let path: String?
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(isSelected ? AppTheme.accent : AppTheme.folderIcon)
                    .font(.system(size: 14))
                
                Text(name)
                    .font(AppTheme.sidebarTagFont)
                    .foregroundColor(isSelected ? AppTheme.text : AppTheme.sidebarTitle)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(isSelected ? AppTheme.text : AppTheme.sidebarSecondaryText)
                    .padding(.horizontal, AppTheme.tagCountPaddingH)
                    .padding(.vertical, AppTheme.tagCountPaddingV)
                    .background(
                        isSelected
                            ? AppTheme.accent.opacity(0.2)
                            : AppTheme.sidebarDirectoryBackground
                    )
                    .cornerRadius(AppTheme.tagCountCornerRadius)
            }
            .contentShape(Rectangle()) // 使整个区域可点击
            .padding(.horizontal, AppTheme.tagRowPaddingH)
            .padding(.vertical, AppTheme.tagRowPaddingV)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.tagRowCornerRadius)
                    .fill(
                        isSelected ? AppTheme.sidebarSelectedBackground : 
                        (isHovered ? AppTheme.sidebarHoverBackground : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
}

#if DEBUG
struct DirectoryListView_Previews: PreviewProvider {
    static var previews: some View {
        DirectoryListView(
            tagManager: {
                let container = TagManager()
                return TagManager()
            }(),
            selectedDirectory: .constant(nil)
        )
        .frame(width: 250)
        .background(AppTheme.sidebarBackground)
    }
}
#endif 