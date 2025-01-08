import SwiftUI

struct ProjectListView: View {
    @State private var searchText = ""
    @State private var selectedTags: Set<String> = []
    @State private var isShowingDirectoryPicker = false
    @State private var watchedDirectory: String = "/Users/douba/Downloads/GPT插件"
    
    // 排序方式
    enum SortOption {
        case timeAsc      // 时间升序
        case timeDesc     // 时间降序
        case commitCount  // 提交次数
    }
    @State private var sortOption: SortOption = .timeDesc
    
    @EnvironmentObject var tagManager: TagManager
    
    // 分步过滤
    private var filteredProjects: [Project] {
        var result = Array(tagManager.projects.values)
        
        // 搜索过滤
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
        .padding()
        .background(AppTheme.titleBarBackground)
        .overlay(
            Rectangle()
                .fill(AppTheme.titleBarBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    var body: some View {
        NavigationView {
            // 侧边栏
            VStack(spacing: 0) {
                // 目录选择按钮
                Button(action: {
                    isShowingDirectoryPicker = true
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
                
                // 标签列表
                VStack(alignment: .leading, spacing: AppTheme.tagListSpacing) {
                    HStack {
                        Text("标签")
                            .font(.headline)
                            .foregroundColor(AppTheme.sidebarTitle)
                        
                        Spacer()
                        
                        Button(action: { selectedTags.removeAll() }) {
                            Text("清除")
                                .font(.subheadline)
                                .foregroundColor(selectedTags.isEmpty ? AppTheme.sidebarSecondaryText : AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .opacity(selectedTags.isEmpty ? 0.5 : 1)
                    }
                    .padding(.horizontal, AppTheme.tagListHeaderPaddingH)
                    .padding(.vertical, AppTheme.tagListHeaderPaddingV)
                    
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: AppTheme.tagRowSpacing) {
                            ForEach(Array(tagManager.allTags).sorted { tag1, tag2 in
                                let count1 = tagManager.getUsageCount(for: tag1)
                                let count2 = tagManager.getUsageCount(for: tag2)
                                return count1 > count2
                            }, id: \.self) { tag in
                                TagRow(
                                    tag: tag,
                                    isSelected: selectedTags.contains(tag),
                                    count: tagManager.getUsageCount(for: tag),
                                    action: { handleTagSelection(tag) },
                                    tagManager: tagManager
                                )
                            }
                        }
                        .padding(.vertical, AppTheme.tagListContentPaddingV)
                    }
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
            
            // 主内容
            VStack {
                searchAndSortBar
                
                if filteredProjects.isEmpty {
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
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 250, maximum: 400))],
                            spacing: 16
                        ) {
                            ForEach(filteredProjects) { project in
                                ProjectCard(
                                    project: project,
                                    tagManager: tagManager,
                                    onTagSelected: handleTagSelection
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .onAppear {
            loadProjects()
        }
        .fileImporter(
            isPresented: $isShowingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    watchedDirectory = url.path
                    loadProjects()
                }
            case .failure(let error):
                print("选择目录失败: \(error)")
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
        
        // 异步加载最新的项目
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedProjects = Project.loadProjects(from: watchedDirectory)
            print("从磁盘加载到 \(loadedProjects.count) 个项目")
            
            // 找出需要更新的项目
            let existingProjects = Set(cachedProjects.map { $0.id })
            let newProjects = loadedProjects.filter { !existingProjects.contains($0.id) }
            let removedProjects = cachedProjects.filter { project in
                !loadedProjects.contains { $0.id == project.id }
            }
            
            if !newProjects.isEmpty || !removedProjects.isEmpty {
                DispatchQueue.main.async {
                    print("开始更新 UI...")
                    print("新增项目: \(newProjects.count), 移除项目: \(removedProjects.count)")
                    
                    // 移除不存在的项目
                    removedProjects.forEach { project in
                        self.tagManager.removeProject(project.id)
                    }
                    
                    // 添加新项目
                    newProjects.forEach { project in
                        self.tagManager.registerProject(project)
                    }
                    
                    print("UI 更新完成，当前项目数: \(self.tagManager.projects.count)")
                }
            } else {
                print("项目列表无变化")
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
