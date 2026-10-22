import SwiftUI

struct SearchSortBar: View {
    let searchInput: ProjectSearchInput
    @Binding var sortOption: SortOption
    @Binding var dateFilter: DateFilter
    @Binding var searchBarRef: SearchBar?
    @Binding var showDetailPanel: Bool
    @Binding var projectViewMode: ProjectViewMode
    let tagManager: TagManager
    @State private var isShowingDashboard = false
    @State private var dashboardProjects: [ProjectData] = []

    private func makeDashboardProjects() -> [ProjectData] {
        Array(tagManager.projects.values).map { project in
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
                    size: UInt64(project.size),
                    checksum: project.checksum,
                    lastCheckTime: project.checked
                )
            )
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 左侧工具按钮组
            HStack(spacing: 8) {
                // 仪表盘按钮
                Button(action: {
                    dashboardProjects = makeDashboardProjects()
                    isShowingDashboard = true
                }) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(AppTheme.titleBarIcon)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .frame(width: AppTheme.searchBarControlHeight, height: AppTheme.searchBarControlHeight)
                .help("项目仪表盘")
                
                Picker("视图", selection: $projectViewMode) {
                    ForEach(ProjectViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 72, height: AppTheme.searchBarControlHeight)
                .help(projectViewMode.title)
            }

            // 搜索框占据中间剩余空间，避免右侧控件溢出
            SearchBar(input: searchInput)
                .modifier(ViewReferenceSetter(reference: $searchBarRef))
                .frame(maxWidth: .infinity)

            // 右侧筛选和排序
            DateFilterMenu(dateFilter: $dateFilter)
            SortButtons(sortOption: $sortOption)

            // 详情面板从右侧展开，开关固定在工具栏最右侧以保持空间映射。
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDetailPanel.toggle()
                }
            }) {
                Image(systemName: "sidebar.trailing")
                    .foregroundColor(showDetailPanel ? AppTheme.accent : AppTheme.titleBarIcon)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .frame(width: AppTheme.searchBarControlHeight, height: AppTheme.searchBarControlHeight)
            .help(showDetailPanel ? "隐藏详情面板" : "显示详情面板")
        }
        .sheet(isPresented: $isShowingDashboard) {
            DashboardView(
                projects: dashboardProjects,
                onClose: {
                    isShowingDashboard = false
                }
            )
            .frame(minWidth: 800, minHeight: 600)
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
}

// MARK: - 排序按钮组件
struct SortButtons: View {
    @Binding var sortOption: SortOption
    
    var body: some View {
        HStack(spacing: 8) {
            // 时间排序按钮
            Button(action: {
                sortOption = sortOption.toggled(for: .activity)
            }) {
                Image(systemName: sortOption.column == .activity && sortOption.isAscending
                    ? "arrow.up.circle.fill"
                    : "arrow.down.circle.fill")
                    .foregroundColor(sortOption.column == .activity ? AppTheme.accent : AppTheme.titleBarIcon)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .frame(width: AppTheme.searchBarControlHeight, height: AppTheme.searchBarControlHeight)
            .help(sortOption.column == .activity && sortOption.isAscending ? "最早的在前" : "最新的在前")

            // 提交次数排序按钮
            Button(action: {
                sortOption = sortOption.toggled(for: .commits)
            }) {
                HStack(spacing: 2) {
                    Image(systemName: "number.circle.fill")
                        .font(.system(size: 20))

                    if sortOption.column == .commits {
                        Image(systemName: sortOption.isAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .foregroundColor(sortOption.column == .commits ? AppTheme.accent : AppTheme.titleBarIcon)
            }
            .buttonStyle(.plain)
            .frame(width: AppTheme.searchBarControlHeight, height: AppTheme.searchBarControlHeight)
            .help(sortOption.column == .commits && sortOption.isAscending ? "提交少的在前" : "提交多的在前")
        }
    }
}

#if DEBUG
struct SearchSortBar_Previews: PreviewProvider {
    static var previews: some View {
        SearchSortBar(
            searchInput: ProjectSearchInput(),
            sortOption: .constant(.timeDescending),
            dateFilter: .constant(.all),
            searchBarRef: .constant(nil),
            showDetailPanel: .constant(false),
            projectViewMode: .constant(.grid),
            tagManager: TagManager()
        )
    }
}
#endif

// MARK: - 日期筛选菜单
struct DateFilterMenu: View {
    @Binding var dateFilter: DateFilter
    
    var body: some View {
        Menu {
            ForEach(DateFilter.allCases, id: \.self) { option in
                Button(action: { dateFilter = option }) {
                    if dateFilter == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "calendar")
                Text(dateFilter.compactLabel)
            }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.titleBarIcon)
                .padding(.horizontal, 5)
                .frame(height: AppTheme.searchBarControlHeight)
                .contentShape(Rectangle())
                .fixedSize()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // Borderless menus otherwise absorb the toolbar's remaining width, which also
        // makes the opened menu nearly as wide as the window.
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: AppTheme.searchBarControlHeight)
        .accessibilityLabel("日期筛选")
        .accessibilityValue(dateFilter.title)
        .help("按日期筛选项目")
    }
}
