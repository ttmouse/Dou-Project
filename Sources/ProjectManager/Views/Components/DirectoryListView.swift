import SwiftUI

struct DirectoryListView: View {
    @ObservedObject var tagManager: TagManager
    @Binding var selectedDirectory: String?
    var onDirectorySelected: (() -> Void)? = nil // 添加目录选择的回调
    
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
                            panel.message = "请选择要添加的项目文件夹"
                            panel.level = .modalPanel

                            if panel.runModal() == .OK {
                                for url in panel.urls {
                                    DispatchQueue.main.async {
                                        let project = Project(
                                            name: url.lastPathComponent,
                                            path: url.path,
                                            lastModified: Date()
                                        )
                                        tagManager.registerProject(project)
                                    }
                                }
                            }
                        }
                    }) {
                        Label("直接添加为项目", systemImage: "plus.rectangle.on.folder")
                    }
                    
                    Button(action: {
                        DispatchQueue.main.async {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.canCreateDirectories = false
                            panel.prompt = "选择"
                            panel.message = "请选择要扫描的文件夹"
                            panel.level = .modalPanel

                            if panel.runModal() == .OK, let url = panel.url {
                                // 仅扫描选定目录的直接子目录
                                do {
                                    let fileManager = FileManager.default
                                    let contents = try fileManager.contentsOfDirectory(
                                        at: url,
                                        includingPropertiesForKeys: [.isDirectoryKey],
                                        options: [.skipsHiddenFiles]
                                    )
                                    
                                    // 过滤出目录
                                    let directories = contents.filter { 
                                        (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                                    }
                                    
                                    // 将每个子目录添加为项目
                                    for dirURL in directories {
                                        let modDate = (try? dirURL.resourceValues(
                                            forKeys: [.contentModificationDateKey]
                                        ).contentModificationDate) ?? Date()
                                        
                                        let project = Project(
                                            name: dirURL.lastPathComponent,
                                            path: dirURL.path,
                                            lastModified: modDate
                                        )
                                        tagManager.registerProject(project)
                                    }
                                    
                                    // 显示确认对话框
                                    DispatchQueue.main.async {
                                        let alert = NSAlert()
                                        alert.messageText = "导入完成"
                                        alert.informativeText = "已添加 \(directories.count) 个子目录作为项目"
                                        alert.alertStyle = .informational
                                        alert.addButton(withTitle: "确定")
                                        alert.runModal()
                                    }
                                } catch {
                                    // 显示错误对话框
                                    let alert = NSAlert()
                                    alert.messageText = "扫描错误"
                                    alert.informativeText = "扫描目录失败: \(error.localizedDescription)"
                                    alert.alertStyle = .warning
                                    alert.addButton(withTitle: "确定")
                                    alert.runModal()
                                }
                            }
                        }
                    }) {
                        Label("扫描子目录并添加", systemImage: "folder.badge.gearshape")
                    }
                    
                    Divider()
                    
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
                        Button(
                            role: .destructive,
                            action: {
                                tagManager.removeWatchedDirectory(path)
                            }
                        ) {
                            Label("移除目录", systemImage: "trash")
                        }

                        Button(action: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                        }) {
                            Label("在访达中显示", systemImage: "folder")
                        }
                    }
                }
            }
            .padding(.vertical, AppTheme.tagListContentPaddingV)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 目录行视图
struct DirectoryRow: View {
    let name: String
    let path: String?
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
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
                    .fill(isSelected ? AppTheme.sidebarSelectedBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
struct DirectoryListView_Previews: PreviewProvider {
    static var previews: some View {
        DirectoryListView(
            tagManager: TagManager(),
            selectedDirectory: .constant(nil)
        )
        .frame(width: 250)
        .background(AppTheme.sidebarBackground)
    }
}
#endif 