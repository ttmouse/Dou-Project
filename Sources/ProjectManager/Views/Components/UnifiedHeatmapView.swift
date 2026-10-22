import SwiftUI

/// 统一的热力图配置
struct HeatmapConfig {
    static let maxDays = 365

    let days: Int                    // 显示天数
    let showTooltip: Bool           // 是否显示悬浮提示
    let showHeader: Bool            // 是否显示头部标签（月份等）
    let showLegend: Bool            // 是否显示图例
    let showWeekdayLabels: Bool     // 是否显示星期标签
    let compactMode: Bool           // 紧凑模式（侧边栏用）
    let useAdaptiveSpacing: Bool    // 是否使用自适应间距

    init(
        days: Int,
        showTooltip: Bool,
        showHeader: Bool,
        showLegend: Bool,
        showWeekdayLabels: Bool,
        compactMode: Bool,
        useAdaptiveSpacing: Bool
    ) {
        self.days = min(max(days, 1), Self.maxDays)
        self.showTooltip = showTooltip
        self.showHeader = showHeader
        self.showLegend = showLegend
        self.showWeekdayLabels = showWeekdayLabels
        self.compactMode = compactMode
        self.useAdaptiveSpacing = useAdaptiveSpacing
    }
    
    // 预设配置
    static let sidebar = HeatmapConfig(
        days: 90,
        showTooltip: true,
        showHeader: false,          // 侧边栏不显示头部
        showLegend: false,
        showWeekdayLabels: false,
        compactMode: true,
        useAdaptiveSpacing: true    // 侧边栏使用自适应间距
    )
    
    static let dashboard = HeatmapConfig(
        days: 365,
        showTooltip: true,
        showHeader: true,           // 数据看板显示完整头部
        showLegend: true,
        showWeekdayLabels: true,
        compactMode: false,
        useAdaptiveSpacing: false   // 数据看板使用固定间距
    )
}

/// 统一的热力图视图
struct UnifiedHeatmapView: View {
    let projects: [ProjectData]
    let config: HeatmapConfig
    let onDateSelected: (([ProjectData]) -> Void)?
    let onDateFilter: (([ProjectData]) -> Void)?
    
    // 状态管理
    @State private var heatmapData: [HeatmapLogic.HeatmapData] = []
    @State private var isGenerating = false
    @State private var hoveredCell: HeatmapLogic.HeatmapData?
    @State private var showTooltip = false
    /// 数据生成代次：用于丢弃已过期的并行计算结果
    @State private var generationToken = 0
    
    init(
        projects: [ProjectData], 
        config: HeatmapConfig = .sidebar,
        onDateSelected: (([ProjectData]) -> Void)? = nil,
        onDateFilter: (([ProjectData]) -> Void)? = nil
    ) {
        self.projects = projects
        self.config = config
        self.onDateSelected = onDateSelected
        self.onDateFilter = onDateFilter
    }
    
    var body: some View {
        VStack(spacing: config.compactMode ? 8 : 12) {
            // 条件显示头部
            if config.showHeader {
                headerSection
            }
            
            // 热力图网格 - 使用原有的自适应布局或固定布局
            ZStack {
                if config.useAdaptiveSpacing {
                    adaptiveHeatmapGrid
                } else {
                    fixedHeatmapGrid
                }
                
                // 使用原有的优秀悬停效果
                if config.showTooltip && showTooltip, let data = hoveredCell {
                    originalStyleTooltip(for: data)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            
            // 条件显示图例
            if config.showLegend {
                legendSection
            }
        }
        .onAppear {
            generateHeatmapData()
        }
        .onChange(of: projects) { _ in
            generateHeatmapData()
        }
    }
    
    // MARK: - 子视图
    
    private var headerSection: some View {
        VStack(spacing: 4) {
            // 月份标签
            HStack(spacing: 0) {
                if config.showWeekdayLabels {
                    Spacer().frame(width: 20) // 对齐星期标签
                }
                ForEach(0..<12) { monthIndex in
                    Text(monthName(monthIndex))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: monthWidth(monthIndex), alignment: .leading)
                }
                Spacer()
            }
        }
    }
    
    // MARK: - 自适应网格（原有侧边栏样式）
    private var adaptiveHeatmapGrid: some View {
        GeometryReader { geometry in
            let weeks = generateWeekGrid(from: heatmapData)
            let metrics = calculateCellMetrics(containerWidth: geometry.size.width, weeks: weeks)
            let cellSize = metrics.cellSize
            let cellSpacing = metrics.cellSpacing
            
            // 确保所有列都能在可用宽度内显示
            let visibleWeeks = weeks.prefix(maxVisibleWeeks(for: geometry.size.width, cellSize: cellSize, cellSpacing: cellSpacing, weeks: weeks))
            
            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(Array(visibleWeeks.enumerated()), id: \.offset) { weekIndex, week in
                    VStack(spacing: cellSpacing) {
                        ForEach(0..<7, id: \.self) { dayIndex in
                            adaptiveHeatmapCell(data: week[dayIndex], cellSize: cellSize)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.tagListHeaderPaddingH)
        }
        .frame(height: calculateGridHeight())
        .padding(.bottom, config.compactMode ? AppTheme.tagListContentPaddingV : 0)
    }
    
    // MARK: - 固定网格（数据看板样式）  
    private var fixedHeatmapGrid: some View {
        let weeks = generateWeekGrid(from: heatmapData)
        
        return HStack(alignment: .top, spacing: 0) {
            // 条件显示星期标签
            if config.showWeekdayLabels {
                weekdayLabels
            }
            
            // 热力图网格
            HStack(alignment: .top, spacing: 1) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                    VStack(spacing: 1) {
                        ForEach(0..<7, id: \.self) { dayIndex in
                            fixedHeatmapCell(data: week[dayIndex])
                        }
                    }
                }
            }
        }
    }
    
    private var weekdayLabels: some View {
        VStack(spacing: 1) {
            ForEach(["", "一", "", "三", "", "五", ""], id: \.self) { label in
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 11)
            }
        }
    }
    
    private var legendSection: some View {
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
    
    // MARK: - 热力图单元格
    
    // 自适应单元格（侧边栏用）
    private func adaptiveHeatmapCell(data: HeatmapLogic.HeatmapData?, cellSize: CGFloat) -> some View {
        Rectangle()
            .frame(width: cellSize, height: cellSize)
            .foregroundColor(originalCellColor(for: data))
            .cornerRadius(max(1, cellSize * 0.2)) // 动态圆角
            .onTapGesture {
                handleCellTap(data: data)
            }
            .onHover { isHovering in
                handleOriginalCellHover(data: data, isHovering: isHovering)
            }
    }
    
    // 固定单元格（数据看板用）
    private func fixedHeatmapCell(data: HeatmapLogic.HeatmapData?) -> some View {
        Rectangle()
            .frame(width: 11, height: 11)
            .foregroundColor(cellColor(for: data))
            .cornerRadius(max(1, 11 * 0.2))
            .onTapGesture {
                handleCellTap(data: data)
            }
            .onHover { isHovering in
                handleCellHover(data: data, isHovering: isHovering)
            }
    }
    
    // MARK: - 交互处理
    
    private func handleCellTap(data: HeatmapLogic.HeatmapData?) {
        guard let data = data, !data.projects.isEmpty else { return }
        
        if let onDateFilter = onDateFilter {
            onDateFilter(data.projects)
        } else if let onDateSelected = onDateSelected {
            onDateSelected(data.projects)
        }
    }
    
    // 原有的300ms延迟悬停效果（侧边栏用）
    private func handleOriginalCellHover(data: HeatmapLogic.HeatmapData?, isHovering: Bool) {
        guard let data = data else { return }
        
        if isHovering {
            hoveredCell = data
            // 300ms 延迟后显示提示 - 原有的优秀体验
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if hoveredCell?.date == data.date { // 确保还在悬停同一个格子
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip = true
                    }
                }
            }
        } else {
            // 立即隐藏提示
            withAnimation(.easeInOut(duration: 0.1)) {
                showTooltip = false
            }
            hoveredCell = nil
        }
    }
    
    // 数据看板的悬停效果
    private func handleCellHover(data: HeatmapLogic.HeatmapData?, isHovering: Bool) {
        guard config.showTooltip, let data = data else { return }
        
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
    
    // 原有AppTheme样式的工具提示
    private func originalStyleTooltip(for data: HeatmapLogic.HeatmapData) -> some View {
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
                Text("\(data.projects.count)个项目活跃（\(data.commitCount)次提交）")
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.success)
                
                if !data.projects.isEmpty {
                    let projectNames = data.projects.prefix(3).map { $0.name }.joined(separator: ", ")
                    Text(projectNames + (data.projects.count > 3 ? "..." : ""))
                        .font(AppTheme.captionFont)
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(2)
                }
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
        .allowsHitTesting(false) // 让鼠标事件穿透 - 重要的原有特性
    }
    
    // 数据看板样式的工具提示
    private func tooltipView(for data: HeatmapLogic.HeatmapData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatDate(data.date))
                .font(.caption)
                .fontWeight(.medium)
            
            if data.commitCount == 0 {
                Text("无活动")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("\(data.projects.count)个项目活跃（\(data.commitCount)次提交）")
                    .font(.caption)
                    .foregroundColor(.green)
                
                if !data.projects.isEmpty {
                    let projectNames = data.projects.prefix(3).map { $0.name }.joined(separator: ", ")
                    Text(projectNames + (data.projects.count > 3 ? "..." : ""))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .frame(maxWidth: 200)
        .fixedSize()
    }
    
    // MARK: - 数据生成
    
    /// 生成热力图数据
    /// 症状（本次修复）：看板首帧卡 5 秒 —— 本视图被推断为 @MainActor（View 协议的隔离），
    /// 普通 `Task {}` 会继承主 actor 并在主线程同步跑完整轮重计算。
    /// 改用 Task.detached 真正下放后台，并用 token 丢弃过期结果（并行后可能后发先至）。
    private func generateHeatmapData() {
        guard !projects.isEmpty else { return }

        // 快照输入，避免后台线程读取视图属性
        let snapshot = projects
        let days = min(config.days, HeatmapConfig.maxDays)

        generationToken &+= 1
        let token = generationToken

        isGenerating = true

        Task.detached(priority: .userInitiated) {
            let data = HeatmapLogic.generateHeatmapData(from: snapshot, days: days)

            await MainActor.run {
                guard token == self.generationToken else { return }  // 已有更新的请求，丢弃本次结果
                self.heatmapData = data
                self.isGenerating = false
            }
        }
    }
    
    // MARK: - 辅助方法
    
    // 原有的AppTheme配色方案（侧边栏用）
    private func originalCellColor(for data: HeatmapLogic.HeatmapData?) -> Color {
        guard let data = data else {
            return AppTheme.border // 无数据：使用主题边框色
        }
        
        if data.commitCount == 0 {
            return AppTheme.sidebarHoverBackground // 无提交：使用侧边栏悬停色
        }
        
        // 使用主题绿色系 - 原有的优秀配色
        let intensity = data.intensity
        return AppTheme.success.opacity(0.3 + intensity * 0.7)
    }
    
    // 数据看板配色方案
    private func cellColor(for data: HeatmapLogic.HeatmapData?) -> Color {
        guard let data = data else {
            return Color.gray.opacity(0.1)
        }
        
        if data.commitCount == 0 {
            return Color.gray.opacity(0.1)
        }
        
        let intensity = data.intensity
        return Color.green.opacity(0.3 + intensity * 0.7)
    }
    
    // MARK: - 自适应布局计算（原有的优秀算法）
    
    // 计算动态的格子大小和间距，充分利用侧边栏宽度
    private func calculateCellMetrics(containerWidth: CGFloat, weeks: [[HeatmapLogic.HeatmapData?]]) -> (cellSize: CGFloat, cellSpacing: CGFloat) {
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
    
    // 计算在给定宽度下能显示的最大周数
    private func maxVisibleWeeks(for containerWidth: CGFloat, cellSize: CGFloat, cellSpacing: CGFloat, weeks: [[HeatmapLogic.HeatmapData?]]) -> Int {
        let horizontalPadding = AppTheme.tagListHeaderPaddingH * 2
        let availableWidth = containerWidth - horizontalPadding
        
        // 计算能容纳的最大周数
        // 公式：n * cellSize + (n-1) * cellSpacing <= availableWidth
        let maxWeeks = Int((availableWidth + cellSpacing) / (cellSize + cellSpacing))
        return min(maxWeeks, weeks.count)
    }
    
    // 计算网格高度（基于预期的格子大小）
    private func calculateGridHeight() -> CGFloat {
        let containerWidth = AppTheme.sidebarMinWidth // 预估宽度
        let weeks = generateWeekGrid(from: heatmapData)
        let metrics = calculateCellMetrics(containerWidth: containerWidth, weeks: weeks)
        let cellSize = metrics.cellSize
        let cellSpacing = metrics.cellSpacing
        
        // 计算实际高度：7天的格子 + 6个间距
        return CGFloat(7) * cellSize + CGFloat(6) * cellSpacing + AppTheme.tagListSpacing
    }
    
    private func generateWeekGrid(from data: [HeatmapLogic.HeatmapData]) -> [[HeatmapLogic.HeatmapData?]] {
        let calendar = Calendar.current
        var grid: [[HeatmapLogic.HeatmapData?]] = []
        
        guard !data.isEmpty else { return grid }
        
        let dataDict = Dictionary(grouping: data) { item in
            calendar.startOfDay(for: item.date)
        }.compactMapValues { $0.first }
        
        // 🎯 修复：数据看板强制使用365天完整范围
        let startDate: Date
        let endDate: Date
        
        if config.days == 365 {
            // 数据看板模式：强制显示完整365天网格
            let today = Date()
            endDate = today
            startDate = calendar.date(byAdding: .day, value: -365, to: today) ?? today
        } else {
            // 侧边栏模式：使用数据驱动的优化范围
            startDate = data.first?.date ?? Date()
            endDate = data.last?.date ?? Date()
        }
        
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
    
    private func monthName(_ index: Int) -> String {
        let monthSequence = [9, 10, 11, 12, 1, 2, 3, 4, 5, 6, 7, 8]
        let monthNumber = monthSequence[index]
        return "\(monthNumber)月"
    }
    
    private func monthWidth(_ index: Int) -> CGFloat {
        return 4.3 * 13.0 // 简化计算，固定宽度
    }
}

// MARK: - 预览

#if DEBUG
struct UnifiedHeatmapView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // 侧边栏模式
            UnifiedHeatmapView(
                projects: createSampleProjects(),
                config: .sidebar
            )
            .frame(width: 300, height: 120)
            .background(Color(.windowBackgroundColor))
            
            // 数据看板模式  
            UnifiedHeatmapView(
                projects: createSampleProjects(),
                config: .dashboard
            )
            .frame(width: 800, height: 200)
            .background(Color(.controlBackgroundColor))
        }
        .padding()
    }
    
    static func createSampleProjects() -> [ProjectData] {
        // 示例数据生成逻辑
        return []
    }
}
#endif