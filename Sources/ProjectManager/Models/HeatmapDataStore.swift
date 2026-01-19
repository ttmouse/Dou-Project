import Foundation
import SwiftUI

/// 热力图数据存储 - 单例模式，持久化缓存，低频更新
class HeatmapDataStore: ObservableObject {
    
    // MARK: - 单例
    static let shared = HeatmapDataStore()
    
    // MARK: - 缓存数据结构
    
    struct DailyActivity: Codable, Identifiable {
        var id: String { dateString }
        let dateString: String      // "yyyy-MM-dd" 格式
        let commitCount: Int
        let projectIds: [String]    // UUID 字符串数组
        
        var date: Date {
            Self.dateFormatter.date(from: dateString) ?? Date()
        }
        
        static let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()
    }
    
    struct HeatmapCache: Codable {
        var version: Int = 1
        var lastUpdated: Date
        var dailyActivity: [String: DailyActivity]  // dateString -> activity
        var projectCount: Int                        // 用于检测项目数量变化
        
        static var empty: HeatmapCache {
            HeatmapCache(
                lastUpdated: .distantPast,
                dailyActivity: [:],
                projectCount: 0
            )
        }
    }
    
    // MARK: - 属性
    
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdateTime: Date = .distantPast
    
    private var cache: HeatmapCache = .empty
    private let cacheFileName = "heatmap_cache.json"
    private let updateInterval: TimeInterval = 30 * 60  // 30分钟
    private var isUpdating = false
    
    private var cacheFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("ProjectManager")
        return appFolder.appendingPathComponent(cacheFileName)
    }
    
    // MARK: - 初始化
    
    private init() {
        loadCache()
    }
    
    // MARK: - 公开接口
    
    /// 获取热力图数据（同步，直接返回缓存）
    func getHeatmapData(days: Int = 365) -> [HeatmapLogic.HeatmapData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var result: [HeatmapLogic.HeatmapData] = []
        
        for dayOffset in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateString = DailyActivity.dateFormatter.string(from: date)
            
            if let activity = cache.dailyActivity[dateString] {
                result.append(HeatmapLogic.HeatmapData(
                    date: date,
                    commitCount: activity.commitCount,
                    projects: []  // 简化：不返回完整项目数据
                ))
            } else {
                result.append(HeatmapLogic.HeatmapData(
                    date: date,
                    commitCount: 0,
                    projects: []
                ))
            }
        }
        
        return result
    }
    
    /// 获取指定日期的项目ID列表
    func getProjectIds(for date: Date) -> [UUID] {
        let dateString = DailyActivity.dateFormatter.string(from: date)
        guard let activity = cache.dailyActivity[dateString] else { return [] }
        return activity.projectIds.compactMap { UUID(uuidString: $0) }
    }
    
    /// 检查是否需要更新
    func needsUpdate(projectCount: Int) -> Bool {
        let timeSinceUpdate = Date().timeIntervalSince(cache.lastUpdated)
        let projectCountChanged = cache.projectCount != projectCount
        return timeSinceUpdate > updateInterval || projectCountChanged
    }
    
    /// 后台刷新（异步，不阻塞UI）
    func refreshIfNeeded(projects: [ProjectData], force: Bool = false) {
        let projectCount = projects.count
        
        guard force || needsUpdate(projectCount: projectCount) else {
            return
        }
        
        guard !isUpdating else { return }
        isUpdating = true
        
        Task {
            await performUpdate(projects: projects)
            
            await MainActor.run {
                self.isUpdating = false
                self.lastUpdateTime = Date()
                self.objectWillChange.send()
            }
        }
    }
    
    /// 强制全量刷新
    func forceRefresh(projects: [ProjectData]) {
        refreshIfNeeded(projects: projects, force: true)
    }
    
    // MARK: - 私有方法
    
    private func loadCache() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: cacheFileURL)
            cache = try JSONDecoder().decode(HeatmapCache.self, from: data)
            lastUpdateTime = cache.lastUpdated
        } catch {
            print("⚠️ 加载热力图缓存失败: \(error)")
            cache = .empty
        }
    }
    
    private func saveCache() {
        do {
            let folder = cacheFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(cache)
            try data.write(to: cacheFileURL)
        } catch {
            print("⚠️ 保存热力图缓存失败: \(error)")
        }
    }
    
    private func performUpdate(projects: [ProjectData]) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateFormatter = DailyActivity.dateFormatter
        
        // 收集所有项目的 git_daily 数据
        var dailyMap: [String: (commits: Int, projectIds: Set<String>)] = [:]
        var projectsWithGitDaily = 0
        
        for project in projects {
            guard let gitDaily = project.git_daily, !gitDaily.isEmpty else { continue }
            projectsWithGitDaily += 1
            
            let dailyData = GitDailyCollector.parseGitDaily(gitDaily)
            for (dateString, commitCount) in dailyData {
                if dailyMap[dateString] == nil {
                    dailyMap[dateString] = (commits: 0, projectIds: [])
                }
                dailyMap[dateString]!.commits += commitCount
                dailyMap[dateString]!.projectIds.insert(project.id.uuidString)
            }
        }
        
        print("📊 HeatmapDataStore: 处理 \(projects.count) 个项目，\(projectsWithGitDaily) 个有git_daily数据，\(dailyMap.count) 个不同日期")
        
        // 转换为 DailyActivity
        var newDailyActivity: [String: DailyActivity] = [:]
        
        // 生成365天的数据（包括无提交的日期）
        for dayOffset in 0..<365 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateString = dateFormatter.string(from: date)
            
            if let data = dailyMap[dateString] {
                newDailyActivity[dateString] = DailyActivity(
                    dateString: dateString,
                    commitCount: data.commits,
                    projectIds: Array(data.projectIds)
                )
            }
        }
        
        // 更新缓存
        await MainActor.run {
            self.cache = HeatmapCache(
                lastUpdated: Date(),
                dailyActivity: newDailyActivity,
                projectCount: projects.count
            )
            self.saveCache()
        }
    }
}

// MARK: - 通知扩展

extension Notification.Name {
    static let heatmapDataUpdated = Notification.Name("heatmapDataUpdated")
}
