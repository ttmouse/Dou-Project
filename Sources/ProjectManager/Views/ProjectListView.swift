import SwiftUI

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
        var result = Array(tagManager.projects.values)

        // 搜索过滤
        if !searchText.isEmpty {
            result = result.filter { project in
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
        }

        // 标签过滤
        if !selectedTags.isEmpty {
            result = result.filter { project in
                !selectedTags.isDisjoint(with: project.tags)
            }
        }

        // 根据排序选项排序
        return result.sorted { lhs, rhs in
            switch sortOption {
            case .timeAsc:
                return lhs.lastModified < rhs.lastModified
            case .timeDesc:
                return lhs.lastModified > rhs.lastModified
            case .commitCount:
                let lhsCount = lhs.gitInfo?.commitCount ?? 0
                let rhsCount = rhs.gitInfo?.commitCount ?? 0
                return lhsCount > rhsCount
            }
        }
    }

    private func handleTagSelection(_ tag: String) {
        selectedTags = [tag]  // 直接选择点击的标签
    }

    // 处理项目选中
    private func handleProjectSelection(_ project: Project, isShiftPressed: Bool) {
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
        for projectId in selectedProjects {
            if let project = tagManager.projects[projectId] {
                tagManager.addTagToProject(projectId: project.id, tag: tag)
            }
        }
        // 清除选中状态
        selectedProjects.removeAll()
    }

    private var searchAndSortBar: some View {
        HStack(spacing: 8) {
            SearchBar(text: $searchText)

            // 时间排序按钮
            Button(action: {
                switch sortOption {
                case .timeDesc: sortOption = .timeAsc
                case .timeAsc: sortOption = .timeDesc
                case .commitCount: sortOption = .timeDesc
                }
            }) {
                Image(
                    systemName: sortOption == .timeAsc
                        ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
                )
                .foregroundColor(
                    sortOption == .commitCount ? AppTheme.titleBarIcon : AppTheme.accent
                )
                .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .help(sortOption == .timeAsc ? "最早的在前" : "最新的在前")

            // 提交次数排序按钮
            Button(action: {
                sortOption = .commitCount
            }) {
                Image(systemName: "number.circle.fill")
                    .foregroundColor(
                        sortOption == .commitCount ? AppTheme.accent : AppTheme.titleBarIcon
                    )
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

    // 目录选择按钮视图
    private var directoryPickerButton: some View {
        Button(action: {
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = true
                panel.prompt = "选择"
                panel.message = "请选择要监视的项目目录"

                panel.begin { response in
                    if response == .OK {
                        if let url = panel.url {
                            DispatchQueue.main.async {
                                self.watchedDirectory = url.path
                                UserDefaults.standard.set(
                                    self.watchedDirectory, forKey: "WatchedDirectory")
                                self.loadProjects()
                            }
                        }
                    }
                }
            }
        }) {
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(AppTheme.sidebarSecondaryText)
                Text(watchedDirectory)
                    .foregroundColor(AppTheme.sidebarTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(AppTheme.sidebarDirectoryBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(AppTheme.sidebarDirectoryBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.vertical, 8)
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
                ) { name in
                    tagManager.addTag(name)
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
                    action: { selectedTags.removeAll() },
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
            directoryPickerButton

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
        ScrollView {
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
                        tagManager: tagManager,
                        onTagSelected: handleTagSelection,
                        onSelect: { isShiftPressed in
                            handleProjectSelection(project, isShiftPressed: isShiftPressed)
                        }
                    )
                }
            }
            .padding(AppTheme.cardGridPadding)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedProjects.removeAll()
            }
        }
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
    }

    var body: some View {
        NavigationView {
            sidebarView
            mainContentView
        }
        .onAppear {
            loadProjects()
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
            ) { newName in
                DispatchQueue.main.async {
                    tagManager.renameTag(identifiableTag.value, to: newName)
                    tagToRename = nil
                }
            }
        }
    }

    private func loadProjects() {
        print("开始加载项目...")

        // 先显示缓存的项目
        let cachedProjects = Array(tagManager.projects.values)
        if !cachedProjects.isEmpty {
            print("使用缓存的 \(cachedProjects.count) 个项目")
        }

        // 使用防抖动延迟加载
        let debounceTime: TimeInterval = 2.0  // 2秒延迟
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceTime) {
            // 异步加载最新的项目
            DispatchQueue.global(qos: .userInitiated).async {
                let loadedProjects = Project.loadProjects(
                    from: self.watchedDirectory,
                    existingProjects: self.tagManager.projects
                )
                print("从磁盘加载到 \(loadedProjects.count) 个项目")

                // 找出需要更新的项目
                let existingProjects = Set(cachedProjects.map { $0.id })
                let newProjects = loadedProjects.filter { !existingProjects.contains($0.id) }
                let removedProjects = cachedProjects.filter { project in
                    !loadedProjects.contains { $0.id == project.id }
                }

                if !newProjects.isEmpty || !removedProjects.isEmpty {
                    // 批量更新 UI
                    DispatchQueue.main.async {
                        print("开始更新 UI...")
                        print("新增项目: \(newProjects.count), 移除项目: \(removedProjects.count)")

                        // 批量移除不存在的项目
                        removedProjects.forEach { project in
                            self.tagManager.removeProject(project.id)
                        }

                        // 批量添加新项目
                        if !newProjects.isEmpty {
                            // 分批添加新项目，每批20个
                            let batchSize = 20
                            for batch in stride(from: 0, to: newProjects.count, by: batchSize) {
                                let end = min(batch + batchSize, newProjects.count)
                                let projectBatch = Array(newProjects[batch..<end])

                                projectBatch.forEach { project in
                                    self.tagManager.registerProject(project)
                                }

                                // 每批之间添加小延迟
                                if end < newProjects.count {
                                    Thread.sleep(forTimeInterval: 0.1)
                                }
                            }
                        }

                        print("UI 更新完成，当前项目数: \(self.tagManager.projects.count)")
                    }
                } else {
                    print("项目列表无变化")
                }
            }
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
