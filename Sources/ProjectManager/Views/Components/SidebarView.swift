import SwiftUI

struct SidebarView: View {
    @Binding var selectedTags: Set<String>
    @Binding var searchBarRef: SearchBar?
    @EnvironmentObject var tagManager: TagManager
    @Binding var isDraggingDirectory: Bool
    @Binding var isShowingNewTagDialog: Bool
    @Binding var tagToRename: IdentifiableString?
    
    var body: some View {
        VStack(spacing: 0) {
            DirectoryManageButton(
                tagManager: tagManager, 
                isDraggingDirectory: $isDraggingDirectory
            )
            
            TagListView(
                selectedTags: $selectedTags,
                searchBarRef: $searchBarRef,
                isShowingNewTagDialog: $isShowingNewTagDialog,
                tagToRename: $tagToRename
            )
        }
        .frame(minWidth: 200, maxWidth: 300)
        .background(AppTheme.sidebarBackground)
        .overlay(
            Rectangle()
                .fill(AppTheme.sidebarBorder)
                .frame(width: 1)
                .offset(x: 299)
        )
        .sheet(isPresented: $isShowingNewTagDialog) {
            TagEditDialog(
                title: "新建标签",
                originalName: "",
                isPresented: $isShowingNewTagDialog,
                tagManager: tagManager
            ) { newName, color in
                tagManager.addTag(newName, color: color)
                isShowingNewTagDialog = false
            }
        }
    }
}

// MARK: - 目录管理按钮
struct DirectoryManageButton: View {
    @ObservedObject var tagManager: TagManager
    @Binding var isDraggingDirectory: Bool
    
    var body: some View {
        Menu {
            // 监视目录列表
            ForEach(Array(tagManager.watchedDirectories), id: \.self) { path in
                Menu {
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
                } label: {
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if !tagManager.watchedDirectories.isEmpty {
                Divider()
            }
            
            // === 添加目录区块 ===
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
                    Label("添加工作目录（扫描项目）", systemImage: "folder.badge.plus")
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
            } label: {
                Label("添加目录...", systemImage: "folder.badge.plus")
            }
            
            Divider()
            
            // === 管理区块 ===
            Menu {
                Button(action: {
                    tagManager.clearCacheAndReloadProjects()
                }) {
                    Label("刷新项目", systemImage: "arrow.triangle.2.circlepath")
                }
            } label: {
                Label("刷新与重载", systemImage: "arrow.clockwise")
            }
            
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(AppTheme.sidebarSecondaryText)
                Text("管理目录")
                    .foregroundColor(AppTheme.sidebarTitle)

                Spacer()

                Text("\(tagManager.watchedDirectories.count)")
                    .font(.caption)
                    .foregroundColor(AppTheme.sidebarSecondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.sidebarDirectoryBackground)
                    .cornerRadius(4)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(AppTheme.sidebarDirectoryBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(AppTheme.sidebarDirectoryBorder, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    style: StrokeStyle(lineWidth: 2, dash: [4])
                )
                .foregroundColor(AppTheme.accent.opacity(0.5))
                .padding(4)
                .opacity(isDraggingDirectory ? 1 : 0)
        )
        .onDrop(of: ["public.file-url"], isTargeted: $isDraggingDirectory) { providers in
            guard let provider = providers.first else { return false }

            _ = provider.loadObject(ofClass: NSURL.self) { (url, error) in
                if let fileURL = url as? URL {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(
                        atPath: fileURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
                    {
                        DispatchQueue.main.async {
                            tagManager.addWatchedDirectory(fileURL.path)
                        }
                    }
                }
            }
            return true
        }
    }
}

// MARK: - 标签列表视图
struct TagListView: View {
    @Binding var selectedTags: Set<String>
    @Binding var searchBarRef: SearchBar?
    @Binding var isShowingNewTagDialog: Bool
    @Binding var tagToRename: IdentifiableString?
    @EnvironmentObject var tagManager: TagManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.tagListSpacing) {
            tagListHeader
            tagListContent
        }
        .frame(maxWidth: .infinity)
    }
    
    private var tagListHeader: some View {
        HStack {
            Text("标签")
                .font(.headline)
                .foregroundColor(AppTheme.sidebarTitle)

            Spacer()

            // 添加新建标签按钮
            Button(action: {
                isShowingNewTagDialog = true
            }) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .help("新建标签")

            clearButton
        }
        .padding(.horizontal, AppTheme.tagListHeaderPaddingH)
        .padding(.vertical, AppTheme.tagListHeaderPaddingV)
    }
    
    private var tagListContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppTheme.tagRowSpacing) {
                // 添加"全部"特殊标签
                TagRow(
                    tag: "全部",
                    isSelected: selectedTags.isEmpty,
                    count: tagManager.projects.count,
                    action: { 
                        // 移除任何现有焦点
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        // 清除搜索框焦点
                        searchBarRef?.clearFocus()
                        selectedTags.removeAll() 
                    },
                    onDrop: nil,
                    onRename: nil,
                    tagManager: tagManager
                )

                // 添加"没有标签"分类
                TagRow(
                    tag: "没有标签",
                    isSelected: selectedTags.contains("没有标签"),
                    count: tagManager.projects.values.filter { $0.tags.isEmpty }.count,
                    action: { 
                        // 移除任何现有焦点
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        // 清除搜索框焦点
                        searchBarRef?.clearFocus()
                        selectedTags = ["没有标签"] 
                    },
                    onDrop: nil,
                    onRename: nil,
                    tagManager: tagManager
                )

                ForEach(
                    Array(tagManager.allTags).sorted { tag1, tag2 in
                        let count1 = tagManager.getUsageCount(for: tag1)
                        let count2 = tagManager.getUsageCount(for: tag2)
                        return count1 > count2
                    }, id: \.self
                ) { tag in
                    TagRow(
                        tag: tag,
                        isSelected: selectedTags.contains(tag),
                        count: tagManager.getUsageCount(for: tag),
                        action: { handleTagSelection(tag) },
                        onDrop: { _ in handleDrop(tag: tag) },
                        onRename: {
                            tagToRename = IdentifiableString(tag)
                        },
                        tagManager: tagManager
                    )
                }
            }
            .padding(.vertical, AppTheme.tagListContentPaddingV)
        }
    }
    
    private var clearButton: some View {
        Button(action: { selectedTags.removeAll() }) {
            Text("清除")
                .font(.subheadline)
                .foregroundColor(
                    selectedTags.isEmpty ? AppTheme.sidebarSecondaryText : AppTheme.accent)
        }
        .buttonStyle(.plain)
        .opacity(selectedTags.isEmpty ? 0.5 : 1)
    }
    
    private func handleTagSelection(_ tag: String) {
        // 移除任何现有焦点
        NSApp.keyWindow?.makeFirstResponder(nil)
        // 清除搜索框焦点
        searchBarRef?.clearFocus()
        
        // 选择点击的标签
        selectedTags = [tag]  // 直接选择点击的标签
    }
    
    private func handleDrop(tag: String) -> Bool {
        // 获取拖拽的项目 ID
        let draggedProjects = NSPasteboard.general.readObjects(forClasses: [NSString.self], options: nil)
        let projectIds = draggedProjects?.compactMap { str -> UUID? in
            guard let idString = str as? String else { return nil }
            return UUID(uuidString: idString)
        } ?? []
        
        if !projectIds.isEmpty {
            // 使用批量添加方法
            for projectId in projectIds {
                tagManager.addTagToProject(projectId: projectId, tag: tag)
            }
            // 清除选中状态
            selectedTags.removeAll()
            return true
        }
        return false
    }
}

// MARK: - 辅助类型
struct IdentifiableString: Identifiable {
    let id: String
    let value: String

    init(_ string: String) {
        self.id = string
        self.value = string
    }
}

#if DEBUG
struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        SidebarView(
            selectedTags: .constant([]),
            searchBarRef: .constant(nil),
            isDraggingDirectory: .constant(false),
            isShowingNewTagDialog: .constant(false),
            tagToRename: .constant(nil)
        )
        .environmentObject(TagManager())
    }
}
#endif 