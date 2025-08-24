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
    
    @State private var showingDataImportView = false
    @State private var isProcessingTagSync = false
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
                        batchSyncTagsFromDirectory()
                    }) {
                        if isProcessingTagSync {
                            Label("同步中...", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("从系统同步标签", systemImage: "tag.circle")
                        }
                    }
                    .disabled(isProcessingTagSync)
                    
                    Button(action: {
                        showingDataImportView = true
                    }) {
                        Label("导入项目数据", systemImage: "square.and.arrow.down")
                    }
                    
                    Button(action: {
                        tagManager.clearCacheAndReloadProjects()
                    }) {
                        Label("刷新项目", systemImage: "arrow.triangle.2.circlepath")
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
        .sheet(isPresented: $showingDataImportView) {
            DataImportView()
                .environmentObject(tagManager)
        }
        .sheet(item: $createProjectPath) { pathItem in
            CreateProjectView(
                parentDirectory: pathItem.path,
                tagManager: tagManager
            )
        }
    }
    
    // MARK: - 批量同步标签功能
    
    /// 批量同步系统标签到应用数据库
    private func batchSyncTagsFromDirectory() {
        guard !isProcessingTagSync else { return }
        
        // 直接对所有已知项目进行标签同步
        self.performTagSyncForAllProjects()
    }
    
    /// 对所有已知项目执行标签同步
    private func performTagSyncForAllProjects() {
        isProcessingTagSync = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var syncedProjects = 0
            var syncedTags = Set<String>()
            let allProjects = Array(self.tagManager.projects.values)
            
            for project in allProjects {
                // 从系统加载此项目目录的标签
                let systemTags = TagSystemSync.loadTagsFromFile(at: project.path)
                
                if !systemTags.isEmpty {
                    DispatchQueue.main.async {
                        // 为项目添加从系统同步的标签
                        for tag in systemTags {
                            self.tagManager.addTagToProject(projectId: project.id, tag: tag)
                        }
                        syncedTags.formUnion(systemTags)
                        syncedProjects += 1
                        
                        print("从系统同步标签到项目 '\(project.name)': \(systemTags)")
                    }
                }
            }
            
            // 同步完成，显示结果
            DispatchQueue.main.async {
                self.isProcessingTagSync = false
                self.showSyncCompletionAlert(projectsCount: syncedProjects, tagsCount: syncedTags.count)
            }
        }
    }
    
    /// 显示同步完成提示
    private func showSyncCompletionAlert(projectsCount: Int, tagsCount: Int) {
        let alert = NSAlert()
        alert.messageText = "标签同步完成"
        alert.informativeText = "已同步 \(projectsCount) 个项目的标签，共发现 \(tagsCount) 个不同标签"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    /// 显示同步错误提示
    private func showSyncErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "标签同步失败"
        alert.informativeText = "同步过程中发生错误: \(error.localizedDescription)"
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