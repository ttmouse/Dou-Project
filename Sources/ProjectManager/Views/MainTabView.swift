import SwiftUI

/// 主标签视图 - 包含项目列表和仪表盘导航
struct MainTabView: View {
    @EnvironmentObject var tagManager: TagManager
    @State private var selectedTab: TabSelection = .projects
    
    enum TabSelection: String, CaseIterable {
        case projects = "项目"
        case dashboard = "仪表盘"
        
        var icon: String {
            switch self {
            case .projects:
                return "folder.fill"
            case .dashboard:
                return "chart.line.uptrend.xyaxis"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            // 侧边栏
            VStack(spacing: 0) {
                // 导航标签
                navigationTabs
                
                Divider()
                    .background(Color(.separatorColor))
                
                // 根据选中标签显示相应内容
                switch selectedTab {
                case .projects:
                    ProjectSidebarContent()
                case .dashboard:
                    DashboardSidebarContent()
                }
            }
            .frame(minWidth: 250, maxWidth: 300)
            .background(Color(.windowBackgroundColor))
            
            // 主内容区域
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    // 切换侧边栏显示
                }) {
                    Image(systemName: "sidebar.left")
                }
            }
        }
    }
    
    // MARK: - 子视图
    
    private var navigationTabs: some View {
        HStack(spacing: 0) {
            ForEach(TabSelection.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14))
                        
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        selectedTab == tab ? 
                        Color(.selectedControlColor).opacity(0.8) : 
                        Color.clear
                    )
                    .foregroundColor(
                        selectedTab == tab ? 
                        Color(.controlAccentColor) : 
                        Color(.labelColor)
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor))
    }
    
    @ViewBuilder
    private var mainContent: some View {
        switch selectedTab {
        case .projects:
            ProjectListMainContent()
        case .dashboard:
            DashboardView(projects: projectDataArray)
        }
    }
    
    // MARK: - 计算属性
    
    private var projectDataArray: [ProjectData] {
        let allProjectData = Array(tagManager.projects.values).map { project in
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
        
        // 过滤掉包含"隐藏标签"的项目，确保数据看板统计准确
        return ProjectLogic.filterProjectsByHiddenTags(allProjectData)
    }
}

/// 项目列表侧边栏内容
struct ProjectSidebarContent: View {
    @State private var selectedTags: Set<String> = []
    @State private var isShowingNewTagDialog = false
    @State private var tagToRename: IdentifiableString? = nil
    @State private var selectedDirectory: String? = nil
    @State private var searchBarRef: SearchBar? = nil
    @State private var isDraggingDirectory = false
    @State private var heatmapFilteredProjectIds: Set<UUID> = []
    
    var body: some View {
        SidebarView(
            selectedTags: $selectedTags,
            searchBarRef: $searchBarRef,
            isDraggingDirectory: $isDraggingDirectory,
            isShowingNewTagDialog: $isShowingNewTagDialog,
            tagToRename: $tagToRename,
            selectedDirectory: $selectedDirectory,
            heatmapFilteredProjectIds: $heatmapFilteredProjectIds
        )
    }
}

/// 仪表盘侧边栏内容
struct DashboardSidebarContent: View {
    @State private var selectedTimeRange: TimeRange = .threeMonths
    @EnvironmentObject var tagManager: TagManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 时间范围选择
            VStack(alignment: .leading, spacing: 8) {
                Text("时间范围")
                    .font(.headline)
                    .padding(.horizontal, 16)
                
                VStack(spacing: 4) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Button(action: {
                            selectedTimeRange = range
                        }) {
                            HStack {
                                Text(range.displayName)
                                    .font(.system(size: 13))
                                Spacer()
                                if selectedTimeRange == range {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                selectedTimeRange == range ? 
                                Color(.selectedControlColor).opacity(0.6) : 
                                Color.clear
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            Divider()
                .padding(.horizontal, 16)
            
            // 统计信息
            VStack(alignment: .leading, spacing: 8) {
                Text("概览")
                    .font(.headline)
                    .padding(.horizontal, 16)
                
                VStack(spacing: 8) {
                    StatRow(
                        label: "总项目数", 
                        value: "\(tagManager.projects.count)",
                        icon: "folder.fill"
                    )
                    
                    StatRow(
                        label: "Git 项目", 
                        value: "\(gitProjectCount)",
                        icon: "arrow.triangle.branch"
                    )
                    
                    StatRow(
                        label: "标签数", 
                        value: "\(allTags.count)",
                        icon: "tag.fill"
                    )
                }
                .padding(.horizontal, 16)
            }
            
            Spacer()
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - 计算属性
    
    private var gitProjectCount: Int {
        return tagManager.projects.values.filter { $0.gitInfo != nil }.count
    }
    
    private var allTags: Set<String> {
        return Set(tagManager.projects.values.flatMap { $0.tags })
    }
}

/// 统计行组件
struct StatRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 16)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
        }
    }
}

/// 项目列表主内容（从原来的 ProjectListView 提取）
struct ProjectListMainContent: View {
    @EnvironmentObject var tagManager: TagManager
    
    var body: some View {
        ProjectListView()
    }
}

// MARK: - 预览

#if DEBUG
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(TagManager())
            .frame(width: 1000, height: 700)
    }
}
#endif