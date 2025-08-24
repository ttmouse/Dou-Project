import Foundation
import SwiftUI
import Combine

/// Dashboard 视图模型 - 遵循 MVVM 架构
@MainActor
final class DashboardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var dailyActivities: [DailyActivity] = []
    @Published var heatmapStats: Dashboard.HeatmapStats = Dashboard.HeatmapStats(
        totalDays: 0, activeDays: 0, totalCommits: 0, 
        maxCommitsInDay: 0, averageCommitsPerDay: 0, activityRate: 0
    )
    @Published var mostActiveProjects: [ProjectData] = []
    @Published var heatmapConfig: Dashboard.HeatmapConfig = .default
    @Published var isLoading: Bool = false
    @Published var error: DashboardError?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let projects: [ProjectData]
    
    // MARK: - Initialization
    
    init(projects: [ProjectData] = []) {
        self.projects = projects
        loadDashboardData()
    }
    
    // MARK: - Public Methods
    
    /// 刷新仪表盘数据
    func refreshData(with newProjects: [ProjectData]) {
        Task {
            await loadDashboardData(projects: newProjects)
        }
    }
    
    /// 更新热力图配置
    func updateHeatmapConfig(_ newConfig: Dashboard.HeatmapConfig) {
        heatmapConfig = newConfig
        generateHeatmapData()
    }
    
    /// 获取指定日期的活动详情
    func getActivityDetails(for date: Date) -> DailyActivity? {
        return dailyActivities.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
    
    /// 获取项目活跃度分数
    func getActivityScore(for project: ProjectData) -> Double {
        return DashboardLogic.calculateActivityScore(project)
    }
    
    // MARK: - Public Methods
    
    func loadDashboardData(projects: [ProjectData]? = nil) {
        let projectsToUse = projects ?? self.projects
        
        Task {
            isLoading = true
            error = nil
            
            do {
                try await generateDashboardData(from: projectsToUse)
            } catch {
                self.error = DashboardError.dataLoadingFailed(error.localizedDescription)
            }
            
            isLoading = false
        }
    }
    
    private func generateDashboardData(from projects: [ProjectData]) async throws {
        // 在后台队列执行计算密集型任务
        let result = await withTaskGroup(of: DashboardDataResult.self) { group in
            // 并行计算不同的数据
            group.addTask {
                let activities = await DashboardLogic.generateDailyActivities(
                    from: projects, 
                    days: await self.heatmapConfig.daysToShow
                )
                return .activities(activities)
            }
            
            group.addTask {
                let activeProjects = DashboardLogic.getMostActiveProjects(
                    from: projects,
                    limit: 10
                )
                return .activeProjects(activeProjects)
            }
            
            var activities: [DailyActivity] = []
            var activeProjects: [ProjectData] = []
            
            for await result in group {
                switch result {
                case .activities(let data):
                    activities = data
                case .activeProjects(let data):
                    activeProjects = data
                }
            }
            
            return (activities, activeProjects)
        }
        
        // 更新主线程上的 UI 状态
        await MainActor.run {
            self.dailyActivities = result.0
            self.mostActiveProjects = result.1
            self.heatmapStats = DashboardLogic.calculateHeatmapStats(from: result.0)
        }
    }
    
    private func generateHeatmapData() {
        Task {
            let activities = DashboardLogic.generateDailyActivities(
                from: self.projects,
                days: heatmapConfig.daysToShow
            )
            
            await MainActor.run {
                self.dailyActivities = activities
                self.heatmapStats = DashboardLogic.calculateHeatmapStats(from: activities)
            }
        }
    }
}

// MARK: - Supporting Types

enum DashboardError: Error, LocalizedError {
    case dataLoadingFailed(String)
    case invalidConfiguration
    case noGitData
    
    var errorDescription: String? {
        switch self {
        case .dataLoadingFailed(let message):
            return "数据加载失败: \(message)"
        case .invalidConfiguration:
            return "配置无效"
        case .noGitData:
            return "没有找到 Git 数据"
        }
    }
}

private enum DashboardDataResult {
    case activities([DailyActivity])
    case activeProjects([ProjectData])
}

// MARK: - Dashboard State Extensions

extension DashboardViewModel {
    
    /// 是否有足够的数据显示图表
    var hasEnoughData: Bool {
        return !dailyActivities.isEmpty && dailyActivities.contains { $0.commitCount > 0 }
    }
    
    /// 最近活跃的天数
    var recentActiveDays: Int {
        let calendar = Calendar.current
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        return dailyActivities
            .filter { $0.date >= lastWeek && $0.commitCount > 0 }
            .count
    }
    
    /// 当前连续活跃天数
    var currentStreak: Int {
        let calendar = Calendar.current
        let today = Date()
        var streak = 0
        
        // 从今天开始向前计算连续天数
        for i in 0..<dailyActivities.count {
            guard let checkDate = calendar.date(byAdding: .day, value: -i, to: today) else { break }
            
            let activity = dailyActivities.first { calendar.isDate($0.date, inSameDayAs: checkDate) }
            
            if let activity = activity, activity.commitCount > 0 {
                streak += 1
            } else {
                break
            }
        }
        
        return streak
    }
    
    /// 最长连续活跃天数
    var longestStreak: Int {
        var maxStreak = 0
        var currentStreakCount = 0
        let sortedActivities = dailyActivities.sorted { $0.date < $1.date }
        
        for i in 0..<sortedActivities.count {
            if sortedActivities[i].commitCount > 0 {
                currentStreakCount += 1
                maxStreak = max(maxStreak, currentStreakCount)
            } else {
                currentStreakCount = 0
            }
        }
        
        return maxStreak
    }
}

// MARK: - Convenience Initializers

extension DashboardViewModel {
    
    /// 为预览创建示例数据
    static func preview() -> DashboardViewModel {
        let sampleProjects = createSampleProjects()
        return DashboardViewModel(projects: sampleProjects)
    }
    
    private static func createSampleProjects() -> [ProjectData] {
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