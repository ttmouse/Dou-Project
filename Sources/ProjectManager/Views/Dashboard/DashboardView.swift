import SwiftUI

/// 主仪表盘视图 - 展示项目活动热力图和统计信息
struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @State private var selectedTimeRange: TimeRange = .threeMonths
    
    let projects: [ProjectData]
    
    init(projects: [ProjectData] = []) {
        self.projects = projects
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
        .navigationTitle("开发活动概览")
        .onChange(of: projects) { newProjects in
            viewModel.refreshData(with: newProjects)
        }
    }
    
    // MARK: - 子视图
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // 标题和时间选择器
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
                
                // 时间范围选择器
                timeRangeSelector
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
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
        .menuStyle(BorderlessButtonMenuStyle())
    }
    
    private var quickStatsCards: some View {
        HStack(spacing: 16) {
            QuickStatCard(
                title: "当前连续",
                value: "\(viewModel.currentStreak)",
                subtitle: "天",
                icon: "flame.fill",
                color: .orange
            )
            
            QuickStatCard(
                title: "最长连续",
                value: "\(viewModel.longestStreak)",
                subtitle: "天",
                icon: "trophy.fill",
                color: .yellow
            )
            
            QuickStatCard(
                title: "最近7天",
                value: "\(viewModel.recentActiveDays)",
                subtitle: "活跃天数",
                icon: "calendar",
                color: .blue
            )
            
            QuickStatCard(
                title: "活跃项目",
                value: "\(viewModel.mostActiveProjects.count)",
                subtitle: "个项目",
                icon: "folder.fill",
                color: .green
            )
        }
    }
    
    private var mainContentSection: some View {
        VStack(spacing: 20) {
            // 热力图区域
            VStack(alignment: .leading, spacing: 12) {
                Text("提交活动热力图")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                SimpleHeatmapView(
                    activities: viewModel.dailyActivities
                )
                .background(Color(.controlBackgroundColor))
                .cornerRadius(10)
            }
            
            // 统计信息卡片
            SimpleStatsCard(stats: viewModel.heatmapStats)
            
            // 最近提交项目列表
            if !viewModel.mostActiveProjects.isEmpty {
                recentCommitProjectsSection
            }
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
            .background(Color(.controlBackgroundColor))
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
            .buttonStyle(.borderedProminent)
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
        .background(Color(.controlBackgroundColor))
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

// MARK: - 简化的热力图和统计组件

/// 简化的热力图视图
struct SimpleHeatmapView: View {
    let activities: [DailyActivity]
    @State private var hoveredActivity: DailyActivity?
    @State private var mouseLocation: CGPoint = .zero
    @State private var showTooltip = false
    
    var body: some View {
        VStack(spacing: 12) {
            // GitHub 风格热力图
            ZStack {
                githubStyleHeatmap
                
                // 悬停工具提示
                if showTooltip, let activity = hoveredActivity {
                    tooltipView(for: activity)
                        .position(x: mouseLocation.x + 60, y: max(30, mouseLocation.y - 10))
                        .zIndex(1000)
                }
            }
            .frame(height: 120)
            
            // 简单的图例
            HStack {
                Text("少")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 1) {
                    ForEach(ActivityLevel.allCases, id: \.self) { level in
                        Rectangle()
                            .frame(width: 9, height: 9)
                            .foregroundColor(level.color)
                            .cornerRadius(1)
                    }
                }
                
                Text("多")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private var githubStyleHeatmap: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 月份标签
            monthLabels
            
            HStack(alignment: .top, spacing: 0) {
                // 星期标签
                weekdayLabels
                
                // 热力图网格
                heatmapGrid
            }
        }
        .background(
            // 透明的鼠标追踪区域
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            mouseLocation = value.location
                        }
                )
        )
    }
    
    private var monthLabels: some View {
        HStack(spacing: 0) {
            // 左侧留空对齐星期标签
            Spacer()
                .frame(width: 20)
            
            ForEach(0..<12) { monthIndex in
                Text(monthName(monthIndex))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: monthWidth(monthIndex), alignment: .leading)
            }
            
            Spacer() // 右侧填充
        }
    }
    
    private var weekdayLabels: some View {
        VStack(spacing: 2) {
            // 上方留空对齐月份标签
            Spacer().frame(height: 12)
            
            ForEach(["", "一", "", "三", "", "五", ""], id: \.self) { label in
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 11)
            }
        }
    }
    
    private var heatmapGrid: some View {
        VStack(spacing: 2) {
            // 上方留空对齐月份标签
            Spacer().frame(height: 12)
            
            ForEach(0..<7) { weekday in
                HStack(spacing: 2) {
                    ForEach(0..<53) { weekIndex in
                        let dayIndex = weekIndex * 7 + weekday
                        if dayIndex < 365 {
                            let activity = dayIndex < activities.count ? activities[dayIndex] : DailyActivity(date: Date(), commitCount: 0)
                            
                            Rectangle()
                                .frame(width: 11, height: 11)
                                .foregroundColor(activity.activityLevel.color)
                                .cornerRadius(2)
                                .scaleEffect(hoveredActivity?.id == activity.id ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.15), value: hoveredActivity?.id == activity.id)
                                .onHover { isHovering in
                                    withAnimation(.easeInOut(duration: 0.1)) {
                                        if isHovering {
                                            hoveredActivity = activity
                                            showTooltip = true
                                        } else {
                                            if hoveredActivity?.id == activity.id {
                                                hoveredActivity = nil
                                                showTooltip = false
                                            }
                                        }
                                    }
                                }
                        } else {
                            Rectangle()
                                .frame(width: 11, height: 11)
                                .foregroundColor(.clear)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private func monthName(_ index: Int) -> String {
        // 从去年9月开始到今年8月的顺序
        let monthSequence = [9, 10, 11, 12, 1, 2, 3, 4, 5, 6, 7, 8]
        let monthNumber = monthSequence[index]
        return "\(monthNumber)月"
    }
    
    private func monthWidth(_ index: Int) -> CGFloat {
        // 简化计算：每个月大约占用4.3周的宽度
        // 每个单元格 11px + 2px 间距 = 13px
        return 4.3 * 13.0 // 约56px每月
    }
    
    private func tooltipView(for activity: DailyActivity) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(activity.date))
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(commitCountText(activity.commitCount))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Rectangle()
                .frame(width: 8, height: 8)
                .foregroundColor(activity.activityLevel.color)
                .cornerRadius(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(.separatorColor), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
    
    // MARK: - 辅助方法
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }
    
    private func commitCountText(_ count: Int) -> String {
        switch count {
        case 0:
            return "无提交"
        case 1:
            return "1次提交"
        default:
            return "\(count)次提交"
        }
    }
}

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
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

/// 热力图单元格组件
struct HeatmapCell: View {
    let activity: DailyActivity
    let isHovered: Bool
    let onHover: (Bool) -> Void
    
    var body: some View {
        Rectangle()
            .frame(width: 11, height: 11)
            .foregroundColor(activity.activityLevel.color)
            .cornerRadius(2)
            .scaleEffect(isHovered ? 1.2 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover(perform: onHover)
    }
}

// TimeRange 枚举已移动到 DashboardModels.swift

// MARK: - 预览

#if DEBUG
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView(projects: createSampleProjects())
            .frame(width: 1000, height: 700)
    }
    
    static func createSampleProjects() -> [ProjectData] {
        let calendar = Calendar.current
        let today = Date()
        
        return (0..<15).map { index in
            let commitDate = calendar.date(byAdding: .day, value: -index * 2, to: today) ?? today
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