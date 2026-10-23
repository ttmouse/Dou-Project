import SwiftUI

/// 主仪表盘视图 - 展示项目活动热力图和统计信息
struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @State private var selectedTimeRange: TimeRange = .threeMonths
    @EnvironmentObject var tagManager: TagManager
    
    let projects: [ProjectData]
    let onClose: (() -> Void)?
    private let usesCompactLayout: Bool
    
    private var dashboardProjects: [ProjectData] {
        let allProjects = tagManager.projects.values.map { project in
            ProjectData(from: project)
        }
        // 过滤掉包含"隐藏标签"的项目
        return ProjectLogic.filterProjectsByHiddenTags(allProjects)
    }
    
    init(projects: [ProjectData] = [], onClose: (() -> Void)? = nil, usesCompactLayout: Bool = false) {
        self.projects = projects
        self.onClose = onClose
        self.usesCompactLayout = usesCompactLayout
        self._viewModel = StateObject(wrappedValue: DashboardViewModel(projects: projects))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 标题和控制区域
                headerSection
                
                // 加载状态或错误显示
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.error {
                    errorView(error)
                } else if viewModel.hasEnoughData {
                    // 主要内容
                    mainContentSection
                } else {
                    emptyStateView
                }
            }
            .padding(20)
        }
        .navigationTitle(usesCompactLayout ? "" : "开发活动概览")
        .onChange(of: projects) { newProjects in
            // Linus式修复：使用tagManager重新获取最新的项目数据，确保包含git_daily
            let freshProjects = tagManager.projects.values.map { project in
                ProjectData(from: project)
            }
            print("🔧 DashboardView: 使用tagManager重新获取项目数据，项目数: \(freshProjects.count)")
            viewModel.refreshData(with: freshProjects)
        }
        .onAppear {
            // Linus式修复：初始化时也使用tagManager获取最新数据
            let freshProjects = tagManager.projects.values.map { project in
                ProjectData(from: project)
            }
            print("🔧 DashboardView.onAppear: 使用tagManager获取项目数据，项目数: \(freshProjects.count)")
            print("🔧 DashboardView.onAppear: 强制清空缓存数据，重新生成365天数据")
            viewModel.refreshData(with: freshProjects)
        }
        .background(
            // 隐藏的 ESC 键处理按钮
            Button("", action: { onClose?() })
            .keyboardShortcut(.escape)
            .hidden()
        )
    }
    
    // MARK: - 子视图
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // 标题和控制区域
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("开发活动概览")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("查看您的项目提交活动和开发模式")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 控制按钮区域
                HStack(spacing: 12) {
                    // 时间范围选择器
                    timeRangeSelector
                    
                    // 关闭按钮
                    if let onClose = onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.secondaryIcon)
                        }
                        .buttonStyle(IconButtonStyle(iconSize: 14, buttonSize: 30))
                        .help("关闭数据看板")
                    }
                }
            }
            .padding(.bottom, 8)
            
            // 快速统计卡片
            quickStatsCards
        }
    }
    
    private var timeRangeSelector: some View {
        Menu {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button(range.displayName) {
                    selectedTimeRange = range
                    updateTimeRange(range)
                }
            }
        } label: {
            HStack {
                Text(selectedTimeRange.displayName)
                    .font(.subheadline)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppTheme.secondaryBackground)
            .cornerRadius(6)
        }
        .menuStyle(BorderlessButtonMenuStyle())
    }
    
    private var quickStatsCards: some View {
        Group {
            if usesCompactLayout {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(0..<4, id: \.self) { index in
                        quickStatCard(for: index)
                    }
                }
            } else {
                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { index in
                        quickStatCard(for: index)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func quickStatCard(for index: Int) -> some View {
        switch index {
        case 0:
            QuickStatCard(title: "当前连续", value: "\(viewModel.currentStreak)", subtitle: "天", icon: "flame.fill", color: .orange)
        case 1:
            QuickStatCard(title: "最长连续", value: "\(viewModel.longestStreak)", subtitle: "天", icon: "trophy.fill", color: .yellow)
        case 2:
            QuickStatCard(title: "最近7天", value: "\(viewModel.recentActiveDays)", subtitle: "活跃天数", icon: "calendar", color: .blue)
        default:
            QuickStatCard(title: "活跃项目", value: "\(viewModel.mostActiveProjects.count)", subtitle: "个项目", icon: "folder.fill", color: .green)
        }
    }
    
    private var mainContentSection: some View {
        VStack(spacing: 20) {
            // 热力图区域
            if usesCompactLayout {
                ScrollView(.horizontal) {
                    heatmapSection
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                heatmapSection
            }
            
            // 统计信息卡片
            SimpleStatsCard(stats: viewModel.heatmapStats)
            
            // 最近提交项目列表
            if !viewModel.mostActiveProjects.isEmpty {
                recentCommitProjectsSection
            }
        }
    }

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("提交活动热力图")
                .font(.headline)
                .fontWeight(.semibold)

            UnifiedHeatmapView(
                projects: dashboardProjects,
                config: .dashboard
            )
            .background(AppTheme.secondaryBackground)
            .cornerRadius(10)
        }
    }
    
    private var recentCommitProjectsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("最近的十次提交")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("最后提交")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 0) {
                ForEach(Array(viewModel.mostActiveProjects.enumerated()), id: \.element.id) { index, project in
                    RecentCommitProjectRow(
                        project: project,
                        rank: index + 1
                    )
                    if index < viewModel.mostActiveProjects.count - 1 {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(AppTheme.secondaryBackground)
            .cornerRadius(12)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("正在加载仪表盘数据...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
    }
    
    private func errorView(_ error: DashboardError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("加载失败")
                .font(.headline)
            
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("重试") {
                viewModel.refreshData(with: [])
            }
            .buttonStyle(AppButtonStyle(isPrimary: true))
        }
        .padding(32)
        .frame(height: 200)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("暂无活动数据")
                .font(.headline)
            
            Text("还没有发现任何 Git 提交活动\n请确保项目包含有效的 Git 仓库")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(height: 200)
    }
    
    private var refreshButton: some View {
        Button(action: {
            viewModel.refreshData(with: [])
        }) {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(IconButtonStyle(iconSize: 14, buttonSize: 28))
        .help("刷新仪表盘数据")
    }
    
    // MARK: - 辅助方法
    
    private func updateTimeRange(_ range: TimeRange) {
        let newConfig = Dashboard.HeatmapConfig(
            daysToShow: range.days,
            cellSize: viewModel.heatmapConfig.cellSize,
            cellSpacing: viewModel.heatmapConfig.cellSpacing,
            cornerRadius: viewModel.heatmapConfig.cornerRadius,
            showWeekdayLabels: viewModel.heatmapConfig.showWeekdayLabels,
            showMonthLabels: viewModel.heatmapConfig.showMonthLabels
        )
        viewModel.updateHeatmapConfig(newConfig)
    }
}

// MARK: - 支持组件

/// 快速统计卡片
struct QuickStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(12)
    }
}

/// 最近提交项目行
struct RecentCommitProjectRow: View {
    let project: ProjectData
    let rank: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // 排名
            Text("\(rank)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            // 项目信息
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(project.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            // 提交信息
            VStack(alignment: .trailing, spacing: 2) {
                if let gitInfo = project.gitInfo {
                    Text(formatRelativeDate(gitInfo.lastCommitDate))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(timeColor(gitInfo.lastCommitDate))
                    
                    Text("\(gitInfo.commitCount) 次提交")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour, .minute], from: date, to: now)
        
        if let days = components.day, days > 0 {
            if days == 1 {
                return "1天前"
            } else if days < 7 {
                return "\(days)天前"
            } else if days < 30 {
                let weeks = days / 7
                return "\(weeks)周前"
            } else {
                let months = days / 30
                return "\(months)月前"
            }
        } else if let hours = components.hour, hours > 0 {
            return "\(hours)小时前"
        } else if let minutes = components.minute, minutes > 0 {
            return "\(minutes)分钟前"
        } else {
            return "刚刚"
        }
    }
    
    private func timeColor(_ date: Date) -> Color {
        let now = Date()
        let timeDiff = now.timeIntervalSince(date)
        let days = timeDiff / (24 * 60 * 60)
        
        switch days {
        case 0..<1: return .green      // 今天 - 绿色
        case 1..<7: return .blue       // 一周内 - 蓝色
        case 7..<30: return .orange    // 一月内 - 橙色
        default: return .secondary     // 更久 - 次要色
        }
    }
}

// MARK: - 统计组件

/// 简化的统计卡片
struct SimpleStatsCard: View {
    let stats: Dashboard.HeatmapStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("活动统计")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(stats.totalCommits)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("总提交数")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(stats.activeDays)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("活跃天数")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%.1f", stats.averageCommitsPerDay))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("日均提交")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(12)
    }
}


// TimeRange 枚举已移动到 DashboardModels.swift

// MARK: - 预览

#if DEBUG
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapper()
            .frame(width: 1000, height: 700)
    }
    
    struct PreviewWrapper: View {
        var body: some View {
            DashboardView(
                projects: createSampleProjects(),
                onClose: { }
            )
        }
    }
    
    static func createSampleProjects() -> [ProjectData] {
        let calendar = Calendar.current
        let today = Date()
        
        return (0..<15).map { index in
            let commitDate = calendar.date(byAdding: .day, value: -(index * 2), to: today) ?? today
            let commitCount = [0, 1, 3, 5, 8, 12, 20].randomElement() ?? 1
            
            return ProjectData(
                id: UUID(),
                name: "项目\(index + 1)",
                path: "/path/to/project\(index + 1)",
                lastModified: commitDate,
                tags: index % 3 == 0 ? ["Swift", "iOS"] : index % 2 == 0 ? ["React", "Web"] : [],
                gitInfo: ProjectData.GitInfoData(
                    commitCount: commitCount,
                    lastCommitDate: commitDate
                ),
                fileSystemInfo: ProjectData.FileSystemInfoData(
                    modificationDate: commitDate,
                    size: UInt64.random(in: 1024...1048576),
                    checksum: "checksum\(index)",
                    lastCheckTime: today
                )
            )
        }
    }
}
#endif
