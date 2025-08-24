import SwiftUI

struct SearchSortBar: View {
    @Binding var searchText: String
    @Binding var sortOption: ProjectListView.SortOption
    @Binding var searchBarRef: SearchBar?
    @State private var isShowingDashboard = false
    @EnvironmentObject var tagManager: TagManager
    
    // MARK: - 计算属性
    
    private var projectDataArray: [ProjectData] {
        return Array(tagManager.projects.values).map { project in
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
    
    var body: some View {
        HStack(spacing: 8) {
            SearchBar(text: $searchText)
                .modifier(ViewReferenceSetter(reference: $searchBarRef))
            
            // 仪表盘按钮
            Button(action: {
                isShowingDashboard = true
            }) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(AppTheme.titleBarIcon)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .help("项目仪表盘")
            
            SortButtons(sortOption: $sortOption)
        }
        .sheet(isPresented: $isShowingDashboard) {
            DashboardView(projects: projectDataArray)
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
    @Binding var sortOption: ProjectListView.SortOption
    
    var body: some View {
        HStack(spacing: 8) {
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
    }
}

#if DEBUG
struct SearchSortBar_Previews: PreviewProvider {
    static var previews: some View {
        SearchSortBar(
            searchText: .constant(""),
            sortOption: .constant(.timeDesc),
            searchBarRef: .constant(nil)
        )
    }
}
#endif 