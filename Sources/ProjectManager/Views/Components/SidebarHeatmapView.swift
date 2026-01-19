import SwiftUI

/// 侧边栏热力图视图 - 使用缓存数据，高性能
struct SidebarHeatmapView: View {
    @ObservedObject private var dataStore = HeatmapDataStore.shared
    
    let onDateSelected: (([ProjectData]) -> Void)?
    let onDateFilter: ((Set<UUID>) -> Void)?
    
    @State private var hoveredCell: HeatmapLogic.HeatmapData?
    @State private var showTooltip = false
    
    private let config = HeatmapConfig.sidebar
    
    init(
        onDateSelected: (([ProjectData]) -> Void)? = nil,
        onDateFilter: ((Set<UUID>) -> Void)? = nil
    ) {
        self.onDateSelected = onDateSelected
        self.onDateFilter = onDateFilter
    }
    
    private var heatmapData: [HeatmapLogic.HeatmapData] {
        dataStore.getHeatmapData(days: config.days)
    }
    
    var body: some View {
        ZStack {
            adaptiveHeatmapGrid
            
            if config.showTooltip && showTooltip, let data = hoveredCell {
                tooltipView(for: data)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
    
    // MARK: - 自适应网格
    
    private var adaptiveHeatmapGrid: some View {
        GeometryReader { geometry in
            let weeks = generateWeekGrid(from: heatmapData)
            let metrics = calculateCellMetrics(containerWidth: geometry.size.width, weeks: weeks)
            let cellSize = metrics.cellSize
            let cellSpacing = metrics.cellSpacing
            let visibleWeeks = weeks.prefix(maxVisibleWeeks(for: geometry.size.width, cellSize: cellSize, cellSpacing: cellSpacing, weeks: weeks))
            
            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(Array(visibleWeeks.enumerated()), id: \.offset) { weekIndex, week in
                    VStack(spacing: cellSpacing) {
                        ForEach(0..<7, id: \.self) { dayIndex in
                            heatmapCell(data: week[dayIndex], cellSize: cellSize)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.tagListHeaderPaddingH)
        }
        .frame(height: calculateGridHeight())
        .padding(.bottom, AppTheme.tagListContentPaddingV)
    }
    
    // MARK: - 单元格
    
    private func heatmapCell(data: HeatmapLogic.HeatmapData?, cellSize: CGFloat) -> some View {
        Rectangle()
            .frame(width: cellSize, height: cellSize)
            .foregroundColor(cellColor(for: data))
            .cornerRadius(max(1, cellSize * 0.2))
            .onTapGesture {
                handleCellTap(data: data)
            }
            .onHover { isHovering in
                handleCellHover(data: data, isHovering: isHovering)
            }
    }
    
    private func cellColor(for data: HeatmapLogic.HeatmapData?) -> Color {
        guard let data = data else {
            return AppTheme.border
        }
        
        if data.commitCount == 0 {
            return AppTheme.sidebarHoverBackground
        }
        
        let intensity = data.intensity
        return AppTheme.success.opacity(0.3 + intensity * 0.7)
    }
    
    // MARK: - 交互
    
    private func handleCellTap(data: HeatmapLogic.HeatmapData?) {
        guard let data = data, data.commitCount > 0 else { return }
        
        let projectIds = dataStore.getProjectIds(for: data.date)
        if let onDateFilter = onDateFilter {
            onDateFilter(Set(projectIds))
        }
    }
    
    private func handleCellHover(data: HeatmapLogic.HeatmapData?, isHovering: Bool) {
        guard let data = data else { return }
        
        if isHovering {
            hoveredCell = data
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if hoveredCell?.date == data.date {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip = true
                    }
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.1)) {
                showTooltip = false
            }
            hoveredCell = nil
        }
    }
    
    // MARK: - 工具提示
    
    private func tooltipView(for data: HeatmapLogic.HeatmapData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatDate(data.date))
                .font(AppTheme.captionFont)
                .fontWeight(.medium)
                .foregroundColor(AppTheme.text)
            
            if data.commitCount == 0 {
                Text("无活动")
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.secondaryText)
            } else {
                let projectIds = dataStore.getProjectIds(for: data.date)
                Text("\(projectIds.count)个项目活跃（\(data.commitCount)次提交）")
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.success)
            }
        }
        .padding(8)
        .background(AppTheme.secondaryBackground.opacity(0.95))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
        .frame(maxWidth: 200)
        .fixedSize()
        .allowsHitTesting(false)
    }
    
    // MARK: - 布局计算
    
    private func generateWeekGrid(from data: [HeatmapLogic.HeatmapData]) -> [[HeatmapLogic.HeatmapData?]] {
        let calendar = Calendar.current
        var grid: [[HeatmapLogic.HeatmapData?]] = []
        
        guard !data.isEmpty else { return grid }
        
        let dataDict = Dictionary(grouping: data) { item in
            calendar.startOfDay(for: item.date)
        }.compactMapValues { $0.first }
        
        let startDate = data.first?.date ?? Date()
        let endDate = data.last?.date ?? Date()
        
        let startOfFirstWeek = calendar.dateInterval(of: .weekOfYear, for: startDate)?.start ?? startDate
        let endOfLastWeek = calendar.dateInterval(of: .weekOfYear, for: endDate)?.end ?? endDate
        
        var currentDate = startOfFirstWeek
        
        while currentDate < endOfLastWeek {
            var week: [HeatmapLogic.HeatmapData?] = []
            
            for _ in 0..<7 {
                let dayKey = calendar.startOfDay(for: currentDate)
                week.append(dataDict[dayKey])
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }
            
            grid.append(week)
        }
        
        return grid
    }
    
    private func calculateCellMetrics(containerWidth: CGFloat, weeks: [[HeatmapLogic.HeatmapData?]]) -> (cellSize: CGFloat, cellSpacing: CGFloat) {
        let horizontalPadding = AppTheme.tagListHeaderPaddingH * 2
        let availableWidth = containerWidth - horizontalPadding
        let weekCount = CGFloat(weeks.count)
        
        guard weekCount > 0 else {
            return (cellSize: 10, cellSpacing: 1.5)
        }
        
        let totalSpacingRatio: CGFloat = 0.10
        let totalSpacing = availableWidth * totalSpacingRatio
        let spacingBetweenWeeks = weekCount > 1 ? totalSpacing / (weekCount - 1) : 0
        
        let totalCellWidth = availableWidth - totalSpacing
        let cellSize = totalCellWidth / weekCount
        
        let minCellSize: CGFloat = 6
        let maxCellSize: CGFloat = 14
        let finalCellSize = max(minCellSize, min(maxCellSize, cellSize))
        
        let actualSpacing: CGFloat
        if finalCellSize != cellSize {
            let remainingWidth = availableWidth - (weekCount * finalCellSize)
            actualSpacing = weekCount > 1 ? max(0.5, remainingWidth / (weekCount - 1)) : 0
        } else {
            actualSpacing = spacingBetweenWeeks
        }
        
        return (cellSize: finalCellSize, cellSpacing: actualSpacing)
    }
    
    private func maxVisibleWeeks(for containerWidth: CGFloat, cellSize: CGFloat, cellSpacing: CGFloat, weeks: [[HeatmapLogic.HeatmapData?]]) -> Int {
        let horizontalPadding = AppTheme.tagListHeaderPaddingH * 2
        let availableWidth = containerWidth - horizontalPadding
        let maxWeeks = Int((availableWidth + cellSpacing) / (cellSize + cellSpacing))
        return min(maxWeeks, weeks.count)
    }
    
    private func calculateGridHeight() -> CGFloat {
        let containerWidth = AppTheme.sidebarMinWidth
        let weeks = generateWeekGrid(from: heatmapData)
        let metrics = calculateCellMetrics(containerWidth: containerWidth, weeks: weeks)
        let cellSize = metrics.cellSize
        let cellSpacing = metrics.cellSpacing
        return CGFloat(7) * cellSize + CGFloat(6) * cellSpacing + AppTheme.tagListSpacing
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}
