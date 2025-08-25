import SwiftUI

struct SidebarView: View {
    @Binding var selectedTags: Set<String>
    @Binding var searchBarRef: SearchBar?
    @EnvironmentObject var tagManager: TagManager
    @Binding var isDraggingDirectory: Bool
    @Binding var isShowingNewTagDialog: Bool
    @Binding var tagToRename: IdentifiableString?
    @Binding var selectedDirectory: String?
    @Binding var heatmapFilteredProjectIds: Set<UUID>
    
    // Linus式：简单的状态管理，不搞复杂的
    @State private var selectedProjects: [ProjectData] = []
    @State private var showProjectPopover = false
    @State private var selectedDateString = ""
    
    // 缓存热力图数据，避免重复计算
    @State private var cachedHeatmapData: [HeatmapLogic.HeatmapData] = []
    @State private var isGeneratingHeatmap = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 添加目录列表
            DirectoryListView(
                tagManager: tagManager,
                selectedDirectory: $selectedDirectory,
                onDirectorySelected: clearSelectedTags // 添加目录选择的回调
            )
            .padding(.bottom, 8)
            
            Divider()
                .background(AppTheme.divider)
                .padding(.bottom, 8)
            
            // Linus式热力图 - 简单直接添加
            heatmapSection
            
            Divider()
                .background(AppTheme.divider)
                .padding(.vertical, 8)
            
            // 标签列表使用剩余空间
            TagListView(
                selectedTags: $selectedTags,
                searchBarRef: $searchBarRef,
                isShowingNewTagDialog: $isShowingNewTagDialog,
                tagToRename: $tagToRename
            )
            .layoutPriority(1) // 给予更高的布局优先级
        }
        .frame(minWidth: AppTheme.sidebarMinWidth, maxWidth: AppTheme.sidebarMaxWidth)
        .background(AppTheme.sidebarBackground)
        .overlay(
            Rectangle()
                .fill(AppTheme.sidebarBorder)
                .frame(width: 1)
                .offset(x: AppTheme.sidebarBorderOffset)
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
        .sheet(isPresented: $showProjectPopover) {
            ProjectListPopover(
                projects: selectedProjects,
                date: selectedDateString,
                isPresented: $showProjectPopover
            )
        }
    }
    
    // MARK: - 热力图部分 (使用标签列表相同的间距)
    private var heatmapSection: some View {
        VStack(spacing: 0) {
            // 热力图筛选状态提示
            if !heatmapFilteredProjectIds.isEmpty {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.checkmark")
                            .foregroundColor(AppTheme.accent)
                            .font(.caption)
                        Text("日期筛选已启用")
                            .font(AppTheme.captionFont)
                            .foregroundColor(AppTheme.accent)
                    }
                    
                    Spacer()
                    
                    Button("清除") {
                        heatmapFilteredProjectIds.removeAll()
                    }
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.accent)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppTheme.tagListHeaderPaddingH)
                .padding(.vertical, 4)
                .background(AppTheme.accent.opacity(0.1))
            }
            
            HeatmapView(
                heatmapData: cachedHeatmapData,
                onDateSelected: { projects in
                    selectedProjects = projects
                    selectedDateString = formatSelectedDate(from: projects)
                    showProjectPopover = true
                },
                onDateFilter: { projects in
                    // 筛选该日期的项目
                    heatmapFilteredProjectIds = Set(projects.map { $0.id })
                    // 清除其他筛选条件
                    selectedTags.removeAll()
                    selectedDirectory = nil
                    // 清除搜索框焦点
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    searchBarRef?.clearFocus()
                }
            )
            .onAppear {
                if cachedHeatmapData.isEmpty && !isGeneratingHeatmap {
                    generateHeatmapDataAsync()
                }
            }
        }
    }
    
    // MARK: - 热力图数据生成 - 异步版本，避免UI阻塞
    private func generateHeatmapDataAsync() {
        isGeneratingHeatmap = true
        
        Task {
            // 在后台线程生成数据
            let projectDataArray = await MainActor.run {
                tagManager.projects.values.map { project in
                    ProjectData(
                        id: project.id,
                        name: project.name,
                        path: project.path,
                        lastModified: project.lastModified,
                        tags: project.tags,
                        gitInfo: project.gitInfo.map { gitInfo in
                            ProjectData.GitInfoData(
                                commitCount: gitInfo.commitCount,
                                lastCommitDate: gitInfo.lastCommitDate
                            )
                        },
                        fileSystemInfo: ProjectData.FileSystemInfoData(
                            modificationDate: project.fileSystemInfo.modificationDate,
                            size: project.fileSystemInfo.size,
                            checksum: project.fileSystemInfo.checksum,
                            lastCheckTime: project.fileSystemInfo.lastCheckTime
                        )
                    )
                }
            }
            
            // 后台生成热力图数据（Git查询）
            let heatmapData = HeatmapLogic.generateHeatmapData(from: Array(projectDataArray), days: 90)
            
            // 回到主线程更新UI
            await MainActor.run {
                cachedHeatmapData = heatmapData
                isGeneratingHeatmap = false
            }
        }
    }
    
    // MARK: - 日期格式化
    private func formatSelectedDate(from projects: [ProjectData]) -> String {
        // 简单实现：使用第一个项目的Git信息来推断日期
        if let firstProject = projects.first,
           let lastCommitDate = firstProject.gitInfo?.lastCommitDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "M月d日"
            return formatter.string(from: lastCommitDate)
        }
        return "选中的日期"
    }
    
    // 清除选中的标签
    private func clearSelectedTags() {
        selectedTags.removeAll()
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
            } label: {
                Label("添加目录...", systemImage: "folder.badge.plus")
            }
            
            Divider()
            
            // === 管理区块 ===
            Menu {
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
        .menuStyle(.automatic)
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
            tagToRename: .constant(nil),
            selectedDirectory: .constant(nil),
            heatmapFilteredProjectIds: .constant([])
        )
        .environmentObject({
            let container = TagManager()
            return TagManager()
        }())
    }
}
#endif 