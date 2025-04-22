import SwiftUI
import UniformTypeIdentifiers

struct ProjectListView: View {
    @State private var searchText = ""
    @State private var selectedTags: Set<String> = []
    @State private var isShowingDirectoryPicker = false
    @State private var watchedDirectory: String =
        UserDefaults.standard.string(forKey: "WatchedDirectory")
        ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
        ?? NSHomeDirectory() + "/Desktop"
    @State private var selectedProjects: Set<UUID> = []  // 选中的项目
    @State private var isShowingNewTagDialog = false
    @State private var tagToRename: IdentifiableString? = nil
    @State private var isDraggingDirectory = false  // 添加拖放状态
    
    // 添加对SearchBar的引用
    @State private var searchBarRef: SearchBar? = nil

    // 排序方式
    enum SortOption {
        case timeAsc  // 时间升序
        case timeDesc  // 时间降序
        case commitCount  // 提交次数
    }
    @State private var sortOption: SortOption = .timeDesc

    @EnvironmentObject var tagManager: TagManager

    // 分步过滤
    private var filteredProjects: [Project] {
        // 1. 获取所有项目
        let allProjects = Array(tagManager.projects.values)

        // 2. 搜索过滤
        let searchFiltered =
            searchText.isEmpty
            ? allProjects
            : allProjects.filter { project in
                // 项目名称匹配
                if project.name.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                // 路径匹配
                if project.path.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                // 标签匹配
                if project.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
                {
                    return true
                }
                return false
            }

        // 3. 标签过滤
        let tagFiltered =
            selectedTags.isEmpty
            ? searchFiltered
            : searchFiltered.filter { project in
                if selectedTags.contains("没有标签") {
                    return project.tags.isEmpty
                }
                return !selectedTags.isDisjoint(with: project.tags)
            }

        // 4. 排序
        return tagFiltered.sorted { lhs, rhs in
            switch sortOption {
            case .timeAsc:
                return lhs.lastModified < rhs.lastModified
            case .timeDesc:
                return lhs.lastModified > rhs.lastModified
            case .commitCount:
                let count1 = lhs.gitInfo?.commitCount ?? 0
                let count2 = rhs.gitInfo?.commitCount ?? 0
                return count1 > count2  // 按提交次数降序排序
            }
        }
    }

    private func handleTagSelection(_ tag: String) {
        // 移除任何现有焦点
        NSApp.keyWindow?.makeFirstResponder(nil)
        // 清除搜索框焦点
        searchBarRef?.clearFocus()
        
        // 选择点击的标签
        selectedTags = [tag]  // 直接选择点击的标签
    }

    // 处理项目选中
    private func handleProjectSelection(_ project: Project, isShiftPressed: Bool) {
        // 移除任何现有焦点
        NSApp.keyWindow?.makeFirstResponder(nil)
        // 清除搜索框焦点
        searchBarRef?.clearFocus()
        
        if isShiftPressed {
            // Shift 键按下时，切换选中状态
            if selectedProjects.contains(project.id) {
                selectedProjects.remove(project.id)
            } else {
                selectedProjects.insert(project.id)
            }
        } else {
            // Shift 键未按下时，单选
            selectedProjects = [project.id]
        }
    }

    // 处理拖拽完成
    private func handleDrop(tag: String) {
        // 使用批量添加方法
        tagManager.addTagToProjects(projectIds: selectedProjects, tag: tag)
        // 清除选中状态
        selectedProjects.removeAll()
    }

    private var searchAndSortBar: some View {
        HStack(spacing: 8) {
            SearchBar(text: $searchText)
                .modifier(ViewReferenceSetter(reference: $searchBarRef))

            // 时间排序按钮
            Button(action: {
                switch sortOption {
                case .timeDesc: sortOption = .timeAsc
                case .timeAsc: sortOption = .timeDesc
                case .commitCount: sortOption = .timeDesc
                }
            }) {
                Image(systemName: sortOption == .timeAsc ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundColor(sortOption == .commitCount ? AppTheme.titleBarIcon : AppTheme.accent)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .help(sortOption == .timeAsc ? "最早的在前" : "最新的在前")

            // 提交次数排序按钮
            Button(action: {
                sortOption = .commitCount
            }) {
                Image(systemName: "number.circle.fill")
                    .foregroundColor(sortOption == .commitCount ? AppTheme.accent : AppTheme.titleBarIcon)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .help("按提交次数排序")
        }
        .padding(AppTheme.searchBarAreaPadding)
        .frame(height: AppTheme.searchBarAreaHeight)
        .background(AppTheme.searchBarAreaBackground)
        .overlay(
            Rectangle()
                .fill(AppTheme.searchBarAreaBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // 添加清除按钮的视图计算属性
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

    // 目录管理按钮视图
    private var directoryManageButton: some View {
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

    // 标签列表头部视图
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
            .sheet(isPresented: $isShowingNewTagDialog) {
                TagEditDialog(
                    title: "新建标签",
                    isPresented: $isShowingNewTagDialog,
                    tagManager: tagManager
                ) { name, color in
                    tagManager.addTag(name, color: color)
                }
            }

            clearButton
        }
        .padding(.horizontal, AppTheme.tagListHeaderPaddingH)
        .padding(.vertical, AppTheme.tagListHeaderPaddingV)
    }

    // 标签列表内容视图
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

    // 为 String 添加 Identifiable 扩展
    private struct IdentifiableString: Identifiable {
        let id: String
        let value: String

        init(_ string: String) {
            self.id = string
            self.value = string
        }
    }

    // 侧边栏视图
    private var sidebarView: some View {
        VStack(spacing: 0) {
            directoryManageButton

            // 标签列表
            VStack(alignment: .leading, spacing: AppTheme.tagListSpacing) {
                tagListHeader
                tagListContent
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 200, maxWidth: 300)
        .background(AppTheme.sidebarBackground)
        .overlay(
            Rectangle()
                .fill(AppTheme.sidebarBorder)
                .frame(width: 1)
                .offset(x: 299)
        )
    }

    // 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            Text("没有匹配的项目")
                .font(.headline)

            Text("尝试修改搜索条件或清除标签筛选")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 项目网格视图
    private var projectGridView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: AppTheme.cardMinWidth,
                            maximum: AppTheme.cardMaxWidth
                        ),
                        spacing: AppTheme.cardGridSpacingH
                    )
                ],
                spacing: AppTheme.cardGridSpacingV
            ) {
                ForEach(filteredProjects) { project in
                    ProjectCard(
                        project: project,
                        isSelected: selectedProjects.contains(project.id),
                        selectedCount: selectedProjects.count,
                        selectedProjects: selectedProjects,
                        tagManager: tagManager,
                        onTagSelected: handleTagSelection,
                        onSelect: { isShiftPressed in
                            // 确保在点击卡片时，移除现有焦点
                            NSApp.keyWindow?.makeFirstResponder(nil)
                            handleProjectSelection(project, isShiftPressed: isShiftPressed)
                        }
                    )
                }
            }
            .padding(AppTheme.cardGridPadding)
            .contentShape(Rectangle())
            .onTapGesture {
                // 确保在点击空白区域时，移除现有焦点
                NSApp.keyWindow?.makeFirstResponder(nil)
                // 清除搜索框焦点
                searchBarRef?.clearFocus()
                selectedProjects.removeAll()
            }
        }
        .overlay(alignment: .trailing) {
            ScrollIndicatorView()
        }
    }

    // 添加全选功能方法
    private func selectAllProjects() {
        // 清空当前选择
        selectedProjects.removeAll()
        
        // 选择所有筛选出的项目
        for project in filteredProjects {
            selectedProjects.insert(project.id)
        }
        
        print("已选择 \(selectedProjects.count) 个项目")
    }

    // 主内容视图
    private var mainContentView: some View {
        VStack {
            searchAndSortBar
            if filteredProjects.isEmpty {
                emptyStateView
            } else {
                projectGridView
            }
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }

            _ = provider.loadObject(ofClass: NSURL.self) { (url, error) in
                if let fileURL = url as? URL {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(
                        atPath: fileURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
                    {
                        DispatchQueue.main.async {
                            // 获取文件的修改时间
                            let modDate =
                                (try? URL(fileURLWithPath: fileURL.path).resourceValues(
                                    forKeys: [.contentModificationDateKey]
                                ).contentModificationDate) ?? Date()

                            let project = Project(
                                name: fileURL.lastPathComponent,
                                path: fileURL.path,
                                lastModified: modDate
                            )
                            tagManager.registerProject(project)
                        }
                    }
                }
            }
            return true
        }
    }

    var body: some View {
        HSplitView {
            sidebarView
            mainContentView
        }
        .onAppear {
            loadProjects()
            setupSelectAllMenuCommand()
        }
        .sheet(item: $tagToRename) { identifiableTag in
            TagEditDialog(
                title: "重命名标签",
                originalName: identifiableTag.value,
                isPresented: .init(
                    get: { tagToRename != nil },
                    set: { if !$0 { tagToRename = nil } }
                ),
                tagManager: tagManager
            ) { newName, color in
                DispatchQueue.main.async {
                    tagManager.renameTag(identifiableTag.value, to: newName, color: color)
                    tagToRename = nil
                }
            }
        }
        .toast()  // 添加 Toast 修饰符
    }

    private func loadProjects() {
        // 立即加载缓存的项目数据
        print("立即加载已缓存的项目数据")
        
        // 使用防抖动延迟加载
        let debounceTime: TimeInterval = 0.5  // 减少延迟
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceTime) {
            // 触发目录重新扫描和项目加载（后台进行）
            tagManager.directoryWatcher.incrementallyReloadProjects()
        }
    }

    // 设置全选菜单命令（通过主菜单实现⌘A）
    private func setupSelectAllMenuCommand() {
        DispatchQueue.main.async {
            // 1. 检查是否已经有我们自己的全局监听器处理了
            if SelectAllHandler.shared != nil {
                return // 已经设置过了
            }
            
            // 2. 创建全局事件监听器（不依赖于菜单项）
            let handler = SelectAllHandler { [self] in
                // 检查当前第一响应者
                if let firstResponder = NSApp.mainWindow?.firstResponder {
                    let className = String(describing: type(of: firstResponder))
                    
                    // 如果焦点在文本控件上，不执行我们的全选
                    if className.contains("Text") || className.contains("Field") || 
                       className.contains("SearchField") || className.contains("TextView") ||
                       className.contains("Input") || className.contains("Editor") {
                        // 不处理，让系统默认行为生效
                        return
                    }
                }
                
                // 执行我们的卡片全选功能
                selectAllProjects()
            }
            
            // 保存到全局变量
            SelectAllHandler.shared = handler
            
            // 3. 添加全局事件监听
            handler.setupGlobalKeyMonitor()
            
            // 4. 检查菜单项（作为备用方案）
            if let editMenu = NSApp.mainMenu?.item(withTitle: "Edit")?.submenu ?? 
                              NSApp.mainMenu?.item(withTitle: "编辑")?.submenu {
                
                // 检查是否有全选菜单项
                let selectAllTitle = "全选"
                let englishTitle = "Select All"
                
                if let selectAllItem = editMenu.item(withTitle: selectAllTitle) ?? editMenu.item(withTitle: englishTitle) {
                    print("找到全选菜单项: \(selectAllItem.title)")
                    
                    // 保存原始动作
                    handler.originalSelector = selectAllItem.action
                    
                    // 添加我们自己的动作作为菜单项的备选
                    let newAction = #selector(SelectAllHandler.menuItemPerformSelectAll(_:))
                    
                    // 替换动作
                    selectAllItem.action = newAction
                    selectAllItem.target = handler
                }
            }
        }
    }
}

// ViewModifier方式获取视图引用
struct ViewReferenceSetter<T: View>: ViewModifier {
    @Binding var reference: T?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // 当视图出现时保存引用
                reference = content as? T
            }
            .onDisappear {
                // 当视图消失时移除引用
                reference = nil
            }
    }
}

// 处理全选操作的类（必须是类才能使用@objc）
class SelectAllHandler: NSObject {
    var action: () -> Void
    var eventMonitor: Any?
    var originalSelector: Selector?
    
    // 保持一个全局引用以避免释放
    static var shared: SelectAllHandler?
    
    init(action: @escaping () -> Void) {
        self.action = action
        super.init()
    }
    
    // 设置全局键盘事件监听器
    func setupGlobalKeyMonitor() {
        // 移除现有监听器
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        // 添加全局键盘监听
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 检测 ⌘A 快捷键
            if event.modifierFlags.contains(.command) && event.keyCode == 0 {
                // 检查第一响应者
                if let firstResponder = NSApp.keyWindow?.firstResponder {
                    let className = String(describing: type(of: firstResponder))
                    
                    // 如果焦点在文本控件上，不干扰原始事件
                    if className.contains("Text") || className.contains("Field") || 
                       className.contains("SearchField") || className.contains("TextView") ||
                       className.contains("Input") || className.contains("Editor") {
                        return event // 让事件继续传递
                    }
                }
                
                // 执行我们的全选动作
                self?.action()
                return nil // 事件已处理
            }
            return event // 让事件继续传递
        }
    }
    
    // 用于菜单项的动作
    @objc func menuItemPerformSelectAll(_ sender: Any?) {
        action()
    }
    
    // 用于全局事件的动作
    @objc func performSelectAll() {
        action()
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

#if DEBUG
    struct ProjectListView_Previews: PreviewProvider {
        static var previews: some View {
            ProjectListView()
                .environmentObject(TagManager())
        }
    }
#endif
