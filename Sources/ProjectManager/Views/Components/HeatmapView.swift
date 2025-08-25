import SwiftUI

/// 热力图视图 - Linus式：保持简单，功能第一
struct HeatmapView: View {
    let heatmapData: [HeatmapLogic.HeatmapData]
    let onDateSelected: ([ProjectData]) -> Void
    let onDateFilter: (([ProjectData]) -> Void)?
    
    // 自适应配置 - 根据侧边栏宽度动态调整
    private let daysPerWeek = 7
    
    // 计算动态的格子大小和间距，充分利用侧边栏宽度
    private func calculateCellMetrics(containerWidth: CGFloat) -> (cellSize: CGFloat, cellSpacing: CGFloat) {
        let horizontalPadding = AppTheme.tagListHeaderPaddingH * 2
        let availableWidth = containerWidth - horizontalPadding
        let weekCount = CGFloat(weeks.count)
        
        guard weekCount > 0 else {
            return (cellSize: 10, cellSpacing: 1.5)
        }
        
        // 设定间距占总宽度的比例（10%）
        let totalSpacingRatio: CGFloat = 0.10
        let totalSpacing = availableWidth * totalSpacingRatio
        let spacingBetweenWeeks = weekCount > 1 ? totalSpacing / (weekCount - 1) : 0
        
        // 计算格子大小：剩余宽度除以周数
        let totalCellWidth = availableWidth - totalSpacing
        let cellSize = totalCellWidth / weekCount
        
        // 限制格子大小在合理范围内
        let minCellSize: CGFloat = 6
        let maxCellSize: CGFloat = 14
        let finalCellSize = max(minCellSize, min(maxCellSize, cellSize))
        
        // 如果格子大小被限制了，重新计算间距
        let actualSpacing: CGFloat
        if finalCellSize != cellSize {
            let remainingWidth = availableWidth - (weekCount * finalCellSize)
            actualSpacing = weekCount > 1 ? max(0.5, remainingWidth / (weekCount - 1)) : 0
        } else {
            actualSpacing = spacingBetweenWeeks
        }
        
        return (cellSize: finalCellSize, cellSpacing: actualSpacing)
    }
    
    private var weeks: [[HeatmapLogic.HeatmapData?]] {
        generateWeekGrid(from: heatmapData)
    }
    
    var body: some View {
        // 热力图网格
        heatmapGrid
    }
    
    // MARK: - 热力图网格 (自适应布局，无水平滚动)
    private var heatmapGrid: some View {
        GeometryReader { geometry in
            let metrics = calculateCellMetrics(containerWidth: geometry.size.width)
            let cellSize = metrics.cellSize
            let cellSpacing = metrics.cellSpacing
            
            // 确保所有列都能在可用宽度内显示
            let visibleWeeks = weeks.prefix(maxVisibleWeeks(for: geometry.size.width, cellSize: cellSize, cellSpacing: cellSpacing))
            
            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(Array(visibleWeeks.enumerated()), id: \.offset) { weekIndex, week in
                    VStack(spacing: cellSpacing) {
                        ForEach(0..<daysPerWeek, id: \.self) { dayIndex in
                            heatmapCell(data: week[dayIndex], cellSize: cellSize)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.tagListHeaderPaddingH)
        }
        .frame(height: calculateGridHeight(with: AppTheme.sidebarMinWidth))
        .padding(.bottom, AppTheme.tagListContentPaddingV)
    }
    
    // 计算在给定宽度下能显示的最大周数
    private func maxVisibleWeeks(for containerWidth: CGFloat, cellSize: CGFloat, cellSpacing: CGFloat) -> Int {
        let horizontalPadding = AppTheme.tagListHeaderPaddingH * 2
        let availableWidth = containerWidth - horizontalPadding
        
        // 计算能容纳的最大周数
        // 公式：n * cellSize + (n-1) * cellSpacing <= availableWidth
        let maxWeeks = Int((availableWidth + cellSpacing) / (cellSize + cellSpacing))
        return min(maxWeeks, weeks.count)
    }
    
    // 计算网格高度（基于预期的格子大小）
    private func calculateGridHeight(with containerWidth: CGFloat) -> CGFloat {
        let metrics = calculateCellMetrics(containerWidth: containerWidth)
        let cellSize = metrics.cellSize
        let cellSpacing = metrics.cellSpacing
        
        // 计算实际高度：7天的格子 + 6个间距
        return CGFloat(daysPerWeek) * cellSize + CGFloat(daysPerWeek - 1) * cellSpacing + AppTheme.tagListSpacing
    }
    
    // MARK: - 热力图单元格
    private func heatmapCell(data: HeatmapLogic.HeatmapData?, cellSize: CGFloat) -> some View {
        Rectangle()
            .frame(width: cellSize, height: cellSize)
            .foregroundColor(cellColor(for: data))
            .cornerRadius(max(1, cellSize * 0.2)) // 动态圆角
            .onTapGesture {
                if let data = data, !data.projects.isEmpty {
                    // 优先执行筛选功能
                    if let onDateFilter = onDateFilter {
                        onDateFilter(data.projects)
                    } else {
                        // 如果没有筛选功能，则显示弹窗
                        onDateSelected(data.projects)
                    }
                }
            }
            .help(cellTooltip(for: data))
    }
    
    // MARK: - 颜色计算 (统一风格：使用AppTheme颜色)
    private func cellColor(for data: HeatmapLogic.HeatmapData?) -> Color {
        guard let data = data else {
            return AppTheme.border // 无数据：使用主题边框色
        }
        
        if data.commitCount == 0 {
            return AppTheme.sidebarHoverBackground // 无提交：使用侧边栏悬停色
        }
        
        // 使用主题绿色系
        let intensity = data.intensity
        return AppTheme.success.opacity(0.3 + intensity * 0.7)
    }
    
    // MARK: - 提示文本
    private func cellTooltip(for data: HeatmapLogic.HeatmapData?) -> String {
        guard let data = data else {
            return "无数据"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        let dateString = formatter.string(from: data.date)
        
        if data.commitCount == 0 {
            return "\(dateString): 无活动"
        } else {
            let projectNames = data.projects.map { $0.name }.joined(separator: ", ")
            return "\(dateString): \(data.commitCount)个项目活跃\n\(projectNames)"
        }
    }
    
    
    // MARK: - 网格生成 (Linus式：直接计算，不搞花里胡哨)
    private func generateWeekGrid(from data: [HeatmapLogic.HeatmapData]) -> [[HeatmapLogic.HeatmapData?]] {
        let calendar = Calendar.current
        var grid: [[HeatmapLogic.HeatmapData?]] = []
        
        // 按日期建立索引
        var dataDict: [Date: HeatmapLogic.HeatmapData] = [:]
        for item in data {
            dataDict[calendar.startOfDay(for: item.date)] = item
        }
        
        // 找到第一天和最后一天
        guard let firstDate = data.first?.date,
              let lastDate = data.last?.date else {
            return []
        }
        
        let startOfFirstWeek = calendar.dateInterval(of: .weekOfYear, for: firstDate)?.start ?? firstDate
        let endOfLastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDate)?.end ?? lastDate
        
        var currentDate = startOfFirstWeek
        
        while currentDate < endOfLastWeek {
            var week: [HeatmapLogic.HeatmapData?] = []
            
            // 一周7天
            for _ in 0..<daysPerWeek {
                let dayKey = calendar.startOfDay(for: currentDate)
                week.append(dataDict[dayKey])
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }
            
            grid.append(week)
        }
        
        return grid
    }
}

// MARK: - 项目列表弹窗 (Linus式：简单的弹窗显示项目)
struct ProjectListPopover: View {
    let projects: [ProjectData]
    let date: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.tagListSpacing) {
            HStack {
                Text("\(date) 的活跃项目")
                    .font(AppTheme.subtitleFont)
                    .foregroundColor(AppTheme.text)
                Spacer()
                Button("关闭") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, AppTheme.tagListHeaderPaddingH)
            .padding(.vertical, AppTheme.tagListHeaderPaddingV)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.tagRowSpacing) {
                    ForEach(projects, id: \.id) { project in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(AppTheme.bodyFont)
                                    .fontWeight(.medium)
                                    .foregroundColor(AppTheme.text)
                                
                                Text(project.path)
                                    .font(AppTheme.captionFont)
                                    .foregroundColor(AppTheme.secondaryText)
                                
                                if let gitInfo = project.gitInfo {
                                    Text("提交数: \(gitInfo.commitCount)")
                                        .font(AppTheme.captionFont)
                                        .foregroundColor(AppTheme.success)
                                }
                            }
                            Spacer()
                        }
                        .padding(AppTheme.tagRowPaddingH)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(AppTheme.tagRowCornerRadius)
                    }
                }
            }
            .padding(.horizontal, AppTheme.tagListContentPaddingV)
        }
        .padding()
        .frame(minWidth: 300, maxWidth: 400, minHeight: 200, maxHeight: 400)
        .background(AppTheme.secondaryBackground)
    }
}

// MARK: - Preview
#if DEBUG
struct HeatmapView_Previews: PreviewProvider {
    static var previews: some View {
        HeatmapView(
            heatmapData: sampleHeatmapData(),
            onDateSelected: { projects in
                print("Selected projects: \(projects.map { $0.name })")
            },
            onDateFilter: { projects in
                print("Filter projects: \(projects.map { $0.name })")
            }
        )
        .frame(width: 400)
    }
    
    static func sampleHeatmapData() -> [HeatmapLogic.HeatmapData] {
        let calendar = Calendar.current
        let today = Date()
        
        return (0..<30).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                return nil
            }
            
            let commitCount = Int.random(in: 0...5)
            return HeatmapLogic.HeatmapData(
                date: date,
                commitCount: commitCount,
                projects: [] // 预览时为空
            )
        }
    }
}
#endif